import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Tacit.Kit as K

FocusScope {
    id: workspace
    property var mailboxClient: null
    property var controller: localSession
    MailWorkspaceSession {
        id: localSession
        mailboxClient: workspace.mailboxClient
        agentInk: workspace.t.accent
    }
    readonly property bool showingMailLoading: !controller.mailboxClient && controller.ui.view === "importing"
    property bool prewarmHtml: false
    readonly property var t: K.Kit.tokens
    readonly property real listMinimum: t.width.rail + t.space.xl
    readonly property real readerMinimum: t.width.panel + t.space.page * 2
    readonly property bool compact: width < listMinimum + readerMinimum
    readonly property bool railFits: width >= listMinimum + readerMinimum + t.width.rail
    readonly property real railWidth: controller.ui.rail && railFits ? t.width.rail - t.space.xl - t.space.l : 0
    readonly property real listWidth: t.width.panel + t.space.page + t.space.m
    readonly property bool firstImport: !!controller.firstImportAccount
    readonly property bool managingImport: firstImport && controller.firstImportInterrupted
        && ["settings", "setup"].includes(controller.ui.view)
    readonly property bool removingLocalMail: !!controller.removingLocalMailAccount
    readonly property bool waitingForStartupAccounts: !!controller.mailboxClient && !controller.hasLoadedAccounts
    readonly property bool fullPage: waitingForStartupAccounts || firstImport || removingLocalMail || ["setup", "settings"].includes(controller.ui.view)
    property bool compactReading: true
    property string selection: controller.ui.selected
    property string activeView: controller.ui.view
    onSelectionChanged: if (selection)
        compactReading = true
    onActiveViewChanged: if (["draft", "compose", "importing"].includes(activeView))
        compactReading = true

    readonly property bool listCountsKnown: !controller.mailboxClient || !!controller.railQuery.displayedKey
    readonly property bool listLoading: controller.ui.searching ? controller.searchQuery.loading : controller.folderQuery.loading
    readonly property string listError: controller.ui.searching ? controller.searchQuery.error
        : controller.folderQuery.folder === controller.ui.folder ? controller.folderQuery.error : ""
    readonly property bool listImportInterrupted: !controller.ui.searching && !listLoading && controller.ui.folder === "Inbox"
        && !controller.rows.length && controller.accounts.some(account => account.importPending
            && controller.syncStatusByAccount[account.id]?.failed)
    readonly property string listCategoryName: ({CATEGORY_PERSONAL: qsTr("Primary"), CATEGORY_PROMOTIONS: qsTr("Promotions"),
        CATEGORY_SOCIAL: qsTr("Social"), CATEGORY_UPDATES: qsTr("Updates")})[controller.activeGmailCategory] || ""

    property int readerSwitchRevision: 0
    property string readerCaptureTarget: ""

    function openMessage(id) {
        compactReading = true;
        if (readerCaptureTarget === id)
            return;
        readerCaptureTarget = "";
        const revision = ++readerSwitchRevision;
        if (id === controller.ui.selected)
            return;
        if (!compact && reader.visible && controller.ui.view === "read" && !controller.ui.attachment
                && K.Kit.ms(t.motion.fadeFast.ms) > 0 && !readerSnapshot.visible) {
            const previous = controller.ui.selected;
            readerCaptureTarget = id;
            if (reader.grabToImage(result => {
                if (revision !== readerSwitchRevision)
                    return;
                readerCaptureTarget = "";
                if (controller.ui.selected !== previous
                        || controller.ui.view !== "read" || !controller.rows.some(row => row.id === id))
                    return;
                readerSnapshot.capture = result;
                readerSnapshot.source = result.url;
                controller.act("select", {id: id});
                readerSnapshot.reveal();
            }))
                return;
        }
        readerCaptureTarget = "";
        readerSnapshot.clear();
        controller.act("select", {id: id});
    }

    function showMailboxes() {
        if (compact || !railFits)
            folderPicker.openAt(folderTitle, 0, folderTitle.height);
        else
            controller.act("rail");
    }

    Item { id: pointerFocus }

    TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        onTapped: point => {
            if (search.activeFocus && !search.contains(search.mapFromItem(workspace, point.position)))
                pointerFocus.forceActiveFocus(Qt.MouseFocusReason);
        }
    }

    MailHtmlCache { id: renderedMail }
    Component.onCompleted: controller.htmlCache = renderedMail
    Component.onDestruction: { controller.visibleMessageRows = []; controller.htmlCache = null; }

    focus: true

    Timer {
        interval: 250
        running: workspace.prewarmHtml && workspace.visible && !htmlWarmup.attempted
            && workspace.activeView === "read" && workspace.controller.ui.folder === "Inbox"
            && workspace.controller.rows.some(row => row.hasHtml || row.bodyHtml || row.body_html || row.bodyHtmlFixture)
        onTriggered: {
            htmlWarmup.attempted = true;
            const message = workspace.controller.selected;
            if (!message?.bodyHtml && !message?.body_html && !message?.bodyHtmlFixture)
                htmlWarmup.active = true;
        }
    }

    Loader {
        id: htmlWarmup
        property bool attempted: false
        readonly property bool loaded: !!item?.ready
        active: false
        visible: false
        width: 1

        // Warm the engine with an empty document, then release the view and its profile.
        Component.onCompleted: setSource(Qt.resolvedUrl("MailHtmlView.qml"), {html: ""})
        onLoadedChanged: if (loaded) Qt.callLater(() => { htmlWarmup.active = false; })
        onStatusChanged: if (status === Loader.Error) active = false

        Timer {
            interval: 5000
            running: htmlWarmup.active
            onTriggered: htmlWarmup.active = false
        }
    }

    component Rule: Rectangle {
        height: 1
        color: K.Kit.tokens.hairline
    }
    FileDialog {
        id: files
        title: "Attach files to this local draft"
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (var url of selectedFiles) {
                var path = String(url);
                workspace.controller.act("attach", {
                    url: path,
                    name: decodeURIComponent(path.split("/").pop())
                });
            }
        }
    }
    FileDialog {
        id: saveFile
        property var attachment
        property var pending: []
        function openNext() {
            if (!pending.length)
                return;
            attachment = pending[0];
            pending = pending.slice(1);
            selectedFile = String(currentFolder) + "/" + encodeURIComponent(attachment.name);
            open();
        }
        onRejected: pending = []
        title: "Save attachment"
        fileMode: FileDialog.SaveFile
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        onAccepted: {
            if (attachment.messageId && workspace.controller.mailboxClient) {
                workspace.controller.mailboxClient.saveAttachment(attachment.messageId, attachment.id, selectedFile);
                Qt.callLater(openNext);
                return;
            }
            const source = attachment.url || Qt.resolvedUrl(attachment.path || "");
            if (typeof previewFiles !== "undefined" && previewFiles.copy(source, selectedFile))
                workspace.controller.act("notice", {
                    text: "Saved " + attachment.name
                });
            else
                workspace.controller.act("notice", {
                    text: typeof previewFiles !== "undefined" ? previewFiles.error : "Open the attachment in its default app to save a copy."
                });
            Qt.callLater(openNext);
        }
    }
    Connections {
        target: workspace.controller

        function onSaveRequested(file) {
            const files = file && typeof file.length === "number" ? Array.from(file) : [file];
            saveFile.pending = files.filter(item => item && (item.url || item.path || item.messageId));
            if (saveFile.pending.length)
                saveFile.openNext();
            else
                workspace.controller.act("notice", {text: "No attachment is available to save."});
        }
    }
    Shortcut {
        sequences: [StandardKey.New]
        enabled: workspace.controller.ui.folder !== "Trash"
        onActivated: workspace.controller.act("new")
    }
    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: {
            workspace.compactReading = false;
            search.forceActiveFocus();
        }
    }
    Shortcut {
        sequence: "Ctrl+Return"
        enabled: workspace.controller.canSend
        onActivated: workspace.controller.act("send")
    }
    Shortcut {
        sequence: "Meta+Return"
        enabled: workspace.controller.canSend
        onActivated: workspace.controller.act("send")
    }
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: !["draft", "compose"].includes(workspace.controller.ui.view) && (workspace.controller.undoAvailable || !!workspace.controller.ui.undo || !!workspace.controller.conversationUndoToken)
        onActivated: workspace.controller.undoAvailable ? workspace.controller.act("undoSend") : workspace.controller.act("undo")
    }
    Shortcut {
        sequence: "Ctrl+,"
        onActivated: workspace.controller.act("settings")
    }
    Shortcut {
        sequence: "Meta+,"
        onActivated: workspace.controller.act("settings")
    }
    Shortcut {
        sequence: "Escape"
        enabled: workspace.controller.ui.searching && !searchFilter.menuOpen
        onActivated: {
            if (searchFilter.menuOpen) searchFilter.dismissMenu();
            else { pointerFocus.forceActiveFocus(Qt.ShortcutFocusReason); workspace.controller.act("closeSearch"); }
        }
    }
    Keys.onEscapePressed: workspace.controller.act("escape")

    RowLayout {
        anchors.fill: parent
        spacing: 0
        visible: !workspace.fullPage

        Rectangle {
            visible: workspace.railWidth > 0
            Layout.preferredWidth: workspace.railWidth
            Layout.fillHeight: true
            color: workspace.t.windowGround

            MailMailboxRail {
                anchors.fill: parent
                controller: workspace.controller
            }
        }
        Item {
            id: inbox
            objectName: "inboxPane"
            visible: !workspace.compact || !workspace.compactReading
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.minimumWidth: workspace.compact ? 0 : workspace.listMinimum
            Layout.preferredWidth: workspace.listWidth
            Layout.maximumWidth: workspace.compact ? Infinity : workspace.listWidth
            Rectangle {
                anchors.fill: parent
                color: workspace.t.windowGround
            }
            Rule {
                x: parent.width - 1
                width: 1
                height: parent.height
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: workspace.t.space.m
                spacing: 0
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: workspace.t.space.xxl
                    Layout.rightMargin: workspace.t.space.xxl
                    spacing: workspace.t.space.xs
                    Item {
                        id: searchRow
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: Math.max(search.implicitHeight, newMailAction.implicitHeight, searchFilter.implicitHeight)
                        K.SearchField {
                            id: search
                            objectName: "mailSearch"
                            scope: qsTr("mails")
                            Component.onCompleted: {
                                // This app replaces clear-text with close-search, including its tab stop.
                                const clear = children.find(child => child.symbol === "close" && child.label === "Clear the search");
                                if (clear) { clear.visible = false; clear.enabled = false; }
                                // Reserve the existing trailing action zone even when the field is narrow.
                                const placeholder = children.find(child => child.text === "Search " + scope);
                                if (placeholder) {
                                    placeholder.width = Qt.binding(() => Math.max(0, search.width - placeholder.x
                                        - (closeSearchAction.visible ? closeSearchAction.width + 2 * workspace.t.space.xs : workspace.t.space.m)));
                                    placeholder.elide = Text.ElideRight;
                                }
                            }
                            openness: search.open || workspace.controller.ui.searching ? 1 : 0
                            anchors.left: parent.left
                            readonly property real actionSpace: (newMailAction.visible || searchFilter.visible)
                                ? (searchFilter.visible ? searchFilter.width : newMailAction.width) + 2 * workspace.t.space.m + workspace.t.space.s : 0
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property real availableWidth: Math.max(0, searchRow.width - actionSpace)
                            fieldWidth: availableWidth
                            width: Math.min(implicitWidth, availableWidth)
                            text: workspace.controller.ui.query
                            onTextChanged: if (text !== workspace.controller.ui.query)
                                workspace.controller.act("search", {
                                    text: text
                                })
                            onAccepted: workspace.controller.act("search", {
                                text: text
                            })
                            onDismissed: workspace.controller.act("closeSearch")
                            onDown: mailList.forceActiveFocus()
                        }
                        K.IconButton {
                            id: closeSearchAction
                            objectName: "closeSearch"
                            visible: workspace.controller.ui.searching
                            anchors.right: search.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: search.verticalCenter
                            width: 32; height: 32
                            symbol: "close"
                            size: 18
                            label: qsTr("Close search")
                            onActivated: { pointerFocus.forceActiveFocus(Qt.MouseFocusReason); workspace.controller.act("closeSearch"); }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: closeSearchAction.activated()
                            }
                        }

                        MailMenuButton {
                            id: searchFilter
                            objectName: "searchFilter"
                            visible: workspace.controller.ui.searching
                            anchors.right: parent.right
                            anchors.rightMargin: workspace.t.space.m
                            anchors.verticalCenter: parent.verticalCenter
                            text: workspace.controller.ui.searchFilter === "All mail" ? qsTr("Filter") : workspace.controller.ui.searchFilter
                            items: [{label: qsTr("All"), checked: workspace.controller.ui.searchFilter === "All mail"},
                                {label: qsTr("Unread"), checked: workspace.controller.ui.searchFilter === "Unread"},
                                {label: qsTr("With attachments"), checked: workspace.controller.ui.searchFilter === "With attachments"},
                                {label: qsTr("Starred"), checked: workspace.controller.ui.searchFilter === "Starred"}]
                            onPicked: index => workspace.controller.act("searchFilter", {value: ["All mail", "Unread", "With attachments", "Starred"][index]})
                        }
                        MailAction {
                            id: newMailAction
                            objectName: "newMessage"
                            anchors.right: parent.right
                            anchors.rightMargin: workspace.t.space.m
                            anchors.verticalCenter: parent.verticalCenter
                            height: implicitHeight
                            visible: !workspace.controller.ui.searching && workspace.controller.ui.folder !== "Trash"
                            text: qsTr("New mail")
                            onActivated: { workspace.compactReading = true; workspace.controller.act("new"); }

                        }
                    }
                    RowLayout {
                        Layout.topMargin: workspace.t.space.m - workspace.t.space.xs
                        id: inboxHeaderRow
                        Layout.fillWidth: true
                        spacing: workspace.t.space.xxl
                        Item {
                            id: folderTitle
                            Layout.preferredWidth: folderTitleContent.implicitWidth
                            Layout.preferredHeight: referenceHeadline.implicitHeight
                            MailAction {
                                objectName: "folderMenu"
                                visible: !workspace.controller.ui.searching
                                anchors.fill: parent
                                text: ""
                                Accessible.name: workspace.controller.ui.folder + " mailboxes"
                                onActivated: workspace.showMailboxes()
                            }
                            MailHeadline {
                                id: referenceHeadline
                                visible: false
                                text: folderTitleText.text
                            }
                            RowLayout {
                                id: folderTitleContent
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: workspace.t.space.xs
                                K.TacitText {
                                    id: folderTitleText
                                    text: workspace.controller.ui.searching ? qsTr("Search results") : workspace.controller.ui.folder
                                    size: "section"
                                    weight: "strong"
                                    cut: "display"
                                }
                                K.Symbol {
                                    visible: !workspace.controller.ui.searching
                                    text: workspace.controller.ui.rail ? "expand_less" : "expand_more"
                                    size: workspace.t.icon.row
                                    color: workspace.t.inkSec
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }

                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: workspace.t.space.m
                        K.TacitText {
                            id: mailboxCaption
                            objectName: "mailboxCaption"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.alignment: Qt.AlignBaseline
                            size: "meta"
                            ink: "quiet"
                            wrapMode: Text.NoWrap
                            elide: Text.ElideLeft
                            text: {
                                const controller = workspace.controller;
                                if (controller.ui.searching && (workspace.listLoading || controller.loadingOlderMail))
                                    return qsTr("Searching… · All accounts, all folders");
                                if (controller.ui.searching && workspace.listError)
                                    return qsTr("All accounts, all folders");
                                if (controller.ui.searching)
                                    return (controller.rows.length === 1 ? qsTr("%L1 result · All accounts, all folders")
                                        : qsTr("%L1 results · All accounts, all folders")).arg(controller.rows.length);
                                const {folder, account} = controller.ui;
                                const label = controller.accounts.find(entry => entry.id === account)?.name ?? account;
                                if (!controller.rows.length && workspace.listLoading)
                                    return qsTr("Opening %1… · %2").arg(folder).arg(label);
                                if (!controller.rows.length && (workspace.listError || workspace.listImportInterrupted))
                                    return label;
                                if (!workspace.listCountsKnown && controller.count(folder, account, false) === 0)
                                    return label;
                                if (folder === "Inbox")
                                    return qsTr("%L1 unread · %L2 total")
                                        .arg(controller.count(folder, account))
                                        .arg(controller.count(folder, account, false));
                                return qsTr("%L1 total").arg(controller.count(folder, account, false));
                            }
                        }

                    }

                }
                RowLayout {
                    id: gmailCategoryBar
                    Layout.topMargin: workspace.t.space.l
                    objectName: "gmailCategoryBar"
                    Accessible.role: Accessible.ToolBar
                    Accessible.name: qsTr("Gmail categories")
                    visible: workspace.controller.hasGmailCategories && workspace.controller.ui.folder === "Inbox" && !workspace.controller.ui.searching
                    Layout.fillWidth: true
                    Layout.leftMargin: workspace.t.space.l + workspace.t.space.xs
                    Layout.rightMargin: workspace.t.space.l
                    spacing: workspace.t.space.xs
                    readonly property var categories: ["CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES"]
                    Flickable {
                        id: gmailCategoryViewport
                        objectName: "gmailCategoryViewport"
                        Layout.fillWidth: true
                        Layout.preferredHeight: gmailTabs.implicitHeight
                        contentWidth: gmailTabs.implicitWidth
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        function revealCurrent() {
                            const tab = gmailTabs.children.find(child => child.index === gmailTabs.current);
                            if (!tab) return;
                            const target = Math.max(tab.x + tab.width - width, Math.min(contentX, tab.x));
                            contentX = Math.max(0, Math.min(contentWidth - width, target));
                        }
                        onWidthChanged: Qt.callLater(revealCurrent)
                        K.Tabs {
                            id: gmailTabs
                            objectName: "gmailCategoryTabs"
                            labels: [qsTr("Primary"), qsTr("Promotions"), qsTr("Social"), qsTr("Updates")]
                            label: qsTr("Gmail categories")
                            current: gmailCategoryBar.categories.indexOf(workspace.controller.activeGmailCategory)
                            onCurrentChanged: gmailCategoryViewport.revealCurrent()
                            onPicked: index => workspace.controller.act("gmailCategory", {value: gmailCategoryBar.categories[index]})
                        }
                    }

                }
                Rule {
                    objectName: "mailListHairline"
                    Layout.fillWidth: true
                    Layout.leftMargin: workspace.t.space.xxl
                    Layout.rightMargin: workspace.t.space.xxl
                    Layout.topMargin: gmailCategoryBar.visible ? 0 : workspace.t.space.l
                    color: Qt.alpha(workspace.t.inkMain, workspace.t.wash.hover + 0.02)
                }
                K.PageState {
                    id: listState
                    objectName: "mailListState"
                    visible: !workspace.listLoading && (!!workspace.listError || workspace.listImportInterrupted
                        || (!workspace.controller.rows.length && !workspace.controller.loadingOlderMail))
                    Layout.fillWidth: true
                    Layout.leftMargin: workspace.t.space.xxl
                    Layout.rightMargin: workspace.t.space.xxl
                    Layout.topMargin: workspace.t.space.l
                    Layout.bottomMargin: workspace.t.space.l
                    maxWidth: Math.max(0, inbox.width - 2 * workspace.t.space.xxl
                        - (failure ? workspace.t.icon.row + workspace.t.space.m : 0))
                    failure: !!workspace.listError || workspace.listImportInterrupted
                    text: workspace.listError || (workspace.listImportInterrupted
                        ? qsTr("Mail import was interrupted. Tacit will try again.")
                        : workspace.controller.ui.searching ? qsTr("No messages match your search.")
                        : workspace.listCategoryName && (!workspace.listCountsKnown
                            || workspace.controller.count("Inbox", workspace.controller.ui.account, false) > 0)
                            ? qsTr("No messages in %1.").arg(workspace.listCategoryName)
                        : workspace.controller.ui.folder === "Inbox" ? qsTr("Your Inbox is empty.")
                        : qsTr("No messages in %1.").arg(workspace.controller.ui.folder))
                    action: workspace.listError ? qsTr("Try again")
                        : workspace.controller.ui.searching && !workspace.listImportInterrupted ? qsTr("Clear search") : ""
                    onActivated: {
                        if (workspace.listError) {
                            if (workspace.controller.ui.searching) workspace.controller.searchQuery.refresh();
                            else workspace.controller.folderQuery.refresh();
                        } else if (workspace.controller.ui.searching) workspace.controller.act("closeSearch");
                    }
                }
                K.RowList {
                    id: mailList
                    objectName: "messageList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    Layout.leftMargin: workspace.t.space.m
                    Layout.rightMargin: workspace.t.space.m
                    view.anchors.topMargin: 0
                    view.anchors.bottomMargin: 0
                    view.bottomMargin: ringSpace + workspace.t.space.m
                    label: "Messages in " + workspace.controller.ui.folder
                    property var departing: []
                    property bool resettingScope: false
                    property bool restoringSelection: false
                    property bool revealAfterSearch: false
                    property var mailboxData: ({})
                    property var searchData: ({})
                    readonly property var displayedData: workspace.controller.ui.searching ? searchData : mailboxData
                    property string mailboxScope: ""
                    property string searchScope: ""
                    property var mailboxSource: null
                    property var searchSource: null
                    property string displayedScope: ""
                    property bool displayedSearch: false
                    readonly property string scope: JSON.stringify([
                        workspace.controller.ui.folder, workspace.controller.ui.account,
                        workspace.controller.ui.searching,
                        workspace.controller.ui.filter, workspace.controller.ui.sort,
                        workspace.controller.ui.searching ? workspace.controller.ui.searchFilter : ""
                    ])
                    readonly property var sourceRows: workspace.controller.rows
                    onSourceRowsChanged: Qt.callLater(syncRows)
                    onScopeChanged: Qt.callLater(syncRows)
                    Component.onCompleted: syncRows()
                    Connections {
                        target: mailList.view
                        function onContentYChanged() { viewportPrefetch.restart(); }
                        function onHeightChanged() { viewportPrefetch.restart(); }
                        function onCountChanged() { viewportPrefetch.restart(); }
                    }
                    onVisibleChanged: viewportPrefetch.restart()
                    onDisplayedDataChanged: viewportPrefetch.restart()
                    Timer {
                        id: viewportPrefetch
                        interval: 80
                        onTriggered: mailList.updateVisibleRows()
                    }
                    function updateVisibleRows() {
                        const rows = [];
                        if (visible) {
                            for (const item of view.contentItem.children) {
                                if (!item.messageId || !item.visible) continue;
                                const y = item.mapToItem(view, 0, 0).y;
                                if (y < view.height && y + item.height > 0) {
                                    const row = displayedData[item.messageId];
                                    if (row) rows.push(row);
                                }
                            }
                        }
                        workspace.controller.visibleMessageRows = rows;
                    }
                    model: resettingScope ? null : displayedRows
                    readonly property var displayedRows: workspace.controller.ui.searching ? searchRowsModel : mailboxRowsModel
                    ListModel { id: mailboxRowsModel }
                    ListModel { id: searchRowsModel }

                    function restoreSelection() {
                        revealAfterSearch = !workspace.controller.ui.searching && workspace.controller.folderQuery.loading;
                        restoringSelection = true;
                        resettingScope = false;
                        view.forceLayout();
                        const selected = workspace.controller.selectedRow;
                        let index = -1;
                        for (let i = 0; i < displayedRows.count; ++i) {
                            const row = displayedData[displayedRows.get(i).messageId];
                            if (row && (row.id === selected?.id || (selected?.backendConversation
                                && row.backendConversation === selected.backendConversation
                                && row.backendAccount === selected.backendAccount))) { index = i; break; }
                        }
                        if (index >= 0) { cursor = index; view.positionViewAtIndex(index, ListView.Contain); }
                        else view.positionViewAtBeginning();
                        Qt.callLater(() => {
                            if (index >= 0 && index < displayedRows.count) {
                                view.forceLayout();
                                view.positionViewAtIndex(index, ListView.Contain);
                            }
                            restoringSelection = false;
                        });
                    }

                    function syncRows() {
                        const switching = displayedScope !== scope;
                        const searchSwitch = displayedSearch !== workspace.controller.ui.searching;
                        displayedSearch = workspace.controller.ui.searching;
                        if (searchSwitch) revealAfterSearch = !displayedSearch;
                        const searching = workspace.controller.ui.searching;
                        const modelScope = searching ? searchScope : mailboxScope;
                        const cachedSource = searching ? searchSource : mailboxSource;
                        if (switching) resettingScope = true;
                        displayedScope = scope;
                        if (modelScope === scope && cachedSource === sourceRows) {
                            if ((switching && searchSwitch) || revealAfterSearch) Qt.callLater(restoreSelection);
                            else resettingScope = false;
                            return;
                        }
                        const previousIds = new Set();
                        for (let i = 0; i < displayedRows.count; ++i)
                            previousIds.add(displayedRows.get(i).messageId);
                        const incomingCount = sourceRows.filter(row => !previousIds.has(row.id)).length;
                        // Shared-record updates must not rebuild an unchanged membership list.
                        if (modelScope === scope && displayedRows.count === sourceRows.length
                                && sourceRows.every((row, index) => displayedRows.get(index).messageId === row.id)) {
                            departure.stop();
                            departing = [];
                            applyRows();
                            resettingScope = switching && searchSwitch;
                            if ((switching && searchSwitch) || revealAfterSearch) Qt.callLater(restoreSelection);
                            else resettingScope = false;
                            return;
                        }
                        if (modelScope !== scope || workspace.controller.ui.searching
                                || workspace.controller.inboxSyncsPending > 0 || incomingCount > 1) {
                            const scopeChanged = modelScope !== scope;
                            const offset = view.contentY - view.originY;
                            displayedScope = scope;
                            departure.stop();
                            departing = [];
                            resettingScope = true;
                            view.cancelFlick();
                            displayedRows.clear();
                            applyRows();
                            resettingScope = switching && searchSwitch;
                            view.forceLayout();
                            if (scopeChanged)
                                view.positionViewAtBeginning();
                            else
                                view.contentY = view.originY + Math.min(offset,
                                    Math.max(-view.topMargin, view.contentHeight - view.height + view.bottomMargin));
                            if ((switching && searchSwitch) || revealAfterSearch) Qt.callLater(restoreSelection);
                            else resettingScope = false;
                            return;
                        }
                        const ids = new Set(sourceRows.map(row => row.id));
                        const removed = [];
                        for (let i = 0; i < displayedRows.count; ++i) {
                            const id = displayedRows.get(i).messageId;
                            if (!ids.has(id))
                                removed.push(id);
                        }
                        if (removed.length && departure.interval > 0) {
                            if (JSON.stringify(removed) !== JSON.stringify(departing)) {
                                departing = removed;
                                departure.restart();
                            }
                        } else {
                            departure.stop();
                            departing = [];
                            applyRows();
                        }
                        if ((switching && searchSwitch) || revealAfterSearch) Qt.callLater(restoreSelection);
                            else resettingScope = false;
                    }

                    function applyRows() {
                        const ids = new Set(sourceRows.map(row => row.id));
                        for (let i = displayedRows.count - 1; i >= 0; --i) {
                            if (!ids.has(displayedRows.get(i).messageId))
                                displayedRows.remove(i);
                        }
                        const data = Object.create(null);
                        sourceRows.forEach(row => { data[row.id] = row; });
                        if (workspace.controller.ui.searching) { searchData = data; searchScope = scope; searchSource = sourceRows; }
                        else { mailboxData = data; mailboxScope = scope; mailboxSource = sourceRows; }
                        sourceRows.forEach((row, index) => {
                            const item = {messageId: row.id};
                            let previous = index;
                            while (previous < displayedRows.count && displayedRows.get(previous).messageId !== row.id)
                                ++previous;
                            if (previous === displayedRows.count)
                                displayedRows.insert(index, item);
                            else {
                                if (previous !== index)
                                    displayedRows.move(previous, index, 1);
                            }
                        });
                    }

                    Timer {
                        id: departure
                        interval: K.Kit.ms(workspace.t.motion.fadeFast.ms)
                        onTriggered: {
                            const view = mailList.view;
                            const offset = view.contentY - view.originY;
                            mailList.applyRows();
                            view.forceLayout();
                            const top = -view.topMargin;
                            const bottom = Math.max(top, view.contentHeight - view.height + view.bottomMargin);
                            view.contentY = view.originY + Math.max(top, Math.min(offset, bottom));
                            mailList.departing = [];
                        }
                    }
                    view.footer: Column {
                        id: olderMailFooter
                        objectName: "olderMailFooter"
                        readonly property var progress: workspace.controller.olderImportProgress
                        visible: workspace.controller.ui.searching && workspace.controller.loadingOlderMail
                        width: mailList.view.width
                        height: visible ? implicitHeight : 0
                        spacing: workspace.t.space.s

                        K.TacitText {
                            width: parent.width
                            wrapMode: Text.Wrap
                            ink: "sec"
                            text: workspace.controller.olderImportWaitingForProvider
                                ? qsTr("Waiting for your mail provider. Older search results may still be missing.")
                                : olderMailFooter.progress.interrupted
                                ? qsTr("Loading older mail was interrupted. Older search results may be missing.")
                                : qsTr("Older search results may still be missing while older mail loads.")
                        }
                        K.TacitText {
                            width: parent.width
                            ink: "sec"
                            visible: !olderMailFooter.progress.waiting
                            text: qsTr("%L1 of %L2 older messages saved.")
                                .arg(olderMailFooter.progress.saved).arg(olderMailFooter.progress.total)
                        }
                        K.Progress {
                            width: parent.width
                            label: qsTr("Loading older mail")
                            going: olderMailFooter.progress.waiting && !olderMailFooter.progress.interrupted
                            value: olderMailFooter.progress.total > 0 ? olderMailFooter.progress.saved / olderMailFooter.progress.total : 0
                        }
                    }
                    view.add: Transition {
                        enabled: !mailList.resettingScope && !workspace.controller.ui.searching
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: K.Kit.ms(workspace.t.motion.fade.ms)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: workspace.t.motion.fade.curve
                        }
                    }
                    view.displaced: Transition {
                        enabled: !mailList.resettingScope && !workspace.controller.ui.searching
                        NumberAnimation {
                            properties: "x,y"
                            duration: K.Kit.ms(K.Kit.motion("arrive").ms)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: K.Kit.motion("arrive").curve
                        }
                    }
                    onActivated: i => {
                        const id = displayedRows.get(i)?.messageId;
                        if (id && !departing.includes(id))
                            workspace.openMessage(id);
                    }
                    onCursorChanged: {
                        if (!resettingScope && !restoringSelection && displayedScope === scope && cursor >= 0 && cursor < displayedRows.count) {
                            const id = displayedRows.get(cursor).messageId;
                            if (!departing.includes(id))
                                Qt.callLater(() => {
                                    if (!resettingScope && !restoringSelection && displayedScope === scope && displayedRows.get(cursor)?.messageId === id)
                                        workspace.openMessage(id);
                                });
                        }
                    }
                    delegate: Column {
                        id: messageRow
                        required property int index
                        required property string messageId
                        width: mailList.rowWidth
                        height: implicitHeight
                        MailMessagePreview {
                            id: preview
                            property var lastRow
                            readonly property var liveRow: mailList.displayedData[messageRow.messageId]
                                ?? mailList.mailboxData[messageRow.messageId] ?? mailList.searchData[messageRow.messageId]
                            onLiveRowChanged: if (liveRow) lastRow = liveRow
                            modelData: liveRow ?? lastRow
                            opacity: mailList.departing.includes(messageRow.messageId) ? 0 : 1
                            enabled: opacity === 1
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: departure.interval
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: workspace.t.motion.fadeFast.curve
                                }
                            }

                            controller: workspace.controller
                            width: mailList.rowWidth
                            ring: mailList.ringAt(messageRow.index)
                            onRowClicked: modifiers => mailList.clickAt(messageRow.index, modifiers)
                            onMessageRequested: messageId => workspace.openMessage(messageId)
                            onContextRequestedForMessage: (messageId, position) => {
                                workspace.controller.act("select", {
                                    id: messageId
                                });
                                messageMenu.openAt(preview, position.x, position.y);
                            }
                        }
                    }
                }
            }

        }
        Item {
            id: reading
            readonly property real statusTop: workspace.t.height.header + workspace.t.space.xxl
            objectName: "readerPane"
            visible: !workspace.compact || workspace.compactReading
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: workspace.compact ? 0 : workspace.readerMinimum
            Layout.preferredWidth: workspace.t.width.list
            MailReader {
                id: reader
                visible: !workspace.showingMailLoading && (!!workspace.controller.selected || ["draft", "compose"].includes(workspace.controller.ui.view))
                anchors.fill: parent
                controller: workspace.controller
                compact: workspace.compact
                enabled: !readerSnapshot.visible
                onBackRequested: workspace.compactReading = false
                attachmentDialogOpen: files.visible
                onAttachRequested: files.open()
            }
            Image {
                id: readerSnapshot
                anchors.fill: reader
                visible: source.toString() !== ""
                property var capture: null
                function clear() {
                    crossfade.stop();
                    opacity = 1;
                    source = "";
                    capture = null;
                }
                onStatusChanged: {
                    if (status === Image.Error)
                        clear();
                    else if (status === Image.Ready)
                        Qt.callLater(reveal);
                }
                function reveal() {
                    if (status !== Image.Ready || crossfade.running)
                        return;
                    crossfade.start();
                }
                ParallelAnimation {
                    id: crossfade
                    NumberAnimation {
                        target: readerSnapshot
                        property: "opacity"
                        to: 0
                        duration: K.Kit.ms(workspace.t.motion.fadeFast.ms)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: workspace.t.motion.fadeFast.curve
                    }
                    onFinished: readerSnapshot.clear()
                }
            }
            Column {
                visible: workspace.showingMailLoading
                x: reader.textX
                y: reading.statusTop
                width: reader.textWidth
                spacing: workspace.t.space.xl
                MailHeadline {
                    width: parent.width
                    text: qsTr("Getting your mail")
                }
                K.TacitText {
                    text: qsTr("%1 of %2 messages imported from Personal.")
                          .arg(workspace.controller.ui.imported.toLocaleString(Qt.locale(), "f", 0))
                          .arg((8600).toLocaleString(Qt.locale(), "f", 0))
                    ink: "sec"
                    width: parent.width
                    wrapMode: Text.Wrap
                }
                K.Progress {
                    width: parent.width
                    value: workspace.controller.ui.imported / 8600
                    label: qsTr("Importing mail")
                }
            }
            K.PageState {
                visible: !reader.visible && !workspace.showingMailLoading
                    && !(workspace.controller.selectedRow && workspace.controller.threadQuery.loading)
                x: reader.textX
                y: reading.statusTop
                maxWidth: reader.textWidth
                text: qsTr("Choose a message to read.")
                action: workspace.compact ? qsTr("Back to %1").arg(workspace.controller.ui.folder) : ""
                onActivated: workspace.compactReading = false
            }
        }
    }
    MailSettings {
        visible: !workspace.waitingForStartupAccounts && workspace.controller.ui.view === "settings" && !workspace.removingLocalMail
        anchors.fill: parent
        controller: workspace.controller
    }
    MailAccountSetup {
        anchors.fill: parent
        visible: !workspace.waitingForStartupAccounts && workspace.controller.ui.view === "setup"
            && (!workspace.firstImport || workspace.managingImport) && !workspace.removingLocalMail
        controller: workspace.controller
    }
    K.PageState {
        objectName: "startupAccountError"
        anchors.centerIn: parent
        visible: workspace.waitingForStartupAccounts && !workspace.controller.loadingAccounts
        maxWidth: Math.max(0, Math.min(workspace.t.width.panel, workspace.width - 2 * workspace.t.space.xl))
        failure: true
        text: qsTr("Could not check your mail accounts.")
        action: qsTr("Try again")
        onActivated: workspace.controller.requestAccounts()
    }
    Column {
        id: mailProgress
        visible: (workspace.firstImport && !workspace.managingImport) || workspace.removingLocalMail
        objectName: "firstMailImport"
        anchors.centerIn: parent
        width: Math.max(0, Math.min(workspace.t.width.panel, parent.width - 2 * workspace.t.space.xl))
        spacing: workspace.t.space.l
        readonly property int completed: workspace.removingLocalMail
            ? workspace.controller.removalCompleted : workspace.controller.displayedImportDownloaded
        readonly property int total: workspace.removingLocalMail
            ? workspace.controller.removalTotal : workspace.controller.importTotal
        MailHeadline {
            width: parent.width
            text: workspace.removingLocalMail ? qsTr("Removing local mail") : qsTr("Getting your mail")
        }
        K.TacitText {
            width: parent.width
            wrapMode: Text.Wrap
            ink: "sec"
            id: importDetail
            objectName: "mailProgressDetail"
            height: workspace.removingLocalMail ? implicitHeight : Math.max(implicitHeight, 2 * importDetailMetrics.height)
            FontMetrics {
                id: importDetailMetrics
                font: importDetail.font
            }
            text: workspace.removingLocalMail
                ? (mailProgress.total < 0 ? qsTr("Preparing to remove local mail…")
                    : mailProgress.completed >= mailProgress.total ? qsTr("Finishing up…")
                    : qsTr("%L1 of %L2 messages removed.").arg(mailProgress.completed).arg(mailProgress.total))
                : workspace.controller.firstImportInterrupted
                    ? (workspace.controller.syncStatusByAccount[workspace.controller.firstImportAccount]?.googleSignInAgain
                        ? qsTr("Sign in to Google again to continue importing mail.")
                        : qsTr("Mail import paused. Tacit will retry automatically."))
                : workspace.controller.waitingForImportedInbox ? qsTr("Opening your inbox…")
                : mailProgress.total < 0 ? workspace.controller.importPreparationText
                : workspace.controller.importPreparation === 10
                    ? qsTr("%L1 of %L2 messages downloaded. Checking for mailbox changes…")
                        .arg(mailProgress.completed).arg(mailProgress.total)
                : workspace.controller.importPreparation === 11 && workspace.controller.importBatchWaitSeconds > 0
                    ? qsTr("%L1 of %L2 messages downloaded. Waiting for the next batch · %L3 s")
                        .arg(mailProgress.completed).arg(mailProgress.total).arg(workspace.controller.importBatchWaitSeconds)
                : mailProgress.completed === mailProgress.total ? qsTr("Saving your mail…")
                : qsTr("%L1 of %L2 messages downloaded.")
                    .arg(mailProgress.completed).arg(mailProgress.total)
        }
        K.Progress {
            width: parent.width
            visible: !workspace.removingLocalMail && !workspace.controller.waitingForImportedInbox
                && !workspace.controller.firstImportInterrupted && workspace.controller.importPreparation !== 3
                && (mailProgress.total < 0 || mailProgress.completed < mailProgress.total
                    || workspace.controller.importPreparation === 10)
            label: qsTr("Importing mail")
            going: mailProgress.total < 0 || workspace.controller.importPreparation === 10
            value: mailProgress.total > 0 ? mailProgress.completed / mailProgress.total : 0
        }
        Item {
            width: parent.width
            implicitHeight: retrySettings.implicitHeight
            visible: !workspace.removingLocalMail
            Row {
                id: providerWait
                objectName: "waitingForMailProvider"
                visible: !workspace.controller.firstImportInterrupted
                    && !workspace.controller.waitingForImportedInbox
                    && !!workspace.controller.waitingForMailProvider[workspace.controller.firstImportAccount]
                spacing: workspace.t.space.s
                K.TacitText {
                    anchors.verticalCenter: parent.verticalCenter
                    ink: "sec"
                    text: qsTr("Waiting for your mail provider…")
                }
                K.Progress {
                    anchors.verticalCenter: parent.verticalCenter
                    width: workspace.t.space.xl
                    label: qsTr("Waiting for your mail provider")
                    going: providerWait.visible
                }
            }
            MailAction {
                id: retrySettings
                visible: workspace.firstImport && workspace.controller.firstImportInterrupted
                text: qsTr("Account settings")
                onActivated: workspace.controller.act("settings")
            }
        }
    }
    MailMenu {
        id: folderPicker
        items: ["Inbox", "Starred", "Drafts", "Sent", "Archive", "Spam", "Trash"].map(v => ({
                    label: v,
                    folder: v
                })).concat([
            {
                rule: true
            }
        ], workspace.controller.accounts.map(a => ({
                    label: a.name + " · " + a.email,
                    folder: "Inbox",
                    account: a.name
                })), [
            {
                rule: true
            },
            {
                label: "Add account",
                action: "setup"
            },
            {
                label: "Settings",
                action: "settings"
            }
        ])
        onPicked: i => {
            const entry = items[i];
            if (entry.action)
                workspace.controller.act(entry.action);
            else
                workspace.controller.act("folder", {
                    folder: entry.folder,
                    account: entry.account
                });
            workspace.compactReading = false;
        }
    }
    MailMenu {
        id: messageMenu
        readonly property bool inTrash: workspace.controller.selected?.folder === "Trash"
        items: inTrash ? [
            {label: qsTr("Restore thread")}
        ] : [
            {
                label: "Reply"
            },
            {
                label: "Reply all"
            },
            {
                label: "Forward"
            },
            {
                label: "Mark unread"
            },
            {
                label: "Star"
            },
            {
                label: "Archive"
            },
            {
                label: qsTr("Move to Spam"),
                available: workspace.controller.selected?.folder === "Inbox"
            },
            {
                label: "Move to Trash",
                risk: true
            }
        ].map((item, index) => Object.assign({originalIndex: index}, item)).filter(item => item.available !== false)
        onPicked: index => {
            const i = inTrash ? index : items[index].originalIndex;
            if (inTrash) {
                if (i === 0)
                    workspace.controller.act("restoreTrash");
                return;
            }
            if (i < 3)
                workspace.controller.reply(items[i].label, false);
            else if (i === 3)
                workspace.controller.act("unread", {
                    value: true
                });
            else if (i === 4)
                workspace.controller.act("star");
            else
                workspace.controller.act("move", {
                    folder: i === 5 ? "Archive" : i === 6 ? "Spam" : "Trash"
                });
        }
    }
    K.Notice {
        id: notice
        objectName: "mailNotice"
        onActivated: workspace.controller.act("undo")
        onClosed: if (workspace.controller.ui.notice === text)
            workspace.controller.act("clearNotice")
    }
    Connections {
        target: workspace.controller

        function onDataChanged() {
            if (workspace.controller.ui.notice && workspace.controller.ui.notice !== notice.text)
                notice.show(workspace.controller.ui.notice, (workspace.controller.ui.undo || workspace.controller.undoAvailable || workspace.controller.conversationUndoToken) ? "Undo" : "");
        }
    }
}
