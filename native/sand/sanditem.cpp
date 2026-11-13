#include "sanditem.h"
#include <rhi/qrhi.h>
#include <QFile>
#include <QtMath>
#include <random>
#include <vector>
#include <QDebug>

// the tank, in sim px (the notch's 150 x 40 at 12 per screen px) - the numbers of sandwind.py / sandpbd.py
namespace {
constexpr float S = 12.0f, W = 150 * S, H = 40 * S, D = 26.0f;
constexpr float GRAIN = 2.0f, R0 = 1.8f * GRAIN, R1 = 3.2f * GRAIN;
// the bed 1.5x the film's: the larger grains settle lower, and at 14 S the bed lay ~8 px deep against the film's 11-14
constexpr float BED = 14 * S * 1.5f, SINK0 = BED + 50, CORNER = 17 * S, CELL = 2 * R1 + 0.2f;
constexpr int CAP = 12, KSUB = 8, SUBS = 6, ITERS = 2, TRK = 60, MAXVENTS = 512;
constexpr float TS = 2.0f, DTS = TS / 60.0f / SUBS, G = 3200.0f;
const int GX = int(std::ceil(W / CELL)), GY = int(std::ceil((H + SINK0 + 60) / CELL)), GZ = int(std::ceil(D / CELL));
const int NCOL = int(W / 6) + 1;
// the voice's drives (sandpbd.py's defaults: the film's, with more volume - PUFF, LIFTL - and the calm restored)
constexpr float PUFF = 6800, HPUFF = 1500, LIFTL = 2.5f, ELL = 18, CDEP = 220, THROB = 3, VLIFE = 0.25f;
constexpr float VRATE = 220, HRATE = 100, TAU0 = 0.28f, LAMB = 1.0f, NU = 400, EREST = 0.48f;
constexpr float TAPA = 5, TAPP = 0.06f, SWAY = 1.2f, SPREAD = 3.0f, TRAIL = 2.5f;

float smoothstep(float a, float b, float x) { float u = std::clamp((x - a) / (b - a), 0.0f, 1.0f); return u * u * (3 - 2 * u); }
// the bed rises from under the floor as listening starts (sandwind.py sink_at; no sinking at the end)
float sinkAt(float x)
{
    const float a = x - 0.25f, rise = smoothstep(0.0f, 0.5f, a);
    const float swell = 4.0f * std::sin(float(M_PI) * std::clamp((a - 0.38f) / 0.4f, 0.0f, 1.0f));
    return SINK0 * (1 - rise) - swell;
}

struct Sim {   // the shaders' uniform block (std140, scalars only: packed)
    qint32 n, gx, gy, gz, cap, ncol, nvent, ksub, trkN, trkHead, pad0, pad1;
    float W, H, D, CELL, CORNER, dt, g, t, tv, tau0, lam, nu, VLIFE, PUFF, HPUFF, LIFTL, ELL, CDEP, THROB, gscale,
          muS, muK, relax, sink, low, sway, mid, level, shake, TAPA, TAPP, e, eFloor, vrest, spread, trail;
};
struct Draw { float mvp[16]; float W, H, D, px; };
struct Vent { float x, t0, sigma, strength; };

QShader loadShader(const QString &name)
{
    QFile f(QStringLiteral(":/sand/shaders/") + name + QStringLiteral(".qsb"));
    if (!f.open(QIODevice::ReadOnly)) { qWarning("Sand: no shader %s", qPrintable(name)); return {}; }
    return QShader::fromSerialized(f.readAll());
}
} // namespace

class SandRenderer : public QQuickRhiItemRenderer
{
public:
    void initialize(QRhiCommandBuffer *cb) override;
    void synchronize(QQuickRhiItem *item) override;
    void render(QRhiCommandBuffer *cb) override;

private:
    void seed(QRhiResourceUpdateBatch *u);
    void voiceStep();
    QRhiBuffer *storage(qsizetype bytes) { auto *b = m_rhi->newBuffer(QRhiBuffer::Static, QRhiBuffer::StorageBuffer, bytes); b->create(); m_own.emplace_back(b); return b; }

