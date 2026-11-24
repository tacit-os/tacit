import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail

Item {
    width: 640; height: 480
    Mail.MailHtmlView {
        id: document
        width: parent.width
        html: "<p>New content</p><div data-tacit-quoted-history hidden><blockquote>Cited content</blockquote></div>"
        quotedHistoryExpanded: true
    }
    TestCase {
        name: "QuoteHairlineColor"
        when: windowShown
        function test_qmlMatchesTheNativeHeaderRule() {
            tryVerify(() => document.ready);
            const browser = findChild(document, "mailHtmlBrowser");
            tryVerify(() => findChild(document, "htmlQuoteHairline--0") !== null);
            const rule = findChild(document, "htmlQuoteHairline--0");
            const expected = Qt.alpha(K.Kit.tokens.inkMain, K.Kit.tokens.wash.hover + 0.02);
            compare(rule.color.r, expected.r);
            compare(rule.color.g, expected.g);
            compare(rule.color.b, expected.b);
            compare(rule.color.a, expected.a);
            compare(rule.width, 1);
            verify(rule.height > 0);
            let cssBorder = null;
            browser.runJavaScript("document.querySelector('[data-tacit-quoted-history]').style.borderInlineStart",
                1, value => cssBorder = value);
            tryVerify(() => cssBorder !== null);
            compare(cssBorder, "");
            document.quotedHistoryExpanded = false;
            tryVerify(() => findChild(document, "htmlQuoteHairline--0") === null);
        }
    }
}
