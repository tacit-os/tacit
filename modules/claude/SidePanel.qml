import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The Claude app's third column: Results and Agents (AgentsPane: what the agents found; sub-agents,
 * workflow runs, background commands) and Files (what the session touched, the project, a read-only
 * viewer). The review (ChangesPanel; Made for a session outside a git repository that only made new
 * files) opens from Results and from the conversation, with a way back to Results. Drag its left
 * edge to widen it; the width is remembered. Results and Agents are offered once the session has run
 * (a new one has nothing in them yet).
 */
Item {
    id: side

    property var changes: ({ files: [], add: 0, del: 0 })
    property var items: []
    property string cwd: ""
    property string sessionId: ""
    property bool fresh: false
    property bool locked: false
    property string tab: "files"      // results | agents | files | review
    property var host: null
    property var agentsInfo: null
    property bool canStop: false
    property real clock: Date.now()
    signal stopRequested(string task)
    property real maxWidth: 900
    property bool over: false          // opened over the conversation (no room beside it)
    property color base: "transparent"  // the window's ground, solid under the panel when it is over
    signal closeRequested()
    signal showRequested()
    property var sendFn: null           // the review's comments go through the conversation's send
    property string agentName: "Claude Code"
    signal attachRequested(string path)   // Made: a file for the next message
    signal pictureRequested(string path)  // Agents: a step's picture, in the window's viewer
    signal restartHostRequested()         // Results: the background service has no Results

    readonly property alias review: reviewPanel
    readonly property alias files: filesPane
    readonly property var tabs: side.fresh ? [{ key: "files", label: "Files" }]
        : [{ key: "results", label: "Results" }, { key: "agents", label: "Agents" }, { key: "files", label: "Files" }]
    readonly property alias agents: agentsPane
    function openAgent(id) { side.tab = "agents"; agentsPane.openAgent(id); side.showRequested(); }
    function openRun(run) { side.tab = "agents"; agentsPane.openRun(run); side.showRequested(); }
    readonly property string shownTab: side.fresh ? "files" : side.tab

    // a file at a line (or at the first line holding `find`), from the conversation or Review
    function openFile(path, line, find) {
        side.tab = "files";
        filesPane.open(path, line, find);
        side.showRequested();
    }

    // Beside the conversation the panel stands on the window's own ground, the same as the
    // conversation, with one hairline between them: a tone of its own read as grey, and near-black as
    // a hole in the window. Over the conversation (no room beside it) it is a plain slab in the
    // window's material, with a hairline where it meets the conversation.
    Rectangle {
        visible: side.over
        anchors.fill: parent
        color: side.base
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
        }
    }
    Rectangle {
        visible: !side.over
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 19; bottomMargin: 19 }
        width: 1
        color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
    }

    // ── width: dragged, remembered ─────────────────────────────────────────
    FileView {
        id: widthFile
        path: `${Directories.state}/user/claude-panel-width.txt`
        blockLoading: true
        printErrors: false
    }
    property real chosenWidth: Number((widthFile.text() || "420").trim()) || 420
    // a file on the Agents trail gets room for its diffs; Back gives it back
    readonly property bool wide: (side.shownTab === "agents" || side.shownTab === "results") && agentsPane.wantsWide
    property real wideBy: side.wide ? Math.max(0, 640 - side.chosenWidth) : 0
    // not while the edge is dragged: eased, it swung the edge out past the pointer and back
    Behavior on wideBy { enabled: !grip.pressed; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    implicitWidth: Math.max(320, Math.min(side.chosenWidth + side.wideBy, side.maxWidth))

    MouseArea {
        id: grip
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: -3 }
        width: 7
        z: 10
        hoverEnabled: true
        cursorShape: Qt.SplitHCursor
        property real startX: 0
        property real startWidth: 0
        property real startChosen: 0
        onPressed: m => { startX = mapToGlobal(m.x, 0).x; startWidth = side.implicitWidth; startChosen = side.chosenWidth; }
        // while a file page holds the panel at 640, only a width past that is yours: dragged no wider, it stays as you had it
        onPositionChanged: m => {
            if (!pressed) return;
            const w = Math.max(320, Math.min(side.maxWidth, startWidth - (mapToGlobal(m.x, 0).x - startX)));
            side.chosenWidth = side.wide && w <= 640 ? Math.min(startChosen, 640) : w;
        }
        onReleased: widthFile.setText(Math.round(side.chosenWidth) + "\n")
    }
    Rectangle {   // where to drag: shown only while the grip is hovered or held
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 40; bottomMargin: 40 }
        width: 2
        radius: 1
        color: Appearance.colors.colPrimary
        opacity: grip.pressed ? 0.8 : grip.containsMouse ? 0.5 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    FilesPane {
        id: filesPane
        anchors { fill: parent; topMargin: 19; bottomMargin: 19 }
        visible: side.shownTab === "files"
        cwd: side.cwd
        sessionId: side.sessionId
        items: side.items
        changes: side.changes
        tabs: side.tabs
        onTabPicked: key => side.tab = key
        onCloseRequested: side.closeRequested()
    }

    AgentsPane {
        id: agentsPane
        anchors { fill: parent; topMargin: 19; bottomMargin: 19 }
        visible: side.shownTab === "agents" || side.shownTab === "results"
        root: side.shownTab === "results" ? "results" : "agents"
        host: side.host
        sessionId: side.sessionId
        info: side.agentsInfo
        files: side
        cwd: side.cwd
        canStop: side.canStop
        now: side.clock
        tabs: side.tabs
        onTabPicked: key => side.tab = key
        onCloseRequested: side.closeRequested()
        onStopRequested: task => side.stopRequested(task)
        onPictureRequested: p => side.pictureRequested(p)
        onRestartHostRequested: side.restartHostRequested()
        onReviewRequested: { reviewPanel.showTurn(null); side.tab = "review"; }
    }
    ChangesPanel {
        id: reviewPanel
        anchors { fill: parent; topMargin: 19; bottomMargin: 19 }
        visible: side.shownTab === "review"
        changes: side.changes
        items: side.items
        locked: side.locked
        sessionId: side.sessionId
        cwd: side.cwd
        tabs: side.tabs
        backLabel: side.fresh ? "" : "Results"
        onBackRequested: side.tab = "results"
        onTabPicked: key => side.tab = key
        onOpenRequested: (abs, line) => side.openFile(abs, line, "")
        sendFn: side.sendFn
        agentName: side.agentName
        onAttachRequested: path => side.attachRequested(path)
        onCloseRequested: side.closeRequested()
    }
}