    QRhi *m_rhi = nullptr;
    std::vector<std::unique_ptr<QRhiResource>> m_own;
    QRhiBuffer *m_ubuf = nullptr, *m_drawUbuf = nullptr, *m_quad = nullptr;
    QRhiBuffer *m_pos, *m_posOut, *m_vel, *m_velOut, *m_prev, *m_vpre, *m_rest, *m_spin, *m_ori, *m_cnt, *m_idx, *m_surf, *m_vents, *m_trkBuf, *m_inst;
    QRhiShaderResourceBindings *m_srb = nullptr, *m_drawSrb = nullptr;
    QHash<QString, QRhiComputePipeline *> m_cp;
    // the passes, looked up once (by name on every dispatch it was 85 string lookups a frame)
    QRhiComputePipeline *m_clear = nullptr, *m_insert = nullptr, *m_surfclear = nullptr, *m_surffill = nullptr, *m_copy = nullptr,
                        *m_stabilize = nullptr, *m_predict = nullptr, *m_solve = nullptr, *m_velPass = nullptr, *m_finish = nullptr, *m_pack = nullptr;
    const bool m_debug = qEnvironmentVariableIsSet("SAND_DEBUG");
    QRhiGraphicsPipeline *m_gp = nullptr;
    quint32 m_align = 0;
    bool m_ok = false, m_needSeed = true, m_quadUp = false;

    std::vector<float> m_pos0, m_col;   // the bed as it starts, and the drawn grains' colours
    int m_n = 0;

    // the voice, as of the last synchronize
    float m_low = 0, m_mid = 0, m_high = 0;
    float m_puff = PUFF, m_lift = LIFTL, m_ventRate = VRATE, m_ventWidth = 1.0f, m_hiss = HPUFF, m_shake = 3.0f;
    bool m_active = false, m_wasActive = false;
    float m_tv = 0;                 // video seconds since this listening began
    // The sand's time against the clock's: a step of 1/60 s once that much has passed, at most one a frame, so a 120
    // or 144 Hz screen runs it at the speed it was tuned at (it ran a step per frame, two or more times too fast).
    QElapsedTimer m_wall;
    qint64 m_wallAt = 0;            // ns on m_wall at the last frame
    float m_due = 1.0f / 60.0f;     // seconds not yet run; the first frame of a listening steps at once
    float m_endAt = -1;             // when it stopped (m_tv), or -1
    bool m_settledSent = false;
    // smoothed bands (sandwind.py: low 0.08 s, mid 0.03 s, high 0.02 s), the low band's last second, the vents
    float m_lows = 0, m_mids = 0, m_highs = 0, m_midPrev = 0, m_lastOnset = -1;
    std::vector<float> m_trk = std::vector<float>(TRK, 0.0f);
    int m_trkHead = 0;
    std::vector<Vent> m_ventList;
    std::mt19937 m_rng { 20261015 };
    float m_gpuMs = 0;
    SandItem *m_item = nullptr;
};

QQuickRhiItemRenderer *SandItem::createRenderer() { return new SandRenderer; }

SandItem::SandItem()
{
    m_clock.start();
    // new voice values reach the renderer at its next synchronize, which only an update() from this side brings
    connect(this, &SandItem::voiceChanged, this, &QQuickItem::update);
    connect(this, &SandItem::tuneChanged, this, &QQuickItem::update);
}

void SandItem::setActive(bool a)
{
    if (a == m_active)
        return;
    m_active = a;
    m_activeChangedAt = m_clock.elapsed();
    emit activeChanged();
    update();
}

