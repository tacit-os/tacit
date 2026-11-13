import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "ActivityWords.js" as Words

// A turn's steps between two pieces of prose, as plain lines by kind: "Ran 4 commands",
// "Edited notes.txt", "Read 5 files" (how Claude Desktop and ChatGPT show work). A line opens to
// its steps, commands and diffs as ToolLine and ThinkingLine draw them. While the agent works,
// the last line carries the ring and names the step it is on.
Item {
    id: group
    property var tools: []
    // Which lines are open is the conversation's to keep (by their first step's id): the group
    // is rebuilt whenever the turn updates.
    property var openIds: null
    property var selfOpen: ({})       // lines whose steps carry no ids
    signal toggled(string key)
    property bool runningLast: false   // the group's last step is the one running now
    property var runningIds: []        // or: the steps running now, by id (several can run at once)
    property bool asking: false        // ...and it waits for your answer (a permission or question card)
    property var viewer: null
    property var files: null
    property bool calm: false          // true: sand and meta (ToolLine, DiffView); the owner's choice is green and red

    // consecutive steps of one kind make one line, and a thought is a line of its own between them. Riding
    // inside the next command line was fine while thoughts came empty; with their words (2026-10-09) the
    // reasoning sat inside "Ran 2 commands" (owner: "why everything under ran commands").
    readonly property var lines: {
        const out = [];
        for (const it of group.tools) {
            const last = out[out.length - 1];
            const k = it.kind === "thinking" ? "think" : Words.kind(it);
            if (last && last.k === k) last.steps.push(it);
            else out.push({ k: k, steps: [it] });
        }
        return out.map((l, i) => Object.assign(l, {
            key: (l.steps[0].id ?? "").length ? `line:${l.steps[0].id}` : `line#${i}`,
            // a denied or failed edit changed nothing
            add: l.steps.reduce((a, s) => a + (s.error === true ? 0 : (s.files ?? []).reduce((b, f) => b + (f.add ?? 0), 0)), 0),
            del: l.steps.reduce((a, s) => a + (s.error === true ? 0 : (s.files ?? []).reduce((b, f) => b + (f.del ?? 0), 0)), 0),
            error: l.steps.some(s => s.error === true),
            failed: l.steps.filter(s => s.error === true).length
        }));
    }
    function isOpen(key) { return group.openIds && !key.startsWith("line#") ? group.openIds[key] === true : group.selfOpen[key] === true; }
    function toggle(key) {
        if (group.openIds && !key.startsWith("line#")) group.toggled(key);
        else group.selfOpen = Object.assign({}, group.selfOpen, { [key]: !group.selfOpen[key] });
    }

    // no animation of its own: each line opens on its own progress, and the group's height follows
    implicitHeight: col.implicitHeight + 4

    Column {
        id: col
        width: parent.width
        Repeater {
            model: group.lines
            delegate: Column {
                id: lineCol
                required property var modelData
                required property int index
                readonly property bool open: group.isOpen(modelData.key)
                // opening and closing, as a tool line does: height, clip and fade on one value
                property real progress: open ? 1 : 0
                Behavior on progress { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                readonly property bool shown: progress > 0
                readonly property var running: group.runningIds.length ? modelData.steps.filter(s => group.runningIds.includes(s.id)) : []
                readonly property bool live: (group.runningLast && index === group.lines.length - 1) || running.length > 0
                // the step it is on: the newest still running, else the newest
                readonly property var now: running.length ? running[running.length - 1] : modelData.steps[modelData.steps.length - 1]
                width: col.width

                Item {
                    id: lineRow
                    width: parent.width
                    height: 32
                    HoverHandler { id: hov }
                    activeFocusOnTab: true
                    Keys.onReturnPressed: group.toggle(lineCol.modelData.key)
                    Keys.onEnterPressed: group.toggle(lineCol.modelData.key)
                    Keys.onSpacePressed: group.toggle(lineCol.modelData.key)
                    Rectangle {
                        anchors { fill: parent; leftMargin: -6; rightMargin: -6 }
                        radius: Appearance.rounding.small
                        color: hov.hovered || lineRow.activeFocus ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent"
                    }
                    MaterialSymbol {
                        id: mark
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        visible: !lineCol.live
                        text: hov.hovered || lineRow.activeFocus || lineCol.open ? (lineCol.open ? "expand_more" : "chevron_right") : (lineCol.modelData.error ? "error" : Words.glyph(lineCol.modelData.k))
                        iconSize: 17
                        color: lineCol.modelData.error && !hov.hovered && !lineRow.activeFocus ? Appearance.colors.colClay : Appearance.colors.colInkSecondary
                    }
                    LiveDot { anchors.centerIn: mark; visible: lineCol.live }
                    StyledText {
                        id: says
                        anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
                        // a failed or denied step is said, not only marked: its details are folded
                        text: !lineCol.live ? Words.says(lineCol.modelData.k, lineCol.modelData.steps) + (lineCol.modelData.failed > 0 ? ` · ${lineCol.modelData.failed} failed` : "")
                            : group.asking ? "Waiting for you" : Words.doing(lineCol.modelData.k, lineCol.modelData.steps)
                        font.pixelSize: 14
                        color: lineCol.live ? Appearance.colors.colInkMain : Appearance.colors.colInkMeta
                    }
                    Row {
                        id: counts
                        anchors { left: says.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        visible: lineCol.modelData.k === "edit" && (lineCol.modelData.add + lineCol.modelData.del) > 0
                        StyledText { text: `+${lineCol.modelData.add}`; visible: lineCol.modelData.add > 0; font.family: Appearance.font.family.numbers; font.pixelSize: 14; color: group.calm ? Appearance.colors.colPrimary : Appearance.m3colors.m3success }
                        StyledText { text: `−${lineCol.modelData.del}`; visible: lineCol.modelData.del > 0; font.family: Appearance.font.family.numbers; font.pixelSize: 14; color: group.calm ? Appearance.colors.colInkMeta : Appearance.colors.colError }
                    }
                    // the step it is on, while it works; a thought's first words, as ThinkingLine has them. With
                    // "Thought" alone on its row, the reply under it read as the thought's own text (owner
                    // 2026-10-08: "replies leaking in reasoning")
                    readonly property bool thought: lineCol.modelData.k === "think" && !lineCol.live
                    StyledText {
                        anchors { left: counts.visible ? counts.right : says.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: (lineCol.live || parent.thought) && text.length > 0 && !lineCol.open
                        elide: Text.ElideRight
                        text: lineCol.now.kind === "thinking" ? (parent.thought ? (lineCol.now.text ?? "").replace(/\s+/g, " ").trim() : "")
                            : (lineCol.now.desc ?? lineCol.now.summary ?? "")
                        // a command or a thought, never markup: as rich text a "<h1>" in a grep spilled over the rows around (as ToolLine)
                        textFormat: Text.PlainText
                        font.pixelSize: 14
                        color: parent.thought ? Appearance.colors.colInkMeta : Appearance.colors.colInkSecondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: group.toggle(lineCol.modelData.key)
                    }
                }
                // the steps themselves, under a hairline, when the line is open
                Item {
                    visible: lineCol.shown
                    clip: lineCol.progress < 1
                    opacity: lineCol.progress
                    width: parent.width
                    height: (steps.implicitHeight + 4) * lineCol.progress
                    Rectangle {
                        anchors { left: parent.left; leftMargin: 7; top: parent.top; topMargin: 1; bottom: parent.bottom }
                        width: 1
                        color: Appearance.m3colors.m3outlineVariant
                    }
                    Column {
                        id: steps
                        anchors { left: parent.left; leftMargin: 19; right: parent.right }
                        Repeater {
                            model: lineCol.shown ? lineCol.modelData.steps : []
                            delegate: Loader {
                                required property var modelData
                                required property int index
                                width: steps.width
                                sourceComponent: modelData.kind === "thinking" ? thinkStep : toolStep
                                Component { id: thinkStep; ThinkingLine { text: modelData.text; bare: lineCol.modelData.k === "think"; openIds: group.openIds; onToggled: key => group.toggled(key) } }
                                Component { id: toolStep; ToolLine { item: modelData; openIds: group.openIds; onToggled: key => group.toggled(key); viewer: group.viewer; files: group.files; calm: group.calm; running: lineCol.live && (group.runningIds.length ? group.runningIds.includes(modelData.id) : index === lineCol.modelData.steps.length - 1) } }
                            }
                        }
                    }
                }
            }
        }
    }
}
