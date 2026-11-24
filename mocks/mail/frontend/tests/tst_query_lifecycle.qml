import QtQuick
import QtTest
import ".." as Mail

Item {
    id: fixture
    QtObject {
        id: fakeClient
        property bool enabled: false
        property int calls: 0
        signal mailboxFirstPage(int revision, var messages)
        signal mailboxLoaded(int revision, var messages, bool ok)
        signal failed()
        signal searchFirstPage(int revision, var messages)
        signal searched(int revision, var messages, bool ok)
        function loadMailboxCounts(revision) { ++calls; }
        function loadMailboxView(account, folder, filter, sort, revision) { ++calls; }
        function search(term, revision) { ++calls; }
    }
    Component { id: folderFactory; Mail.MailboxQuery {} }
    Component { id: searchFactory; Mail.MailSearchQuery {} }
    TestCase {
        name: "QueryLifecycle"
        when: windowShown
        property var query: null
        property string kind: ""
        property int publications: 0
        function modes() { return [{tag: "folder"}, {tag: "search"}, {tag: "counts"}]; }
        function start(mode) {
            kind = mode;
            fakeClient.enabled = false; fakeClient.calls = 0; publications = 0;
            query = mode === "search"
                ? searchFactory.createObject(fixture, {client: fakeClient, term: "first"})
                : folderFactory.createObject(fixture, {client: fakeClient, folder: mode === "counts" ? "" : "Inbox", allFolders: mode === "counts"});
            if (mode === "search") {
                query.partial.connect(() => { ++publications; });
                query.completed.connect(() => { ++publications; });
            } else query.refreshed.connect(() => { ++publications; });
            fakeClient.enabled = true;
            if (mode === "search") query.active = true;
            else query.refresh();
            tryCompare(fakeClient, "calls", 1);
        }
        function respond(revision, ok = true) {
            if (kind === "search") fakeClient.searched(revision, [{id: "result"}], ok);
            else fakeClient.mailboxLoaded(revision, [{id: "result"}], ok);
        }
        function firstPage(revision) {
            if (kind === "search") fakeClient.searchFirstPage(revision, [{id: "partial"}]);
            else fakeClient.mailboxFirstPage(revision, [{id: "partial"}]);
        }
        function cleanup() {
            if (query) { query.destroy(); query = null; }
            wait(0);
        }
        function test_searchFilterUsesDistinctRevisionAndRetainsMatchingResults() {
            start("search");
            const oldRevision = query.revision;
            query.filter = "Unread";
            tryCompare(fakeClient, "calls", 2);
            respond(oldRevision);
            compare(publications, 0);
            respond(query.revision);
            compare(publications, 1);
            query.retainedTerm = query.term;
            query.retainedFilter = "Unread";
            query.active = false;
            query.active = true;
            wait(70);
            compare(fakeClient.calls, 2);
        }
        function test_refreshSignalsCoalesce_data() { return modes(); }
        function test_refreshSignalsCoalesce(row) {
            start(row.tag);
            const revision = query.revision;
            query.refresh(); query.refresh(); query.refresh();
            compare(fakeClient.calls, 1);
            verify(query.loading); verify(query.refreshPending);
            respond(revision);
            compare(fakeClient.calls, 2);
            verify(query.loading); verify(!query.refreshPending);
            verify(row.tag === "counts" ? query.revision < revision : query.revision > revision);
            respond(query.revision);
            verify(!query.loading);
            compare(fakeClient.calls, 2);
        }
        function test_refreshStartedByResultConsumerIsNotDuplicated_data() { return modes(); }
        function test_refreshStartedByResultConsumerIsNotDuplicated(row) {
            start(row.tag);
            const onResult = () => query.refresh();
            if (kind === "search") query.completed.connect(onResult);
            else query.refreshed.connect(onResult);
            query.refresh(); // One queued refresh before the original response arrives.
            respond(query.revision);
            if (kind === "search") query.completed.disconnect(onResult);
            else query.refreshed.disconnect(onResult);
            compare(fakeClient.calls, 2);
            verify(query.loading); verify(!query.refreshPending);
            respond(query.revision);
            compare(fakeClient.calls, 2);
            verify(!query.loading);
        }
        function test_staleRepliesAndEarlyResults_data() { return [{tag: "folder"}, {tag: "search"}]; }
        function test_staleRepliesAndEarlyResults(row) {
            start(row.tag);
            const oldRevision = query.revision;
            if (kind === "search") query.term = "second";
            else query.folder = "Archive";
            tryCompare(fakeClient, "calls", 2);
            firstPage(oldRevision); respond(oldRevision);
            compare(publications, 0); verify(query.loading);
            firstPage(query.revision);
            compare(publications, 1); verify(query.loading);
            respond(query.revision);
            compare(publications, 2); verify(!query.loading);
        }
        function test_failedRequestStillServicesQueuedRefresh_data() { return modes(); }
        function test_failedRequestStillServicesQueuedRefresh(row) {
            start(row.tag);
            query.refresh();
            respond(query.revision, false);
            compare(fakeClient.calls, 2); verify(query.loading);
            respond(query.revision, false);
            verify(!query.loading); verify(!query.refreshPending);
            if (kind !== "search") verify(query.error.length > 0);
        }
        function test_refreshDoesNotReplaceVisibleFolderWithPartialPage() {
            start("folder");
            respond(query.revision);
            const visible = query.messages;
            query.refresh(); firstPage(query.revision);
            compare(query.messages, visible);
            verify(query.loading);
            respond(query.revision);
            verify(!query.loading);
        }
        function test_closingSearchRejectsInFlightReplies() {
            start("search");
            const revision = query.revision;
            query.active = false;
            firstPage(revision); respond(revision);
            compare(publications, 0); verify(!query.loading);
        }
        function test_retainedSearchDoesNotRequestAgain() {
            start("search");
            respond(query.revision);
            query.retainedTerm = query.term;
            query.active = false;
            query.active = true;
            wait(80);
            compare(fakeClient.calls, 1);
            verify(!query.loading);
        }
    }
}
