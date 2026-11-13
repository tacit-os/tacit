import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "ActivityWords.js" as Words

/**
 * A workflow run in the conversation: one soft slab with its name, how many of its agents are
 * done, how long it has run, Stop while it runs (sessions this app runs), and its phases as pills
 * joined by chevrons: done (raised, a check), running (the sand wash, the working indicator),
 * stopped (a hairline, the stop glyph), waiting (a hairline). A click opens the run in the side
 * panel's Agents tab, once the host has read it.
 */
Rectangle {
    id: card
    property var item: null           // the Workflow tool item
    property var run: null            // agent-host "agents" workflows[] entry for this call
    property bool open: false
    property bool canStop: false
    property real now: Date.now()
    property bool pending: false      // the host may still say how it stands (see AgentsGroup)
    signal opened()
    signal stopRequested(string task)

    // before the host has read it, the call stands in; a launch answers at once ("Workflow launched").
    // A call the host has no record of, in an idle session it has answered about, has ended. The 30 s are counted on a
    // clock of their own, as AgentsGroup's: `now` ticks only while something runs.
    property real graceNow: Date.now()
    Timer { running: (card.item?.ts ?? 0) > 0 && card.graceNow - card.item.ts < 30000; interval: 1000; repeat: true; onTriggered: card.graceNow = Date.now() }
    readonly property bool waiting: card.pending || ((card.item?.ts ?? 0) > 0 && card.graceNow - card.item.ts < 30000)
    readonly property string status: card.run?.state
        ?? (card.item && (card.item.result === undefined || /^(Async agent launched|Workflow launched)/.test(String(card.item.result))) ? (card.waiting ? "running" : "ended") : "done")
    readonly property var members: card.run?.agents ?? []
    // the phases the script declares, else the ones its agents report, in order of appearance
    readonly property var phases: {
        const declared = card.run?.phases ?? [];
        const seen = declared.slice();
        for (const m of card.members) if (m.phase && !seen.includes(m.phase)) seen.push(m.phase);
        return seen;
    }
    function phaseStatus(p) {
        // agents that do not say their phase: a finished run has finished every phase
        if (!card.members.some(m => m.phase)) return card.status === "done" ? "done" : "waiting";
        const ms = card.members.filter(m => m.phase === p);
        if (ms.length && ms.every(m => m.state === "done")) return "done";
        if (ms.some(m => m.state === "running")) return "running";
        if (ms.some(m => m.state === "failed")) return "failed";
        return ms.length ? "stopped" : "waiting";
    }
    // Stop: "Stopping…" from the press until the run's state changes or the host says it refused.
    // A refusal shown before a second press is set aside for a few seconds, until the host has
    // the new request.
    property var stopPress: null      // { state, at, refusedBefore }
    readonly property string stopShows: {
        const s = card.run?.stop?.state ?? "";
        const p = card.stopPress;
        const mine = p !== null && p.state === card.status;
        if (s === "refused" && !(mine && p.refusedBefore && card.now - p.at < 3000)) return "refused";
        return mine || s === "stopping" ? "stopping" : "";
    }
    onRunChanged: if (card.stopPress && card.run?.stop?.state === "stopping") card.stopPress = Object.assign({}, card.stopPress, { refusedBefore: false })

    implicitHeight: col.implicitHeight + 28
    radius: 22
    color: card.open ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
         : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, area.containsMouse || card.activeFocus ? 0.93 : 0.955)
    // Tab reaches the card once the host has read the run; Enter or Space opens it, as a click does
    activeFocusOnTab: card.run !== null
    Keys.onReturnPressed: card.opened()
    Keys.onEnterPressed: card.opened()
    Keys.onSpacePressed: card.opened()
    Behavior on color { ColorAnimation { duration: 160 } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: card.run !== null
        cursorShape: card.run !== null ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: card.opened()
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 16; rightMargin: 14 }
        spacing: 12
        Item {
            width: parent.width
            height: 28
            MaterialSymbol { id: glyph; anchors.verticalCenter: parent.verticalCenter; text: "stacks"; iconSize: 17; color: Appearance.colors.colInkSecondary }
            StyledText {
                id: label
                anchors { left: glyph.right; leftMargin: 9; verticalCenter: parent.verticalCenter }
                text: "Workflow"
                font.pixelSize: 14
                color: Appearance.colors.colInkMain
            }
            StyledText {
                anchors { left: label.right; leftMargin: 8; right: right.left; rightMargin: 10; baseline: label.baseline }
                elide: Text.ElideRight
                textFormat: Text.PlainText
                maximumLineCount: 1
                text: card.run?.name ?? card.item?.summary ?? ""
                font.pixelSize: 14
                color: Appearance.colors.colInkSecondary
            }
            Row {
                id: right
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property int done: card.members.filter(m => m.state === "done").length
                    text: [card.members.length ? `${done} of ${card.members.length} agents` : "",
                           card.run?.started ? Words.span((card.status === "running" ? card.now : (card.run.ended || card.run.started)) - card.run.started) : "",
                           card.status === "stopped" ? "stopped" : card.status === "failed" ? "failed" : ""].filter(x => x.length).join(" · ")
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: 13
                    color: Appearance.colors.colInkSecondary
                }
                PillButton {
                    visible: card.canStop && card.status === "running" && (card.run?.task ?? "").length > 0
                    text: card.stopShows === "stopping" ? "Stopping…" : "Stop"
                    onClicked: {
                        if (card.stopShows === "stopping") return;
                        card.stopPress = { state: card.status, at: Date.now(), refusedBefore: card.stopShows === "refused" };
                        card.stopRequested(card.run.task);
                    }
                }
            }
        }
        StyledText {
            visible: card.status === "running" && card.stopShows === "refused"
            width: parent.width
            elide: Text.ElideRight
            text: `Couldn't stop: ${String(card.run?.stop?.message ?? "").split("\n")[0]}`
            font.pixelSize: 13
            color: Appearance.colors.colInkSecondary
        }
        // the phases, in order; a chevron after each pill but the last, so a wrapped line starts on a pill
        Flow {
            visible: card.phases.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: card.phases
                Row {
                    id: phaseRow
                    required property var modelData
                    required property int index
                    readonly property string st: card.phaseStatus(phaseRow.modelData)
                    spacing: 6
                    Rectangle {
                        height: 30
                        radius: 15
                        width: pill.implicitWidth + (phaseRow.st === "waiting" ? 28 : 24)
                        color: phaseRow.st === "done" ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                             : phaseRow.st === "running" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84) : "transparent"
                        border.width: phaseRow.st === "waiting" || phaseRow.st === "stopped" ? 1 : 0
                        border.color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                        Row {
                            id: pill
                            anchors.centerIn: parent
                            spacing: 6
                            LiveDot { visible: phaseRow.st === "running"; anchors.verticalCenter: parent.verticalCenter }
                            MaterialSymbol { visible: phaseRow.st === "done" || phaseRow.st === "failed" || phaseRow.st === "stopped"; anchors.verticalCenter: parent.verticalCenter
                                text: phaseRow.st === "done" ? "check" : phaseRow.st === "failed" ? "close" : "stop"; iconSize: 14
                                color: phaseRow.st === "failed" ? Appearance.colors.colClay : phaseRow.st === "stopped" ? Appearance.colors.colInkSecondary : Appearance.colors.colInkMain }
                            StyledText { text: phaseRow.modelData; font.pixelSize: 13; font.weight: Font.Medium; color: Appearance.colors.colInkMain; anchors.verticalCenter: parent.verticalCenter }
                            StyledText {
                                readonly property var ms: card.members.filter(m => m.phase === phaseRow.modelData)
                                visible: phaseRow.st !== "done" && ms.length > 0
                                text: `${ms.filter(m => m.state === "done").length} of ${ms.length}`
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: 13
                                color: Appearance.colors.colInkSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    MaterialSymbol { visible: phaseRow.index < card.phases.length - 1; anchors.verticalCenter: parent.verticalCenter; text: "chevron_right"; iconSize: 15; color: Appearance.colors.colInkFaint }
                }
            }
        }
    }
}