void SandRenderer::synchronize(QQuickRhiItem *rhiItem)
{
    auto *item = static_cast<SandItem *>(rhiItem);
    m_item = item;
    m_low = float(item->m_low); m_mid = float(item->m_mid); m_high = float(item->m_high);
    m_puff = float(item->m_puff); m_lift = float(item->m_lift); m_ventRate = float(item->m_ventRate);
    m_ventWidth = float(item->m_ventWidth); m_hiss = float(item->m_hiss); m_shake = float(item->m_shake);
    m_active = item->m_active;
    if (item->m_gpuMs != m_gpuMs) { item->m_gpuMs = m_gpuMs; QMetaObject::invokeMethod(item, [item] { emit item->gpuMsChanged(); }, Qt::QueuedConnection); }
    if (m_endAt >= 0 && !m_settledSent && m_tv > m_endAt + 1.0f) {
        m_settledSent = true;
        QMetaObject::invokeMethod(item, [item] { emit item->settled(); }, Qt::QueuedConnection);
    }
}

void SandRenderer::initialize(QRhiCommandBuffer *)
{
    if (m_rhi == rhi())
        return;
    QElapsedTimer built; built.start();
    struct Report { QElapsedTimer &t; ~Report() { if (qEnvironmentVariableIsSet("SAND_DEBUG")) qDebug("SANDDBG built in %lld ms", t.elapsed()); } } report { built };
    m_rhi = rhi();
    m_own.clear(); m_cp.clear();
    if (!m_rhi->isFeatureSupported(QRhi::Compute)) {
        qWarning("Sand: this graphics backend has no compute");
        return;
    }
    // the bed, packed in layers under the floor, a dune-like top, nothing inside the rounded corners (init_grains)
    std::mt19937 rng(20261014);
    std::uniform_real_distribution<float> u01(0.0f, 1.0f);
    auto top = [](float x) { return H - 2 + SINK0 - BED * (0.8f + 0.18f * std::sin(2 * float(M_PI) * x / W * 1.35f + 0.6f) + 0.07f * std::sin(2 * float(M_PI) * x / W * 3.1f)); };
    const float step = 2 * R1 * 0.98f;
    std::vector<float> zlay;
    for (float z = R1; z <= D - R1 + 0.01f; z += step * 0.9f) zlay.push_back(z);
    m_pos0.clear();
    int row = 0;
    for (float y = H - 2 + SINK0 - R1; y > H - 2 + SINK0 - BED * 1.1f; y -= step * 0.87f, row++) {
        for (size_t zi = 0; zi < zlay.size(); zi++) {
            for (float x = R1 + ((row + int(zi)) % 2) * R1; x < W - R1; x += step) {
                if (y < top(x)) continue;
                const float r = R0 + (R1 - R0) * u01(rng), cy = H - CORNER + SINK0;
                bool ok = true;
                if (y > cy && (x < CORNER || x > W - CORNER)) {
                    const float cxx = x < CORNER ? CORNER : W - CORNER;
                    ok = std::hypot(x - cxx, y - cy) < CORNER - 2 - r - 0.5f;
                }
                if (ok) m_pos0.insert(m_pos0.end(), { x + (u01(rng) - 0.5f) * 0.6f, y, zlay[zi] + (u01(rng) - 0.5f) * 0.6f, r });
            }
        }
    }
    m_n = int(m_pos0.size() / 4);
    // the drawn grains' colours: the film's palette (hex, share, glint)
    struct Pal { const char *hex; float share, glint; };
    const Pal pal[] = { { "#c9ac88", 0.28f, 0.25f }, { "#b3926e", 0.2f, 0.2f }, { "#dccab0", 0.15f, 0.5f }, { "#8f765e", 0.12f, 0.1f },
                        { "#ece4d8", 0.08f, 1.0f }, { "#5e5047", 0.07f, 0.05f }, { "#a87f5a", 0.1f, 0.15f } };
    auto lin = [](float c) { return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f); };
    std::vector<float> cum; float acc = 0; for (const auto &p : pal) cum.push_back(acc += p.share);
    m_col.assign(size_t(m_n) * KSUB * 4, 0.0f);
    for (int k = 0; k < m_n * KSUB; k++) {
        const float pick = u01(rng) * acc; int c = 0; while (c < 6 && pick > cum[c]) c++;
        const QColor q(pal[c].hex); const float v = 0.88f + 0.22f * u01(rng);
        m_col[k * 4 + 0] = lin(float(q.redF())) * v; m_col[k * 4 + 1] = lin(float(q.greenF())) * v; m_col[k * 4 + 2] = lin(float(q.blueF())) * v;
        m_col[k * 4 + 3] = pal[c].glint * (0.3f + 0.7f * u01(rng));
    }
    const qsizetype n4 = qsizetype(m_n) * 16;
    m_pos = storage(n4); m_posOut = storage(n4); m_vel = storage(n4); m_velOut = storage(n4); m_prev = storage(n4);
    m_vpre = storage(n4); m_rest = storage(qsizetype(m_n) * 4); m_spin = storage(n4); m_ori = storage(n4);
    m_cnt = storage(qsizetype(GX) * GY * GZ * 4); m_idx = storage(qsizetype(GX) * GY * GZ * CAP * 4);
    m_surf = storage((NCOL + 1) * 4); m_vents = storage(MAXVENTS * 16); m_trkBuf = storage(TRK * 4);
    m_inst = m_rhi->newBuffer(QRhiBuffer::Static, QRhiBuffer::UsageFlags(QRhiBuffer::VertexBuffer | QRhiBuffer::StorageBuffer), qsizetype(m_n) * KSUB * 48);
    m_inst->create(); m_own.emplace_back(m_inst);
    m_align = m_rhi->ubufAligned(sizeof(Sim));
    m_ubuf = m_rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, m_align * (SUBS + 1)); m_ubuf->create(); m_own.emplace_back(m_ubuf);
    m_drawUbuf = m_rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, sizeof(Draw)); m_drawUbuf->create(); m_own.emplace_back(m_drawUbuf);
    m_quad = m_rhi->newBuffer(QRhiBuffer::Immutable, QRhiBuffer::VertexBuffer, 12 * sizeof(float)); m_quad->create(); m_own.emplace_back(m_quad);

    using B = QRhiShaderResourceBinding;
    m_srb = m_rhi->newShaderResourceBindings(); m_own.emplace_back(m_srb);
    QRhiBuffer *bufs[] = { m_pos, m_posOut, m_vel, m_velOut, m_prev, m_vpre, m_rest, m_spin, m_ori, m_cnt, m_idx, m_surf, m_vents, m_trkBuf, m_inst };
    QList<QRhiShaderResourceBinding> bl { B::uniformBufferWithDynamicOffset(0, B::ComputeStage, m_ubuf, sizeof(Sim)) };
    for (int b = 0; b < 15; b++) bl.append(B::bufferLoadStore(b + 1, B::ComputeStage, bufs[b]));
    m_srb->setBindings(bl.cbegin(), bl.cend()); m_srb->create();
    for (const char *name : { "clear", "insert", "surfclear", "surffill", "copy", "stabilize", "predict", "solve", "vel", "finish", "pack" }) {
        auto *cp = m_rhi->newComputePipeline();
        cp->setShaderStage({ QRhiShaderStage::Compute, loadShader(QString::fromLatin1(name) + QStringLiteral(".comp")) });
        cp->setShaderResourceBindings(m_srb);
        if (!cp->create()) { qWarning("Sand: compute pipeline %s failed", name); delete cp; return; }
        m_cp.insert(QString::fromLatin1(name), cp); m_own.emplace_back(cp);
    }
    m_clear = m_cp.value(QStringLiteral("clear")); m_insert = m_cp.value(QStringLiteral("insert"));
    m_surfclear = m_cp.value(QStringLiteral("surfclear")); m_surffill = m_cp.value(QStringLiteral("surffill"));
    m_copy = m_cp.value(QStringLiteral("copy")); m_stabilize = m_cp.value(QStringLiteral("stabilize"));
    m_predict = m_cp.value(QStringLiteral("predict")); m_solve = m_cp.value(QStringLiteral("solve"));
    m_velPass = m_cp.value(QStringLiteral("vel")); m_finish = m_cp.value(QStringLiteral("finish")); m_pack = m_cp.value(QStringLiteral("pack"));
    m_drawSrb = m_rhi->newShaderResourceBindings(); m_own.emplace_back(m_drawSrb);
    m_drawSrb->setBindings({ B::uniformBuffer(0, B::VertexStage | B::FragmentStage, m_drawUbuf) }); m_drawSrb->create();
    m_gp = m_rhi->newGraphicsPipeline(); m_own.emplace_back(m_gp);
    m_gp->setShaderStages({ { QRhiShaderStage::Vertex, loadShader(QStringLiteral("grain.vert")) }, { QRhiShaderStage::Fragment, loadShader(QStringLiteral("grain.frag")) } });
    QRhiVertexInputLayout il;
    il.setBindings({ QRhiVertexInputBinding(2 * sizeof(float)), QRhiVertexInputBinding(12 * sizeof(float), QRhiVertexInputBinding::PerInstance) });
    il.setAttributes({ QRhiVertexInputAttribute(0, 0, QRhiVertexInputAttribute::Float2, 0), QRhiVertexInputAttribute(1, 1, QRhiVertexInputAttribute::Float4, 0),
                       QRhiVertexInputAttribute(1, 2, QRhiVertexInputAttribute::Float4, 16), QRhiVertexInputAttribute(1, 3, QRhiVertexInputAttribute::Float4, 32) });
    m_gp->setVertexInputLayout(il);
    m_gp->setShaderResourceBindings(m_drawSrb);
    m_gp->setRenderPassDescriptor(renderTarget()->renderPassDescriptor());
    m_gp->setSampleCount(renderTarget()->sampleCount());
    m_gp->setDepthTest(true); m_gp->setDepthWrite(true); m_gp->setDepthOp(QRhiGraphicsPipeline::Less);
    QRhiGraphicsPipeline::TargetBlend blend;   // premultiplied
    blend.enable = true; blend.srcColor = QRhiGraphicsPipeline::One; blend.dstColor = QRhiGraphicsPipeline::OneMinusSrcAlpha;
    blend.srcAlpha = QRhiGraphicsPipeline::One; blend.dstAlpha = QRhiGraphicsPipeline::OneMinusSrcAlpha;
    m_gp->setTargetBlends({ blend });
    if (!m_gp->create()) { qWarning("Sand: draw pipeline failed"); return; }
    m_ok = true; m_needSeed = true; m_quadUp = false;
}

