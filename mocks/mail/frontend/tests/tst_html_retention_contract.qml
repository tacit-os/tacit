import QtQuick
import QtTest
import ".." as Mail

Item {
    width: 800; height: 600
    Mail.MailHtmlCache { id: cache }
    Item { id: owner; width: 600; height: 500 }
    TestCase {
        name: "HtmlRetentionContract"
        when: windowShown
        function test_threeDocumentsSurviveNavigationAndFourthEvictsOldest() {
            const retained = [];
            for (let i = 0; i < 3; ++i) {
                const slot = cache.acquire("mail-" + i, {html: "<p>Document " + i + "</p>"}, owner);
                tryCompare(slot, "status", Loader.Ready);
                tryCompare(slot.item, "ready", true);
                retained.push({slot, item: slot.item, revision: findChild(slot.item, "mailHtmlBrowser").documentRevision});
                cache.release(slot, owner);
            }
            compare(cache.count, 3);
            // Revisit every document with an updated search term, as folder/search navigation does.
            for (let i = 0; i < 3; ++i) {
                const slot = cache.acquire("mail-" + i,
                    {html: "<p>Document " + i + "</p>", searchTerm: "Document"}, owner);
                compare(slot, retained[i].slot);
                compare(slot.item, retained[i].item);
                tryCompare(slot.item, "searchMatchCount", 1);
                compare(findChild(slot.item, "mailHtmlBrowser").documentRevision, retained[i].revision);
                cache.release(slot, owner);
            }
            const fourth = cache.acquire("mail-3", {html: "<p>Fourth document</p>"}, owner);
            tryCompare(fourth, "status", Loader.Ready);
            tryCompare(fourth.item, "ready", true);
            cache.release(fourth, owner);
            compare(cache.count, 3);
            verify(!cache.slots.some(slot => slot.messageKey === "mail-0"));
            verify(cache.slots.some(slot => slot === retained[1].slot));
            verify(cache.slots.some(slot => slot === retained[2].slot));
            cache.invalidate();
            compare(cache.count, 0);
        }
    }
}
