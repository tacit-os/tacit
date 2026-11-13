import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.claude as Praxis

/**
 * Where the editor starts when no project was given: recent projects first, then
 * every git repository under the home folder. Type to narrow, Enter or click to open.
 * A path typed into the same field (starting with / or ~) lists the folders there instead, so any folder opens,
 * repository or not; Tab completes the one the keyboard is on.
 */
Item {
    id: picker

    property var recents: []
    property var found: []
    property var gone: ({})              // recent projects whose folder is no longer there
    readonly property bool pathMode: filter.text.startsWith("/") || filter.text.startsWith("~")
    property var pathHits: []
    function expand(t) { return t === "~" || t.startsWith("~/") ? Quickshell.env("HOME") + t.substring(1) : t; }
    readonly property var all: {
        if (picker.pathMode) return picker.pathHits;
        const seen = {}, out = [];
        for (const p of picker.recents.concat(picker.found)) if (p.length && !seen[p] && !picker.gone[p]) { seen[p] = true; out.push(p); }
        const q = filter.text.toLowerCase();
        return q.length ? out.filter(p => p.toLowerCase().includes(q)) : out;
    }
    signal chosen(string dir)
    property bool canGoBack: false       // over an open project: Esc goes back to it
    signal back()

    function refresh() { if (!scan.running) scan.running = true; if (!here.running) here.running = true; }
    function focusFilter() { filter.forceActiveFocus(); }
    function typeFilter(t) { filter.text = t; }        // for scripted checks
    // Only when it is actually on screen: with a project given, this scan of the whole home
    // folder was run on every launch for a picker nobody sees. Each time it shows, as the window stays
    // alive hidden: a repository cloned or deleted since is then right.
    onVisibleChanged: if (picker.visible) { picker.focusFilter(); picker.refresh(); }
    function home(p) { const h = Quickshell.env("HOME"); return p === h || p.startsWith(h + "/") ? "~" + p.substring(h.length) : p; }

    // the folders in the typed path's parent that start with its last part; the typed folder itself first
    Timer { id: pathLater; interval: 60; onTriggered: picker.listPath() }
    function listPath() {
        const t = picker.expand(filter.text);
        const cut = t.lastIndexOf("/");
        const parent = cut <= 0 ? "/" : t.substring(0, cut);
        pathLs.prefix = t.substring(cut + 1);
        pathLs.parentDir = parent;
        pathLs.typed = t.endsWith("/") && t.length > 1 ? t.substring(0, t.length - 1) : t;
        pathLs.running = false;
        pathLs.command = ["sh", "-c", 'test -d "$2" && echo "$2"; find "$1" -mindepth 1 -maxdepth 1 -type d -printf "%f\\n" 2>/dev/null | sort',
                          "sh", parent, pathLs.typed];
        pathLs.running = true;
    }
    Process {
        id: pathLs
        property string prefix: ""
        property string parentDir: ""
        property string typed: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l.length);
                const self = lines.length && lines[0] === pathLs.typed ? [pathLs.typed] : [];
                const pre = pathLs.prefix.toLowerCase();
                const base = pathLs.parentDir === "/" ? "" : pathLs.parentDir;
                const kids = lines.slice(self.length)
                    .filter(n => n.toLowerCase().startsWith(pre) && (pre.startsWith(".") || !n.startsWith(".")))
                    .map(n => base + "/" + n)
                    .filter(f => f !== pathLs.typed);
                picker.pathHits = self.concat(kids).slice(0, 200);
            }
        }
    }

    Process {
        id: here
        command: ["sh", "-c", 'for d in "$@"; do [ -d "$d" ] || echo "$d"; done', "sh"].concat(picker.recents)
        stdout: StdioCollector {
            onStreamFinished: {
                const g = {};
                for (const l of this.text.split("\n")) if (l.length) g[l] = true;
                picker.gone = g;
            }
        }
    }

    Process {
        id: scan
        // a .git folder, or the .git file of a worktree or a submodule; six deep reaches ~/go/src/github.com/owner/repo
        command: ["fd", "--hidden", "--no-ignore", "--max-depth", "6", "^\\.git$", Quickshell.env("HOME"),
            "--exclude", ".cache", "--exclude", ".local", "--exclude", "node_modules", "--exclude", ".gradle",
            "--exclude", ".npm", "--exclude", ".cargo", "--exclude", ".var", "--exclude", "build", "--exclude", "target",
            // tools' own checkouts and caches (skills, marketplaces): repositories nobody opens as a project; by whole
            // name, so a project in a folder like http-cache is listed
            "--exclude", "cache", "--exclude", "__pycache__", "--exclude", ".pub-cache",
            "--exclude", "vendor_imports", "--exclude", ".codex", "--exclude", ".grok", "--exclude", ".claude"]
        stdout: StdioCollector {
            onStreamFinished: picker.found = this.text.split("\n").filter(l => l.length)
                .map(l => l.replace(/\/\.git\/?$/, "")).sort()
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 48)
        spacing: 14

        StyledText {
            text: "Open a project"
            font.pixelSize: 26
            font.family: Appearance.font.family.title
            color: Tacit.inkMain
        }

        Rectangle {
            width: parent.width
            height: 42
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            MaterialSymbol {
                id: searchGlyph
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "search"; iconSize: 20
                color: Tacit.inkMeta
            }
            TextInput {
                // as StyledText: letters as designed, nothing snapped (fontconfig's full hinting widened Tacit Sans)
                font.hintingPreference: Font.PreferNoHinting
                id: filter
                anchors.left: searchGlyph.right; anchors.leftMargin: 8
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                font.family: Appearance.font.family.main
                font.variableAxes: Appearance.font.variableAxes.main
                font.pixelSize: 16
                color: Tacit.inkMain
                selectionColor: Appearance.colors.colSecondaryContainer
                focus: true
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onUpPressed: list.decrementCurrentIndex()
                Keys.onReturnPressed: if (picker.all[list.currentIndex]) picker.chosen(picker.all[list.currentIndex])
                Keys.onEnterPressed: if (picker.all[list.currentIndex]) picker.chosen(picker.all[list.currentIndex])
                Keys.onEscapePressed: if (picker.canGoBack) { filter.text = ""; picker.back(); }
                Keys.onTabPressed: event => {
                    const hit = picker.all[list.currentIndex];
                    if (picker.pathMode && hit) filter.text = picker.home(hit) + "/";
                    event.accepted = true;
                }
                // from the text itself: pathMode is a binding that has not seen this change yet
                onTextChanged: { list.currentIndex = 0; if (/^[\/~]/.test(text)) pathLater.restart(); else picker.pathHits = []; }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filter.text.length === 0
                    text: "Find a project, or type a path like ~/Documents"
                    font.pixelSize: 16
                    color: Tacit.inkFaint
                }
            }
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(contentHeight, 420)
            clip: true
            model: picker.all
            highlightMoveDuration: 0
            Praxis.FastWheel { view: list; ease: true }
            delegate: Item {
                id: row
                required property string modelData
                required property int index
                width: ListView.view.width
                height: 48
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: list.currentIndex === row.index ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.86)
                        : (ma.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent")
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
                MaterialSymbol {
                    id: g
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "folder"; fill: 1; iconSize: 22
                    color: Tacit.inkSec
                }
                Column {
                    anchors.left: g.right; anchors.leftMargin: 12
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    StyledText {
                        width: parent.width; elide: Text.ElideRight
                        text: row.modelData.split("/").pop()
                        font.pixelSize: 16
                        color: Tacit.inkMain
                    }
                    StyledText {
                        width: parent.width; elide: Text.ElideMiddle
                        text: picker.home(row.modelData)
                        font.pixelSize: 13
                        color: Tacit.inkMeta
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: picker.chosen(row.modelData)
                }
            }
        }

        StyledText {
            visible: picker.all.length === 0
            text: picker.pathMode ? "No folder by that name." : scan.running ? "Looking…" : "No git repositories here."
            font.pixelSize: 15
            color: Tacit.inkMeta
        }
    }
}
