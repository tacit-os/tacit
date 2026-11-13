pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.services

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    property list<string> variantCodes: []     // each layout's variant, "" for none (the on-screen keyboard's labels)
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property bool needsLayoutRefresh: false

    // Update the layout code according to the layout name (Hyprland gives the name not the code)
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (WM.compositor !== "hyprland") return;
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName];
        } else {
            getLayoutProc.running = true;
        }
    }

    // Get the layout code from the base.lst file by grabbing the line with the current layout name
    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                const foundLine = lines.find(line => {
                    // Skip comment lines and empty lines
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    // Match layout: (whitespace + ) key + whitespace + description
                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1];
                        root.currentLayoutCode = matchLayout[1];
                        return true;
                    }

                    // Match variant: (whitespace + ) variant + whitespace + key + whitespace + description
                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout;
                        root.currentLayoutCode = complexLayout;
                        return true;
                    }
                    
                    return false;
                });
            }
        }
    }

    // Find out available layouts and current active layout. Should only be necessary on init
    Process {
        id: fetchLayoutsProc
        running: WM.compositor === "hyprland"
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                let hyprlandKeyboard;
                try {
                    hyprlandKeyboard = JSON.parse(devicesCollector.text)["keyboards"].find(kb => kb.main === true);
                } catch (e) {
                    return; // hyprctl not up yet, or no main keyboard: keep what we have
                }
                if (!hyprlandKeyboard)
                    return;
                root.variantCodes = (hyprlandKeyboard["variant"] ?? "").split(",");
                root.layoutCodes = hyprlandKeyboard["layout"].split(",");
                root.currentLayoutName = hyprlandKeyboard["active_keymap"];
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                if (root.needsLayoutRefresh) {
                    root.needsLayoutRefresh = false;
                    fetchLayoutsProc.running = true;
                }

                // A layout added by `hyprctl keyword` never sends configreloaded: refetch
                // the codes when the event names a layout we did not know about.
                if (root.layoutCodes.length <= 1)
                    fetchLayoutsProc.running = true;

                const dataString = event.data;
                const layoutName = dataString.substring(dataString.indexOf(",") + 1);
                // A virtual keyboard (wtype, when Flow types) has no layout name: Hyprland says "error", then the
                // real layout comes back. Neither the indicator nor the on-screen keyboard's setting follows it.
                if (layoutName.length === 0 || layoutName.toLowerCase() === "error")
                    return;
                root.currentLayoutName = layoutName;

                // The on-screen keyboard looks this value up by full name in layouts.js
                // ("English (US)", "German", "Russian"), so the trimmed "English" matched nothing
                // and it fell back to US on a machine whose layout it had just been told.
                if (Config.options.osk.layout !== root.currentLayoutName)	// a config write, only when it changes
                    Config.options.osk.layout = root.currentLayoutName;
            } else if (event.name == "configreloaded") {
                root.needsLayoutRefresh = true;
            }
        }
    }
}