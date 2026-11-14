import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store

Item {
    width:1720;height:972
    Mail.MailWorkspaceSession {id:state; reduceAction: Fixture.reduce}
    Mail.MailWorkspace {id:workspace;anchors.fill:parent;controller:state}
    TestCase {
        name:"MailFrontend"
        when:windowShown
        function init(){state.data=Fixture.initial("read");K.Kit.reducedMotion=true;wait(30);}
        function keyClicks(text){for(var i=0;i<text.length;i++)keyClick(text[i]);}
        function button(name){var found=findChild(workspace,name);verify(found!==null,"Missing "+name);return found;}
        function click(name){var b=button(name);mouseClick(b,b.width/2,b.height/2);wait(30);}
        function test_selectMessage(){var list=button("messageList");var row=list.view.itemAtIndex(1);verify(row!==null);mouseClick(row,row.width/2,row.height/2);compare(state.ui.selected,"studio");compare(state.selected.unread,false);}
        function test_replyKeepsDraft(){click("replyAll");compare(state.ui.view,"draft");verify(state.draft.showCc);verify(button("archive").visible);verify(!findChild(workspace,"keepDraft"));state.act("select",{id:"studio"});state.act("select",{id:"mara"});compare(state.ui.view,"draft");}
        function test_newMessageTyping(){click("newMessage");compare(state.ui.view,"compose");var to=button("draftTo");to.input.forceActiveFocus();keyClicks("anna.richter@example.net");compare(state.draft.to,"anna.richter@example.net");var body=button("draftBody");body.input.forceActiveFocus();keyClicks("A local message");compare(state.draft.body,"A local message");verify(state.canSend);click("sendDraft");compare(state.data.jobs.length,1);state.act("undoSend");compare(state.ui.view,"compose");compare(state.draft.body,"A local message");}
        function test_recipientSuggestionKeyboard(){
            click("newMessage");
            button("draftTo").input.forceActiveFocus();
            keyClicks("anna");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(state.draft.to, "a.richter@moss.example");
        }
        function test_archiveAndUndo(){click("archive");compare(Store.find(state.data,"mara").folder,"Archive");state.act("undo");compare(Store.find(state.data,"mara").folder,"Inbox");}
        function test_search(){var search=button("mailSearch");search.forceActiveFocus();keyClicks("palettes");compare(state.ui.query,"palettes");compare(state.rows.length,3);}
        function test_keyboardSelection(){var list=button("messageList");list.cursor=-1;list.forceActiveFocus();keyClick(Qt.Key_Down);wait(30);compare(state.ui.selected,"mara");keyClick(Qt.Key_Down);wait(30);compare(state.ui.selected,"studio");}
        function test_collapsedPreviewStaysNearSender(){
            var header=button("history-lena-first"), preview=button("collapsedPreview-lena-first");
            var position=preview.mapToItem(header,0,0);
            verify(preview.text.length>0);
            compare(preview.horizontalAlignment,Qt.AlignLeft);
            verify(position.x < header.width / 3,"Preview should start in the left third of the wide header");
        }
        function test_expandHistory(){click("history-lena-first");verify(state.selected.history[0].expanded);click("history-lena-first");verify(!state.selected.history[0].expanded);}
        function test_historyMotionAndDivider(){
            K.Kit.reducedMotion=false;
            var body=button("historyBody-lena-first");
            compare(body.height,0);
            state.act("expand",{id:"lena-first"});
            wait(80);
            compare(button("historyBody-lena-first"),body,"Expanding must preserve the message item");
            verify(body.height>0,"The body should expand during the arrive motion");
            var halfway=body.height;
            wait(K.Kit.motion("arriveSmall").ms);
            verify(body.height>halfway,"Expansion must move through intermediate heights");
            var divider=button("historyDivider-lena-first");
            verify(divider.y>=body.y+body.height,"The hairline must follow the whole message");
            state.act("expand",{id:"lena-first"});
            wait(60);verify(body.height>0,"Content must remain visible during leave");
            tryCompare(body,"height",0,K.Kit.motion("leave").ms+500);
            K.Kit.reducedMotion=true;
        }
        function test_latestMessageToggle(){
            var body=button("messageBody-mara");verify(body.height>0);
            click("messageHeader-mara");compare(body.height,0);
            click("messageHeader-mara");verify(body.height>0);
            compare(button("attachment-review").fileName,"Review summary.pdf");
        }
        function test_sentMessageToggle(){
            state.reply("Reply",false);state.act("draft",{body:"A local reply"});state.act("send");wait(30);
            var id=state.selected.replies[0].id;
            var body=button("messageBody-"+id), header=button("messageHeader-"+id);
            verify(body.height>0);header.forceActiveFocus();keyClick(Qt.Key_Return);wait(30);compare(body.height,0);
            keyClick(Qt.Key_Return);wait(30);verify(body.height>0);
        }
        function test_headerFocusRoom(){
            var scroll=button("readingScroll"), row=button("messageHeader-mara");
            var room=K.Kit.tokens.state.focusGap+K.Kit.tokens.state.focusRing;
            var at=row.mapToItem(scroll,0,0);
            verify(at.x>=room,"The full left focus ring must fit inside the scroll viewport");
            verify(at.x+row.width+room<=scroll.width,"The full right focus ring must fit inside the scroll viewport");
            var first=button("history-lena-first").mapToItem(scroll,0,0);
            verify(first.y>=room,"The top focus ring must fit inside the scroll viewport");
            var title=button("folderMenu"), caption=button("mailboxCaption");
            var titleAt=title.mapToItem(workspace,0,0), captionAt=caption.mapToItem(workspace,0,0);
            verify(captionAt.y>=titleAt.y+title.height+room,"Caption must clear the title's focus ring");
        }
        function test_attachmentStrip(){
            compare(button("attachment-review").fileName,"Review summary.pdf");
            state.act("select",{id:"studio"});
            wait(30);
            compare(state.selected.files.length,10);
            compare(state.selected.files[9].name,"10 Next steps.md");
            const first = button("attachment-prototype-1");
            const saves = Qt.createQmlObject('import QtTest; SignalSpy { signalName: "saveRequested" }', first);
            saves.target = state;
            mouseDoubleClickSequence(first, first.width / 2, first.height / 2);
            tryVerify(() => state.ui.attachment?.id === state.selected.files[0].id);
            wait(500);
            compare(saves.count, 0);
            saves.destroy();
        }
        function test_replyKeepsSingleMessageVisible(){
            state.act("select",{id:"studio"});
            wait(30);
            var original=button("messageBody-studio");
            const reader = button("readingScroll");
            reader.contentY = Math.max(0, reader.contentHeight - reader.height);
            click("reply");
            compare(state.draft.to,"tactical.studio@example.com");
            compare(button("messageBody-studio"),original);
            verify(original.visible && original.height>0);
            var editor=button("mailEditor");
            verify(editor.mapToItem(workspace,0,0).y>=original.mapToItem(workspace,0,original.height).y);
        }
        function test_replyTargetsHistoricalMessage(){
            click("history-lena-first");
            click("reply-lena-first");
            compare(state.draft.conversation,"mara");
            compare(state.draft.to,"lena.fischer@example.com");
            var editor=button("mailEditor"), source=button("history-lena-first"), next=button("history-nils-first");
            compare(editor.replySourceName,"Lena Fischer");
            verify(editor.mapToItem(workspace,0,0).y>=source.mapToItem(workspace,0,source.height).y);
            verify(editor.mapToItem(workspace,0,editor.height).y<=next.mapToItem(workspace,0,0).y);
        }
        function test_threadOpensAtHistoricalDraft() {
            state.reply("Reply", false, "lena-first");
            const draftId = state.draft.id;
            state.act("select", {id: "studio"});
            state.act("select", {id: "mara"});
            compare(state.draft.id, draftId);

            const scroll = button("readingScroll");
            const editor = button("mailEditor");
            const source = button("historyBody-lena-first");
            tryVerify(() => source.visible);
            verify(!button("historyBody-nils-first").visible);
            tryVerify(() => {
                const top = editor.mapToItem(scroll.contentItem, 0, 0).y;
                const bottom = top + editor.height;
                const expected = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                    top, bottom - scroll.height));
                return Math.abs(scroll.contentY - expected) < 1;
            });
        }

        function test_threadWithoutDraftOpensAtLastMessage() {
            state.act("select", {id: "studio"});
            state.act("select", {id: "mara"});
            compare(state.ui.view, "read");
            const scroll = button("readingScroll");
            const latest = button("messageHeader-mara");
            tryVerify(() => {
                const top = latest.mapToItem(scroll.contentItem, 0, 0).y;
                const expected = Math.max(0, Math.min(scroll.contentHeight - scroll.height, top));
                return Math.abs(scroll.contentY - expected) < 1;
            });
        }
        function test_filterMenuKeyboard(){click("viewOptions");wait(200);keyClick(Qt.Key_Down);keyClick(Qt.Key_Down);keyClick(Qt.Key_Return);wait(30);compare(state.ui.filter,"Unread");verify(state.rows.every(function(m){return m.unread;}));}
        function test_editorFooterFollowsBody(){
            click("replyAll");
            var send=button("sendDraft"), body=button("draftBody"), editor=button("mailEditor"), scroll=button("readingScroll");
            var sendY=send.mapToItem(editor,0,0).y;
            var bodyEnd=body.mapToItem(editor,0,body.height).y;
            verify(sendY>=bodyEnd,"Send must follow the writing field");
            verify(sendY+send.height<=editor.height,"Send must stay inside its editor");
            verify(body.width<=scroll.width,"The editor must fit the reading column");
        }
        function test_replyGifFitsShortViewport() {
            const previousHeight = workspace.parent.height;
            try {
                click("replyAll");
                workspace.parent.height = 500;
                wait(30);
                const body = button("draftBody");
                if (!button("formatBold").visible)
                    skip("Optional editor-engine module is unavailable");
                body.insertAttachment(Qt.resolvedUrl("../fixtures/funny-cat-52.gif"),
                    {id: "fit-gif", name: "funny-cat-52.gif"}, 0);
                const dimensions = /<img [^>]* width="([\d.]+)" height="([\d.]+)"/.exec(body.snapshot().bodyHtml);
                verify(dimensions !== null);
                const width = Number(dimensions[1]);
                const height = Number(dimensions[2]);
                verify(height <= button("readingScroll").height * 0.45);
                verify(Math.abs(width / height - 470 / 278) < 0.01);
            } finally {
                workspace.parent.height = previousHeight;
            }
        }
        function test_sendReplyWithGifAndTrailingText() {
            click("replyAll");
            const body = button("draftBody");
            if (!button("formatBold").visible)
                skip("Optional editor-engine module is unavailable");

            body.input.forceActiveFocus();
            keyClicks("Before the GIF");
            const file = Qt.resolvedUrl("../fixtures/funny-cat-52.gif");
            const attachment = { id: "test-gif", name: "funny-cat-52.gif" };
            body.insertAttachment(file, attachment, body.input.cursorPosition);
            keyClicks("lol");

            const html = body.snapshot().bodyHtml;
            verify(html.indexOf("Before the GIF") < html.indexOf("data:image/gif;base64,"));
            verify(html.indexOf("lol", html.indexOf("</a>")) > html.indexOf("</a>"));
            verify(html.length > 200000, "Exercise the large HTML loading path");

            button("mailEditor").sendDraft();
            compare(state.selected.replies[state.selected.replies.length - 1].bodyHtml, html);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true, 10000);
            const browser = button("mailHtmlBrowser");
            verify(waitForRendering(browser));
            compare(browser.backgroundColor, Qt.rgba(0, 0, 0, 0));
            let rendered = false;
            browser.runJavaScript(
                "(() => { const image = document.querySelector('img');"
                + " const range = document.createRange(); range.selectNodeContents(document.body);"
                + " return !!image && image.naturalWidth > 0 && document.body.innerText.trim().endsWith('lol')"
                + " && range.getBoundingClientRect().bottom <= window.innerHeight + 1; })()",
                1, result => { rendered = result; });
            tryVerify(() => rendered);
        }
        function test_richTextDraft(){
            state.act("new");
            state.act("draft", {to: "anna@example.net", body: "First\nSecond"});
            wait(30);
            var body = button("draftBody");
            var bold = button("formatBold");
            if (!bold.visible)
                skip("Optional editor-engine module is unavailable");

            body.input.forceActiveFocus();
            body.input.select(0, 5);
            click("formatBold");
            tryVerify(() => state.draft.bodyHtml.includes("<strong>First</strong>"));
            click("formatItalic");
            tryVerify(() => state.draft.bodyHtml.includes("<em><strong>First</strong></em>"));

            click("formatLink");
            var url = button("formatLinkUrl");
            url.input.text = "https://example.org/";
            click("applyFormatLink");
            tryVerify(() => state.draft.bodyHtml.includes('href="https://example.org/"'));
            body.input.selectAll();
            click("formatList");
            tryVerify(() => state.draft.bodyHtml.includes("<ul>"));
            compare(state.draft.body, "First\nSecond");

            var id = state.draft.id;
            var html = state.draft.bodyHtml;
            state.act("keepDraft");
            state.act("select", {id: id});
            tryCompare(button("draftBody").input, "length", 12);
            tryVerify(() => button("draftBody").snapshot().bodyHtml.includes("<strong>"));
            html = button("draftBody").snapshot().bodyHtml;
            verify(html.includes("<ul>") && html.includes('href="https://example.org/"'));
            body = button("draftBody");
            body.input.forceActiveFocus();
            body.input.cursorPosition = body.input.length;
            click("formatBold");
            keyClicks("X");
            tryVerify(() => state.draft.bodyHtml.includes("<strong>X</strong>"));
            body.input.undo();
            tryVerify(() => state.draft.bodyHtml === html);
            state.act("send");
            compare(state.selected.replies[0].bodyHtml, html);
            state.act("undoSend");
            compare(state.draft.bodyHtml, html);
        }
        function test_sidebar(){click("folderMenu");compare(state.ui.rail,true);verify(button("mailboxes").visible);}
    }
}
