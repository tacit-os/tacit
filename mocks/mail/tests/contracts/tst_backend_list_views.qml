import QtQuick
import QtTest
import "../../frontend/mail-store.js" as Store
import "../../frontend" as Mail

Item {
    readonly property var client: testMailbox
    SignalSpy { id: searchSpy; target: client; signalName: "searched" }
    SignalSpy { id: viewSpy; target: client; signalName: "mailboxLoaded" }
    Component { id: workspaceFactory; Mail.MailWorkspace { width: 1720; height: 972 } }
    TestCase {
        name: "BackendListViews"
        when: windowShown
        function test_explicitBackendContract() {
            for (const test of testListContract.cases) {
                viewSpy.clear();
                client.loadMailboxView(test.account, test.folder, test.filter, test.sort, 9200);
                tryCompare(viewSpy, "count", 1, 10000);
                const reply = viewSpy.signalArguments[0];
                verify(reply[2], test.name);
                const raw = reply[1].filter(row => row.id.startsWith("query-"));
                compare(raw.map(row => row.id).join(","), test.rows.map(row => row.id).join(","), test.name);
                raw.forEach((row, index) => {
                    const expected = test.rows[index];
                    compare(row.folder_message_count, expected.count, test.name);
                    compare(row.folder_starred, expected.starred, test.name);
                    compare(row.folder_other_starred, expected.other_starred, test.name);
                });
                let state = Store.emptyMailbox();
                state.ui = Object.assign({}, state.ui, {folder: test.folder, account: test.account || "All accounts", filter: test.filter, sort: test.sort});
                state = Store.replaceBackendView(state, Store.mailboxRows([], raw), Store.backendViewKey(test.folder, test.account, test.filter, test.sort));
                compare(Store.results(state).map(row => row.id).join(","), test.rows.map(row => row.id).join(","), test.name);
            }
        }
        function test_explicitSearchAndCounters() {
            for (const test of testListContract.searches) {
                searchSpy.clear(); client.search(test.term, 9100);
                tryCompare(searchSpy, "count", 1, 10000);
                verify(searchSpy.signalArguments[0][2]);
                let actual = searchSpy.signalArguments[0][1].map(row => row.id);
                if (test.native_scope === "fixture") actual = actual.filter(id => id.startsWith("query-"));
                const expected = (test.native_prefix || []).concat(test.ids);
                compare(actual.join(","), expected.join(","), test.term);
            }
            viewSpy.clear(); client.loadMailboxCounts(-9200);
            tryCompare(viewSpy, "count", 1, 10000);
            verify(viewSpy.signalArguments[0][2]);
            const actual = viewSpy.signalArguments[0][1].filter(row => row.account_id.startsWith("query-"));
            compare(actual.length, testListContract.counts.length);
            for (const expected of testListContract.counts) {
                const row = actual.find(row => row.account_id === expected.account_id && row.mailbox === expected.mailbox);
                verify(!!row); compare(row.total, expected.total); compare(row.unread, expected.unread);
            }
        }
        function test_closingSearchKeepsOlderThreadMessageAndRevealsRepresentative() {
            const workspace = createTemporaryObject(workspaceFactory, parent, {mailboxClient: client});
            verify(workspace);
            const session = workspace.controller;
            tryVerify(() => session.folderQuery.displayedKey && !session.folderQuery.loading, 10000);
            verify(!!session.data.backendViews);
            session.act("search", {text: "Dusk"});
            tryVerify(() => session.data.search?.complete && session.rows.some(row => row.id === "seed-01"), 10000);
            session.act("select", {id: "seed-01"});
            tryVerify(() => session.selected?.id === "seed-01", 10000);
            const conversation = session.selected.backendConversation;
            session.act("closeSearch");
            compare(session.ui.selected, "seed-01");
            verify(!!Store.find(session.data, "seed-01"));
            tryVerify(() => session.rows.some(row => row.backendConversation === conversation), 10000);
            const representatives = session.rows.filter(row => row.backendConversation === conversation);
            compare(representatives.length, 1);
            verify(representatives[0].folderMessageCount > 1);
            const list = findChild(workspace, "messageList");
            tryVerify(() => {
                const index = session.rows.findIndex(row => row.id === representatives[0].id);
                const item = list.view.itemAtIndex(index);
                if (!item) return false;
                const y = item.mapToItem(list.view, 0, 0).y;
                return y >= 0 && y + item.height <= list.view.height + 1;
            });
            compare(session.ui.selected, "seed-01");
        }
    }
}
