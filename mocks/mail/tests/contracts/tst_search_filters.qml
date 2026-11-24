import QtQuick
import QtTest

Item {
    SignalSpy { id: responses; target: testMailbox; signalName: "searched" }
    TestCase {
        name: "NativeSearchFilters"
        when: windowShown
        property int revision: 9700
        function result(filter) {
            responses.clear();
            const ticket = ++revision;
            testMailbox.search("", ticket, filter);
            tryVerify(() => responses.signalArguments.some(reply => reply[0] === ticket), 10000);
            const reply = responses.signalArguments.find(reply => reply[0] === ticket);
            verify(reply[2]);
            return reply[1];
        }
        function test_searchFilterAppliesToEveryPage() {
            const rows = result("All mail");
            compare(rows.filter(row => row.account_id === "category-pages").length, 420);
            compare(new Set(rows.map(row => row.id)).size, rows.length);
            for (let i = 1; i < rows.length; ++i)
                verify(rows[i - 1].date > rows[i].date || rows[i - 1].date === rows[i].date && rows[i - 1].id > rows[i].id);
            for (const filter of ["Unread", "Starred", "With attachments"]) {
                const filtered = result(filter);
                verify(filtered.length > 0);
                compare(filtered.filter(row => row.account_id === "category-pages").length, 0);
                verify(filtered.every(row => filter === "Unread" ? row.unread
                    : filter === "Starred" ? row.flagged : row.attachments.length > 0));
            }
            compare(result("All mail").length, rows.length);
        }
    }
}
