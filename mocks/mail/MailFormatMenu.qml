import QtQuick
import QtQuick.Controls
import Tacit.Kit as K

Item {
    id: button

    required property var formats
    required property string text
    readonly property bool hasFormat: formats.some(format => format.current === true)
    signal formatPicked(var format)
    readonly property var t: K.Kit.tokens
    implicitWidth: caption.implicitWidth + 2 * t.space.m
    implicitHeight: t.height.field
    width: implicitWidth
    height: implicitHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.ButtonMenu
    Accessible.name: text
    Accessible.onPressAction: choices.open()

    Rectangle {
        anchors.fill: parent
        radius: button.t.radius.slab
        color: button.t.inkMain
        opacity: button.hasFormat
            ? (choices.opened || triggerHover.hovered ? button.t.wash.currentHover : button.t.wash.current)
            : (choices.opened || triggerHover.hovered ? button.t.wash.hover : 0)
    }
    Row {
        id: caption
        anchors.centerIn: parent
        spacing: button.t.space.xs
        K.TacitText {
            text: button.text
            ink: button.hasFormat ? "accent" : "sec"
        }
        K.Symbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "expand_more"
            size: button.t.icon.rail
            color: button.hasFormat ? button.t.accent : button.t.inkSec
        }
    }
    K.FocusRing { shown: button.activeFocus && K.Kit.focusVisible }
    HoverHandler { id: triggerHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: choices.open() }
    Keys.onPressed: event => {
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Down].includes(event.key)) {
            K.Kit.focusVisible = true;
            choices.open();
            event.accepted = true;
        }
    }

    Popup {
        id: choices
        y: button.height + button.t.space.xs
        width: button.t.width.rail
        padding: button.t.space.s
        focus: true
        modal: true
        dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: rows.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
        background: Rectangle {
            radius: button.t.radius.panel
            color: button.t.windowGround
            border.color: button.t.hairline

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
        }

        contentItem: Column {
            id: rows

            Repeater {
                model: button.formats

                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool separator: modelData.rule === true
                    width: rows.width
                    implicitWidth: sample.implicitWidth + 2 * button.t.space.m
                    height: separator ? button.t.space.s : Math.max(button.t.height.menuRow,
                        sample.implicitHeight + button.t.space.s)
                    activeFocusOnTab: !separator
                    Accessible.role: separator ? Accessible.Separator : Accessible.MenuItem
                    Accessible.name: modelData.label ?? ""
                    Accessible.checkable: modelData.current !== undefined
                    Accessible.checked: modelData.current === true
                    Accessible.onPressAction: pick()

                    function pick() {
                        if (separator)
                            return;
                        choices.close();
                        button.formatPicked(modelData);
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: button.t.radius.row
                        color: button.t.inkMain
                        opacity: pointer.hovered && !row.separator ? button.t.wash.hover : 0
                    }
                    Rectangle {
                        visible: row.separator
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 1
                        color: button.t.hairline
                    }
                    K.FocusRing { shown: row.activeFocus && K.Kit.focusVisible }
                    Rectangle {
                        visible: row.modelData.current === true
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: button.t.space.l
                        color: button.t.accent
                        Accessible.ignored: true
                    }

                    Rectangle {
                        anchors.fill: sample
                        visible: row.modelData.action === "highlight"
                        color: visible ? row.modelData.value : "transparent"
                    }
                    K.TacitText {
                        id: sample
                        x: button.t.space.m
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.separator
                        text: row.modelData.label ?? ""
                        textFormat: Text.PlainText
                        font.family: row.modelData.action === "font" ? row.modelData.value : button.t.font.main
                        font.pixelSize: row.modelData.action === "size"
                            ? Math.round(Number(row.modelData.value) * 96 / 72) : button.t.size.row
                        font.underline: row.modelData.action === "underline"
                        font.strikeout: row.modelData.action === "strike"
                        color: row.modelData.action === "color" ? row.modelData.value
                            : row.modelData.action === "highlight" ? button.t.inkOnAccent : button.t.inkMain
                        Accessible.ignored: true
                    }
                    HoverHandler { id: pointer; enabled: !row.separator; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton)
                                row.pick();
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            row.pick();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                            K.Kit.focusVisible = true;
                            row.nextItemInFocusChain(event.key === Qt.Key_Down).forceActiveFocus(Qt.TabFocusReason);
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
