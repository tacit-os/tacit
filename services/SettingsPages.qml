pragma Singleton

import qs.services
import Quickshell

/**
 * The settings pages, once. The panel's rail (modules/ii/settings/SettingsContent.qml) and the
 * palette's Settings section both read this list, so a page added or regrouped here reaches both
 * and neither can be missing one the other has.
 *
 * `key` is what the palette and the `settings page <name>` IPC send; `name` is only ever shown,
 * so it may be translated; `path` is the file under modules/ii/settings/pages, which the
 * palette's keyword harvester greps for the section titles inside the page.
 */
Singleton {
    id: root

    readonly property var list: {
        const pages = [
            { key: "Quick",     name: Translation.tr("Quick"),     icon: "instant_mix",    iconRotation: 0,   path: "QuickConfig.qml" },
            { key: "General",   name: Translation.tr("General"),   icon: "browse",         iconRotation: 0,   path: "GeneralConfig.qml" },
            { key: "Notch",     name: Translation.tr("Notch"),     icon: "call_to_action", iconRotation: 0,   path: "NotchConfig.qml" },
            { key: "Network",   name: Translation.tr("Network"),   icon: "wifi",           iconRotation: 0,   path: "NetworkConfig.qml" },
            { key: "Bluetooth", name: Translation.tr("Bluetooth"), icon: "bluetooth",      iconRotation: 0,   path: "BluetoothConfig.qml" },
            { key: "Desktop",   name: Translation.tr("Desktop"),   icon: "texture",        iconRotation: 0,   path: "BackgroundConfig.qml" },
            { key: "Interface", name: Translation.tr("Interface"), icon: "bottom_app_bar", iconRotation: 0,   path: "InterfaceConfig.qml" },
            { key: "Services",  name: Translation.tr("Services"),  icon: "settings",       iconRotation: 0,   path: "ServicesConfig.qml" }
        ];
        // The compositor's own page is the one the machine is running under
        if (WM.compositor === "hyprland")
            pages.push({ key: "Hyprland", name: Translation.tr("Hyprland"), icon: "select_window_2", iconRotation: 0, path: "HyprlandConfig.qml" });
        if (WM.compositor === "niri")
            pages.push({ key: "Niri", name: Translation.tr("Niri"), icon: "select_window_2", iconRotation: 0, path: "NiriConfig.qml" });
        pages.push({ key: "About", name: Translation.tr("About"), icon: "info", iconRotation: 0, path: "About.qml" });
        return pages;
    }
}
