import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "ActivityWords.js" as Words

/**
 * One agent: its name and standing, what it was asked (one line, open on click), Stop and Copy
 * report; then what matters first - what stopped it, or its report (a running one's step is the
 * shimmering line); who started it and whom it started; then its activity, its whole run as ticks
 * over it: under All, the agent's own words with the steps between them folded as the conversation
 * folds them ("Ran 4 commands", "Edited Main.qml"), each opening to its commands, diffs and pictures;
 * under Edits, Pictures and Commands, those steps one by one; under Files, the files it changed. A running stream follows its newest
 * step until you scroll up; then a pill counts what arrived. A finished one opens on its last sixty
 * groups, the earlier ones a click away.
 */
PanelPage {
    id: ap
    bodyHeight: col.implicitHeight
    readonly property var p: ap.pane
    readonly property var a: ap.p.findAgent(ap.p.info, ap.entry.id)
    readonly property var data: ap.p.stepsBy[ap.entry.id] ?? null
    readonly property var detail: ap.data?.detail ?? null
    readonly property bool running: ap.a?.state === "running"
    function bump() { ap.entryChanged(); }
    function restore() {
        if (ap.entry.f.follow) { Qt.callLater(ap.toEnd); return; }
        ap.wantY = ap.entry.y ?? 0;
        ap.settle();
    }

    // ── the steps ──────────────────────────────────────────────────────────
    function kindOf(it) {
        if ((it.images ?? []).length) return "picture";
        if (["Edit", "MultiEdit", "Write", "apply_patch", "NotebookEdit"].includes(it.tool) || (it.old ?? "").length || (it.patch ?? "").length) return "edit";
        if (["Bash", "BashOutput", "exec", "shell", "KillShell", "TaskOutput", "TaskStop"].includes(it.tool)) return "command";
        return "read";
    }
    function toolWord(t) {
        return ({ Bash: "Ran", BashOutput: "Output", exec: "Ran", shell: "Ran", KillShell: "Stopped", Grep: "Search", Glob: "Find", WebFetch: "Fetch",
                  WebSearch: "Web", grep: "Search", find: "Find", ls: "Find", list: "Find", websearch: "Web", codesearch: "Web", ToolSearch: "Tools", TodoWrite: "Todo", Task: "Agent", Agent: "Agent", Skill: "Skill", Monitor: "Watch", TaskOutput: "Output", TaskStop: "Stopped" })[t] ?? Words.label(t);
    }
    function textOf(it) {
        if ((it.images ?? []).length) return String(it.summary || it.desc || "a picture").replace(/^~\//, "");
        return String(it.desc || it.summary || it.tool || "").replace(/\s+/g, " ");
    }
    readonly property var tools: (ap.data?.items ?? []).filter(it => it.kind === "tool")
    readonly property var kinds: ap.tools.map(ap.kindOf)
    readonly property var labels: ap.tools.map(it => `${it.tool ?? ""} ${ap.textOf(it)}`)
    readonly property var counts: {
        const c = { edit: 0, picture: 0, command: 0, read: 0 };
        for (const k of ap.kinds) c[k]++;
        return c;
    }
    // the files its edits touched, net per file
    readonly property var fileList: {
        const m = {};
        ap.tools.forEach((it, i) => {
            if (ap.kinds[i] !== "edit") return;
            for (const f of it.files ?? []) {
                if (!m[f.path]) m[f.path] = { path: f.path, add: 0, del: 0, first: i };
                const e = m[f.path];
                e.add += f.add ?? 0; e.del += f.del ?? 0;
            }
        });
        return Object.values(m).sort((x, y) => (y.add + y.del) - (x.add + x.del));
    }
    readonly property string filter: ap.entry.f.filter ?? "all"
    // the stream: one entry per step, or per run of three or more reads or commands in a row
    readonly property var groups: {
        const out = [];
        ap.tools.forEach((it, i) => {
            const k = ap.kinds[i];
            if (ap.filter !== "all" && k !== ap.filter) return;
            const g = out[out.length - 1];
            if (g && ap.filter === "all" && g.k === k && (k === "read" || k === "command") && g.last === i - 1) { g.items.push(i); g.last = i; }
            else out.push({ k: k, items: [i], last: i });
        });
        return out;
    }
    readonly property int shownFrom: ap.running || ap.entry.f.all || ap.filter !== "all" ? 0 : Math.max(0, ap.groups.length - 60)
    readonly property var shownGroups: ap.groups.slice(ap.shownFrom)

    // its story, as the conversation draws a turn: what it said, and the steps between two pieces of
    // what it said as one activity group (lo..hi: the steps in it, by number). Its last words are its
    // report, shown above, and are not said twice.
    readonly property var story: {
        const items = ap.data?.items ?? [];
        const report = String(ap.detail?.report ?? "").trim();
        const out = [];
        let run = [], step = 0, first = -1;
        const flush = () => { if (run.length) out.push({ type: "activity", tools: run, lo: first < 0 ? step : first, hi: step - 1 }); run = []; first = -1; };
        for (const it of items) {
            if (it.kind === "tool" || it.kind === "thinking") {
                if (it.kind === "tool") { if (first < 0) first = step; step++; }
                run.push(it);
                continue;
            }
            if (it.role !== "assistant" || it.kind !== "text") continue;   // what it was asked, relayed messages
            if (!ap.running && String(it.text).trim() === report) continue;
            flush();
            for (const b of StringUtils.splitMarkdownBlocks(it.text)) {
                if (b.type === "code") out.push({ type: "code", content: b.content, lang: b.lang ?? "", lo: step, hi: step - 1 });
                else if (b.content.trim().length) out.push({ type: "text", content: b.content.trim(), lo: step, hi: step - 1 });
            }
        }
        flush();
        return out;
    }
    readonly property int storyFrom: ap.running || ap.entry.f.all ? 0 : Math.max(0, ap.story.length - 60)
    readonly property var shownStory: ap.story.slice(ap.storyFrom)
    // which lines and steps of the story are open, kept with the page on the trail
    readonly property var openIds: ap.entry.f.open ?? ({})
    function toggleOpen(key) {
        if (!key.length) return;
        const m = Object.assign({}, ap.openIds);
        if (m[key]) delete m[key]; else m[key] = true;
        ap.entry.f.open = m;
        ap.bump();
    }
    // the key ActivityGroup gives the line holding a step, and the step's own
    function lineKeyOf(block, i) {
        let n = block.lo, line = null, prev = "";
        for (const it of block.tools) {
            // a thought is a line of its own, and ends the run before it (as ActivityGroup.lines)
            if (it.kind === "thinking") { prev = "think"; continue; }
            const k = Words.kind(it);
            if (k !== prev) { line = it; prev = k; }
            if (n === i) return [(line.id ?? "").length ? `line:${line.id}` : "", it.id ?? ""];
            n++;
        }
        return ["", ""];
    }

    // ── following a running stream ─────────────────────────────────────────
    property bool autoScroll: false
    property int seen: ap.tools.length
    property int unseen: 0
    function begin() {
        if (ap.entry.f.jump !== undefined) { ap.entry.f.follow = false; jumpLater.i = ap.entry.f.jump; delete ap.entry.f.jump; jumpLater.start(); }
        if (ap.entry.f.follow === undefined) ap.entry.f.follow = ap.running;
        // followed while it ran and finished since: it opens as a finished one does, at the top on its report (the kept
        // place was the old end of its activity)
        else if (ap.entry.f.follow && ap.a && !ap.running) { ap.entry.f.follow = false; ap.entry.y = 0; }
        ap.seen = ap.tools.length;
        ap.unseen = 0;
    }
    // a step asked for from elsewhere (a file's edit): shown once the stream is laid out
    Timer { id: jumpLater; property int i: 0; interval: 150; onTriggered: ap.jumpTo(i) }
    Timer { id: hitEnd; interval: 1600; onTriggered: { delete ap.entry.f.hit; ap.bump(); } }
    onToolsChanged: {
        const n = ap.tools.length;
        if (n > ap.seen) {
            if (ap.entry.f.follow) Qt.callLater(ap.toEnd);
            else ap.unseen += n - ap.seen;
            const fr = {};
            for (let i = ap.seen; i < n; i++) fr[i] = true;
            ap.freshSteps = fr;
            freshClear.restart();
        }
        ap.seen = n;
    }
    property var freshSteps: ({})
    Timer { id: freshClear; interval: 1200; onTriggered: ap.freshSteps = ({}) }
    function toEnd() {
        ap.autoScroll = true;
        ap.flick.contentY = Math.max(0, ap.flick.contentHeight - ap.flick.height);
        ap.autoScroll = false;
        ap.unseen = 0;
    }
    Connections {
        target: ap.flick
        function onContentYChanged() {
            viewTimer.restart();
            if (ap.autoScroll || !ap.running) return;
            const atEnd = ap.flick.contentY + ap.flick.height >= ap.flick.contentHeight - 30;
            // only you stop the following: the page growing under a followed stream does not
            if (ap.userMoving) {
                if (atEnd && !ap.entry.f.follow) { ap.entry.f.follow = true; ap.unseen = 0; }
                else if (!atEnd && ap.entry.f.follow) ap.entry.f.follow = false;
            }
        }
        function onContentHeightChanged() { if (ap.entry.f.follow && ap.running) Qt.callLater(ap.toEnd); }
    }
    // the steps in view, for the band over the ticks
    property int viewLo: -1
    property int viewHi: -1
    Timer { id: viewTimer; interval: 80; onTriggered: ap.updateView() }
    function updateView() {
        let lo = -1, hi = -1;
        const top = ap.flick.contentY, bottom = top + ap.flick.height;
        if (ap.filter === "all") {
            for (let i = 0; i < storyRep.count; i++) {
                const it = storyRep.itemAt(i), b = ap.shownStory[i];
                if (!it || !b || b.hi < b.lo) continue;
                const y = it.mapToItem(ap.flick.contentItem, 0, 0).y;
                if (y + it.height < top || y > bottom) continue;
                if (lo < 0) lo = b.lo;
                hi = b.hi;
            }
            ap.viewLo = lo; ap.viewHi = hi;
            return;
        }
        for (let i = 0; i < stream.count; i++) {
            const it = stream.itemAt(i);
            if (!it) continue;
            const y = it.mapToItem(ap.flick.contentItem, 0, 0).y;
            if (y + it.height < top || y > bottom) continue;
            const g = ap.shownGroups[i];
            if (!g) continue;
            if (lo < 0) lo = g.items[0];
            hi = g.items[g.items.length - 1];
        }
        ap.viewLo = lo; ap.viewHi = hi;
    }
    // a tick pressed: the stream opens to that step and brings it to the middle
    function jumpTo(i) {
        ap.entry.f.follow = false;
        ap.entry.f.filter = "all";
        ap.entry.f.all = true;
        // in the story: the line holding the step opens, and the step in it
        const b = ap.story.find(x => x.type === "activity" && x.lo <= i && i <= x.hi);
        if (b) {
            const [line, own] = ap.lineKeyOf(b, i);
            const m = Object.assign({}, ap.openIds);
            if (line.length) m[line] = true;
            if (own.length) m[own] = true;
            ap.entry.f.open = m;
            ap.bump();
            Qt.callLater(() => {
                const k = ap.shownStory.indexOf(b);
                const it = k >= 0 ? storyRep.itemAt(k) : null;
                if (!it) return;
                const y = it.mapToItem(ap.flick.contentItem, 0, 0).y;
                ap.flick.contentY = Math.max(0, Math.min(ap.flick.contentHeight - ap.flick.height, y - ap.flick.height / 4));
            });
            return;
        }
        const g = ap.groups.find(x => x.items.includes(i));
        if (g && g.items.length >= 3) ap.entry.f[`g${g.items[0]}`] = true;
        ap.entry.f.hit = i;
        ap.bump();
        hitEnd.restart();
        Qt.callLater(() => {
            for (let k = 0; k < stream.count; k++) {
                const it = stream.itemAt(k);
                const gg = ap.shownGroups[k];
                if (!it || !gg || !gg.items.includes(i)) continue;
                const y = it.mapToItem(ap.flick.contentItem, 0, 0).y;
                ap.flick.contentY = Math.max(0, Math.min(ap.flick.contentHeight - ap.flick.height, y - ap.flick.height / 3));
                return;
            }
        });
    }

    // a report paragraph by paragraph and code apart, as the conversation draws a reply
    function textBlocks(r) {
        const out = [];
        for (const b of StringUtils.splitMarkdownBlocks(r)) {
            if (b.type === "code") out.push({ code: true, content: b.content, lang: b.lang ?? "" });
            else for (const q of b.content.split(/\n{2,}/)) if (q.trim().length) out.push({ code: false, content: q.trim() });
        }
        return out;
    }
    readonly property var reportBlocks: {
        const r = ap.detail?.report ?? "";
        if (ap.detail?.kind !== "json") return ap.textBlocks(r);
        let v;
        try { v = JSON.parse(r); } catch (e) { return [{ code: true, content: r, lang: "json" }]; }
        if (v === null || typeof v !== "object" || Array.isArray(v)) return [{ code: true, content: r, lang: "json" }];
        // a structured report reads as one: its summary first, a list of words as a list, home as ~,
        // nothing for an empty field or a status the header already says
        const home = Quickshell.env("HOME") ?? "";
        // only where a path starts: "/backup/home/a/notes.txt" read as "/backup~/notes.txt"
        const atHome = new RegExp("(^|[^\\w./~-])" + home.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "/", "g");
        const said = x => home.length ? String(x).replace(atHome, "$1~/") : String(x);
        const keys = Object.keys(v).sort((x, y) => (y.toLowerCase() === "summary") - (x.toLowerCase() === "summary"));
        const out = [];
        for (const k of keys) {
            const x = v[k];
            if (x === null || x === "" || (Array.isArray(x) && !x.length) || (typeof x === "object" && !Object.keys(x).length)) continue;
            if (k.toLowerCase() === "status" && String(x).toLowerCase() === String(ap.a?.state ?? "")) continue;
            out.push({ label: String(k).replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2").replace(/^./, c => c.toUpperCase()) });
            if (Array.isArray(x) && x.every(y => typeof y !== "object" || y === null)) out.push({ code: false, content: x.map(y => `- ${said(y)}`).join("\n") });
            else if (Array.isArray(x) && x.every(y => y && typeof y === "object" && !Array.isArray(y))) out.push(...x.map(y => ap.itemOf(y, said)));
            else if (typeof x === "object") out.push({ code: true, content: said(JSON.stringify(x, null, 2)), lang: "json" });
            else out.push(...ap.textBlocks(said(x)));
        }
        return out;
    }
    // one entry of a structured list (a finding, an issue, a fix) as words: what it is, what the agent
    // said of it, the fix it proposed, how bad and where; the fields as agent-host's results reads them
    function itemOf(o, said) {
        const pick = keys => { for (const k of keys) { const t = o[k]; if (typeof t === "string" && t.trim().length) return t.trim(); } return ""; };
        // a paragraph-long name gives its first sentence as the title and the rest to what was said
        const named = pick(["title", "problem", "claim", "what", "issue", "summary", "symptom", "finding", "name", "description", "what_changed"])
                   || String(o.id ?? "");
        const cut = named.search(/[.;:] /);
        // one long sentence: cut at a word before 110 characters, what follows goes on in the detail
        const at = named.lastIndexOf(" ", 110);
        const [title, more] = cut >= 12 && cut < 160 ? [named.substring(0, cut), named.substring(cut + 1).trim()]
                            : named.length > 160 && at > 40 ? [named.substring(0, at) + " …", "… " + named.substring(at + 1)] : [named, ""];
        const said2 = pick(["problem", "claim", "symptom", "cause", "failureScenario", "scenario", "why", "evidence", "what_changed", "reason"]);
        const detail = [more, said2 && !said2.startsWith(title) && said2 !== named ? said2 : ""].filter(x => x).join("\n\n");
        const severity = pick(["severity", "priority", "impact"]);
        const s = severity.toLowerCase();
        const level = ["p0", "p1", "blocker", "critical", "high", "severe"].includes(s) ? "high" : ["p2", "major", "medium", "moderate"].includes(s) ? "medium" : s ? "low" : "";
        const file = pick(["file", "where", "path"]);
        const state = o.real === false ? "not real" : o.real === true ? "real" : o.fixed === true ? "fixed" : typeof o.done === "boolean" ? (o.done ? "done" : "not done") : pick(["status", "verdict"]);
        return { item: true, title: said(title), detail: said(detail), fix: said(pick(["fix", "better_fix"])), level: level,
                 meta: [severity, state, file ? said(file).split("/").pop() + (o.line !== undefined && !String(file).includes(":") ? `:${o.line}` : "") : ""].filter(x => x).join(" · ") };
    }

    // a long report folds after its first two paragraphs (a structured one's, under its first label)
    readonly property int foldAt: {
        const b = ap.reportBlocks, at = b.length && b[0].label !== undefined ? 3 : 2;
        return b.length > at + 1 ? at : b.length;
    }
    property var navIds: []
    function navKey(k) { return false; }

    component Quiet: Item {
        id: q
        property string text: ""
        property string glyph: ""
        property bool on: false
        signal clicked()
        width: qRow.implicitWidth + 16
        height: 30
        Rectangle { anchors.fill: parent; radius: 8; color: q.on ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8) : qArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent" }
        Row {
            id: qRow
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            MaterialSymbol { visible: q.glyph.length > 0; anchors.verticalCenter: parent.verticalCenter; text: q.glyph; iconSize: 16; color: Appearance.colors.colInkSecondary }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: q.text; font.pixelSize: 15; color: q.on ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary }
        }
        MouseArea { id: qArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.clicked() }
    }
    // one step's line: its number, its kind, what it did
    component StepLine: Item {
        id: sl
        property int i: 0
        property string kindWord: ""
        property string what: ""
        property bool hit: false
        property bool link: false
        signal clicked()
        width: parent ? parent.width : 0
        height: slRow.implicitHeight
        Rectangle {
            anchors { fill: parent; leftMargin: -6; rightMargin: -10; topMargin: -3; bottomMargin: -3 }
            radius: 8
            color: sl.hit ? ColorUtils.transparentize(Appearance.m3colors.m3primaryContainer, 0.62) : "transparent"
            Behavior on color { ColorAnimation { duration: 400 } }
        }
        Row {
            id: slRow
            width: sl.width
            spacing: 8
            StyledText { width: 26; horizontalAlignment: Text.AlignRight; text: sl.i + 1; font.pixelSize: 13; font.features: { "tnum": 1 }; color: Appearance.colors.colInkMeta; topPadding: 1 }
            StyledText { width: 62; text: sl.kindWord; font.pixelSize: 14; font.weight: Font.Medium; color: Appearance.colors.colInkSecondary; elide: Text.ElideRight }
            StyledText { width: sl.width - 104; text: sl.what; font.pixelSize: 14; color: sl.hit || (sl.link && slArea.containsMouse) ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary; elide: Text.ElideMiddle }
        }
        MouseArea { id: slArea; anchors.fill: parent; enabled: sl.link; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sl.clicked() }
    }

    Column {
        id: col
        width: parent.width
        spacing: 4
        StyledText {
            visible: !ap.a
            width: parent.width
            topPadding: 16
            text: "This agent is no longer in the session's list."
            font.pixelSize: 15
            color: Appearance.colors.colInkSecondary
        }
        StyledText {
            visible: !!ap.a
            width: parent.width
            topPadding: 6
            wrapMode: Text.Wrap
            text: ap.a?.description || ap.a?.label || "Agent"
            font.pixelSize: 24
            font.weight: Font.DemiBold
            color: Appearance.colors.colInkMain
        }
        StyledText {
            visible: !!ap.a
            width: parent.width
            elide: Text.ElideRight
            text: ap.a ? [({ running: "Running", done: "Done", failed: "Failed", stopped: "Stopped" })[ap.a.state] ?? "Waiting",
                          ap.p.took(ap.a), `${ap.a.steps ?? ap.tools.length} steps`, ap.a.type ?? "", ap.p.modelName(ap.a.model ?? "")].filter(x => x && x.length).join(" · ") : ""
            font.pixelSize: 14
            font.features: { "tnum": 1 }
            topPadding: 4
            color: ap.a?.state === "failed" ? Appearance.colors.colClay : Appearance.colors.colInkSecondary
        }
        StyledText {
            visible: (ap.detail?.asked ?? "").length > 0
            width: parent.width
            topPadding: 4
            wrapMode: Text.Wrap
            maximumLineCount: ap.entry.f.asked ? 400 : 1
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: `<font color="${Appearance.colors.colInkSecondary}">Asked</font> ${String(ap.detail?.asked ?? "").replace(/^\s*\[[^\]\n]{0,80}\]\s*/, "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n+/g, " ")}`
            font.pixelSize: 14
            color: Appearance.colors.colInkSecondary
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { ap.entry.f.asked = !ap.entry.f.asked; ap.bump(); } }
        }
        Row {
            x: -8
            topPadding: 6
            spacing: 2
            Quiet {
                visible: ap.p.canStop && ap.running && (ap.a?.background ?? false) && (ap.a?.task ?? "").length > 0
                glyph: "stop"
                text: ap.p.stopShows(ap.a) === "stopping" ? "Stopping…" : "Stop"
                onClicked: ap.p.stop(ap.a)
            }
        }
        StyledText {
            visible: ap.running && ap.p.stopShows(ap.a) === "refused"
            width: parent.width
            wrapMode: Text.Wrap
            text: ap.p.refusal(ap.a)
            font.pixelSize: 14
            color: Appearance.colors.colInkSecondary
        }

        // ── what matters first ──────────────────────────────────────────────
        Rectangle {
            visible: ap.running
            width: parent.width
            height: 42
            radius: 12
            color: ColorUtils.transparentize(Appearance.m3colors.m3primaryContainer, 0.72)
            Row {
                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 10
                StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Now"; font.pixelSize: 14; font.weight: Font.DemiBold; color: Appearance.colors.colPrimary }
                ShineText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 50
                    text: ap.p.lineOf(ap.a)
                    active: ap.running
                    pixelSize: 15
                }
            }
        }
        Rectangle {
            visible: ap.a?.state === "failed"
            width: parent.width
            height: errCol.implicitHeight + 22
            radius: 12
            color: ColorUtils.transparentize(Appearance.colors.colClay, 0.86)
            Column {
                id: errCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11; leftMargin: 13; rightMargin: 13 }
                spacing: 3
                StyledText { text: "It stopped"; font.pixelSize: 14; font.weight: Font.DemiBold; color: Appearance.colors.colClay }
                StyledText { width: parent.width; wrapMode: Text.Wrap; text: ap.a?.error ?? ap.detail?.report ?? ""; font.pixelSize: 15; color: Appearance.colors.colInkMain }
            }
        }
        StyledText {
            readonly property string says: (ap.data?.error ?? "").length ? ap.data.error : ap.detail === null ? "Reading…" : ""
            visible: says.length > 0
            width: parent.width
            topPadding: 8
            wrapMode: Text.Wrap
            text: says
            font.pixelSize: 15
            color: Appearance.colors.colInkMeta
        }
        PanelSection {
            visible: reportBox.visible
            topPadding: 22
            text: "Report"
            actionText: copied.running ? "Copied" : "Copy"
            actionGlyph: "content_copy"
            onAction: { Quickshell.clipboardText = ap.detail.report; copied.restart(); }
            Timer { id: copied; interval: 1500 }
        }
        Column {
            id: reportBox
            readonly property bool long: ap.foldAt < ap.reportBlocks.length
            visible: !ap.running && ap.a?.state !== "failed" && ap.reportBlocks.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: ap.running ? [] : reportBox.long && !ap.entry.f.report ? ap.reportBlocks.slice(0, ap.foldAt) : ap.reportBlocks
                delegate: Loader {
                    required property var modelData
                    width: parent.width
                    sourceComponent: modelData.label !== undefined ? reportLabel : modelData.item ? reportItem : modelData.code ? reportCode : reportText
                    Component { id: reportLabel; StyledText { topPadding: 10; text: modelData.label; font.pixelSize: 14; font.weight: Font.DemiBold; color: Appearance.colors.colInkSecondary } }
                    // a finding of the report: a severity mark, its title, what was said, the fix, how bad and where
                    Component {
                        id: reportItem
                        Item {
                            implicitHeight: itemCol.implicitHeight + 18
                            Rectangle {
                                x: 7
                                y: 8
                                width: 7; height: 7; radius: 3.5
                                color: modelData.level === "high" ? Appearance.colors.colClay
                                     : modelData.level === "medium" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)
                                     : ColorUtils.transparentize(Appearance.colors.colInkFaint, 0.3)
                            }
                            Column {
                                id: itemCol
                                x: 34
                                width: parent.width - 34
                                spacing: 3
                                StyledText { width: parent.width; wrapMode: Text.Wrap; text: modelData.title; font.pixelSize: 16; font.weight: Font.Medium; color: Appearance.colors.colInkMain }
                                StyledText { visible: modelData.detail.length > 0; width: parent.width; wrapMode: Text.Wrap; text: modelData.detail; font.pixelSize: 15; lineHeight: 1.15; color: Appearance.colors.colInkSecondary }
                                StyledText { visible: modelData.fix.length > 0; width: parent.width; wrapMode: Text.Wrap; text: `Fix: ${modelData.fix}`; font.pixelSize: 15; lineHeight: 1.15; color: Appearance.colors.colInkSecondary }
                                StyledText { visible: modelData.meta.length > 0; width: parent.width; elide: Text.ElideRight; text: modelData.meta; font.pixelSize: 14; color: Appearance.colors.colInkMeta }
                            }
                        }
                    }
                    Component { id: reportText; ClaudeText { markdown: modelData.content; compact: true } }
                    Component { id: reportCode; CodeBlock { code: modelData.content; lang: modelData.lang } }
                }
            }
            StyledText {
                visible: ap.detail?.cut ?? false
                width: parent.width
                wrapMode: Text.Wrap
                text: "The report goes on past 200,000 characters; the rest is in the agent's transcript."
                font.pixelSize: 14
                color: Appearance.colors.colInkMeta
            }
        }
        Quiet {
            visible: reportBox.visible && reportBox.long
            x: -8
            glyph: ap.entry.f.report ? "expand_less" : "expand_more"
            text: ap.entry.f.report ? "Fold the report" : "Read the whole report"
            onClicked: { ap.entry.f.report = !ap.entry.f.report; ap.bump(); }
        }

        // ── where it sits ──────────────────────────────────────────────────
        PanelSection { visible: !!ap.a?.inRun; text: "In the workflow" }
        PanelRow {
            readonly property var run: ap.p.runs.find(r => r.run === ap.a?.inRun) ?? null
            visible: !!run
            mark: run?.state ?? "done"
            title: ap.p.runName(run)
            line: run ? `${(run.agents ?? []).filter(m => m.state === "done").length} of ${(run.agents ?? []).length} done` : ""
            meta: ap.p.took(run)
            onClicked: ap.p.openRun(ap.a.inRun)
        }
        PanelSection { visible: !!(ap.a?.parent && ap.p.tree.byId[ap.a.parent]); text: "Started by" }
        PanelRow {
            readonly property var par: ap.a?.parent ? ap.p.tree.byId[ap.a.parent] ?? null : null
            visible: !!par
            mark: par?.state ?? "done"
            title: par?.description || "Agent"
            line: ap.p.lineOf(par)
            meta: ap.p.took(par)
            onClicked: ap.p.openAgent(par.agent)
        }
        PanelSection { visible: (ap.p.tree.kids[ap.entry.id] ?? []).length > 0; text: "Agents it started"; count: (ap.p.tree.kids[ap.entry.id] ?? []).length }
        Repeater {
            model: ap.p.tree.kids[ap.entry.id] ?? []
            PanelRow {
                required property var modelData
                mark: modelData.state
                title: modelData.description || "Agent"
                line: ap.p.lineOf(modelData)
                tone: modelData.state === "failed" ? "bad" : modelData.state === "running" ? "live" : ""
                meta: ap.p.took(modelData)
                onClicked: ap.p.openAgent(modelData.agent)
            }
        }

        // ── the activity ───────────────────────────────────────────────────
        PanelSection { visible: ap.tools.length > 0; text: "Activity"; count: ap.tools.length }
        // the whole run as ticks, the steps in view below marked on it
        TickStrip {
            visible: ap.tools.length > 1
            width: parent.width
            kinds: ap.kinds
            labels: ap.labels
            viewLo: ap.viewLo
            viewHi: ap.viewHi
            fresh: ap.freshSteps
            onJump: i => ap.jumpTo(i)
        }
        Item { visible: ap.tools.length > 1; width: 1; height: 12 }
        Flow {
            visible: ap.tools.length > 0
            width: parent.width
            spacing: 6
            bottomPadding: 10
            Repeater {
                model: [["all", "All", ap.tools.length], ["edit", "Edits", ap.counts.edit], ["picture", "Pictures", ap.counts.picture], ["files", "Files", ap.fileList.length], ["command", "Commands", ap.counts.command]].filter(x => x[2] > 0)
                Quiet {
                    required property var modelData
                    text: `${modelData[1]}  ${modelData[2]}`
                    on: ap.filter === modelData[0]
                    onClicked: { ap.entry.f.filter = modelData[0]; ap.entry.f.follow = modelData[0] === "all" && ap.running; ap.unseen = 0; ap.bump(); ap.flick.contentY = 0; }
                }
            }
        }
        // the files its edits touched
        Repeater {
            model: ap.filter === "files" ? ap.fileList : []
            PanelRow {
                required property var modelData
                glyph: "edit"
                title: String(modelData.path).split("/").pop()
                line: String(modelData.path).split("/").slice(0, -1).join("/")
                add: modelData.add ?? 0
                del: modelData.del ?? 0
                onClicked: ap.p.openFile(modelData.path, ap.entry.id)
            }
        }
        Quiet {
            visible: ap.filter === "all" ? ap.storyFrom > 0 : (ap.filter !== "files" && ap.shownFrom > 0)
            x: -8
            glyph: "expand_less"
            text: ap.filter === "all" ? "Show what came before" : `Show the ${ap.groups.slice(0, ap.shownFrom).reduce((n, g) => n + g.items.length, 0)} earlier steps`
            onClicked: { ap.entry.f.all = true; ap.bump(); }
        }
        Repeater {
            id: storyRep
            model: ap.filter === "all" ? ap.shownStory : []
            delegate: Loader {
                id: piece
                required property var modelData
                required property int index
                width: col.width
                sourceComponent: piece.modelData.type === "activity" ? storyActivity : piece.modelData.type === "code" ? storyCode : storyText
                Component { id: storyText; ClaudeText { topPadding: 12; bottomPadding: 4; markdown: piece.modelData.content; compact: true } }
                Component { id: storyCode; CodeBlock { code: piece.modelData.content; lang: piece.modelData.lang } }
                Component {
                    id: storyActivity
                    ActivityGroup {
                        tools: piece.modelData.tools
                        openIds: ap.openIds
                        onToggled: key => ap.toggleOpen(key)
                        viewer: pictureShim
                        files: ap.p.files
                        runningLast: ap.running && piece.index === ap.shownStory.length - 1
                    }
                }
            }
        }
        Repeater {
            id: stream
            model: ap.filter === "files" || ap.filter === "all" ? [] : ap.shownGroups
            Column {
                id: grp
                required property var modelData
                readonly property var g: grp.modelData
                readonly property bool folded: grp.g.items.length >= 3 && !ap.entry.f[`g${grp.g.items[0]}`]
                width: col.width
                spacing: 0
                // a run of reads or commands: one line that opens to them
                Item {
                    visible: grp.g.items.length >= 3
                    width: parent.width
                    height: 28
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        StyledText { width: 26; horizontalAlignment: Text.AlignRight; text: grp.g.items[0] + 1; font.pixelSize: 13; font.features: { "tnum": 1 }; color: Appearance.colors.colInkMeta }
                        StyledText { text: `${grp.g.items.length} ${grp.g.k === "command" ? "commands" : "reads and searches"}`; font.pixelSize: 14; font.weight: Font.Medium; color: foldArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary }
                    }
                    MaterialSymbol { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: grp.folded ? "chevron_right" : "expand_more"; iconSize: 15; color: Appearance.colors.colInkFaint }
                    MouseArea { id: foldArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { ap.entry.f[`g${grp.g.items[0]}`] = grp.folded; ap.bump(); } }
                }
                Repeater {
                    model: grp.folded ? [] : grp.g.items
                    Column {
                        id: st
                        required property int modelData
                        readonly property var it: ap.tools[st.modelData] ?? ({})
                        readonly property string k: ap.kinds[st.modelData] ?? "read"
                        readonly property bool open: !!ap.entry.f[`open${st.modelData}`]
                        width: col.width
                        spacing: 4
                        topPadding: 5
                        bottomPadding: st.k === "edit" || st.k === "picture" ? 12 : 4
                        opacity: ap.freshSteps[st.modelData] ? 0 : 1
                        Component.onCompleted: if (ap.freshSteps[st.modelData]) opacity = 1
                        Behavior on opacity { NumberAnimation { duration: 500 } }
                        StepLine {
                            i: st.modelData
                            hit: ap.entry.f.hit === st.modelData
                            kindWord: st.k === "edit" ? (st.it.tool === "Write" ? "Write" : "Edit") : st.k === "picture" ? "Picture" : ap.toolWord(st.it.tool)
                            what: st.k === "edit" ? (st.it.files ?? []).map(f => `${String(f.path).split("/").pop()} +${f.add ?? 0} −${f.del ?? 0}`).join(", ") || ap.textOf(st.it) : ap.textOf(st.it)
                            link: st.k === "edit" && (st.it.files ?? []).length > 0
                            onClicked: ap.p.openFile(st.it.files[0].path, ap.entry.id)
                        }
                        // an edit as its diff: about five lines, the whole change on a click
                        Item {
                            visible: st.k === "edit"
                            x: 34
                            width: parent.width - 34
                            height: visible ? Math.min(dv.implicitHeight, st.open ? 100000 : 112) : 0
                            clip: true
                            Rectangle { anchors.fill: parent; radius: 10; color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.96) }
                            DiffView { id: dv; width: parent.width; item: st.k === "edit" ? st.it : ({}) }
                        }
                        StyledText {
                            visible: st.k === "edit" && dv.implicitHeight > 112
                            x: 34
                            text: st.open ? "Fold the change" : "Show the whole change"
                            font.pixelSize: 14
                            color: wholeArea.containsMouse ? Appearance.colors.colInkMain : Appearance.colors.colInkMeta
                            MouseArea { id: wholeArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { ap.entry.f[`open${st.modelData}`] = !st.open; ap.bump(); } }
                        }
                        // a picture as the conversation shows one: fitted, framed, in the text column
                        Thumbs {
                            visible: st.k === "picture"
                            x: 34
                            width: parent.width - 34
                            paths: st.k === "picture" ? st.it.images : []
                            viewer: pictureShim
                        }
                    }
                }
            }
        }
    }

    // Thumbs opens a picture through a viewer; the panel's goes to the window's
    QtObject { id: pictureShim; function show(p) { ap.p.pictureRequested(p); } }

    // what arrived while you were scrolled up
    over: Rectangle {
        visible: ap.running && ap.unseen > 0 && !ap.entry.f.follow
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        width: pillRow.implicitWidth + 28
        height: 32
        radius: 16
        color: Appearance.m3colors.m3primaryContainer
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            StyledText { text: `${ap.unseen} new ${ap.unseen === 1 ? "step" : "steps"}`; font.pixelSize: 14; color: Appearance.m3colors.m3onPrimaryContainer }
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "arrow_downward"; iconSize: 15; color: Appearance.m3colors.m3onPrimaryContainer }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { ap.entry.f.follow = true; ap.toEnd(); } }
    }
}
