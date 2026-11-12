import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.tacit

/**
 * The agent asks before running something: what and on what, then Allow once / Always / Deny.
 * Drawn in the composer's tones: the overlay surface and outline, neutral pills (the "yes" a
 * step stronger), no accent fill.
 * "Always" hands back Claude Code's own suggestion, so the rule lands where the CLI puts it.
 * The host's own asks come here too: a copy session reaching a network host (Door: once, this session or this
 * folder) and a write outside its folder (Wall: open that folder for the session).
 */
Rectangle {
    id: card
    property var pending: ({})    // { request, tool, input, suggestions }
    signal answered(bool allow, var permissions, var input)

    readonly property string label: {
        switch (card.pending.tool) {
        case "Bash": return "Run this command?";
        case "Edit": case "MultiEdit": return "Edit this file?";
        case "Write": return "Write this file?";
        case "WebFetch": return "Fetch this page?";
        case "Door": return "Let it reach this address?";
        case "Wall": return "Let it write outside its folder?";
        case "ExitPlanMode": return "Start on this plan?";
        }
        return `Use ${card.pending.tool ?? "this tool"}?`;
    }
    // the plan Plan mode ends with, drawn as the agent's replies are: as the detail it was one cut-off line of JSON
    readonly property string plan: card.pending.tool === "ExitPlanMode" ? String(card.pending.input?.plan ?? "") : ""
    readonly property string detail: {
        const i = card.pending.input ?? {};
        if (card.pending.tool === "Door") return `${i.host ?? ""}${i.port ? ":" + i.port : ""}` + ((i.step ?? "").length ? `\n${i.step}` : "");
        if (card.pending.tool === "Wall") return `${i.path ?? ""}\nOpens ${i.folder ?? "its folder"} for this session`;
        return i.command ?? i.file_path ?? i.url ?? i.pattern ?? i.query ?? JSON.stringify(i);
    }
    readonly property bool canAlways: (card.pending.suggestions ?? []).length > 0
    readonly property var buttons: {
        switch (card.pending.tool) {
        case "Door": return [
            { label: "Allow once", accent: true, allow: true, input: { scope: "once" }, keys: ["Alt+Return", "Alt+Enter"] },
            { label: "This session", accent: false, allow: true, input: { scope: "session" }, keys: ["Alt+S"] },
            { label: "This folder", accent: false, allow: true, input: { scope: "folder" }, keys: ["Alt+F"] },
            { label: "Deny", accent: false, allow: false, keys: ["Alt+N"] }];
        case "Wall": return [
            { label: "Open the folder", accent: true, allow: true, keys: ["Alt+Return", "Alt+Enter"] },
            { label: "Deny", accent: false, allow: false, keys: ["Alt+N"] }];
        }
        return [
            { label: "Allow once", accent: true, allow: true, keys: ["Alt+Return", "Alt+Enter"] },
            { label: "Always allow", accent: false, allow: true, always: true, keys: ["Alt+Shift+Return", "Alt+Shift+Enter"] },
            { label: "Deny", accent: false, allow: false, keys: ["Alt+N"] }
        ].filter(b => !b.always || card.canAlways);
    }
    // what an edit will change, drawn as a finished one is (DiffView): the path alone asked for a yes to an edit
    // you could not see. Clipped as the transcript clips them; cut: the characters left out, said under the diff
    readonly property var change: {
        const i = card.pending.input ?? {};
        const clip = t => String(t ?? "").substring(0, 3000);
        const left = t => Math.max(0, String(t ?? "").length - 3000);
        const all = k => (i.edits ?? []).map(e => e[k] ?? "").join("\n");
        switch (card.pending.tool) {
        case "Edit": return { old: clip(i.old_string), new: clip(i.new_string), cut: left(i.old_string) + left(i.new_string) };
        case "MultiEdit": return { old: clip(all("old_string")), new: clip(all("new_string")), cut: left(all("old_string")) + left(all("new_string")) };
        case "Write": return { new: clip(i.content), cut: left(i.content) };
        }
        return null;
    }
    // answered: the card stays until the host takes the request away; a second click answered a closed
    // request and put up "That request had already closed"
    property bool sent: false
    // keys for the card on top (a second card waiting would share them): the buttons were mouse-only.
    // Each button takes its own (`keys` in `buttons`): Alt chords, as the composer keeps the keyboard while the card
    // is up, and Ctrl+Enter there, meant to send a reply, allowed the request instead
    property bool keys: true
    readonly property bool keyed: card.keys && card.visible && !card.sent
    opacity: card.sent ? 0.6 : 1
    // still here well after the answer (it did not reach the host): it can be answered again
    Timer { running: card.sent; interval: 5000; onTriggered: card.sent = false }
    function pick(b) {
        if (card.sent) return;
        card.sent = true;
        card.answered(b.allow, b.always ? card.pending.suggestions : null, b.input ?? null);
    }

    implicitHeight: column.implicitHeight + 28
    radius: 14
    // as the composer: on the window's frost with a hairline, where the inks keep their contrast (2026-10-11)
    color: "transparent"
    border.width: 1
    border.color: Appearance.colors.colInkDivider

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10
        RowLayout {
            spacing: 8
            MaterialSymbol { text: "back_hand"; iconSize: 17; color: Appearance.colors.colInkSecondary }
            StyledText {
                Layout.fillWidth: true
                text: card.label
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Appearance.colors.colInkMain
            }
        }
        // all of it, scrolling past 220 px as the diff does: cut at six lines, the rest of what Allow once runs could
        // not be read
        Flickable {
            id: detailFlick
            Layout.fillWidth: true
            readonly property Item shown: card.plan.length ? planText : detailText
            Layout.preferredHeight: Math.min(detailFlick.shown.implicitHeight, 220)
            contentHeight: detailFlick.shown.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            GlideWheel { view: detailFlick; chain: true; gain: 1.6; gainPerSpeed: 3; gainMax: 6 }
            StyledText {
                id: detailText
                visible: !card.plan.length
                width: detailFlick.width
                text: card.detail
                // what will run, never markup: as rich text a "<b>" in an echo was drawn bold, its tags gone
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                font.family: Appearance.font.family.monospace
                font.pixelSize: 14
                color: Appearance.colors.colInkSecondary
            }
            ClaudeText {
                id: planText
                visible: card.plan.length > 0
                width: detailFlick.width
                compact: true
                markdown: card.plan
            }
        }
        DiffView {
            visible: card.change !== null
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(implicitHeight, 220) : 0
            item: card.change ?? ({})
        }
        // a Write of 10,000 characters read as if its first 3000 were the whole file
        StyledText {
            visible: (card.change?.cut ?? 0) > 0
            Layout.fillWidth: true
            text: `… ${card.change?.cut ?? 0} more characters not shown`
            font.pixelSize: 13
            color: Appearance.colors.colInkMeta
        }
        Row {
            spacing: 8
            Repeater {
                model: card.buttons
                delegate: Rectangle {
                    required property var modelData
                    // Allow once on sand, Always allow on the soft fill, Deny an outline: three
                    // buttons that look like buttons, the likely one first
                    readonly property real tone: modelData.allow ? 0.9 : 1
                    width: btnText.implicitWidth + 28
                    height: 32
                    radius: Appearance.rounding.full
                    color: modelData.accent ? (btnArea.pressed ? Qt.darker(Appearance.colors.colPrimary, 1.1) : btnArea.containsMouse ? Qt.lighter(Appearance.colors.colPrimary, 1.08) : Appearance.colors.colPrimary)
                         : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, btnArea.pressed ? tone - 0.1 : btnArea.containsMouse ? tone - 0.05 : tone)
                    Behavior on color { enabled: !btnArea.pressed; ColorAnimation { duration: 110 } }
                    // the button the keyboard is on (Tab, then Enter or Space) shows a ring
                    activeFocusOnTab: true
                    Keys.onReturnPressed: card.pick(modelData)
                    Keys.onEnterPressed: card.pick(modelData)
                    Keys.onSpacePressed: card.pick(modelData)
                    border.width: activeFocus ? 1.5 : modelData.allow ? 0 : 1
                    border.color: activeFocus ? Appearance.colors.colInkMain : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.82)
                    Shortcut {
                        sequences: modelData.keys ?? []
                        enabled: card.keyed
                        onActivated: card.pick(modelData)
                    }
                    StyledText {
                        id: btnText
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 14
                        font.weight: modelData.accent ? Font.DemiBold : Font.Medium
                        color: modelData.accent ? Appearance.m3colors.m3onPrimary : Appearance.colors.colInkMain
                    }
                    MouseArea {
                        id: btnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !card.sent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.pick(modelData)
                    }
                }
            }
        }
    }
}
