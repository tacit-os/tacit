import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store
import "fixtures/mailbox-responses.js" as Queries

Item {
    width:1720;height:972
    Mail.MailWorkspaceSession {id:state; reduceAction: Fixture.reduce; queryRows: Fixture.results}
    Mail.MailWorkspace {id:workspace;anchors.fill:parent;controller:state}
    Component {
        id: kitMenuButton
        Mail.MailMenuButton { text: "Choose"; items: [{label: "First"}] }
    }
    Component {
        id: formatMenuButton
        Mail.MailFormatMenu { text: "Choose"; formats: [{label: "First"}] }
    }
    QtObject {
        id: remoteImageClient
        property int requests: 0
        readonly property string source: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        signal messageImagesAllowed(string messageId, bool ok)
        signal imagePoliciesChanged()

    }
    Component {
        id: htmlBackgroundView
        Mail.MailHtmlView { width: 600; html: "" }
    }
    Component { id: imageCacheComponent; Mail.MailHtmlCache {} }
    Component { id: imageOwnerComponent; Item { width: 600; height: 800 } }
    TestCase {
        name:"MailFrontend"
        when:windowShown
        function init(){
            K.Kit.reducedMotion = true;
            state.htmlCache.invalidate();
            state.messageExpansion = {};
            state.threadScrollPositions = new Map();
            state.approvedRemoteImages = ({});
            state.data = Fixture.initial("read");
            wait(30);
        }
        function keyClicks(text){for(var i=0;i<text.length;i++)keyClick(text[i]);}
        function button(name){var found=findChild(workspace,name);verify(found!==null,"Missing "+name);return found;}
        function click(name){
            const b = button(name);
            const scroll = button("readingScroll");
            for (let parent = b.parent; parent; parent = parent.parent) {
                if (parent !== scroll.contentItem)
                    continue;
                const center = b.mapToItem(scroll, b.width / 2, b.height / 2);
                if (center.y < 0 || center.y >= scroll.height) {
                    const top = b.mapToItem(scroll.contentItem, 0, 0).y;
                    scroll.contentY = Math.max(0, Math.min(top, scroll.contentHeight - scroll.height));
                }
                break;
            }
            mouseClick(b,b.width/2,b.height/2);
            wait(30);
        }
        function test_listShowsAccountOnlyWithMultipleSignedInAccounts() {
            const list = button("messageList");
            const message = state.rows[0];
            const account = {name: message.account, email: "first@example.test", provider: "managed-imap"};
            const second = {name: "Second account", email: "second@example.test", provider: "managed-imap"};
            const row = list.view.itemAtIndex(0);
            verify(row !== null);
            const metadata = findChild(row, "messageListMetadata");
            verify(metadata !== null);
            const withoutAccount = [message.time].filter(Boolean).join("  ·  ");
            const withAccount = [message.account, message.time].filter(Boolean).join("  ·  ");

            state.data = Object.assign({}, state.data, {accounts: [account]});
            tryCompare(metadata, "text", withoutAccount);
            state.data = Object.assign({}, state.data, {accounts: [account, second]});
            tryCompare(metadata, "text", withAccount);
            state.data = Object.assign({}, state.data, {
                accounts: [account, Object.assign({}, second, {provider: "offline-imap"})]
            });
            tryCompare(metadata, "text", withoutAccount);
        }
        function test_messageImportanceAndStarSymbols_data() {
            return [
                {tag: "provider important", flags: {important: true}, important: true},
                {tag: "gmail important", flags: {gmail_labels: ["IMPORTANT"]}, important: true},
                {tag: "high importance", flags: {importance: "High"}, important: true},
                {tag: "star only", flags: {flagged: true}, important: false},
                {tag: "both symbols", flags: {important: true, flagged: true}, important: true},
                {tag: "normal importance", flags: {importance: "normal"}, important: false},
                {tag: "legacy without importance", flags: {}, important: false}
            ];
        }

        function test_messageImportanceAndStarSymbols(row) {
            const entry = Object.assign({id: "importance-test", account_id: "work",
                conversation_id: "importance-thread", mailbox: "Inbox",
                from: {email: "sender@example.test"}, subject: "A message",
                date: "2026-11-18T12:00:00Z", unread: true}, row.flags);
            state.data = Queries.fromMailbox(Fixture.initial("read"), [entry]);
            const list = button("messageList");
            tryVerify(() => {
                const item = list.view.itemAtIndex(0);
                return item !== null && findChild(item, "messageListSubject")?.text === entry.subject;
            });
            const subject = findChild(list.view.itemAtIndex(0), "messageListSubject");
            verify(subject !== null);
            const item = list.view.itemAtIndex(0);
            compare(findChild(item, "messageImportant").visible, row.important);
            compare(findChild(item, "messageStarred").visible, row.flags.flagged === true);
            verify(subject.ink !== "accent");
            state.act("select", {id: entry.id});
            verify(subject.ink !== "accent");
            compare(findChild(item, "messageImportant").visible, row.important);
            compare(findChild(item, "messageStarred").visible, row.flags.flagged === true);
        }

        function test_selectMessage() {
            const list = button("messageList");
            const selectedId = state.rows[1].id;
            const row = list.view.itemAtIndex(1);
            verify(row !== null);
            mouseClick(row, row.width / 2, row.height / 2);
            compare(state.ui.selected, selectedId);
            compare(state.selected.unread, false);
        }
        function test_replyKeepsDraft(){click("replyAll");compare(state.ui.view,"draft");verify(state.draft.showCc);verify(button("archive").visible);verify(!findChild(workspace,"keepDraft"));state.act("select",{id:"studio"});state.act("select",{id:"mara"});compare(state.ui.view,"draft");}
        function test_newMessageTyping(){click("newMessage");compare(state.ui.view,"compose");var to=button("draftTo");to.input.forceActiveFocus();keyClicks("anna.richter@example.net");compare(state.draft.to,"anna.richter@example.net");var body=button("draftBody");body.input.forceActiveFocus();keyClicks("A local message");compare(state.draft.body,"A local message");verify(state.canSend);click("sendDraft");compare(state.data.jobs.length,1);state.act("undoSend");compare(state.ui.view,"compose");compare(state.draft.body,"A local message");}
        function test_recipientSuggestionKeyboard(){
            click("newMessage");
            button("draftTo").input.forceActiveFocus();
            keyClicks("anna");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(state.draft.to, "a.richter@moss.example");
        }
        function test_archiveAndUndo(){click("archive");compare(Store.find(state.data,"mara").folder,"Archive");state.act("undo");compare(Store.find(state.data,"mara").folder,"Inbox");}
        function test_clickOutsideSearchReleasesFocus() {
            const search = button("mailSearch");
            search.forceActiveFocus();
            keyClicks("palettes");
            verify(search.activeFocus);
            mouseClick(workspace, 5, 5);
            tryCompare(search, "activeFocus", false);
            compare(state.ui.query, "palettes");
        }
        function test_closeSearchReleasesFocus() {
            const search = button("mailSearch");
            search.forceActiveFocus();
            keyClicks("palettes");
            verify(search.activeFocus);
            click("closeSearch");
            compare(state.ui.searching, false);
            compare(search.activeFocus, false);
        }
        function test_closeSearchKeyboardKeepsSelection() {
            const selectedId = state.ui.selected;
            state.act("search", {text: "palettes"});
            const search = button("mailSearch");
            const oldClear = search.children.find(child => child.label === "Clear the search");
            verify(!!oldClear); verify(!oldClear.enabled); verify(!oldClear.visible);
            button("closeSearch").forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(state.ui.searching, false);
            compare(state.ui.selected, selectedId);
        }
        function test_escapeClosesFilterBeforeSearch() {
            state.act("search", {text: "palettes"});
            click("searchFilter"); wait(50);
            verify(button("searchFilter").menuOpen);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !button("searchFilter").menuOpen);
            verify(state.ui.searching);
            keyClick(Qt.Key_Escape); wait(30);
            verify(!state.ui.searching);
        }
        function test_search(){var search=button("mailSearch");search.forceActiveFocus();keyClicks("palettes");compare(state.ui.query,"palettes");compare(state.rows.length,3);}
        function test_keyboardSelection() {
            const list = button("messageList");
            const first = state.rows[0].id;
            const second = state.rows[1].id;
            list.cursor = -1;
            list.forceActiveFocus();
            keyClick(Qt.Key_Down);
            wait(30);
            compare(state.ui.selected, first);
            keyClick(Qt.Key_Down);
            wait(30);
            compare(state.ui.selected, second);
        }
        function test_collapsedPreviewStaysNearSender(){
            var header=button("history-lena-first"), preview=button("collapsedPreview-lena-first");
            var position=preview.mapToItem(header,0,0);
            verify(preview.text.length>0);
            compare(preview.horizontalAlignment,Qt.AlignLeft);
            verify(position.x < header.width / 3,"Preview should start in the left third of the wide header");
        }
        function test_discardKeepsExpandedMessages() {
            const body = button("historyBody-lena-first");
            if (!body.expanded) {
                button("history-lena-first").forceActiveFocus();
                keyClick(Qt.Key_Space);
            }
            compare(body.expanded, true);
            state.reply("Reply", false);
            button("discardDraft").activated();
            tryCompare(state.ui, "view", "read");
            tryVerify(() => !findChild(workspace, "mailEditor")?.visible);
            tryCompare(button("historyBody-lena-first"), "visible", true);
            state.act("select", {id: "studio"});
            tryVerify(() => !findChild(workspace, "historyBody-lena-first"));
            state.act("select", {id: "mara"});
            compare(state.ui.selected, "mara");
            compare(button("historyBody-lena-first").expanded, true);

        }
        function test_recipientAddressTooltip() {
            const data = Fixture.initial("read");
            const mail = Store.find(data, "studio");
            mail.to = "recipient@example.org";
            mail.cc = "copy@example.org";
            state.data = data;
            state.act("select", {id: "studio"});
            wait(30);
            const recipients = button("recipients-studio");
            mouseMove(recipients, recipients.width / 2, recipients.height / 2);
            tryCompare(recipients.addressTooltip, "visible", true);
            compare(recipients.addressTooltip.text, "recipient@example.org, copy@example.org");
        }
        function test_senderAddressTooltip() {
            state.act("select", {id: "studio"});
            wait(30);
            const sender = button("senderName-studio");
            const tooltip = sender.addressTooltip;
            wait(30);
            mouseMove(sender, sender.width / 2, sender.height / 2);
            tryCompare(tooltip, "visible", true);
            compare(tooltip.text, state.selected.address);
            mouseClick(sender, sender.width / 2, sender.height / 2);
            tryCompare(button("messageBody-studio"), "expanded", false);
            mouseMove(workspace, 2, 2);
            tryCompare(tooltip, "visible", false);
        }
        function test_persistentRemoteImageRendersLocally_data() {
            return [{tag: "already cached", cached: true}, {tag: "cached CSS", cached: true, css: true}];
        }

        function test_persistentRemoteImageRendersLocally(row) {
            remoteImageClient.requests = 0;
            const url = "https://example.invalid/picture.gif";
            const view = createTemporaryObject(htmlBackgroundView, workspace, {
                html: row.css ? '<div style="width:100px;height:100px;background-image:url(' + url + ')">Mail</div>'
                    : '<p>Mail</p><img src="' + url + '">',
                mailboxClient: remoteImageClient, messageId: "cached-mail", remoteImages: !row.cached,
                remoteImageSources: row.cached ? [{url, source: remoteImageClient.source}] : []
            });
            verify(view);
            tryCompare(view, "ready", true);
            const browser = findChild(view, "mailHtmlBrowser");
            let visible = false;
            const inspect = row.css
                ? "getComputedStyle(document.querySelector('div')).backgroundImage.includes('data:image/gif;base64,')"
                : "(() => { const img = document.querySelector('img');"
                    + " return img.complete && img.naturalWidth > 0 && img.src.startsWith('data:'); })()";
            browser.runJavaScript(inspect, 1, result => { visible = result; });
            tryVerify(() => visible);
            compare(remoteImageClient.requests, row.cached ? 0 : 1);
            verify(!view.hasExternalImages);
        }

        function test_proxyProgressCountsOriginRequestsOnly() {
            const view = createTemporaryObject(htmlBackgroundView, workspace, {
                html: '<body style="background:white"><p>Mail</p></body>',
                mailboxClient: remoteImageClient, messageId: "proxy-progress", remoteImages: true
            });
            tryCompare(view, "ready", true);
            compare(view.imageCount, 0);
            const profile = findChild(view, "mailImageProfile");
            const browser = findChild(view, "mailHtmlBrowser");
            verify(profile);
            let inserted = false;
            browser.runJavaScript("(() => { const img = document.createElement('img');"
                + " img.dataset.tacitRemote = 'https://example.invalid/two.gif';"
                + " Object.defineProperty(img, 'complete', {get: () => document.body.dataset.decoded === 'yes'});"
                + " document.body.append(img); return true; })()", 1, value => { inserted = value; });
            tryVerify(() => inserted);
            profile.originImageStarted("https://example.invalid/one.gif");
            profile.originImageStarted("https://example.invalid/two.gif");
            compare(view.imageCount, 2);
            verify(view.loading);
            verify(!view.ready);
            profile.originImageFinished("https://example.invalid/one.gif", true);
            tryCompare(view, "finishedImages", 1);
            compare(view.progress, 0.5);
            profile.originImageFinished("https://example.invalid/two.gif", true);
            wait(150);
            verify(!view.ready); // Bytes received is not yet an image ready to display.
            compare(view.finishedImages, 1);
            browser.runJavaScript("document.body.dataset.decoded = 'yes';", 1, () => {});
            tryCompare(view, "ready", true);
            compare(view.finishedImages, 2);
            profile.imageCacheMiss("https://example.invalid/missing.gif");
            verify(view.hasExternalImages);
        }

        function test_threeRenderedMessagesSurviveReturnWithoutNavigation() {
            const cache = createTemporaryObject(imageCacheComponent, workspace);
            const owner = createTemporaryObject(imageOwnerComponent, workspace);
            const data = id => ({html: '<p>' + id + '</p><img src="' + remoteImageClient.source + '">',
                messageId: id, client: remoteImageClient, allowed: false});
            const first = cache.acquire("one", data("one"), owner);
            tryVerify(() => first.item?.ready === true);
            const browser = findChild(first, "mailHtmlBrowser");
            const revision = browser.documentRevision;
            cache.release(first, owner);
            const hiddenWidth = browser.width;
            compare(hiddenWidth, owner.width);
            for (const id of ["two", "three"]) {
                const slot = cache.acquire(id, data(id), owner);
                tryVerify(() => slot.item?.ready === true);
                cache.release(slot, owner);
            }
            compare(cache.count, 3);
            const returned = cache.acquire("one", data("one"), owner);
            compare(returned, first);
            verify(returned.item.ready);
            compare(findChild(returned, "mailHtmlBrowser"), browser);
            compare(browser.documentRevision, revision);
            returned.documentData = Object.assign({}, data("one"), {allowed: true});
            wait(40);
            compare(browser.documentRevision, revision);
            cache.release(returned, owner);
            const fourth = cache.acquire("four", data("four"), owner);
            compare(cache.count, 3);
            verify(!cache.slots.some(slot => slot.messageKey === "two"));
            cache.release(fourth, owner);
            cache.invalidate(["one"]);
            verify(!cache.slots.some(slot => slot.messageKey === "one"));
        }

        function test_prefetchContainsOnlyVisibleRows() {
            // An explicit long provider response guarantees offscreen rows;
            // this check must not depend on the visual demo's row order/height.
            const records = Array.from({length: 50}, (_, index) => Store.message("viewport-" + index,
                "Sender", "Message " + index, "Body", "Work", "Today", "12:00", false));
            const data = Object.assign({}, state.data, {ui: Object.assign({}, state.ui, {selected: "viewport-0"})});
            state.data = Queries.orderedView(Queries.replaceMailboxRows(data, records));
            wait(0);
            const list = button("messageList");
            list.view.forceLayout();
            list.updateVisibleRows();
            verify(state.visibleMessageRows.length > 0);
            const ids = new Set(state.visibleMessageRows.map(row => row.id));
            for (const child of list.view.contentItem.children) {
                if (!child.messageId || !child.visible) continue;
                const y = child.mapToItem(list.view, 0, 0).y;
                compare(ids.has(child.messageId), y < list.view.height && y + child.height > 0);
            }
            verify(state.visibleMessageRows.length < state.rows.length);
        }

        function test_htmlBackgroundChoices_data() {
            return [
                {tag: "none", mode: "none", html: "<p>Mail</p>", background: "none"},
                {tag: "primary", mode: "primary", html: "<p>Mail</p>", background: "primary"},
                {tag: "overlay", mode: "overlay", html: "<p>Mail</p>", background: "overlay"},
                {tag: "auto dark text", mode: "auto", html: '<p style="color:#111">Mail body</p>', background: "primary"},
                {tag: "auto light text", mode: "auto", html: '<p style="color:#eee">Mail body</p>', background: "overlay"},
                {tag: "auto dominant body", mode: "auto",
                    html: '<h1 style="color:#eee">Title</h1><p style="color:#111">' + "Body ".repeat(100) + '</p>',
                    background: "primary"},
                {tag: "own body background", mode: "auto",
                    html: '<body style="background:#fff;padding:17px"><p>Mail</p></body>', background: "none", padding: 17},
                {tag: "own table background", mode: "primary",
                    html: '<table bgcolor="#fff"><tr><td>Mail</td></tr></table>', background: "none"},
                {tag: "large html", mode: "auto",
                    html: "<!--" + "x".repeat(210000) + "-->" + '<p style="color:#111">Mail</p>', background: "primary"}
            ];
        }

        function test_htmlBackgroundChoices(row) {
            const view = createTemporaryObject(htmlBackgroundView, workspace,
                {html: row.html, backgroundMode: row.mode});
            verify(view);
            tryCompare(view, "ready", true);
            compare(view.appliedBackground, row.background);
            const browser = findChild(view, "mailHtmlBrowser");
            let padding = -1;
            browser.runJavaScript("parseFloat(getComputedStyle(document.body).paddingTop)", 1,
                result => { padding = result; });
            const expected = row.padding ?? (row.background === "none" ? 0 : K.Kit.tokens.space.s);
            tryVerify(() => padding === expected);
            if (row.background !== "none") {
                view.backgroundMode = "none";
                tryCompare(view, "ready", true);
                compare(view.appliedBackground, "none");
                padding = -1;
                browser.runJavaScript("parseFloat(getComputedStyle(document.body).paddingTop)", 1,
                    result => { padding = result; });
                tryVerify(() => padding === 0);
            }
        }

        function test_htmlBackgroundSettingIsSaved() {
            const original = state.readingPreferences.htmlBackground;
            try {
                state.act("settings");
                const setting = button("htmlBackgroundSetting");
                for (const [index, mode] of ["none", "primary", "overlay", "auto"].entries()) {
                    setting.picked(index);
                    compare(state.settings.htmlBackground, mode);
                    compare(state.readingPreferences.htmlBackground, mode);
                }
            } finally {
                state.readingPreferences.htmlBackground = original;
                state.readingPreferences.sync();
            }
        }

        function test_textMailColourChoicesApplyAndPersist() {
            const original = state.readingPreferences.bodyInk;
            try {
                for (const [index, ink] of ["main", "sec", "meta", "faint"].entries()) {
                    state.act("settings");
                    const setting = button("textMailColourSetting");
                    setting.picked(index);
                    compare(state.settings.bodyInk, ink);
                    compare(state.readingPreferences.bodyInk, ink);
                    state.act("select", {id: "mara"});
                    const body = button("messageBody-mara");
                    const paragraph = findChild(body, "plainMailParagraph");
                    verify(paragraph !== null);
                    compare(paragraph.ink, ink);
                }
                state.act("setting", {key: "bodyInk", value: "accent"});
                compare(state.settings.bodyInk, "faint");
            } finally {
                state.readingPreferences.bodyInk = original;
                state.readingPreferences.sync();
            }
        }

        function test_expandHistory() {
            const body = button("historyBody-lena-first");
            const wasVisible = body.visible;
            button("history-lena-first").forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryCompare(body, "visible", !wasVisible);
            keyClick(Qt.Key_Space);
            tryCompare(body, "visible", wasVisible);
        }
        function test_historyMotionAndDivider(){
            K.Kit.reducedMotion=false;
            var body=button("historyBody-lena-first");
            compare(body.height,0);
            button("history-lena-first").forceActiveFocus();
            keyClick(Qt.Key_Space);
            wait(80);
            compare(button("historyBody-lena-first"),body,"Expanding must preserve the message item");
            verify(body.height>0,"The body should expand during the arrive motion");
            var halfway=body.height;
            wait(K.Kit.motion("arriveSmall").ms);
            verify(body.height>halfway,"Expansion must move through intermediate heights");
            var divider=button("historyDivider-lena-first");
            verify(divider.y>=body.y+body.height,"The hairline must follow the whole message");
            keyClick(Qt.Key_Space);
            wait(60);verify(body.height>0,"Content must remain visible during leave");
            tryCompare(body,"height",0,K.Kit.motion("leave").ms+500);
            K.Kit.reducedMotion=true;
        }
        function test_latestMessageToggle(){
            var body=button("messageBody-mara");verify(body.height>0);
            click("messageHeader-mara");compare(body.height,0);
            click("messageHeader-mara");verify(body.height>0);
            compare(button("attachment-review").fileName,"Review summary.pdf");
        }
        function test_sentMessageToggle(){
            state.reply("Reply",false);state.act("draft",{body:"A local reply"});state.act("send");wait(30);
            var id=state.selected.replies[0].id;
            var body=button("messageBody-"+id), header=button("messageHeader-"+id);
            verify(body.height>0);header.forceActiveFocus();keyClick(Qt.Key_Return);wait(30);compare(body.height,0);
            keyClick(Qt.Key_Return);wait(30);verify(body.height>0);
        }
        function test_headerFocusRoom(){
            var scroll=button("readingScroll"), row=button("messageHeader-mara");
            var room=K.Kit.tokens.state.focusGap+K.Kit.tokens.state.focusRing;
            var at=row.mapToItem(scroll,0,0);
            verify(at.x>=room,"The full left focus ring must fit inside the scroll viewport");
            verify(at.x+row.width+room<=scroll.width,"The full right focus ring must fit inside the scroll viewport");
            var first=button("history-lena-first").mapToItem(scroll,0,0);
            verify(first.y>=room,"The top focus ring must fit inside the scroll viewport");
            var title=button("folderMenu"), caption=button("mailboxCaption");
            var titleAt=title.mapToItem(workspace,0,0), captionAt=caption.mapToItem(workspace,0,0);
            verify(captionAt.y>=titleAt.y+title.height+room,"Caption must clear the title's focus ring");
        }
        function test_attachmentStrip(){
            compare(button("attachment-review").fileName,"Review summary.pdf");
            state.act("select",{id:"studio"});
            wait(30);
            compare(state.selected.files.length,10);
            compare(state.selected.files[9].name,"10 Next steps.md");
            const first = button("attachment-prototype-1");
            const saves = Qt.createQmlObject('import QtTest; SignalSpy { signalName: "saveRequested" }', first);
            saves.target = state;
            mouseDoubleClickSequence(first, first.width / 2, first.height / 2);
            tryVerify(() => state.ui.attachment?.id === state.selected.files[0].id);
            wait(500);
            compare(saves.count, 0);
            saves.destroy();
        }
        function test_replyKeepsSingleMessageVisible(){
            state.act("select",{id:"studio"});
            wait(30);
            var original=button("messageBody-studio");
            const reader = button("readingScroll");
            reader.contentY = Math.max(0, reader.contentHeight - reader.height);
            click("reply");
            compare(state.draft.to,"tactical.studio@example.com");
            compare(button("messageBody-studio"),original);
            verify(original.visible && original.height>0);
            var editor=button("mailEditor");
            verify(editor.mapToItem(workspace,0,0).y>=original.mapToItem(workspace,0,original.height).y);
        }
        function test_replyTargetsHistoricalMessage(){
            click("history-lena-first");
            click("reply-lena-first");
            compare(state.draft.conversation,"mara");
            compare(state.draft.to,"lena.fischer@example.com");
            var editor=button("mailEditor"), source=button("history-lena-first"), next=button("history-nils-first");
            compare(editor.replySourceName,"Lena Fischer");
            verify(editor.mapToItem(workspace,0,0).y>=source.mapToItem(workspace,0,source.height).y);
            verify(editor.mapToItem(workspace,0,editor.height).y<=next.mapToItem(workspace,0,0).y);
        }
        function test_threadOpensAtHistoricalDraft() {
            state.reply("Reply", false, "lena-first");
            const draftId = state.draft.id;
            state.act("select", {id: "studio"});
            state.act("select", {id: "mara"});
            compare(state.draft.id, draftId);

            const scroll = button("readingScroll");
            const editor = button("mailEditor");
            tryVerify(() => editor.visible);
            tryVerify(() => {
                const top = editor.mapToItem(scroll.contentItem, 0, 0).y;
                const expected = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                    top - K.Kit.tokens.space.l));
                return Math.abs(scroll.contentY - expected) < 1;
            });
        }

        function test_htmlProgressWaitsForImages_data() {
            return [{tag: "remote", remote: true}, {tag: "local", remote: false}];
        }

        function test_htmlProgressWaitsForImages(row) {
            const data = Fixture.initial("read");
            Store.find(data, "studio").bodyHtml = '<body style="background:white"><p>HTML message</p></body>';
            state.data = data;
            if (row.remote)
                state.allowRemoteImages("studio");
            state.act("select", {id: "studio"});
            tryVerify(() => !!findChild(workspace, "mailHtmlBrowser"));
            const browser = button("mailHtmlBrowser");
            tryVerify(() => browser.loaded);

            // Hold one image pending deterministically in the same isolated world as the reader.
            let inserted = false;
            browser.runJavaScript("(() => {"
                + " for (const done of [true, false]) {"
                + " const img = document.createElement('img');"
                + " Object.defineProperty(img, 'currentSrc', {value: "
                + JSON.stringify(row.remote ? "https://example.invalid/image.png" : "data:image/png;base64,") + "});"
                + " Object.defineProperty(img, 'complete', {get: () => done || document.body.dataset.finish === 'yes'});"
                + " document.body.append(img); } return true; })()", 1, result => { inserted = result; });
            tryVerify(() => inserted);
            browser.loaded = false;
            browser.loadingMessage = true;
            browser.fitDocument();

            const progress = button("htmlLoadProgress");
            if (row.remote) {
                tryCompare(progress, "value", 0.5);
                verify(progress.visible);
                compare(button("htmlSurface-studio").opacity, 0);
            } else {
                tryCompare(browser, "imageCount", 0);
                verify(!progress.visible);
            }
            verify(!browser.loaded);
            browser.runJavaScript("document.body.dataset.finish = 'yes';", 1, () => {});
            tryVerify(() => browser.loaded);
            compare(browser.finishedImages, row.remote ? 2 : 0);
            compare(browser.imageCount, row.remote ? 2 : 0);
            compare(button("htmlSurface-studio").opacity, 1);
        }

        function test_localHtmlImagesDoNotOfferRemoteLoading() {
            const data = Fixture.initial("read");
            Store.find(data, "studio").bodyHtml = '<!-- <img src="https://example.invalid/unused.png"> -->'
                + '<img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">';
            state.data = data;
            state.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            verify(!button("loadImages-studio").visible);
        }

        function test_loadImagesStaysDismissedAfterReopeningMessage() {
            const data = Fixture.initial("read");
            Store.find(data, "studio").bodyHtml = '<p>HTML message</p><img src="https://example.invalid/image.png">';
            state.data = data;
            state.act("select", {id: "studio"});
            const action = button("loadImages-studio");
            tryVerify(() => action.visible);
            action.activated();
            tryCompare(action, "visible", false);
            state.act("select", {id: "mara"});
            state.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            verify(!button("loadImages-studio").visible);
        }

        function test_htmlFadesWithoutHeightAnimation() {
            K.Kit.reducedMotion = false;
            const data = Fixture.initial("read");
            Store.find(data, "studio").bodyHtml = "<p>HTML message</p>".repeat(30);
            state.data = data;
            state.act("select", {id: "studio"});

            const body = button("messageBody-studio");
            const presentation = button("htmlPresentation-studio");
            tryVerify(() => presentation.reveal > 0 && presentation.reveal < 1);
            verify(body.height > 0);
            const height = presentation.height;
            tryCompare(presentation, "reveal", 1);
            compare(presentation.height, height);
        }

        function test_singleHtmlMailStaysAtTopAfterReveal() {
            K.Kit.reducedMotion = false;
            const data = Fixture.initial("read");
            const message = Store.find(data, "studio");
            message.bodyHtml = "<p>HTML message</p>".repeat(150);
            state.data = data;
            state.act("select", {id: "studio"});

            const scroll = button("readingScroll");
            tryVerify(() => !!findChild(workspace, "mailHtmlBrowser"));
            const browser = button("mailHtmlBrowser");
            tryVerify(() => browser.loaded && browser.height > scroll.height);
            tryVerify(() => !!findChild(workspace, "reply")?.enabled);
            wait(0);
            verify(scroll.contentHeight > scroll.height);
            compare(scroll.contentY, 0);
        }

        function test_longSingleMailOpensAtTopAfterDraft() {
            const data = Fixture.initial("read");
            Store.find(data, "mara").body = "Long reply context.\n".repeat(150);
            Store.find(data, "studio").bodyHtml = "<p>HTML message</p>".repeat(150);
            state.data = data;
            state.act("select", {id: "mara"});
            state.reply("Reply", false, "mara");

            const scroll = button("readingScroll");
            tryVerify(() => button("mailEditor").visible && scroll.contentY > 0);

            state.act("select", {id: "studio"});
            compare(state.ui.view, "read");
            tryVerify(() => !!findChild(workspace, "mailHtmlBrowser"));
            const browser = button("mailHtmlBrowser");
            tryVerify(() => browser.loaded && browser.height > scroll.height);
            tryCompare(scroll, "contentY", 0);
        }

        function test_threadWithoutDraftOpensAtLastMessage() {
            state.act("select", {id: "studio"});
            waitForRendering(workspace);
            state.threadScrollPositions = new Map();
            state.act("select", {id: "mara"});
            compare(state.ui.view, "read");
            const scroll = button("readingScroll");
            const header = button("messageHeader-mara");
            tryVerify(() => {
                const top = header.mapToItem(scroll.contentItem, 0, 0).y;
                const expected = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                    top - K.Kit.tokens.space.l));
                return Math.abs(scroll.contentY - expected) < 1;
            });
        }
        function test_menuDismissClickDoesNotReachPage_data() {
            return [{tag: "filter", trigger: "searchFilter"}, {tag: "message actions", trigger: "messageMore"}];
        }

        function test_menuDismissClickDoesNotReachPage(row) {
            if (row.tag === "filter") state.act("search", {text: "palettes"});
            click(row.trigger);
            wait(200);
            const newMessage = button(row.tag === "filter" ? "closeSearch" : "newMessage");
            mouseClick(newMessage, newMessage.width / 2, newMessage.height / 2);
            wait(30);
            compare(state.ui.view, "read", "Dismissing a menu must consume the click");
            if (row.tag === "filter") verify(state.ui.searching);
            mouseClick(newMessage, newMessage.width / 2, newMessage.height / 2);
            if (row.tag === "filter") tryCompare(state.ui, "searching", false);
            else tryCompare(state.ui, "view", "compose");
        }

        function test_editorMenusConsumeDismissClick_data() {
            return [{tag: "account and reply menus", component: kitMenuButton},
                {tag: "format menus", component: formatMenuButton}];
        }

        function test_editorMenusConsumeDismissClick(row) {
            const trigger = createTemporaryObject(row.component, workspace, {x: 900, y: 100});
            verify(trigger);
            mouseClick(trigger, trigger.width / 2, trigger.height / 2);
            wait(200);
            const newMessage = button("newMessage");
            mouseClick(newMessage, newMessage.width / 2, newMessage.height / 2);
            wait(30);
            compare(state.ui.view, "read");
            mouseClick(newMessage, newMessage.width / 2, newMessage.height / 2);
            tryCompare(state.ui, "view", "compose");
        }

        function test_mailboxMetadataAlignsWithFilter() {
            const caption = button("mailboxCaption");
            const filter = button("searchFilter");
            for (const counts of [false, true]) {
                if (counts) {
                    const messages = Store.mailboxMessages(state.data).map((message, index) => Object.assign({}, message,
                        {unread: index < 5}));
                    state.data = Queries.replaceMailboxRows(state.data, messages);
                }
                wait(0);
                verify(!filter.visible, "Everyday inbox must not expose search filters");
                verify(!findChild(workspace, "mailSortLabel"));
                compare(caption.lineCount, 1);
            }
        }

        function test_filterMenuKeyboard(){state.act("search",{text:"palettes"});click("searchFilter");wait(200);keyClick(Qt.Key_Down);keyClick(Qt.Key_Down);keyClick(Qt.Key_Return);wait(30);compare(state.ui.searchFilter,"Unread");compare(state.ui.sort,"Newest first");compare(button("searchFilter").items.length,4);}

        function test_editorFooterFollowsBody(){
            click("replyAll");
            var send=button("sendDraft"), body=button("draftBody"), editor=button("mailEditor"), scroll=button("readingScroll");
            var sendY=send.mapToItem(editor,0,0).y;
            var bodyEnd=body.mapToItem(editor,0,body.height).y;
            verify(sendY>=bodyEnd,"Send must follow the writing field");
            verify(sendY+send.height<=editor.height,"Send must stay inside its editor");
            verify(body.width<=scroll.width,"The editor must fit the reading column");
        }
        function test_replyGifFitsShortViewport() {
            const previousHeight = workspace.parent.height;
            try {
                click("replyAll");
                workspace.parent.height = 500;
                wait(30);
                const body = button("draftBody");
                if (!button("formatBold").visible)
                    skip("Optional editor-engine module is unavailable");
                body.insertAttachment(Qt.resolvedUrl("../../tests/fixtures/funny-cat-52.gif"),
                    {id: "fit-gif", name: "funny-cat-52.gif"}, 0);
                const dimensions = /<img [^>]* width="([\d.]+)" height="([\d.]+)"/.exec(body.snapshot().bodyHtml);
                verify(dimensions !== null);
                const width = Number(dimensions[1]);
                const height = Number(dimensions[2]);
                verify(height <= button("readingScroll").height * 0.45);
                verify(Math.abs(width / height - 470 / 278) < 0.01);
                tryVerify(() => !!findChild(body, "editorAnimatedImage"));
                const gif = findChild(body, "editorAnimatedImage");
                tryVerify(() => gif.frameCount > 1);
                verify(Math.abs(gif.width - width) < 0.01);
                verify(Math.abs(gif.height - height) < 0.01);
                const frame = gif.currentFrame;
                tryVerify(() => gif.currentFrame !== frame);
            } finally {
                workspace.parent.height = previousHeight;
            }
        }
        function test_reopenedDraftGifKeepsAnimating() {
            click("replyAll");
            const body = button("draftBody");
            if (!button("formatBold").visible)
                skip("Optional editor-engine module is unavailable");

            const messageId = state.selected.id;
            const draftId = state.draft.id;
            body.insertAttachment(Qt.resolvedUrl("../../tests/fixtures/funny-cat-52.gif"),
                {id: "reopen-gif", name: "funny-cat-52.gif"}, 0);
            tryVerify(() => state.draft?.bodyHtml?.includes("data:image/gif;base64,"));

            state.act("select", {id: "studio"});
            compare(state.ui.view, "read");
            tryVerify(() => !findChild(workspace, "editorAnimatedImage"));
            state.act("select", {id: messageId});
            compare(state.draft.id, draftId);
            tryVerify(() => !!findChild(button("draftBody"), "editorAnimatedImage"));
            const gif = findChild(button("draftBody"), "editorAnimatedImage");
            tryVerify(() => gif.visible && gif.frameCount > 1);
            const frame = gif.currentFrame;
            tryVerify(() => gif.currentFrame !== frame);
        }

        function test_sendReplyWithGifAndTrailingText() {
            click("replyAll");
            const body = button("draftBody");
            if (!button("formatBold").visible)
                skip("Optional editor-engine module is unavailable");

            body.input.forceActiveFocus();
            keyClicks("Before the GIF");
            const file = Qt.resolvedUrl("../../tests/fixtures/funny-cat-52.gif");
            const attachment = { id: "test-gif", name: "funny-cat-52.gif" };
            body.insertAttachment(file, attachment, body.input.cursorPosition);
            keyClicks("lol");

            const html = body.snapshot().bodyHtml;
            verify(html.indexOf("Before the GIF") < html.indexOf("data:image/gif;base64,"));
            verify(html.indexOf("lol", html.indexOf("</a>")) > html.indexOf("</a>"));
            verify(html.length > 200000, "Exercise the large HTML loading path");

            button("mailEditor").sendDraft();
            compare(state.selected.replies[state.selected.replies.length - 1].bodyHtml, html);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true, 10000);
            const browser = button("mailHtmlBrowser");
            verify(waitForRendering(browser));
            compare(browser.backgroundColor, Qt.rgba(0, 0, 0, 0));
            let rendered = false;
            browser.runJavaScript(
                "(() => { const image = document.querySelector('img');"
                + " const range = document.createRange(); range.selectNodeContents(document.body);"
                + " return !!image && image.naturalWidth > 0 && document.body.innerText.trim().endsWith('lol')"
                + " && range.getBoundingClientRect().bottom <= window.innerHeight + 1; })()",
                1, result => { rendered = result; });
            tryVerify(() => rendered);
        }
        function test_richTextDraft(){
            state.act("new");
            state.act("draft", {to: "anna@example.net", body: "First\nSecond"});
            wait(30);
            var body = button("draftBody");
            var bold = button("formatBold");
            if (!bold.visible)
                skip("Optional editor-engine module is unavailable");

            body.input.forceActiveFocus();
            body.input.select(0, 5);
            click("formatBold");
            tryVerify(() => state.draft.bodyHtml.includes("<strong>First</strong>"));
            click("formatItalic");
            tryVerify(() => state.draft.bodyHtml.includes("<em><strong>First</strong></em>"));

            click("formatLink");
            var url = button("formatLinkUrl");
            url.input.text = "https://example.org/";
            click("applyFormatLink");
            tryVerify(() => state.draft.bodyHtml.includes('href="https://example.org/"'));
            body.input.selectAll();
            click("formatList");
            tryVerify(() => state.draft.bodyHtml.includes("<ul>"));
            compare(state.draft.body, "First\nSecond");

            var id = state.draft.id;
            var html = state.draft.bodyHtml;
            state.act("keepDraft");
            state.act("select", {id: id});
            tryCompare(button("draftBody").input, "length", 12);
            tryVerify(() => button("draftBody").snapshot().bodyHtml.includes("<strong>"));
            html = button("draftBody").snapshot().bodyHtml;
            verify(html.includes("<ul>") && html.includes('href="https://example.org/"'));
            body = button("draftBody");
            body.input.forceActiveFocus();
            body.input.cursorPosition = body.input.length;
            click("formatBold");
            keyClicks("X");
            tryVerify(() => state.draft.bodyHtml.includes("<strong>X</strong>"));
            body.input.undo();
            tryVerify(() => state.draft.bodyHtml === html);
            state.act("send");
            compare(state.selected.replies[0].bodyHtml, html);
            state.act("undoSend");
            compare(state.draft.bodyHtml, html);
        }
        function test_sidebar(){click("folderMenu");compare(state.ui.rail,true);verify(button("mailboxes").visible);}
    }
}
