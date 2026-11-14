// Local, deterministic frontend state. No sockets, provider calls or credentials.
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function message(id, from, subject, body, account, day, time, unread) {
    return {id:id, from:from, address:from.toLowerCase().replace(/[^a-z]/g, ".")+"@example.com", subject:subject, body:body, account:account, day:day, time:time, unread:!!unread, starred:false, folder:"Inbox", files:[], replies:[], generated:false};
}
function emptyMailbox() {
    var s={messages:[],accounts:[],drafts:[],jobs:[],sequence:0,settings:{agentDrafts:true,agentSort:false,agentScope:"Work only",undoSeconds:10,workSignature:"Lorenz\nMoss Studio",personalSignature:"Lorenz",pictures:"Ask first",notifications:"From people only",reducedMotion:false},ui:{view:"read",selected:"",folder:"Inbox",account:"All accounts",rail:false,query:"",searching:false,filter:"All mail",sort:"Newest first",draftId:"",notice:"",undo:null,notification:false,provider:"",providerEmail:"",imported:0,online:true,attachment:null},now:0};
    return s;
}
function find(s,id){return s.messages.find(function(m){return m.id===id;})||null;}
function current(s){return find(s,s.ui.selected);}
function draft(s){return s.drafts.find(function(d){return d.id===s.ui.draftId;})||null;}
function agentDraft(s,id){return s.drafts.find(function(d){return d.conversation===id&&d.agent;})||null;}
function canReplyAll(thread, accounts) {
    if (!thread)
        return false;
    function addressKey(value) {
        var address = value.match(/<([^<>]+)>/);
        return (address ? address[1] : value).trim().toLowerCase();
    }
    var own = new Set(accounts.map(function(account) { return addressKey(account.email); }));
    var others = new Set();
    [thread].concat(thread.history || [], thread.replies || []).forEach(function(entry) {
        var sender = entry.outgoing ? "" : entry.address;
        [sender, entry.to, entry.cc].forEach(function(field) {
            emails(field).forEach(function(value) {
                var address = addressKey(value);
                if (address.includes("@") && !own.has(address))
                    others.add(address);
            });
        });
    });
    return others.size >= 2;
}
function replySource(s, thread, sourceId) {
    if (!thread || !sourceId || sourceId === thread.id)
        return thread;
    var received = (thread.history || []).find(function(entry) { return entry.id === sourceId; });
    if (received)
        return received;
    var sent = (thread.replies || []).find(function(entry) { return entry.id === sourceId; });
    if (!sent)
        return thread;
    var recipients = sent.to.split(",").map(function(address) { return address.trim(); }).filter(Boolean);
    var account = s.accounts.find(function(item) { return item.name === thread.account; });
    return Object.assign({}, sent, {from:"You", address:account ? account.email : "", replyAddress:recipients[0] || "", cc:recipients.slice(1).concat(sent.cc || []).join(", ")});
}
function threadDay(date, now) {
    const calendarDay = value => Date.UTC(value.getFullYear(), value.getMonth(), value.getDate());
    const daysAgo = (calendarDay(now) - calendarDay(date)) / 86400000;
    const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
    const weekday = weekdays[date.getDay()];
    if (daysAgo === 0)
        return "Today";
    if (daysAgo === 1)
        return "Yesterday";
    if (daysAgo > 1 && daysAgo < 7)
        return weekday;
    const year = date.getFullYear() === now.getFullYear() ? "" : " " + date.getFullYear();
    return weekday + " " + date.getDate() + " " + months[date.getMonth()] + year;
}
function fromMailbox(state, messages, sourceRows) {
    const rows = messages.filter(entry => entry.mailbox !== "Drafts" && entry.mailbox !== "Outbox")
        .map(entry => {
            const date = new Date(entry.date);
            const row = message(entry.id, entry.from.name || entry.from.email, entry.subject,
                entry.body_text || "", entry.account_id === "work" ? "Work" : "Personal",
                date.toLocaleDateString(), date.toLocaleTimeString().slice(0, 5), entry.unread);
            row.address = entry.from.email;
            row.timestamp = date.getTime();
            row.backendAccount = entry.account_id;
            row.backendConversation = entry.conversation_id;
            row.cc = (entry.cc || []).map(address => address.email).join(", ");
            row.folder = entry.mailbox;
            row.trashOrigin = entry.trash_origin || "Inbox";
            row.starred = entry.flagged;
            row.bodyHtml = entry.body_html || "";
            row.files = (entry.attachments || []).map(file => ({
                id: file.id, messageId: entry.id, name: file.filename, bytes: file.size,
                kind: file.media_type.startsWith("image/") ? "image" : "document",
                inline: file.inline || row.bodyHtml.includes('cid:' + file.id)
            }));
            return row;
        });
    const drafts = messages.filter(entry => entry.mailbox === "Drafts").map(entry => {
        const source = (sourceRows || rows).find(row => row.backendConversation === entry.conversation_id
            && row.account === (entry.account_id === "work" ? "Work" : "Personal"));
        const addresses = values => (values || []).map(address => address.email).join(", ");
        return {
            id: entry.id, backendId: entry.id, backendConversation: entry.conversation_id, conversation: source?.id || "", sourceId: entry.reply_source_id || "",
            mode: source ? "Reply" : "New message", account: entry.account_id === "work" ? "Work" : "Personal",
            to: addresses(entry.to), cc: addresses(entry.cc), bcc: addresses(entry.bcc),
            showCc: !!entry.cc?.length, showBcc: !!entry.bcc?.length, subject: entry.subject,
            body: entry.body_text || "", bodyHtml: entry.body_html || "",
            files: (entry.attachments || []).map(file => ({id: file.id, messageId: entry.id, backendId: file.id, name: file.filename, inline: file.inline, inlineSource: file.inlineSource}))
        };
    });
    return Object.assign({}, state, {
        messages: rows, drafts, jobs: [],
        ui: Object.assign({}, state.ui, {
            selected: rows.some(row => row.id === state.ui.selected)
                ? state.ui.selected : rows.find(row => row.folder === "Inbox")?.id || "",
            view: drafts.some(draft => draft.id === state.ui.draftId) ? state.ui.view : "read"
        })
    });
}

