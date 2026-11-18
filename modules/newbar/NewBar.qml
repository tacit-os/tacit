pragma ComponentBehavior: Bound

// The top bar: a full-width strip docked to the top edge, standing in for the notch.
// It follows Tacit Design (design.tacitos.co):
//   Materials - frost (colPanelFrost) lifted by a 6 % wash of the main ink, never a solid grey patch
//   Shape     - the panel's corner is Tacit.radius.panel (14); a strip flush to both edges has no free corner
//   Colour    - text is ranked by ink (inkMain, inkSec, inkMeta, inkFaint), never text with opacity
//   Actions   - the right-hand buttons are IconButton from the kit (36 square, a wash on hover)
//
// Zones: left (workspaces, active window), centre (clock), right (notifications, control centre).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.demo
import qs.modules.ii.bar
import qs.services
import Tacit.Kit as K

Scope {
    id: newBar

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: barLoader
            active: true
            required property ShellScreen modelData

            component: PanelWindow {
                id: root
                screen: barLoader.modelData

                WlrLayershell.namespace: "quickshell:newbar"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // Reserve the strip's height so windows start below it and never cover it.
                // The zone is fixed, so windows never reflow while the bar is up.
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: Appearance.sizes.baseBarHeight
                color: "transparent"

                anchors {
                    top: true
                    left: true
                    right: true
                }
                implicitHeight: Appearance.sizes.baseBarHeight
                mask: Region { item: strip }

                // The ground: frost, then the main ink at the wash's 6 % over it. The wash is
                // drawn rather than mixed so the wallpaper's hue still comes through.
                Rectangle {
                    id: strip
                    anchors.fill: parent
                    color: Appearance.colors.colPanelFrost
                }
                Rectangle {
                    anchors.fill: parent
                    color: ColorUtils.applyAlpha(Tacit.inkMain, Tacit.wash.action)
                }

                // Three equal zones. Each takes a third of the width, so the centre stays the
                // centre of the screen whatever the outer zones carry.
                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: Tacit.space.m
                        rightMargin: Tacit.space.s
                    }
                    spacing: 0

                    // --- Left: workspaces, then the active window ---
                    Item {
                        id: leftZone
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: Tacit.space.m

                            // Placeholder: a circle mark that opens the app launcher.
                            // The overview's Connections treat a direct overviewOpen (as the
                            // corner's launcher button does) as the launcher's search.
                            K.IconButton {
                                id: circlePlaceholderButton
                                symbol: "ring"
                                label: "App launcher"
                                size: 18
                                onActivated: GlobalStates.overviewOpen = true
                            }

                            Row {
                                id: workspaceRow
                                spacing: Tacit.space.xs

                                // Only the workspaces that hold a window; the one in use is always
                                // listed too, so the bar still says where you are after switching to
                                // an empty workspace.
                                readonly property var shownWorkspaces: {
                                    const activeId = WM.activeWorkspaceForMonitor(root.screen?.name)?.id ?? -1;
                                    return WM.workspaces
                                        .filter(ws => ws.id === activeId || WM.windowList.some(w => w.workspaceId === ws.id))
                                        .sort((a, b) => a.id - b.id);
                                }

                                Repeater {
                                    model: workspaceRow.shownWorkspaces

                                    Item {
                                        id: chip
                                        required property var modelData
                                        readonly property bool active: modelData.id === (WM.activeWorkspaceForMonitor(root.screen?.name)?.id ?? -1)

                                        width: Math.max(20, number.implicitWidth + 10)
                                        height: 20

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: chip.active ? Tacit.inkMain
                                                : hover.hovered ? ColorUtils.applyAlpha(Tacit.inkMain, Tacit.wash.hoverSmall)
                                                : "transparent"
                                        }

                                        Text {
                                            id: number
                                            anchors.centerIn: parent
                                            text: String(chip.modelData.id)
                                            color: chip.active ? Tacit.ground : Tacit.inkSec
                                            font.family: Tacit.font.main
                                            font.pixelSize: 12
                                            font.weight: chip.active ? Tacit.weight.medium : Tacit.weight.regular
                                        }

                                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: WM.switchWorkspace(chip.modelData.id) }
                                    }
                                }
                            }

                            // The focused window's name: one line, elided, capped so a long
                            // title never crowds the clock. Back to the app or Desktop when
                            // nothing is focused.
                            Item {
                                id: activeWindowItem
                                readonly property var toplevel: ToplevelManager.activeToplevel
                                readonly property string name: toplevel?.title || toplevel?.appId || Translation.tr("Desktop")
                                implicitWidth: Math.min(title.implicitWidth, 240)
                                implicitHeight: title.implicitHeight

                                Text {
                                    id: title
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, 240)
                                    text: activeWindowItem.name
                                    elide: Text.ElideRight
                                    color: Tacit.inkMain
                                    font.family: Tacit.font.main
                                    font.pixelSize: Tacit.size.meta
                                    font.weight: Tacit.weight.regular
                                }
                            }
                        }
                    }

                    // --- Right: indicators, actions, then the clock at the end ---
                    Item {
                        id: rightZone
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: Tacit.space.xs

                            // --- Indicators: battery, network, volume ---
                            // Network and volume are still symbols only; battery reads UPower.
                            // Its mark says the charge at a glance: charging, or a pack running out.
                            K.IconButton {
                                id: batteryButton
                                symbol: Battery.isCharging ? "battery_charging"
                                    : Battery.isLowAndNotCharging ? "battery_alert"
                                    : "battery"
                                label: Battery.available ? `Battery ${Math.round(Battery.percentage * 100)}%` : "Battery"
                                size: 18
                            }
                            K.IconButton {
                                id: networkButton
                                symbol: "wifi"
                                label: "Network"
                                size: 18
                            }
                            K.IconButton {
                                id: volumeButton
                                symbol: "volume"
                                label: "Volume"
                                size: 18
                            }

                            // Notifications. Opens the same centre the corner door and an arrival
                            // open (GlobalStates.notificationCenterOpen). The badge counts what is
                            // unread, in the accent with the ink that sits on an accent fill.
                            K.IconButton {
                                id: notifButton
                                symbol: Notifications.unread > 0 ? "bell_ring" : "bell"
                                label: "Notifications"
                                size: 18
                                checked: GlobalStates.notificationCenterOpen
                                onActivated: GlobalStates.notificationCenterOpen = !GlobalStates.notificationCenterOpen

                                Rectangle {
                                    id: notifBadge
                                    anchors {
                                        right: parent.right
                                        top: parent.top
                                        rightMargin: 3
                                        topMargin: 3
                                    }
                                    width: 15
                                    height: 15
                                    radius: width / 2
                                    color: Tacit.accent
                                    visible: Notifications.unread > 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: Notifications.unread > 99 ? "99+" : String(Notifications.unread)
                                        color: Tacit.inkOnAccent
                                        font.family: Tacit.font.main
                                        font.pixelSize: 9
                                        font.weight: Tacit.weight.medium
                                    }
                                }
                            }

                            // The Control panel: the same surface SUPER + N reaches
                            // (quickshell:sidebarRightToggle -> GlobalStates.sidebarRightOpen).
                            // Its mark is drawn here: three sliders with their handles, since the
                            // kit's symbols have no control-centre one.
                            K.IconButton {
                                id: controlButton
                                symbol: ""
                                label: "Control panel"
                                size: 18
                                checked: GlobalStates.sidebarRightOpen
                                onActivated: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

                                Item {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16

                                    readonly property color ink: controlButton.checked ? Tacit.accent
                                        : controlButton.hovered ? Tacit.inkMain
                                        : Tacit.inkSec

                                    Repeater {
                                        model: [
                                            { y: 2, x: 11 },
                                            { y: 8, x: 5 },
                                            { y: 14, x: 11 }
                                        ]

                                        Item {
                                            anchors.fill: parent
                                            required property var modelData

                                            Rectangle {
                                                x: 0
                                                y: modelData.y - 0.75
                                                width: modelData.x - 3
                                                height: 1.5
                                                radius: 0.75
                                                color: parent.parent.ink
                                            }
                                            Rectangle {
                                                x: modelData.x + 3
                                                y: modelData.y - 0.75
                                                width: 13 - modelData.x
                                                height: 1.5
                                                radius: 0.75
                                                color: parent.parent.ink
                                            }
                                            Rectangle {
                                                x: modelData.x - 2.5
                                                y: modelData.y - 2.5
                                                width: 5
                                                height: 5
                                                radius: 2.5
                                                color: parent.parent.ink
                                            }
                                        }
                                    }
                                }
                            }

                            // The clock keeps the end of the bar: "Wed Nov 18 11:00 PM".
                            Item {
                                Layout.leftMargin: Tacit.space.s
                                implicitWidth: clock.implicitWidth
                                implicitHeight: clock.implicitHeight

                                Text {
                                    id: clock
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Qt.locale().toString(DateTime.clock.date, "ddd MMM d hh:mm AP")
                                    color: Tacit.inkMain
                                    font.family: Tacit.font.main
                                    font.pixelSize: Tacit.size.meta
                                    font.weight: Tacit.weight.regular
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
