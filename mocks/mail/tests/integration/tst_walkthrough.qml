import QtQuick
import QtTest
import "../../frontend" as Mail

Item {
    width: 1720
    height: 972

    readonly property var session: workspace.controller
    Mail.MailWorkspace {
        id: workspace
        anchors.fill: parent
        mailboxClient: testMailbox
    }

    SignalSpy {
        id: syncFinished
        target: testMailbox
        signalName: "inboxSyncFinished"
    }

    TestCase {
        name: "MaildFrontend"
        when: windowShown

        function control(name) {
            const item = findChild(workspace, name);
            verify(item !== null, "Missing " + name);
            return item;
        }

        function messageBrowser(messageId) {
            const body = findChild(workspace, "messageBody-" + messageId);
            return body ? findChild(body, "mailHtmlBrowser") : null;
        }

        function test_startupSyncWithUnlimitedTimeoutCompletes() {
            tryVerify(() => session.accounts.some(account => account.id === "work"));
            syncFinished.clear();
            verify(testMailbox.syncInbox("work"));
            tryVerify(() => syncFinished.count > 0);
            compare(syncFinished.signalArguments[0][0], "work");
            compare(syncFinished.signalArguments[0][1], true,
                "A zero timeout must allow the import stream to finish");
            verify(!session.syncStatusByAccount.work.failed);
        }

        function test_backendHistoryAndGifFixture() {
            tryVerify(() => session.rows.some(row => row.id === "seed-rich-text"));
            session.act("select", {id: "seed-02"});
            tryVerify(() => !!findChild(workspace, "history-seed-00"));
            const header = control("history-seed-00");
            const scroll = control("readingScroll");
            scroll.contentY = 0;
            mouseClick(header);
            tryVerify(() => control("historyBody-seed-00").visible);
            session.act("select", {id: "seed-rich-text"});
            tryVerify(() => messageBrowser("seed-rich-text")?.loaded === true, 10000);
            verify(session.selected.files.some(file => file.name === "funny-cat-52.gif" && file.inline));
            const chip = findChild(workspace, "attachment-seed-rich-text-gif");
            verify(!chip || !chip.visible);
        }

        function test_cachedOriginAndMissingOriginUseMaildProxy() {
            session.act("select", {id: "seed-rich-text"});
            tryVerify(() => messageBrowser("seed-rich-text")?.loaded === true, 10000);
            const browser = messageBrowser("seed-rich-text");
            let cachedVisible = false;
            browser.runJavaScript("(() => { const img = document.querySelector('#proxy-cached');"
                + " return img?.complete && img.naturalWidth > 0 && img.src.startsWith('tacit-image://mail/'); })()", 1,
                value => { cachedVisible = value; });
            tryVerify(() => cachedVisible);
            verify(browser.hasExternalImages);
            compare(browser.imageCount, 0); // Both probes are local; a miss must not start origin progress.
            tryVerify(() => findChild(workspace, "loadImages-seed-rich-text")?.visible === true);
        }

        function test_prefetchedThreadAndLocalImageAreReadyAtSelection() {
            const query = session.threadQuery;
            tryVerify(() => session.rows.some(row => row.id === "seed-02")
                && session.rows.some(row => row.id === "seed-rich-text"));
            const threadKey = id => {
                const row = session.rows.find(entry => entry.id === id);
                return JSON.stringify([row.backendAccount, row.backendConversation]);
            };
            const conversationKey = threadKey("seed-02");
            const richMailKey = threadKey("seed-rich-text");
            session.act("select", {id: "seed-rich-text"});
            tryVerify(() => query.prefetched.get(conversationKey)?.messages
                .some(message => message.id === "seed-00"));

            session.act("select", {id: "seed-02"});
            verify(!query.loading);
            verify(session.selected.history.some(message => message.id === "seed-00"));
            verify(!!findChild(workspace, "history-seed-00"));

            tryVerify(() => query.prefetched.get(richMailKey)?.messages
                .some(message => message.id === "seed-rich-text"
                    && message.attachments.some(file => file.inlineSource?.startsWith("tacit-image://mail/"))));
            session.act("select", {id: "seed-rich-text"});
            verify(!query.loading);
            verify(session.selected.files.some(file => file.inlineSource?.startsWith("tacit-image://mail/")));

            tryVerify(() => messageBrowser("seed-rich-text")?.loaded === true);
            const browser = messageBrowser("seed-rich-text");
            let imageVisible = false;
            browser.runJavaScript("Array.from(document.images).some(image => "
                + "image.complete && image.naturalWidth > 0 && image.src.startsWith('tacit-image://mail/'))",
                1, result => { imageVisible = result === true; });
            tryVerify(() => imageVisible);
        }

        function test_replyWithGifAndPdf() {
            tryVerify(() => session.rows.length > 0 && !!session.selected);
            session.draftQuery.refresh();
            if (testPhase === "create") {
                session.reply("Reply", false);
                tryVerify(() => !!findChild(workspace, "draftBody"));
                const editor = control("draftBody");
                tryVerify(() => control("formatBold").visible);
                editor.input.forceActiveFocus();
                keyClick(Qt.Key_A);
                const gif = Qt.resolvedUrl("../fixtures/funny-cat-52.gif");
                const pdf = Qt.resolvedUrl("../fixtures/review-summary.pdf");
                editor.fileDropped(gif, editor.input.cursorPosition);
                keyClick(Qt.Key_L);
                keyClick(Qt.Key_O);
                keyClick(Qt.Key_L);
                session.act("attach", {url: String(pdf), name: "review-summary.pdf"});
                const draftId = session.draft.id;
                const conversation = session.ui.selected;
                session.act("select", {id: "seed-02"});
                session.act("select", {id: conversation});
                compare(session.ui.view, "draft");
                compare(session.draft.id, draftId);
                verify(control("archive").visible);
                tryVerify(() => !!session.savedDraftIds[draftId] && !session.draftSaving, 15000);
                return;
            }

            if (testPhase === "send") {
                tryVerify(() => session.data.drafts.length === 1);
                session.act("select", {id: session.data.drafts[0].id});
                tryVerify(() => !!findChild(workspace, "draftBody"));
                const editor = control("draftBody");
                tryVerify(() => editor.snapshot().bodyHtml.includes("data:image/gif;base64,"));
                verify(editor.snapshot().body.includes("lol"));
                compare(session.draft.files.length, 2);
                const send = control("sendDraft");
                tryVerify(() => send.enabled);
                const scroll = control("readingScroll");
                // Explicit user scrolling takes over from initial header positioning.
                scroll.movementStarted();
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                verify(waitForRendering(send));
                mouseClick(send);
                tryVerify(() => session.ui.view === "read", 15000);
                tryVerify(() => !session.hasPending, 20000);
                return;
            }

            session.act("folder", {folder: "Sent"});
            tryVerify(() => session.rows.length > 0);
            const sent = session.rows.find(row => row.body.includes("lol"));
            verify(!!sent, "The sent reply must survive a daemon restart");
            compare(sent.files.length, 2);
            verify(sent.files.some(file => file.name === "review-summary.pdf"));
            session.act("select", {id: sent.id});
            tryVerify(() => messageBrowser(sent.id)?.loaded === true, 15000);
            const browser = messageBrowser(sent.id);
            let rendered = false;
            browser.runJavaScript(
                "(() => { const image = document.querySelector('img');"
                + " return !!image && image.naturalWidth > 0 && document.body.innerText.includes('lol'); })()",
                1, result => { rendered = result; });
            tryVerify(() => rendered);
        }
    }
}
