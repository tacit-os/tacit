import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store

Item {
    width: 1720; height: 972
    Mail.MailWorkspaceSession { id: session; reduceAction: Fixture.reduce; queryRows: Fixture.results }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "HtmlCacheProbeVisibility"
        when: windowShown
        function test_localImageProbeDoesNotHideHtmlBody() {
            K.Kit.reducedMotion = true;
            const data = Fixture.initial("read");
            Store.find(data, "studio").bodyHtml = "<p>Cached HTML body remains visible.</p>";
            session.data = data;
            session.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const surface = findChild(workspace, "htmlSurface-studio");
            const presentation = findChild(workspace, "htmlPresentation-studio");
            const progress = findChild(workspace, "htmlLoadProgress");
            const revision = browser.documentRevision;
            let inserted = false;
            // Keep a local image incomplete deterministically, without network access or sleeps.
            browser.runJavaScript("(() => { const img = document.createElement('img');"
                + " Object.defineProperty(img, 'currentSrc', {value: 'tacit-image://mail/cache-only-probe'});"
                + " Object.defineProperty(img, 'complete', {get: () => document.body.dataset.probeFinished === 'yes'});"
                + " document.body.append(img); return true; })()", 1, value => { inserted = value; });
            tryVerify(() => inserted);
            browser.bodyReady = false;
            browser.loaded = false;
            browser.loadingMessage = true;
            browser.fitDocument();
            tryVerify(() => surface.item.displayReady);
            verify(!browser.loaded, "The cache probe must still be pending");
            verify(browser.loadingMessage);
            compare(browser.imageCount, 0);
            verify(!progress.visible, "Local checks must not show remote-download progress");
            compare(surface.opacity, 1);
            verify(presentation.height > 0);
            compare(browser.documentRevision, revision);
            browser.runJavaScript("document.body.dataset.probeFinished = 'yes';", 1, () => {});
            tryVerify(() => browser.loaded);
            compare(surface.opacity, 1);
            compare(browser.documentRevision, revision);
        }
    }
}
