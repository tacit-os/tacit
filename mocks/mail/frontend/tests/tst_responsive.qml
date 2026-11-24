import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store

Item {
    id:fixture
    width:1720;height:972
    Mail.MailWorkspaceSession {id:state; reduceAction: Fixture.reduce; queryRows: Fixture.results}
    Mail.MailWorkspace {id:workspace;anchors.fill:parent;controller:state}
    TestCase {
        name:"MailResponsive"
        when:windowShown
        function init(){fixture.width=1720;fixture.height=972;state.messageExpansion={};state.threadScrollPositions=new Map();state.data=Fixture.initial("read");K.Kit.reducedMotion=true;workspace.compactReading=true;wait(40);}
        function item(name){var result=findChild(workspace,name);verify(result!==null,"Missing "+name);return result;}
        function inside(control){var at=control.mapToItem(workspace,0,0);verify(at.x>=-1&&at.y>=-1,control.objectName+" starts outside the window at "+at);verify(at.x+control.width<=workspace.width+1&&at.y+control.height<=workspace.height+1,control.objectName+" ends outside the window");}
        function test_sizes_data(){return [
            {tag:"minimum",w:400,h:600},
            {tag:"narrow",w:560,h:500},
            {tag:"short",w:820,h:400},
            {tag:"medium",w:1024,h:768},
            {tag:"wide",w:1720,h:972}
        ];}
        function test_sizes(data){
            fixture.width=data.w;fixture.height=data.h;wait(60);
            const scroll = item("readingScroll");
            scroll.contentY = 0;
            inside(item("readerPane"));inside(item("messageSubject"));inside(item("readingScroll"));
            verify(item("readingScroll").height>0,"Reading area must retain visible space");
            var size=item("messageSubject").font.pixelSize;
            compare(size,K.Kit.tokens.size.headline,"Window resizing must not scale typography");
            state.reply("Reply all",false);wait(80);
            const to = item("draftTo");
            scroll.contentY = Math.max(0, Math.min(to.mapToItem(scroll.contentItem, 0, 0).y,
                scroll.contentHeight - scroll.height));
            inside(item("draftTo"));
            verify(item("draftBody").width>0,"Body editor must have usable width");
            var editor=item("mailEditor"), body=item("draftBody");
            var footer=item("editorFooter");
            if (footer.mapToItem(scroll,0,footer.height).y>scroll.height)
                scroll.contentY=Math.max(0,scroll.contentHeight-scroll.height);
            inside(item("editorFooter"));inside(item("sendDraft"));
            verify(body.width<=editor.width+1,"The body must not exceed its reading column");
            verify(body.input.width<=body.width+1,"Text wrapping must use the actual body width");
        }
        function test_compactNavigation(){
            fixture.width=560;fixture.height=600;wait(50);
            verify(!item("inboxPane").visible);verify(item("readerPane").visible);
            var back=item("backToInbox");mouseClick(back,back.width/2,back.height/2);wait(50);
            verify(item("inboxPane").visible);verify(!item("readerPane").visible);
            inside(item("mailSearch"));inside(item("newMessage"));
            verify(!item("searchFilter").visible);
            var list=item("messageList"),row=list.view.itemAtIndex(1);verify(row!==null);
            const selectedId = row.messageId;
            mouseClick(row,row.width/2,row.height/2);wait(50);
            compare(state.ui.selected,selectedId);verify(item("readerPane").visible);verify(!item("inboxPane").visible);
            fixture.width=1720;wait(50);verify(item("inboxPane").visible);verify(item("readerPane").visible);
        }
        function test_composeStartsAtRecipients(){
            fixture.width=560;fixture.height=600;state.act("new");wait(80);
            compare(item("readingScroll").contentY,0);
            inside(item("draftFrom"));inside(item("draftTo"));inside(item("draftSubject"));
        }
        function test_narrowSettingsAndSetup(){
            fixture.width=560;fixture.height=600;state.act("settings");wait(60);
            var columns=item("settingsColumns"), scroll=item("settingsScroll");
            compare(columns.columns,1);compare(scroll.contentWidth,scroll.width);
            var at=columns.mapToItem(workspace,0,0);
            verify(at.x>=0&&at.x+columns.width<=workspace.width+1,"Settings must not overflow horizontally");
            state.act("setup");wait(60);inside(item("provider-Google"));inside(item("provider-Another provider"));
        }
        function test_setupProviderColumn(){
            fixture.width=1720;fixture.height=972;
            state.data=Store.emptyMailbox();
            state.act("setup");
            const content=item("setupContent");
            const google=item("provider-Google");
            const other=item("provider-Another provider");
            const back=item("setupBackToMail");
            tryCompare(content,"width",560);
            verify(!back.visible);
            const left=content.mapToItem(workspace,0,0).x;
            for (const row of [google,other]) {
                const label=findChild(row,"providerName");
                compare(label.mapToItem(workspace,0,0).x,left);
                compare(row.width,content.width);
            }
            const account={id:"personal",name:"Personal",email:"mail@example.test",provider:"managed-imap"};
            state.data=Object.assign({},state.data,{accounts:[account]});
            tryCompare(back,"visible",true);
            state.data=Object.assign({},state.data,{accounts:[Object.assign({},account,{provider:"offline-imap"})]});
            tryCompare(back,"visible",false);
        }
        function test_setupProviderHover(){
            fixture.width=1320;fixture.height=780;
            state.act("setup");
            const row=item("provider-Google");
            const marker=findChild(row,"providerMarker");
            mouseMove(row,row.width/2,row.height/2);
            tryCompare(marker,"visible",true);
            compare(marker.width,2);
            mousePress(row,row.width/2,row.height/2);
            tryCompare(marker,"width",3);
            mouseMove(workspace,5,5);
            mouseRelease(workspace,5,5);
            tryCompare(marker,"width",2);
        }
        function test_longSubject(){
            fixture.width=560;fixture.height=600;
            var data=Store.copy(state.data);Store.find(data,"mara").subject="A much longer subject that needs several lines in a narrow window and must never overlap the message toolbar or the thread";state.data=data;wait(60);
            var subject=item("messageSubject"), scroll=item("readingScroll");
            // This checks title geometry; initial thread targeting is tested separately.
            scroll.movementStarted();
            scroll.contentY = 0;
            var titleBottom=subject.mapToItem(workspace,0,subject.height).y;
            var firstMessage=item("history-lena-first");
            verify(firstMessage.mapToItem(workspace,0,0).y>=titleBottom,"Thread must follow the full wrapped subject");
            inside(subject);inside(scroll);
        }
    }
}
