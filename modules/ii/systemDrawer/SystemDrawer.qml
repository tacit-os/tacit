import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The shell every bar drawer shares: the bar's own material continued below the strip, the
 * same cove, drop-out motion, button anchoring and ways out. A drawer supplies its body, its
 * open flag and its button's anchor; the window stays at full height so the layer never
 * resizes, while the drawn panel hugs the body's own implicitHeight.
 *
 * The surface is on the bar's namespace, so its colour, see-through and blur come from the
 * bar's rules and tokens instead of a second set kept in step.
 */
Scope {
    id: drawer

    property bool open: false
    property var anchor: null
    property Component content: null
    property real drawerWidth: 340
    property real maxBodyHeight: 460
    property string ipcTarget: ""
    // A tray item's menu takes its own grab. While it is open a click is consumed by that grab,
    // which would otherwise clear the drawer's dismissable grab and close the drawer. The menu
    // tells us here so the drawer can ignore that one dismissal.
    property bool holdDismissal: false

    signal openRequested()
    signal closeRequested()
    signal toggleRequested()

    // Re-arm the drawer in the shared grab after a menu's own grab cleared it.
    function regrab() {
        if (panelWindow.visible)
            GlobalFocusGrab.addDismissable(panelWindow);
    }

    PanelWindow {
        id: panelWindow

        readonly property bool animatedEntrance: WM.compositor !== "hyprland"
        property bool reallyVisible: false
        // The monitor in use when the drawer was opened; fixed until the next open so a
        // focus change does not carry the open drawer to another screen.
        property var openScreen: null
        screen: openScreen
        visible: reallyVisible

        Component.onCompleted: reallyVisible = drawer.open

        Connections {
            target: drawer
            function onOpenChanged() {
                if (drawer.open) {
                    // Only while it is down: opened again during the exit slide it stays where it is,
                    // since moving a mapped layer surface would carry it out from under the pointer.
                    if (!panelWindow.reallyVisible)
                        panelWindow.openScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
                    closeAnimTimer.stop();
                    panelWindow.reallyVisible = true;
                    // Opened again during the exit slide, `visible` never changes, and a click-away
                    // has emptied the grab.
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    closeAnimTimer.restart();
                }
            }
        }

        Timer {
            id: closeAnimTimer
            interval: Appearance.animationCurves.normalDuration
            onTriggered: panelWindow.reallyVisible = false
        }

        function hide() {
            drawer.closeRequested();
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
                // Extra grab members are added as they appear; see the Connections below.
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }



        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                // A menu's own grab clears ours; do not let that close the drawer underneath it.
                if (!drawer.holdDismissal)
                    panelWindow.hide();
            }
        }

        exclusiveZone: 0
        readonly property bool floating: Config.options.bar.show
        readonly property int cove: floating ? 0 : 12
        readonly property int topGap: floating ? 8 : 0
        // Follow the body's own width when it declares one, so a drawer can hug its content.
        readonly property real bodyWidth: (bodyLoader.item?.implicitWidth > 0)
            ? bodyLoader.item.implicitWidth : drawer.drawerWidth
        implicitWidth: bodyWidth + cove
        // The window is the reservoir the body slides inside; only the drawn panel follows
        // the body's own height, so there is no empty ground under short content.
        readonly property real panelHeight: Math.min(drawer.maxBodyHeight,
            (screen?.height ?? 1080) - Appearance.sizes.baseBarHeight - cove - topGap)
        implicitHeight: panelHeight + cove + topGap

        readonly property real anchorX: {
            const a = drawer.anchor;
            return a && a.screen === screen?.name ? a.x
                : (screen?.x ?? 0) + (screen?.width ?? 1920) - bodyWidth / 2 - 16;
        }

        mask: Region {
            item: maskBox
        }

        WlrLayershell.namespace: "quickshell:newbar"
        readonly property bool overFullscreen: WM.fullscreenOnMonitor(Hyprland.monitorFor(panelWindow.screen)?.name)
        WlrLayershell.layer: drawer.open && panelWindow.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.keyboardFocus: drawer.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            left: true
            top: true
        }
        margins.left: Math.max((screen?.x ?? 0) + 16,
            Math.min(panelWindow.anchorX - implicitWidth / 2,
                     (screen?.x ?? 0) + (screen?.width ?? 1920) - implicitWidth - 16))
            - (screen?.x ?? 0)

        Item {
            anchors.fill: parent

            // On compositors without a focus grab, a press outside the drawer closes it.
            MouseArea {
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            Item {
                id: maskBox
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.max(0, Math.min(entranceWrapper.contentHeight * (1 - entranceWrapper.offsetScale), parent.height))
            }

            Item {
                id: entranceWrapper
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                clip: true

                readonly property real contentHeight: (bodyLoader.item?.implicitHeight ?? 0) + panelWindow.cove + panelWindow.topGap
                property real offsetScale: drawer.open ? 0 : 1
                height: contentHeight
                transform: Translate { y: -entranceWrapper.contentHeight * entranceWrapper.offsetScale }

                Behavior on offsetScale {
                    Anim {
                        type: Anim.Standard
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                    z: -1
                }

                Loader {
                    id: bodyLoader
                    active: panelWindow.reallyVisible
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: panelWindow.topGap
                        leftMargin: panelWindow.cove
                    }
                    height: item?.implicitHeight ?? 0

                    focus: drawer.open
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: drawer.content
                }
            }
        }

        IpcHandler {
            target: drawer.ipcTarget

            function open(): void { drawer.openRequested() }
            function close(): void { drawer.closeRequested() }
            function toggle(): void { drawer.toggleRequested() }
        }
    }
}
