import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "ActivityWords.js" as Words

/**
 * One agent (a sub-agent, an agent inside a workflow run, a background command) as one quiet
 * line: how it stands, its name and kind, how long it has run or took and how many steps, and
 * while it runs its newest step under it. Used in the conversation's Agents group and in the
 * side panel's Agents tab. The open one wears the sand wash that marks what is chosen elsewhere
 * in Tacit (the dock's keyboard focus, the palette's verb).
 */
Item {
    id: row
    property string title: ""
    property string kind: ""          // agentType, "workflow", a folder for a command
    property string status: "running"  // running | done | failed | stopped | ended
    property real started: 0
    property real ended: 0
    property int steps: -1            // -1: not counted (a command)
    property var last: null           // { tool, summary, desc }: the newest step, shown while it runs
    property bool open: false
    property bool cursor: false       // the keyboard's row: the hover wash
    property bool chevron: true
    property real now: Date.now()     // ticked by the owner while anything runs
    property int indent: 0
    property real bleed: 6            // how far the wash reaches past the row's sides
    signal clicked()

    readonly property bool running: row.status === "running"
    function join(parts) { return parts.filter(x => x.length).join(" · "); }
    // an end the host never recorded (a call it has no agent for) says nothing, not "0s"
    readonly property string spanText: row.started > 0 && (row.running || row.ended > 0) ? Words.span((row.running ? row.now : row.ended) - row.started) : ""
    readonly property string stepsText: !row.running && row.steps >= 0 ? `${row.steps} ${row.steps === 1 ? "step" : "steps"}` : ""
    readonly property string word: row.status === "stopped" ? "stopped" : row.status === "failed" ? "failed" : ""
    // a command that ended wears the same stop glyph: only "stopped" needs its word
    readonly property bool wordNeeded: row.status === "stopped"
    // narrow: the kind goes first, then the status word (when its glyph says it), then the step
    // count, then the name elides
    readonly property var metas: [row.join([row.spanText, row.stepsText, row.word]),
                                  row.join([row.spanText, row.stepsText, row.wordNeeded ? row.word : ""]),
                                  row.join([row.spanText, row.wordNeeded ? row.word : ""])]
    readonly property real fixed: row.indent + 28 + 16 + (row.chevron ? 20 : 0)
    readonly property int tier: name.implicitWidth + row.fixed + fit0.implicitWidth <= row.width ? 0
        : name.implicitWidth + row.fixed + fit1.implicitWidth <= row.width ? 1 : 2
    // room for the name (worked out here: deriving it from the name's own width looped)
    readonly property real room: row.width - row.indent - 28 - meta.width - 16
    // the kind goes before anything in the meta does
    readonly property bool kindFits: row.kind.length > 0 && name.implicitWidth + 8 + kindText.implicitWidth + row.fixed + fit0.implicitWidth <= row.width
    readonly property bool showStep: row.running && row.last !== null && (row.last?.tool ?? "").length > 0
    readonly property string stepKind: row.showStep ? Words.kind(row.last) : ""
    // the newest step is still going, so it reads as happening ("Running a command"), not done; a file
    // step names its file in the words, the rest show what the agent says it is doing, or the step's
    // own line
    readonly property string stepSays: !row.showStep ? "" : Words.doing(row.stepKind, [row.last])
    readonly property string stepDetail: !row.showStep ? ""
        : row.last.desc ?? (row.stepKind === "read" || row.stepKind === "edit" ? "" : row.last.summary ?? "")

    implicitHeight: row.showStep ? 56 : 38

    // Tab reaches a row that opens; Enter or Space opens it
    activeFocusOnTab: row.chevron
    Keys.onReturnPressed: row.clicked()
    Keys.onEnterPressed: row.clicked()
    Keys.onSpacePressed: row.clicked()

    Rectangle {
        anchors { fill: parent; leftMargin: row.indent - row.bleed; rightMargin: -row.bleed }
        radius: 10
        color: row.open ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
             : area.containsMouse || row.cursor || row.activeFocus ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent"
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    // how it stands: the app's own working indicator in sand while it runs
    Item {
        id: mark
        x: row.indent
        y: 10
        width: 18
        height: 18
        LiveDot { anchors.centerIn: parent; visible: row.running }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: !row.running
            text: row.status === "done" ? "check" : row.status === "failed" ? "close" : "stop"
            iconSize: 16
            color: row.status === "failed" ? Appearance.colors.colClay : Appearance.colors.colInkSecondary
        }
    }
    StyledText {
        id: name
        anchors { left: mark.right; leftMargin: 10; verticalCenter: mark.verticalCenter }
        width: Math.min(implicitWidth, row.room)
        elide: Text.ElideRight
        text: row.title
        font.pixelSize: 15
        font.weight: Font.Medium
        color: Appearance.colors.colInkMain
    }
    StyledText {
        id: kindText
        visible: row.kindFits
        anchors { left: name.right; leftMargin: 8; baseline: name.baseline }
        text: row.kind
        font.pixelSize: 13
        color: Appearance.colors.colInkSecondary
    }
    // the meta as it would read at each step of narrowing, measured, never shown
    StyledText { id: fit0; visible: false; text: row.metas[0]; font.family: Appearance.font.family.numbers; font.pixelSize: 13 }
    StyledText { id: fit1; visible: false; text: row.metas[1]; font.family: Appearance.font.family.numbers; font.pixelSize: 13 }
    Row {
        id: meta
        anchors { right: parent.right; verticalCenter: mark.verticalCenter }
        spacing: 4
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: row.metas[row.tier]
            font.family: Appearance.font.family.numbers
            font.pixelSize: 13
            color: Appearance.colors.colInkSecondary
        }
        MaterialSymbol {
            visible: row.chevron
            anchors.verticalCenter: parent.verticalCenter
            text: "chevron_right"
            iconSize: 16
            color: Appearance.colors.colInkFaint
        }
    }
    // while it runs: its newest step, so the work can be watched without opening it
    Row {
        visible: row.showStep
        anchors { left: name.left; right: parent.right; top: mark.bottom; topMargin: 4 }
        spacing: 6
        clip: true
        MaterialSymbol {
            id: stepGlyph
            anchors.verticalCenter: parent.verticalCenter
            text: row.showStep ? Words.glyph(row.stepKind) : ""
            iconSize: 14
            color: Appearance.colors.colInkMeta
        }
        StyledText {
            id: stepWords
            text: row.stepSays
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Appearance.colors.colInkSecondary
        }
        StyledText {
            visible: text.length > 0
            width: Math.max(0, parent.width - stepGlyph.width - stepWords.width - 12)
            elide: Text.ElideRight
            text: row.stepDetail
            font.pixelSize: 13
            color: Appearance.colors.colInkSecondary
        }
    }
    MouseArea {
        id: area
        anchors { fill: parent; leftMargin: row.indent - row.bleed; rightMargin: -row.bleed }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
