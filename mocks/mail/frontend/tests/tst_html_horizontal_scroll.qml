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
        name: "HtmlHorizontalScroll"
        when: windowShown
        function evaluate(browser, script) {
            let done = false, result;
            browser.runJavaScript(script, 1, value => {result = value; done = true;});
            tryVerify(() => done);
            return result;
        }
        function test_wheelReachesWideDocumentWithoutMovingReader_data() {
            return [{tag: "top", deep: false}, {tag: "scrolled-long-mail", deep: true}];
        }
        function test_wheelReachesWideDocumentWithoutMovingReader(row) {
            K.Kit.reducedMotion = true;
            const data = Fixture.initial("read");
            const mail = Store.find(data, "studio");
            mail.history = []; mail.files = []; mail.bodyParts = null;
            mail.bodyHtml = '<table style="width:1600px;min-width:1600px"><tr><td style="height:5000px">Wide newsletter</td></tr></table>';
            session.data = data;
            session.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const scroll = findChild(workspace, "readingScroll");
            verify(evaluate(browser, "document.scrollingElement.scrollWidth > innerWidth"));
            const revision = browser.documentRevision;
            if (row.deep) {
                scroll.movementStarted();
                scroll.contentY += 1200;
                waitForRendering(scroll);
            }
            const y = scroll.contentY;
            const sampleY = Math.max(40, -browser.mapToItem(scroll, 0, 0).y + 100);
            const point = browser.mapToItem(scroll, 40, sampleY);
            verify(point.y > 0 && point.y < scroll.height);
            mouseWheel(scroll, point.x, point.y, -120, 0);
            tryCompare({get x() { return evaluate(browser, "window.scrollX"); }}, "x", 120);
            compare(scroll.contentY, y);
            compare(browser.documentRevision, revision);
            const glide = findChild(workspace, "readingGlide");
            const gesturePoint = browser.mapToItem(glide, 40, sampleY);
            // Trackpads use pixel deltas and can include small diagonal drift.
            const gesture = {x: gesturePoint.x, y: gesturePoint.y,
                pixelDelta: {x: -64, y: 2}, angleDelta: {x: 0, y: 0}};
            verify(glide.routeHorizontalWheel(gesture));
            tryVerify(() => evaluate(browser, "window.scrollX") >= 64);
            compare(scroll.contentY, y);
            verify(!glide.routeHorizontalWheel({x: gesturePoint.x, y: gesturePoint.y,
                pixelDelta: {x: 1, y: -64}, angleDelta: {x: 0, y: 0}}));

            evaluate(browser, "window.scrollTo(64, 0)");
            mouseWheel(scroll, point.x, point.y, 120, 0);
            tryVerify(() => evaluate(browser, "window.scrollX") === 0);
        }
    }
}
