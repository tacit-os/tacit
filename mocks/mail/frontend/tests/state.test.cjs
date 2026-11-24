const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const context=vm.createContext({});vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../mail-store.js'),'utf8'),context);
const fixtures = vm.createContext({Store: context});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname, 'fixtures/mailbox-responses.js'), 'utf8').replace(/^\.import[^\n]*\n/gm, ''), fixtures);
context.Responses=fixtures;context.Store={...context};vm.runInContext(fs.readFileSync(require("node:path").join(__dirname,"fixtures/mailbox.js"),"utf8").replace(/^\.import[^\n]*\n/gm,""),context);
const {initial,reduce,results,draft,canSend,current}=context;
const {folderCount}=context;
let s=initial('read');assert.equal(results(s).length,11);assert.equal(folderCount(s,'Inbox'),4);
assert.equal(current(initial('roastmarket')).bodyHtmlFixture,'roastmarket');
s=reduce(s,'select',{id:'studio'});assert.equal(current(s).unread,false);assert.equal(folderCount(s,'Inbox'),3);
s=reduce(s,'search',{text:'palettes'});assert(results(s).some(row=>row.folder==='Inbox'));assert(results(s).some(row=>row.folder && row.folder!=='Inbox'));s=reduce(s,'closeSearch');
s=reduce(s,'folder',{folder:'Inbox'});s=reduce(s,'select',{id:'mara'});s=reduce(s,'move',{folder:'Archive'});assert(!results(s).some(x=>x.id==='mara'));s=reduce(s,'undo');assert(results(s).some(x=>x.id==='mara'));
s=reduce(s,'reply',{mode:'Reply all',agent:true});assert(draft(s).agent);s=reduce(s,'draft',{body:'Edited by me'});assert.equal(draft(s).body,'Edited by me');s=reduce(s,'keepDraft');s=reduce(s,'reply',{agent:true});assert.equal(draft(s).body,'Edited by me');
s=reduce(s,'send',{now:100});assert.equal(current(s).replies[0].status,'sending');s=reduce(s,'undoSend',{now:200});assert.equal(draft(s).body,'Edited by me');assert.equal(current(s).replies.length,0);
s=reduce(s,'online',{value:false});s=reduce(s,'send',{now:300});s=reduce(s,'tick',{now:30000});assert.equal(current(s).replies[0].status,'queued');s=reduce(s,'retry',{now:30001});assert.equal(s.jobs.length,1);s=reduce(s,'online',{value:true});s=reduce(s,'retry',{now:30002});assert.equal(s.jobs.length,0);assert.equal(current(s).replies[0].status,'sent');
s=reduce(s,'new');assert(!canSend(draft(s)));s=reduce(s,'draft',{to:'invalid',body:'Hi'});assert(!canSend(draft(s)));s=reduce(s,'draft',{to:'anna.richter@example.net',subject:'Hello'});assert(canSend(draft(s)));s=reduce(s,'attach',{name:'Notes.md'});assert.equal(draft(s).files.length,1);s=reduce(s,'keepDraft');s=reduce(s,'folder',{folder:'Drafts'});assert(results(s).some(x=>x.subject==='Hello'));
s=reduce(s,'setting',{key:'agentScope',value:'All accounts'});s=reduce(s,'notify');assert.equal(s.mailboxIds[0],'anna-notification');s=reduce(s,'openNotification',{reply:true});assert.equal(current(s).id,'anna-notification');assert.equal(draft(s).to,'anna.richter@example.com');
s=reduce(s,'setup');s=reduce(s,'provider',{name:'Microsoft'});s=reduce(s,'providerEmail',{text:'new@example.com'});s=reduce(s,'connect');assert.equal(s.ui.view,'importing');for(let i=0;i<7;i++)s=reduce(s,'tick');assert.equal(s.ui.view,'read');assert(s.accounts.some(a=>a.email==='new@example.com'));

