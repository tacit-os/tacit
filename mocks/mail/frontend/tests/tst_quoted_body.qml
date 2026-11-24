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
        name: "QuotedBody"
        when: windowShown
        function init() { K.Kit.reducedMotion = true; session.htmlCache.invalidate(); }
        function prepare(html) {
            const data = Fixture.initial("read");
            const row = Store.find(data, "studio");
            row.body = "New content\n\n> Old content";
            row.bodyParts = {text: [{kind: "content", content: "New content\n\n"},
                {kind: "quotedHistory", content: "> Old content"}]};
            row.history = [];
            if (html) {
                row.bodyHtml = "<p>New content</p><blockquote>Old content</blockquote>";
                row.bodyParts.html = [{kind: "content", content: "<p>New content</p>"},
                    {kind: "quotedHistory", content: "<blockquote>Old content</blockquote>"}];
            } else row.bodyHtml = "";
            session.data = data;
            session.act("select", {id: "studio"});
        }
        function test_plainHistoryToggleAndOriginalPreserved() {
            prepare(false);
            const action = findChild(workspace, "quotedHistory-studio");
            verify(action && action.visible);
            compare(action.tip, "Show clipped content");
            let paragraphs = [];
            function collect(item) {
                if (item.objectName === "plainMailParagraph" && item.visible) paragraphs.push(item.text);
                for (const child of item.children ?? []) collect(child);
            }
            collect(workspace);
            verify(!paragraphs.join(" ").includes("Old content"));
            action.activated();
            compare(action.tip, "Hide expanded content");
            paragraphs = []; collect(workspace);
            verify(paragraphs.join(" ").includes("Old content"));
            compare(Store.find(session.data, "studio").body, "New content\n\n> Old content");
        }
        function test_htmlToggleDoesNotReloadOrLoseRenderedView() {
            prepare(true);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const surface = findChild(workspace, "htmlSurface-studio");
            const lease = surface.lease;
            const revision = browser.documentRevision;
            let imageAdded = false;
            browser.runJavaScript("(() => { const img = document.createElement('img'); img.id = 'quote-test-image';"
                + " img.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';"
                + " img.dataset.retained = 'yes'; document.body.firstElementChild.append(img); return true; })()",
                1, value => imageAdded = value);
            tryVerify(() => imageAdded);
            const action = findChild(workspace, "quotedHistory-studio");
            function hidden(expected) {
                let result = null;
                browser.runJavaScript("(() => { const q = document.querySelector('[data-tacit-quoted-history]');"
                    + " return !!q && getComputedStyle(q).display === 'none'; })()", 1, value => result = value);
                tryCompare({get value() {return result;}}, "value", expected);
            }
            hidden(true);
            action.activated();
            hidden(false);
            // A background flag refresh must not collapse or replace the open body.
            const refreshed = Object.assign({}, session.data);
            const row = Object.assign({}, Store.find(session.data, "studio"), {unread: false});
            session.data = Store.upsertMessages(refreshed, [row]);
            compare(action.tip, "Hide expanded content");
            hidden(false);
            compare(findChild(workspace, "htmlSurface-studio").lease, lease);
            compare(browser.documentRevision, revision);
            action.activated();
            hidden(true);
            compare(surface.lease, lease);
            compare(browser.documentRevision, revision);
            verify(browser.loaded);
            let imageRetained = false;
            browser.runJavaScript("document.getElementById('quote-test-image')?.dataset.retained === 'yes'",
                1, value => imageRetained = value);
            tryVerify(() => imageRetained);
        }
        function test_noQuoteHasNoAction() {
            session.data = Fixture.initial("read");
            session.act("select", {id: "studio"});
            verify(!findChild(workspace, "quotedHistory-studio").visible);
        }
    }
}
