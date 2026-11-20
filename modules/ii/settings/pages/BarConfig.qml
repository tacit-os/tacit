import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The new top bar's options: which indicators it carries. Each one opens a drawer that wears
 * the bar's own surface, so showing or hiding a button here also decides which drawers can be
 * opened from the strip. The older bar's layout and frame settings stay under Quick.
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

    ContentSection {
        icon: "bottom_app_bar"
        title: Translation.tr("Top bar")
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
