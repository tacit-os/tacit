import QtQuick
import QtTest

Item {
    SignalSpy { id: pages; target: testMailbox; signalName: "mailboxLoaded" }
    TestCase {
        name: "NativeGmailCategories"
        when: windowShown
        property int revision: 9400
        function query(category) {
            const ticket = ++revision;
            pages.clear();
            testMailbox.loadMailboxView("category-transport", "Inbox", "All mail", "Newest first", ticket, "", category);
            tryVerify(() => pages.signalArguments.some(reply => reply[0] === ticket), 10000);
            const reply = pages.signalArguments.find(reply => reply[0] === ticket);
            verify(reply[2]);
            return reply[1];
        }
        function test_allFourCategoriesLoadBeyondFirstPage() {
            for (const category of ["CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES"]) {
                const ticket = ++revision;
                pages.clear();
                testMailbox.loadMailboxView("category-pages", "Inbox", "All mail", "Newest first", ticket, "", category);
                tryVerify(() => pages.signalArguments.some(reply => reply[0] === ticket), 10000);
                const reply = pages.signalArguments.find(reply => reply[0] === ticket);
                verify(reply[2]);
                compare(reply[1].length, 105);
                compare(new Set(reply[1].map(row => row.id)).size, 105);
                verify(reply[1].every(row => row.gmail_labels.includes(category)));
            }
        }
        function test_categoryParameterReachesRealMaild() {
            const promotion = "category-transport-promotion";
            const primary = "category-transport-primary";
            compare(query("CATEGORY_PROMOTIONS").map(row => row.id).join(","), promotion);
            compare(query("CATEGORY_PERSONAL").map(row => row.id).join(","), primary);
            compare(query("CATEGORY_SOCIAL").length, 0);
            const all = query("");
            verify(all.some(row => row.id === promotion)); verify(all.some(row => row.id === primary));
        }
    }
}
