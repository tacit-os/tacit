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
    Component { id: readingStateFactory; Mail.MailReadingState { data: Store.emptyMailbox() } }
    TestCase {
        name: "ThreadScrollSession"
        when: windowShown
        function init() {
            session.threadScrollPositions = new Map();
            session.messageExpansion = ({});
            session.htmlCache.invalidate();
        }
        function setupLongThread(html) {
            K.Kit.reducedMotion = true;
            const data = Fixture.initial("read");
            const mail = Store.find(data,"mara");
            mail.body = "Long latest message.\n\n".repeat(100);
            mail.bodyHtml = html ? "<p>Long latest message.</p>".repeat(100) : "";
            mail.history[0].body = "Earlier message context.\n\n".repeat(25);
            mail.history[0].expanded = true;
            session.data = data;
            session.act("select",{id:"studio"});
            waitForRendering(workspace);
            session.threadScrollPositions = new Map();
            session.act("select",{id:"mara"});
        }
        function test_firstOpenShowsLatestHeader_data() {
            return [{tag:"plain",html:false},{tag:"html",html:true}];
        }
        function test_firstOpenShowsLatestHeader(row) {
            setupLongThread(row.html);
            const scroll = findChild(workspace,"readingScroll");
            const header = findChild(workspace,"messageHeader-mara");
            if (row.html) tryVerify(()=>findChild(workspace,"mailHtmlBrowser")?.loaded === true);
            tryVerify(()=>scroll.contentHeight>scroll.height*2);
            waitForRendering(scroll);
            tryVerify(()=>Math.abs(header.mapToItem(scroll,0,0).y-K.Kit.tokens.space.l)<1);
        }
        function test_returnRestoresUserPosition_data() {
            return [{tag:"plain",html:false},{tag:"html",html:true}];
        }
        function test_returnRestoresUserPosition(row) {
            setupLongThread(row.html);
            const scroll = findChild(workspace,"readingScroll");
            if (row.html) tryVerify(()=>findChild(workspace,"mailHtmlBrowser")?.loaded === true);
            tryVerify(()=>scroll.contentHeight>scroll.height*2);
            waitForRendering(scroll);
            scroll.movementStarted();
            scroll.contentY = 620;
            const saved = scroll.contentY;
            session.act("select",{id:"studio"});
            waitForRendering(scroll);
            session.act("select",{id:"mara"});
            tryCompare(scroll,"contentY",saved);
            // Metadata refreshes must not restart opening-position behavior.
            const updated = Object.assign({}, Store.find(session.data,"mara"),{unread:true});
            session.data = Store.upsertMessages(session.data,[updated]);
            waitForRendering(scroll);
            compare(scroll.contentY,saved);
        }
        function test_positionsAreSessionLocal() {
            const first = readingStateFactory.createObject(fixture);
            first.threadScrollPositions.set("account/thread",360);
            first.destroy();
            const second = readingStateFactory.createObject(fixture);
            compare(second.threadScrollPositions.size,0);
            second.destroy();
        }
        function test_sameConversationSharesPositionAcrossListRows() {
            setupLongThread(false);
            const original = Store.find(session.data,"mara");
            const first = Object.assign({},original,{backendAccount:"work",backendConversation:"shared"});
            const other = Object.assign({},Store.find(session.data,"studio"),{
                backendAccount:"work",backendConversation:"shared",body:original.body,history:original.history
            });
            session.data = Store.upsertMessages(session.data,[first,other]);
            const scroll = findChild(workspace,"readingScroll");
            waitForRendering(scroll);
            scroll.movementStarted();scroll.contentY=620;
            session.act("select",{id:"studio"});
            waitForRendering(scroll);
            compare(scroll.contentY,620);
            compare(session.threadScrollPositions.get("work\u0000shared"),620);
        }
        function test_userScrollDuringHtmlArrivalIsNotOverridden() {
            setupLongThread(true);
            const scroll = findChild(workspace,"readingScroll");
            scroll.movementStarted();scroll.contentY=100;
            tryVerify(()=>findChild(workspace,"mailHtmlBrowser")?.loaded === true);
            compare(scroll.contentY,100);
        }

        function test_wheelScrollIsRemembered() {
            setupLongThread(false);
            const scroll = findChild(workspace,"readingScroll");
            tryVerify(()=>Math.abs(findChild(workspace,"messageHeader-mara").mapToItem(scroll,0,0).y-K.Kit.tokens.space.l)<1);
            waitForRendering(scroll);
            const before = scroll.contentY;
            mouseWheel(scroll,scroll.width/2,scroll.height/2,0,-120);
            tryVerify(()=>scroll.contentY>before);
            tryVerify(()=>!findChild(workspace,"readingGlide").active);
            const saved = scroll.contentY;
            session.act("select",{id:"studio"});
            waitForRendering(scroll);
            session.act("select",{id:"mara"});
            tryCompare(scroll,"contentY",saved);
        }
        function test_scrollbarPositionIsRemembered() {
            setupLongThread(false);
            const scroll = findChild(workspace,"readingScroll");
            waitForRendering(scroll);
            const bar = findChild(workspace,"readingScrollBar");
            bar.previewState = "dragging";
            scroll.contentY = 440;
            bar.previewState = "";
            session.act("select",{id:"studio"});
            waitForRendering(scroll);
            session.act("select",{id:"mara"});
            tryCompare(scroll,"contentY",440);
        }

        function test_historicalDraftHeaderAndPositionReturn() {
            setupLongThread(false);
            session.reply("Reply",false,"lena-first");
            const scroll = findChild(workspace,"readingScroll");
            const editor = findChild(workspace,"mailEditor");
            tryVerify(()=>editor?.visible === true);
            tryVerify(()=>Math.abs(editor.mapToItem(scroll,0,0).y-K.Kit.tokens.space.l)<1);
            scroll.movementStarted();scroll.contentY = 200;
            const saved = scroll.contentY;
            session.act("select",{id:"studio"});
            waitForRendering(scroll);
            session.act("select",{id:"mara"});
            tryCompare(scroll,"contentY",saved);
        }
    }
}
