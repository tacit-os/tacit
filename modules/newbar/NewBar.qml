pragma ComponentBehavior: Bound
import QtQuick.Controls

// The top bar: a full-width strip docked to the top edge, standing in for the notch.
// It follows Tacit Design (design.tacitos.co):
//   Materials - frost (colPanelFrost) lifted by a 6 % wash of the main ink, never a solid grey patch.
//               The frost's amount is Settings > Appearance's see-through (Solid, Frosted, Clear), so
//               the bar, the notch and the panels change look together.
//   Shape     - the panel's corner is Tacit.radius.panel (14); a strip flush to both edges has no free corner
//   Colour    - text is ranked by ink (inkMain, inkSec, inkMeta, inkFaint), never text with opacity
//   Actions   - the right-hand buttons are IconButton from the kit (36 square, a wash on hover)
//
// Zones: left (workspaces, active window), centre (clock), right (notifications, control centre).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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

                readonly property color leftInkMain: BarContrast.inkMain("left")
                readonly property color leftInkSec: BarContrast.inkSec("left")
                readonly property color rightInkMain: BarContrast.inkMain("right")
                readonly property color rightInkSec: BarContrast.inkSec("right")
                readonly property color rightInkMeta: BarContrast.inkMeta("right")

                // The ground: the frost wearing the colour scheme (colBarFrost), then the main ink
                // at the wash's 6 % over it. The wash is drawn rather than mixed so the picture's
                // hue still comes through.
                Rectangle {
                    id: strip
                    anchors.fill: parent
                    color: Config.options.bar.showBackground ? Appearance.colors.colBarFrost : "transparent"
                }
                Rectangle {
                    anchors.fill: parent
                    visible: Config.options.bar.showBackground
                    color: ColorUtils.applyAlpha(Tacit.inkMain, Tacit.wash.action)
                }
                // Clear's blur arrives at full strength and so do the picture's colours. The veil
                // takes the colour out of them and leaves the picture in place (Clear only).
                Rectangle {
                    anchors.fill: parent
                    visible: Config.options.bar.showBackground && Appearance.colors.colBarVeil.a > 0
                    color: Appearance.colors.colBarVeil
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
                            BarActionButton {
                                id: circlePlaceholderButton
                                ink: root.leftInkMain
                                barBottom: Config.options.bar.bottom
                                symbol: "ring"
                                label: Translation.tr("App launcher")
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
                                            color: chip.active ? root.leftInkMain
                                                : hover.hovered ? ColorUtils.applyAlpha(root.leftInkMain, Tacit.wash.hoverSmall)
                                                : "transparent"
                                        }

                                        BarText {
                                            id: number
                                            anchors.centerIn: parent
                                            text: String(chip.modelData.id)
                                            color: chip.active ? BarContrast.onInkMain("left") : root.leftInkSec
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

                                BarText {
                                    id: title
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, 240)
                                    text: activeWindowItem.name
                                    elide: Text.ElideRight
                                    color: root.leftInkMain
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

                            // --- Indicators ---
                            BarActionButton {
                                id: trayButton
                                show: Config.options.bar.showTrayButton
                                ink: root.rightInkMain
                                barBottom: Config.options.bar.bottom
                                symbol: "expand_more"
                                label: Translation.tr("System tray")
                                active: GlobalStates.trayOpen
                                onActivated: GlobalStates.trayOpen = !GlobalStates.trayOpen
                            }
                            Item {
                                id: batteryButton
                                visible: Config.options.bar.showBatteryButton && Battery.available
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: Math.max(36, batteryRow.implicitWidth + Tacit.space.m)
                                implicitHeight: 36
                                readonly property bool showBatteryPercent: Config.options.bar.showBatteryPercentage && Battery.available
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: Battery.available ? Translation.tr("Battery %1%").arg(Math.round(Battery.percentage * 100)) : Translation.tr("Battery")
                                Keys.onReturnPressed: GlobalStates.batteryOpen = !GlobalStates.batteryOpen
                                Keys.onSpacePressed: GlobalStates.batteryOpen = !GlobalStates.batteryOpen

                                HoverHandler { id: batteryHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: GlobalStates.batteryOpen
                                        ? ColorUtils.applyAlpha(root.rightInkMain, Tacit.wash.action)
                                        : (batteryHover.hovered || batteryButton.activeFocus) ? ColorUtils.applyAlpha(root.rightInkMain, Tacit.wash.hoverSmall)
                                        : "transparent"
                                }

                                Row {
                                    id: batteryRow
                                    spacing: 4
                                    anchors.centerIn: parent

                                    K.Symbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Battery.iconName()
                                        size: 18
                                        color: root.rightInkMain
                                    }

                                    BarText {
                                        visible: batteryButton.showBatteryPercent
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: `${Math.round(Battery.percentage * 100)}%`
                                        color: root.rightInkSec
                                        font.family: Tacit.font.main
                                        font.pixelSize: Tacit.size.meta
                                        font.weight: Tacit.weight.regular
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: GlobalStates.batteryOpen = !GlobalStates.batteryOpen
                                }
                                PopupToolTip {
                                    anchorEdges: root.bottom ? Edges.Top : Edges.Bottom
                                    extraVisibleCondition: batteryHover.hovered || batteryButton.activeFocus
                                    text: Battery.available ? Translation.tr("Battery %1%").arg(Math.round(Battery.percentage * 100)) : Translation.tr("Battery")
                                }
                            }
                            BarActionButton {
                                id: networkButton
                                show: Config.options.bar.showNetworkButton
                                ink: root.rightInkMain
                                barBottom: Config.options.bar.bottom
                                symbol: "wifi"
                                label: Translation.tr("Network")
                                active: GlobalStates.networkOpen
                                onActivated: GlobalStates.networkOpen = !GlobalStates.networkOpen
                            }
                            BarActionButton {
                                id: volumeButton
                                show: Config.options.bar.showVolumeButton
                                ink: root.rightInkMain
                                barBottom: Config.options.bar.bottom
                                symbol: "volume"
                                label: Translation.tr("Volume")
                                active: GlobalStates.volumeOpen
                                onActivated: GlobalStates.volumeOpen = true
                            }
                            BarActionButton {
                                id: brightnessButton
                                show: Config.options.bar.showBrightnessButton
                                ink: root.rightInkMain
                                barBottom: Config.options.bar.bottom
                                symbol: "brightness"
                                label: Translation.tr("Brightness")
                                active: GlobalStates.brightnessOpen
                                onActivated: GlobalStates.brightnessOpen = !GlobalStates.brightnessOpen
                            }

                            // The Control panel: the same surface SUPER + N reaches
                            // (quickshell:sidebarRightToggle -> GlobalStates.sidebarRightOpen).
                            BarActionButton {
                                id: controlButton
                                show: Config.options.bar.showControlButton
                                ink: root.rightInkMain
                                barBottom: Config.options.bar.bottom
                                symbol: "tune"
                                label: Translation.tr("Control panel")
                                active: GlobalStates.sidebarRightOpen
                                onActivated: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                            }

                            // Notifications last.
                            Item {
                                id: notifButton
                                visible: Config.options.bar.showNotificationsButton
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 36
                                implicitHeight: 36
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: Notifications.unread > 0 ? Translation.tr("Notifications (%1 unread)").arg(Notifications.unread) : Translation.tr("Notifications")
                                Keys.onReturnPressed: GlobalStates.notificationCenterOpen = !GlobalStates.notificationCenterOpen
                                Keys.onSpacePressed: GlobalStates.notificationCenterOpen = !GlobalStates.notificationCenterOpen
                                HoverHandler { id: notifHover }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: GlobalStates.notificationCenterOpen
                                        ? ColorUtils.applyAlpha(root.rightInkMain, Tacit.wash.action)
                                        : (notifHover.hovered || notifButton.activeFocus) ? ColorUtils.applyAlpha(root.rightInkMain, Tacit.wash.hoverSmall)
                                        : "transparent"
                                }
                                K.Symbol {
                                    anchors.centerIn: parent
                                    text: Notifications.unread > 0 ? "bell-ring" : "bell"
                                    size: 18
                                    color: root.rightInkMain
                                }

                                // The button is 36 px but the glyph is 18 px and centred: anchoring
                                // the badge to the button put it beside the bell like a second icon.
                                // Anchor it to the glyph's box instead so it reads as a corner badge.
                                Item {
                                    id: notifGlyphBox
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                }
                                Rectangle {
                                    id: notifBadge
                                    anchors {
                                        right: notifGlyphBox.right
                                        top: notifGlyphBox.top
                                        rightMargin: -2
                                        topMargin: -2
                                    }
                                    // The count sits on the accent fill, so it needs no shadow:
                                    // BarText's layer effect smeared it inside this small badge.
                                    implicitWidth: Math.max(13, notifCount.implicitWidth + 4)
                                    implicitHeight: 13
                                    width: implicitWidth
                                    height: implicitHeight
                                    radius: height / 2
                                    color: Tacit.accent
                                    visible: Notifications.unread > 0

                                    StyledText {
                                        id: notifCount
                                        anchors.centerIn: parent
                                        text: Notifications.unread > 99 ? "99+" : String(Notifications.unread)
                                        color: Tacit.inkOnAccent
                                        font.family: Tacit.font.main
                                        font.pixelSize: 8
                                        font.weight: Font.Medium
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: GlobalStates.notificationCenterOpen = !GlobalStates.notificationCenterOpen
                                }
                                PopupToolTip {
                                    anchorEdges: root.bottom ? Edges.Top : Edges.Bottom
                                    extraVisibleCondition: notifHover.hovered || notifButton.activeFocus
                                    text: Translation.tr("Notifications")
                                }
                            }

                        }
                    }
                }

                // The control panel hangs off the button: publish where the button is, on the
                // screen the panel will open on. SidebarRight centres its window on this, so the
                // button is the panel's centre wherever the bar lays out its right-hand zone.
                function publishAnchor(key, button) {
                    if (root.screen?.name !== Hyprland.focusedMonitor?.name)
                        return;
                    // Before the first layout a button has no size, and mapToGlobal returns a
                    // corner that left the notification popup under the bar's left group.
                    if (button.width <= 0 || button.height <= 0)
                        return;
                    const c = button.mapToGlobal(button.width / 2, button.height / 2);
                    GlobalStates[key] = { x: c.x, screen: root.screen.name };
                }

                Connections {
                    target: GlobalStates
                    function onSidebarRightOpenChanged() {
                        if (GlobalStates.sidebarRightOpen)
                            root.publishAnchor("controlPanelAnchor", controlButton);
                    }
                    function onVolumeOpenChanged() {
                        if (GlobalStates.volumeOpen)
                            root.publishAnchor("volumeAnchor", volumeButton);
                    }
                    function onNotificationCenterOpenChanged() {
                        if (GlobalStates.notificationCenterOpen)
                            root.publishAnchor("notificationAnchor", notifButton);
                    }
                    function onNetworkOpenChanged() {
                        if (GlobalStates.networkOpen)
                            root.publishAnchor("networkAnchor", networkButton);
                    }
                    function onBatteryOpenChanged() {
                        if (GlobalStates.batteryOpen)
                            root.publishAnchor("batteryAnchor", batteryButton);
                    }
                    function onBrightnessOpenChanged() {
                        if (GlobalStates.brightnessOpen)
                            root.publishAnchor("brightnessAnchor", brightnessButton);
                    }
                    function onTrayOpenChanged() {
                        if (GlobalStates.trayOpen)
                            root.publishAnchor("trayAnchor", trayButton);
                    }
                }
                Connections {
                    target: controlButton
                    function onXChanged() { root.publishAnchor("controlPanelAnchor", controlButton) }
                    function onWidthChanged() { root.publishAnchor("controlPanelAnchor", controlButton) }
                }
                Connections {
                    target: volumeButton
                    function onXChanged() { root.publishAnchor("volumeAnchor", volumeButton) }
                    function onWidthChanged() { root.publishAnchor("volumeAnchor", volumeButton) }
                }
                Connections {
                    target: notifButton
                    function onXChanged() { root.publishAnchor("notificationAnchor", notifButton) }
                    function onWidthChanged() { root.publishAnchor("notificationAnchor", notifButton) }
                }
                // A transient popup arrives without opening the centre, so refresh the anchor on
                // arrival too; otherwise the popup lands wherever the last geometry change left it.
                Connections {
                    target: Notifications
                    function onPopupListChanged() {
                        if (Notifications.popupList.length > 0)
                            root.publishAnchor("notificationAnchor", notifButton);
                    }
                }
                Connections {
                    target: networkButton
                    function onXChanged() { root.publishAnchor("networkAnchor", networkButton) }
                    function onWidthChanged() { root.publishAnchor("networkAnchor", networkButton) }
                }
                Connections {
                    target: batteryButton
                    function onXChanged() { root.publishAnchor("batteryAnchor", batteryButton) }
                    function onWidthChanged() { root.publishAnchor("batteryAnchor", batteryButton) }
                }
                Connections {
                    target: brightnessButton
                    function onXChanged() { root.publishAnchor("brightnessAnchor", brightnessButton) }
                    function onWidthChanged() { root.publishAnchor("brightnessAnchor", brightnessButton) }
                }
                Connections {
                    target: trayButton
                    function onXChanged() { root.publishAnchor("trayAnchor", trayButton) }
                    function onWidthChanged() { root.publishAnchor("trayAnchor", trayButton) }
                }
            }
        }
    }
}
