import QtQuick
import QtTest
import ".." as Mail

Item {
    width: 800; height: 600
    Mail.MailHtmlView {
        id: html
        width: 600
        html: "<html><body><p>Needle and a second NEEDLE. A different word.</p></body></html>"
    }
    QtObject {
        id: client
        property int requests: 0
        signal searchFirstPage(int revision, var messages)
        signal searched(int revision, var messages, bool ok)
        function search(term, revision) { ++requests; }
    }
    Mail.MailSearchQuery {
        id: query
        client: client
        property var hits: []
        property bool complete: false
        onPartial: messages => { hits = messages; complete = false; }
        onCompleted: (messages, ok) => { if (ok) { hits = messages; complete = true; } }
    }
    TestCase {
        name: "LiveSearchHighlight"
        when: windowShown
        function test_firstPageBeforeCompleteAndStaleRepliesIgnored() {
            query.term = "Prüf"; query.active = true;
            const before = client.requests;
            tryCompare(client, "requests", before + 1);
            const revision = query.revision;
            client.searchFirstPage(revision, [{id: "first"}]);
            compare(query.hits.length, 1);
            verify(query.loading); verify(!query.complete);
            query.term = "another";
            client.searched(revision, [{id: "stale"}], true);
            compare(query.hits[0].id, "first");
            client.searched(query.revision, [{id: "fresh"}], true);
            compare(query.hits[0].id, "fresh");
            verify(query.complete); verify(!query.loading);
            query.active = false;
        }
        function test_highlightOpenDocumentWithoutReload() {
            tryCompare(html, "ready", true);
            const browser = findChild(html, "mailHtmlBrowser");
            const revision = browser.documentRevision;
            html.searchTerm = "eed";
            tryCompare(html, "searchMatchCount", 2);
            html.searchTerm = "different";
            tryCompare(html, "searchMatchCount", 1);
            html.searchTerm = "";
            tryCompare(html, "searchMatchCount", 0);
            compare(browser.documentRevision, revision);
        }
    }
}
