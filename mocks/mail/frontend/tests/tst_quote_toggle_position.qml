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
        name: "QuoteTogglePosition"
        when: windowShown
        function test_actionStaysBeforeHistory_data() {
            return [{tag: "text", html: false}, {tag: "html", html: true}];
        }
        function test_actionStaysBeforeHistory(row) {
            K.Kit.reducedMotion = true;
            session.htmlCache.invalidate();
            const data = Fixture.initial("read");
            const mail = Store.find(data, "studio");
            mail.history = []; mail.files = [];
            const oldText = "> Cited content\n".repeat(15);
            const oldHTML = "<blockquote>" + "<p>Cited content</p>".repeat(15) + "</blockquote>";
            mail.body = "New content\n\n" + oldText;
            mail.bodyHtml = row.html ? "<p>New content</p>" + oldHTML : "";
            mail.bodyParts = {text: [{kind: "content", content: "New content\n\n"},
                {kind: "quotedHistory", content: oldText}]};
            if (row.html) mail.bodyParts.html = [{kind: "content", content: "<p>New content</p>"},
                {kind: "quotedHistory", content: oldHTML}];
            session.data = data; session.act("select", {id: "studio"});
            if (row.html) tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const action = findChild(workspace, "quotedHistory-studio");
            verify(!findChild(action, "quotedHistoryChevron-studio"));
            verify(action && action.visible);
            compare(action.tip, "Show clipped content");
            compare(action.symbol, "expand_more");
            compare(action.label, action.tip);
            compare(action.x + action.width / 2, Math.round(action.parent.width / 2));
            waitForRendering(action);
            const before = action.mapToItem(workspace, 0, 0);
            const body = findChild(workspace, "messageBody-studio");
            const collapsedHeight = body.height;
            mouseClick(action);
            compare(action.tip, "Hide expanded content");
            compare(action.symbol, "expand_less");
            compare(action.label, action.tip);
            tryVerify(() => body.height > collapsedHeight + 100);
            compare(action.mapToItem(workspace, 0, 0), before);
            if (row.html) {
                tryVerify(() => findChild(workspace, "htmlQuoteHairline-studio-0") !== null);
                const line = findChild(workspace, "htmlQuoteHairline-studio-0");
                verify(line.mapToItem(action, 0, 0).y - action.height >= K.Kit.tokens.space.m);
            } else {
                const content = findChild(workspace, "quotedHistoryBlock-studio");
                verify(content.mapToItem(action, 0, 0).y - action.height >= K.Kit.tokens.space.m);
            }
            mouseClick(action);
            tryCompare(body, "height", collapsedHeight);
            compare(action.mapToItem(workspace, 0, 0), before);
        }
    }
}