function makeDraft(s,conversation,mode,agent,sourceId){
    var thread=find(s,conversation),m=replySource(s,thread,sourceId),account=thread?thread.account:(s.ui.account==="All accounts"?"Personal":s.ui.account);
    var signature=account==="Work"?s.settings.workSignature:s.settings.personalSignature;
    return {id:"draft-"+(++s.sequence),conversation:conversation,sourceId:sourceId||"",mode:mode,account:account,to:m&&mode!=="Forward"?(m.replyAddress ?? m.address):"",cc:m&&mode==="Reply all"?(m.cc||""):"",bcc:"",showCc:mode==="Reply all",showBcc:false,subject:m?(mode==="Forward"?"Fwd: ":"Re: ")+thread.subject:"",body:agent&&m?(m.id==="mara"?"Hi Mara,\n\nThanks, this reads well. Two notes on the header: the sender and the date could share one line, and the attachment should sit right under the text it belongs to.\n\nI will send the rest by Wednesday, a day before your Thursday deadline.\n\n"+signature:"Hi "+m.from.split(" ")[0]+",\n\nThank you for your message. I will get back to you shortly.\n\n"+signature):mode==="Forward"&&m?"\n\n---------- Forwarded message ----------\nFrom: "+m.from+" <"+m.address+">\nSubject: "+thread.subject+"\n\n"+m.body:"",files:mode==="Forward"&&m?copy(m.files||[]):[],agent:!!agent,edited:false};
}
function emails(value){return String(value||"").split(/[,;]/).map(function(v){return v.trim();}).filter(Boolean);}
function validRecipients(value){var all=emails(value);return all.length>0&&all.every(function(v){return /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(v);});}
function canSend(d){return !!d&&validRecipients(d.to)&&(!d.cc||validRecipients(d.cc))&&(!d.bcc||validRecipients(d.bcc))&&(d.body.trim()!==""||d.files.length>0);}
function results(s, groupConversations = true){
    const q = s.ui.query.toLowerCase().trim();
    function matches(row) {
        return [row.from, row.address, row.to, row.cc, row.bcc, row.subject, row.body,
            ...row.files.map(file => file.name)].join(" ").toLowerCase().includes(q);
    }
    if(s.ui.folder==="Drafts")return s.drafts.filter(function(d){
        return (s.ui.account==="All accounts"||d.account===s.ui.account) && (!s.ui.searching || matches(d));
    }).map(function(d){return {id:d.id,draft:true,from:d.agent?"Your agent":"You",subject:d.subject||"No subject",body:d.body,account:d.account,day:"Drafts",time:"Not sent",unread:false,files:d.files};});
    var list=s.messages.filter(function(m){
        if(s.ui.account!=="All accounts"&&m.account!==s.ui.account)return false;
        if(s.ui.folder==="Starred"){if(!m.starred||m.folder==="Trash")return false;}
        else if(s.ui.folder==="Sent"){if(!m.replies.some(function(r){return r.status==="sent";})&&m.folder!=="Sent")return false;}
        else if(["Family","Receipts","Clients","Invoices"].includes(s.ui.folder)){if(m.category!==s.ui.folder)return false;}
        else if(m.folder!==s.ui.folder)return false;
        if (s.ui.searching && !(s.searchIds ? s.searchIds.includes(m.id) : matches(m))) return false;
        if(s.ui.filter==="Unread"&&!m.unread)return false;if(s.ui.filter==="With attachments"&&m.files.length===0)return false;if(s.ui.filter==="Starred"&&!m.starred)return false;
        return true;
    });
    if (groupConversations && ["Trash", "Archive"].includes(s.ui.folder)) {
        const threads = new Map();
        for (const row of list) {
            const key = JSON.stringify([row.backendAccount, row.backendConversation || row.id]);
            const group = threads.get(key);
            if (!group) {
                threads.set(key, {row: row, count: 1});
            } else {
                ++group.count;
                if (row.timestamp > group.row.timestamp)
                    group.row = row;
            }
        }
        list = Array.from(threads.values(), group =>
            Object.assign({}, group.row, {folderMessageCount: group.count}));
        list.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
    }
    if(s.ui.sort==="Oldest first")list.reverse();
    if(s.ui.sort==="Sender")list.sort(function(a,b){return a.from.localeCompare(b.from);});
    if(s.ui.sort==="Unread first")list.sort(function(a,b){return Number(b.unread)-Number(a.unread);});
    return list;
}
function folderCount(state, folder, account) {
    const ui = Object.assign({}, state.ui, {
        searching: false,
        filter: "Unread",
        folder,
        account: account || "All accounts"
    });
    return results(Object.assign({}, state, {ui}), false).filter(row => row.unread).length;
}
function remember(s){s.ui.undo={messages:copy(s.messages),drafts:copy(s.drafts),jobs:copy(s.jobs),accounts:copy(s.accounts),selected:s.ui.selected};}
function showReplyDraft(state) {
    const row = current(state);
    if (!row || state.ui.view !== "read")
        return;
    const saved = state.drafts.find(draft => !draft.agent && (
        draft.conversation === row.id || (draft.backendConversation
            && draft.backendConversation === row.backendConversation && draft.account === row.account)));
    if (saved && row.folder !== "Trash") {
        saved.conversation = row.id;
        state.ui.draftId = saved.id;
        state.ui.view = "draft";
    }
}
function reduce(previous,action,p){
    p=p||{};var s=copy(previous),u=s.ui,m=current(s),d=draft(s);s.now=p.now===undefined?s.now:p.now;
    switch(action){
    case "select":
        var chosen=s.drafts.find(function(x){return x.id===p.id;});
        if(chosen){u.draftId=chosen.id;u.selected=chosen.conversation;u.view=chosen.conversation?"draft":"compose";}else{u.selected=p.id;u.view="read";var selected=find(s,p.id);if(selected)selected.unread=false;showReplyDraft(s);}break;
    case "folder":u.folder=p.folder;u.account=p.account||"All accounts";u.searching=false;u.query="";u.view="read";u.selected="";var next=results(s)[0];if(next){if(next.draft){u.draftId=next.id;u.view=next.id&&next.id.indexOf("draft-")===0?"compose":"read";var dd=s.drafts.find(function(x){return x.id===next.id;});u.selected=dd.conversation;u.view=dd.conversation?"draft":"compose";}else{u.selected=next.id;find(s,next.id).unread=false;}}break;
    case "rail":u.rail=!u.rail;break;
    case "search":u.query=p.text;u.searching=true;u.view="read";break;
    case "closeSearch":u.query="";u.searching=false;break;
    case "filter":u.filter=p.value;break;
    case "sort":u.sort=p.value;break;
    case "new":var fresh=makeDraft(s,"","New message",false);s.drafts.push(fresh);u.draftId=fresh.id;u.view="compose";break;
    case "reply":
        if(!m)break;if(p.agent&&s.settings.agentScope!=="All accounts"&&s.settings.agentScope!==m.account+" only"){u.notice="This account is outside your agent’s allowed mail. Change it in Settings.";break;}var mode=p.mode||"Reply";var existing=p.agent?agentDraft(s,m.id):s.drafts.find(x=>!x.agent&&x.conversation===m.id);var reply=existing||makeDraft(s,m.id,mode,!!p.agent,p.sourceId);if(!existing)s.drafts.push(reply);u.draftId=reply.id;u.view="draft";break;
    case "mode":if(d){var thread=find(s,d.conversation);var source=replySource(s,thread,d.sourceId);d.mode=p.value;if(source){d.to=p.value==="Forward"?"":(source.replyAddress ?? source.address);d.cc=p.value==="Reply all"?(source.cc||""):"";d.showCc=p.value==="Reply all";d.subject=(p.value==="Forward"?"Fwd: ":"Re: ")+thread.subject;}}break;
    case "draft":if(d){if(p.body!==undefined&&p.bodyHtml===undefined)d.bodyHtml="";Object.keys(p).forEach(function(key){if(key!=="now")d[key]=p[key];});d.edited=p.edited===undefined?true:p.edited;}break;
    case "keepDraft":u.view="read";u.notice="Draft kept. Nothing was sent.";break;
    case "discard":if(d){remember(s);s.drafts=s.drafts.filter(function(x){return x.id!==d.id;});u.draftId="";u.view="read";u.notice="Draft moved to Trash";}break;
    case "attach":if(d&&p.url&&p.name){d.files.push({id:"local-"+(++s.sequence),name:p.name,kind:"document",inline:!!p.inline,url:p.url});}break;
    case "detach":if(d)d.files=d.files.filter(function(f){return f.id!==p.id;});break;
    case "move":if(m){remember(s);m.folder=p.folder;u.notice="Moved to "+p.folder;var rows=results(s);if(!rows.some(function(x){return x.id===m.id;}))u.selected=rows.length?rows[0].id:"";}break;
    case "star":if(m){m.starred=!m.starred;u.notice=m.starred?"Starred":"Star removed";}break;
    case "unread":if(m){m.unread=p.value===undefined?!m.unread:!!p.value;u.notice=m.unread?"Marked unread":"Marked read";}break;
    case "undo":if(u.undo){s.messages=u.undo.messages;s.drafts=u.undo.drafts;s.jobs=u.undo.jobs;s.accounts=u.undo.accounts;u.selected=u.undo.selected;u.undo=null;u.view="read";u.notice="Undone";}break;
    case "expand":if(m){var h=(m.history||[]).find(function(x){return x.id===p.id;});if(h)h.expanded=!h.expanded;}break;
    case "preview":u.attachment=p.file;break;
    case "closePreview":u.attachment=null;break;
    case "settings":u.view="settings";u.rail=false;break;
    case "setting":s.settings[p.key]=p.value;break;
    case "back":u.view="read";u.provider="";u.attachment=null;break;
    case "setup":u.view="setup";u.provider="";u.rail=false;break;
    case "provider":u.provider=p.name;break;
    case "providerEmail":u.providerEmail=p.text;break;
    case "notice":u.notice=p.text;break;
    case "clearNotice":u.notice="";u.undo=null;break;
    case "escape":if(u.attachment)u.attachment=null;else if(u.view==="draft"||u.view==="compose")u.view="read";else if(u.view!=="read")u.view="read";else if(u.searching){u.searching=false;u.query="";}else if(u.rail)u.rail=false;else u.selected="";break;
    case "reset":return emptyMailbox();
    }
    return s;
}

function highlight(text, query, ink, background) {
    function escape(value) {
        return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    var q=String(query||"").trim().replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
    const parts = q ? String(text).split(new RegExp("(" + q + ")", "gi")) : [String(text)];
    return parts.map((part, index) => {
        const escaped = escape(part);
        if (index % 2 === 0)
            return escaped;
        if (background)
            return '<span style="color:' + ink + ';background-color:' + background + ';">' + escaped + '</span>';
        return ink ? '<font color="' + ink + '">' + escaped + '</font>' : '<b>' + escaped + '</b>';
    }).join("").replace(/\n/g, "<br>");
}
