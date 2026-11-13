import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.tacit
import "Highlight.js" as Highlight

/**
 * Review: what the session changed, as hunks you can act on. Scope: a turn (its own edits as the
 * agent made them, so a file outside git or committed since still shows; claude-review edits),
 * this session (every file it touched), or everything uncommitted in the repository; those two
 * compared with the last commit. A file opens to its hunks (the app's
 * DiffView); a hunk can be opened in Code at its line, kept (marked reviewed, remembered per
 * session) or reverted, with an undo for the last revert. The hunks and the revert come from
 * ~/.local/bin/claude-review, which Code uses too. Each file is reviewed in its own repository
 * (a session in ~ often edits several); a file in none is listed without hunks.
 *
 * A diff line can be commented on; the comments go to the session as one message (copied
 * instead when the session runs in a terminal). Commit takes the files in view for one
 * repository, with a message Claude can draft (claude-review draft: a one-off claude -p, so
 * the conversation stays clean); then Push, and Open PR on GitHub (gh, in the browser).
 *
 * A session outside a git repository that only made new files shows them instead (MadeList).
 */
Item {
    id: panel
    // Diff colours that read at a glance on the near-black panel, as Claude Desktop's do: the calm
    // palette's success/error containers are grey-greens that sank into it.
    readonly property color addFill: "#234A2D"
    readonly property color delFill: "#4E2428"
    readonly property color addInk: "#E6F4E8"
    readonly property color delInk: "#FBE3E1"
    readonly property color addMark: "#7BD88F"
    readonly property color delMark: "#F28B82"
    property var changes: ({ files: [], add: 0, del: 0 })   // the host's list for the session
    property string cwd: ""
    property var items: []            // the conversation, for the files of the last turn
    property string sessionId: ""
    signal closeRequested()
    // the conversation's send: false when the message could not go out (then the comments stay)
    property var sendFn: null
    property string agentName: "Claude Code"
    property var tabs: []             // in the side panel: its sections, shown in place of the title
    property string backLabel: ""     // in the side panel: where Back goes (Results), shown in place of the tabs
    signal backRequested()
    signal tabPicked(string key)
    signal openRequested(string abs, int line)   // in the side panel: open in its Files tab
    signal attachRequested(string path)          // Made: @ on a file
    property bool locked: false       // a session in a terminal: comments are copied, not sent
    // A session outside a git repository that only made new files lists them (MadeList) with no
    // git review; the side panel's tab reads Made. One that edited existing files keeps the
    // review: a session in ~ edits files in the repositories under it.
    readonly property bool madeMode: panel.changes.repo === false && (panel.changes.files ?? []).every(f => f.created ?? false)

    property string scope: "turn"     // turn | session | all: the last turn first, as ChatGPT opens on it
    property var review: ({ repo: null, files: [] })
    property bool loaded: false
    property string error: ""
    property var lastRevert: null     // { file, line, undo, repo }
    property var open: ({})           // path -> expanded
    property string cursor: ""        // the file the keys act on
    function step(by) {
        const fs = panel.shownFiles.filter(f => !(f.outside ?? false));
        if (!fs.length) return;
        const at = fs.findIndex(f => f.abs === panel.cursor);
        const next = fs[Math.max(0, Math.min(fs.length - 1, at < 0 ? 0 : at + by))];
        const o = Object.assign({}, panel.open);
        if (at >= 0 && fs[at].abs !== next.abs) o[fs[at].abs] = false;
        o[next.abs] = true;
        panel.open = o;
        panel.cursor = next.abs;
        Qt.callLater(() => {
            const i = panel.rows.findIndex(r => r.kind === "file" && r.file.abs === next.abs);
            if (i >= 0) list.positionViewAtIndex(i, ListView.Beginning);
        });
    }
    function reviewCursor() {
        const f = panel.shownFiles.find(x => x.abs === panel.cursor);
        if (!f) return;
        const hs = f.hunks ?? [];
        const all = hs.length > 0 && hs.every(h => panel.isKept(h.id));
        for (const h of hs) panel.setKept(h.id, !all);
    }
    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Down) { panel.step(1); e.accepted = true; }
            else if (e.key === Qt.Key_Up) { panel.step(-1); e.accepted = true; }
            else if (e.key === Qt.Key_Space) { panel.reviewCursor(); e.accepted = true; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                const f = panel.shownFiles.find(x => x.abs === panel.cursor);
                if (f) panel.openAt(f.abs, (f.hunks ?? [])[0]?.line ?? 0, true);
                e.accepted = true;
            }
        }
    }

    // ── comments on lines, sent as one message ─────────────────────────────
    property var comments: []         // { path, line, text, quote, hunk }
    property var writing: null        // { hunk, line, quote, path } while one is being written
    // What is typed lives here, not in the box: every refresh rebuilds the hunks and the box with
    // them. Leaving the box (another line, a click away) keeps the comment rather than dropping it.
    property string draft: ""
    property bool draftFocused: false
    Timer { id: draftBlur; interval: 1; onTriggered: if (!panel.draftFocused) panel.saveComment(panel.draft) }
    property string sentNote: ""
    function writeOn(w) {
        if (panel.writing) panel.saveComment(panel.draft);
        panel.draft = "";
        panel.writing = w;
    }
    function saveComment(text) {
        const w = panel.writing;
        panel.writing = null;
        panel.draft = "";
        if (!w || !text.trim().length) return;
        panel.comments = panel.comments.concat([{ path: w.path, line: w.line, text: text.trim(), quote: w.quote, hunk: w.hunk }]);
    }
    function sendComments() {
        if (!panel.comments.length) return;
        const lines = ["Comments on your changes:", ""];
        for (const c of panel.comments) {
            lines.push(`- \`${c.path}:${c.line}\` — ${c.text}`);
            if (c.quote.trim().length) lines.push(`  > ${c.quote.trim()}`);
        }
        const msg = lines.join("\n");
        if (panel.locked) { Quickshell.clipboardText = msg; panel.sentNote = "Copied: paste them into the terminal."; }
        else if (!panel.sendFn || !panel.sendFn(msg)) { panel.sentNote = "Not sent: your comments are still here."; sentNoteFade.restart(); return; }
        else panel.sentNote = `Sent ${panel.comments.length === 1 ? "1 comment" : panel.comments.length + " comments"} to ${panel.agentName}.`;
        panel.comments = [];
        sentNoteFade.restart();
    }
    Timer { id: sentNoteFade; interval: 4000; onTriggered: panel.sentNote = "" }

    // ── commit, push, pull request ──────────────────────────────────────────
    property bool committing: false   // the commit sheet is open
    property string commitRepo: ""
    property var repoStatus: ({})
    property string committed: ""     // the last commit's hash: Push and Open PR follow it
    property bool drafting: false
    readonly property var repos: [...new Set(panel.shownFiles.filter(f => f.repo && !f.outside).map(f => f.repo))]
    readonly property var commitFiles: panel.shownFiles.filter(f => f.repo === panel.commitRepo && !f.outside).map(f => f.abs)
    function openCommit() {
        panel.committing = true;
        panel.committed = "";
        panel.commitRepo = panel.repos[0] ?? "";
        panel.readStatus();
    }
    function readStatus() {
        if (!panel.commitRepo.length) return;
        statusProc.command = [panel.tool, "status", panel.commitRepo];
        statusProc.running = false;
        statusProc.running = true;
    }
    Process {
        id: statusProc
        stdout: StdioCollector { onStreamFinished: { try { panel.repoStatus = JSON.parse(this.text); } catch (e) { panel.repoStatus = {}; } } }
    }
    onCommitRepoChanged: panel.readStatus()

    readonly property string home: Quickshell.env("HOME")
    // a file as its repository names it; outside one, from home
    function rel(f) {
        if (f.repo && f.abs.startsWith(f.repo + "/")) return `${f.repo.split("/").pop()}/${f.abs.substring(f.repo.length + 1)}`;
        return f.abs === panel.home || f.abs.startsWith(panel.home + "/") ? "~" + f.abs.substring(panel.home.length) : f.abs;
    }

    // The turn shown: the one whose View changes was pressed, else the newest that changed files
    // (a question asked after it changes nothing and used to leave this empty).
    property var picked: null
    readonly property var lastTurnEdits: {
        const out = [];
        for (let i = panel.items.length - 1; i >= 0; i--) {
            const it = panel.items[i];
            if (it.role === "user" && it.kind === "text") { if (out.length) break; continue; }
            if (it.kind === "tool" && it.error !== true && (it.files ?? []).length) out.unshift(it);
        }
        return out;
    }
    readonly property var turnEdits: panel.picked ?? panel.lastTurnEdits
    function keyOf(edits) { return (edits ?? []).map(it => it.id ?? it.ts).join(","); }
    readonly property string turnKey: panel.keyOf(panel.turnEdits)
    readonly property string cacheKey: panel.scope === "turn" ? "turn:" + panel.turnKey : panel.scope
    onTurnKeyChanged: if (panel.scope === "turn") refreshLater.restart()
    function showTurn(edits) {
        panel.picked = (edits ?? []).length ? edits : null;
        panel.open = ({});
        panel.cursor = "";
        if (panel.scope !== "turn") { panel.scope = "turn"; return; }   // onScopeChanged reads it
        if (panel.cache[panel.cacheKey] !== undefined) panel.show(panel.cache[panel.cacheKey]);
        list.positionViewAtBeginning();
        refreshLater.restart();
    }
    readonly property var scopeFiles: panel.scope === "session" ? panel.changes.files.map(f => f.path) : []

    // ── kept hunks, per session ─────────────────────────────────────────────
    FileView {
        id: keptFile
        path: `${Directories.state}/user/claude-review-kept.json`
        blockLoading: true
        printErrors: false
    }
    property var kept: {
        try { return JSON.parse(keptFile.text() || "{}"); } catch (e) { return {}; }
    }
    function isKept(id) { return (panel.kept[panel.sessionId] ?? []).includes(id); }
    function setKept(id, on) {
        const k = Object.assign({}, panel.kept);
        const list = (k[panel.sessionId] ?? []).filter(x => x !== id);
        if (on) list.push(id);
        k[panel.sessionId] = list.slice(-500);
        panel.kept = k;
        keptFile.setText(JSON.stringify(k));
    }

    // ── reading and acting (claude-review) ──────────────────────────────────
    readonly property string tool: `${Directories.tacitBin}/claude-review`
    function refresh() {
        if (!panel.visible || !panel.cwd.length || panel.madeMode) return;
        if (panel.scope === "turn" ? panel.turnEdits.length === 0 : panel.scope === "session" && panel.scopeFiles.length === 0) {
            panel.review = { repo: panel.review.repo, files: [] };
            panel.shownText = "";
            panel.loaded = true;
            return;
        }
        hunksProc.want = panel.cacheKey;
        if (panel.scope === "turn") {
            // the edits go on stdin: a turn's old and new text runs past what one argument may hold
            hunksProc.input = JSON.stringify({
                items: panel.turnEdits.map(it => ({ tool: it.tool, files: it.files.map(f => f.path), old: it.old ?? "", new: it.new ?? "", patch: it.patch ?? "" })),
                created: (panel.changes.files ?? []).filter(f => f.created).map(f => f.path) });
            hunksProc.command = [panel.tool, "edits", panel.cwd];
        } else {
            hunksProc.input = "";
            hunksProc.command = [panel.tool, "hunks", panel.cwd].concat(panel.scopeFiles);
        }
        // a run still going is stopped for this one, and what it left is no answer to the scope asked now
        hunksProc.stopped = hunksProc.running;
        hunksProc.running = false;
        hunksProc.stdinEnabled = hunksProc.input.length > 0;
        hunksProc.running = true;
    }
    // Each scope's last answer, as read: a switch shows it at once while it is read again, and an
    // answer the same as the one on screen leaves the list alone (a live session pushes its
    // changes after every edit; each rebuilt the whole list).
    property var cache: ({})
    property string shownText: ""
    function show(text) {
        if (text === panel.shownText) return;
        try { panel.review = JSON.parse(text); } catch (e) { panel.review = { repo: null, files: [] }; }
        panel.shownText = text;
    }
    Timer { id: refreshLater; interval: 250; onTriggered: panel.refresh() }
    onVisibleChanged: if (visible) refreshLater.restart()
    onScopeChanged: {
        if (panel.cache[panel.cacheKey] !== undefined) panel.show(panel.cache[panel.cacheKey]);
        refreshLater.stop();
        Qt.callLater(panel.refresh);   // after scopeFiles has followed the scope
    }
    onChangesChanged: refreshLater.restart()
    onCwdChanged: { panel.cache = ({}); panel.lastRevert = null; panel.error = ""; panel.loaded = false; refreshLater.restart(); }
    // All of this belongs to one session: comments written for it, its commit sheet, its last
    // commit. Two chats in the same project share a cwd, so the reset above cannot stand in.
    onSessionIdChanged: {
        panel.picked = null;
        panel.context = ({}); panel.ctxQueue = [];
        panel.cache = ({});
        panel.comments = [];
        panel.writing = null;
        panel.draft = "";
        panel.open = ({});
        panel.committing = false;
        panel.commitRepo = "";
        panel.repoStatus = ({});
        panel.committed = "";
        panel.drafting = false;
        panel.sentNote = "";
        panel.lastRevert = null;
        panel.error = "";
        panel.loaded = false;
        refreshLater.restart();
    }
    Process {
        id: hunksProc
        property string key: ""       // what the run going now reads
        property string want: ""      // what the next run reads: it becomes `key` when that run starts, not before
        property bool stopped: false  // the run going was stopped for a newer one
        property string input: ""
        onStarted: {
            hunksProc.key = hunksProc.want;
            hunksProc.stopped = false;
            if (hunksProc.input.length) { hunksProc.write(hunksProc.input); hunksProc.stdinEnabled = false; }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (hunksProc.stopped) return;
                panel.cache[hunksProc.key] = this.text;
                if (hunksProc.key !== panel.cacheKey) return;   // read for a scope or turn left since
                panel.show(this.text);
                panel.loaded = true;
            }
        }
    }
    Process {
        id: actProc
        property var done: null
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            if (code === 0) { if (actProc.done) actProc.done(actOut.text); panel.error = ""; }
            else panel.error = (actErr.text || "That did not work.").trim().split("\n").pop();
            actProc.done = null;
            panel.drafting = false;
            panel.refresh();
            panel.readStatus();
        }
    }
    function act(args, done) {
        if (actProc.running) {
            // say so where the pill was pressed, not nothing; the note goes when the running action ends
            panel.error = panel.drafting ? "Claude is still writing the message." : "Wait for the last action to finish.";
            return false;
        }
        panel.error = "";
        actProc.done = done;
        actProc.command = [panel.tool].concat(args);
        actProc.running = true;
        return true;
    }
    function revert(file, hunk) {
        panel.act(["revert", panel.cwd, file.abs, hunk.id], out => {
            let r = {};
            try { r = JSON.parse(out); } catch (e) {}
            panel.lastRevert = r.undo ? { file: file.path, line: hunk.line, undo: r.undo, repo: file.repo } : null;
        });
    }
    function undoRevert() {
        if (!panel.lastRevert) return;
        const u = panel.lastRevert;
        panel.act(["restore", u.repo || panel.cwd, u.undo], () => panel.lastRevert = null);
    }
    function draftMessage() {
        // the draft replaces what the box held when Draft was pressed, not what was typed while Claude wrote it
        const before = commitBox.text;
        panel.drafting = panel.act(["draft", panel.commitRepo].concat(panel.commitFiles), out => { if (commitBox.text === before) commitBox.text = out.trim(); });
    }
    function commit() {
        panel.act(["commit", panel.commitRepo, commitBox.text].concat(panel.commitFiles), out => {
            let r = {};
            try { r = JSON.parse(out); } catch (e) {}
            panel.committed = r.hash ?? "";
            commitBox.text = "";
        });
    }
    // in the side panel the file opens there (Ctrl: in Code); on its own, in Code
    function openAt(abs, line, inCode) {
        if (panel.tabs.length && !inCode) { panel.openRequested(abs, line ?? 0); return; }
        Quickshell.execDetached([`${Directories.tacitBin}/code-file`, abs, String(line ?? 0)]);
    }

    readonly property var shownFiles: panel.review.files ?? []
    readonly property int addSum: panel.shownFiles.reduce((a, f) => a + (f.add ?? 0), 0)
    readonly property int delSum: panel.shownFiles.reduce((a, f) => a + (f.del ?? 0), 0)

    Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 1
        color: Appearance.colors.colOutlineVariant
        opacity: 0.4
    }

    // a quiet action glyph (the app's message actions)
    component Act: MaterialSymbol {
        id: actGlyph
        property string tip: ""
        property bool ctrl: false         // the last click held Ctrl
        signal clicked()
        iconSize: 16
        color: actArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
        opacity: actProc.running ? 0.4 : 1
        MouseArea { id: actArea; anchors { fill: parent; margins: -5 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: m => { actGlyph.ctrl = (m.modifiers & Qt.ControlModifier) !== 0; actGlyph.clicked(); } }
        StyledToolTip { text: actGlyph.tip; extraVisibleCondition: actArea.containsMouse }
    }
    // the composer's chip
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal clicked()
        width: chipText.implicitWidth + 20
        height: 28
        radius: 14
        color: chip.on ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.88) : chipArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.92) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        StyledText { id: chipText; anchors.centerIn: parent; text: chip.label; font.pixelSize: 14; color: chip.on ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary }
        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56
        StyledText {
            id: title
            visible: panel.tabs.length === 0
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            text: "Review"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: Appearance.colors.colInkMain
        }
        // opened from Results (or the conversation): Back, named for where it goes, as the side
        // panel's other pages have it, and the title
        Row {
            visible: panel.tabs.length > 0 && panel.backLabel.length > 0
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            spacing: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: backRow.implicitWidth + 22
                height: 32
                radius: 8
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, backArea.pressed ? 0.86 : backArea.containsMouse ? 0.9 : 0.94)
                Row {
                    id: backRow
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "chevron_left"; iconSize: 20; color: Appearance.colors.colInkMain }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: panel.backLabel; font.pixelSize: 14; font.weight: Font.Medium; color: Appearance.colors.colInkMain }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.backRequested() }
            }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: panel.madeMode ? "Made" : "Changes"; font.pixelSize: 16; font.weight: Font.DemiBold; color: Appearance.colors.colInkMain }
        }
        PanelTabs {
            id: tabStrip
            visible: panel.tabs.length > 0 && panel.backLabel.length === 0
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            names: panel.tabs
            current: "review"
            onPicked: key => panel.tabPicked(key)
        }
        Row {
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 14
            Act { visible: !panel.madeMode; text: "refresh"; tip: "Look again"; onClicked: panel.refresh() }
            Act { text: "close"; iconSize: 18; tip: "Close (Ctrl+Alt+B)"; onClicked: panel.closeRequested() }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 } height: 1; color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93) }
    }

    // this turn · this session · everything uncommitted
    Row {
        anchors { right: parent.right; rightMargin: 22; verticalCenter: scopes.verticalCenter }
        visible: panel.shownFiles.length > 0 && !panel.madeMode
        spacing: 6
        StyledText { text: panel.shownFiles.length === 1 ? "1 file" : `${panel.shownFiles.length} files`; font.pixelSize: 13; color: Appearance.colors.colInkSecondary }
        StyledText { visible: panel.addSum > 0; text: `+${panel.addSum}`; font.family: Appearance.font.family.numbers; font.pixelSize: 13; color: panel.addMark }
        StyledText { visible: panel.delSum > 0; text: `−${panel.delSum}`; font.family: Appearance.font.family.numbers; font.pixelSize: 13; color: panel.delMark }
    }
    Row {
        id: scopes
        visible: !panel.madeMode
        anchors { left: parent.left; leftMargin: 24; top: header.bottom; topMargin: 12 }
        spacing: 14
        Repeater {
            model: [{ key: "turn", label: panel.picked ? "This turn" : "Last turn" }, { key: "session", label: "Session" }, { key: "all", label: "Uncommitted" }]
            StyledText {
                required property var modelData
                text: modelData.label
                font.pixelSize: 13
                font.weight: panel.scope === modelData.key ? Font.Medium : Font.Normal
                color: panel.scope === modelData.key || scopeArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkMeta
                MouseArea { id: scopeArea; anchors { fill: parent; margins: -6 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.scope = modelData.key }
            }
        }
    }

    Column {
        id: notes
        anchors { left: parent.left; right: parent.right; top: scopes.visible ? scopes.bottom : header.bottom; topMargin: 6; leftMargin: 20; rightMargin: 20 }
        spacing: 4
        Row {
            visible: panel.lastRevert !== null
            spacing: 6
            StyledText { text: `Reverted ${panel.lastRevert?.file.split("/").pop() ?? ""}:${panel.lastRevert?.line ?? ""}`; font.pixelSize: 12; color: Appearance.colors.colInkSecondary }
            StyledText { text: "·"; font.pixelSize: 13; color: Appearance.colors.colInkSecondary }
            StyledText {
                text: "Undo"
                font.pixelSize: 13
                color: undoArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
                MouseArea { id: undoArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.undoRevert() }
            }
        }
        StyledText {
            visible: panel.error.length > 0
            width: parent.width
            text: panel.error
            wrapMode: Text.Wrap
            font.pixelSize: 13
            color: Appearance.colors.colError
        }

    }

    // The list is one flat run of rows, drawn only where they are on screen: a file, then for an
    // open file each change's fold and its lines, the comments on it and the one being written. A
    // session's diffs run to thousands of lines; built all at once they made scrolling stutter.
    property var context: ({})        // "path:firstLine" -> the unchanged lines read from the file (a chunk of 300)
    property var ctxQueue: []
    function loadContext(f, from, to, key) {
        panel.ctxQueue = panel.ctxQueue.concat([{ abs: f.abs, from: from, to: Math.min(to, from + 299), key: key }]);
        if (!ctxProc.running) panel.nextContext();
    }
    function nextContext() {
        if (!panel.ctxQueue.length) return;
        const q = panel.ctxQueue[0];
        ctxProc.key = q.key;
        ctxProc.command = ["sed", "-n", `${q.from},${q.to}p`, q.abs];
        ctxProc.running = true;
    }
    Process {
        id: ctxProc
        property string key: ""
        stdout: StdioCollector { id: ctxOut }
        onExited: {
            // a read begun for a session left since (the queue was emptied under it) is not the head of the queue:
            // its lines are not kept and the new session's first request stays in line
            if (panel.ctxQueue.length && panel.ctxQueue[0].key === ctxProc.key) {
                const lines = ctxOut.text.length ? ctxOut.text.replace(/\n$/, "").split("\n") : [];
                const c = Object.assign({}, panel.context); c[ctxProc.key] = lines; panel.context = c;
                panel.ctxQueue = panel.ctxQueue.slice(1);
            }
            panel.nextContext();
        }
    }
    // Martida's roles from the palette, as the code blocks use them
    readonly property var codeColors: ({ kw: `${Appearance.m3colors.m3primary}`, type: `${Appearance.m3colors.m3tertiary}`, str: `${Appearance.m3colors.m3tertiary}`,
                                         num: `${Appearance.m3colors.m3secondary}`, com: `${Appearance.colors.colInkMeta}` })
    property bool showOutside: false  // the session's edits outside any git repository: no diff, so folded into one line
    readonly property var rows: {
        const out = [];
        const outsideFiles = panel.shownFiles.filter(f => f.outside ?? false);
        const files = panel.shownFiles.filter(f => !(f.outside ?? false)).concat(panel.showOutside ? outsideFiles : []);
        for (const f of files) {
            const outside = f.outside ?? false;
            const open = !outside && (panel.open[f.abs] ?? (panel.scope === "turn" || panel.shownFiles.length <= 3 || panel.cursor === f.abs));
            out.push({ kind: "file", file: f, open: open });
            if (!open) continue;
            if (f.binary ?? false) { out.push({ kind: "note", text: "A binary file." }); continue; }
            let above = 1;   // the first line not yet shown above the next hunk
            for (const h of f.hunks ?? []) {
                const kept = panel.isKept(h.id);
                // the lines between the last hunk and this one: a fold that opens on a click, a chunk at a time
                let from = above;
                const upTo = h.line - 1;
                while (from <= upTo) {
                    const key = `${f.abs}:${from}`, got = panel.context[key];
                    if (!got) { out.push({ kind: "fold", file: f, from: from, to: upTo, key: key, count: upTo - from + 1 }); break; }
                    for (let i = 0; i < got.length; i++) out.push({ kind: "line", t: "same", text: got[i], line: from + i, file: f, hunk: h, ctx: true });
                    from += got.length;
                    if (got.length === 0) break;
                }
                out.push({ kind: "hunk", file: f, hunk: h, kept: kept });
                const body = h.body.substring(h.body.indexOf("\n") + 1).split("\n");
                let n = h.line;
                if (kept) { for (const l of body) if (l.length && !l.startsWith("-") && !l.startsWith("\\")) n++; above = n; }
                if (kept) continue;
                for (let i = 0; i < body.length; i++) {
                    const l = body[i];
                    if (l.startsWith("\\") || (i === body.length - 1 && l === "")) continue;
                    const t = l.startsWith("+") ? "add" : l.startsWith("-") ? "del" : "same";
                    out.push({ kind: "line", t: t, text: l.startsWith("+") || l.startsWith("-") || l.startsWith(" ") ? l.substring(1) : l,
                               line: t === "del" ? n : n++, file: f, hunk: h });
                }
                above = n;
                for (const c of panel.comments.filter(c => c.hunk === h.id)) out.push({ kind: "comment", c: c });
                if (panel.writing !== null && panel.writing.hunk === h.id) out.push({ kind: "writing" });
            }
        }
        if (outsideFiles.length)
            out.push({ kind: "more", text: panel.showOutside ? "Hide the files outside git"
                : `${outsideFiles.length} more ${outsideFiles.length === 1 ? "file" : "files"} outside a git repository` });
        return out;
    }

    // outside a git repository: what the session made, in place of the review (built only then)
    Loader {
        id: madeLoader
        anchors { left: parent.left; right: parent.right; top: notes.bottom; topMargin: 6; bottom: parent.bottom }
        active: panel.madeMode
        visible: active
        sourceComponent: Component {
            MadeList {
                entries: panel.changes.made ?? []
                items: panel.items
                cwd: panel.cwd
                sessionId: panel.sessionId
                onAttachRequested: path => panel.attachRequested(path)
            }
        }
    }
    readonly property var madeList: madeLoader.item

    ListView {
        id: list
        visible: !panel.madeMode
        anchors { left: parent.left; right: parent.right; top: notes.bottom; topMargin: 6; bottom: footer.top; bottomMargin: 4 }
        clip: true
        model: panel.rows
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}
        GlideWheel { view: list; gain: 1.6; gainPerSpeed: 3; gainMax: 6 }
        delegate: Loader {
            required property var modelData
            width: ListView.view.width
            sourceComponent: modelData.kind === "file" ? fileRowC : modelData.kind === "fold" ? foldRowC : modelData.kind === "hunk" ? hunkRowC : modelData.kind === "line" ? lineRowC
                : modelData.kind === "comment" ? commentRowC : modelData.kind === "writing" ? writingRowC : modelData.kind === "more" ? moreRowC : noteRowC
        }
    }

    // a file: the notch's row (glyph, name, folder quiet beside it, counts at the end), raised while open
    Component {
        id: fileRowC
        Item {
            readonly property var file: parent.modelData.file
            readonly property bool open: parent.modelData.open
            readonly property string path: panel.rel(file)
            readonly property bool outside: file.outside ?? false
            readonly property var hunks: file.hunks ?? []
            readonly property int keptCount: hunks.filter(h => panel.isKept(h.id)).length
            readonly property bool here: panel.cursor === file.abs
            width: parent.width
            height: 38
            Rectangle {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                radius: 10
                color: parent.here || parent.open ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.92)
                    : rowArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
            }
            MaterialSymbol {
                id: glyph
                anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                text: parent.file.status === "U" || parent.file.status === "A" || parent.file.status === "?" ? "note_add" : parent.file.status === "D" ? "delete" : "edit_note"
                iconSize: 17
                color: Appearance.colors.colInkSecondary
            }
            Row {
                anchors { left: glyph.right; leftMargin: 12; right: counts.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                clip: true
                StyledText { id: nameText; text: parent.parent.path.split("/").pop(); font.pixelSize: 15; color: Appearance.colors.colInkMain }
                StyledText {
                    anchors.baseline: nameText.baseline
                    width: Math.max(0, parent.width - nameText.width - 8)
                    text: parent.parent.outside ? "not in a git repository" : parent.parent.path.includes("/") ? parent.parent.path.substring(0, parent.parent.path.lastIndexOf("/")) : ""
                    elide: Text.ElideMiddle
                    font.pixelSize: 13
                    color: Appearance.colors.colInkMeta
                }
            }
            Row {
                id: counts
                anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                spacing: 8
                StyledText { visible: parent.parent.keptCount > 0 && parent.parent.keptCount === parent.parent.hunks.length; text: "reviewed"; font.pixelSize: 13; color: Appearance.colors.colInkSecondary }
                StyledText { visible: parent.parent.file.add > 0; text: `+${parent.parent.file.add}`; font.family: Appearance.font.family.numbers; font.pixelSize: 13; color: panel.addMark }
                StyledText { visible: parent.parent.file.del > 0; text: `−${parent.parent.file.del}`; font.family: Appearance.font.family.numbers; font.pixelSize: 13; color: panel.delMark }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const f = parent.file;
                    panel.cursor = f.abs;
                    keys.forceActiveFocus();
                    if (parent.outside) { panel.openAt(f.abs, 0); return; }
                    const o = Object.assign({}, panel.open);
                    o[f.abs] = !parent.open;
                    panel.open = o;
                }
            }
            StyledToolTip { text: parent.outside ? `${parent.path} · not in a git repository` : parent.path; extraVisibleCondition: rowArea.containsMouse }
        }
    }

    // the unchanged lines between two changes: "⋯ 151 unchanged lines", opened on a click
    Component {
        id: foldRowC
        Item {
            readonly property var row: parent.modelData
            width: parent.width
            height: 28
            Rectangle {
                anchors { fill: parent; leftMargin: 16; rightMargin: 12; topMargin: 1; bottomMargin: 1 }
                radius: 6
                color: foldArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93) : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.96)
            }
            StyledText {
                anchors { left: parent.left; leftMargin: 30; verticalCenter: parent.verticalCenter }
                text: `⋯  ${parent.row.count} unchanged ${parent.row.count === 1 ? "line" : "lines"}`
                font.family: Appearance.font.family.monospace
                font.pixelSize: 12
                color: foldArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkMeta
            }
            MaterialSymbol { anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter } text: "unfold_more"; iconSize: 15; color: Appearance.colors.colInkMeta }
            MouseArea { id: foldArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.loadContext(parent.row.file, parent.row.from, parent.row.to, parent.row.key) }
        }
    }

    // a change opens with a quiet fold, "⋯ line 80"; its actions show while the pointer is on it
    Component {
        id: hunkRowC
        Item {
            readonly property var file: parent.modelData.file
            readonly property var hunk: parent.modelData.hunk
            readonly property bool kept: parent.modelData.kept
            width: parent.width
            height: 26
            HoverHandler { id: hunkHover }
            StyledText {
                anchors { left: parent.left; leftMargin: 42; verticalCenter: parent.verticalCenter }
                // line 0: a turn's edit whose text is no longer in the file (edited again since)
                text: "⋯  " + [parent.kept ? "reviewed" : "", parent.hunk.line ? `line ${parent.hunk.line}` : parent.kept ? "" : "edit",
                               parent.hunk.cut ? "first 400 lines" : ""].filter(x => x.length).join(" · ")
                font.family: Appearance.font.family.monospace
                font.pixelSize: 12
                color: Appearance.colors.colInkMeta
            }
            Row {
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                visible: hunkHover.hovered
                spacing: 14
                Act { text: "open_in_new"; tip: panel.tabs.length ? "Open at this line (Ctrl: in Graphis)" : "Open in Graphis at this line"; onClicked: panel.openAt(parent.parent.file.abs, parent.parent.hunk.line, ctrl) }
                Act {
                    text: parent.parent.kept ? "undo" : "check"
                    tip: parent.parent.kept ? "Not reviewed after all" : "Reviewed: looks right"
                    onClicked: panel.setKept(parent.parent.hunk.id, !parent.parent.kept)
                }
                Act {
                    visible: parent.parent.file.status !== "U" && !(parent.parent.file.turn ?? false) && !parent.parent.kept
                    text: "restart_alt"
                    tip: "Revert this change"
                    onClicked: panel.revert(parent.parent.file, parent.parent.hunk)
                }
            }
        }
    }

    // a line of a change: tone on the text and sign, a 2 px rail beside a changed line, the file's
    // line number; pointing at it offers a comment for Claude
    Component {
        id: lineRowC
        Item {
            readonly property var row: parent.modelData
            width: parent.width
            height: Math.max(22, lineText.implicitHeight + 2)
            HoverHandler { id: lineHover }
            Rectangle {
                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                visible: parent.row.t !== "same"
                color: parent.row.t === "add" ? panel.addFill : panel.delFill
            }
            Rectangle {
                visible: parent.row.t !== "same"
                anchors { left: parent.left; leftMargin: 16; top: parent.top; bottom: parent.bottom }
                width: 2
                color: parent.row.t === "add" ? panel.addMark : panel.delMark
            }
            StyledText {
                id: number
                anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 1 }
                width: 40
                horizontalAlignment: Text.AlignRight
                text: parent.row.t === "del" || !parent.row.hunk.line ? "" : `${parent.row.line}`
                font.family: Appearance.font.family.monospace
                font.pixelSize: 13
                color: Appearance.colors.colInkMeta
            }
            StyledText {
                id: sign
                anchors { left: number.right; leftMargin: 6; top: parent.top; topMargin: 1 }
                width: 14
                text: parent.row.t === "add" ? "+" : parent.row.t === "del" ? "−" : ""
                font.family: Appearance.font.family.monospace
                font.pixelSize: 14
                color: parent.row.t === "add" ? panel.addMark : panel.delMark
            }
            StyledText {
                id: lineText
                anchors { left: sign.right; leftMargin: 4; right: parent.right; rightMargin: 30; top: parent.top; topMargin: 1 }
                textFormat: Text.RichText
                text: Highlight.html(parent.row.text.length ? parent.row.text : " ", parent.row.file.path ?? parent.row.file.abs ?? "", panel.codeColors)
                wrapMode: Text.WrapAnywhere
                font.family: Appearance.font.family.monospace
                font.pixelSize: 14
                color: parent.row.t === "add" ? panel.addInk : parent.row.t === "del" ? panel.delInk : Appearance.colors.colInkSecondary
            }
            MaterialSymbol {
                visible: lineHover.hovered
                anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 2 }
                text: "add_comment"
                iconSize: 15
                color: commentArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
                MouseArea {
                    id: commentArea
                    anchors { fill: parent; margins: -4 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { const r = parent.parent.row; panel.writeOn({ hunk: r.hunk.id, line: r.line, quote: r.text, path: panel.rel(r.file) }); }
                }
            }
        }
    }

    Component {
        id: commentRowC
        Row {
            readonly property var c: parent.modelData.c
            x: 42
            height: 26
            spacing: 8
            MaterialSymbol { text: "chat_bubble"; iconSize: 13; color: Appearance.colors.colInkSecondary; anchors.verticalCenter: parent.verticalCenter }
            StyledText {
                width: Math.min(implicitWidth, list.width - 110)
                text: `${parent.c.line}: ${parent.c.text}`
                elide: Text.ElideRight
                font.pixelSize: 13
                color: Appearance.colors.colInkMain
                anchors.verticalCenter: parent.verticalCenter
            }
            Act { text: "close"; iconSize: 13; tip: "Remove"; onClicked: { const c = parent.c; panel.comments = panel.comments.filter(x => x !== c); } }
        }
    }

    Component {
        id: writingRowC
        Item {
            width: parent.width
            height: 42
            Rectangle {
                anchors { fill: parent; leftMargin: 38; rightMargin: 16; topMargin: 4; bottomMargin: 4 }
                radius: 8
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94)
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.3)
                TextInput {
                    // as StyledText: letters as designed, nothing snapped (fontconfig's full hinting widened Tacit Sans)
                    font.hintingPreference: Font.PreferNoHinting
                    id: commentInput
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    color: Appearance.colors.colInkMain
                    selectionColor: Appearance.colors.colSecondaryContainer
                    clip: true
                    onVisibleChanged: if (visible) { text = panel.draft; cursorPosition = text.length; forceActiveFocus(); }
                    // rebuilt by a refresh: it is born visible, so it takes the draft back here
                    Component.onCompleted: if (visible) { text = panel.draft; cursorPosition = text.length; forceActiveFocus(); }
                    onTextEdited: panel.draft = text
                    onActiveFocusChanged: {
                        panel.draftFocused = activeFocus;
                        if (!activeFocus) draftBlur.restart();
                    }
                    Keys.onReturnPressed: panel.saveComment(text)
                    Keys.onEnterPressed: panel.saveComment(text)
                    Keys.onEscapePressed: { panel.draft = ""; panel.writing = null; }
                }
                StyledText {
                    anchors { left: commentInput.left; verticalCenter: parent.verticalCenter }
                    visible: commentInput.text.length === 0
                    text: `Comment on line ${panel.writing?.line ?? ""} · Enter to add`
                    font.pixelSize: 14
                    color: Appearance.colors.colInkSecondary
                }
            }
        }
    }

    Component {
        id: moreRowC
        Item {
            width: parent.width
            height: 38
            StyledText {
                anchors { left: parent.left; leftMargin: 49; verticalCenter: parent.verticalCenter }
                text: parent.parent.modelData.text
                font.pixelSize: 13
                color: moreArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
            }
            MouseArea { id: moreArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.showOutside = !panel.showOutside }
        }
    }

    Component {
        id: noteRowC
        StyledText {
            x: 42
            height: 26
            verticalAlignment: Text.AlignVCenter
            text: parent.modelData.text ?? ""
            font.pixelSize: 13
            color: Appearance.colors.colInkSecondary
        }
    }

    StyledText {
        anchors { horizontalCenter: parent.horizontalCenter; top: notes.bottom; topMargin: 30 }
        visible: panel.loaded && panel.shownFiles.length === 0 && !panel.madeMode
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: panel.scope === "turn" ? "No turn has changed files yet."
            : panel.scope === "all" ? (panel.review.repo ? "Nothing uncommitted." : "This session's folder is not in a git repository.")
            : panel.changes.files.length === 0 && panel.scope === "session" ? "No edits in this session."
            : "Nothing left uncommitted in these files."
        font.pixelSize: 14
        color: Appearance.colors.colInkSecondary
    }

    // a quiet pill in the composer's tones
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool active: true
        signal clicked()
        width: pillText.implicitWidth + 24
        height: 28
        radius: 14
        opacity: pill.active && !actProc.running ? 1 : 0.45
        color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, pillArea.containsMouse && pill.active ? 0.84 : 0.9)
        Behavior on color { ColorAnimation { duration: 100 } }
        StyledText { id: pillText; anchors.centerIn: parent; text: pill.label; font.pixelSize: 14; color: Appearance.colors.colInkMain }
        MouseArea { id: pillArea; anchors.fill: parent; hoverEnabled: true; cursorShape: pill.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (pill.active) pill.clicked() }
    }

    Column {
        id: footer
        visible: !panel.madeMode
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 12 }
        spacing: 8
        StyledText {
            visible: panel.sentNote.length > 0
            text: panel.sentNote
            font.pixelSize: 13
            color: Appearance.colors.colInkSecondary
        }
        // comments waiting to go
        Row {
            visible: panel.comments.length > 0
            spacing: 8
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.comments.length === 1 ? "1 comment" : `${panel.comments.length} comments`
                font.pixelSize: 14
                color: Appearance.colors.colInkSecondary
            }
            Pill { label: panel.locked ? "Copy for the terminal" : `Send to ${panel.agentName}`; onClicked: panel.sendComments() }
            Pill { label: "Clear"; onClicked: panel.comments = [] }
        }
        Rectangle { width: parent.width; height: 1; color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93); visible: panel.shownFiles.length > 0 }
        // the keys that work here, and commit: a button, then the sheet
        Item {
            visible: !panel.committing && panel.shownFiles.length > 0
            width: parent.width
            height: 30
            Row {
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                spacing: 14
                KeyCap { key: "↑↓"; label: "file" }
                KeyCap { key: "Space"; label: "reviewed" }
                KeyCap { key: "↵"; label: "open in Graphis" }
            }
            Pill {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: panel.repos.length > 0
                label: "Commit…"
                onClicked: panel.openCommit()
            }
        }
        Column {
            visible: panel.committing
            width: parent.width
            spacing: 8
            Row {
                visible: panel.repos.length > 1
                spacing: 4
                Repeater {
                    model: panel.repos
                    delegate: Chip {
                        required property string modelData
                        label: modelData.split("/").pop()
                        on: panel.commitRepo === modelData
                        onClicked: panel.commitRepo = modelData
                    }
                }
            }
            StyledText {
                width: parent.width
                text: panel.committed.length
                    ? `Committed ${panel.committed}${panel.repoStatus.branch ? " on " + panel.repoStatus.branch : ""}.`
                    : `${panel.commitFiles.length === 1 ? "1 file" : panel.commitFiles.length + " files"} in ${panel.commitRepo.split("/").pop()}${panel.repoStatus.branch ? " · " + panel.repoStatus.branch : ""}`
                elide: Text.ElideRight
                font.pixelSize: 13
                color: Appearance.colors.colInkSecondary
            }
            Rectangle {
                visible: !panel.committed.length
                width: parent.width
                height: Math.max(72, commitBox.implicitHeight + 16)
                radius: 10
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95)
                border.width: 1
                border.color: commitBox.activeFocus ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.55) : ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.3)
                TextArea {
                    // as StyledText: letters as designed, nothing snapped (fontconfig's full hinting widened Tacit Sans)
                    font.hintingPreference: Font.PreferNoHinting
                    id: commitBox
                    anchors { fill: parent; margins: 8 }
                    wrapMode: TextEdit.Wrap
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    color: Appearance.colors.colInkMain
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: panel.drafting ? "Claude is writing it…" : "Commit message"
                    placeholderTextColor: Appearance.colors.colInkSecondary
                    padding: 0
                    background: null
                }
            }
            Row {
                spacing: 6
                Pill { visible: !panel.committed.length; label: panel.drafting ? "Drafting…" : "Draft"; active: !panel.drafting && panel.commitFiles.length > 0; onClicked: panel.draftMessage() }
                Pill { visible: !panel.committed.length; label: "Commit"; active: commitBox.text.trim().length > 0 && panel.commitFiles.length > 0; onClicked: panel.commit() }
                Pill {
                    visible: panel.committed.length > 0 && (panel.repoStatus.remote ?? "").length > 0
                    label: panel.repoStatus.upstream ? (panel.repoStatus.ahead > 0 ? `Push ${panel.repoStatus.ahead}` : "Pushed") : "Push"
                    active: !panel.repoStatus.upstream || panel.repoStatus.ahead > 0
                    onClicked: panel.act(["push", panel.commitRepo], () => {})
                }
                Pill {
                    visible: panel.committed.length > 0 && (panel.repoStatus.github ?? false) && (panel.repoStatus.gh ?? false)
                    label: "Open PR"
                    onClicked: panel.act(["pr", panel.commitRepo], () => {})
                }
                Pill { label: panel.committed.length ? "Done" : "Cancel"; onClicked: { panel.committing = false; panel.committed = ""; } }
            }
        }
    }
}
