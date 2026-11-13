import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "ActivityWords.js" as Words

/**
 * A workflow run: its name and standing (with an estimate of what is left while it runs), its
 * phases as lanes, what it does, Stop; then its agents. A small phase lists its agents, what needs
 * you first and the finished folded past five; in a run with a phase of more than twelve, the
 * agents come first: one line for the failed (Show, Retry), then one state at a time, thirty rows
 * at a time; phases of one or two agents stay in the lanes. The log folds at the foot.
 */
PanelPage {
    id: rp
    bodyHeight: col.implicitHeight
    readonly property var p: rp.pane
    readonly property var run: rp.p.runs.find(r => r.run === rp.entry.id) ?? null
    readonly property var members: rp.run?.agents ?? []
    function bump() { rp.entryChanged(); }

    // the declared phases, then any its agents report that the script did not; agents that do not
    // say their phase are listed together (last, as "Agents", once other agents have a phase)
    readonly property var phases: {
        const ms = rp.members;
        const loose = ms.filter(m => !m.phase);
        if (!ms.some(m => m.phase)) return [{ name: "Agents", members: ms }];
        const names = (rp.run?.phases ?? []).slice();
        for (const m of ms) if (m.phase && !names.includes(m.phase)) names.push(m.phase);
        const out = names.map(n => ({ name: n, members: ms.filter(m => m.phase === n) }));
        if (loose.length) out.push({ name: "Agents", members: loose });
        return out;
    }
    readonly property bool huge: rp.phases.some(ph => ph.members.length > 12)
    readonly property bool allSingle: rp.phases.length > 1 && rp.phases.every(ph => ph.members.length === 1)
    // how long is left: the finished agents' median time, the work still to do, how many run at once
    readonly property string eta: {
        if (rp.run?.state !== "running") return "";
        const times = rp.members.filter(m => m.state === "done" && m.ended && m.started).map(m => m.ended - m.started).sort((a, b) => a - b);
        const running = rp.members.filter(m => m.state === "running").length;
        const waiting = rp.members.filter(m => !["done", "running", "failed", "stopped"].includes(m.state)).length;
        if (times.length < 3 || running === 0) return "";
        const left = Math.ceil((waiting + running / 2) / running) * times[Math.floor(times.length / 2)];
        return `about ${Words.span(Math.max(60000, left))} left`;
    }
    readonly property var order: ({ failed: 0, running: 1, waiting: 2, done: 3, stopped: 4 })
    function sorted(ms) { return ms.slice().sort((a, b) => (rp.order[a.state] ?? 2) - (rp.order[b.state] ?? 2)); }

    // the rows the keys move through: the agents each phase draws, in the order drawn (a big phase one state at a
    // time, the finished folded, a small phase of a big run left to the lanes)
    function navIds() {
        const out = [];
        for (let i = 0; i < phaseList.count; i++) {
            const ph = phaseList.itemAt(i);
            if (ph?.drawn) for (const m of ph.shown) out.push(m.agent);
        }
        return out;
    }
    function navKey(k) {
        const ids = rp.navIds(), n = ids.length;
        if (!n) return false;
        const at = ids.indexOf(rp.entry.f.cursor ?? "");
        if (k === Qt.Key_Down || k === Qt.Key_Up) { rp.entry.f.cursor = ids[Math.max(0, Math.min(n - 1, at < 0 ? 0 : at + (k === Qt.Key_Down ? 1 : -1)))]; rp.bump(); return true; }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) && at >= 0) { rp.p.openAgent(ids[at]); return true; }
        return false;
    }
    property string came: ""
    Timer { running: rp.came.length > 0; interval: 1600; onTriggered: rp.came = "" }

    component Member: PanelRow {
        id: member
        property var m: ({})
        mark: m.state === "stopped" ? "stopped" : (m.state ?? "waiting")
        title: rp.p.niceLabel(m.label, m.phase)
        line: rp.p.lineOf(m)
        tone: m.state === "failed" ? "bad" : m.state === "running" ? "live" : ""
        meta: rp.p.took(m)
        cursor: (rp.entry.f.cursor ?? "") === m.agent
        // the keys' row is scrolled into view, as on the Results page
        onCursorChanged: if (cursor) rp.reveal(member)
        cameFrom: rp.came === `agent:${m.agent}`
        onClicked: rp.p.openAgent(m.agent)
    }
    component Quiet: Item {
        id: q
        property string text: ""
        property string glyph: ""
        signal clicked()
        width: qRow.implicitWidth + 16
        height: 30
        Rectangle { anchors.fill: parent; radius: 8; color: qArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent" }
        Row {
            id: qRow
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            MaterialSymbol { visible: q.glyph.length > 0; anchors.verticalCenter: parent.verticalCenter; text: q.glyph; iconSize: 16; color: Appearance.colors.colInkSecondary }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: q.text; font.pixelSize: 15; color: Appearance.colors.colInkSecondary }
        }
        MouseArea { id: qArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.clicked() }
    }

    Column {
        id: col
        width: parent.width
        spacing: 4
        StyledText {
            visible: !rp.run
            width: parent.width
            topPadding: 16
            text: "This workflow is no longer in the session's list."
            font.pixelSize: 15
            color: Appearance.colors.colInkSecondary
        }
        StyledText {
            visible: !!rp.run
            width: parent.width
            topPadding: 6
            wrapMode: Text.Wrap
            text: rp.p.runName(rp.run)
            font.pixelSize: 24
            font.weight: Font.DemiBold
            color: Appearance.colors.colInkMain
        }
        StyledText {
            visible: !!rp.run
            width: parent.width
            topPadding: 2
            text: [rp.run?.state === "running" ? `Running ${rp.p.took(rp.run)}` : rp.run?.state === "failed" ? `Failed after ${rp.p.took(rp.run)}` : rp.run?.state === "stopped" ? `Stopped after ${rp.p.took(rp.run)}` : `Finished in ${rp.p.took(rp.run)}`, "workflow", rp.eta].filter(x => x).join(" · ")
            font.pixelSize: 15
            font.features: { "tnum": 1 }
            color: Appearance.colors.colInkSecondary
        }
        // what the workflow does, under its name: three lines, the rest on a click
        StyledText {
            visible: (rp.run?.summary ?? "").length > 0
            width: parent.width
            topPadding: 10
            wrapMode: Text.Wrap
            maximumLineCount: rp.entry.f.what ? 400 : 3
            elide: Text.ElideRight
            text: rp.run?.summary ?? ""
            font.pixelSize: 15
            lineHeight: 1.15
            color: Appearance.colors.colInkSecondary
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rp.entry.f.what = !rp.entry.f.what; rp.bump(); } }
        }
        // why a run failed: the first line of its error
        StyledText {
            readonly property var err: rp.run?.error ?? null
            readonly property string line: err === null || err === "" ? "" : (typeof err === "string" ? err : (err.message ?? JSON.stringify(err))).trim().split("\n")[0]
            visible: line.length > 0
            width: parent.width
            topPadding: 4
            wrapMode: Text.Wrap
            text: line
            font.pixelSize: 14
            color: Appearance.colors.colClay
        }
        // a big run's phases at a glance (its lists show one state at a time); a small run's progress is
        // in each phase's heading
        Item { visible: rp.huge; width: 1; height: 16 }
        RunLanes {
            visible: rp.huge
            width: parent.width
            phases: rp.phases
            now: rp.p.now
            onOpenAgent: id => rp.p.openAgent(id)
        }
        Row {
            x: -8
            topPadding: 6
            spacing: 2
            Quiet {
                visible: rp.p.canStop && rp.run?.state === "running" && (rp.run?.task ?? "").length > 0
                glyph: "stop"
                text: rp.p.stopShows(rp.run) === "stopping" ? "Stopping…" : "Stop"
                onClicked: rp.p.stop(rp.run)
            }
        }
        StyledText {
            visible: rp.run?.state === "running" && rp.p.stopShows(rp.run) === "refused"
            width: parent.width
            wrapMode: Text.Wrap
            text: rp.p.refusal(rp.run)
            font.pixelSize: 14
            color: Appearance.colors.colInkSecondary
        }

        // ── the agents, phase by phase ─────────────────────────────────────
        PanelSection { visible: rp.allSingle; text: "Agents"; count: rp.members.length }
        Repeater {
            id: phaseList
            model: rp.phases
            Column {
                id: phaseCol
                required property var modelData
                readonly property var ms: phaseCol.modelData.members
                readonly property bool big: phaseCol.ms.length > 12
                readonly property string key: phaseCol.modelData.name
                readonly property bool single: phaseCol.ms.length === 1
                readonly property var byState: {
                    const b = { failed: [], running: [], waiting: [], done: [], stopped: [] };
                    for (const m of phaseCol.ms) (b[m.state] ?? b.waiting).push(m);
                    return b;
                }
                readonly property string pick: rp.entry.f[`st-${phaseCol.key}`] ?? rp.entry.f.pick
                    ?? (phaseCol.byState.running.length ? "running" : phaseCol.byState.waiting.length ? "waiting" : "done")
                readonly property int limit: rp.entry.f[`lim-${phaseCol.key}`] ?? 30
                readonly property var shown: phaseCol.big ? (phaseCol.byState[phaseCol.pick] ?? []).slice(0, phaseCol.limit)
                    : phaseCol.ms.length > 5 ? rp.sorted(phaseCol.ms).filter(m => m.state !== "done" || rp.entry.f[`done-${phaseCol.key}`]) : rp.sorted(phaseCol.ms)
                readonly property bool drawn: !(rp.huge && phaseCol.ms.length <= 2)
                visible: phaseCol.drawn
                width: parent.width
                spacing: 1
                topPadding: phaseCol.single && !rp.allSingle ? 12 : 0
                PanelSection {
                    visible: !phaseCol.single
                    text: phaseCol.key
                    count: phaseCol.ms.length
                    trailing: Row {
                        spacing: 10
                        height: 22
                        RunBar { anchors.verticalCenter: parent.verticalCenter; width: Math.min(120, Math.max(40, phaseCol.ms.length * 14)); states: phaseCol.ms.map(m => m.state) }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${phaseCol.byState.done.length} of ${phaseCol.ms.length}`
                            font.pixelSize: 14
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colInkMeta
                        }
                    }
                }
                // a big phase: one line for the failed, then a state at a time
                Row {
                    visible: phaseCol.big && phaseCol.byState.failed.length > 0 && phaseCol.pick !== "failed"
                    x: -8
                    spacing: 2
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; text: "error"; iconSize: 16; color: Appearance.colors.colClay }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; leftPadding: 4; rightPadding: 4; text: `${phaseCol.byState.failed.length} failed`; font.pixelSize: 14; color: Appearance.colors.colClay }
                    Quiet { text: "Show"; onClicked: { rp.entry.f[`st-${phaseCol.key}`] = "failed"; rp.bump(); } }
                }
                Flow {
                    visible: phaseCol.big
                    width: parent.width
                    spacing: 2
                    topPadding: 6
                    bottomPadding: 4
                    Repeater {
                        model: phaseCol.big ? ["running", "waiting", "done", "failed", "stopped"].filter(k => phaseCol.byState[k].length) : []
                        Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool on: phaseCol.pick === chip.modelData
                            width: chipRow.implicitWidth + 20
                            height: 28
                            radius: 8
                            color: chip.on ? Appearance.m3colors.m3surfaceContainerHigh : chipArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent"
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                StyledText { text: ({ running: "Running", waiting: "Waiting", done: "Done", failed: "Failed", stopped: "Stopped" })[chip.modelData]; font.pixelSize: 14; color: chip.modelData === "failed" ? Appearance.colors.colClay : chip.on ? Appearance.colors.colInkMain : Appearance.colors.colInkMeta }
                                StyledText { text: phaseCol.byState[chip.modelData].length; font.pixelSize: 14; font.features: { "tnum": 1 }; color: Appearance.colors.colInkFaint }
                            }
                            MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { rp.entry.f[`st-${phaseCol.key}`] = chip.modelData; rp.entry.f[`lim-${phaseCol.key}`] = 30; rp.bump(); } }
                        }
                    }
                }
                Repeater {
                    model: phaseCol.shown
                    Member { required property var modelData; m: modelData }
                }
                Quiet {
                    visible: phaseCol.big && (phaseCol.byState[phaseCol.pick] ?? []).length > phaseCol.limit
                    x: -8
                    glyph: "expand_more"
                    text: `${Math.min(30, (phaseCol.byState[phaseCol.pick] ?? []).length - phaseCol.limit)} more of ${(phaseCol.byState[phaseCol.pick] ?? []).length - phaseCol.limit}`
                    onClicked: { rp.entry.f[`lim-${phaseCol.key}`] = phaseCol.limit + 30; rp.bump(); }
                }
                Quiet {
                    visible: !phaseCol.big && phaseCol.ms.length > 5 && phaseCol.byState.done.length > 0
                    x: -8
                    glyph: rp.entry.f[`done-${phaseCol.key}`] ? "expand_less" : "check"
                    text: rp.entry.f[`done-${phaseCol.key}`] ? "Hide the finished" : `${phaseCol.byState.done.length} done`
                    onClicked: { rp.entry.f[`done-${phaseCol.key}`] = !rp.entry.f[`done-${phaseCol.key}`]; rp.bump(); }
                }
                StyledText { visible: phaseCol.ms.length === 0; text: "Not started"; font.pixelSize: 15; color: Appearance.colors.colInkMeta }
            }
        }

        // the log, folded
        Item {
            visible: (rp.run?.logs ?? []).length > 0
            width: parent.width
            height: 40
            StyledText {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: `Log · ${(rp.run?.logs ?? []).length} ${(rp.run?.logs ?? []).length === 1 ? "line" : "lines"}`
                font.pixelSize: 14
                color: logArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
            }
            MaterialSymbol { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: rp.entry.f.log ? "expand_more" : "chevron_right"; iconSize: 17; color: Appearance.colors.colInkFaint }
            MouseArea { id: logArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { rp.entry.f.log = !rp.entry.f.log; rp.bump(); } }
        }
        StyledText {
            visible: (rp.run?.logs ?? []).length > 0 && !!rp.entry.f.log
            width: parent.width
            wrapMode: Text.Wrap
            text: (rp.run?.logs ?? []).join("\n")
            font.family: Appearance.font.family.monospace
            font.pixelSize: 14
            lineHeight: 1.2
            color: Appearance.colors.colInkSecondary
        }
    }
    function begin() { rp.came = rp.entry.came ?? ""; }
}
