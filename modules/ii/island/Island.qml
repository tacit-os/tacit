pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

/**
 * The Dynamic Island: one top-centre layer window per screen, holding the morphing container.
 * The window itself never moves or resizes - only IslandContent does - so the reserved zone stays
 * constant and windows never jitter. It stays mapped while the screen is locked too: only the notch
 * inside it goes at lock and comes back at unlock.
 */
Scope {
    id: island

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.island.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        LazyLoader {
            id: islandLoader
            active: true
            required property ShellScreen modelData

            component: PanelWindow {
                id: islandRoot
                screen: islandLoader.modelData

                // Keep the notch's own namespace even with the bar's colour: sharing the bar's
                // namespace stacked two translucent surfaces on the same layer and the compositor
                // blended their antialiased edges into a dotted seam. The notch's blur rule uses
                // the same threshold as the bar's, so "follow the bar" still blurs alike.
                WlrLayershell.namespace: "quickshell:island"
                // Keys only when opened from a key (IslandController.keyboard); None otherwise so
                // a hover never steals typing from the window under the pointer. Also only while
                // THIS screen's sheet is really open - a stale flag must not hold the seat on a
                // window showing the resting pill - and only on the screen the key was pressed
                // on, so two monitors' notches never ask for the seat at once.
                // Exclusive, and OnDemand is not an option here: this window is mapped for the
                // session (the resting pill), and Hyprland gives focus on an interactivity change
                // only to an exclusive surface (LayerSurface.cpp onCommit) - the sidebars get away
                // with OnDemand because their window maps as it opens. While it is exclusive the
                // compositor refuses keyboard focus to windows (FocusState.cpp), so a click
                // elsewhere cannot take the keyboard back: Escape at the sheet level
                // (IslandContent) and the shortcut are the ways out.
                WlrLayershell.keyboardFocus: (IslandController.keyboard && islandContent !== null && islandContent.open && islandContent.keyScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                // Hyprland buries the Top layer under a fullscreen window. boring.notch's
                // nowPlayingOnly: ride the Overlay layer while something plays in ANOTHER app, so a
                // game or a film keeps the music's transport; the fullscreen window's own player (a
                // video in the browser) is not another app, and the notch stays under it (Discord
                // 2026-10-27: the notch over YouTube in fullscreen). A maximized window is not fullscreen.
                readonly property var thisMonitorData: HyprlandData.monitors.find(m => m.name === islandRoot.screen?.name)
                readonly property var fullscreenWindow: HyprlandData.trueFullscreenWindow(thisMonitorData?.activeWorkspace?.id)
                readonly property bool overFullscreen: fullscreenWindow !== null && Config.options.island.showInFullscreenWhilePlaying
                    && IslandController.mediaPresent && MprisController.isPlaying
                    && !MprisController.playsIn(fullscreenWindow, MprisController.activePlayer)
                // Top is buried under a fullscreen window, which puts the notch behind a game or
                // film with no map/unmap flicker. The panel family creates the notch after the bar
                // so it stacks above the strip on this same layer.
                WlrLayershell.layer: WlrLayer.Top
                color: "transparent"

                // Window-aware means honest: the reserve is exactly the resting header (34px)
                // plus a 4px breath, plus the margin the notch is nudged down by, so the
                // reserve always ends where the notch does. Peeks and the hover strip change
                // width only, and the clicked sheet OVERLAYS windows like a menu does - so
                // nothing on the desktop ever reflows because of the notch, and nothing moves
                // under the pointer.
                // The top bar (modules/newbar) owns the top edge when shown: it reserves the
                // strip and the notch hangs from its underside with no reserve of its own. With
                // the bar off, the notch returns to its pre-bar place and keeps its own reserve.
                readonly property bool barShown: Config.options.bar.show
                // -1 = ignore other surfaces' exclusive zones, so the notch stays at the screen
                // top even while the bar reserves its strip.
                exclusionMode: barShown ? ExclusionMode.Ignore : ExclusionMode.Normal
                exclusiveZone: barShown ? -1 : (Config.options.island.reservedHeight + Config.options.island.topMargin)

                // Top-anchored only (the compositor centres it), at a FIXED size that never
                // changes: 860 x 540 since the browser's address sheet (820 wide with its shadow,
                // 2026-10-02); the other sheets keep to 440 (34 header + 150 player + 36 timer
                // row + 212 rows). Not the screen's width: the compositor blends every mapped
                // layer over every damaged pixel it overlaps. A window that resized on open/close
                // was tried and reverted: Hyprland animates a layer's size change, scaling what it
                // shows, so the notch shrank and swung aside (seen again growing it for the
                // address sheet). The mask keeps everything outside the notch click-through.
                anchors {
                    top: true
                }
                implicitWidth: 860
                implicitHeight: barShown ? 540 : (540 + Config.options.island.topMargin)
                // Bar shown: the notch draws over the strip (chip at the screen's top edge).
                // Bar off: the notch sits at its pre-bar offset from the top edge.
                readonly property bool contentShown: contentLoader.item !== null
                mask: islandRoot.contentShown ? notchMask : emptyMask
                Region {
                    id: notchMask
                    item: contentLoader
                    // the sign-in's hole: the page window under it takes the pointer there
                    Region {
                        item: islandRoot.islandContent?.holeItem ?? null
                        intersection: Intersection.Subtract
                    }
                }
                Region {
                    id: emptyMask
                    width: 0
                    height: 0
                }

                // Include in focus grab, like the bar
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(islandRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(islandRoot);
                }

                // An open sheet closed only when the pointer left it or on Esc, so a leave that never came (a drag over
                // the notch, a tap on a touch screen) or the recording's choice (it holds the keyboard) left it open with
                // no way out (Discord, SrwR16, 2026-11-05). While one is open, a clear window covers the rest of the
                // screen and a press on it folds the sheet. Not the desktop's click-away grab: Hyprland drops a grab as
                // soon as the pointer rests outside it, which closed a sheet opened from a key at once, and the grab takes
                // the keys. Not during a drag, nor the sign-in, which has its own way back (a pill) and a page in use. Ask and
                // the address hold the keyboard, so a press outside is their only pointer way out besides Esc: it closes them
                // as Esc does, but a wheel turn over the rest of the screen does not (a draft is not worth losing to a scroll).
                readonly property bool clickAway: islandContent !== null && islandContent.open && !islandContent.draggingOut
                    && !islandContent.dragOver && !islandContent.textDragOver
                    && islandContent.view !== "signin"
                // a press or a wheel turn on a catcher folds the sheet, as Esc does; a wheel turn leaves Ask and the address
                function away(wheel) {
                    if (wheel && (islandContent.view === "ask" || islandContent.view === "address"))
                        return;
                    islandContent.pinnedUntilVisit = false;
                    islandContent.open = false;
                }
                PanelWindow {
                    id: awayCatcher
                    screen: islandRoot.screen
                    visible: islandRoot.clickAway
                    WlrLayershell.namespace: "quickshell:islandAway"
                    WlrLayershell.layer: islandRoot.WlrLayershell.layer
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Ignore
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"
                    // the notch keeps its own pointer: a hole where it is (the catcher maps above it)
                    mask: Region {
                        width: awayCatcher.width
                        height: awayCatcher.height
                        Region {
                            x: (awayCatcher.width - islandRoot.width) / 2 + contentLoader.x
                            y: contentLoader.y
                            width: contentLoader.width
                            height: contentLoader.height
                            intersection: Intersection.Subtract
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        onPressed: islandRoot.away(false)
                        onWheel: islandRoot.away(true)
                    }
                }
                // While the sheet holds the keyboard, a click on a window on another screen cannot take it back either,
                // and with nothing there to catch it the sheet stayed open and went on taking what was typed. So every
                // other screen gets a catcher too while it holds them.
                readonly property bool holdsKeys: islandRoot.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive
                Variants {
                    model: islandRoot.clickAway && islandRoot.holdsKeys ? Quickshell.screens.filter(s => s.name !== islandRoot.screen?.name) : []
                    PanelWindow {
                        required property ShellScreen modelData
                        screen: modelData
                        WlrLayershell.namespace: "quickshell:islandAway"
                        WlrLayershell.layer: islandRoot.WlrLayershell.layer
                        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                        exclusionMode: ExclusionMode.Ignore
                        anchors {
                            top: true
                            bottom: true
                            left: true
                            right: true
                        }
                        color: "transparent"
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                            onPressed: islandRoot.away(false)
                            onWheel: islandRoot.away(true)
                        }
                    }
                }

                // The notch goes at lock and is built again at unlock, the window holding it does not: unmapped, it took
                // its reserved band with it, and every tiled window grew 38 px under the lock and shrank back after it.
                // A Loader is a focus scope: it holds the window's focus so the notch's keys reach it as before.
                Loader {
                    id: contentLoader
                    active: !GlobalStates.screenLocked
                    focus: true
                    // Bar shown: the header sits on the bar's centre line. Bar off: the notch
                    // keeps its pre-bar offset from the top edge.
                    visible: islandRoot.contentShown
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: islandRoot.barShown ? 0 : Config.options.island.topMargin
                    sourceComponent: IslandContent {
                        screenData: islandRoot.screen
                    }
                }
                readonly property IslandContent islandContent: contentLoader.item
            }
        }
    }
}
