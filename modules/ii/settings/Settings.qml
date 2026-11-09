//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Scope {
    id: root

    readonly property real sizeScale: Config.options.settings.style === "minimal" ? 0.75 : 1.0

    Component.onCompleted: {
        GlobalStates.settingsOpen = false;
    }

    // The whole window tree is only worth its RAM while the legacy panel is open
    // (shortcut: the first open skips the fade, because the loader builds it already visible).
    LazyLoader {
        active: GlobalStates.settingsOpen

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.settingsOpen

        function hide() {
            GlobalStates.settingsOpen = false;
        }

        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
                settingsWindow.userMoved = false;
                Qt.callLater(() => settingsWindow.forceActiveFocus());
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            opacity: GlobalStates.settingsOpen ? 1 : 0
            z: 0
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: false
                onClicked: panelWindow.hide()
            }
        }

        Rectangle {
            id: settingsWindow
            width: Config.options.settings.style === "minimal" ? Math.min(parent.width - 70, 980 * sizeScale) : Math.min(parent.width - 80, 980 * sizeScale)
            height: Math.min(parent.height - 80, 665 * sizeScale)
            color: Appearance.colors.colLayer0
            border.width: Config.options.settings.borderSize
            border.color: Appearance.getColorFromName(Config.options.settings.borderColor)
            radius: Appearance.rounding.windowRounding
            z: 1

            property bool userMoved: false
            anchors.centerIn: userMoved ? undefined : parent

            // Escape, Tab and the arrow keys below are handled here, so this is what has to hold
            // focus while the panel is up.
            focus: true

            opacity: GlobalStates.settingsOpen ? 1 : 0
            scale: GlobalStates.settingsOpen ? 1 : 0.95

            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Keys.onTabPressed: (event) => {
            const count = settingsContent.pages.length;
            settingsContent.currentPage = (settingsContent.currentPage + 1) % count;
            settingsContent.showingProfile = false;
            event.accepted = true;
        }

        Keys.onBacktabPressed: (event) => {
            const count = settingsContent.pages.length;
            settingsContent.currentPage = (settingsContent.currentPage - 1 + count) % count;
            settingsContent.showingProfile = false;
            event.accepted = true;
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panelWindow.hide();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                const instance = GlobalStates.currentPageInstance;
                if (instance && instance.contentY !== undefined) {
                    const step = 60;
                    const delta = event.key === Qt.Key_Down ? step : -step;
                    const maxY = Math.max(0, (instance.contentHeight ?? 0) - instance.height);
                    instance.contentY = Math.max(0, Math.min(maxY, instance.contentY + delta));
                }
                event.accepted = true;
                return;
            }
        }

            Rectangle {
                id: dragHandle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32
                color: "transparent"
                z: 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    drag.target: settingsWindow
                    drag.axis: Drag.XAndYAxis
                    onPressed: settingsWindow.userMoved = true
                    onDoubleClicked: settingsWindow.userMoved = false
                }

                RippleButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 10
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: panelWindow.hide()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnSurface
                    }
                    StyledToolTip {
                        text: Translation.tr("Close")
                    }
                }
            }

            SettingsContent {
                id: settingsContent
                anchors.fill: parent
            }
        }
    }
    }

    // `settings` and the settingsToggle shortcut open the Settings app (services/SettingsApp.qml),
    // which replaced this panel; `settings legacy` still opens the panel itself.
    IpcHandler {
        target: "settings"
        function toggle(): void { SettingsApp.toggle(); }
        function open(): void   { SettingsApp.open(""); }
        function close(): void  { GlobalStates.settingsOpen = false; }
        // `settings page Notch` (or "Notch:search term", or a Settings key like "sound")
        function page(name: string): void { SettingsApp.open(SettingsApp.keyFor(name)); }
        function legacy(): void { GlobalStates.settingsOpen = true; }
    }

    CompositorGlobalShortcut {
        name: "settingsToggle"
        description: "Toggles Settings"
        onPressed: SettingsApp.toggle();
    }
}