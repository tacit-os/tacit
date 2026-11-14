import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

ColumnLayout {
    id: strip

    required property var files
    signal previewRequested(var file)
    signal saveRequested(var files)

    readonly property var t: K.Kit.tokens
    readonly property string attachmentHelp: qsTr("Click or press Space to download. Double-click or press Enter to preview.")
    spacing: chips.spacing

    RowLayout {
        Layout.fillWidth: true
        spacing: strip.t.space.m

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: countLabel.implicitHeight

            K.TacitText {
                id: actionBaseline
                visible: false
                anchors.verticalCenter: parent.verticalCenter
                text: downloadAll.text
            }

            K.TacitText {
                id: countLabel
                y: downloadAll.visible
                    ? actionBaseline.y + actionBaseline.baselineOffset - baselineOffset
                    : (parent.height - height) / 2
                size: "meta"
                ink: "faint"
                text: strip.files.length === 1 ? qsTr("1 attachment")
                    : qsTr("%1 attachments").arg(strip.files.length)
            }
        }

        MailAction {
            id: downloadAll
            visible: strip.files.length > 1
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: strip.t.space.m
            text: qsTr("Download all")
            onActivated: strip.saveRequested(strip.files)
        }
    }

    Flow {
        id: chips

        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: strip.t.space.s

        // Flow packs the natural widths first. Justify every row except the last.
        readonly property var rowOffsets: {
            const offsets = [];
            let start = 0;
            while (start < attachments.count) {
                const first = attachments.itemAt(start);
                if (!first)
                    break;
                let end = start;
                let last = first;
                while (end + 1 < attachments.count) {
                    const next = attachments.itemAt(end + 1);
                    if (!next || next.y !== first.y)
                        break;
                    last = next;
                    ++end;
                }
                if (end === attachments.count - 1)
                    break;
                const slack = Math.max(0, chips.width - last.x - last.width);
                for (let i = start; i <= end; ++i)
                    offsets[i] = end === start ? 0 : slack * (i - start) / (end - start);
                start = end + 1;
            }
            return offsets;
        }

        Repeater {
            id: attachments
            model: strip.files

            Rectangle {
                id: chip

                required property var modelData
                required property int index
                readonly property string fileName: modelData.name

                objectName: "attachment-" + modelData.id
                width: Math.min(chips.width, fileLabel.implicitWidth + 2 * strip.t.space.m)
                height: strip.t.height.field
                radius: height / 2
                color: Qt.alpha(strip.t.inkMain, pointer.pressed ? strip.t.wash.pressed
                    : pointer.containsMouse ? strip.t.wash.hover : strip.t.wash.action)
                activeFocusOnTab: true

                Accessible.role: Accessible.Button
                Accessible.name: fileName
                Accessible.description: strip.attachmentHelp
                Accessible.onPressAction: strip.saveRequested([modelData])

                transform: Translate {
                    x: chips.rowOffsets[chip.index] ?? 0
                }

                K.Tooltip {
                    shown: !pointer.pressed && !downloadDelay.running
                        && (pointer.containsMouse || (chip.activeFocus && K.Kit.focusVisible))
                    text: strip.attachmentHelp
                }

                Behavior on color {
                    ColorAnimation { duration: K.Kit.ms(strip.t.motion.hover.ms) }
                }

                K.FocusRing {
                    shown: chip.activeFocus && K.Kit.focusVisible
                    corner: chip.radius
                }

                K.TacitText {
                    id: fileLabel
                    anchors.fill: parent
                    anchors.leftMargin: strip.t.space.m
                    anchors.rightMargin: strip.t.space.m
                    verticalAlignment: Text.AlignVCenter
                    text: chip.modelData.name
                    ink: "sec"
                    elide: Text.ElideMiddle
                    Accessible.ignored: true
                }

                Timer {
                    id: downloadDelay
                    interval: Qt.styleHints.mouseDoubleClickInterval
                    onTriggered: strip.saveRequested([chip.modelData])
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        K.Kit.focusVisible = false;
                        chip.forceActiveFocus(Qt.MouseFocusReason);
                        downloadDelay.restart();
                    }
                    onDoubleClicked: {
                        downloadDelay.stop();
                        strip.previewRequested(chip.modelData);
                    }
                }

                Keys.onPressed: event => {
                    K.Kit.focusVisible = true;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        strip.previewRequested(chip.modelData);
                    else if (event.key === Qt.Key_Space)
                        strip.saveRequested([chip.modelData]);
                    else
                        return;
                    event.accepted = true;
                }
            }
        }
    }
}
