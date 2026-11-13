pragma Singleton

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * What the command palette needs from the old launcher: the `/action` list (built in and the
 * user's own scripts) and the clipboard work-safety tests. The palette's Settings results come
 * from services/SettingsCatalog.qml. The launcher's own flat result list lived here too and had
 * no reader left once services/PaletteSearch.qml took over; the palette is the one search model now.
 */
Singleton {
    id: root

    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    label: actionName,
                    hint: Translation.tr("Runs your script %1").arg(fileName),
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // An API key handed to the keyring: saved, or held in memory until the keyring opens, as Settings > Accounts says of
    // a locked one; a reload before then loses it, so it is not called saved
    function keySaid(app, saved) {
        Quickshell.execDetached(["notify-send", app, saved ? Translation.tr("API key saved!")
            : Translation.tr("The keyring is locked; the key is saved once you unlock the screen with your password"), "-a", "Shell"]);
    }

    property var searchActions: [
        {
            action: "accentcolor",
            label: Translation.tr("Accent colour"),
            hint: Translation.tr("Sets the accent colour from a hex code, e.g. #674737"),
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "superpaste",
            label: Translation.tr("Paste several"),
            hint: Translation.tr("Pastes the last N clipboard entries; 4i pastes the last 4 images"),
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            label: Translation.tr("Add a to-do"),
            hint: Translation.tr("Adds the text after it to your to-do list"),
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            hidden: true, // repeats the palette's System row
            execute: () => {
                Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`)
            }
        },
        {
            action: "wipeclipboard",
            label: Translation.tr("Clear clipboard history"),
            hint: Translation.tr("Deletes every saved clipboard entry"),
            execute: () => {
                // Cliphist.wipe() runs `cliphist wipe` and clears the in-memory entries; the raw
                // rm left the launcher listing history it could no longer decode.
                Cliphist.wipe();
                Quickshell.execDetached(["notify-send", Translation.tr("Clipboard"), Translation.tr("Clipboard history wiped"), "-a", "Shell"]);
            }
        },
        {
            action: "unsplash",
            label: Translation.tr("Unsplash key"),
            hint: Translation.tr("Saves your Unsplash API key for the online wallpaper browser"),
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("Usage: /unsplash YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "unsplash"], args.trim(), saved => root.keySaid("Unsplash", saved));
            }
        },
        {
            action: "wallhaven",
            label: Translation.tr("Wallhaven key"),
            hint: Translation.tr("Saves your Wallhaven API key for the online wallpaper browser"),
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("Usage: /wallhaven YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "wallhaven"], args.trim(), saved => root.keySaid("Wallhaven", saved));
            }
        },
        {
            action: "pexels",
            label: Translation.tr("Pexels key"),
            hint: Translation.tr("Saves your Pexels API key for the online wallpaper browser"),
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("Usage: /pexels YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "pexels"], args.trim(), saved => root.keySaid("Pexels", saved));
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts).filter(a => !a.hidden)

    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }
}
