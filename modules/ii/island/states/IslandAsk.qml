pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../../../claude"

/**
 * Ask: the notch's quick Claude chat (Super+Shift+Space, the palette's Claude row, a capture).
 * The conversation, the context chips, the draft and whether this continues the last chat all
 * live in services/Claude.qml; this sheet draws them, so closing it loses nothing.
 *
 * The field is the palette's header (glyph, large borderless text, hairline under it) and stays
 * put at the top; under it the chips (what Claude will be told you are looking at, each
 * removable), the line that says whether this continues the last chat, then suggestions or the
 * conversation, so the notch only ever grows at its bottom edge. The glyph is the shell's shape:
 * still while idle, morphing while the agent works.
 */
Item {
    id: ask
    signal close()

    readonly property bool talking: Claude.earlier.length > 0 || Claude.items.length > 0 || Claude.pendingQ.length > 0
    readonly property color textColor: IslandController.contentColor
    readonly property color dimColor: IslandController.subtextColor
    readonly property color lineColor: ColorUtils.transparentize(IslandController.contentColor, 0.9)
    // the notch window is 440 tall; its header takes 34
    readonly property real room: 406
    // IslandContent opens Ask 600 wide. The content keeps that width while the notch widens
    // round it, so text is laid out once instead of re-wrapping on every frame of the open.
    readonly property real fullWidth: 600

    implicitHeight: body.implicitHeight + 14
    clip: true

    function focusInput() { input.forceActiveFocus(); }
    Component.onCompleted: { input.text = Claude.draftText; input.cursorPosition = input.text.length; }
    Connections {
        target: Claude
        // a conversation just (re)built lands at its end
        function onLoaded() { talk.instant = true; settleTalk.restart(); }
        function onDraftTextChanged() { if (input.text !== Claude.draftText) input.text = Claude.draftText; }
        // the work done, the glyph goes back to its resting shape (the shape morphs there)
        function onBusyChanged() { if (!Claude.busy) glyph.shapeIndex = 0; }
    }

    // ── the conversation, as turns: your question, the steps, the answer ────
    readonly property var turns: {
        const out = [];
        for (const it of Claude.earlier.concat(Claude.items)) {
            if (it.kind === "result") continue;
            if (it.role === "user" && (it.kind === "text" || it.kind === "command")) { out.push({ q: Claude.strip(it.text), steps: [], answer: [] }); continue; }
            if (it.role === "user") continue;
            if (!out.length) out.push({ q: "", steps: [], answer: [] });
            const t = out[out.length - 1];
            if (it.kind === "tool" || it.kind === "thinking") t.steps.push(it);
            else if (it.kind === "text") t.answer.push(it.text);
        }
        if (Claude.pendingQ.length && !out.some(t => t.q === Claude.pendingQ)) out.push({ q: Claude.pendingQ, steps: [], answer: [] });
        return out.slice(-3);
    }
    // "read 2 files · ran 1 command": what a turn did, in one line
    function stepLine(steps) {
        const n = { read: 0, ran: 0, edited: 0, looked: 0, other: 0 };
        for (const s of steps) {
            if (s.kind !== "tool") continue;
            const t = s.tool;
            if (t === "Read" || t === "view_image") n.read++;
            else if (["Bash", "shell", "exec_command", "shell_command"].includes(t)) n.ran++;
            else if (["Edit", "Write", "MultiEdit", "apply_patch"].includes(t)) n.edited++;
            else if (["Grep", "Glob", "WebSearch", "WebFetch"].includes(t)) n.looked++;
            else n.other++;
        }
        const parts = [];
        if (n.read) parts.push(n.read === 1 ? "read 1 file" : `read ${n.read} files`);
        if (n.ran) parts.push(n.ran === 1 ? "ran 1 command" : `ran ${n.ran} commands`);
        if (n.edited) parts.push(n.edited === 1 ? "edited 1 file" : `edited ${n.edited} files`);
        if (n.looked) parts.push(n.looked === 1 ? "searched once" : `searched ${n.looked} times`);
        if (n.other) parts.push(n.other === 1 ? "used 1 tool" : `used ${n.other} tools`);
        return parts.join(" · ");
    }
    function lastStep(steps) {
        for (let i = steps.length - 1; i >= 0; i--)
            if (steps[i].kind === "tool") return steps[i].desc || steps[i].summary || steps[i].tool;
        return "Thinking";
    }
    // what is on screen of the live answer: whole words, with an open code fence, ** or `
    // closed for now so half-written markup never flashes
    readonly property string liveShown: {
        let s = Claude.liveText.substring(0, Claude.shown);
        if (((s.match(/^```/gm) ?? []).length) % 2) s += "\n```";
        const prose = s.split(/^```[\s\S]*?^```/m).join("");
        if (((prose.match(/\*\*/g) ?? []).length) % 2) s += "**";
        if (((prose.match(/`/g) ?? []).length) % 2) s += "`";
        return s;
    }
    // prose and fenced code, drawn as the Claude app draws them
    function blocksOf(md) {
        return StringUtils.splitMarkdownBlocks(md).map(b => b.type === "code" ? { code: true, content: b.content.replace(/\n+$/, ""), lang: b.lang ?? "" }
                                                                              : { code: false, content: b.content.trim() })
            .filter(b => b.code || b.content.length);
    }

    // ── what you probably mean, before you have asked anything ──────────────
    FileView {
        id: originsFile
        path: `${Directories.state}/user/files/origins.json`
        printErrors: false
    }
    readonly property var latest: {
        let idx = {};
        try { const d = JSON.parse(originsFile.text() || "{}"); idx = d.index ?? d; } catch (e) {}
        const p = Object.keys(idx).filter(k => idx[k]?.kind === "screenshot" || idx[k]?.kind === "download")
            .sort((a, b) => (idx[b].at ?? 0) - (idx[a].at ?? 0))[0];
        return p ? { path: p, kind: idx[p].kind, at: idx[p].at ?? 0, title: idx[p].title ?? "" } : null;
    }
    // origins.json records what happened, not what is still on disk. A deleted screenshot must
    // not be offered: the row would draw an empty thumbnail and the question would reach the
    // agent with a path that is not there.
    property string latestGone: ""
    onLatestChanged: {
        ask.latestGone = "";
        if (ask.latest) {
            latestCheck.command = ["test", "-e", ask.latest.path];
            latestCheck.running = true;
        }
    }
    Process {
        id: latestCheck
        onExited: exitCode => {
            if (exitCode !== 0)
                ask.latestGone = latestCheck.command[2];
        }
    }
    readonly property var suggestions: {
        const rows = [{ glyph: "crop_free", title: "Look at part of the screen", sub: "draw a box", act: "region" }];
        const w = ToplevelManager.activeToplevel;
        if (w) rows.push({ glyph: "select_window", title: "This window", sub: w.title ?? w.appId ?? "", act: "window" });
        if (ask.latest && ask.latest.path !== ask.latestGone) rows.push({ glyph: ask.latest.kind === "screenshot" ? "screenshot_monitor" : "download", title: ask.latest.path.split("/").pop(),
                                    sub: Voice.facts([ask.latest.title, Voice.age(ask.latest.at)]), act: "file", path: ask.latest.path, thumb: Claude.isImage(ask.latest.path) });
        rows.push({ glyph: "open_in_new", title: "Open Praxis", sub: "every session", act: "app" });
        return rows;
    }
    // A capture happens with the notch folded, so the sheet is not in the picture; the file then
    // comes back through `island askWith`, which reopens Ask with it attached.
    function pick(row) {
        if (row.act === "file") { Claude.chips = Claude.chips.concat([Claude.fileChip(row.path)]); input.forceActiveFocus(); return; }
        if (row.act === "app") { Claude.hand("show"); ask.close(); return; }
        ask.close();
        if (row.act === "region")
            // This instance by its own path: under any other config name the capture never came back
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "claude"]);
        else if (row.act === "window")
            // The wait is for the notch to fold out of the shot. Nothing focused by then - an
            // empty workspace, or the focus still on a layer surface - gives hyprctl no geometry
            // at all, and this used to hand grim "null,null nullxnull" and end there: the notch
            // was already folded, so the failure had nowhere to appear. It says so now.
            Quickshell.execDetached(["bash", "-c", `sleep 0.55; g=$(hyprctl activewindow -j | jq -r 'if (.at | type) == "array" then "\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])" else "" end'); if [ -z "$g" ]; then notify-send 'Ask' 'No window was focused, so there was nothing to look at.' -a "Tacit"; exit 1; fi; d="$HOME/.cache/agent-host/region"; mkdir -p "$d"; f="$d/window-$(date '+%Y-%m-%d_%H.%M.%S').png"; grim -g "$g" "$f" || { notify-send 'Ask' 'That window could not be captured.' -a "Tacit"; exit 1; }; qs -p '${StringUtils.shellSingleQuoteEscape(Quickshell.shellPath(""))}' ipc call island askWith "$f"`]);
    }

    // a quiet text button in the header's tone (the continuity line, Start, Stop)
    component Link: StyledText {
        id: link
        signal clicked()
        font.pixelSize: 13
        color: linkArea.containsMouse ? ask.textColor : ask.dimColor
        Behavior on color { ColorAnimation { duration: 100 } }
        MouseArea { id: linkArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: link.clicked() }
    }

    Rectangle {
        id: talkFade
        visible: false
        layer.enabled: true
        width: talk.width
        height: talk.height
        readonly property real edge: Math.min(0.4, 20 / Math.max(1, talk.height))
        gradient: Gradient {
            GradientStop { position: 0; color: talk.contentY > 1 ? "transparent" : "white" }
            GradientStop { position: talkFade.edge; color: "white" }
            GradientStop { position: 1 - talkFade.edge; color: "white" }
            GradientStop { position: 1; color: talk.contentY < talk.contentHeight - talk.height - 1 ? "transparent" : "white" }
        }
    }

    Column {
        id: body
        x: Math.round((ask.width - width) / 2)
        width: ask.fullWidth

        // ── the field: the palette's header, in the notch ───────────────────
        Column {
            id: header
            x: 20
            width: parent.width - 40
            topPadding: 6
            bottomPadding: 12
            spacing: 8
            RowLayout {
                width: parent.width
                spacing: 12
                MaterialLoadingIndicator {
                    id: glyph
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: -1
                    implicitSize: 26
                    colBg: "transparent"
                    loading: Claude.busy
                    colShape: Claude.busy || input.text.length > 0 ? ask.textColor : ask.dimColor
                    Behavior on colShape { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                }
                TextArea {
                    id: input
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    wrapMode: TextEdit.Wrap
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: ask.textColor
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Claude.busy ? "Add to the queue" : Claude.continuing ? "Ask a follow-up" : "Ask anything"
                    placeholderTextColor: ask.dimColor
                    padding: 0
                    topPadding: 1
                    background: null
                    onTextChanged: if (Claude.draftText !== text) Claude.draftText = text
                    Keys.onPressed: e => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { Claude.send(input.text); e.accepted = true; }
                        else if (e.key === Qt.Key_Escape) { ask.close(); e.accepted = true; }
                    }
                }
                // working: stop it; otherwise take the conversation to the app
                Rectangle {
                    visible: Claude.sid.length > 0
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: -2
                    implicitWidth: actRow.implicitWidth + 16
                    implicitHeight: 26
                    radius: 13
                    color: actArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Row {
                        id: actRow
                        anchors.centerIn: parent
                        spacing: 5
                        StyledText { text: Claude.busy ? "Stop" : "Open in app"; font.pixelSize: 13; color: actArea.containsMouse ? ask.textColor : ask.dimColor; anchors.verticalCenter: parent.verticalCenter }
                        MaterialSymbol { text: Claude.busy ? "stop_circle" : "arrow_outward"; iconSize: 14; color: actArea.containsMouse ? ask.textColor : ask.dimColor; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (Claude.busy) Claude.stop(); else { Claude.openInApp(); ask.close(); } }
                    }
                }
            }
            // what goes with the question: what you are looking at, and what you attached
            Flow {
                visible: Claude.chips.length > 0
                x: 38
                width: parent.width - 38
                spacing: 6
                Repeater {
                    model: Claude.chips
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool thumb: chip.modelData.kind === "image"
                        width: chip.thumb ? 64 : Math.min(chipRow.implicitWidth + 20, 260)
                        height: chip.thumb ? 48 : 28
                        radius: chip.thumb ? 10 : 14
                        clip: true
                        color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, chipArea.containsMouse ? 0.88 : 0.92)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        scale: 0.85
                        opacity: 0
                        Component.onCompleted: { chip.scale = 1; chip.opacity = 1; }
                        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        HoverHandler { id: chipArea }
                        Image { id: chipThumb; visible: chip.thumb && chipThumb.status === Image.Ready; anchors.fill: parent; source: chip.thumb ? FileUtils.fileUrl(chip.modelData.path) : ""; fillMode: Image.PreserveAspectCrop; sourceSize.height: 96; asynchronous: true }
                        // still loading, or gone from disk: its glyph rather than a blank tile
                        MaterialSymbol { visible: chip.thumb && chipThumb.status !== Image.Ready; anchors.centerIn: parent; text: "image"; iconSize: 20; color: ask.dimColor }
                        Row {
                            id: chipRow
                            visible: !chip.thumb
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 5
                            MaterialSymbol { text: chip.modelData.glyph; iconSize: 15; color: ask.dimColor; anchors.verticalCenter: parent.verticalCenter }
                            StyledText { text: chip.modelData.label; width: Math.min(implicitWidth, 190); elide: Text.ElideRight; font.pixelSize: 14; color: ask.dimColor; anchors.verticalCenter: parent.verticalCenter }
                            MaterialSymbol { text: "close"; iconSize: 13; color: ask.dimColor; opacity: chipArea.hovered ? 1 : 0.6; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Rectangle {
                            visible: chip.thumb
                            anchors { right: parent.right; top: parent.top; margins: 3 }
                            width: 16; height: 16; radius: 8
                            color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                            MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 12; color: Tacit.inkMain }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Claude.removeChip(chip.index) }
                        StyledToolTip { text: "Leave this out"; extraVisibleCondition: chipArea.hovered }
                    }
                }
            }
            // continue the last chat, or a new one (§4): always said, one click to flip
            Row {
                x: 38
                spacing: 6
                StyledText {
                    text: Claude.note.length ? Claude.note
                        : Claude.continuing ? `Continuing “${Claude.current?.title ?? ""}” · ${Claude.ago(Claude.current?.lastAt)}`
                                              + (Claude.current && Claude.current.cwd !== Claude.cwd ? ` · in ${Claude.folderName(Claude.current.cwd)}` : "")
                        : `New chat in ${Claude.folderName(Claude.cwd)}`
                    font.pixelSize: 13
                    color: ask.dimColor
                }
                StyledText { visible: flip.visible; text: "·"; font.pixelSize: 13; color: ask.dimColor }
                Link {
                    id: flip
                    visible: Claude.continuing || !!(Claude.current && Claude.current.id)
                    text: Claude.continuing ? "New chat" : `Continue “${Claude.current?.title ?? ""}”`
                    onClicked: { Claude.continuing ? Claude.newChat() : Claude.continueChat(); input.forceActiveFocus(); }
                }
            }
        }

        // the palette's hairline, edge to edge
        Rectangle { width: parent.width; height: 1; color: ask.lineColor }

        // agent-host is not there: say so, and the question waits in the draft
        Row {
            visible: !Claude.connected
            x: 58
            topPadding: 10
            spacing: 8
            StyledText { text: "Claude isn't running."; font.pixelSize: 14; color: ask.dimColor }
            Link { text: "Start"; font.pixelSize: 14; onClicked: Claude.startHost() }
        }

        // ── before anything is asked: what you most likely mean ─────────────
        Column {
            visible: !ask.talking
            x: 8
            width: parent.width - 16
            topPadding: 6
            spacing: 2
            Repeater {
                model: ask.talking ? [] : ask.suggestions
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 40
                    radius: 10
                    color: rowArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93) : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                    opacity: 0
                    transform: Translate { id: rowRise; y: 6 }
                    Component.onCompleted: rowIn.start()
                    SequentialAnimation {
                        id: rowIn
                        PauseAnimation { duration: 60 + row.index * 35 }
                        ParallelAnimation {
                            NumberAnimation { target: row; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                            NumberAnimation { target: rowRise; property: "y"; to: 0; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve }
                        }
                    }
                    // glyphs sit under the field's shape
                    // the thumbnail takes the glyph's place only once it is really there
                    MaterialSymbol { id: rowGlyph; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } text: row.modelData.glyph; iconSize: 18; color: ask.dimColor; opacity: rowThumb.status === Image.Ready ? 0 : 1 }
                    Image {
                        id: rowThumb
                        visible: (row.modelData.thumb ?? false) && rowThumb.status === Image.Ready
                        anchors.centerIn: rowGlyph
                        width: 26; height: 26
                        source: row.modelData.thumb ? FileUtils.fileUrl(row.modelData.path) : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.height: 52
                        asynchronous: true
                    }
                    StyledText { id: rowTitle; anchors { left: parent.left; leftMargin: 50; verticalCenter: parent.verticalCenter } text: row.modelData.title; font.pixelSize: 15; color: ask.textColor }
                    StyledText {
                        anchors { left: rowTitle.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: row.modelData.sub ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        color: ask.dimColor
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ask.pick(row.modelData) }
                }
            }
        }

        // ── the conversation: the last few turns, newest at the bottom ──────
        Item { visible: ask.talking; width: 1; height: 14 }
        Flickable {
            id: talk
            visible: ask.talking
            x: 20
            width: parent.width - 40
            // everything else first; the conversation takes what is left of the notch
            height: visible ? Math.min(turnColumn.implicitHeight, ask.room - header.height - 1 - 14 - queued.height - cards.height - (errorLine.visible ? errorLine.height : 0) - 14) : 0
            contentHeight: turnColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Follows the end as the answer grows, on a spring so the lines glide up rather than
            // step; scrolled up by hand, it stays where you left it.
            property bool pinned: true
            onMovementEnded: talk.pinned = talk.contentY >= talk.contentHeight - talk.height - 4
            onContentHeightChanged: if (talk.pinned) talk.contentY = Math.max(0, talk.contentHeight - talk.height)
            onHeightChanged: if (talk.pinned) talk.contentY = Math.max(0, talk.contentHeight - talk.height)
            // a conversation just loaded lands at its end; only growth after that glides
            property bool instant: true
            Timer { id: settleTalk; interval: 400; running: true; onTriggered: talk.instant = false }
            Behavior on contentY { enabled: !talk.moving && !talk.instant; SpringAnimation { spring: 0.9; damping: 0.2; epsilon: 0.25 } }
            // an edge with more text past it fades out instead of cutting a line in half
            layer.enabled: talk.contentHeight > talk.height + 1
            layer.effect: OpacityMask { maskSource: talkFade }
            Column {
                id: turnColumn
                width: talk.width
                spacing: 16
                Repeater {
                    model: ask.turns
                    delegate: Column {
                        id: turn
                        required property var modelData
                        required property int index
                        readonly property bool current: turn.index === ask.turns.length - 1
                        width: turnColumn.width
                        spacing: 6
                        opacity: 0
                        transform: Translate { id: turnRise; y: 8 }
                        Component.onCompleted: turnIn.start()
                        ParallelAnimation {
                            id: turnIn
                            NumberAnimation { target: turn; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                            NumberAnimation { target: turnRise; property: "y"; to: 0; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve }
                        }
                        // 4px in: Qt's rich text keeps a 4px document margin, the answers start there
                        StyledText {
                            visible: turn.modelData.q.length > 0
                            leftPadding: 4
                            width: parent.width
                            text: turn.modelData.q
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: ask.textColor
                        }
                        // the work, in one line: what it is doing now, or what it did
                        Row {
                            visible: turn.modelData.steps.length > 0 || (turn.current && Claude.busy && !Claude.liveText.length)
                            x: 4
                            spacing: 7
                            height: 22
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "stacks"
                                iconSize: 15
                                color: ask.dimColor
                            }
                            ShineText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, turn.width - 30)
                                text: turn.current && Claude.busy && !Claude.liveText.length ? ask.lastStep(turn.modelData.steps) : ask.stepLine(turn.modelData.steps) || "thought it over"
                                pixelSize: 14
                                color: ask.dimColor
                                active: turn.current && Claude.busy
                            }
                        }
                        Repeater {
                            id: answers
                            model: turn.modelData.answer
                            delegate: Column {
                                id: answer
                                required property string modelData
                                required property int index
                                // the newest answer is drawn by the live text until it is all out
                                visible: !(turn.current && Claude.liveDone && Claude.liveText.length && answer.index === answers.count - 1)
                                width: turn.width
                                spacing: 8
                                Repeater {
                                    model: ask.blocksOf(answer.modelData)
                                    delegate: Loader {
                                        required property var modelData
                                        width: answer.width
                                        sourceComponent: modelData.code ? codeC : textC
                                        property var block: modelData
                                    }
                                }
                            }
                        }
                        Column {
                            visible: turn.current && Claude.liveText.length > 0
                            width: turn.width
                            spacing: 8
                            Repeater {
                                model: turn.current ? ask.blocksOf(ask.liveShown) : []
                                delegate: Loader {
                                    required property var modelData
                                    width: turn.width
                                    sourceComponent: modelData.code ? codeC : textC
                                    property var block: modelData
                                }
                            }
                        }
                    }
                }
            }
        }
        Component { id: textC; ClaudeText { markdown: parent ? parent.block.content : ""; font.pixelSize: 16 } }
        Component { id: codeC; CodeBlock { code: parent ? parent.block.content : ""; lang: parent ? parent.block.lang : "" } }

        // typed while it works: sent in order when it is done
        Column {
            id: queued
            x: 24
            width: parent.width - 48
            topPadding: Claude.queue.length ? 8 : 0
            spacing: 4
            Repeater {
                model: Claude.queue
                delegate: Row {
                    required property var modelData
                    spacing: 7
                    MaterialSymbol { text: "schedule"; iconSize: 14; color: ask.dimColor; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: modelData.question; width: Math.min(implicitWidth, queued.width - 30); elide: Text.ElideRight; font.pixelSize: 14; color: ask.dimColor; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }

        // the agent asks something, or asks to run something: the Claude app's own cards
        Column {
            id: cards
            x: 20
            width: parent.width - 40
            topPadding: Claude.pending.length ? 12 : 0
            spacing: 8
            Repeater {
                model: Claude.pending
                delegate: Loader {
                    id: card
                    required property var modelData
                    width: cards.width
                    source: Qt.resolvedUrl(card.modelData.tool === "AskUserQuestion" ? "../../../claude/QuestionCard.qml" : "../../../claude/PermissionCard.qml")
                    onLoaded: {
                        card.item.pending = card.modelData;
                        const id = Claude.sid;
                        if (card.modelData.tool === "AskUserQuestion") {
                            card.item.answered.connect(input => Claude.request({ op: "answer", id: id, request: card.modelData.request, allow: true, input: input }));
                            card.item.skipped.connect(() => Claude.request({ op: "answer", id: id, request: card.modelData.request, allow: false, message: "The user skipped the question." }));
                        } else {
                            card.item.answered.connect((allow, permissions) => {
                                const req = { op: "answer", id: id, request: card.modelData.request, allow: allow };
                                if (permissions) req.permissions = permissions;
                                Claude.request(req);
                            });
                        }
                    }
                }
            }
        }

        StyledText {
            id: errorLine
            visible: Claude.error.length > 0
            x: 24
            width: parent.width - 48
            topPadding: 10
            text: Claude.error
            wrapMode: Text.Wrap
            font.pixelSize: 13
            color: Appearance.colors.colError
        }
    }
}
