import QtQuick
import QtTest
import "../../frontend" as Mail

Item {
    width: 1720; height: 972
    Loader {
        id: workspaceLoader
        anchors.fill: parent
        sourceComponent: Mail.MailWorkspace { mailboxClient: testMailbox }
    }
    readonly property var workspace: workspaceLoader.item
    readonly property var session: workspace?.controller
    TestCase {
        name: "NavigationContract"
        when: windowShown
        function cleanupTestCase() {
            // WebEngine flushes pending JavaScript callbacks when its profile is
            // destroyed. Release the fixture while its QML engine is still alive.
            workspaceLoader.active = false;
            wait(0);
        }
        function test_searchAndRefreshKeepOpenDocumentAndLocalImages() {
            tryVerify(() => session.rows.some(row => row.id === "seed-rich-text"), 10000);
            session.act("select", {id: "seed-rich-text"});
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true, 10000);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const revision = browser.documentRevision;
            const field = findChild(workspace, "mailSearch");
            field.forceActiveFocus();
            for (const key of [Qt.Key_D, Qt.Key_E, Qt.Key_S, Qt.Key_I, Qt.Key_G, Qt.Key_N, Qt.Key_R, Qt.Key_U, Qt.Key_N, Qt.Key_D, Qt.Key_E])
                keyClick(key);
            tryVerify(() => session.data.search?.query === "designrunde"
                && session.rows.some(row => row.id === "seed-rich-text"), 10000);
            tryVerify(() => browser.searchMatchCount > 0);
            compare(findChild(workspace, "mailHtmlBrowser"), browser);
            compare(browser.documentRevision, revision);
            session.act("closeSearch");
            compare(session.ui.selected, "seed-rich-text");
            tryCompare(browser, "searchMatchCount", 0);
            const list = findChild(workspace, "messageList");
            tryVerify(() => {
                const index = session.rows.findIndex(row => row.id === "seed-rich-text");
                const item = list.view.itemAtIndex(index);
                if (!item) return false;
                const y = item.mapToItem(list.view, 0, 0).y;
                return y >= 0 && y + item.height <= list.view.height + 1;
            });
            session.folderQuery.refresh();
            tryCompare(session.folderQuery, "loading", false, 10000);
            compare(session.ui.selected, "seed-rich-text");
            compare(findChild(workspace, "mailHtmlBrowser"), browser);
            compare(browser.documentRevision, revision);
            let inlineLoaded = false;
            browser.runJavaScript("Array.from(document.images).some(image => image.complete && image.naturalWidth > 0 && image.src.startsWith('tacit-image://mail/'))",
                1, value => { inlineLoaded = value; });
            tryVerify(() => inlineLoaded);
        }
    }
}
