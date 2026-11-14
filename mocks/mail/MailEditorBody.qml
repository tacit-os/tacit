import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Tacit.Kit as K

Item {
    id: body

    signal dropFinished()
    signal fileDropped(url file, int position)

    property string draftId: ""
    property string draftText: ""
    property string draftHtml: ""
    property bool animationsPaused: false
    onAnimationsPausedChanged: documentTools.item?.setAnimationsPaused(animationsPaused)
    readonly property alias input: input
    readonly property var t: K.Kit.tokens
    property string loadedDraftId: ""
    property bool syncing: false
    property bool editingLink: false
    property bool editingExistingLink: false
    property int linkStart: 0
    property int linkEnd: 0
    property int formatRevision: 0
    readonly property var activeFormats: {
        body.formatRevision;
        return documentTools.item?.activeFormats(input.selectionStart, input.selectionEnd) ?? {};
    }
    readonly property bool canClearFormatting: {
        const tools = documentTools.item;
        if (!tools)
            return false;
        const format = activeFormats;
        const font = input.cursorSelection.font;
        return Boolean((typingStart >= 0 ? typingBold || typingItalic : font.bold || font.italic)
            || (format.font && format.font !== "sans-serif" && format.font !== input.font.family)
            || (format.size > 0 && format.size !== 12)
            || format.underline || format.strike || format.highlight
            || (format.color && format.color !== t.inkMain.toString())
            || format.align || format.quote || format.indent
            || tools.isList(input.selectionStart)
            || tools.linkRange(input.selectionStart, input.selectionEnd).url);
    }

    function markFormats(options) {
        return options.map(option => {
            const active = body.activeFormats[option.action];
            const current = option.action === "indent"
                ? option.value === "1" && active === true
                : option.value === undefined ? active === true : String(active) === option.value;
            return Object.assign({}, option, {current: current});
        });
    }
    property int typingStart: -1
    property bool typingBold: false
    property bool typingItalic: false
    signal edited()
    signal submitted()
    signal dismissed()

    property real maximumImageHeight: 480
    property real maximumWritingHeight: 480
    property bool growWithContent: false
    implicitHeight: (toolbar.visible ? toolbar.height : 0)
        + (growWithContent ? Math.max(8 * metrics.lineSpacing, input.contentHeight + metrics.lineSpacing)
            : Math.min(maximumWritingHeight, Math.max(8 * metrics.lineSpacing, input.contentHeight)))
        + 2 * t.space.s

    function insertAttachment(file, attachment, position) {
        if (!documentTools.item)
            return;
        input.cursorPosition = documentTools.item.insertAttachment(
            file, attachment.id, attachment.name, position, Math.floor(input.width), Math.floor(maximumImageHeight));
        edited();
    }

    function focusIn() { input.forceActiveFocus(); }

    function applyFormat(option) {
        documentTools.item.formatRange(input.selectionStart, input.selectionEnd, option.action, option.value ?? "");
        ++formatRevision;
        edited();
        focusIn();
    }

    function snapshot() {
        return { body: documentTools.item?.plainText() ?? input.text,
                 bodyHtml: documentTools.item?.html() ?? "" };
    }

    function syncDraft() {
        if (!draftId)
            return;
        const current = snapshot();
        if (loadedDraftId === draftId && current.body === draftText
            && (!documentTools.item || current.bodyHtml === draftHtml))
            return;
        syncing = true;
        typingStart = -1;
        if (loadedDraftId !== draftId)
            editingLink = false;
        loadedDraftId = draftId;
        if (documentTools.item)
            documentTools.item.load(draftText, draftHtml);
        else
            input.text = draftText;
        syncing = false;
        ++formatRevision;
    }

    onDraftIdChanged: syncTimer.restart()
    onDraftTextChanged: syncTimer.restart()
    onDraftHtmlChanged: syncTimer.restart()
    Component.onCompleted: syncTimer.restart()

    Timer {
        id: syncTimer
        interval: 0
        onTriggered: body.syncDraft()
    }

    function emphasize(bold) {
        const selected = input.cursorSelection;
        const font = selected.font;
        const enabled = bold ? !(typingStart >= 0 ? typingBold : font.bold)
                             : !(typingStart >= 0 ? typingItalic : font.italic);
        if (input.selectionStart !== input.selectionEnd) {
            documentTools.item.setEmphasis(input.selectionStart, input.selectionEnd, bold, enabled);
            edited();
        } else {
            if (typingStart !== input.cursorPosition) {
                typingStart = input.cursorPosition;
                typingBold = font.bold;
                typingItalic = font.italic;
            }
            if (bold)
                typingBold = enabled;
            else
                typingItalic = enabled;
        }
        focusIn();
    }

    function beginLink() {
        const range = documentTools.item.linkRange(input.selectionStart, input.selectionEnd);
        linkStart = range.start;
        linkEnd = range.end;
        editingExistingLink = range.url !== "";
        linkField.text = range.url;
        editingLink = true;
        linkField.focusIn();
        linkField.input.selectAll();
    }

    function finishLink(value) {
        const end = documentTools.item.setLink(linkStart, linkEnd, value);
        editingLink = false;
        focusIn();
        if (linkStart === linkEnd)
            input.cursorPosition = end;
        edited();
    }

    Loader {
        id: documentTools
        visible: false
        Component.onCompleted: setSource(Qt.resolvedUrl("MailRichTextDocument.qml"), { document: input.textDocument })
        onLoaded: {
            item.setAnimationsPaused(body.animationsPaused);
            syncTimer.restart();
        }
    }

    component FormatButton: K.IconButton {
        id: control
        property string letter: ""
        tip: label
        size: body.t.icon.rail
        width: body.t.height.field
        height: body.t.height.field
        K.TacitText {
            anchors.centerIn: parent
            visible: control.letter !== ""
            text: control.letter
            weight: control.letter === "B" ? "strong" : "medium"
            font.italic: control.letter === "I"
            color: control.checked ? body.t.accent : control.hovered ? body.t.inkMain : body.t.inkSec
            Accessible.ignored: true
        }
    }

    Item {
        id: toolbar
        width: parent.width
        height: body.editingLink ? body.t.height.field : toolbarLayout.height
        visible: documentTools.status === Loader.Ready

        Flickable {
            id: toolbarLayout
            readonly property bool compactSpacing: width < formatTools.children.reduce(
                (total, control) => total + control.width, 0)
                + (formatTools.children.length + 2) * body.t.space.m
                + clearFormatting.implicitWidth
            readonly property real actionGap: compactSpacing ? body.t.space.xs : body.t.space.m
            width: parent.width
            implicitHeight: toolbarRow.implicitHeight
            height: implicitHeight
            contentWidth: toolbarRow.width
            contentHeight: height
            clip: contentWidth > width
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            visible: !body.editingLink

            Controls.ScrollBar.horizontal: Controls.ScrollBar {
                id: toolbarBar
                parent: toolbar
                anchors.left: toolbar.left
                anchors.right: toolbar.right
                anchors.top: toolbarLayout.bottom
                anchors.topMargin: (body.t.space.s - height) / 2
                height: 2
                padding: 0
                policy: toolbarLayout.interactive ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
            }

            RowLayout {
                id: toolbarRow
                width: Math.max(toolbarLayout.width, implicitWidth)
                spacing: toolbarLayout.actionGap

        Row {
            id: formatTools
            spacing: toolbarLayout.actionGap

            MailFormatMenu {
                text: qsTr("Type")
                formats: body.markFormats([
                    { label: qsTr("Sans serif"), action: "font", value: "sans-serif" },
                    { label: qsTr("Monospace"), action: "font", value: body.t.font.code },
                    { rule: true },
                    { label: qsTr("Small"), action: "size", value: "10" },
                    { label: qsTr("Normal"), action: "size", value: "12" },
                    { label: qsTr("Large"), action: "size", value: "16" },
                    { label: qsTr("Huge"), action: "size", value: "24" }
                ])
                onFormatPicked: format => body.applyFormat(format)
            }

            Row {
                spacing: body.t.space.xs

                FormatButton {
                    objectName: "formatBold"
                    symbol: ""
                    letter: "B"
                    label: qsTr("Bold")
                    checkable: true
                    checked: body.typingStart >= 0 ? body.typingBold : (input.cursorSelection?.font.bold ?? false)
                    onActivated: body.emphasize(true)
                }
                FormatButton {
                    objectName: "formatItalic"
                    symbol: ""
                    letter: "I"
                    label: qsTr("Italic")
                    checkable: true
                    checked: body.typingStart >= 0 ? body.typingItalic : (input.cursorSelection?.font.italic ?? false)
                    onActivated: body.emphasize(false)
                }
            }

            FormatButton {
                objectName: "formatLink"
                symbol: "link"
                label: qsTr("Insert or edit link")
                onActivated: body.beginLink()
            }

            Row {
                spacing: body.t.space.xs

                FormatButton {
                    objectName: "formatList"
                    symbol: "list"
                    label: qsTr("Bulleted list")
                    checkable: true
                    checked: {
                        body.formatRevision;
                        return documentTools.item?.isList(input.selectionStart) ?? false;
                    }
                    onActivated: {
                        documentTools.item.toggleList(input.selectionStart, input.selectionEnd);
                        ++body.formatRevision;
                        body.edited();
                        body.focusIn();
                    }
                }
                MailFormatMenu {
                    text: qsTr("Paragraph")
                    formats: body.markFormats([
                        { label: qsTr("Align left"), action: "align", value: "left" },
                        { label: qsTr("Align center"), action: "align", value: "center" },
                        { label: qsTr("Align right"), action: "align", value: "right" },
                        { rule: true },
                        { label: qsTr("Numbered list"), action: "numbered" },
                        { label: qsTr("Decrease indent"), action: "indent", value: "-1" },
                        { label: qsTr("Increase indent"), action: "indent", value: "1" },
                        { label: qsTr("Quote"), action: "quote" }
                    ])
                    onFormatPicked: format => body.applyFormat(format)
                }
            }

            MailFormatMenu {
                text: qsTr("Style")
                formats: body.markFormats([
                    { label: qsTr("Underline"), action: "underline" },
                    { label: qsTr("Strikethrough"), action: "strike" },
                    { rule: true },
                    { label: qsTr("Text · Accent"), action: "color", value: body.t.accent.toString() },
                    { label: qsTr("Text · Main"), action: "color", value: body.t.inkMain.toString() },
                    { label: qsTr("Highlight · Accent"), action: "highlight", value: body.t.accent.toString() }
                ])
                onFormatPicked: format => body.applyFormat(format)
            }
        }

            Item { Layout.fillWidth: true }

            Item {
                implicitWidth: clearFormatting.implicitWidth
                implicitHeight: clearFormatting.implicitHeight
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.rightMargin: toolbarLayout.actionGap

                MailAction {
                    id: clearFormatting
                    objectName: "clearFormatting"
                    anchors.fill: parent
                    text: qsTr("Clear formatting")
                    visible: body.canClearFormatting
                    enabled: body.canClearFormatting
                    onActivated: {
                        body.typingStart = -1;
                        body.applyFormat({action: "clear"});
                    }
                }
            }
        }

            }

        RowLayout {
            anchors.fill: parent
            spacing: body.t.space.m
            visible: body.editingLink

            MailEditorField {
                id: linkField
                objectName: "formatLinkUrl"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                label: qsTr("Link address")
                hint: qsTr("https://…")
                Connections {
                    target: linkField.input
                    function onAccepted() { if (applyLink.enabled) body.finishLink(linkField.text); }
                }
            }
            MailAction {
                id: applyLink
                objectName: "applyFormatLink"
                text: qsTr("Apply")
                enabled: documentTools.item?.validLink(linkField.text) ?? false
                onActivated: body.finishLink(linkField.text)
            }
            MailAction {
                visible: body.editingExistingLink
                text: qsTr("Remove link")
                onActivated: body.finishLink("")
            }
            MailAction {
                text: qsTr("Cancel")
                onActivated: { body.editingLink = false; body.focusIn(); }
            }
        }

        Shortcut {
            sequence: "Escape"
            enabled: body.editingLink
            onActivated: { body.editingLink = false; body.focusIn(); }
        }
    }

    FontMetrics {
        id: metrics
        font: input.font
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.topMargin: body.t.space.s + (toolbar.visible ? toolbar.height : 0)
        anchors.bottomMargin: body.t.space.s
        contentWidth: width
        contentHeight: input.contentHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        clip: true

        TextEdit {
            id: input
            width: scroll.width
            height: Math.max(contentHeight, scroll.height)
            textFormat: toolbar.visible ? TextEdit.RichText : TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            persistentSelection: true
            activeFocusOnTab: true
            font: placeholder.font
            renderType: placeholder.renderType
            color: body.t.inkMain
            selectionColor: Qt.alpha(body.t.accent, 0.4)
            selectedTextColor: body.t.inkMain
            cursorDelegate: Rectangle {
                width: 1.5
                color: "transparent"
                visible: input.cursorVisible
            }
            Rectangle {
                readonly property rect caretGeometry: {
                    body.formatRevision;
                    const nativeCaret = input.cursorRectangle;
                    const position = input.cursorPosition;
                    return input.positionToRectangle(position);
                }
                x: caretGeometry.x
                y: caretGeometry.y
                height: caretGeometry.height
                width: 1.5
                color: body.t.accent
                visible: input.activeFocus && input.cursorVisible
                Accessible.ignored: true
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: qsTr("Message body")
            Accessible.multiLine: true
            onTextChanged: {
                ++body.formatRevision;
                if (!body.syncing && body.loadedDraftId === body.draftId && body.draftId !== "")
                    body.edited();
            }
            onCursorRectangleChanged: {
                const caret = cursorRectangle;
                if (caret.y < scroll.contentY)
                    scroll.contentY = caret.y;
                else if (caret.y + caret.height > scroll.contentY + scroll.height)
                    scroll.contentY = caret.y + caret.height - scroll.height;
            }
            onSelectedTextChanged: {
                if (selectionStart !== selectionEnd)
                    body.typingStart = -1;
            }
            Keys.onPressed: event => {
                K.Kit.focusVisible = true;
                if (documentTools.item && event.matches(StandardKey.Paste)) {
                    const end = documentTools.item.pasteClipboard(selectionStart, selectionEnd, Math.floor(width), Math.floor(body.maximumImageHeight));
                    if (end >= 0)
                        cursorPosition = end;
                    event.accepted = true;
                } else if (documentTools.item && (event.modifiers & Qt.ControlModifier)
                           && (event.key === Qt.Key_B || event.key === Qt.Key_I || event.key === Qt.Key_K)) {
                    if (event.key === Qt.Key_K)
                        body.beginLink();
                    else
                        body.emphasize(event.key === Qt.Key_B);
                    event.accepted = true;
                } else if (body.typingStart >= 0 && event.text.length > 0
                           && event.text.charCodeAt(0) >= 32
                           && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                    cursorPosition = documentTools.item.insertFormatted(cursorPosition, event.text,
                        body.typingBold, body.typingItalic);
                    body.typingStart = cursorPosition;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    && (event.modifiers & Qt.ControlModifier)) {
                    body.submitted();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    body.dismissed();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    const forward = event.key === Qt.Key_Tab;
                    input.nextItemInFocusChain(forward)?.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
                    event.accepted = true;
                } else {
                    body.typingStart = -1;
                }
            }
        }
    }

    K.TacitText {
        id: placeholder
        y: scroll.y
        width: body.width
        text: qsTr("Write your message")
        size: "body"
        ink: "quiet"
        visible: input.length === 0 && input.preeditText === ""
        Accessible.ignored: true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: input.activeFocus ? body.t.accent : Qt.alpha(body.t.inkMain, body.t.wash.current)
        Accessible.ignored: true
    }

    DropArea {
        id: fileDrop
        anchors.fill: scroll
        onEntered: event => {
            event.accepted = event.hasUrls && event.urls.some(url => String(url).startsWith("file:"));
        }
        onDropped: event => {
            if (!event.hasUrls)
                return;
            const point = input.mapFromItem(fileDrop, event.x, event.y);
            input.cursorPosition = input.positionAt(point.x, point.y);
            for (const file of event.urls) {
                if (String(file).startsWith("file:"))
                    body.fileDropped(file, input.cursorPosition);
            }
            body.focusIn();
            event.acceptProposedAction();
            body.dropFinished();
        }

        Rectangle {
            anchors.fill: parent
            visible: fileDrop.containsDrag
            color: Qt.alpha(body.t.accent, body.t.wash.hover)
            border.color: body.t.accent
            radius: body.t.radius.row
            Accessible.ignored: true
        }
    }

    HoverHandler { cursorShape: Qt.IBeamCursor }
}
