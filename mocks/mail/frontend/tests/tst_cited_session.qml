import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store

Item {
    id: fixture
    width: 1720; height: 972
    Mail.MailWorkspaceSession { id: session; reduceAction: Fixture.reduce; queryRows: Fixture.results }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    Component { id: freshReader; Mail.MailReadingState { data: Store.emptyMailbox() } }
    TestCase {
        name: "CitedSession"
        when: windowShown
        function test_remembersEachMessage_data() {
            return [{tag: "text", html: false}, {tag: "html", html: true}];
        }
        function test_remembersEachMessage(row) {
            K.Kit.reducedMotion = true;
            const data = Fixture.initial("read");
            for (const id of ["studio", "mara"]) {
                const mail = Store.find(data, id);
                mail.history = []; mail.files = [];
                mail.body = "New content\n\n> Cited content";
                mail.bodyHtml = row.html ? "<p>New content</p><blockquote>Cited content</blockquote>" : "";
                mail.bodyParts = {text: [{kind: "content", content: "New content\n\n"},
                    {kind: "quotedHistory", content: "> Cited content"}]};
                if (row.html) mail.bodyParts.html = [{kind: "content", content: "<p>New content</p>"},
                    {kind: "quotedHistory", content: "<blockquote>Cited content</blockquote>"}];
            }
            session.data = data;
            session.act("select", {id: "studio"});
            let action = findChild(workspace, "quotedHistory-studio");
            compare(action.tip, "Show clipped content");
            action.activated();
            compare(action.tip, "Hide expanded content");
            session.act("select", {id: "mara"});
            tryVerify(() => findChild(workspace, "quotedHistory-mara") !== null);
            compare(findChild(workspace, "quotedHistory-mara").tip, "Show clipped content");
            // Render-cache eviction is independent of this per-session preference.
            session.htmlCache.invalidate();
            session.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "quotedHistory-studio") !== null);
            action = findChild(workspace, "quotedHistory-studio");
            compare(action.tip, "Hide expanded content");
            action.activated();
            session.act("select", {id: "mara"});
            session.act("select", {id: "studio"});
            tryVerify(() => findChild(workspace, "quotedHistory-studio") !== null);
            compare(findChild(workspace, "quotedHistory-studio").tip, "Show clipped content");
        }
        function test_newSessionStartsCollapsed() {
            const reader = freshReader.createObject(fixture);
            reader.setQuotedHistoryExpanded("mail-a", true);
            verify(reader.quotedHistoryExpansion["mail-a"]);
            reader.destroy();
            const restarted = freshReader.createObject(fixture);
            verify(!restarted.quotedHistoryExpansion["mail-a"]);
            restarted.destroy();
        }
    }
}
