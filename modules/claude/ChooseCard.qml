import QtQuick
import QtQuick.Controls
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The agent asks you to pick among files or folders (the host's choose tool): the paths as setup's rings, one or
 * several, your own words in a soft well, then the verb it gave ("Move 2"). "None of these" answers that nothing
 * fits; "Leave it to the agent" declines, and it decides and says what it chose. Drawn as QuestionCard is.
 */
Rectangle {
    id: card
    property var pending: ({})        // { request, tool: "Choose", input: { question, items, header, multiSelect, verb } }
    property var picked: []           // the paths ticked
    // the most the card may take; past it the paths scroll and the actions stay in view
    property real maxHeight: 100000
    signal answered(var input)        // { chosen, note, none }
    signal declined()
    // the first card waiting answers to the keys the box hands it while nothing is typed there (Composer.cardKey),
    // the set every card has: 1-9 ticks a path, Enter answers, Esc leaves it to the agent
    property bool keys: false
    readonly property bool keysOn: card.keys && card.visible && !card.sent
    function key(k) {
        if (!card.keysOn) return false;
        if (k === "enter") { if (card.picked.length) card.submit(false); return true; }
        if (k === "esc") { card.sent = true; card.declined(); return true; }
        const p = card.items[k - 1];
        if (p === undefined) return false;
        card.toggle(p);
        return true;
    }

    // Half an answer, kept by the conversation while another session is open (the card is made anew on the way back,
    // and its ticks and note went): `half` is what to keep, `kept` what was kept, put back once made.
    readonly property var half: ({ picked: card.picked, note: other.text })
    property var kept: null
    Component.onCompleted: if (card.kept) {
        card.picked = (card.kept.picked ?? []).filter(p => card.items.includes(p));
        other.text = card.kept.note ?? "";
    }

    readonly property var items: card.pending.input?.items ?? []
    readonly property bool multi: card.pending.input?.multiSelect ?? true
    readonly property string verb: card.pending.input?.verb ?? ""
    // answered: the card stays until the host takes the request away; a second click answered a closed request
    property bool sent: false
    opacity: card.sent ? 0.6 : 1
    // still here well after the answer (it did not reach the host): it can be answered again
    Timer { running: card.sent; interval: 5000; onTriggered: card.sent = false }
    enabled: !card.sent

    function home(p) {
        const h = Quickshell.env("HOME");
        return p.startsWith(h + "/") ? "~" + p.substring(h.length) : p;
    }
    function toggle(path) {
        card.picked = card.multi ? (card.picked.includes(path) ? card.picked.filter(p => p !== path) : card.picked.concat([path])) : [path];
    }
    function submit(none) {
        card.sent = true;
        const chosen = none ? [] : card.items.filter(p => card.picked.includes(p));
        card.answered({ chosen: chosen, note: other.text.trim(), none: none });
    }

    readonly property int pad: 24
    implicitHeight: column.implicitHeight + 2 * card.pad
    radius: Appearance.rounding.card
    // as the composer: on the window's frost with a hairline, where the inks keep their contrast
    color: "transparent"
    border.width: 1
    border.color: Appearance.colors.colInkDivider

    Column {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: card.pad }
        spacing: 16
        StyledText {
            text: card.pending.input?.header || "Choose"
            font.pixelSize: Tacit.size.row
            font.weight: Font.Medium
            color: Tacit.inkSec
        }
        StyledText {
            width: parent.width
            text: card.pending.input?.question ?? ""
            wrapMode: Text.Wrap
            font.pixelSize: Tacit.size.section
            font.weight: Font.Medium
            color: Tacit.inkMain
        }
        Flickable {
            id: body
            width: parent.width
            height: Math.min(rows.implicitHeight, Math.max(120, card.maxHeight - 280))
            contentHeight: rows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: StyledScrollBar {}
            Column {
                id: rows
                width: body.width
                spacing: 12
                Repeater {
                    model: card.items
                    // setup's Choice: a ring, the chosen one with a dot of the accent
                    delegate: Item {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property bool on: card.picked.includes(row.modelData)
                        readonly property string rel: card.home(row.modelData)
                        readonly property int cut: row.rel.replace(/\/+$/, "").lastIndexOf("/")
                        width: rows.width
                        height: 24
                        Rectangle {
                            y: 2
                            width: 20; height: 20
                            radius: card.multi ? 6 : 10
                            color: "transparent"
                            border.width: 1
                            border.color: row.on ? ColorUtils.transparentize(Tacit.accent, 0.15) : ColorUtils.transparentize(Tacit.inkMain, rowArea.containsMouse ? 0.35 : 0.55)
                            Behavior on border.color { ColorAnimation { duration: 140 } }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 10; height: 10
                                radius: card.multi ? 3 : 5
                                color: Tacit.accent
                                scale: row.on ? 1 : 0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }
                        // the name in full tone, its folder quiet beside it
                        StyledText {
                            id: name
                            x: 36
                            width: Math.min(implicitWidth, row.width - 36)
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.rel.replace(/\/+$/, "").substring(row.cut + 1)
                            elide: Text.ElideMiddle
                            font.pixelSize: Tacit.size.body
                            color: Tacit.inkMain
                        }
                        StyledText {
                            anchors { left: name.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
                            text: row.cut > 0 ? row.rel.substring(0, row.cut) : ""
                            elide: Text.ElideLeft
                            font.pixelSize: Tacit.size.meta
                            color: Tacit.inkMeta
                        }
                        MouseArea {
                            id: rowArea
                            anchors { fill: parent; margins: -6 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.toggle(row.modelData)
                        }
                    }
                }
            }
        }
        // your own words: a field on the paths' edge
        Rectangle {
            x: 36
            width: parent.width - 36
            height: 44
            radius: Tacit.radius.slab
            color: "transparent"
            border.width: 1
            border.color: other.activeFocus ? ColorUtils.mix(Appearance.colors.colInkDivider, Appearance.colors.colInkFaint, 0.3)
                : otherArea.containsMouse ? ColorUtils.mix(Appearance.colors.colInkDivider, Appearance.colors.colInkFaint, 0.12) : Appearance.colors.colInkDivider
            Behavior on border.color { ColorAnimation { duration: 160 } }
            TextInput {
                // as StyledText: letters as designed, nothing snapped
                font.hintingPreference: Font.PreferNoHinting
                id: other
                anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16; verticalCenter: parent.verticalCenter }
                font.family: Appearance.font.family.main
                font.pixelSize: Tacit.size.row
                color: Tacit.inkMain
                selectionColor: ColorUtils.transparentize(Tacit.accent, 0.6)
                clip: true
                Keys.onReturnPressed: if (card.picked.length) card.submit(false)
            }
            StyledText {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                visible: other.text.length === 0
                text: "Add a note…"
                font.pixelSize: Tacit.size.row
                color: Tacit.inkMeta
            }
            MouseArea {
                id: otherArea
                anchors.fill: parent
                visible: !other.activeFocus
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                onClicked: other.forceActiveFocus()
            }
        }
        // the agent decides as words; the way forward, the one ring, on the right
        Item {
            width: parent.width
            height: forward.implicitHeight
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Leave it to the agent"
                font.pixelSize: Tacit.size.row
                color: leaveArea.containsMouse ? Tacit.inkMain : Tacit.inkSec
                MouseArea { id: leaveArea; anchors { fill: parent; margins: -8 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { card.sent = true; card.declined(); } }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 24
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "None of these"
                    font.pixelSize: Tacit.size.row
                    color: noneArea.containsMouse ? Tacit.inkMain : Tacit.inkSec
                    MouseArea { id: noneArea; anchors { fill: parent; margins: -8 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.submit(true) }
                }
                Slab {
                    id: forward
                    width: Math.max(104, implicitWidth)
                    text: (card.verb || "Choose") + (card.multi && card.picked.length > 1 ? ` ${card.picked.length}` : "")
                    tone: card.picked.length ? "default" : ""
                    onPicked: if (card.picked.length) card.submit(false)
                }
            }
        }
    }
}
