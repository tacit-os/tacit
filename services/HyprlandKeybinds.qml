pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses the `get_keybinds.py` script to parse comments in config files in a certain format and convert to JSON.
 */
Singleton {
    id: root
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    // An install has no ~/.config/hypr: the session's own copy under TACIT_HYPR holds the keys there. The person's copy wins.
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string shippedKeybindConfigPath: `${Quickshell.env("TACIT_HYPR") || "/usr/share/tacit/hypr"}/hyprland/keybinds.lua`
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
    // the session's own keys (Super+Space, Super+Shift+Space, Super+Escape), which Hyprland reads from TACIT_HYPR
    property string sessionKeybindConfigPath: `${Quickshell.env("TACIT_HYPR") || "/usr/share/tacit/hypr"}/tacit/keybinds.lua`
    property var defaultKeybinds: {"children": []}
    property var sessionKeybinds: {"children": []}
    property var userKeybinds: {"children": []}
    // The keys above a file's first section header are the parser's top-level `keybinds`; they
    // were left out, which hid SUPER+Tab, SUPER+N and every key in custom/keybinds.lua.
    function topSection(parsed, name) {
        const top = parsed.keybinds ?? [];
        return top.length > 0 ? [{ "name": name, "keybinds": top, "children": [] }] : [];
    }
    // Settings > Shortcuts (Shortcuts.qml) moves a key to others or takes it off, and gives apps keys of their own; the
    // compositor does as it says (tacit/shortcuts.lua), so the list does too, or it named keys that no longer worked
    function asBind(combo, comment) {
        const parts = Shortcuts.forHypr(combo).split("+");
        return { "mods": parts.slice(0, -1), "key": parts[parts.length - 1], "comment": comment };
    }
    function withShortcuts(section, moved) {
        return {
            "name": section.name,
            "keybinds": [].concat(...(section.keybinds ?? []).map(b => {
                const to = moved[Shortcuts.norm([...b.mods, b.key].join("+"))];
                return to === undefined ? [b] : to === "" ? [] : [Object.assign({}, b, root.asBind(to, b.comment))];
            })),
            "children": (section.children ?? []).map(c => root.withShortcuts(c, moved))
        };
    }
    property var keybinds: {
        const moved = {};
        for (const m of Shortcuts.moves(Shortcuts.changed))
            moved[Shortcuts.norm(m[0])] = m[1];
        const apps = Shortcuts.apps.filter(a => (a.keys ?? "") !== "").map(a => root.asBind(a.keys, `App: ${a.name}`));
        return {
            children: [
                ...root.topSection(defaultKeybinds, "Shell"),
                ...(defaultKeybinds.children ?? []),
                ...root.topSection(sessionKeybinds, "Tacit"),
                ...(sessionKeybinds.children ?? []),
                ...root.topSection(userKeybinds, "Your keys"),
                ...(userKeybinds.children ?? []),
            ].map(s => root.withShortcuts(s, moved)).concat(apps.length > 0 ? [{ "name": "Your shortcuts", "keybinds": apps, "children": [] }] : [])
        };
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getDefaultKeybinds.running = true
                getSessionKeybinds.running = true
                getUserKeybinds.running = true
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: ["sh", "-c", 'p="$2"; [ -r "$p" ] || p="$3"; exec "$1" --path "$p"', "sh",
            root.keybindParserPath, root.defaultKeybindConfigPath, root.shippedKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.defaultKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }

    Process {
        id: getSessionKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.sessionKeybindConfigPath]

        stdout: SplitParser {
            onRead: data => {
                try {
                    root.sessionKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.userKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}

