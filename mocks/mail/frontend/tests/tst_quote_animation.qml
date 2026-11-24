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
        name: "QuoteAnimation"
        when: windowShown
        function test_bothDirectionsKeepButtonAndDocument_data() {
            return [{tag:"text",html:false},{tag:"html",html:true}];
        }
        function test_bothDirectionsKeepButtonAndDocument(row) {
            K.Kit.reducedMotion = true;
            session.htmlCache.invalidate();
            session.readingState.quotedHistoryExpansion = ({});
            const data = Fixture.initial("read");
            const mail = Store.find(data,"studio");
            mail.history=[];mail.files=[];
            const quote = "> Cited text\n".repeat(30);
            const quoteHTML = "<blockquote>"+"<p>Cited text</p>".repeat(30)+"</blockquote>";
            mail.body="New content\n\n"+quote;
            mail.bodyHtml=row.html ? "<p>New content</p>"+quoteHTML : "";
            mail.bodyParts={text:[{kind:"content",content:"New content\n\n"},{kind:"quotedHistory",content:quote}]};
            if(row.html)mail.bodyParts.html=[{kind:"content",content:"<p>New content</p>"},{kind:"quotedHistory",content:quoteHTML}];
            session.data=data;session.act("select",{id:"studio"});
            if(row.html)tryVerify(()=>findChild(workspace,"mailHtmlBrowser")?.loaded===true);
            const button=findChild(workspace,"quotedHistory-studio");
            const body=findChild(workspace,"messageBody-studio");
            const surface=row.html?findChild(workspace,"htmlSurface-studio"):null;
            const browser=row.html?findChild(workspace,"mailHtmlBrowser"):null;
            const revision=browser?.documentRevision;
            waitForRendering(button);
            const position=button.mapToItem(workspace,0,0);
            const closed=body.height;
            K.Kit.reducedMotion=false;
            mouseClick(button);
            tryVerify(()=>body.height>closed+1);
            const duringOpen=body.height;
            tryVerify(()=>body.height>duringOpen+10);
            if(row.html)tryVerify(()=>!surface.item.quotedHistoryAnimating);
            wait(K.Kit.ms(K.Kit.motion("arriveSmall").ms));
            const opened=body.height;
            compare(button.mapToItem(workspace,0,0),position);
            mouseClick(button);
            tryVerify(()=>body.height<opened-1&&body.height>closed+1);
            tryCompare(body,"height",closed);
            compare(button.mapToItem(workspace,0,0),position);
            // Reversing an in-flight opening must still settle fully closed.
            mouseClick(button);
            tryVerify(()=>body.height>closed+1);
            mouseClick(button);
            tryCompare(body,"height",closed);
            compare(button.mapToItem(workspace,0,0),position);
            if(row.html){compare(surface.item,browser.parent);compare(browser.documentRevision,revision);}
            K.Kit.reducedMotion=true;
        }
    }
}
