pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property alias folderModel: presetsFolderModel
    property alias onlineFolderModel: onlinePresetsFolderModel
    property alias importedFolderModel: importedPresetsFolderModel

    FolderListModel {
        id: presetsFolderModel
        folder: Qt.resolvedUrl(Directories.userPresetsPath)
        showDirs: false
        nameFilters: ["*.json"]
    }

    FolderListModel {
        id: onlinePresetsFolderModel
        folder: Qt.resolvedUrl(`${Quickshell.env("HOME")}/.cache/quickshell/presets`)
        showDirs: false
        nameFilters: ["*.json"]
    }

    FolderListModel {
        id: importedPresetsFolderModel
        folder: Qt.resolvedUrl(`${Quickshell.env("HOME")}/.cache/quickshell/presets_imported`)
        showDirs: false
        nameFilters: ["*.json"]
    }

    function refresh() {
        const current = presetsFolderModel.folder
        presetsFolderModel.folder = ""
        presetsFolderModel.folder = current
    }

    function refreshOnline() {
        const current = onlinePresetsFolderModel.folder
        onlinePresetsFolderModel.folder = ""
        onlinePresetsFolderModel.folder = current
    }

    function refreshImported() {
        const current = importedPresetsFolderModel.folder
        importedPresetsFolderModel.folder = ""
        importedPresetsFolderModel.folder = current
    }

    // A save, an overwrite or an import that failed: presets.sh's own reason (it exits 1 with "Error: ..." on stderr),
    // for the line under the preset rows; "" again once one goes through or another starts
    property string error: ""
    function report(code, said, fallback) {
        const line = (said ?? "").trim().split("\n").filter(l => l.trim().length > 0).pop()?.trim().replace(/^Error:\s*/, "") ?? ""
        root.error = code === 0 ? "" : line.length > 0 ? line.charAt(0).toUpperCase() + line.slice(1) : fallback
    }

    Process {
        id: saveProc
        stderr: StdioCollector { id: saveSaid }
        onExited: (code, status) => {
            root.report(code, saveSaid.text, Translation.tr("The preset could not be saved"))
            root.refresh()
        }
    }

    Process {
        id: deleteProc
        onExited: root.refresh()
    }

    Process {
        id: deleteOnlineProc
        onExited: root.refreshOnline()
    }

    Process {
        id: deleteImportedProc
        onExited: root.refreshImported()
    }

    Process {
        id: overwriteProc
        stderr: StdioCollector { id: overwriteSaid }
        onExited: (code, status) => {
            root.report(code, overwriteSaid.text, Translation.tr("The preset could not be saved"))
            root.refresh()
            root.refreshOnline()
            root.refreshImported()
        }
    }

    Process {
        id: exportZipProc
    }

    Process {
        id: importZipProc
        stderr: StdioCollector { id: importSaid }
        onExited: (code, status) => {
            root.report(code, importSaid.text, Translation.tr("The preset could not be imported"))
            root.refreshImported()
        }
    }

    function save(rawInput) {
        const raw = rawInput.trim()
        if (raw.length === 0) return

        const commaIndex = raw.indexOf(",")
        let name = raw
        let description = ""

        if (commaIndex !== -1) {
            name = raw.substring(0, commaIndex).trim()
            description = raw.substring(commaIndex + 1).trim()
        }

        // the name is a file name in the presets folder: no slashes, and no leading dot (".." or a hidden file)
        name = name.replace(/[\/\s]/g, "_").replace(/^\.+/, "")
        if (name.length === 0) return

        root.error = ""
        saveProc.command = ["bash", Directories.presetsScriptPath, "--save", name, description]
        saveProc.running = true
    }

    function apply(name) {
        GlobalStates.settingsOpen = false
        Wallpapers.confirmedPath = ""
        Wallpapers.previewPath = ""
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name])
    }

    function applyOnline(name) {
        GlobalStates.settingsOpen = false
        Wallpapers.confirmedPath = ""
        Wallpapers.previewPath = ""
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name, "--online"])
    }

    function remove(name) {
        deleteProc.command = ["bash", Directories.presetsScriptPath, "--remove", name]
        deleteProc.running = true
    }

    function removeOnline(name) {
        deleteOnlineProc.command = ["bash", Directories.presetsScriptPath, "--remove", name, "--online"]
        deleteOnlineProc.running = true
    }

    function removeImported(name) {
        deleteImportedProc.command = ["bash", Directories.presetsScriptPath, "--remove", name, "--imported"]
        deleteImportedProc.running = true
    }

    function applyImported(name) {
        GlobalStates.settingsOpen = false
        Wallpapers.confirmedPath = ""
        Wallpapers.previewPath = ""
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name, "--imported"])
    }

    // source: "" for a saved preset, "--online" or "--imported" for the card's own folder
    function overwrite(name, source = "") {
        // Overwrite with same name (presets.sh --save filters General+Services)
        root.error = ""
        overwriteProc.command = ["bash", Directories.presetsScriptPath, "--save", name, ...(source ? [source] : [])]
        overwriteProc.running = true
    }

    function exportZip(name, source = "") {
        exportZipProc.command = ["bash", Directories.presetsScriptPath, "--export-zip", name, ...(source ? [source] : [])]
        exportZipProc.running = true
    }

    function importZip(path) {
        const clean = String(path).replace(/^file:\/\//, "")
        root.error = ""
        importZipProc.command = ["bash", Directories.presetsScriptPath, "--import-zip", clean]
        importZipProc.running = true
    }
}
