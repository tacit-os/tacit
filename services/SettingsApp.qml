pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

/**
 * The one way the shell opens Settings, which runs as its own process (tacit-settings.qml). Every
 * button, menu row and palette result goes through here, and so do the old panel's `settings`
 * IPC and shortcut, so nothing opens the old in-shell panel by accident.
 */
Singleton {
    id: root
    readonly property string opener: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/settings/open.sh"))

    // page: a key of SettingsCatalog; "" keeps whatever page Settings is on
    function open(page: string): void {
        Quickshell.execDetached([root.opener, page ?? ""]);
    }
    function toggle(): void {
        Quickshell.execDetached([root.opener, "--toggle"]);
    }

    // The old panel's page names ("Notch", or "Notch:search term"), for links and scripts
    // written against it.
    readonly property var oldPages: ({
        "Quick": "look", "General": "look", "Bar": "desktop", "Notch": "notch", "Network": "network",
        "Bluetooth": "bluetooth", "Desktop": "look", "Interface": "desktop", "Services": "apps",
        "Hyprland": "windows", "Niri": "windows", "About": "about"
    })
    function keyFor(name: string): string {
        const head = (name ?? "").split(":")[0];
        const isKey = k => SettingsCatalog.categories.some(c => c.key === k);
        if (isKey(head))
            return head;
        if (root.oldPages[head] !== undefined)
            return root.oldPages[head];
        // in another case ("Sound", "NETWORK", "hyprland"), after the exact ones: the old "Desktop" is not "desktop"
        const lower = head.toLowerCase();
        if (isKey(lower))
            return lower;
        const old = Object.keys(root.oldPages).find(k => k.toLowerCase() === lower);
        return old !== undefined ? root.oldPages[old] : "";
    }
}
