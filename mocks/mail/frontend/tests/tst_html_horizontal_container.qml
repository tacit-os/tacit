import QtQuick
import QtTest
import ".." as Mail

Item {
    width: 600; height: 500
    Mail.MailHtmlView {
        id: html
        width: parent.width
        height: implicitHeight
        html: '<table style="width:1600px;min-width:1600px"><tr><td style="height:200px">Wide mail</td></tr></table>'
    }
    TestCase {
        name: "HtmlHorizontalContainer"
        when: windowShown
        function test_browserUsesContentWidthAndQmlClipsIt() {
            tryVerify(() => html.ready);
            const viewport = findChild(html, "htmlHorizontalViewport");
            const browser = findChild(html, "mailHtmlBrowser");
            tryVerify(() => viewport.contentWidth >= 1600);
            compare(viewport.width, 600);
            compare(browser.width, viewport.contentWidth);
            verify(viewport.clip);
            const revision = browser.documentRevision;
            html.scrollHorizontally(120);
            compare(viewport.contentX, 120);
            html.scrollHorizontally(100000);
            compare(viewport.contentX, viewport.contentWidth - viewport.width);
            html.scrollHorizontally(-100000);
            compare(viewport.contentX, 0);
            compare(browser.documentRevision, revision);
        }
    }
}