let n=initial('read');n=reduce(n,'new');n=reduce(n,'draft',{to:'a@example.com',body:'A new message'});n=reduce(n,'send',{now:10});n=reduce(n,'undoSend',{now:11});assert.equal(draft(n).conversation,'');n=reduce(n,'send',{now:12});assert.equal(n.jobs.length,1);n=reduce(n,'tick',{now:20000});assert.equal(n.jobs.length,0);assert.equal(current(n).replies[0].status,'sent');

let scope=initial('read');scope=reduce(scope,'select',{id:'anna'});scope=reduce(scope,'reply',{agent:true});assert.equal(scope.ui.view,'read');assert(scope.ui.notice.includes('allowed'));
let settings=initial('read');settings=reduce(settings,'setting',{key:'notifications',value:'Off'});settings=reduce(settings,'notify');assert.equal(settings.ui.notification,false);

console.log('Frontend state: all workflow checks passed');

for (const action of ["new", "reply"]) {
    let mail = reduce(initial("read"), action, {mode:"Reply"});
    mail = reduce(mail, "draft", {to:"a@example.com", body:"Earlier text"});
    const html = '<p><strong>GIF</strong><img src="data:image/gif;base64,R0lGODlh"></p>';
    mail = reduce(mail, "send", {body:"GIF", bodyHtml:html});
    const sent = current(mail).replies.at(-1);
    assert.equal(sent.body, "GIF");
    assert.equal(sent.bodyHtml, html);
}

{
    const accountId = "imap-third@example.org";
    const mailbox = context.emptyMailbox();
    mailbox.accounts = [{id: accountId, name: "Shared name"}, {id: "other", name: "Shared name"}];
    const wire = {account_id: accountId, from: {email: "sender@example.org"}, subject: "Incoming",
        conversation_id: "thread", date: "2026-11-14T10:00:00Z"};
    const loaded = fixtures.fromMailbox(mailbox, [
        {...wire, id: "incoming", mailbox: "Inbox", unread: true},
        {...wire, id: "other-incoming", account_id: "other", mailbox: "Inbox", unread: true},
        {...wire, id: "saved", mailbox: "Drafts"}
    ]);
    assert.equal(context.mailboxMessages(loaded)[0].account, "Shared name");
    assert.equal(folderCount(loaded, "Inbox", accountId), 1);
    assert.equal(loaded.drafts[0].conversation, "incoming");
    assert.equal(loaded.drafts[0].backendAccount, accountId);
    assert.equal(context.makeDraft(loaded, "incoming", "Reply", false).backendAccount, accountId);
    loaded.ui.account = accountId;
    assert.equal(context.makeDraft(loaded, "", "New message", false).backendAccount, accountId);
}

{
 const state=context.emptyMailbox();
 const entry=(id,date,flags={})=>Object.assign({id,account_id:'work',conversation_id:'star-thread',mailbox:'Inbox',from:{email:'sender@example.test'},subject:'Thread',body_text:'Text',date},flags);
 const old=entry('old-star','2026-11-18T10:00:00Z',{flagged:true});
 const latest=entry('latest','2026-11-19T10:00:00Z');
 let loaded=fixtures.fromMailbox(state,[Object.assign({},latest,{folder_message_count:2,folder_other_starred:true})]);
 let rows=context.Store.results(loaded);
 assert.equal(rows.length,1);assert.equal(rows[0].id,'latest');assert.equal(rows[0].starred,true);
 loaded=fixtures.fromMailbox(state,[Object.assign({},latest,{folder_message_count:2,folder_other_starred:false})]);
 assert.equal(context.Store.results(loaded)[0].starred,false);
 loaded=fixtures.fromMailbox(state,[entry('gmail-label','2026-11-19T10:00:00Z',{gmail_labels:['STARRED']})]);
 assert.equal(context.Store.results(loaded)[0].starred,true);
}
