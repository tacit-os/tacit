import QtQuick
import QtTest
import ".." as Mail
import "../mail-store.js" as Store
import "fixtures/mailbox-responses.js" as Queries

Item {
    id: fixture
    QtObject {
        id: cacheProbe
        property int calls: 0
        property var ids: null
        function invalidate(messageIds) { ++calls; ids = messageIds; }
    }
    QtObject {
        id: clientProbe
        property string consent: ""
        signal threadPrefetched(int ticket, var messages, bool ok)
        signal threadPrefetchImagesLoaded(int ticket, var messages)
        signal threadMessageLoaded(int revision, var message)
        signal threadLoaded(int revision, var messages, bool ok)
        function allowMessageImages(id) { consent = id; }
        function loadThread(account, conversation, revision) {}
        function prefetchThread(account, conversation, ticket) {}
        function loadThreadImages(messages, revision) {}
    }
    Component { id: readingFactory; Mail.MailReadingState {} }
    TestCase {
        name: "ReadingState"
        when: windowShown
        property var reader: null
        function init() {
            reader = readingFactory.createObject(fixture, {data: Store.emptyMailbox()});
            verify(reader !== null);
            cacheProbe.calls = 0; cacheProbe.ids = null; clientProbe.consent = "";
        }
        function cleanup() { reader.destroy(); reader = null; wait(0); }
        function raw(id, sender = "sender@example.test", mailbox = "Inbox") {
            return {id, account_id: "work", conversation_id: "conversation", mailbox,
                from: {name: "Sender", email: sender}, to: [{email: "me@example.test"}],
                subject: "Thread", body_text: "Body " + id, date: "2026-11-16T12:00:00Z", attachments: []};
        }
        function showSummary() {
            const state = Store.emptyMailbox();
            state.accounts = [{id: "work", name: "Work", email: "me@example.test"}];
            reader.data = Queries.fromMailbox(state, [raw("selected")]);
            compare(reader.selectedRow.id, "selected");
        }
        function test_threadProjectionKeepsHistoryAndSummaryFallbacks() {
            showSummary();
            const full = Object.assign({}, raw("selected"), {
                body_text: "Full body", body_html: "<p>Full body</p>", to: [],
                remote_images: [{url: "https://example.invalid/picture"}], remote_images_allowed: true
            });
            const deletedDraft = Object.assign({}, raw("draft", "me@example.test", "Trash"), {trash_origin: "Drafts"});
            reader.threadQuery.messages = [raw("previous", "another@example.test"), full,
                deletedDraft, raw("trashed", "third@example.test", "Trash")];
            compare(reader.selected.body, "Full body");
            compare(reader.selected.bodyHtml, "<p>Full body</p>");
            compare(reader.selected.to, "me@example.test");
            compare(reader.selected.remoteImages.length, 1);
            verify(reader.selected.remoteImagesAllowed);
            compare(reader.selected.history.length, 2);
            compare(reader.selected.history[0].id, "previous");
            compare(reader.selected.history[1].id, "trashed");
            verify(!reader.selected.history[0].expanded);
            verify(reader.canReplyAll);
            compare(reader.selectedRow.body, "Body selected");
        }
        function test_waitForInitialThreadButKeepExistingThreadDuringRefresh() {
            showSummary();
            reader.threadQuery.loading = true;
            compare(reader.selected, null);
            reader.threadQuery.messages = [raw("previous"), raw("selected")];
            compare(reader.selected.id, "selected");
            compare(reader.selected.history.length, 1);
            reader.threadQuery.loading = false;
            compare(reader.selected.history.length, 1);
        }
        function test_invalidateClearsBothReadingCaches() {
            reader.htmlCache = cacheProbe;
            reader.threadQuery.prefetched.set("old", {messages: [raw("old")]});
            reader.invalidate(["deleted"]);
            compare(cacheProbe.calls, 1);
            compare(cacheProbe.ids[0], "deleted");
            compare(reader.threadQuery.prefetched.size, 0);
            reader.invalidate();
            compare(cacheProbe.calls, 2);
            compare(cacheProbe.ids, undefined);
        }
        function test_remoteConsentRemainsOwnedByMaildWhenConnected() {
            reader.allowRemoteImages("demo");
            verify(reader.approvedRemoteImages.demo);
            reader.client = clientProbe;
            verify(!reader.approvedRemoteImages.demo);
            reader.allowRemoteImages("message");
            compare(clientProbe.consent, "message");
            verify(!reader.approvedRemoteImages.message);
        }
    }
}