// the bed back under the floor, everything at rest, the drawn grains' colours in place
void SandRenderer::seed(QRhiResourceUpdateBatch *u)
{
    const qsizetype n4 = qsizetype(m_n) * 16;
    std::vector<float> zero(size_t(m_n) * 4, 0.0f), ori(size_t(m_n) * 4);
    std::mt19937 rng(7); std::normal_distribution<float> nd;
    for (int i = 0; i < m_n; i++) {
        float q[4] = { nd(rng), nd(rng), nd(rng), nd(rng) }, l = std::sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
        for (int k = 0; k < 4; k++) ori[i * 4 + k] = q[k] / l;
    }
    u->uploadStaticBuffer(m_pos, 0, n4, m_pos0.data()); u->uploadStaticBuffer(m_posOut, 0, n4, m_pos0.data()); u->uploadStaticBuffer(m_prev, 0, n4, m_pos0.data());
    for (QRhiBuffer *b : { m_vel, m_velOut, m_vpre, m_spin }) u->uploadStaticBuffer(b, 0, n4, zero.data());
    u->uploadStaticBuffer(m_rest, 0, qsizetype(m_n) * 4, zero.data());
    u->uploadStaticBuffer(m_ori, 0, n4, ori.data());
    std::vector<float> inst(size_t(m_n) * KSUB * 12, 0.0f);
    for (int k = 0; k < m_n * KSUB; k++) { inst[k * 12 + 3] = -1; for (int c = 0; c < 4; c++) inst[k * 12 + 4 + c] = m_col[k * 4 + c]; }
    u->uploadStaticBuffer(m_inst, 0, qsizetype(inst.size()) * 4, inst.data());
    if (!m_quadUp) {
        static const float quad[] = { -1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1 };
        u->uploadStaticBuffer(m_quad, quad); m_quadUp = true;
    }
    std::fill(m_trk.begin(), m_trk.end(), 0.0f);
    m_ventList.clear(); m_lows = m_mids = m_highs = m_midPrev = 0; m_lastOnset = -1; m_tv = 0; m_endAt = -1; m_settledSent = false;
}

