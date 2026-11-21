import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The top bar and the notch. Show or hide the strip; when it is off the shell returns to the
 * pre-bar layout (control panel bottom-right, notifications at the top corner, notch
 * standalone). Height and indicators apply only while the bar is shown.
 */
ContentPage {
    id: page
    forceWidth: true

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                const child = rootItem.children[i];
                if (child.title && child.title.toLowerCase().includes(t))
                    return child;
            }
            for (let i = 0; i < rootItem.children.length; i++) {
                const found = findTarget(rootItem.children[i]);
                if (found) return found;
            }
            return null;
        }

        const target = findTarget(page.contentItem);
        if (target) {
            const pos = target.mapToItem(page.contentItem, 0, 0);
            page.contentY = Math.max(0, pos.y);
        }
    }

    readonly property bool barShown: Config.options.bar.show

    ContentSection {
        icon: "bottom_app_bar"
        title: Translation.tr("Top bar")
        shape: MaterialShape.Shape.ClamShell
        Layout.fillWidth: true

        GroupedList {
            ConfigSwitch {
                buttonIcon: "bottom_app_bar"
                text: Translation.tr("Show bar")
                checked: Config.options.bar.show
                onSwitched: value => { Config.options.bar.show = value }
            }
        }
    }

    ContentSection {
        icon: "notch"
        title: Translation.tr("Notch")
        shape: MaterialShape.Shape.Cookie4Sided
        Layout.fillWidth: true

        GroupedList {
            ConfigSelectionArray {
                Layout.fillWidth: true
                icon: "notch"
                text: Translation.tr("Notch colour")
                currentValue: Config.options.island.bodyStyle
                onSelected: newValue => { Config.options.island.bodyStyle = newValue; }
                options: page.barShown ? [
                    { displayName: Translation.tr("Dark"), icon: "contrast", value: "solid" },
                    { displayName: Translation.tr("Follow the bar"), icon: "bottom_app_bar", value: "bar" }
                ] : [
                    { displayName: Translation.tr("Dark"), icon: "contrast", value: "solid" }
                ]
            }
        }
    }

    ContentSection {
        visible: page.barShown
        icon: "height"
        title: Translation.tr("Height")
        shape: MaterialShape.Shape.ClamShell
        Layout.fillWidth: true

        GroupedList {
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Bar height")
                value: Config.options.bar.height
                from: 36
                to: 56
                stepSize: 2
                onValueChanged: { Config.options.bar.height = value }
            }
        }
    }

    ContentSection {
        visible: page.barShown
        icon: "bottom_app_bar"
        title: Translation.tr("Indicators")
        shape: MaterialShape.Shape.ClamShell
        Layout.fillWidth: true

        GroupedList {
            ConfigSwitch {
                buttonIcon: "expand_more"
                text: Translation.tr("System tray button")
                checked: Config.options.bar.showTrayButton
                onSwitched: value => { Config.options.bar.showTrayButton = value }
            }
            ConfigSwitch {
                buttonIcon: "battery"
                text: Translation.tr("Battery button and drawer")
                checked: Config.options.bar.showBatteryButton
                onSwitched: value => { Config.options.bar.showBatteryButton = value }
            }
            ConfigSwitch {
                buttonIcon: "percent"
                text: Translation.tr("Show battery percentage in bar")
                checked: Config.options.bar.showBatteryPercentage
                onSwitched: value => { Config.options.bar.showBatteryPercentage = value }
            }
            ConfigSwitch {
                buttonIcon: "wifi"
                text: Translation.tr("Network button and drawer")
                checked: Config.options.bar.showNetworkButton
                onSwitched: value => { Config.options.bar.showNetworkButton = value }
            }
            ConfigSwitch {
                buttonIcon: "volume"
                text: Translation.tr("Volume button and drawer")
                checked: Config.options.bar.showVolumeButton
                onSwitched: value => { Config.options.bar.showVolumeButton = value }
            }
            ConfigSwitch {
                buttonIcon: "brightness"
                text: Translation.tr("Brightness button and drawer")
                checked: Config.options.bar.showBrightnessButton
                onSwitched: value => { Config.options.bar.showBrightnessButton = value }
            }
            ConfigSwitch {
                buttonIcon: "tune"
                text: Translation.tr("Control panel button")
                checked: Config.options.bar.showControlButton
                onSwitched: value => { Config.options.bar.showControlButton = value }
            }
            ConfigSwitch {
                buttonIcon: "bell"
                text: Translation.tr("Notifications button")
                checked: Config.options.bar.showNotificationsButton
                onSwitched: value => { Config.options.bar.showNotificationsButton = value }
            }
        }
    }
}
