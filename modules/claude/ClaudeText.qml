import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions
import "Markdown.js" as Md

// Message text: markdown turned into Qt rich text by Markdown.js with the palette's colours,
// selectable. Body text sits a step below full on-surface; bold and headings take the full
// tone, inline code the tertiary colour on a container chip, links the primary.
TextArea {
    // as StyledText: letters as designed, nothing snapped (fontconfig's full hinting widened Tacit Sans)
    font.hintingPreference: Font.PreferNoHinting
    id: root
    property string markdown: ""
    property string highlight: ""      // find in the conversation: its matches get a tone behind them
    property bool plainText: false
    property bool compact: false       // the side panel's sizes: the conversation's text, headings 18/17/16

    readonly property var tokens: ({
        // the solved inks (APCA Lc on this ground): the old fixed mix read grey, Lc ~71 measured on the frost,
        // under the 75 body text needs (owner 2026-10-09: "text gray and background is gray")
        text: Appearance.colors.colInkMain.toString(),
        strong: Appearance.colors.colInkMain.toString(),
        dim: Appearance.colors.colInkSecondary.toString(),
        link: Appearance.m3colors.m3primary.toString(),
        code: Appearance.m3colors.m3tertiary.toString(),
        // an rgba overlay, never a solid grey: the window is see-through and warm behind the text
        codeBg: `rgba(${Math.round(Appearance.m3colors.m3onSurface.r * 255)},${Math.round(Appearance.m3colors.m3onSurface.g * 255)},${Math.round(Appearance.m3colors.m3onSurface.b * 255)},0.08)`,
        rule: Appearance.m3colors.m3outlineVariant.toString(),
        mono: Appearance.font.family.monospace,
        codeSize: 14,
        lh: 125,             // Qt takes this against the font's own line height (1.25 em): 125% = 1.56x the size
        gap: root.compact ? 10 : 14,
        h1: root.compact ? 18 : 22,
        h2: root.compact ? 17 : 19,
        h3: root.compact ? 16 : 17
    })

    readOnly: true
    selectByMouse: true
    renderType: Text.NativeRendering
    font.family: Appearance.font.family.main
    font.pixelSize: 16
    // the main face's weight, as StyledText's; left unset it drew the face's Regular (400)
    font.variableAxes: Appearance.font.variableAxes.main
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    wrapMode: TextEdit.Wrap
    color: root.tokens.text
    textFormat: TextEdit.RichText
    text: root.mark(root.plainText ? Md.plain(root.markdown) : Md.toHtml(root.markdown, root.tokens))
    // matches in the text between tags only, so markup and link targets are left alone, and never inside an entity (&lt;)
    function mark(html) {
        if (root.highlight.length < 2) return html;
        const re = new RegExp(Md.esc(root.highlight).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
        const tone = `rgba(${Math.round(Appearance.colors.colPrimary.r * 255)},${Math.round(Appearance.colors.colPrimary.g * 255)},${Math.round(Appearance.colors.colPrimary.b * 255)},0.42)`;
        return ("<i></i>" + html).replace(/>([^<]+)</g, (m, t) => ">" + t.split(/(&#?\w+;)/).map((part, i) => i % 2 ? part : part.replace(re, x => `<span style="background-color:${tone}">${x}</span>`)).join("") + "<").substring(7);
    }
    padding: 0
    // compact (the side panel): on the page's text edge; the document keeps a 4 px margin of its own
    leftPadding: root.compact ? -2 : 0
    rightPadding: root.compact ? -2 : 0
    background: null

    // only web and mail links open: a reply can be steered by what the agent read, and file: or another scheme
    // would be handed to whatever program the desktop has for it
    onLinkActivated: link => { if (/^(https?|mailto):/i.test(link)) Qt.openUrlExternally(link); }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
    }
}
