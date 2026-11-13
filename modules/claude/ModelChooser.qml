import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.tacit

/**
 * The model menu's content: a filter that always has the keyboard, the agent's models (recent
 * ones first once there are two, long lists five or six to a group with the rest a line away), the
 * effort levels of the highlighted model and the line that keeps the choice for the folder. Used by
 * the message box and the preferences sheet. Keys: typing filters, ↑↓ Tab PgUp PgDn, ←→ effort
 * (empty filter), Enter uses the line, Ctrl+Enter also keeps it for the folder, Ctrl+, opens
 * Preferences, Esc clears the filter, then closes. ↓ past the last model reaches the account's
 * step line (Enter runs it), which Enter also runs when there is no model to use. The highlight stays on the last model the pointer or a key reached, so the
 * effort words and the keep line always act on the model that is lit.
 *
 * With a host that reads no model lists (no "catalog" feature): Claude Code's four model names
 * and a typed name, nothing else.
 */
FocusScope {
    id: mc
    property var model: null           // AccountsModel
    property bool catalogs: true       // the host reads model lists
    property string agent: "claude"
    property string account: ""
    property string cwd: ""
    property string current: ""        // the model id in use; "" or "default" is the agent's default
    property string effort: ""         // the level in use; "" is the model's default
    property string wish: ""           // the level last asked for, for models that offer it again
    property bool autoOk: true         // "Auto" can be chosen: no running session reports a level
    property bool canStep: false       // the menu can send you to the account's next step
    property var recent: []            // the newest models picked for this agent
    property string keepFolder: ""
    property bool showKeep: true
    property real maxHeight: 420
    property color ground: Appearance.m3colors.m3surfaceContainerLow
    signal chosen(string model, string effort, bool keep)
    signal effortPicked(string level)  // a level for the current model, the menu staying open
    signal closed()
    signal allDefaults()
    signal stepRequested()
    property bool ready: false
    Component.onCompleted: { mc.ready = true; if (mc.catKey) mc.model.catalog(mc.agent, mc.account, mc.cwd); }
    // another agent or account: the list, the highlight and the level start over
    onAgentChanged: if (mc.ready) mc.reset()
    onAccountChanged: if (mc.ready) mc.reset()
    onEffortChanged: if (mc.ready) mc.level = mc.effort

    readonly property var words: ({ low: "low", medium: "medium", high: "high", xhigh: "extra high", max: "max",
                                    ultra: "ultra", off: "off", none: "none", minimal: "minimal" })
    readonly property var oldList: [
        { id: "", label: "Default", efforts: [] },
        { id: "opus", label: "Opus", efforts: [] },
        { id: "sonnet", label: "Sonnet", efforts: [] },
        { id: "haiku", label: "Haiku", efforts: [] }
    ]
    // the copy AccountsModel holds; asked for outside the binding (asking writes the request tag)
    readonly property string catKey: mc.catalogs && mc.model?.available ? mc.model.catalogKey(mc.agent, mc.account || (mc.model.defaultAccount(mc.agent)?.id ?? ""), mc.cwd) : ""
    readonly property var cat: mc.catKey ? mc.model.catalogs[mc.catKey] ?? null : null
    onCatKeyChanged: { mc.gaveUp = false; if (mc.catKey) Qt.callLater(() => mc.model.catalog(mc.agent, mc.account, mc.cwd)); }
    // The host refreshes a stale list in the background and says nothing when that fails, so "Checking" is
    // shown for a while only; then the footer says the saved list is all there is
    readonly property bool stale: mc.catalogs && (mc.cat?.stale ?? false)
    property bool gaveUp: false
    onStaleChanged: if (!mc.stale) mc.gaveUp = false
    Timer { interval: 30000; running: mc.stale && !mc.gaveUp; onTriggered: mc.gaveUp = true }
    readonly property var models: mc.catalogs ? (mc.model?.shapeModels?.(mc.cat?.models ?? []) ?? []) : mc.oldList
    readonly property bool multi: mc.agent === "pi" || mc.agent === "opencode"   // one group per provider
    readonly property string accountWord: {
        const l = mc.model?.accountsOf(mc.agent) ?? [];
        if (l.length < 2) return "";
        const a = mc.model.account(mc.account) ?? mc.model.defaultAccount(mc.agent);
        return a ? `${mc.model.agentName(mc.agent)}, ${a.label}` : "";
    }

    // the row in use: its id, else the row that resolves to it (a session reports the full
    // model, the list offers "sonnet"), else the default row for "" and "default"; a model the
    // list does not offer (an older session, a retired id) gets a row of its own
    readonly property var foundModel: mc.catalogs ? mc.model?.modelRowOf?.(mc.models, mc.current) ?? null : mc.models.find(m => m.id === mc.current) ?? null
    readonly property var missing: {
        if (!mc.catalogs || !mc.models.length || mc.foundModel || !mc.current || mc.current === "default") return null;
        return { id: mc.current, label: mc.model.plainId(mc.current), detail: "Not offered here", efforts: [], group: "", missing: true };
    }
    readonly property var currentModel: mc.foundModel ?? mc.missing
    // by id: a list read back from a property is a copy, not the same objects
    function isCurrent(m) { return !!m && !!mc.currentModel && m.id === mc.currentModel.id; }
    // every word of the filter must start a word of the label (best), sit inside it, or sit in the
    // id or group name; the label alone ranks, so a model never matches through its maker's letters
    function score(m, q) {
        const label = m.label.toLowerCase();
        const starts = label.split(/[\s\-_/.:~]+/);
        const other = `${m.id} ${m.group ?? ""} ${m.rec ? "recommended default" : ""}`.toLowerCase();
        let s = 0;
        for (const t of q.split(/\s+/).filter(x => x.length)) {
            if (label.startsWith(t)) s += 100;
            else if (starts.some(w => w.startsWith(t))) s += 80;
            else if (label.includes(t)) s += 50;
            else if (other.includes(t)) s += 20;
            else return -1;
        }
        return s;
    }
    // what a row says at its right
    function detailOf(m) { return m.rec ? "Recommended" : (m.detail ?? ""); }

    property string filter: ""
    property var opened: ({})          // groups shown whole
    // models a long list shows before "more": Claude's older ones start after the fifth
    readonly property int cut: mc.agent === "claude" ? 5 : 6
    // kind: model | typed | more | less | label | rule | note
    readonly property var rows: {
        const out = [];
        const ms = mc.models;
        const raw = mc.filter.trim();
        const q = raw.toLowerCase();
        if (q.length) {
            const hits = [];
            for (const m of ms) {
                const s = mc.score(m, q);
                if (s >= 0) hits.push({ m: m, s: s, i: hits.length });
            }
            hits.sort((a, b) => b.s - a.s || a.i - b.i);
            for (const h of hits.slice(0, 200)) out.push({ kind: "model", m: h.m, group: mc.multi ? h.m.group ?? "" : "" });
            if (!hits.length && ms.length) out.push({ kind: "note", text: `No model called ${raw}` });
            if (mc.agent !== "codex" && !ms.some(m => m.id === raw)) out.push({ kind: "typed", text: raw });
            return out;
        }
        if (!mc.catalogs) {
            for (const m of ms) out.push({ kind: "model", m: m });
            return out;
        }
        if (mc.missing) out.push({ kind: "model", m: mc.missing });
        // the models picked lately, once there are two to choose between
        const seen = {}, rec = [];
        for (const id of mc.recent) {
            const m = id && id !== "default" ? mc.model.modelRowOf(ms, id) : null;
            if (m && !m.plainDefault && !seen[m.id]) { seen[m.id] = true; rec.push(m); }
        }
        const recent = rec.length >= 2 ? rec.slice(0, 3) : [];
        if (recent.length) {
            out.push({ kind: "label", text: "Recent" });
            for (const m of recent) out.push({ kind: "model", m: m });
            out.push({ kind: "rule" });
        }
        const groups = [], by = {};
        for (const m of ms) {
            if (recent.some(r => r.id === m.id)) continue;
            const g = m.group ?? "";
            if (!by[g]) { by[g] = []; groups.push(g); }
            by[g].push(m);
        }
        groups.forEach((g, gi) => {
            if (g !== "" && (mc.multi || gi > 0)) out.push({ kind: "label", text: g });
            const list = by[g];
            const whole = mc.opened[g] || list.length <= mc.cut + 1;
            for (const m of (whole ? list : list.slice(0, mc.cut))) out.push({ kind: "model", m: m });
            const n = list.length - mc.cut;
            if (!whole) out.push({ kind: "more", group: g, n: n,
                                   text: mc.agent === "claude" ? `Older models (${n})` : mc.multi ? `More from ${g} (${n})` : `More models (${n})`,
                                   hint: n > 30 ? "or type to search" : "" });
            else if (list.length > mc.cut + 1) out.push({ kind: "less", group: g });
        });
        return out;
    }
    function usable(i) { const k = mc.rows[i]?.kind; return k === "model" || k === "typed" || k === "more" || k === "less"; }
    function rowH(r) { return r.kind === "label" ? 26 : r.kind === "rule" ? 9 : 34; }
    property int pick: -1
    // the key highlight is on the account's step line, below the list
    property bool onStep: false
    readonly property bool stepPicked: mc.onStep && mc.stepRow
    // the highlight is drawn once a key or the pointer has moved it; before that it only marks where Enter lands
    property bool touched: false
    // the current model's line, or the best match while filtering; with no current model, none
    function firstPick() {
        if (mc.filter.trim().length) {
            for (let j = 0; j < mc.rows.length; j++) if (mc.usable(j)) return j;
            return -1;
        }
        return mc.rows.findIndex(r => r.kind === "model" && mc.isCurrent(r.m));
    }
    // the model the effort and keep lines are for: the highlighted one, else the current one;
    // none while a filter has found nothing, or the highlight is on the typed name
    readonly property var lit: {
        const r = mc.rows[mc.pick];
        if (r?.kind === "model") return r.m;
        if (mc.filter.trim().length || r?.kind === "typed") return null;
        return mc.currentModel;
    }
    // the levels a model offers; "" is Auto (the agent decides) where the model names no level of its own
    function levelsOf(m) {
        const l = mc.catalogs ? m?.efforts ?? [] : [];
        if (!l.length) return [];
        const own = m.defaultEffort && l.includes(m.defaultEffort);
        return mc.autoOk && !own ? [""].concat(l) : l;
    }
    readonly property var levels: mc.levelsOf(mc.lit)
    property string level: ""
    // the level a model gets: the chosen one when it offers it, else (for another model than the
    // one in use) the level last asked for, else its own default ("" when the catalog names none:
    // the agent decides)
    function levelFor(m) {
        const l = m?.efforts ?? [];
        if (mc.level !== "" && l.includes(mc.level)) return mc.level;
        if (mc.level === "" && mc.wish && !mc.isCurrent(m) && l.includes(mc.wish)) return mc.wish;
        return m?.defaultEffort && l.includes(m.defaultEffort) ? m.defaultEffort : "";
    }
    readonly property string litLevel: mc.levelFor(mc.lit)
    // no level chosen: the model's own; "Default", so it is not taken for the box's Auto mode
    function wordText(l) { return l === "" ? "Default" : mc.words[l] ?? l; }
    // Every distinct list of levels among the models on show: the effort line keeps the height of
    // the longest while the list stays as it is, so moving the highlight never moves the rows.
    // Each word is as wide as its bold form, so the marked one never rewraps the line.
    readonly property var effortSets: {
        const seen = {}, out = [];
        for (const r of mc.rows.slice(0, 60)) {
            if (r.kind !== "model") continue;
            const l = mc.levelsOf(r.m);
            if (l.length && !seen[l.join(" ")]) { seen[l.join(" ")] = true; out.push(l); }
        }
        return out;
    }
    readonly property real effortLabelW: Math.ceil(note.advanceWidth("Effort")) + 12
    function wordW(l) { return Math.ceil(bold.advanceWidth(mc.wordText(l))) + 16; }
    // the lines a list takes at width w, wrapped as Flow wraps (spacing 0)
    function effortLines(l, w) {
        let x = mc.effortLabelW, n = 1;
        for (const e of l) {
            const ww = mc.wordW(e);
            if (x > 0 && x + ww > w) { n++; x = 0; }
            x += ww;
        }
        return n;
    }
    readonly property int effortRows: Math.max(1, mc.effortSets.reduce((a, l) => Math.max(a, mc.effortLines(l, effortFlow.width)), 0))

    // No models to show: the step the account needs first, else the host's answer to asking again
    property string failed: ""
    readonly property string acctStep: {
        if (!mc.catalogs || !mc.model?.available) return "";
        const s = mc.model.stepOf(mc.agent, mc.account || (mc.model.defaultAccount(mc.agent)?.id ?? ""));
        return s === "signedOut" && mc.multi ? "noProvider" : s;
    }
    readonly property string stepWord: mc.model?.stepWord(mc.acctStep) ?? ""
    readonly property string stepSentence: {
        const n = mc.model?.agentName(mc.agent) ?? mc.agent;
        switch (mc.acctStep) {
        case "signedOut": case "expired": return `Sign in to ${n}`;
        case "noProvider": return `Set up a provider for ${n}`;
        case "notInstalled": case "needsNode": return `Install ${n}`;
        case "noKey": case "keyRefused": return `${n} needs a new key`;
        }
        return "";
    }
    readonly property string need: {
        if (!mc.catalogs || !mc.model?.available || mc.models.length) return "";
        const n = mc.model.agentName(mc.agent);
        if (mc.stepSentence) return mc.stepSentence + " first";
        switch (mc.acctStep) {
        case "installing": return `${n} is being installed`;
        case "locked": return "Unlock the keyring first";
        case "noKeyring": return "The keyring isn't running";
        }
        return mc.cat === null ? mc.failed : `${n} lists no models`;
    }
    // the account's next step as a button, also when models are listed (pi's cached list)
    readonly property bool stepRow: mc.canStep && mc.stepWord !== "" && mc.stepSentence !== ""
    // AccountsModel asks once per connection and keeps no failure, so a list that is missing when
    // the menu opens is asked for again here; the reply is stored as AccountsModel stores its own
    function ask() {
        mc.failed = "";
        if (!mc.catKey || mc.cat !== null || mc.need !== "") return;
        const self = mc, key = mc.catKey;
        const id = mc.account || (mc.model.defaultAccount(mc.agent)?.id ?? "");
        const req = { op: "catalog", agent: mc.agent };
        if (id) req.account = id;
        if (mc.cwd) req.cwd = mc.cwd;
        mc.model.link.request(req, r => {
            if (r.ev === "catalog") self.model.storeCatalog(r, key);
            else if (self.catKey === key) self.failed = r.message || "The model list could not be read";
        });
    }

    function reset() {
        mc.filter = "";
        field.text = "";
        mc.opened = ({});
        mc.touched = false;
        mc.onStep = false;
        mc.level = mc.effort;
        mc.pick = mc.firstPick();
        list.positionViewAtBeginning();
        if (mc.pick >= 0) list.positionViewAtIndex(mc.pick, ListView.Contain);
        field.forceActiveFocus();
        mc.ask();
    }
    // a list that arrives (or changes) while nothing has been moved puts the highlight on the model in use
    onRowsChanged: if (!mc.touched || !mc.usable(mc.pick)) mc.pick = mc.firstPick()
    onCurrentModelChanged: if (mc.ready && !mc.touched && !mc.filter.trim().length) mc.pick = mc.firstPick()
    onPickChanged: {
        if (mc.pick >= 0) list.positionViewAtIndex(mc.pick, ListView.Contain);
        if (mc.tipRow !== mc.pick) mc.tipRow = -1;
    }
    function step(d, by) {
        if (mc.stepPicked) {
            if (d < 0) mc.onStep = false;
            return;
        }
        let i = mc.pick;
        for (let n = 0; n < (by ?? 1); n++) {
            let j = i + d;
            while (j >= 0 && j < mc.rows.length && !mc.usable(j)) j += d;
            if (j < 0 || j >= mc.rows.length) {
                if (d > 0 && mc.stepRow) { mc.onStep = true; mc.touched = true; return; }
                break;
            }
            i = j;
        }
        mc.touched = true;
        mc.pick = i;
    }
    function use(i, keep) {
        const r = mc.rows[i];
        if (mc.stepPicked || (!r && mc.stepRow && !mc.rows.some((x, j) => mc.usable(j)))) { mc.stepRequested(); return; }
        if (!r) return;
        if (r.kind === "more" || r.kind === "less") {
            mc.opened = Object.assign({}, mc.opened, { [r.group]: r.kind === "more" });
            return;
        }
        if (r.kind === "typed") mc.chosen(r.text, "", keep);
        else if (r.kind === "model") mc.chosen(r.m.id, mc.levelFor(r.m), keep);
    }
    // A level for the lit model. On the model in use it applies at once; on another one a key only
    // sets it for Enter, while a click on the word uses that model at that level.
    function setLevel(l, byPointer) {
        mc.level = l;
        const m = mc.lit;
        if (!m) return;
        if (mc.isCurrent(m)) mc.effortPicked(l);
        else if (byPointer) mc.chosen(m.id, mc.levelFor(m), false);
    }
    // the lit model is the folder's start already, at this level: Auto ("") too, so Auto can be kept over a saved
    // level; a model that names no levels is kept at whatever level was saved
    readonly property bool kept: {
        const run = mc.model?.defaults?.folders?.[mc.keepFolder]?.run?.[mc.agent];
        const m = mc.lit;
        if (!run?.model || !m) return false;
        return (run.model === m.id || !!m.aliases?.includes(run.model)) && (!(m.efforts ?? []).length || (run.effort ?? "") === mc.levelFor(m));
    }
    readonly property bool keepShown: mc.showKeep && mc.catalogs && !!mc.model?.available && mc.keepFolder.startsWith("/") && mc.need === "" && !!mc.lit
    readonly property string folderName: mc.keepFolder === Quickshell.env("HOME") ? "Home" : (mc.keepFolder.split("/").filter(s => s.length).pop() ?? "")
    readonly property string keepWords: mc.kept ? `Saved for new sessions in ${mc.folderName}` : `Use for new sessions in ${mc.folderName}`

    // ── width: what the rows on show ask for ─────────────────────────────────
    FontMetrics { id: big; font.family: Appearance.font.family.compact; font.pixelSize: 15 }
    FontMetrics { id: small; font.family: Appearance.font.family.numbers; font.pixelSize: 13 }
    FontMetrics { id: note; font.family: Appearance.font.family.compact; font.pixelSize: 13 }
    FontMetrics { id: link; font.family: Appearance.font.family.compact; font.pixelSize: 13; font.weight: Font.Medium }
    FontMetrics { id: bold; font.family: Appearance.font.family.compact; font.pixelSize: 15; font.weight: Font.DemiBold }
    function w14(t) { return big.advanceWidth(t); }
    function w12(t) { return small.advanceWidth(t); }
    readonly property real want: {
        let w = mc.w14("Find a model") + (mc.accountWord ? 24 + mc.w12(mc.accountWord) : 0) + 20;
        for (const r of mc.rows.slice(0, 60)) {
            if (r.kind === "model") {
                const d = [mc.detailOf(r.m), r.group ?? ""].filter(s => s).join(", ");
                w = Math.max(w, 20 + mc.w14(r.m.label) + (d ? 12 + mc.w12(d) : 0) + 22);
            } else if (r.kind === "typed") w = Math.max(w, 20 + mc.w14(`Use "${r.text}" anyway`));
            else if (r.kind === "more") w = Math.max(w, 20 + mc.w14(r.text) + (r.hint ? 12 + mc.w12(r.hint) : 0));
        }
        // the longest effort line on one line, its words with their gaps
        for (const l of mc.effortSets) w = Math.max(w, 21 + mc.effortLabelW + l.reduce((a, e) => a + mc.wordW(e), 0));
        if (mc.keepShown) w = Math.max(w, 20 + mc.w14(mc.keepWords) + 16 + Math.ceil(link.advanceWidth("Preferences")) + 6);
        if (mc.stepRow) w = Math.max(w, 20 + mc.w14(mc.need || mc.stepSentence) + 16 + Math.ceil(link.advanceWidth(mc.stepWord)) + 16);
        if (!mc.catalogs) w = Math.max(w, 21 + note.advanceWidth("Update the agent helper to see every model"));
        if (mc.need && !mc.stepRow) w = Math.max(w, 21 + Math.min(needText.implicitWidth, 300));
        return Math.ceil(w);
    }
    // the width of the whole list holds while a filter narrows it, so the menu does not jump as you type
    property real heldW: 0
    onWantChanged: if (mc.filter === "") mc.heldW = mc.want
    implicitWidth: Math.max(mc.want, mc.heldW)
    implicitHeight: head.height + list.height + foot.implicitHeight

    // The window's Ctrl+, Shortcut (Preferences) takes the key unless the menu claims it here: from the menu it closes the
    // menu first, else the menu stayed open beside the sheet
    Keys.onShortcutOverride: e => e.accepted = e.key === Qt.Key_Comma && (e.modifiers & Qt.ControlModifier) !== 0 && mc.keepShown
    Keys.onPressed: e => {
        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
        e.accepted = true;
        if (e.key === Qt.Key_Escape) {
            if (field.text.length) field.text = "";
            else mc.closed();
        } else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) mc.step(1);
        else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) mc.step(-1);
        else if (e.key === Qt.Key_PageDown) mc.step(1, 8);
        else if (e.key === Qt.Key_PageUp) mc.step(-1, 8);
        else if ((e.key === Qt.Key_Left || e.key === Qt.Key_Right) && !field.text.length && mc.levels.length) {
            const i = mc.levels.indexOf(mc.litLevel) + (e.key === Qt.Key_Right ? 1 : -1);
            if (i >= 0 && i < mc.levels.length) mc.setLevel(mc.levels[i], false);
        } else if (e.key === Qt.Key_Comma && ctrl && mc.keepShown) mc.allDefaults();
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) mc.use(mc.pick, ctrl);
        else e.accepted = false;
    }

    // the filter: typing here narrows the list and never reaches the message
    Item {
        id: head
        width: parent.width
        height: 38
        TextInput {
            id: field
            anchors { left: parent.left; right: acctText.left; leftMargin: 10; rightMargin: 8; verticalCenter: parent.verticalCenter }
            clip: true
            focus: true
            font.family: Appearance.font.family.compact
            font.pixelSize: 15
            font.hintingPreference: Font.PreferNoHinting
            color: Appearance.colors.colInkMain
            selectionColor: Appearance.colors.colSecondaryContainer
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            onTextChanged: { mc.filter = field.text; mc.onStep = false; mc.pick = mc.firstPick(); }
            Keys.forwardTo: [mc]
        }
        StyledText {
            visible: field.text.length === 0
            anchors { left: field.left; verticalCenter: parent.verticalCenter }
            text: mc.need && mc.agent !== "codex" ? "Type the model name" : "Find a model"
            font.family: Appearance.font.family.compact
            font.pixelSize: 15
            color: Appearance.colors.colInkFaint
        }
        StyledText {
            id: acctText
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: mc.accountWord
            font.family: Appearance.font.family.compact
            font.pixelSize: 13
            color: Appearance.colors.colInkMeta
        }
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: head.bottom }
        readonly property real room: Math.max(90, mc.maxHeight - head.height - foot.implicitHeight)
        // from the rows' kinds: contentHeight is an estimate while rows are off screen
        readonly property real natural: mc.rows.reduce((a, r) => a + mc.rowH(r), 0)
        // a list that needs scrolling stops half-way through a row: the cut row says there is more
        // (no fade over it: a gradient reads as a shadow on the menu's flat ground)
        readonly property real fit: {
            let y = 0, last = 0, next = 0;
            for (const r of mc.rows) {
                const h = mc.rowH(r);
                if (y + h > list.room) { next = h; break; }
                y += h;
                last = y;
            }
            if (last === 0) return list.room;
            return next > 0 && last + next / 2 <= list.room ? last + next / 2 : Math.max(last - 17, 0) + 17;
        }
        height: list.natural <= list.room ? list.natural : list.fit
        clip: true
        interactive: list.natural > list.height + 1
        boundsBehavior: Flickable.StopAtBounds
        model: mc.rows
        GlideWheel { view: list; gain: 1.6; gainPerSpeed: 3; gainMax: 6 }
        onContentYChanged: tipTimer.stop()
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var r: row.modelData
            width: list.width
            height: mc.rowH(row.r)
            StyledText {
                visible: row.r.kind === "label"
                x: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: row.r.text ?? ""
                font.family: Appearance.font.family.compact
                font.pixelSize: 13
                color: Appearance.colors.colInkMeta
            }
            StyledText {
                visible: row.r.kind === "note"
                x: 10
                y: (34 - height) / 2
                width: parent.width - 20
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.r.text ?? ""
                font.family: Appearance.font.family.compact
                font.pixelSize: 15
                color: Appearance.colors.colInkSecondary
            }
            Rectangle {
                visible: row.r.kind === "rule"
                x: 8; y: 4
                width: parent.width - 16
                height: 1
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
            }
            BoxShape.Line {
                id: line
                visible: mc.usable(row.index)
                width: parent.width
                label: row.r.kind === "model" ? row.r.m.label : row.r.kind === "typed" ? `Use "${row.r.text}" anyway` : row.r.kind === "more" ? row.r.text : row.r.kind === "less" ? "Show fewer" : ""
                detail: row.r.kind === "model" ? [mc.detailOf(row.r.m), row.r.group ?? ""].filter(s => s).join(", ") : row.r.kind === "more" ? row.r.hint : ""
                ink: row.r.kind === "more" || row.r.kind === "less" ? Appearance.colors.colInkSecondary : Appearance.colors.colInkMain
                on: row.r.kind === "model" && mc.isCurrent(row.r.m)
                strong: line.on
                picked: mc.pick === row.index && !mc.stepPicked && (mc.touched || mc.filter.trim().length > 0)
                onEntered: { mc.touched = true; mc.onStep = false; mc.pick = row.index; tipTimer.restart(); }
                onClicked: mc.use(row.index, false)
                Loader {
                    anchors.fill: parent
                    readonly property string about: row.r.m?.about ?? ""
                    active: mc.tipRow === row.index && about !== "" && about !== row.r.m?.label && about !== mc.detailOf(row.r.m)
                    sourceComponent: StyledToolTip { text: row.r.m?.about ?? ""; alternativeVisibleCondition: true; extraVisibleCondition: false }
                }
            }
        }
    }
    // the model's own words, on dwell
    property int tipRow: -1
    Timer { id: tipTimer; interval: 700; onTriggered: mc.tipRow = mc.pick }

    Column {
        id: foot
        anchors { left: parent.left; right: parent.right; top: list.bottom }
        // the first read of a list
        Row {
            visible: mc.catalogs && mc.cat === null && mc.need === ""
            x: 10
            height: 34
            spacing: 8
            Spinner { anchors.verticalCenter: parent.verticalCenter; implicitSize: 14; colShape: Appearance.colors.colPrimary }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `Reading ${mc.model?.agentName(mc.agent) ?? mc.agent}'s models…`
                font.family: Appearance.font.family.compact
                font.pixelSize: 15
                color: Appearance.colors.colInkSecondary
            }
        }
        StyledText {
            id: needText
            visible: mc.need !== "" && !mc.stepRow
            x: 10
            width: parent.width - 20
            topPadding: 7
            bottomPadding: 7
            text: mc.need
            wrapMode: Text.Wrap
            font.family: Appearance.font.family.compact
            font.pixelSize: 13
            color: Appearance.colors.colInkMeta
        }
        // the account's next step, as the chip row offers it
        BoxShape.Line {
            id: stepLine
            visible: mc.stepRow
            width: parent.width
            label: mc.need || mc.stepSentence
            tail: mc.stepWord
            dot: true
            ink: Appearance.colors.colInkSecondary
            picked: mc.stepPicked
            onEntered: { mc.touched = true; mc.onStep = true; }
            onClicked: mc.stepRequested()
        }
        Item {
            visible: effortLine.visible || keepLine.visible
            width: parent.width
            height: 9
            Rectangle { x: 8; y: 4; width: parent.width - 16; height: 1; color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9) }
        }
        // the levels wrap onto a second line when there are many (pi has eight)
        Item {
            id: effortLine
            visible: mc.effortSets.length > 0 && !!mc.lit && mc.need === ""
            width: parent.width
            height: mc.effortRows * 34
            StyledText {
                visible: mc.levels.length === 0
                x: 10
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "This model has no effort setting"
                font.family: Appearance.font.family.compact
                font.pixelSize: 13
                color: Appearance.colors.colInkMeta
            }
            Flow {
                id: effortFlow
                visible: mc.levels.length > 0
                x: 10
                width: parent.width - 20
                StyledText {
                    width: mc.effortLabelW
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: "Effort"
                    font.family: Appearance.font.family.compact
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Appearance.colors.colInkSecondary
                }
                // the marked word sits on the selected-row fill; each slot's last 2 px are the gap
                Repeater {
                    id: effortRep
                    model: mc.levels
                    delegate: Item {
                        id: word
                        required property string modelData
                        readonly property bool marked: word.modelData === mc.litLevel
                        width: mc.wordW(word.modelData)
                        height: 34
                        Rectangle {
                            width: parent.width - 2
                            height: 26
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 8
                            color: word.marked ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.89)
                                 : wordArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent"
                        }
                        StyledText {
                            x: 7
                            width: parent.width - 16
                            height: 34
                            verticalAlignment: Text.AlignVCenter
                            text: mc.wordText(word.modelData)
                            font.family: Appearance.font.family.compact
                            font.pixelSize: 15
                            font.weight: word.marked ? Font.DemiBold : Font.Normal
                            color: word.marked || wordArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
                        }
                        MouseArea {
                            id: wordArea
                            anchors { fill: parent; rightMargin: 2 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mc.setLevel(word.modelData, true)
                        }
                    }
                }
            }
        }
        BoxShape.Line {
            id: keepLine
            visible: mc.keepShown
            width: parent.width
            label: mc.keepWords
            ink: mc.kept ? Appearance.colors.colInkMeta : Appearance.colors.colInkSecondary
            still: mc.kept
            tail: "Preferences"
            onClicked: {
                const m = mc.lit;
                if (m) mc.chosen(m.id, mc.levelFor(m), true);
            }
            // Preferences has its own target over the word
            MouseArea {
                id: prefsArea
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 12 + Math.ceil(link.advanceWidth("Preferences")) + 6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mc.allDefaults()
                Rectangle {
                    anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
                    radius: 6
                    color: prefsArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.92) : "transparent"
                }
            }
        }
        StyledText {
            visible: !mc.catalogs || mc.stale
            x: 10
            width: parent.width - 20
            height: 26
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            text: !mc.catalogs ? "Update the agent helper to see every model"
                : !mc.gaveUp ? "Checking for new models…"
                : (mc.cat?.at ?? 0) > 0 ? `Could not check for new models; list from ${Qt.formatDateTime(new Date(mc.cat.at), "d MMM")}`
                : "Could not check for new models"
            font.family: Appearance.font.family.compact
            font.pixelSize: 13
            color: Appearance.colors.colInkMeta
        }
    }
}
