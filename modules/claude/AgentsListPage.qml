import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The trail's first level: what needs you (failures; a workflow with more than two failures is one
 * row), what runs, and what finished in this session, newest first. Rows keep the order they had
 * when you arrived: what finishes while you look updates in place and settles into Done when you
 * come back, so a row never slides away from the pointer.
 */
PanelPage {
    id: lp
    bodyHeight: col.implicitHeight

    readonly property var p: lp.pane

    // ids by section, taken when the page is drawn fresh and kept while you are on it
    function orderNow() {
        const needs = [], running = [], done = [];
        for (const r of lp.p.runs) {
            const failed = (r.agents ?? []).filter(m => m.state === "failed");
            if (failed.length > 2) needs.push(`fails:${r.run}`);
            else for (const m of failed) needs.push(`agent:${m.agent}`);
            (r.state === "running" ? running : done).push(`run:${r.run}`);
        }
        for (const a of lp.p.tree.roots) {
            if (a.state === "failed") needs.push(`agent:${a.agent}`);
            else (lp.p.tree.busy[a.agent] ? running : done).push(`agent:${a.agent}`);
        }
        for (const s of lp.p.shells) (s.state === "running" ? running : done).push(`shell:${s.task ?? s.call}`);
        const at = k => { const [t, id] = [k.split(":")[0], k.slice(k.indexOf(":") + 1)];
            const x = t === "run" ? lp.p.runs.find(r => r.run === id) : t === "agent" ? lp.p.findAgent(lp.p.info, id) : null;
            return x ? (x.ended || x.started || 0) : 0; };
        done.sort((a, b) => at(b) - at(a));
        return { needs: needs, running: running, done: done };
    }
    // taken once the session's agents have been read, not before
    property var order: null
    function take() { lp.entry.order = lp.orderNow(); lp.order = lp.entry.order; }
    function begin() { if (lp.entry.order) lp.order = lp.entry.order; else if (lp.p.loaded) lp.take(); lp.came = lp.entry.came ?? ""; lp.cursorKey = lp.entry.f.cursor ?? ""; }
    Connections { target: lp.p; function onLoadedChanged() { if (lp.p.loaded && !lp.order && lp.entry.k) lp.take(); } }
    // what failed, started or finished after you arrived joins its section at the end and is kept there: one that started
    // while you looked and then finished was in neither the kept order nor the running ones, and its row went
    readonly property var fresh: {
        const o = lp.order; if (!o) return { needs: [], running: [], done: [] };
        const seen = new Set([...o.needs, ...o.running, ...o.done]);
        const n = lp.orderNow();
        return { needs: n.needs.filter(k => !seen.has(k)), running: n.running.filter(k => !seen.has(k)), done: n.done.filter(k => !seen.has(k)) };
    }
    onFreshChanged: {
        const o = lp.order, f = lp.fresh;
        if (!o || !(f.needs.length || f.running.length || f.done.length)) return;
        lp.entry.order = { needs: o.needs.concat(f.needs), running: o.running.concat(f.running), done: o.done.concat(f.done) };
        lp.order = lp.entry.order;
    }
    readonly property int settled: {
        const o = lp.order; if (!o) return 0;
        return o.running.filter(k => { const s = lp.stateOf(k); return s && s !== "running"; }).length;
    }
    function stateOf(k) {
        const t = k.split(":")[0], id = k.slice(k.indexOf(":") + 1);
        if (t === "run") return lp.p.runs.find(r => r.run === id)?.state ?? "";
        if (t === "agent") return lp.p.findAgent(lp.p.info, id)?.state ?? "";
        if (t === "shell") return lp.p.shells.find(s => (s.task ?? s.call) === id)?.state ?? "";
        return "failed";
    }
    readonly property var doneShown: lp.order ? (lp.entry.f.allDone ? lp.order.done : lp.order.done.slice(0, 6)) : []
    // the rows the keys move through, in order
    readonly property var navList: lp.order ? [...lp.order.needs, ...lp.order.running, ...lp.doneShown] : []
    function navKey(k) {
        const n = lp.navList.length;
        if (!n) return false;
        const at = lp.navList.indexOf(lp.entry.f.cursor ?? "");
        if (k === Qt.Key_Down || k === Qt.Key_Up) { lp.entry.f.cursor = lp.navList[Math.max(0, Math.min(n - 1, at < 0 ? 0 : at + (k === Qt.Key_Down ? 1 : -1)))]; lp.cursorChanged(); return true; }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) && at >= 0) { lp.openKey(lp.navList[at]); return true; }
        return false;
    }
    signal cursorChanged()
    property string cursorKey: ""
    onCursorChanged: lp.cursorKey = lp.entry.f.cursor ?? ""
    function openKey(k) {
        const t = k.split(":")[0], id = k.slice(k.indexOf(":") + 1);
        if (t === "run") lp.p.openRun(id);
        else if (t === "agent") lp.p.openAgent(id);
        else if (t === "fails") lp.p.openRunFailed(id);
    }
    // the row you came back from wears the wash a moment
    property string came: ""
    Timer { running: lp.came.length > 0; interval: 1600; onTriggered: lp.came = "" }

    component Entry: Item {
        id: en
        property string k: ""
        readonly property string t: en.k.split(":")[0]
        readonly property string id: en.k.slice(en.k.indexOf(":") + 1)
        readonly property var run: en.t === "run" || en.t === "fails" ? lp.p.runs.find(r => r.run === en.id) ?? null : null
        readonly property var agent: en.t === "agent" ? lp.p.findAgent(lp.p.info, en.id) : null
        readonly property var shell: en.t === "shell" ? lp.p.shells.find(s => (s.task ?? s.call) === en.id) ?? null : null
        readonly property var members: en.run?.agents ?? []
        readonly property string stops: en.shell ? lp.p.stopShows(en.shell) : ""
        width: parent ? parent.width : 0
        height: row.implicitHeight
        PanelRow {
            id: row
            anchors { left: parent.left; right: stopPill.visible ? stopPill.left : parent.right; rightMargin: stopPill.visible ? 10 : 0 }
            mark: en.t === "fails" ? "failed" : (en.run?.state ?? en.agent?.state ?? en.shell?.state ?? "done")
            glyph: en.t === "shell" ? "terminal" : ""
            title: en.t === "fails" ? `${en.members.filter(m => m.state === "failed").length} agents failed`
                 : en.run ? lp.p.runName(en.run) : en.agent ? (en.agent.description || en.agent.label || "Agent") : (en.shell?.desc || en.shell?.command || "")
            line: {
                if (en.t === "fails") return `in ${lp.p.runName(en.run)}`;
                if (en.run) {
                    const n = s => en.members.filter(m => m.state === s).length;
                    const d = n("done"), f = n("failed"), st = n("stopped");
                    const ph = en.members.find(m => m.state === "running")?.phase ?? "";
                    return [en.run.state === "running" && ph ? ph : "", `${d} of ${en.members.length} done`, f ? `${f} failed` : "", st ? `${st} stopped` : ""].filter(x => x).join(" · ");
                }
                if (en.agent) return lp.p.lineOf(en.agent);
                if (en.stops === "refused") return lp.p.refusal(en.shell);
                return en.shell?.state === "running" ? "running" : "ended";
            }
            tone: en.t === "fails" || en.agent?.state === "failed" ? "bad" : (en.run?.state ?? en.agent?.state) === "running" ? "live" : ""
            meta: en.t === "fails" ? "" : lp.p.took(en.run ?? en.agent ?? en.shell)
            chevron: en.t !== "shell"
            cursor: lp.cursorKey === en.k
            // the keys' row is scrolled into view, as on the Results page
            onCursorChanged: if (cursor) lp.reveal(en)
            cameFrom: lp.came === en.k
            extra: RunBar {
                visible: !!en.run && en.t === "run"
                width: parent ? parent.width : 0
                states: en.members.map(m => m.state)
            }
            onClicked: lp.openKey(en.k)
        }
        PillButton {
            id: stopPill
            visible: !!en.shell && lp.p.canStop && en.shell.state === "running" && (en.shell.task ?? "").length > 0
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: en.stops === "stopping" ? "Stopping…" : "Stop"
            onClicked: lp.p.stop(en.shell)
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 1
        StyledText {
            readonly property string says: lp.p.loaded ? (!lp.p.readable ? `${lp.p.toolName(lp.p.info?.tool ?? "")}'s agents can't be read yet. Its results still show in the conversation.`
                : (!lp.p.agents.length && !lp.p.runs.length && !lp.p.shells.length) ? "No agents in this session yet." : "")
                : lp.p.listError.length ? lp.p.listError
                : !(lp.p.host?.connected ?? false) ? "Lost the connection to the background service. Praxis keeps trying to reconnect." : "Reading…"
            visible: says.length > 0
            width: parent.width
            topPadding: 16
            wrapMode: Text.Wrap
            text: says
            font.pixelSize: 15
            color: says === "Reading…" ? Appearance.colors.colInkMeta : Appearance.colors.colInkSecondary
        }
        PanelSection { visible: (lp.order?.needs ?? []).length > 0; text: "Needs you"; count: (lp.order?.needs ?? []).length }
        Repeater { model: lp.order?.needs ?? []; Entry { required property string modelData; k: modelData } }
        PanelSection { visible: (lp.order?.running ?? []).length > 0; text: "Running"; count: (lp.order?.running ?? []).length }
        Repeater { model: lp.order?.running ?? []; Entry { required property string modelData; k: modelData } }
        StyledText {
            visible: lp.settled > 0
            width: parent.width
            topPadding: 6
            wrapMode: Text.Wrap
            text: `${lp.settled} finished while you were here · ${lp.settled === 1 ? "it moves" : "they move"} to Done when you come back`
            font.pixelSize: 14
            color: Appearance.colors.colInkFaint
        }
        PanelSection { visible: lp.doneShown.length > 0; text: "Done in this session"; count: (lp.order?.done ?? []).length }
        Repeater { model: lp.doneShown; Entry { required property string modelData; k: modelData } }
        StyledText {
            visible: (lp.order?.done ?? []).length > 6
            height: 34
            leftPadding: 34
            verticalAlignment: Text.AlignVCenter
            text: lp.entry.f.allDone ? "Show fewer" : `Show all ${(lp.order?.done ?? []).length}`
            font.pixelSize: 14
            color: allArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
            MouseArea { id: allArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { lp.entry.f.allDone = !lp.entry.f.allDone; lp.entryChanged(); } }
        }
        StyledText {
            readonly property int ended: lp.p.info?.shellsEnded ?? 0
            visible: ended > 0
            topPadding: 10
            text: `${ended} earlier background ${ended === 1 ? "command" : "commands"} ended`
            font.pixelSize: 14
            color: Appearance.colors.colInkSecondary
        }
    }
}
