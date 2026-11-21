import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.systemDrawer
import qs.modules.tacit
import Tacit.Kit
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The volume settings for the master output: the output device, its mute switch, the master
 * slider, and then the output section — the same audio settings as the control panel's sound
 * section. Opens from the bar's volume button (GlobalStates.volumeOpen) and closes on click
 * away, on Esc, or through the `volume` IPC target.
 *
 * The window follows the control panel (SidebarRight.qml): the bar's own surface continued
 * below the strip, the same cove, the same slide out of the bar, centred on its button, and
 * the same dismissal through GlobalFocusGrab. Only the body is smaller.
 */
Scope {
    id: volumePopup

    PanelWindow {
        id: panelWindow

        readonly property bool animatedEntrance: WM.compositor !== "hyprland"
        property bool reallyVisible: false
        // The monitor in use when the panel was opened; fixed until the next open so a
        // focus change does not carry the open panel to another screen.
        property var openScreen: null
        screen: openScreen
        visible: reallyVisible

        Component.onCompleted: reallyVisible = GlobalStates.volumeOpen

        Connections {
            target: GlobalStates
            function onVolumeOpenChanged() {
                if (GlobalStates.volumeOpen) {
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
                    // The shell owns the exit slide on every compositor now, so always let it finish.
                    closeAnimTimer.restart();
                }
            }
        }

        Timer {
            id: closeAnimTimer
            // Matches Anim.Standard's own duration, so the window stays mapped through the slide.
            interval: Appearance.animationCurves.normalDuration
            onTriggered: panelWindow.reallyVisible = false
        }

        function hide() {
            GlobalStates.volumeOpen = false;
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
        readonly property bool floating: Config.options.bar.show && (!Config.options.bar.showBackground || Config.options.bar.drawerStyle !== "attached")
        // The cove and the window's measure. The body is 340 wide; the extra cove is where the
        // silhouette flares into the strip, like the control panel's own cove.
        readonly property int cove: floating ? 0 : 12
        readonly property int topGap: floating ? 8 : 0
        implicitWidth: 340 + cove
        // Tall enough for the master row, the slider and the audio section's capped list
        // (six 40 px rows) without the last row running into the silhouette's rounded bottom.
        readonly property real panelHeight: Math.min(460, panelMaxHeight)
        implicitHeight: panelHeight + cove + topGap

        // The volume button's centre, published by the bar. The fallback is the right edge
        // before any bar has published it (a keybind opening the panel).
        readonly property real anchorX: {
            const a = GlobalStates.volumeAnchor;
            return a && a.screen === screen?.name ? a.x
                : (screen?.x ?? 0) + (screen?.width ?? 1920) - implicitWidth / 2 - 16;
        }
        // What the panel may never exceed: the screen minus the bar's reserved band and the
        // cove, so the whole silhouette stays on screen.
        readonly property real panelMaxHeight: (screen?.height ?? 1080)
            - Appearance.sizes.baseBarHeight - cove - topGap

        mask: Region {
            item: maskBox
        }

        // The bar's namespace, so the drawer wears the bar's surface: its blur rule and threshold
        // (session/hypr/tacit/rules.lua) apply to this layer too, with no second rule to keep in
        // step. The body's colour and see-through come from the bar's colBarSurface below.
        WlrLayershell.namespace: "quickshell:newbar"
        // Under a fullscreen window the Top layer is buried: take the keyboard unseen otherwise.
        readonly property bool overFullscreen: WM.fullscreenOnMonitor(Hyprland.monitorFor(panelWindow.screen)?.name)
        WlrLayershell.layer: GlobalStates.volumeOpen && panelWindow.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.volumeOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            left: true
            top: true
        }
        // Centre the window on the volume button, held at least 16 px inside the screen's edges
        // (the compositor hides what lies flush against a rounded screen corner).
        margins.left: Math.max((screen?.x ?? 0) + 16,
            Math.min(panelWindow.anchorX - implicitWidth / 2,
                     (screen?.x ?? 0) + (screen?.width ?? 1920) - implicitWidth - 16))
            - (screen?.x ?? 0)

        Item {
            anchors.fill: parent

            // On compositors without a focus grab, a press outside the panel closes it.
            MouseArea {
                id: outsideClickArea
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            // The click area is the part of the panel still inside the window. It is its own
            // item because a slide is a transform on the wrapper, and the mask must never leave
            // the surface.
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

                readonly property bool open: GlobalStates.volumeOpen
                readonly property real contentHeight: (bodyLoader.item?.implicitHeight ?? 0) + panelWindow.cove + panelWindow.topGap
                // The panel drops out of the bar as one piece, on the control panel's curve.
                property real offsetScale: open ? 0 : 1
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
                    // The body sits flush under the bar; the cove to its left is drawn inside it.
                    active: panelWindow.reallyVisible
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: panelWindow.topGap
                        leftMargin: panelWindow.cove
                    }
                    height: item?.implicitHeight ?? 0

                    focus: GlobalStates.volumeOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: Component {
                        Item {
                            id: body
                            implicitWidth: 340
                            // The silhouette hugs its content: two paddings, the master row, the
                            // slider, their gaps and the audio section's own animated height. The
                            // layer window stays at full height so it never resizes; only the panel
                            // drawn inside grows and shrinks, leaving no empty ground at the bottom.
                            implicitHeight: Math.min(
                                Kit.tokens.space.l + 34
                                + Kit.tokens.space.m + 28   // the kit slider's implicit height
                                + Kit.tokens.space.m + output.implicitHeight
                                + Kit.tokens.space.m + Kit.tokens.space.xl,
                                panelWindow.panelMaxHeight)

                            DockedRect {
                                anchors.fill: parent
                                visible: !Config.options.bar.show || (Config.options.bar.showBackground && Config.options.bar.drawerStyle === "attached")
                                edge: "top"
                                cornerRadius: Appearance.rounding.verylarge
                                fillet: 12
                                color: Appearance.colors.colBarSurface
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: Config.options.bar.show && (!Config.options.bar.showBackground || Config.options.bar.drawerStyle !== "attached")
                                radius: Appearance.rounding.verylarge
                                color: Appearance.colors.colBarSurface
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                            }

                            ColumnLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: Kit.tokens.space.l
                                    rightMargin: Kit.tokens.space.l
                                    topMargin: Kit.tokens.space.l
                                    // The silhouette curves in at the bottom; keep the last row
                                    // above that curve rather than letting it cut the text.
                                    bottomMargin: Kit.tokens.space.xl
                                }
                                spacing: Kit.tokens.space.m

                                // Master output row: the volume glyph as the mark, a mute toggle,
                                // and the live percentage from the default sink.
                                Item {
                                    id: master
                                    Layout.preferredHeight: 34
                                    width: parent.width
                                    RowLayout {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        spacing: Kit.tokens.space.s

                                        MaterialSymbol {
                                            text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                                            iconSize: 18
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: (Audio.sink?.friendlyName ?? Audio.sink?.audio?.channelMap?.[0]?.description ?? Translation.tr("Output")).toString()
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            text: Audio.sink?.audio?.muted ? Translation.tr("Muted")
                                                : Math.round(Audio.value * 100) + "%"
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledSwitch {
                                            readonly property bool live: !(Audio.sink?.audio?.muted ?? true)
                                            checked: live
                                            onClicked: Audio.toggleMute()
                                        }
                                    }
                                }

                                // The master slider: the control panel's own one-line slider.
                                LineSlider {
                                    Layout.fillWidth: true
                                    glyph: (Audio.sink?.audio?.muted ?? false) ? "volume_off"
                                        : ((Audio.sink?.audio?.volume ?? 0) < 0.34 ? "volume_down" : "volume_up")
                                    label: Translation.tr("Volume")
                                    value: Audio.sink?.audio?.volume ?? 0
                                    enabledControl: Audio.sink?.audio != null
                                    onMoved: v => {
                                        if (Audio.sink?.audio) {
                                            Audio.setVolume(v);
                                            // Dragging up from a muted sink brings the sound back.
                                            if (v > 0 && Audio.sink.audio.muted)
                                                Audio.sink.audio.muted = false;
                                        }
                                    }
                                }

                                // Then the audio settings (output devices and every app on it,
                                // with its own level and mute) — the control panel's own section.
                                AudioSection {
                                    id: output
                                    input: false
                                    shown: true
                                }

                                Item {
                                    Layout.fillHeight: true
                                }
                            }
                        }
                    }
                }
            }
        }

        IpcHandler {
            target: "volume"

            function open(): void {
                GlobalStates.volumeOpen = true;
            }

            function close(): void {
                GlobalStates.volumeOpen = false;
            }

            function toggle(): void {
                GlobalStates.volumeOpen = !GlobalStates.volumeOpen;
            }
        }
    }
}
