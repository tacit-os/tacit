import QtQuick
import QtTest
import ".." as Mail

Item {
    id: fixture
    QtObject {
        id: client
        property bool enabled: false
        property var calls: []
        signal mailboxFirstPage(int revision, var messages)
        signal mailboxLoaded(int revision, var messages, bool ok)
        signal failed()
        function loadMailboxCounts(revision) {}
        function loadMailboxView(account, folder, filter, sort, revision) {
            calls = calls.concat([{account, folder, filter, sort, revision}]);
        }
    }
    Component { id: factory; Mail.MailboxQuery {} }
    TestCase {
        name: "BackendQueryLifecycle"
        when: windowShown
        property var query: null
        property var publications: []
        function init() {
            client.enabled = false; client.calls = []; publications = [];
            query = createTemporaryObject(factory, fixture, {client, folder: "Inbox"});
            query.refreshed.connect(rows => { publications = publications.concat([rows]); });
            client.enabled = true;
            query.refresh();
            compare(client.calls.length, 1);
        }
        function test_scopeChangesRejectOldPages_data() {
            return [{tag: "filter", key: "filter", value: "Unread"},
                {tag: "sort", key: "sort", value: "Sender"},
                {tag: "account", key: "account", value: "work"}];
        }
        function test_scopeChangesRejectOldPages(row) {
            const stale = query.revision;
            query[row.key] = row.value;
            compare(client.calls.length, 2);
            compare(client.calls[1][row.key], row.value);
            client.mailboxFirstPage(stale, [{id: "stale"}]);
            client.mailboxLoaded(stale, [{id: "stale"}], true);
            compare(publications.length, 0);
            client.mailboxFirstPage(query.revision, [{id: "fresh"}]);
            compare(publications.length, 1);
            client.mailboxLoaded(query.revision, [{id: "fresh"}, {id: "second"}], true);
            compare(publications.length, 2);
            verify(!query.loading);
        }
        function test_refreshKeepsConfirmedViewUntilFullResult() {
            client.mailboxLoaded(query.revision, [{id: "old"}], true);
            query.refresh();
            client.mailboxFirstPage(query.revision, [{id: "partial"}]);
            compare(publications.length, 1);
            compare(query.messages[0].id, "old");
            client.mailboxLoaded(query.revision, [{id: "complete"}], true);
            compare(publications.length, 2);
            compare(query.messages[0].id, "complete");
        }
    }
}
