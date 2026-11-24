import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store

Item {
    width: 1720; height: 972
    QtObject {
        id: clientProbe
        property int ticket: 0
        signal imagePoliciesChanged()
        signal messageImagesAllowed(string id, bool ok)
        signal imageStateLoaded(string id, int ticket, var result, bool ok)
        function inspectImages(id) { return ++ticket; }
    }
    Mail.MailWorkspaceSession { id: session; reduceAction: Fixture.reduce; queryRows: Fixture.results }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "ImagePromptState"
        when: windowShown
        function test_promptUsesFreshManifestBeforeLocalProbesFinish_data() {
            return [{tag: "missing", cached: false, allowed: false, prompt: true},
                {tag: "cached", cached: true, allowed: false, prompt: false},
                {tag: "automatic", cached: false, allowed: true, prompt: false}];
        }
        function test_promptUsesFreshManifestBeforeLocalProbesFinish(row) {
            K.Kit.reducedMotion = true;
            session.htmlCache.invalidate();
            const data = Fixture.initial("read");
            Store.find(data, "studio").bodyHtml = "<p>Local HTML body</p>";
            session.data = data; session.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const surface = findChild(workspace, "htmlSurface-studio");
            const button = findChild(workspace, "loadImages-studio");
            surface.item.mailboxClient = clientProbe;
            let inserted = false;
            browser.runJavaScript("(() => { const img = document.createElement('img');"
                + " Object.defineProperty(img, 'currentSrc', {value: 'https://example.invalid/image.png'});"
                + " Object.defineProperty(img, 'src', {get: () => 'data:', set: () => {}});"
                + " Object.defineProperty(img, 'complete', {get: () => document.body.dataset.finished === 'yes'});"
                + " document.body.append(img); return true; })()", 1, value => { inserted = value; });
            tryVerify(() => inserted);
            browser.loaded = false; browser.loadingMessage = true;
            browser.inspectImageState(["https://example.invalid/image.png"]);
            clientProbe.imageStateLoaded("studio", browser.imageStateTicket, {
                cached_images: row.cached ? [{url: "https://example.invalid/image.png"}] : [],
                origin_allowed: row.allowed
            }, true);
            browser.fitDocument();
            tryVerify(() => surface.item.imagePromptReady);
            verify(!browser.loaded, "The per-image check remains pending");
            compare(button.visible, row.prompt);
            compare(surface.opacity, 1);
            // Permission changes invalidate any earlier status response.
            browser.refreshPermissions();
            clientProbe.imageStateLoaded("studio", clientProbe.ticket, {cached_images: [], origin_allowed: false}, true);
            if (!row.prompt) verify(!surface.item.hasExternalImages);
            browser.runJavaScript("document.body.dataset.finished = 'yes';", 1, () => {});
            tryVerify(() => browser.loaded);
        }
    }
}
