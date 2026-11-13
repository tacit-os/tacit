import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.claude as Praxis

/**
 * Ctrl+P finds a file by name, Ctrl+Shift+F finds text in every file. A card at the
 * top of the window, drawn like the shell's other popovers; type, move with the
 * arrows, Enter opens, Esc closes.
 *
 * Search shows each file the way the editor would open it: with typing on, a changed file is
 * searched as it was before the change (git grep at `base`), a new one not at all,
 * so a result never shows code that has not been typed yet; with it off, as it is on disk.
 */
Item {
    id: finder

    property var project
    property string mode: "files"        // "files" | "search"
    property var glyphFor: name => "draft"
    property bool typing: false          // typing mode is on; off, every file opens as it is on disk and is searched so
    property var typed: ({})             // typed out in full: searched as written
    property var results: []             // files: [{ rel, score }]  search: [{ rel, line, text }]
    readonly property bool shown: visible
    signal chosen(string rel, int line)
    signal closed()

    visible: false

    function stop() { debounce.stop(); rg.running = false; gg.running = false; }
    function open(m) {
        finder.stop();
        finder.mode = m;
        query.text = "";
        finder.results = m === "files" ? finder.matchFiles("") : [];
        list.currentIndex = 0;
        finder.visible = true;
        query.forceActiveFocus();
    }
    function searchFor(q) { finder.open("search"); query.text = q; }
    function close() { finder.visible = false; finder.stop(); finder.closed(); }
    function choose(i) {
        const r = finder.results[i];
        if (!r) return;
        finder.stop();
        finder.visible = false;
        finder.chosen(r.rel, r.line || 0);
    }

    // ── files by name: a subsequence match, scored for runs and word starts ────
    function score(path, q) {
        const p = path.toLowerCase(), name = p.substring(p.lastIndexOf("/") + 1);
        let i = 0, s = 0, run = 0, last = -2;
        for (const ch of q) {
            const at = p.indexOf(ch, i);
            if (at < 0) return -1;
            run = at === last + 1 ? run + 1 : 0;
            s += 1 + run * 2;
            if (at === 0 || "/._-".includes(p.charAt(at - 1))) s += 3;
            last = at; i = at + 1;
        }
        if (name.includes(q)) s += 10 + (name.startsWith(q) ? 10 : 0);
        return s - path.length * 0.01;
    }
    function matchFiles(q) {
        const files = finder.project ? finder.project.files.concat(finder.project.extraFiles) : [];
        q = q.toLowerCase().replace(/\s+/g, "");
        if (!q.length) return files.slice(0, 200).map(f => ({ rel: f, score: 0 }));
        const out = [];
        for (const f of files) { const sc = finder.score(f, q); if (sc >= 0) out.push({ rel: f, score: sc }); }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, 200);
    }

    // ── text in files ─────────────────────────────────────────────────────────
    property var _plain: []
    property var _hidden: ({})
    property var rgInfo: ({})
    readonly property bool searching: rg.running || gg.running
    property var _before: []
    function runSearch() {
        rg.running = false; gg.running = false;
        const q = query.text;
        if (q.length < 2) { finder.results = []; return; }
        const ch = finder.project.changes, changed = Object.keys(ch).filter(f => finder.typing && ch[f] !== "D" && !finder.typed[f]);
        finder._plain = []; finder._before = [];
        // Changed files that have not been typed out are left out here and searched as they
        // were before the change below. They are filtered after the search rather than with
        // rg --glob, whose patterns do not match an absolute search path.
        finder._hidden = {};
        for (const f of changed) finder._hidden[f] = true;
        rg.command = ["rg", "--line-number", "--no-heading", "--color", "never", "--smart-case", "--fixed-strings",
            "--max-count", "20", "--max-columns", "200", "--", q, finder.project.root];
        rg.running = true;
        const modified = changed.filter(f => ch[f] === "M");
        if (modified.length) {
            gg.command = ["git", "-C", finder.project.root, "grep", "--line-number", "-I", "--fixed-strings",
                /[A-Z]/.test(q) ? "--no-ignore-case" : "-i", "-e", q, finder.project.base, "--"].concat(modified);
            gg.running = true;
        }
    }
    function merge() {
        if (finder.mode !== "search") return;   // a straggler must never land in the file list
        finder.results = finder._plain.concat(finder._before).slice(0, 300);
        if (list.currentIndex >= finder.results.length) list.currentIndex = 0;
    }
    function parse(text, prefix) {
        const out = [];
        for (const l of text.split("\n")) {
            if (!l.length) continue;
            let s = l;
            if (prefix.length && s.startsWith(prefix)) s = s.substring(prefix.length);
            const m = /^(.+?):(\d+):(.*)$/.exec(s);
            if (m) out.push({ rel: m[1].replace(/^\.\//, ""), line: parseInt(m[2]), text: m[3].trim() });
        }
        return out;
    }
    Process {
        id: rg
        workingDirectory: finder.project ? finder.project.root : ""
        stdout: StdioCollector {
            onStreamFinished: { finder._plain = finder.parse(this.text, finder.project.root + "/").filter(r => !finder._hidden[r.rel]); finder.merge(); }
        }
        stderr: StdioCollector { id: rgErr }
        onExited: (code, status) => finder.rgInfo = { code: code, err: rgErr.text.substring(0, 300) }
    }
    Process {
        id: gg
        stdout: StdioCollector {
            onStreamFinished: { finder._before = finder.parse(this.text, (finder.project ? finder.project.base : "HEAD") + ":"); finder.merge(); }
        }
    }
    Timer { id: debounce; interval: 180; onTriggered: finder.runSearch() }

    // ── drawing ───────────────────────────────────────────────────────────────
    MouseArea { anchors.fill: parent; onClicked: finder.close() }   // a click outside closes it

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 56
        width: Math.min(680, parent.width - 48)
        height: Math.min(field.height + 20 + list.contentHeight + (list.count ? 10 : 0) + (note.visible ? note.height + 8 : 0), parent.height - 112)
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Tacit.hairline
        MouseArea { anchors.fill: parent }   // clicks on the card stay on the card

        Rectangle {
            id: field
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            height: 42
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            MaterialSymbol {
                id: fieldGlyph
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                text: finder.mode === "files" ? "search" : "manage_search"
                iconSize: 20
                color: Tacit.inkMeta
            }
            TextInput {
                // as StyledText: letters as designed, nothing snapped (fontconfig's full hinting widened Tacit Sans)
                font.hintingPreference: Font.PreferNoHinting
                id: query
                anchors { left: fieldGlyph.right; leftMargin: 8; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                font.family: Appearance.font.family.main
                font.variableAxes: Appearance.font.variableAxes.main
                font.pixelSize: 16
                color: Tacit.inkMain
                selectionColor: Appearance.colors.colSecondaryContainer
                clip: true
                onTextChanged: {
                    list.currentIndex = 0;
                    if (finder.mode === "files") finder.results = finder.matchFiles(text);
                    else debounce.restart();
                }
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onUpPressed: list.decrementCurrentIndex()
                Keys.onReturnPressed: finder.choose(list.currentIndex)
                Keys.onEnterPressed: finder.choose(list.currentIndex)
                Keys.onEscapePressed: finder.close()
            }
            StyledText {
                anchors { left: fieldGlyph.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                visible: query.text.length === 0
                text: finder.mode === "files" ? "Go to file" : "Search in files"
                font.pixelSize: 16
                color: Tacit.inkMeta
            }
        }

        StyledText {
            id: note
            anchors { left: parent.left; right: parent.right; top: field.bottom; margins: 10; topMargin: 6 }
            visible: finder.results.length === 0 && query.text.length >= (finder.mode === "files" ? 1 : 2)
            text: finder.searching ? "Searching…"
                : finder.mode === "search" && finder.rgInfo.code > 1 ? (finder.rgInfo.err.split("\n")[0] || "Search failed.")
                : "No matches"
            elide: Text.ElideRight
            font.pixelSize: 14
            color: finder.mode === "search" && finder.rgInfo.code > 1 ? Appearance.colors.colError : Tacit.inkMeta
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: note.visible ? note.bottom : field.bottom; bottom: parent.bottom; margins: 10; topMargin: 6 }
            clip: true
            model: finder.results
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Praxis.FastWheel { view: list; ease: true }
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property string name: row.modelData.rel.split("/").pop()
                readonly property string dir: row.modelData.rel.includes("/") ? row.modelData.rel.substring(0, row.modelData.rel.lastIndexOf("/")) : ""
                readonly property string status: finder.project ? (finder.project.changes[row.modelData.rel] || "") : ""
                width: ListView.view.width
                height: finder.mode === "files" ? 40 : 46
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: list.currentIndex === row.index ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.86)
                        : (ma.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent")
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
                MaterialSymbol {
                    id: g
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: finder.glyphFor(row.name)
                    iconSize: 18
                    color: Tacit.inkMeta
                }
                Column {
                    anchors { left: g.right; leftMargin: 10; right: letter.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Row {
                        spacing: 8
                        width: parent.width
                        StyledText {
                            id: nameText
                            text: finder.mode === "files" ? row.name : `${row.name}:${row.modelData.line}`
                            font.pixelSize: 15
                            color: row.status === "U" ? Appearance.m3colors.m3primary
                                : row.status === "M" ? Appearance.m3colors.m3tertiary : Tacit.inkMain
                        }
                        StyledText {
                            anchors.baseline: nameText.baseline
                            text: row.dir
                            width: Math.max(0, parent.width - nameText.width - 8)
                            elide: Text.ElideMiddle
                            font.pixelSize: 13
                            color: Tacit.inkMeta
                        }
                    }
                    StyledText {
                        visible: finder.mode === "search"
                        width: parent.width
                        text: row.modelData.text || ""
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 13
                        color: Tacit.inkMeta
                    }
                }
                StyledText {
                    id: letter
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: row.status
                    font.pixelSize: 13
                    font.family: Appearance.font.family.numbers
                    color: row.status === "U" ? Appearance.m3colors.m3primary : Appearance.m3colors.m3tertiary
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: finder.choose(row.index)
                }
            }
        }
    }
}