// one 60 Hz frame of the voice: smoothing, the low band's history, the vents it opens (sandwind.py, drawn live here)
void SandRenderer::voiceStep()
{
    const float dt = 1.0f / 60.0f;
    const bool on = m_active;
    const float lo = on ? m_low : 0, mi = on ? m_mid : 0, hi = on ? m_high : 0;
    m_lows += (lo - m_lows) * (1 - std::exp(-dt / 0.08f));
    m_mids += (mi - m_mids) * (1 - std::exp(-dt / 0.03f));
    m_highs += (hi - m_highs) * (1 - std::exp(-dt / 0.02f));
    const float hiss = std::pow(std::clamp((m_highs - 0.3f) / 0.7f, 0.0f, 1.0f), 1.5f);   // only real s/t/k
    m_trkHead = (m_trkHead + 1) % TRK; m_trk[m_trkHead] = m_lows;
    std::uniform_real_distribution<float> u01(0.0f, 1.0f);
    auto at = [&](float a, float b) { return a + (b - a) * u01(m_rng); };
    auto spot = [&] { return CORNER * 0.6f + u01(m_rng) * (W - 1.2f * CORNER); };
    const float s = std::min(1.3f, m_mids / 0.6f);
    // vowels: Poisson with the mid band, plus a burst cluster at each syllable onset (a fast rise of the mid band)
    const float rate = m_ventRate * std::pow(std::max(0.0f, m_mids - 0.08f), 1.5f) * dt;
    for (int k = std::poisson_distribution<int>(std::max(1e-6f, rate))(m_rng); k > 0; k--)
        m_ventList.push_back({ spot(), m_tv + at(0, dt), at(18, 50) * m_ventWidth, (0.4f + 0.6f * u01(m_rng)) * s });
    const float rise = (m_mids - m_midPrev) / dt; m_midPrev = m_mids;
    if (rise > 6.0f && s >= 0.25f && m_tv - m_lastOnset > 0.09f) {
        m_lastOnset = m_tv;
        for (int k = std::poisson_distribution<int>(4 * s)(m_rng); k > 0; k--)
            m_ventList.push_back({ spot(), m_tv + at(0, 0.025f), at(18, 50) * m_ventWidth, (0.4f + 0.6f * u01(m_rng)) * s });
    }
    // hiss: narrow quick puffs
    for (int k = std::poisson_distribution<int>(std::max(1e-6f, HRATE * hiss * dt))(m_rng); k > 0; k--)
        m_ventList.push_back({ spot(), m_tv + at(0, dt), at(8, 18), -(0.5f + 0.5f * u01(m_rng)) });
    std::erase_if(m_ventList, [&](const Vent &v) { return m_tv - v.t0 > VLIFE; });
    if (m_ventList.size() > size_t(MAXVENTS)) m_ventList.erase(m_ventList.begin(), m_ventList.end() - MAXVENTS);
}

