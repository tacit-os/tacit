import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Results, the first page of its tab: how many findings and how many need a look; what is still
 * running; Ask (one Sonnet call per question); the written reports not read yet, read by Sonnet only
 * from the button that says what it costs; what couldn't run; the findings that need a look, highest
 * severity first; those whose file changed after their report, folded (they may be fixed); the
 * settled ones, folded; the files the agents changed; their pictures.
 * Structured reports give their findings for free (agent-host results.rs).
 */
PanelPage {
    id: rp
    bodyHeight: col.implicitHeight
    readonly property var p: rp.pane
    readonly property var r: rp.p.results
    readonly property var all: rp.r?.findings ?? []
    function bump() { rp.entryChanged(); }

    readonly property var levels: ["high", "medium", "low", ""]
    function lvl(f) { const i = rp.levels.indexOf(f.level ?? ""); return i < 0 ? 3 : i; }
    // what needs a look: highest severity first, a problem a checker found real before the rest
    readonly property var look: rp.all.filter(f => f.need === "look" && !f.changedSince)
        .sort((a, b) => rp.lvl(a) - rp.lvl(b) || (!!b.checked?.real - !!a.checked?.real) || ((a.status === "open") - (b.status === "open")))
    readonly property var maybe: rp.all.filter(f => f.need === "look" && f.changedSince)
        .sort((a, b) => rp.lvl(a) - rp.lvl(b))
    readonly property var settled: rp.all.filter(f => f.need !== "look")
    // grouped by how bad when anything is rated; one list when nothing is
    readonly property bool rated: rp.look.some(f => f.level)
    readonly property var lookGroups: rp.rated
        ? [["high", "High"], ["medium", "Medium"], ["low", "Low"], ["none", "Not rated"]]
            .map(x => ({ level: x[0], name: x[1], items: rp.look.filter(f => (f.level || "none") === x[0]) })).filter(g => g.items.length)
        : [{ level: "all", name: "", items: rp.look }]
    readonly property var lookShown: rp.look
    readonly property var running: [...rp.p.runs.filter(x => x.state === "running").map(x => ({ run: x })),
                                    ...rp.p.agents.filter(a => a.state === "running").map(a => ({ agent: a }))]
    function names(f) {
        const s = f.sources ?? [];
        const n = rp.p.niceLabel(s[0]?.name ?? "");
        return s.length > 1 ? `${n} and ${s.length - 1} more` : s.length ? n : "";
    }
    function base(path) { return String(path ?? "").split("/").pop(); }
    function esc(t) { return String(t ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
    function when(ms) { return new Date(ms).toLocaleDateString(Qt.locale(), "d MMM"); }
    readonly property var statusWord: ({ problem: "Problem", open: "Open", fixed: "Fixed", done: "Done", confirmed: "Confirmed", not_a_bug: "Not a bug" })

    // ── the keys: a cursor over the visible rows and buttons, each known by a key ──
    // The mouse and Enter both go through act(), so a row does the same either way.
    readonly property string cur: rp.entry.f.cursor ?? ""
    function fkey(f) { return `f:${f.sources?.[0]?.source ?? ""}|${f.title}`; }
    function runKey(x) { return x.run ? `run:${x.run.run}` : `agent:${x.agent.agent}`; }
    function failedSources() { return [].concat(...(rp.r?.failures ?? []).map(x => x.sources ?? [])); }
    readonly property var navList: {
        const out = [], f = rp.entry.f;
        const unread = (rp.r?.unread?.count ?? 0) > 0 && (rp.r?.reading ?? 0) === 0;
        rp.running.slice(0, f.runN ?? 5).forEach(x => out.push(rp.runKey(x)));
        if (rp.running.length > (f.runN ?? 5)) out.push("more:runN");
        if (unread) out.push("read");
        if (rp.failedSources().length > 0) {
            out.push("fails");
            if (f.failures) rp.failedSources().forEach(x => out.push(`fsrc:${x.source}`));
        }
        for (const g of rp.lookGroups) {
            const key = `lookN-${g.level}`, n = f[key] ?? (g.level === "none" ? 10 : 20);
            g.items.slice(0, n).forEach(x => out.push(rp.fkey(x)));
            if (g.items.length > n) out.push(`more:${key}`);
        }
        if (rp.maybe.length > 0) {
            out.push("maybe");
            if (f.maybe) {
                rp.maybe.slice(0, f.maybeN ?? 20).forEach(x => out.push(rp.fkey(x)));
                if (rp.maybe.length > (f.maybeN ?? 20)) out.push("more:maybeN");
            }
        }
        if (rp.settled.length > 0) {
            out.push("settled");
            if (f.settled) {
                rp.settled.slice(0, f.settledN ?? 20).forEach(x => out.push(rp.fkey(x)));
                if (rp.settled.length > (f.settledN ?? 20)) out.push("more:settledN");
            }
        }
        const changes = rp.r?.changes ?? [];
        changes.slice(0, f.changesN ?? 3).forEach(x => out.push(`file:${x.path}`));
        if (changes.length > (f.changesN ?? 3)) out.push("more:changesN");
        if (changes.length > 0) out.push("review");
        const pics = rp.r?.pictures ?? [];
        pics.slice(0, f.allPictures ? 80 : 6).forEach(x => out.push(`pic:${x.path}`));
        if (pics.length > 6) out.push("pics");
        return out;
    }
    function act(k) {
        const f = rp.entry.f, i = k.indexOf(":"), t = i < 0 ? k : k.slice(0, i), id = i < 0 ? "" : k.slice(i + 1);
        switch (t) {
        case "run": rp.p.openRun(id); return;
        case "agent": case "fsrc": rp.p.openAgent(id); return;
        case "read": rp.p.readReports(); return;
        case "fails": f.failures = !f.failures; break;
        case "f": { const x = [...rp.all].find(y => rp.fkey(y) === k); if (x) rp.p.openFinding(x); return; }
        case "maybe": f.maybe = !f.maybe; break;
        case "settled": f.settled = !f.settled; break;
        case "file": { const x = (rp.r?.changes ?? []).find(y => y.path === id); if (x) rp.p.openFileBy(x.path, x.by); return; }
        case "review": rp.p.reviewRequested(); return;
        case "pic": rp.p.pictureRequested(id); return;
        case "pics": f.allPictures = !f.allPictures; break;
        case "more": {
            if (id === "changesN") {
                const shown = f.changesN ?? 3;
                f.changesN = Math.min((rp.r?.changes ?? []).length, shown === 3 ? 20 : shown + 20);
            } else {
                f[id] = (f[id] ?? (id === "runN" ? 5 : id === "lookN-none" ? 10 : 20)) + 20;
            }
            break;
        }
        }
        rp.bump();
    }
    function navKey(k) {
        const list = rp.navList, n = list.length;
        if (!n) return false;
        const at = list.indexOf(rp.cur);
        if (k === Qt.Key_Down || k === Qt.Key_Up) {
            rp.entry.f.cursor = list[Math.max(0, Math.min(n - 1, at < 0 ? 0 : at + (k === Qt.Key_Down ? 1 : -1)))];
            rp.bump();
            return true;
        }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) && at >= 0) { rp.act(list[at]); return true; }
        return false;
    }

    component Quiet: Item {
        id: q
        property string text: ""
        property string glyph: ""
        property bool on: false
        property bool cursor: false
        property color ink: Appearance.colors.colInkSecondary
        signal clicked()
        width: qRow.implicitWidth + 16
        height: 30
        Rectangle { anchors.fill: parent; radius: 8; color: q.on ? Appearance.m3colors.m3surfaceContainerHigh : (qArea.containsMouse || q.cursor) ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent" }
        Row {
            id: qRow
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            MaterialSymbol { visible: q.glyph.length > 0; anchors.verticalCenter: parent.verticalCenter; text: q.glyph; iconSize: 16; color: q.ink }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: q.text; font.pixelSize: 15; font.features: { "tnum": 1 }; color: q.on ? Appearance.colors.colInkMain : q.ink }
        }
        MouseArea { id: qArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.clicked() }
        onCursorChanged: if (q.cursor) rp.reveal(q)
    }
    // a finding: its severity as a quiet mark, its title, who found it and where
    component FindingRow: Item {
        id: fr
        property var f: ({})
        width: parent ? parent.width : 0
        height: frCol.implicitHeight + 16
        readonly property bool cursor: rp.cur === rp.fkey(fr.f)
        onCursorChanged: if (fr.cursor) rp.reveal(fr)
        Rectangle {
            anchors { fill: parent; leftMargin: -10; rightMargin: -10 }
            radius: 10
            color: (frArea.containsMouse || fr.cursor) ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent"
        }
        Rectangle {
            x: 7
            y: 8 + 8
            width: 7; height: 7; radius: 3.5
            color: fr.f.level === "high" ? Appearance.colors.colClay
                 : fr.f.level === "medium" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)
                 : ColorUtils.transparentize(Appearance.colors.colInkFaint, 0.3)
        }
        Column {
            id: frCol
            x: 34
            y: 8
            width: parent.width - 34 - 24
            spacing: 2
            StyledText {
                width: parent.width
                text: fr.f.title ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: 16
                color: Appearance.colors.colInkMain
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.StyledText
                readonly property string sev: fr.f.level === "high" ? `<font color="${Appearance.colors.colClay}">High</font>`
                                            : fr.f.level === "medium" ? `<font color="${Appearance.colors.colPrimary}">Medium</font>` : fr.f.level === "low" ? "Low" : ""
                text: [sev, fr.f.changedSince ? `File changed ${rp.when(fr.f.changedSince)}` : "",
                       fr.f.checked?.real ? "Checked: real" : "", fr.f.need === "look" ? (fr.f.status === "open" ? "Open" : "") : (rp.statusWord[fr.f.status] ?? ""),
                       rp.esc(rp.names(fr.f)), rp.esc(rp.base(fr.f.files?.[0]))].filter(x => x).join(" · ")
                font.pixelSize: 14
                color: Appearance.colors.colInkSecondary
            }
        }
        MaterialSymbol {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "chevron_right"
            iconSize: 17
            color: (frArea.containsMouse || fr.cursor) ? Appearance.colors.colInkSecondary : Appearance.colors.colInkFaint
        }
        MouseArea { id: frArea; anchors { fill: parent; leftMargin: -10; rightMargin: -10 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rp.act(rp.fkey(fr.f)) }
    }

    Column {
        id: col
        width: parent.width
        spacing: 2

        StyledText {
            // what the host can do is known once it has said hello: away or just back, it is not too old
            readonly property string says: !rp.p.canResults ? (rp.p.host?.greeted ? "Results need a newer background service. Restarting it gets the new one."
                    : "Reconnecting to Praxis's background service…")
                : rp.p.resultsError.length ? rp.p.resultsError
                : !rp.r ? "Reading the agents' reports…"
                : rp.r.counts?.sources === 0 ? "Nothing has reported in this session yet." : ""
            visible: says.length > 0
            width: parent.width
            topPadding: 16
            wrapMode: Text.Wrap
            text: says
            font.pixelSize: 15
            color: Appearance.colors.colInkSecondary
        }
        PillButton { visible: !rp.p.canResults && !!rp.p.host?.greeted; text: "Restart it"; onClicked: rp.p.restartHostRequested() }

        // ── the headline ────────────────────────────────────────────────────
        Row {
            visible: !!rp.r && rp.all.length > 0
            topPadding: 6
            spacing: 10
            StyledText { text: `${rp.look.length}`; font.pixelSize: 28; font.weight: Font.DemiBold; font.features: { "tnum": 1 }; color: Appearance.colors.colPrimary }
            StyledText {
                anchors.baseline: parent.children[0].baseline
                text: `${rp.look.length === 1 ? "needs" : "need"} a look · ${rp.all.length} ${rp.all.length === 1 ? "finding" : "findings"}`
                font.pixelSize: 17
                color: Appearance.colors.colInkSecondary
            }
        }
        StyledText {
            visible: !!rp.r && (rp.r.counts?.sources ?? 0) > 0
            width: parent.width
            text: [`from ${rp.r?.counts?.reports ?? 0} ${(rp.r?.counts?.reports ?? 0) === 1 ? "report" : "reports"}`,
                   (rp.r?.counts?.running ?? 0) ? `${rp.r.counts.running} still running` : ""].filter(x => x).join(" · ")
            font.pixelSize: 14
            color: Appearance.colors.colInkMeta
        }

        // ── still running ───────────────────────────────────────────────────
        PanelSection { visible: rp.running.length > 0; text: "Running"; count: rp.running.length }
        Repeater {
            model: rp.running.slice(0, rp.entry.f.runN ?? 5)
            PanelRow {
                id: runRow
                required property var modelData
                readonly property var run: modelData.run ?? null
                readonly property var members: run?.agents ?? []
                mark: "running"
                title: run ? rp.p.runName(run) : (modelData.agent.description || "Agent")
                line: run ? `${members.filter(m => m.state === "done").length} of ${members.length} done` : rp.p.lineOf(modelData.agent)
                tone: "live"
                meta: rp.p.took(run ?? modelData.agent)
                extra: RunBar { visible: !!run; width: parent ? parent.width : 0; states: members.map(m => m.state) }
                cursor: rp.cur === rp.runKey(modelData)
                onCursorChanged: if (cursor) rp.reveal(runRow)
                onClicked: rp.act(rp.runKey(modelData))
            }
        }

        Quiet {
            readonly property int rest: rp.running.length - (rp.entry.f.runN ?? 5)
            visible: rest > 0
            x: -8
            glyph: "expand_more"
            text: `${Math.min(20, rest)} more of ${rest}`
            cursor: rp.cur === "more:runN"
            onClicked: rp.act("more:runN")
        }

        // ── ask ─────────────────────────────────────────────────────────────
        Item { visible: rp.p.canResults && !!rp.r && rp.r.counts?.reports > 0; width: 1; height: 14 }
        Rectangle {
            visible: rp.p.canResults && !!rp.r && rp.r.counts?.reports > 0
            width: parent.width
            height: 42
            radius: 12
            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94)
            MaterialSymbol { id: askGlyph; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: "chat"; iconSize: 17; color: Appearance.colors.colInkMeta }
            StyledTextInput {
                id: askField
                anchors { left: askGlyph.right; right: parent.right; leftMargin: 8; rightMargin: 12; verticalCenter: parent.verticalCenter }
                font.pixelSize: 16
                color: Appearance.colors.colInkMain
                clip: true
                Keys.onReturnPressed: { rp.p.ask(text); }
                Keys.onEnterPressed: { rp.p.ask(text); }
                StyledText {
                    visible: askField.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ask Sonnet about these results"
                    font.pixelSize: 16
                    color: Appearance.colors.colInkFaint
                }
            }
        }
        // the answer, with the reports it rests on
        Column {
            visible: !!rp.p.answer
            width: parent.width
            topPadding: 10
            spacing: 6
            StyledText {
                width: parent.width
                wrapMode: Text.Wrap
                text: rp.p.answer?.q ?? ""
                font.pixelSize: 14
                color: Appearance.colors.colInkMeta
            }
            ShineText {
                visible: rp.p.answer?.asking ?? false
                width: parent.width
                text: "Asking Sonnet…"
                active: visible
                pixelSize: 15
                color: Appearance.colors.colInkSecondary
            }
            StyledText {
                visible: !!rp.p.answer?.error
                width: parent.width
                wrapMode: Text.Wrap
                text: rp.p.answer?.error ?? ""
                font.pixelSize: 15
                color: Appearance.colors.colClay
            }
            ClaudeText { visible: !!rp.p.answer?.answer; width: parent.width; markdown: rp.p.answer?.answer ?? "" }
            Repeater {
                model: rp.p.answer?.sources ?? []
                PanelRow {
                    required property var modelData
                    readonly property var a: rp.p.findAgent(rp.p.info, modelData.source)
                    mark: a?.state ?? "done"
                    title: modelData.name
                    line: a ? rp.p.lineOf(a) : ""
                    chevron: !!a
                    onClicked: if (a) rp.p.openAgent(modelData.source)
                }
            }
            StyledText {
                visible: !!rp.p.answer?.answer
                text: `Answered by Sonnet from these reports · $${(rp.p.answer?.cost ?? 0).toFixed(2)}`
                font.pixelSize: 14
                color: Appearance.colors.colInkFaint
            }
        }

        // ── written reports, read only on request ───────────────────────────
        Item { visible: (rp.r?.unread?.count ?? 0) > 0 || (rp.r?.reading ?? 0) > 0; width: 1; height: 10 }
        Rectangle {
            id: readBtn
            visible: (rp.r?.unread?.count ?? 0) > 0 && (rp.r?.reading ?? 0) === 0
            readonly property bool cursor: rp.cur === "read"
            onCursorChanged: if (cursor) rp.reveal(readBtn)
            width: parent.width
            height: 42
            radius: 10
            color: (readArea.containsMouse || rp.cur === "read") ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.94) : "transparent"
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.84)
            Row {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "description"; iconSize: 17; color: Appearance.colors.colInkSecondary }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `Read ${rp.r?.unread?.count ?? 0} written ${(rp.r?.unread?.count ?? 0) === 1 ? "report" : "reports"}`
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    color: Appearance.colors.colInkMain
                }
            }
            StyledText {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: `about $${(rp.r?.unread?.cost ?? 0).toFixed(2)}`
                font.pixelSize: 14
                font.features: { "tnum": 1 }
                color: Appearance.colors.colPrimary
            }
            MouseArea { id: readArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rp.act("read") }
        }
        StyledText {
            visible: (rp.r?.unread?.count ?? 0) > 0 && (rp.r?.reading ?? 0) === 0
            width: parent.width
            topPadding: 6
            wrapMode: Text.Wrap
            text: "Sonnet reads each once; every finding quotes its report."
            font.pixelSize: 14
            color: Appearance.colors.colInkSecondary
        }
        ShineText {
            visible: (rp.r?.reading ?? 0) > 0
            width: parent.width
            text: `Reading ${rp.r?.reading ?? 0} written ${(rp.r?.reading ?? 0) === 1 ? "report" : "reports"}…`
            active: visible
            pixelSize: 15
            color: Appearance.colors.colInkSecondary
        }
        StyledText {
            visible: !!rp.r?.error
            width: parent.width
            wrapMode: Text.Wrap
            text: `Couldn't read a report: ${rp.r?.error ?? ""}`
            font.pixelSize: 14
            color: Appearance.colors.colClay
        }

        // ── what couldn't run ───────────────────────────────────────────────
        Item {
            readonly property int n: (rp.r?.failures ?? []).reduce((k, x) => k + (x.sources ?? []).length, 0)
            visible: n > 0
            width: parent.width
            height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "error"; iconSize: 16; color: Appearance.colors.colClay }
                StyledText { anchors.verticalCenter: parent.verticalCenter; text: `${parent.parent.n} couldn't run`; font.pixelSize: 15; color: Appearance.colors.colClay }
                Quiet { anchors.verticalCenter: parent.verticalCenter; text: rp.entry.f.failures ? "Hide" : "Show"; cursor: rp.cur === "fails"; onClicked: rp.act("fails") }
            }
        }
        Repeater {
            model: rp.entry.f.failures ? (rp.r?.failures ?? []) : []
            Column {
                required property var modelData
                width: col.width
                spacing: 0
                StyledText { width: parent.width; topPadding: 4; wrapMode: Text.Wrap; text: modelData.cause; font.pixelSize: 14; color: Appearance.colors.colInkSecondary }
                Repeater {
                    model: modelData.sources ?? []
                    PanelRow {
                        id: failRow
                        required property var modelData
                        mark: "failed"
                        title: modelData.name
                        cursor: rp.cur === `fsrc:${modelData.source}`
                        onCursorChanged: if (cursor) rp.reveal(failRow)
                        onClicked: rp.act(`fsrc:${modelData.source}`)
                    }
                }
            }
        }

        // ── needs a look ────────────────────────────────────────────────────
        PanelSection { visible: rp.look.length > 0 && !rp.rated; text: "Needs a look"; count: rp.look.length }
        Repeater {
            model: rp.lookGroups
            Column {
                id: lg
                required property var modelData
                readonly property string key: `lookN-${lg.modelData.level}`
                readonly property int n: rp.entry.f[lg.key] ?? (lg.modelData.level === "none" ? 10 : 20)
                width: col.width
                PanelSection { visible: rp.rated; text: lg.modelData.name; count: lg.modelData.items.length }
                Repeater {
                    model: lg.modelData.items.slice(0, lg.n)
                    FindingRow { required property var modelData; f: modelData }
                }
                Quiet {
                    readonly property int rest: lg.modelData.items.length - lg.n
                    visible: rest > 0
                    x: -8
                    glyph: "expand_more"
                    text: `${Math.min(20, rest)} more of ${rest}`
                    cursor: rp.cur === `more:${lg.key}`
                    onClicked: rp.act(`more:${lg.key}`)
                }
            }
        }

        // ── changed since they were found, folded ───────────────────────────
        Item {
            id: maybeRow
            visible: rp.maybe.length > 0
            readonly property bool cursor: rp.cur === "maybe"
            onCursorChanged: if (cursor) rp.reveal(maybeRow)
            width: parent.width
            height: 44
            StyledText {
                anchors { left: parent.left; right: maybeChev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: `${rp.maybe.length} may be fixed · their file changed after the report`
                font.pixelSize: 14
                color: (maybeArea.containsMouse || rp.cur === "maybe") ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
            }
            MaterialSymbol { id: maybeChev; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: rp.entry.f.maybe ? "expand_more" : "chevron_right"; iconSize: 17; color: Appearance.colors.colInkFaint }
            MouseArea { id: maybeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rp.act("maybe") }
        }
        Repeater {
            model: rp.entry.f.maybe ? rp.maybe.slice(0, rp.entry.f.maybeN ?? 20) : []
            FindingRow { required property var modelData; f: modelData }
        }
        Quiet {
            readonly property int rest: rp.maybe.length - (rp.entry.f.maybeN ?? 20)
            visible: !!rp.entry.f.maybe && rest > 0
            x: -8
            glyph: "expand_more"
            text: `${Math.min(20, rest)} more of ${rest}`
            cursor: rp.cur === "more:maybeN"
            onClicked: rp.act("more:maybeN")
        }

        // ── settled, folded ─────────────────────────────────────────────────
        Item {
            id: settledRow
            visible: rp.settled.length > 0
            readonly property bool cursor: rp.cur === "settled"
            onCursorChanged: if (cursor) rp.reveal(settledRow)
            width: parent.width
            height: 44
            StyledText {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: `${rp.settled.length} settled · fixed, done, checked`
                font.pixelSize: 14
                color: (settledArea.containsMouse || rp.cur === "settled") ? Appearance.colors.colInkMain : Appearance.colors.colInkSecondary
            }
            MaterialSymbol { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: rp.entry.f.settled ? "expand_more" : "chevron_right"; iconSize: 17; color: Appearance.colors.colInkFaint }
            MouseArea { id: settledArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rp.act("settled") }
        }
        Repeater {
            model: rp.entry.f.settled ? rp.settled.slice(0, rp.entry.f.settledN ?? 20) : []
            FindingRow { required property var modelData; f: modelData }
        }
        Quiet {
            readonly property int rest: rp.settled.length - (rp.entry.f.settledN ?? 20)
            visible: !!rp.entry.f.settled && rest > 0
            x: -8
            glyph: "expand_more"
            text: `${Math.min(20, rest)} more of ${rest}`
            cursor: rp.cur === "more:settledN"
            onClicked: rp.act("more:settledN")
        }

        // ── the files they changed ──────────────────────────────────────────
        PanelSection { visible: (rp.r?.changes ?? []).length > 0; text: "Changed"; count: (rp.r?.changes ?? []).length }
        Repeater {
            model: (rp.r?.changes ?? []).slice(0, rp.entry.f.changesN ?? 3)
            PanelRow {
                id: fileRow
                required property var modelData
                glyph: "edit"
                title: rp.base(modelData.path)
                line: (modelData.by ?? []).length > 1 ? `${modelData.by.length} agents` : (modelData.by?.[0]?.name ?? "")
                add: modelData.add ?? 0
                del: modelData.del ?? 0
                cursor: rp.cur === `file:${modelData.path}`
                onCursorChanged: if (cursor) rp.reveal(fileRow)
                onClicked: rp.act(`file:${modelData.path}`)
            }
        }
        Row {
            x: -8
            spacing: 2
            Quiet {
                readonly property int n: (rp.r?.changes ?? []).length
                visible: n > (rp.entry.f.changesN ?? 3)
                glyph: "expand_more"
                readonly property int shown: rp.entry.f.changesN ?? 3
                // the first press shows 20 files at most, then 20 more each: the label says how many
                readonly property int next: Math.min(n, shown === 3 ? 20 : shown + 20)
                text: next >= n && shown === 3 ? `All ${n} files` : `${next - shown} more`
                cursor: rp.cur === "more:changesN"
                onClicked: rp.act("more:changesN")
            }
            Quiet { visible: (rp.r?.changes ?? []).length > 0; glyph: "difference"; text: "Review changes"; cursor: rp.cur === "review"; onClicked: rp.act("review") }
        }

        // ── pictures ────────────────────────────────────────────────────────
        PanelSection { visible: (rp.r?.pictures ?? []).length > 0; text: "Pictures"; count: (rp.r?.pictures ?? []).length }
        Flow {
            visible: (rp.r?.pictures ?? []).length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: (rp.r?.pictures ?? []).slice(0, rp.entry.f.allPictures ? 80 : 6)
                Rectangle {
                    id: thumb
                    required property var modelData
                    width: (col.width - 12) / 3
                    height: width * 0.66
                    radius: 8
                    clip: true
                    color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95)
                    Image {
                        anchors.fill: parent
                        source: FileUtils.fileUrl(thumb.modelData.path)
                        fillMode: Image.PreserveAspectCrop
                        verticalAlignment: Image.AlignTop
                        asynchronous: true
                        sourceSize.width: 360
                    }
                    readonly property bool cursor: rp.cur === `pic:${thumb.modelData.path}`
                    onCursorChanged: if (cursor) rp.reveal(thumb)
                    border.width: cursor ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                    MouseArea { id: thumbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rp.act(`pic:${thumb.modelData.path}`) }
                    StyledToolTip { text: `${thumb.modelData.name} · step ${(thumb.modelData.step ?? 0) + 1}`; extraVisibleCondition: thumbArea.containsMouse }
                }
            }
        }
        Quiet {
            visible: (rp.r?.pictures ?? []).length > 6
            x: -8
            glyph: rp.entry.f.allPictures ? "expand_less" : "expand_more"
            text: rp.entry.f.allPictures ? "Fewer pictures" : `All ${(rp.r?.pictures ?? []).length} pictures`
            cursor: rp.cur === "pics"
            onClicked: rp.act("pics")
        }
    }
}
