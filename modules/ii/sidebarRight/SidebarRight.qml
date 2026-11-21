import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Tacit.Kit

Scope {
    id: root
    // The window hugs the content's measure: seven action-height cells (the secondary row)
    // with their gaps, plus the body's two paddings. Update together with the content's
    // own paddings (SidebarRightContent's sidebarPadding) and togglesWidth.
    property int sidebarWidth: Kit.tokens.height.action * 7 + Kit.tokens.space.s * 6 + Kit.tokens.space.l * 2
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical

    PanelWindow {
        id: panelWindow

        readonly property bool animatedEntrance: WM.compositor !== "hyprland"
        property bool reallyVisible: false
        // Keeping the panel built waits until the shell has settled, so building it does not
        // block the first bar frames.
        property bool settled: false
        Timer {
            interval: 5000
            running: true
            onTriggered: panelWindow.settled = true
        }
        visible: reallyVisible
        // The monitor in use when the panel was opened; fixed until the next open so a
        // focus change does not carry the open panel to another screen.
        property var openScreen: null
        screen: openScreen

        Component.onCompleted: reallyVisible = GlobalStates.sidebarRightOpen

        Connections {
            target: GlobalStates
            function onSidebarRightOpenChanged() {
                if (GlobalStates.sidebarRightOpen) {
                    // only while it is down: opened again during the exit slide it stays where it is, since
                    // moving a mapped layer surface would carry it out from under the pointer
                    if (!panelWindow.reallyVisible)
                        panelWindow.openScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
                    closeAnimTimer.stop();
                    panelWindow.reallyVisible = true;
                    // Opened again during the exit slide, `visible` never changes, and a click-away has emptied the grab
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    // The shell owns the exit slide on every compositor now (Hyprland's
                    // layer animation is off for this namespace), so always let it finish.
                    closeAnimTimer.restart();
                }
            }
        }

        Timer {
            id: closeAnimTimer
            // Matches Anim.Standard's own duration (the normal one); a little extra
            // would only keep the window a moment later, never empty the mask.
            interval: Appearance.animationCurves.normalDuration
            onTriggered: panelWindow.reallyVisible = false
        }

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
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

        exclusiveZone: 0
        // Bar shown: hangs from the bar's underside, centred on the control button, and drops
        // down out of the strip. Bar off: returns to the pre-bar bottom-right corner and rises up.
        readonly property bool barShown: Config.options.bar.show
        readonly property bool floating: barShown && (!Config.options.bar.showBackground || Config.options.bar.drawerStyle !== "attached")
        readonly property int cove: floating ? 0 : 12
        readonly property int topGap: floating ? 8 : 0
        implicitWidth: sidebarWidth + cove
        // The button's centre, published by the bar. Fall back to the right edge when opened by
        // a keybind before any bar has published it.
        readonly property real anchorX: {
            const a = GlobalStates.controlPanelAnchor;
            return a && a.screen === screen?.name ? a.x
                : (screen?.x ?? 0) + (screen?.width ?? 1920) - implicitWidth / 2 - 16;
        }
        // What the panel may never exceed. Bar on: screen minus the bar band. Bar off: screen
        // minus the notch's reserve, so the panel and notch never fight for the same space.
        readonly property real panelMaxHeight: {
            const h = screen?.height ?? 1080
            const limit = barShown
                ? h - Appearance.sizes.baseBarHeight - cove - topGap
                : h - (Config.options.island.reservedHeight + Config.options.island.topMargin) - cove
            return Math.max(200, Math.min(limit, h - 8))
        }
        // Constant, like the notch's window: a layer surface cannot animate a resize, so the
        // window is as tall as the panel can ever get and the panel animates inside it. The
        // mask keeps the empty part click-through. Clamp to the screen so a stale/large
        // implicitHeight from content binding loops can never make the window exceed it.
        implicitHeight: Math.min(panelMaxHeight + cove + topGap, (screen?.height ?? 1080) - 8)
        // The click area is the part of the panel still inside the window. It is its own item
        // because a slide is a transform on entranceWrapper, and the mask must never leave the
        // surface.
        mask: Region {
            item: maskBox
        }
        WlrLayershell.namespace: "quickshell:sidebarRight"
        // under a fullscreen window the Top layer is buried: the panel took the keyboard unseen. Overlay while open there
        readonly property bool overFullscreen: WM.fullscreenOnMonitor(Hyprland.monitorFor(panelWindow.screen)?.name)
        WlrLayershell.layer: GlobalStates.sidebarRightOpen && panelWindow.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            left: barShown
            top: barShown
            right: !barShown
            bottom: !barShown
        }
        // Bar shown: centre on the button, held inside the screen edges. Bar off: flush in the
        // bottom-right corner.
        margins.left: barShown ? Math.max((screen?.x ?? 0) + 16,
            Math.min(panelWindow.anchorX - implicitWidth / 2,
                     (screen?.x ?? 0) + (screen?.width ?? 1920) - implicitWidth - 16))
            - (screen?.x ?? 0) : 0

        Item {
            anchors.fill: parent

            MouseArea {
                id: outsideClickArea
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            Item {
                id: maskBox
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: panelWindow.barShown ? parent.top : undefined
                anchors.bottom: panelWindow.barShown ? undefined : parent.bottom
                height: Math.max(0, Math.min(entranceWrapper.contentHeight * (1 - entranceWrapper.offsetScale), parent.height))
            }



            Item {
                id: entranceWrapper
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: panelWindow.barShown ? parent.top : undefined
                anchors.bottom: panelWindow.barShown ? undefined : parent.bottom
                clip: true

                readonly property bool open: GlobalStates.sidebarRightOpen
                readonly property real contentHeight: (sidebarContentLoader.item?.implicitHeight ?? 0) + panelWindow.cove + (panelWindow.barShown ? panelWindow.topGap : 0)
                // Bar shown: the panel drops out of the bar. Bar off: it rises from the bottom edge.
                // A standard curve, no fade (blur would pop mid-way).
                property real offsetScale: open ? 0 : 1
                // Clamp to the window: a stale content implicitHeight must never make the
                // wrapper (and its content) grow past the screen-sized layer surface.
                height: Math.max(0, Math.min(contentHeight, parent?.height ?? contentHeight))
                transform: Translate {
                    y: panelWindow.barShown
                        ? -entranceWrapper.contentHeight * entranceWrapper.offsetScale
                        : entranceWrapper.contentHeight * entranceWrapper.offsetScale
                }

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
                    id: sidebarContentLoader
                    // The body sits flush in the corner; the coves are drawn by the DockedRect
                    // inside SidebarRightContent.qml.
                    active: panelWindow.reallyVisible || (panelWindow.settled && Config?.options.sidebar.keepRightSidebarLoaded)
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: panelWindow.barShown ? parent.top : undefined
                        bottom: panelWindow.barShown ? undefined : parent.bottom
                        topMargin: panelWindow.barShown ? panelWindow.topGap : 0
                        leftMargin: panelWindow.cove
                    }
                    // No Behavior here: the content animates its own height and the panel follows
                    // frame by frame.
                    height: item?.implicitHeight ?? 0

                    focus: GlobalStates.sidebarRightOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {
                        maxHeight: panelWindow.panelMaxHeight
                        barShown: panelWindow.barShown
                    }
                }
            }
        }

        IpcHandler {
            target: "sidebarRight"

            function toggle(): void {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }

            function close(): void {
                GlobalStates.sidebarRightOpen = false;
            }

            function open(): void {
                GlobalStates.sidebarRightOpen = true;
            }

            // the panel on its sound section
            function openSound(): void {
                GlobalStates.sidebarRightSection = "showAudioOutputDialog";
                GlobalStates.sidebarRightOpen = true;
            }
        }

        CompositorGlobalShortcut {
            name: "sidebarRightToggle"
            description: "Toggles right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }
        CompositorGlobalShortcut {
            name: "sidebarRightOpen"
            description: "Opens right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = true;
            }
        }
        CompositorGlobalShortcut {
            name: "sidebarRightClose"
            description: "Closes right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }
}