void SandRenderer::render(QRhiCommandBuffer *cb)
{
    if (!m_ok)
        return;
    QRhiResourceUpdateBatch *u = m_rhi->nextResourceUpdateBatch();
    if (m_active && !m_wasActive && (m_endAt >= 0 || m_needSeed)) m_needSeed = true;    // a new listening: the bed starts again
    if (m_needSeed) { seed(u); m_needSeed = false; }
    if (!m_active && m_wasActive) m_endAt = m_tv;
    m_wasActive = m_active;
    const bool running = m_active || (m_endAt >= 0 && m_tv < m_endAt + 1.2f);
    if (running) {
        if (!m_wall.isValid()) m_wall.start();
        const qint64 now = m_wall.nsecsElapsed();
        // a long gap (the rest between listenings, a slow frame) is not made up afterwards
        m_due = std::min(m_due + float(now - m_wallAt) * 1e-9f, 2.0f / 60.0f);
        m_wallAt = now;
    }
    const bool step = running && m_due >= 1.0f / 60.0f;

    if (step) {
        m_due -= 1.0f / 60.0f;
        voiceStep();
        std::vector<Vent> vents = m_ventList;
        if (!vents.empty()) u->uploadStaticBuffer(m_vents, 0, qsizetype(vents.size()) * 16, vents.data());
        u->uploadStaticBuffer(m_trkBuf, 0, TRK * 4, m_trk.data());
        const float level = m_endAt < 0 ? 0.0f : 0.7f * smoothstep(m_endAt + 0.25f, m_endAt + 0.35f, m_tv) * (1 - smoothstep(m_endAt + 0.7f, m_endAt + 0.85f, m_tv));
        for (int s = 0; s <= SUBS; s++) {
            const float tvs = m_tv + std::min(s, SUBS - 1) * (1.0f / 60.0f / SUBS);
            Sim p {};
            p.n = m_n; p.gx = GX; p.gy = GY; p.gz = GZ; p.cap = CAP; p.ncol = NCOL; p.nvent = int(vents.size()); p.ksub = KSUB;
            p.trkN = TRK; p.trkHead = m_trkHead;
            p.W = W; p.H = H; p.D = D; p.CELL = CELL; p.CORNER = CORNER; p.dt = DTS; p.g = G; p.t = tvs * TS; p.tv = tvs;
            p.tau0 = TAU0; p.lam = LAMB; p.nu = NU; p.VLIFE = VLIFE; p.PUFF = m_puff; p.HPUFF = m_hiss; p.LIFTL = m_lift; p.ELL = ELL;
            p.CDEP = CDEP; p.THROB = THROB; p.gscale = GRAIN; p.muS = 0.6f; p.muK = 0.45f; p.relax = 1.0f;
            p.sink = sinkAt(tvs); p.low = m_lows; p.sway = SWAY * std::sin(2 * float(M_PI) * 0.6f * tvs); p.mid = m_mids; p.level = level;
            p.shake = m_shake; p.TAPA = TAPA; p.TAPP = TAPP; p.e = EREST; p.eFloor = EREST * 0.8f; p.vrest = 2 * G * DTS;
            p.spread = SPREAD; p.trail = TRAIL;
            u->updateDynamicBuffer(m_ubuf, quint32(s) * m_align, sizeof(Sim), &p);
        }
        auto groups = [](int count) { return (count + 127) / 128; };
        cb->beginComputePass(u);
        u = nullptr;
        auto run = [&](QRhiComputePipeline *pass, int count, int s) {
            cb->setComputePipeline(pass);
            const QRhiCommandBuffer::DynamicOffset off(0, quint32(s) * m_align);
            cb->setShaderResources(m_srb, 1, &off);
            cb->dispatch(groups(count), 1, 1);
        };
        const int cells = GX * GY * GZ;
        for (int s = 0; s < SUBS; s++) {
            if (s % 2 == 0) { run(m_surfclear, NCOL + 1, s); run(m_surffill, m_n, s); }
            run(m_clear, cells, s); run(m_insert, m_n, s); run(m_stabilize, m_n, s); run(m_copy, m_n, s);
            run(m_predict, m_n, s);
            run(m_clear, cells, s); run(m_insert, m_n, s);
            for (int it = 0; it < ITERS; it++) { run(m_solve, m_n, s); run(m_copy, m_n, s); }
            run(m_velPass, m_n, s); run(m_finish, m_n, s);
        }
        run(m_pack, m_n * KSUB, SUBS);
        // SAND_DEBUG: once a second, where the grains are (for checks)
        QRhiResourceUpdateBatch *rb = nullptr;
        if (m_debug && int(m_tv * 60) % 60 == 0) {
            rb = m_rhi->nextResourceUpdateBatch();
            auto *res = new QRhiReadbackResult;
            const float tv = m_tv, sk = sinkAt(m_tv), lo = m_lows, mi = m_mids, raw = m_mid;
            const int n = m_n, nv = int(m_ventList.size());
            res->completed = [res, tv, sk, n, lo, mi, raw, nv] {
                const auto *f = reinterpret_cast<const float *>(res->data.constData());
                float ymin = 1e9, ymax = -1e9, sum = 0; int above = 0, nan = 0;
                for (int i = 0; i < n; i++) {
                    const float y = f[i * 4 + 1];
                    if (!(y == y)) { nan++; continue; }
                    ymin = std::min(ymin, y); ymax = std::max(ymax, y); sum += y; if (y < H) above++;
                }
                qDebug("SANDDBG tv %.2f sink %.1f | y min %.1f mean %.1f max %.1f | visible %d/%d nan %d | low %.2f mid %.2f (raw %.2f) vents %d",
                       tv, sk, ymin, sum / std::max(1, n - nan), ymax, above, n, nan, lo, mi, raw, nv);
                delete res;
            };
            rb->readBackBuffer(m_pos, 0, qsizetype(m_n) * 16, res);
            auto *rv = new QRhiReadbackResult;
            auto *posCopy = res;   // positions arrive first; the speeds are read on their own
            Q_UNUSED(posCopy);
            rv->completed = [rv, n, tv] {
                const auto *f = reinterpret_cast<const float *>(rv->data.constData());
                double s = 0; int c = 0;
                for (int i = 0; i < n; i++) { const float vx = f[i * 4], vy = f[i * 4 + 1]; const float sp = std::sqrt(vx * vx + vy * vy); if (sp < 5000) { s += sp; c++; } }
                qDebug("SANDDBG tv %.2f mean speed %.1f px/s", tv, s / std::max(1, c));
                delete rv;
            };
            rb->readBackBuffer(m_vel, 0, qsizetype(m_n) * 16, rv);
        }
        cb->endComputePass(rb);
        m_tv += 1.0f / 60.0f;
        const double gpu = cb->lastCompletedGpuTime();
        if (gpu > 0) m_gpuMs = float(gpu * 1000.0);
    }

    // draw: the item's rect is the tank, W x H
    if (!u) u = m_rhi->nextResourceUpdateBatch();
    Draw d {};
    const QMatrix4x4 corr = m_rhi->clipSpaceCorrMatrix();
    std::memcpy(d.mvp, corr.constData(), sizeof(d.mvp));
    d.W = W; d.H = H; d.D = D; d.px = W / float(std::max(1, renderTarget()->pixelSize().width()));
    u->updateDynamicBuffer(m_drawUbuf, 0, sizeof(Draw), &d);
    cb->beginPass(renderTarget(), QColor(0, 0, 0, 0), { 1.0f, 0 }, u);
    cb->setGraphicsPipeline(m_gp);
    const QSize sz = renderTarget()->pixelSize();
    cb->setViewport({ 0, 0, float(sz.width()), float(sz.height()) });
    cb->setShaderResources();
    const QRhiCommandBuffer::VertexInput vin[] = { { m_quad, 0 }, { m_inst, 0 } };
    cb->setVertexInput(0, 2, vin);
    cb->draw(6, quint32(m_n * KSUB));
    cb->endPass();
    if (running)
        update();   // another frame while the sand moves
}

static_assert(sizeof(Sim) == 48 * 4, "Sim must match the shaders' uniform block");
