pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs

Singleton {
    id: root
    property var items: []
    property int maxItems: 30

    // Persisted like the to-do list (services/Todo.qml): parked files survive a shell restart
    // (boring.notch ShelfPersistenceService). Missing files are pruned on load.
    // Every Tacit program that touches the shelf (the desktop, Settings, Pinax) keeps its own copy of this list, so the
    // file is the shared state: each copy re-reads it when another one writes, and writes only what changed. Before, a
    // copy that had not heard of a Clear wrote its old list back with the next file it parked, and the pictures returned.
    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/shelf.json`)
    property bool loaded: false
    property string saved: ""           // the text last read from or written to the file
    onItemsChanged: {
        if (!root.loaded)
            return
        const text = JSON.stringify(root.items)
        if (text === root.saved)
            return
        root.saved = text
        shelfFile.setText(text)
    }
    Component.onCompleted: shelfFile.reload()

    FileView {
        id: shelfFile
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const first = !root.loaded
            let list = []
            try {
                const parsed = JSON.parse(shelfFile.text())
                list = Array.isArray(parsed) ? parsed.filter(p => typeof p === "string") : []
            } catch (e) {
                // a file that cannot be read after the first time is not a shelf with nothing on it
                if (!first)
                    return
            }
            // our own write coming back, or a re-read that changed nothing, leaves the list alone
            if (first || JSON.stringify(list) !== root.saved) {
                root.saved = JSON.stringify(list)
                root.items = list
            }
            root.loaded = true
            if (first)
                root.prune()
        }
        onLoadFailed: (error) => {
            root.loaded = true
            if (error == FileViewError.FileNotFound)
                shelfFile.setText("[]")
        }
    }

    function addItems(urls) {
        let arr = [...items]
        for (const url of urls) {
            // a link or an image dragged from a browser is not a file to park
            if (!url.toString().startsWith("file://")) continue
            // Producers percent-encode the path, as a dropped url is; one that did not leaves a stray "%"
            // that decodeURIComponent throws on, and its text is kept as it is
            let raw = url.toString()
            try { raw = decodeURIComponent(raw) } catch (e) {}
            const path = FileUtils.trimFileProtocol(raw)
            if (arr.includes(path)) continue
            // A full shelf makes room instead of swallowing the drop and opening with nothing new
            if (arr.length >= root.maxItems)
                arr.shift()
            arr.push(path)
        }
        // Only a real change: reassigning the same list rebuilds every tile, and a tile that is
        // the source of the drag being dropped dies under Qt's feet (the shell crashed on a
        // shelf tile dropped back onto the notch).
        if (arr.length !== items.length || arr.some((p, i) => p !== items[i]))
            root.items = arr
    }

    function show(urls, x, y, screen) {
        root.addItems(urls)
        GlobalStates.dropShelfX = x
        GlobalStates.dropShelfY = y
        GlobalStates.dropShelfScreen = screen ?? null
        GlobalStates.dropShelfOpen = true
    }

    // Copy puts what a paste can use: a lone picture goes as the picture (and as its file, both at once, by the Viewer's
    // viewer-copy), so it pastes into a chat or an editor; wl-copy offers one type only and a picture sent as a list of
    // file links pasted nowhere. Anything else goes as file links, which Pinax and file managers take. Said once it is on
    // the clipboard, never before.
    signal copied(string words)
    signal copyFailed()
    function copyAll() {
        if (root.items.length === 0 || copyProc.running) return
        const one = root.items.length === 1 ? root.items[0] : ""
        if (/\.(png|jpe?g|webp|bmp|gif)$/i.test(one)) {
            copyProc.words = `Copied · ${one.split("/").pop()}`
            copyProc.command = ["sh", Quickshell.shellPath("scripts/viewer/viewer-copy"), one, "image"]
        } else {
            // percent-encoded paths, one per line: Recents reads a multi-file copy by the "\n" after each uri
            const uriList = root.items.map(p => FileUtils.fileUrl(p)).join("\n")
            copyProc.words = root.items.length === 1 ? `Copied · ${one.replace(/\/$/, "").split("/").pop()}` : `Copied · ${root.items.length} files`
            copyProc.command = ["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(uriList)}' | wl-copy --type text/uri-list`]
        }
        copyProc.running = true
    }

    function remove(path) {
        root.items = root.items.filter(p => p !== path)
    }

    // Drop entries whose file is gone (boring.notch ShelfStateViewModel.cleanupInvalidItems). One on a drive that is not
    // mounted (/run/media/<user>/<label>, /media/<user>/<label>, /mnt/<label>, as Pinax reads them) is kept: nothing mounts
    // a stick at login, and its files are back when it is.
    function prune() {
        if (root.items.length === 0) return
        pruneProc.running = false
        pruneProc.running = true
    }

    Process {
        id: pruneProc
        command: ["bash", "-c", `for f in ${root.items.map(p => `'${StringUtils.shellSingleQuoteEscape(p)}'`).join(" ")}; do [ -e "$f" ] && continue; `
            + `[[ $f =~ ^/(run/media/[^/]+|media/[^/]+|mnt)/[^/]+ ]] && ! mountpoint -q "$BASH_REMATCH" && continue; printf '%s\n' "$f"; done`]
        stdout: SplitParser {
            onRead: line => { const p = line.trim(); if (p.length > 0) root.remove(p) }
        }
    }

    function clear() {
        root.items = []
        GlobalStates.dropShelfOpen = false
    }

    function hide() {
        GlobalStates.dropShelfOpen = false
    }

    // qs -c tacit ipc call shelf add /path/to/file   (scripts can park files on the notch)
    IpcHandler {
        target: "shelf"

        function add(path: string): void {
            root.addItems([path.startsWith("file://") ? path : "file://" + encodeURI(path)]);
        }

        function clear(): void {
            root.clear();
        }

        function remove(path: string): void {
            root.remove(path);
        }
    }

    Process {
        id: copyProc
        property string words: ""
        onExited: code => {
            // viewer-copy answers 3 when only the picture's file went (no PNG could be made from it), 4 when only the
            // picture did (no viewer-clip to offer both)
            if (code === 0 || code === 3 || code === 4)
                root.copied(code === 3 ? "Copied the file, not the picture" : code === 4 ? "Copied the picture, not the file" : copyProc.words)
            else
                root.copyFailed()
        }
    }
}
