import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.tacit
import "ActivityWords.js" as Words

/**
 * Results and Agents, in the side panel, as trails of pages, one per tab. Results: what the session's
 * agents found (agent-host's "results": findings by what they need, failures, changes, pictures),
 * a finding, and from there its agents. Agents: what the session runs besides its own turn
 * (sub-agents, workflow runs, background commands) and what finished: the list, a workflow, an agent,
 * a file. Each level keeps its scroll and folds; Back (the chevron, a crumb, Esc, Backspace, the
 * mouse's back button, two fingers to the right) returns to exactly where you were; a page already
 * on the trail is gone back to rather than stacked again. "agents" is polled by the window; an
 * agent's steps come from "agent" and are kept per agent while the session is open; "results" is
 * asked again when the agents change or while reports are being read. Stop sends stop_task, offered
 * only for sessions this app runs.
 */
Item {
    id: pane
    property var host: null
    property string sessionId: ""
    property var info: null           // agent-host "agents" reply
    property bool canStop: false
    property real now: Date.now()
    property var tabs: []
    property string root: "agents"    // the tab showing: "agents" or "results"
    property var files: null          // the side panel: a step's file opens there
    property string cwd: ""           // the session's folder, where a report's relative file is looked for
    signal tabPicked(string key)
    signal closeRequested()
    signal stopRequested(string task)
    signal pictureRequested(string path)
    signal reviewRequested()          // Results: the session's changes in the review
    signal restartHostRequested()     // Results: the background service is too old for them

    // ── the trail ───────────────────────────────────────────────────────────
    // entries: { k: "results" | "finding" | "list" | "run" | "agent" | "file", id, y, f: {folds, filter, ...}, came }
    property var trail: [{ k: "list", y: 0, f: ({}) }]
    property var trails: ({})         // the other tab's trail, kept while this one shows
    property string shownRoot: ""
    function rootEntry(r) { return { k: r === "results" ? "results" : "list", y: 0, f: {} }; }
    onRootChanged: pane.switchRoot()
    function switchRoot() {
        if (pane.shownRoot === pane.root) return;
        if (pane.page && pane.shownRoot.length) { pane.page.save(); pane.trails[pane.shownRoot] = pane.trail; }
        pane.shownRoot = pane.root;
        pane.trail = pane.trails[pane.root] ?? [pane.rootEntry(pane.root)];
        pane.show(0);
    }
    readonly property var topEntry: pane.trail[pane.trail.length - 1]
    // what the window and the conversation ask of the panel (claude.qml): which agent or run shows
    readonly property string view: pane.topEntry.k === "agent" ? "agent" : pane.topEntry.k === "run" ? "run" : "list"
    readonly property string shownAgent: pane.topEntry.k === "agent" ? pane.topEntry.id : ""
    readonly property string shownRun: pane.topEntry.k === "run" ? pane.topEntry.id : ""
    property var page: null
    // levels you backed out of, by kind and id: going to one again finds it as you left it
    property var memo: ({})
    function forget(from) { for (const e of pane.trail.slice(from)) pane.memo[`${e.k}:${e.id ?? ""}`] = e; }

    function push(e) {
        if (pane.page) pane.page.save();
        const j = pane.trail.findIndex(x => x.k === e.k && (x.id ?? "") === (e.id ?? ""));
        if (j >= 0) {
            const was = pane.trail.length - 1;
            pane.forget(j + 1);
            pane.trail = pane.trail.slice(0, j + 1);
            if (e.f) Object.assign(pane.trail[j].f, e.f);
            if (pane.trail[j].k === "list") pane.trail[j].order = null;
            pane.show(j === was ? 0 : -1);
            return;
        }
        pane.topEntry.came = e.came ?? `${e.k}:${e.id}`;
        const m = pane.memo[`${e.k}:${e.id ?? ""}`];
        if (m) { delete m.came; if (e.f) Object.assign(m.f, e.f); }
        pane.trail = pane.trail.concat([m ?? Object.assign({ y: 0, f: {} }, e)]);
        pane.show(1);
    }
    function back() {
        if (pane.trail.length < 2) return false;
        if (pane.page) pane.page.save();
        pane.forget(pane.trail.length - 1);
        pane.trail = pane.trail.slice(0, -1);
        // coming back to the list: what finished while you were away settles into Done now
        if (pane.topEntry.k === "list") pane.topEntry.order = null;
        pane.show(-1);
        return true;
    }
    function jumpTo(i) {
        if (i >= pane.trail.length - 1) return;
        if (pane.page) pane.page.save();
        pane.forget(i + 1);
        pane.trail = pane.trail.slice(0, i + 1);
        if (pane.topEntry.k === "list") pane.topEntry.order = null;
        pane.show(-1);
    }
    function showList() {
        if (pane.root !== "agents") { pane.trails.agents = [pane.rootEntry("agents")]; return; }
        if (pane.trail.length === 1 && pane.page) return;
        if (pane.page) pane.page.save();
        pane.forget(1);
        pane.trail = [Object.assign(pane.trail[0], { order: null })];
        pane.show(0);
    }
    function openAgent(id) { pane.push({ k: "agent", id: id }); }
    function openRun(run) { pane.push({ k: "run", id: run }); }
    function openRunFailed(run) { pane.push({ k: "run", id: run, f: { pick: "failed" } }); }
    function openFile(path, from) { pane.push({ k: "file", id: path, f: { from: from ?? "" } }); }
    function openStep(agent, i) { pane.push({ k: "agent", id: agent, f: { jump: i } }); }
    // a finding is known by its first source and its title; the page keeps the finding as it was
    function openFinding(f) { pane.push({ k: "finding", id: `${f.sources?.[0]?.source ?? ""}|${f.title}`, f: { finding: f } }); }
    // A finding's file as the report wrote it ("F.qml", "F.qml:14", "F.qml:12-20", "dir/F.qml", "/abs/F.qml:14", "~/F.qml")
    // placed: its absolute path (a file the agents changed first, else the session's folder) and line (a range's first);
    // path "" when it cannot be placed.
    function fileOf(raw, line) {
        const m = /^(.*?)(?::(\d+)(?:-\d+)?(?::\d+)?)?$/.exec(String(raw ?? "").trim());
        const rel = m[1].replace(/^\.\//, "");
        const at = Number(m[2]) || Number(line) || 0;
        if (!rel.length) return { path: "", line: 0 };
        if (rel.startsWith("/") || rel.startsWith("~/")) return { path: rel, line: at };
        const changed = (pane.results?.changes ?? []).find(c => c.path === rel || c.path.endsWith("/" + rel));
        return { path: changed ? changed.path : pane.cwd.length ? `${pane.cwd}/${rel}` : "", line: at };
    }
    // a file the session's agents changed: their steps are read so the file page can show each edit
    function openFileBy(path, by) {
        for (const b of (by ?? []).slice(0, 12)) if (!pane.stepsBy[b.source] && !String(b.source).startsWith("turn-")) pane.loadSteps(b.source);
        pane.openFile(path, by?.[0]?.source ?? "");
    }
    // a file asks the panel for room (SidePanel widens while it shows)
    readonly property bool wantsWide: pane.topEntry.k === "file"
    function show(dir) {
        const e = pane.topEntry;
        const comp = ({ agent: agentPageC, run: runPageC, file: filePageC, results: resultsPageC, finding: findingPageC })[e.k] ?? listPageC;
        const old = pane.page;
        // the entry is handed over after the page is made: createObject's property map would copy it,
        // and the page keeps its scroll and folds in the trail's own entry
        const p = comp.createObject(stage, { pane: pane, x: dir > 0 ? 24 : dir < 0 ? -24 : 0, opacity: dir ? 0 : 1 });
        p.entry = e;
        p.begin();
        pane.page = p;
        if (dir) Qt.callLater(() => { if (p) { p.x = 0; p.opacity = 1; } });
        Qt.callLater(() => { if (p && p.restore) p.restore(); });
        if (old) { if (dir) old.leave(dir); else old.destroy(); }
        if (e.k === "agent") pane.loadSteps(e.id);
    }
    function label(e) {
        if (e.k === "list") return "Agents";
        if (e.k === "results") return "Results";
        if (e.k === "finding") return e.f.finding?.title ?? "Finding";
        if (e.k === "run") return pane.runName(pane.runs.find(r => r.run === e.id));
        if (e.k === "agent") { const a = pane.findAgent(pane.info, e.id); return a?.description || a?.label || "Agent"; }
        if (e.k === "file") return String(e.id).split("/").pop();
        return "";
    }
    onSessionIdChanged: {
        pane.presses = ({}); pane.listError = ""; pane.probed = ""; pane.stepsBy = ({}); pane.memo = ({});
        pane.results = null; pane.resultsError = ""; pane.answer = null;
        pane.trails = ({});
        pane.trail = [pane.rootEntry(pane.root)];
        pane.show(0);
        pane.loadResults();
    }
    Component.onCompleted: pane.switchRoot()

    // ── results ─────────────────────────────────────────────────────────────
    readonly property bool canResults: (pane.host?.features ?? []).includes("results")
    property var results: null
    property string resultsError: ""
    property bool resultsBusy: false
    // a reply is taken only when it says something new: it can be megabytes, the page is not redrawn
    // for an equal one. All of it is compared but its tag: counts alone missed what changes in place (a finding
    // that may be fixed, a verdict, a change's line counts), and the page went on showing the old reply
    property string resultsSig: ""
    function sigOfResults(m) { return JSON.stringify(Object.assign({}, m, { tag: 0 })); }
    function loadResults() {
        if (!pane.canResults || !pane.sessionId.length || pane.resultsBusy || pane.root !== "results" || !pane.visible) return;
        const sid = pane.sessionId;
        pane.resultsBusy = true;
        pane.host.request({ op: "results", id: sid }, m => {
            pane.resultsBusy = false;
            if (pane.sessionId !== sid) return;
            if (m.ev !== "results") { pane.resultsError = m.message ?? ""; return; }
            pane.resultsError = "";
            const sig = pane.sigOfResults(m);
            if (!pane.results || sig !== pane.resultsSig) { pane.resultsSig = sig; pane.results = m; }
        });
    }
    onVisibleChanged: pane.loadResults()
    onShownRootChanged: pane.loadResults()
    onCanResultsChanged: pane.loadResults()
    Timer { id: resultsSoon; interval: 800; onTriggered: pane.loadResults() }
    // while reports are being read, every few seconds
    Timer { running: (pane.results?.reading ?? 0) > 0 && pane.root === "results" && pane.visible; interval: 3000; repeat: true; onTriggered: pane.loadResults() }
    function readReports() {
        if (!pane.canResults) return;
        const sid = pane.sessionId;
        pane.host.request({ op: "read_reports", id: sid }, () => { if (pane.sessionId === sid) resultsSoon.restart(); });
    }
    // a question about the results: one Sonnet call
    property var answer: null         // { q, answer, sources, cost } | { q, asking: true } | { q, error }
    function ask(q) {
        const t = String(q).trim();
        if (!t.length || !pane.canResults || pane.answer?.asking) return;
        const sid = pane.sessionId;
        pane.answer = { q: t, asking: true };
        pane.host.request({ op: "ask", id: sid, q: t }, m => {
            if (pane.sessionId !== sid) return;
            pane.answer = m.ev === "ask" ? { q: t, answer: m.answer, sources: m.sources ?? [], cost: m.cost ?? 0 } : { q: t, error: m.message ?? "No answer" };
        });
    }

    // ── the data ────────────────────────────────────────────────────────────
    readonly property var agents: pane.info?.agents ?? []
    readonly property var runs: pane.info?.workflows ?? []
    readonly property var shells: pane.info?.shells ?? []
    // workflow members are agents too; the panel finds one by id wherever it lives
    function findAgent(info, id) {
        const a = (info?.agents ?? []).find(x => x.agent === id);
        if (a) return a;
        for (const r of info?.workflows ?? []) {
            const m = (r.agents ?? []).find(x => x.agent === id);
            if (m) return Object.assign({ description: pane.niceLabel(m.label), type: "workflow agent", inRun: r.run }, m);
        }
        return null;
    }
    readonly property bool loaded: pane.info !== null && (pane.info.id === undefined || pane.info.id === pane.sessionId)
    readonly property bool readable: pane.info?.readable !== false
    property string listError: ""
    property string probed: ""        // the session this pane has asked itself
    function probe() {
        if (!pane.host || !pane.host.connected || !pane.sessionId.length || pane.loaded || pane.probed === pane.sessionId) return;
        const id = pane.sessionId;
        pane.probed = id;
        pane.host.request({ op: "agents", id: id }, m => { if (pane.sessionId === id && !pane.loaded && m.ev !== "agents" && !m.disconnected) pane.listError = m.message ?? ""; });
    }
    Timer { running: pane.visible && !pane.loaded && pane.listError.length === 0 && (pane.host?.connected ?? false) && pane.sessionId.length > 0; interval: 1500; onTriggered: pane.probe() }
    // a workflow agent's label as words: "build:zen-import" → "Zen import" under its phase's heading,
    // "Build: zen import" elsewhere; a description written in words stays as it is
    function niceLabel(label, phase) {
        let s = String(label || "Agent").trim();
        if (/\s/.test(s)) return s;
        const i = s.indexOf(":");
        if (i > 0 && phase !== undefined) s = s.substring(i + 1);
        else if (i > 0) s = s.substring(0, i) + ": " + s.substring(i + 1).replace(/^\s+/, "");
        s = s.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim();
        return s.length ? s.charAt(0).toUpperCase() + s.substring(1) : "Agent";
    }
    // a workflow is named when its script says so; until then, by its phases
    function runName(r) {
        if (!r) return "Workflow";
        if (r.name && r.name !== r.run) return pane.niceLabel(r.name);
        const ph = (r.phases ?? []).length ? r.phases : [...new Set((r.agents ?? []).map(m => m.phase).filter(x => x))];
        return ph.length ? `Workflow · ${ph.join(" → ")}` : "Workflow";
    }
    function toolName(t) { return t === "codex" ? "Codex" : t === "opencode" ? "opencode" : t === "pi" ? "pi" : "This agent"; }

    // an agent's steps, its whole ask and its report, kept per agent while the session is open
    property var stepsBy: ({})        // agent -> { items, detail, error, sig }
    function loadSteps(agent) {
        if (!pane.host || !pane.sessionId || !agent) return;
        const sid = pane.sessionId;
        pane.host.request({ op: "agent", id: sid, agent: agent }, m => {
            if (pane.sessionId !== sid) return;
            const c = Object.assign({}, pane.stepsBy);
            const was = c[agent] ?? {};
            c[agent] = m.ev === "agent"
                ? { items: m.items ?? [], detail: { asked: m.asked ?? "", report: m.report ?? "", kind: m.reportKind ?? "text", cut: m.reportCut === true }, error: "", sig: pane.sigOf(pane.findAgent(pane.info, agent)) }
                : Object.assign({}, was, { error: m.message ?? "" });
            pane.stepsBy = c;
        });
    }
    function sigOf(a) { return a ? `${a.state}|${a.steps ?? ""}|${a.ended ?? ""}` : ""; }
    Connections {
        target: pane.host
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (!pane.host.connected) return;
            pane.listError = ""; pane.probed = "";
            if (pane.view === "agent") pane.loadSteps(pane.shownAgent);
        }
    }
    // the shown agent's steps are read again when its state, step count or end changes
    onInfoChanged: {
        const info = pane.info;
        if (info) pane.listError = "";
        if (pane.root === "results") resultsSoon.restart();
        if (pane.view === "agent") {
            const sig = pane.sigOf(pane.findAgent(info, pane.shownAgent));
            if (sig !== (pane.stepsBy[pane.shownAgent]?.sig ?? "")) pane.loadSteps(pane.shownAgent);
        }
        let m = null;
        for (const e of (info?.agents ?? []).concat(info?.workflows ?? [], info?.shells ?? [])) {
            const p = pane.presses[e.task ?? ""];
            if (p && p.refusedBefore && e.stop?.state === "stopping") { m = m ?? Object.assign({}, pane.presses); m[e.task] = Object.assign({}, p, { refusedBefore: false }); }
        }
        if (m) pane.presses = m;
    }

    // ── Stop: "Stopping…" from the press until the task's state changes or the host refuses ──
    property var presses: ({})        // task -> { state, at, refusedBefore }
    function stopShows(e) {
        if (!e || !(e.task ?? "").length) return "";
        const s = e.stop?.state ?? "", p = pane.presses[e.task], mine = !!p && p.state === e.state;
        if (s === "refused" && !(mine && p.refusedBefore && pane.now - p.at < 3000)) return "refused";
        return mine || s === "stopping" ? "stopping" : "";
    }
    function stop(e) {
        const was = pane.stopShows(e);
        if (was === "stopping") return;
        const m = Object.assign({}, pane.presses);
        m[e.task] = { state: e.state, at: Date.now(), refusedBefore: was === "refused" };
        pane.presses = m;
        pane.stopRequested(e.task);
    }
    function refusal(e) { return `Couldn't stop: ${String(e?.stop?.message ?? "").split("\n")[0]}`; }

    function modelName(m) {
        const x = /(?:claude-)?([a-z]+)-(\d+)(?:-(\d+))?/.exec(m ?? "");
        if (!x) return m ?? "";
        return x[1].charAt(0).toUpperCase() + x[1].substring(1) + " " + x[2] + (x[3] && x[3].length <= 2 ? "." + x[3] : "");
    }
    function took(a) { return a && a.started > 0 ? Words.span((a.state === "running" ? pane.now : (a.ended || a.started)) - a.started) : ""; }
    function firstSentence(t) { const s = String(t ?? "").replace(/\s+/g, " ").trim(); const m = s.match(/^.*?[.!?](\s|$)/); return (m ? m[0] : s).trim(); }
    // the line under an agent's name: the step it is on, what stopped it (the host's outcome: the first sentence of its report), or how it went
    function lineOf(a) {
        if (!a) return "";
        if (a.state === "running") return a.last ? `${a.last.desc || a.last.summary || a.last.tool || ""}` : "Starting";
        if (a.state === "failed") {
            const run = a.inRun ? pane.runs.find(r => r.run === a.inRun) : null;
            return [pane.firstSentence(a.error ?? a.outcome ?? "It stopped with an error"), run ? `in ${pane.runName(run)}` : ""].filter(x => x).join(" · ");
        }
        if (a.state === "stopped") return "Stopped";
        const n = a.steps ?? 0;
        return `${n} ${n === 1 ? "step" : "steps"}`;
    }

    // ── who started whom, built once per reply ─────────────────────────────
    readonly property var tree: {
        const byId = {}, kids = {}, busy = {};
        for (const a of pane.agents) byId[a.agent] = a;
        for (const a of pane.agents) if (a.parent) (kids[a.parent] = kids[a.parent] ?? []).push(a);
        const roots = pane.agents.filter(a => !(a.parent && byId[a.parent]));
        const walk = (a, seen) => {
            if (seen[a.agent]) return false;
            seen[a.agent] = true;
            let r = a.state === "running";
            for (const k of kids[a.agent] ?? []) r = walk(k, seen) || r;
            busy[a.agent] = r;
            return r;
        };
        for (const r of roots) walk(r, {});
        return { byId: byId, kids: kids, roots: roots, busy: busy };
    }

    // ── keys: Esc and Backspace go back; ↑↓ and Enter act on the page's rows ──
    Item {
        id: keys
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape || e.key === Qt.Key_Backspace) { if (pane.back()) e.accepted = true; return; }
            if (pane.page && pane.page.navKey && pane.page.navKey(e.key)) e.accepted = true;
        }
    }
    function key(k) {
        if (k === Qt.Key_Escape || k === Qt.Key_Backspace) return pane.back();
        return !!(pane.page && pane.page.navKey && pane.page.navKey(k));
    }
    // the mouse's back button; two fingers swiped right (what the pages' scrolling leaves alone), once a
    // gesture, as a browser goes back
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onClicked: pane.back()
        property real swept: 0
        property double at: 0
        property bool spent: false
        onWheel: e => {
            if (Math.abs(e.pixelDelta.x) <= Math.abs(e.pixelDelta.y)) { e.accepted = false; return; }
            const now = Date.now();
            if (e.phase === Qt.ScrollBegin || now - at > 300) { swept = 0; spent = false; }
            at = now;
            swept += e.pixelDelta.x;
            if (!spent && swept > 120) { spent = true; pane.back(); }
        }
    }

    // ── the header: the panel's tabs, Close ────────────────────────────────
    component Act: MaterialSymbol {
        id: actGlyph
        property string tip: ""
        signal clicked()
        iconSize: 16
        color: actArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
        MouseArea { id: actArea; anchors { fill: parent; margins: -5 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: actGlyph.clicked() }
        StyledToolTip { text: actGlyph.tip; extraVisibleCondition: actArea.containsMouse }
    }
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56
        PanelTabs {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            names: pane.tabs
            current: pane.root
            // the tab showing, picked again, goes back to its first page
            onPicked: key => { if (key === pane.root) pane.jumpTo(0); else pane.tabPicked(key); }
        }
        Act { anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter } text: "close"; iconSize: 18; tip: "Close (Ctrl+Alt+B)"; onClicked: pane.closeRequested() }
    }

    // ── where you are: Back, named for where it goes, and the pages before that ──
    // The page's own title says where you are, so it is not a crumb; the tab says the first page.
    Item {
        id: crumbBar
        anchors { left: parent.left; right: parent.right; top: header.bottom }
        height: pane.trail.length > 1 ? 46 : 0
        clip: true
        readonly property var parentEntry: pane.trail.length > 1 ? pane.trail[pane.trail.length - 2] : null
        // the pages before the one Back goes to, not counting the tab's first page; at most two, the
        // nearest last
        readonly property var before: pane.trail.slice(1, -2).map((e, k) => ({ e: e, i: k + 1 })).slice(-2)
        Row {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                id: backButton
                anchors.verticalCenter: parent.verticalCenter
                width: backRow.implicitWidth + 22
                height: 32
                radius: 8
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, backArea.pressed ? 0.86 : backArea.containsMouse ? 0.9 : 0.94)
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    id: backRow
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "chevron_left"; iconSize: 20; color: Appearance.colors.colInkMain }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, crumbBar.width * 0.55)
                        elide: Text.ElideRight
                        text: crumbBar.parentEntry ? pane.label(crumbBar.parentEntry) : ""
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: Appearance.colors.colInkMain
                    }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pane.back() }
                StyledToolTip { text: "Back (Esc)"; extraVisibleCondition: backArea.containsMouse }
            }
            // the pages before it: "in A › B"
            StyledText {
                visible: crumbBar.before.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "in"
                font.pixelSize: 14
                color: Appearance.colors.colInkMeta
            }
            Repeater {
                model: crumbBar.before
                Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    MaterialSymbol { visible: crumb.index > 0; anchors.verticalCenter: parent.verticalCenter; text: "chevron_right"; iconSize: 15; color: Appearance.colors.colInkFaint }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: crumbWord.width + 12
                        height: 26
                        radius: 6
                        color: crumbArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.92) : "transparent"
                        StyledText {
                            id: crumbWord
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 150)
                            elide: Text.ElideRight
                            text: pane.label(crumb.modelData.e)
                            font.pixelSize: 14
                            color: crumbArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
                        }
                        MouseArea { id: crumbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pane.jumpTo(crumb.modelData.i) }
                    }
                }
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 20; rightMargin: 20 }
            height: 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
        }
    }

    Item {
        id: stage
        anchors { left: parent.left; right: parent.right; top: crumbBar.bottom; bottom: parent.bottom }
        clip: true
    }
    // a press in the pane gives it the keys (as the conversation's box has them otherwise) and goes on
    // to what is under it
    MouseArea {
        anchors.fill: parent
        z: 10
        onPressed: m => { keys.forceActiveFocus(); m.accepted = false; }
    }
    Component { id: listPageC; AgentsListPage {} }
    Component { id: runPageC; RunPage {} }
    Component { id: agentPageC; AgentPage {} }
    Component { id: filePageC; FilePage {} }
    Component { id: resultsPageC; ResultsPage {} }
    Component { id: findingPageC; FindingPage {} }
}
