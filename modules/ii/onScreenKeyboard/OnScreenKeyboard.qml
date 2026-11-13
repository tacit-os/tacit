import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.osk.pinnedOnStartup ?? false

    // SidebarRightContent.qml's TextAction. The keyboard's Pin and Hide are the same actions as
    // before (Pin on press, Hide on click).
    component OskTextAction: RippleButton {
        id: taction
        property string glyph: ""
        property string label: ""
        property bool on: false
        implicitWidth: tactionRow.implicitWidth + 20
        implicitHeight: 32
        buttonRadius: 16
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        contentItem: Row {
            id: tactionRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: taction.glyph
                fill: taction.on ? 1 : 0
                iconSize: 18
                color: taction.on ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: taction.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    Loader {
        id: oskLoader
        // Torn down on lock, not just hidden: a latched Shift or Ctrl is physically held through
        // ydotool until the release below runs, so it would outlive the window and reach the
        // password field. Going away also clears the keys' own latch marks.
        active: GlobalStates.oskOpen && !GlobalStates.screenLocked
        onActiveChanged: {
            if (!oskLoader.active) {
                Ydotool.releaseAllKeys();
            }
        }
        
        sourceComponent: PanelWindow { // Window
            id: oskRoot
            visible: oskLoader.active

            anchors {
                bottom: true
                left: true
                right: true
            }

            function hide() {
                GlobalStates.oskOpen = false
            }
            // Docked flush into the bottom edge like the palette (SearchWidget.qml), coves 12 px.
            readonly property int dockCornerSize: 12
            exclusiveZone: root.pinned ? implicitHeight : 0
            implicitWidth: oskBackground.width + dockCornerSize * 2
            implicitHeight: oskBackground.height
            WlrLayershell.namespace: "quickshell:osk"
            WlrLayershell.layer: WlrLayer.Overlay
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item: oskDock
            }

            // Make it usable with other panels
            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(oskRoot);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(oskRoot);
            }

            // The coves reach dockCornerSize past the body on both flanks, so the input mask is
            // that wider box.
            Item {
                id: oskDock
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                }
                width: oskBackground.width + oskRoot.dockCornerSize * 2
                height: oskBackground.height

                DockedRect {
                    anchors.fill: oskBackground
                    edge: "bottom"
                    cornerRadius: Appearance.rounding.verylarge
                    fillet: oskRoot.dockCornerSize
                    color: Appearance.colors.colPanelFrost
                }
                Item {
                    id: oskBackground
                    x: oskRoot.dockCornerSize
                    readonly property real padding: 14
                    implicitWidth: oskContent.implicitWidth + padding * 2
                    implicitHeight: 62 + oskContent.implicitHeight
                    width: implicitWidth
                    height: implicitHeight

                    // The notch's 34 px strip (IslandHeader.qml) carrying Pin and Hide.
                    RowLayout {
                        x: 16
                        y: 4
                        width: parent.width - 32
                        height: 34
                        spacing: 6
                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Keyboard")
                            font.pixelSize: 15
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: oskContent.heading
                            font.pixelSize: 14
                            color: Appearance.colors.colSubtext
                        }
                        OskTextAction {
                            glyph: "keep"
                            label: Translation.tr("Pin")
                            on: root.pinned
                            downAction: () => root.pinned = !root.pinned
                        }
                        OskTextAction {
                            glyph: "keyboard_hide"
                            label: Translation.tr("Hide")
                            onClicked: () => {
                                oskRoot.hide()
                            }
                        }
                    }
                    Rectangle {
                        x: oskBackground.padding
                        y: 38
                        width: parent.width - oskBackground.padding * 2
                        height: 1
                        color: Appearance.colors.colLayer0Border
                    }
                    OskContent {
                        id: oskContent
                        x: oskBackground.padding
                        y: 44
                    }
                }
            }

        }
    }

    IpcHandler {
        target: "osk"

        function toggle(): void {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }

        function close(): void {
            GlobalStates.oskOpen = false
        }

        function open(): void {
            GlobalStates.oskOpen = true
        }
    }

    CompositorGlobalShortcut {
        name: "oskToggle"
        description: "Toggles on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "oskOpen"
        description: "Opens on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = true
        }
    }

    CompositorGlobalShortcut {
        name: "oskClose"
        description: "Closes on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = false
        }
    }

}
