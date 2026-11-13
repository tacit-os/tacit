pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Files, the desktop's own file surface (modules/ii/files). This singleton is what the rest
 * of the desktop talks to: open a window where your attention is, reveal a path, and the
 * places every window shares. Where a window opens is decided here and said once in its
 * status line: a file that arrived in the last ten minutes -> its folder with it selected;
 * a focused terminal -> its working directory; else the folder you were in last.
 *
 *   qs -c tacit ipc call files open
 *   qs -c tacit ipc call files reveal /path/to/file
 *   qs -c tacit ipc call files at /some/folder
 */
Singleton {
    id: root

    // The folders the Files windows show (FilesPanel keeps them here), carried over a reload of the shell: an update
    // reloads it, and the windows, which are the shell's own, closed with it and never came back. FilesPanel opens them
    // again once it is built; a shell that starts rather than reloads has none. The first child on purpose: a reload
    // pairs a singleton's old children with its new ones by place. shell.qml loads this singleton while the reload can
    // still hand it the old one.
    PersistentProperties {
        id: kept
        property var folders: []
    }
    function keepFolders(folders) {
        kept.folders = folders;
    }
    function keptFolders() {
        return kept.folders;
    }
    function load() {}

    // openRequested: a window shows this (the newest one if any, else a new one).
    // newRequested: always another window. focusRequested: bring the newest forward.
    signal openRequested(string folder, string select, string reason)
    signal newRequested(string folder, string select, string reason)
    signal focusRequested()
    // A drop: the windows look at where the cursor let go (Super released; also the
    // `files drop` call, so the gesture can be bound or tested without a keyboard).
    signal dropRequested()
    // The press that begins a Super+drag (`files dragstart`): a maximised window lets go
    // of the screen and floats under the hand, so the drag has something to move.
    signal dragStartRequested()
    // An action for the newest window, by name (`files act paste`): what the keys do,
    // reachable from a script or a bind.
    signal actRequested(string name)
    signal searchRequested(string query)   // `files search <q>`: a deep search in the newest window
    signal shelfRequested()                // `files shelf`: the parked files as a list
    signal saveRequested(string folder)    // `files save` / `savefolder`: the Save As window
    function openShelf() {
        if (root.windows > 0) { root.shelfRequested(); root.focusRequested(); }
        else { root.newRequested(root.lastFolder || root.home, "", ""); shelfAfterOpen.restart(); }
    }
    Timer { id: shelfAfterOpen; interval: 500; onTriggered: root.shelfRequested() }

    property int windows: 0
    // Each window takes its own Hyprland address once (see FilesWindow.client): they all share
    // a class and a title, and nothing else tells two of them apart.
    property var addresses: ({})
    function takeAddress(a) {
        let m = Object.assign({}, root.addresses);
        m[a] = true;
        root.addresses = m;
    }
    function releaseAddress(a) {
        root.setWindowFolder(a, "");
        if (!(a in root.addresses))
            return;
        let m = Object.assign({}, root.addresses);
        delete m[a];
        root.addresses = m;
    }
    function addressTaken(a) {
        return root.addresses[a] === true;
    }
    // The folder each window shows, by address (`files windows`, for Praxis's "Open here").
    property var folderByAddress: ({})
    function setWindowFolder(address, folder) {
        if (!address || (!folder && !(address in root.folderByAddress)))
            return;
        let m = Object.assign({}, root.folderByAddress);
        if (folder)
            m[address] = root.trim(folder);
        else
            delete m[address];
        root.folderByAddress = m;
    }
    // Picking for another app (the Claude app's attach): a Files window opens with a bar at its
    // foot; Choose hands the selection back over that app's IPC as `picked <json list>`. Cancel, and
    // closing the window without Choose, send `picked []`, so the asker is told the pick is over. The
    // JSON list is padded with a space each side: qs ipc reads an argument that starts with [ and ends
    // with ] as its own list syntax, which dropped `[]` and split two or more paths into too many arguments.
    // pickdir: for a folder; Choose with nothing selected takes the folder the window shows.
    // save: a file to be written, named in the Save As window (SaveWindow.qml); the answer is the one
    // full path (Files writes nothing). savefolder: a folder to write several files into.
    // asker: the app that asked, from the window that had the focus when the request came.
    property var picking: null        // { shell, target, label, dir, save, name, asker }
    // the app that asked: the window that had the focus when the request came
    function askerNow() {
        const t = ToplevelManager.activeToplevel;
        return t && t.appId !== Quickshell.appId ? (DesktopEntries.heuristicLookup(t.appId)?.name ?? "") : "";
    }
    // One pick at a time (pickDone answers the one pick for both windows): a second asker is told at once
    // that nothing was picked, and the window already waiting on you comes forward.
    function pickBusy(shell, target) {
        if (root.picking === null)
            return false;
        Quickshell.execDetached(["qs", "-p", shell, "ipc", "call", target, "picked", " [] "]);
        root.focusRequested();
        return true;
    }
    function pick(folder, shell, target, label, dir) {
        if (root.pickBusy(shell, target))
            return;
        root.picking = { "shell": shell, "target": target, "label": label, "dir": dir === true, "asker": root.askerNow() };
        root.openNewAt(folder.length ? folder : root.home);
    }
    function save(folder, name, shell, target, label, dir) {
        if (root.pickBusy(shell, target))
            return;
        root.picking = { "shell": shell, "target": target, "label": label, "dir": dir === true, "save": true, "name": name, "asker": root.askerNow() };
        root.saveRequested(folder.length ? root.trim(folder) : "");
    }
    // Where Save As put things, newest first: the Save As window's folder chips.
    property var saveFolders: []
    function savedIn(folder) {
        const f = root.trim(folder);
        root.saveFolders = [f].concat(root.saveFolders.filter(x => x !== f)).slice(0, 8);
        saveTimer.restart();
    }
    function pickDone(paths) {
        const p = root.picking;
        root.picking = null;
        if (p)
            Quickshell.execDetached(["qs", "-p", p.shell, "ipc", "call", p.target, "picked", ` ${JSON.stringify(paths)} `]);
    }
    property string lastFolder: ""
    // Pinax's last copy or cut, one for every window (a window's own went stale the moment another window or app
    // copied): { op: "copy" | "cut", paths, at }. The clipboard is the truth at a paste (FilesWindow.paste); this is
    // the verb it carries and the cut rows drawn faint.
    property var clip: null
    property var viewByFolder: ({})   // folder -> "list" | "grid", once chosen
    property var sizeByFolder: ({})   // folder -> the grid's icon size (1 = as made), once changed
    // How you left the window: its size, floating or tiled, maximised. The next one opens
    // exactly so. One rule, no cases.
    property var windowState: ({ "w": 1000, "h": 640, "floating": true, "maximised": false })
    // The trash the rest of the desktop uses: gio and the job runner both honour
    // XDG_DATA_HOME, so the window, the rail and this count must read it from the same place.
    readonly property string trashDir: {
        const x = Quickshell.env("XDG_DATA_HOME") ?? "";
        return (x.length > 0 ? x : root.home + "/.local/share") + "/Trash/files";
    }
    // The trash's count, for the rail, with what is in the trashes gio makes on other drives (a stick's .Trash-UID,
    // the shared .Trash/UID): the Trash view lists each as a folder under the drive's name (driveTrashes: [{ name,
    // path, count }], path its files folder). Only the home trash was listed, so a file deleted on a stick was nowhere
    // to be seen. Refreshed at start, after every job and when a drive comes or goes.
    property int trashCount: 0
    property var driveTrashes: []
    function driveOf(path) {
        return Devices.list.find(d => d.mountpoint.length > 0 && (path === d.mountpoint || path.startsWith(d.mountpoint + "/"))) ?? null;
    }
    Process {
        id: trashCounter
        command: ["bash", "-c", 'ls -1A "$1" 2>/dev/null | wc -l; shift; for m in "$@"; do for t in "$m/.Trash-$UID/files" "$m/.Trash/$UID/files"; do '
            + 'n=$(ls -1A "$t" 2>/dev/null | wc -l); if [ "$n" -gt 0 ]; then printf "%s\\t%s\\n" "$n" "$t"; fi; done; done', "_", root.trashDir]
            .concat(Devices.list.filter(d => d.mountpoint.length > 0).map(d => d.mountpoint))
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const drives = [];
                for (const l of lines.slice(1)) {
                    const [n, path] = l.split("\t");
                    const dev = root.driveOf(path ?? "");
                    if (dev)
                        drives.push({ "name": Devices.nameFor(dev), "path": path, "count": parseInt(n) || 0 });
                }
                root.driveTrashes = drives;
                root.trashCount = (parseInt(lines[0]) || 0) + drives.reduce((a, t) => a + t.count, 0);
            }
        }
    }
    Timer { id: trashLater; interval: 600; onTriggered: trashCounter.running = true }
    Connections {
        target: Jobs
        function onJobFinished(job) { trashLater.restart(); }
    }
    Connections {
        target: Devices
        function onListChanged() { trashLater.restart(); }
    }
    // When each place was last looked at: a place with arrivals since then shows a dot.
    property var lastLooked: ({})
    function looked(folder) {
        let m = Object.assign({}, root.lastLooked);
        m[root.trim(folder)] = Date.now();
        root.lastLooked = m;
        saveTimer.restart();
    }
    function hasNew(folder) {
        const f = root.trim(folder);
        const since = root.lastLooked[f] ?? 0;
        return Recents.items.some(i => (i.kind === "download" || i.kind === "screenshot") && i.at > since && root.parent(i.path) === f);
    }
    // Habits: where files of a kind from a source went when you moved them. Learned from
    // your own moves (a Files move job), never from anything automatic; offered on a row as
    // "-> Invoices" when two of the last three such moves went to the same place; never
    // acted on by itself. Visible and forgettable.
    property var habits: ({})   // "app|kind" -> [dest, dest, ...] newest last (last 6)
    function learnMove(fromPath, dest) {
        const origin = Origins.originFor(fromPath);
        const key = `${origin?.app || "-"}|${Things.kindOf(fromPath)}`;
        let h = Object.assign({}, root.habits);
        h[key] = (h[key] ?? []).concat([root.trim(dest)]).slice(-6);
        root.habits = h;
        saveTimer.restart();
    }
    // the folder two of the last three moves of this kind went to, if not the folder it is in
    function offerFor(path) {
        const origin = Origins.originFor(path);
        const key = `${origin?.app || "-"}|${Things.kindOf(path)}`;
        const last = (root.habits[key] ?? []).slice(-3);
        if (last.length < 2)
            return "";
        const counts = ({});
        for (const d of last) counts[d] = (counts[d] ?? 0) + 1;
        const best = Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0];
        if (counts[best] < 2 || best === root.parent(path))
            return "";
        return best;
    }
    function forgetHabits() {
        root.habits = ({});
        saveTimer.restart();
    }
    // Folders you pinned to the rail (a drop on the rail, or "Pin" on a folder), in order. A fixed
    // place may be pinned too (Praxis lists pins); this rail and the palette show it once, as the place.
    property var pins: []
    function pin(path) {
        const p = root.trim(path);
        if (p.length === 0 || root.pins.includes(p))
            return;
        root.pins = root.pins.concat([p]);
        saveTimer.restart();
    }
    function unpin(path) {
        root.pins = root.pins.filter(x => x !== root.trim(path));
        saveTimer.restart();
    }
    // A pinned folder to position `index` among the pins (clamped).
    function move(path, index) {
        const p = root.trim(path);
        if (!root.pins.includes(p))
            return;
        const rest = root.pins.filter(x => x !== p);
        const to = Math.max(0, Math.min(index, rest.length));
        rest.splice(to, 0, p);
        root.pins = rest;
        saveTimer.restart();
    }
    // Names you gave folders, {path: name}; any folder, pinned or not. An empty name clears it.
    property var names: ({})
    function rename(path, name) {
        const p = root.trim(path);
        const n = (name ?? "").trim();
        if (p.length === 0)
            return;
        let m = Object.assign({}, root.names);
        if (n.length > 0)
            m[p] = n;
        else
            delete m[p];
        root.names = m;
        saveTimer.restart();
    }
    // The rail: "auto" (compact when the window is narrow), or what Ctrl+B last chose.
    property string railPref: "auto"
    function setRailPref(v) {
        root.railPref = v;
        saveTimer.restart();
    }
    function rememberWindow(state) {
        root.windowState = Object.assign({}, root.windowState, state);
        saveTimer.restart();
    }
    readonly property string home: FileUtils.trimFileProtocol(Directories.home)
    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/files/state.json`)
    property bool loaded: false

    readonly property var places: [
        { "name": "Home", "path": root.home, "glyph": "home" },
        { "name": "Downloads", "path": FileUtils.trimFileProtocol(Directories.downloads), "glyph": "download" },
        { "name": "Documents", "path": FileUtils.trimFileProtocol(Directories.documents), "glyph": "description" },
        { "name": "Pictures", "path": FileUtils.trimFileProtocol(Directories.pictures), "glyph": "image" },
        { "name": "Music", "path": FileUtils.trimFileProtocol(Directories.music), "glyph": "music_note" },
        { "name": "Videos", "path": FileUtils.trimFileProtocol(Directories.videos), "glyph": "movie" },
        { "name": "Desktop", "path": FileUtils.trimFileProtocol(Directories.desktop), "glyph": "desktop_windows" }
    ]

    // The name you gave it; else "Downloads" for the downloads folder, "Home" for home, else the
    // folder's own name.
    function placeName(path) {
        const p = root.trim(path);
        if (root.names[p])
            return root.names[p];
        const place = root.places.find(x => x.path === p);
        if (place)
            return place.name;
        return p === "/" ? "/" : p.split("/").pop();
    }
    function trim(path) {
        const p = FileUtils.trimFileProtocol(path ?? "");
        return p.length > 1 ? p.replace(/\/+$/, "") : p;
    }
    function parent(path) {
        const p = root.trim(path);
        const i = p.lastIndexOf("/");
        return i <= 0 ? "/" : p.substring(0, i);
    }

    // ------------------------------------------------------------------ where to open
    function open(folder, select) {
        root.decide(folder, select, root.openRequested);
    }
    function openNew() {
        // A window created while a pick is outstanding reads Files.picking when it is built and
        // opens as a second picker; whichever one answers first clears the pick for both, so the
        // other one's Choose does nothing. The window that is waiting on you comes forward.
        if (root.picking !== null) {
            root.focusRequested();
            return;
        }
        root.decide("", "", root.newRequested);
    }
    function openNewAt(folder) {
        root.newRequested(root.trim(folder), "", "");
    }
    function decide(folder, select, emit) {
        if ((folder ?? "").length > 0) {
            emit(root.trim(folder), select ?? "", "");
            return;
        }
        const now = Date.now();
        const arrived = Recents.items.find(i => (i.kind === "download" || i.kind === "screenshot") && now - i.at < 600000);
        if (arrived) {
            const dir = root.parent(arrived.path);
            const age = Voice.age(arrived.at, now);
            emit(dir, arrived.path, Voice.because(root.placeName(dir), `${arrived.text} arrived ${age === "now" ? "just now" : age + " ago"}`));
            return;
        }
        if (Attention.terminal) {
            Attention.cwdOfFocused(cwd => {
                if (cwd.length > 0)
                    emit(root.trim(cwd), "", Voice.because(root.placeName(cwd), "your terminal is there"));
                else
                    emit(root.lastFolder || root.home, "", "");
            });
            return;
        }
        emit(root.lastFolder || root.home, "", "");
    }
    function reveal(path) {
        root.openRequested(root.parent(path), root.trim(path), "");
    }
    // Super+E: the open window if there is one, else a new one.
    function toggle() {
        if (root.windows > 0)
            root.focusRequested();
        else
            root.open("", "");
    }

    function remember(folder) {
        root.lastFolder = root.trim(folder);
        root.looked(folder);
        saveTimer.restart();
    }
    function viewFor(folder) {
        return root.viewByFolder[root.trim(folder)] ?? "";
    }
    function sizeFor(folder) {
        return root.sizeByFolder[root.trim(folder)] ?? 0;
    }
    function setSize(folder, size) {
        let next = Object.assign({}, root.sizeByFolder);
        if (size === 1) delete next[root.trim(folder)];
        else next[root.trim(folder)] = size;
        root.sizeByFolder = next;
        saveTimer.restart();
    }
    function setView(folder, view) {
        let next = Object.assign({}, root.viewByFolder);
        next[root.trim(folder)] = view;
        root.viewByFolder = next;
        saveTimer.restart();
    }

    IpcHandler {
        target: "files"
        function open(): void { root.open("", ""); }
        function another(): void { root.openNew(); }
        function toggle(): void { root.toggle(); }
        function reveal(path: string): void { root.reveal(path); }
        function at(folder: string): void { root.open(folder, ""); }
        function drop(): void { root.dropRequested(); }
        function dragstart(): void { root.dragStartRequested(); }
        function act(name: string): void { root.actRequested(name); }
        function search(query: string): void { root.searchRequested(query); }
        function shelf(): void { root.openShelf(); }
        function pick(folder: string, shell: string, target: string, label: string): void { root.pick(folder, shell, target, label, false); }
        function pickdir(folder: string, shell: string, target: string, label: string): void { root.pick(folder, shell, target, label, true); }
        // The asker is closing with its pick open: end it, so no Choose is left that answers nobody
        function cancelpick(target: string): void { if (root.picking?.target === target) root.pickDone([]); }
        function save(folder: string, name: string, shell: string, target: string, label: string): void { root.save(folder, name, shell, target, label, false); }
        function savefolder(folder: string, shell: string, target: string, label: string): void { root.save(folder, "", shell, target, label, true); }
        // The rail's pins and folder names, shared with Praxis (it writes only through these).
        function pin(path: string): void { root.pin(path); }
        function unpin(path: string): void { root.unpin(path); }
        function rename(path: string, name: string): void { root.rename(path, name); }
        function move(path: string, index: int): void { root.move(path, index); }
        // [{address, folder}] for every open window whose address is known
        function windows(): string {
            return JSON.stringify(Object.keys(root.folderByAddress).map(a => ({ "address": a, "folder": root.folderByAddress[a] })));
        }
    }
    CompositorGlobalShortcut {
        name: "filesToggle"
        description: "Files: focus the window, or open one"
        onPressed: root.toggle()
    }
    CompositorGlobalShortcut {
        name: "filesNew"
        description: "Files: open another window"
        onPressed: root.openNew()
    }

    // A job finishing while no Files window is in front is the notch's to say.
    Connections {
        target: Jobs
        function onJobFinished(job) {
            const filesInFront = Attention.app === Quickshell.appId && Attention.title === "Files";
            if (filesInFront)
                return;
            IslandController.request("copied", {
                "icon": job.state === "done" ? "check" : "error",
                "text": Jobs.label(job)
            }, 70);
        }
    }

    // ------------------------------------------------------------------ persistence
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: if (root.loaded) stateFile.setText(JSON.stringify({ "lastFolder": root.lastFolder, "viewByFolder": root.viewByFolder, "sizeByFolder": root.sizeByFolder, "window": root.windowState, "railPref": root.railPref, "pins": root.pins, "names": root.names, "habits": root.habits, "lastLooked": root.lastLooked, "saveFolders": root.saveFolders }))
    }
    Component.onCompleted: { stateFile.reload(); trashLater.restart(); }
    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            try {
                const p = JSON.parse(stateFile.text());
                root.lastFolder = p.lastFolder ?? "";
                root.viewByFolder = p.viewByFolder ?? ({});
                root.sizeByFolder = p.sizeByFolder ?? ({});
                if (p.window)
                    root.windowState = Object.assign({}, root.windowState, p.window);
                if (p.railPref)
                    root.railPref = p.railPref;
                if (Array.isArray(p.pins))
                    root.pins = p.pins;
                if (p.names && typeof p.names === "object")
                    root.names = p.names;
                if (p.habits && typeof p.habits === "object")
                    root.habits = p.habits;
                if (Array.isArray(p.saveFolders))
                    root.saveFolders = p.saveFolders;
                if (p.lastLooked && typeof p.lastLooked === "object")
                    root.lastLooked = p.lastLooked;
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: (error) => {
            root.loaded = true;
            if (error == FileViewError.FileNotFound)
                stateFile.setText("{}");
        }
    }
}
