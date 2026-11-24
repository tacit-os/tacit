// Local, deterministic frontend state. No sockets, provider calls or credentials.
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function message(id, from, subject, body, account, day, time, unread) {
    return {id:id, from:from, address:from.toLowerCase().replace(/[^a-z]/g, ".")+"@example.com", subject:subject, body:body, account:account, day:day, time:time, unread:!!unread, starred:false, folder:"Inbox", files:[], replies:[], generated:false};
}
function emptyMailbox() {
    var s={records:{},mailboxIds:[],accounts:[],drafts:[],jobs:[],sequence:0,settings:{agentDrafts:true,agentSort:false,agentScope:"Work only",undoSeconds:10,workSignature:"Lorenz\nMoss Studio",personalSignature:"Lorenz",pictures:"Ask first",notifications:"From people only",reducedMotion:false},ui:{view:"read",selected:"",folder:"Inbox",account:"All accounts",rail:false,query:"",searching:false,filter:"All mail",searchFilter:"All mail",gmailCategory:"",sort:"Newest first",draftId:"",notice:"",undo:null,notification:false,provider:"",providerEmail:"",imported:0,online:true,attachment:null},now:0};
    return s;
}
// Lists store membership only; every view resolves the same message record.
var lastMessageViews = null;
var noSearchIds = [];
function stableIds(previous, next) {
    return previous && previous.length === next.length && next.every((id, index) => id === previous[index])
        ? previous : next;
}
function messageViews(state) {
    const searchIds = state.search?.ids ?? noSearchIds;
    const previous = lastMessageViews;
    if (previous?.records === state.records && previous.mailbox.ids === state.mailboxIds
            && previous.search.ids === searchIds) return previous;
    function project(ids, cached) {
        if (cached?.ids === ids && ids.every((id, index) => state.records[id] === cached.rows[index])) return cached;
        return {ids, rows: ids.map(id => state.records[id]).filter(Boolean)};
    }
    const views = {records: state.records,
        mailbox: project(state.mailboxIds, previous?.mailbox), search: project(searchIds, previous?.search)};
    lastMessageViews = views;
    return views;
}
function mailboxMessages(state) { return messageViews(state).mailbox.rows; }
function searchMessages(state) { return messageViews(state).search.rows; }
function find(state, id) { return Object.prototype.hasOwnProperty.call(state.records, id) ? state.records[id] : null; }
function upsertMessages(state, rows) {
    const records = Object.assign(Object.create(null), state.records);
    for (const row of rows) records[row.id] = row;
    return Object.assign({}, state, {records});
}
function patchMessage(state, id, changes) {
    const row = find(state, id);
    return row ? upsertMessages(state, [Object.assign({}, row, changes)]) : state;
}
function pruneMessages(state) {
    const keep = new Set(state.mailboxIds.concat(state.search?.ids ?? []));
    if (state.search?.selectedId) keep.add(state.search.selectedId);
    const ids = Object.keys(state.records);
    if (ids.every(id => keep.has(id))) return state;
    const records = Object.create(null);
    for (const id of ids) if (keep.has(id)) records[id] = state.records[id];
    return Object.assign({}, state, {records});
}
function replaceSearchRows(state, rows, query, complete = true) {
    return pruneMessages(Object.assign({}, upsertMessages(state, rows), {
        search: {query, ids: stableIds(state.search?.ids, Array.from(new Set(rows.map(row => row.id)))),
            selectedId: current(state)?.id ?? "", complete}
    }));
}
function backendViewKey(folder, account, filter, sort, gmailCategory = "") {
    const key = [folder, account === "All accounts" ? "" : account, filter, sort].join("\u001f");
    return gmailCategory ? key + "\u001f" + gmailCategory : key;
}
function backendViewIds(views, selectedId) {
    const ids = new Set();
    for (const view of Object.values(views)) for (const id of view.ids) ids.add(id);
    if (selectedId) ids.add(selectedId);
    return Array.from(ids);
}
function replaceBackendView(state, rows, key) {
    const metadata = Object.create(null);
    const records = rows.map(row => {
        metadata[row.id] = {count: row.folderMessageCount, starred: row.folderOtherStarred};
        const record = Object.assign({}, row);
        delete record.folderMessageCount; delete record.folderStarred; delete record.folderOtherStarred;
        return record;
    });
    const updated = upsertMessages(state, records);
    const backendViews = Object.assign({}, state.backendViews, {[key]: {
        ids: rows.map(row => row.id), metadata
    }});
    return pruneMessages(Object.assign({}, updated, {
        mailboxIds: stableIds(state.mailboxIds, backendViewIds(backendViews, current(state)?.id)), backendViews
    }));
}
function removeMessages(state, ids, permanent = false) {
    const removed = new Set(ids);
    const search = state.search ? Object.assign({}, state.search, {
        ids: state.search.ids.filter(id => !removed.has(id)),
        selectedId: removed.has(state.search.selectedId) ? "" : state.search.selectedId
    }) : undefined;
    let ui = state.ui;
    if (permanent && ui.undo?.records) {
        const records = Object.assign(Object.create(null), ui.undo.records);
        for (const id of ids) delete records[id];
        const undo = removed.has(ui.undo.selected) ? null : Object.assign({}, ui.undo, {
            records, mailboxIds: ui.undo.mailboxIds.filter(id => !removed.has(id))
        });
        ui = Object.assign({}, ui, {undo});
    }
    return pruneMessages(Object.assign({}, state, {ui, mailboxIds: state.mailboxIds.filter(id => !removed.has(id)), search}));
}
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
    var account = s.accounts.find(function(item) { return (item.id || item.name) === accountKey(thread); });
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
function accountKey(row) {
    return row.backendAccount || row.account;
}
function accountLabel(accounts, fallback) {
    return accounts.find(account => account.id === fallback)?.name
        || ({work: "Work", personal: "Personal"})[fallback] || fallback;
}
function mailboxRows(accounts, messages) {
    return messages.filter(entry => entry.mailbox !== "Drafts" && entry.mailbox !== "Outbox")
        .map(entry => {
            const date = new Date(entry.date);
            const row = message(entry.id, entry.from.name || entry.from.email, entry.subject,
                entry.body_text || "", accountLabel(accounts, entry.account_id),
                date.toLocaleDateString(), date.toLocaleTimeString().slice(0, 5), entry.unread);
            row.folderMessageCount = entry.folder_message_count;
            row.folderStarred = entry.folder_starred;
            row.folderOtherStarred = entry.folder_other_starred;
            row.address = entry.from.email;
            row.timestamp = date.getTime();
            row.backendAccount = entry.account_id;
            row.backendConversation = entry.conversation_id;
            row.to = (entry.to || []).map(address => address.email).join(", ");
            row.cc = (entry.cc || []).map(address => address.email).join(", ");
            row.folder = entry.mailbox;
            row.gmailLabels = entry.gmail_labels || [];
            row.gmail = String(entry.remote_id || "").startsWith("gmail:") || row.gmailLabels.length > 0;
            row.gmailSent = row.folder === "Inbox" && !!entry.gmail_labels?.includes("SENT");
            row.trashOrigin = entry.trash_origin || "Inbox";
            row.starred = !!entry.flagged || !!entry.gmail_labels?.includes("STARRED");
            row.important = !!entry.important || !!entry.gmail_labels?.includes("IMPORTANT")
                || String(entry.importance || "").trim().toLowerCase() === "high";
            row.remoteImages = entry.remote_images || [];
            row.remoteImagesAllowed = !!entry.remote_images_allowed;
            row.bodyHtml = entry.body_html || "";
            row.bodyParts = entry.body_parts || null;
            row.hasHtml = !!entry.has_html || !!entry.body_html;
            row.files = (entry.attachments || []).map(file => ({
                id: file.id, messageId: entry.id, name: file.filename, bytes: file.size,
                kind: file.media_type.startsWith("image/") ? "image" : "document",
                inline: file.inline || row.bodyHtml.includes('cid:' + file.id),
                width: file.width, height: file.height, inlineSource: file.inlineSource
            }));
            return row;
        });
}
function mailboxDrafts(accounts, messages, sourceRows) {
    return messages.filter(entry => entry.mailbox === "Drafts").map(entry => {
        const source = sourceRows.find(row => row.backendConversation === entry.conversation_id
            && accountKey(row) === entry.account_id);
        const addresses = values => (values || []).map(address => address.email).join(", ");
        return {
            id: entry.id, backendId: entry.id, backendAccount: entry.account_id, backendConversation: entry.conversation_id, conversation: source?.id || "", sourceId: entry.reply_source_id || "",
            mode: source ? "Reply" : "New message", account: accountLabel(accounts, entry.account_id),
            to: addresses(entry.to), cc: addresses(entry.cc), bcc: addresses(entry.bcc),
            showCc: !!entry.cc?.length, showBcc: !!entry.bcc?.length, subject: entry.subject,
            body: entry.body_text || "", bodyHtml: entry.body_html || "",
            files: (entry.attachments || []).map(file => ({id: file.id, messageId: entry.id, backendId: file.id, name: file.filename, inline: file.inline, inlineSource: file.inlineSource}))
        };
    });
}
function makeDraft(s,conversation,mode,agent,sourceId){
    var thread=find(s,conversation),m=replySource(s,thread,sourceId),account=thread?thread.account:(s.ui.account==="All accounts"?"Personal":s.ui.account);
    const sender = s.accounts.find(item => (item.id || item.name) === (thread ? accountKey(thread) : s.ui.account))
        || (!thread && s.ui.account === "All accounts" ? s.accounts.find(item => item.id === "personal") || s.accounts[0] : null);
    if (sender) account = sender.name;
    var signature=account==="Work"?s.settings.workSignature:s.settings.personalSignature;
    return {id:"draft-"+(++s.sequence),conversation:conversation,sourceId:sourceId||"",mode:mode,account:account,backendAccount:sender?.id || thread?.backendAccount,to:m&&mode!=="Forward"?(m.replyAddress ?? m.address):"",cc:m&&mode==="Reply all"?(m.cc||""):"",bcc:"",showCc:mode==="Reply all",showBcc:false,subject:m?(mode==="Forward"?"Fwd: ":"Re: ")+thread.subject:"",body:agent&&m?(m.id==="mara"?"Hi Mara,\n\nThanks, this reads well. Two notes on the header: the sender and the date could share one line, and the attachment should sit right under the text it belongs to.\n\nI will send the rest by Wednesday, a day before your Thursday deadline.\n\n"+signature:"Hi "+m.from.split(" ")[0]+",\n\nThank you for your message. I will get back to you shortly.\n\n"+signature):mode==="Forward"&&m?"\n\n---------- Forwarded message ----------\nFrom: "+m.from+" <"+m.address+">\nSubject: "+thread.subject+"\n\n"+m.body:"",files:mode==="Forward"&&m?copy(m.files||[]):[],agent:!!agent,edited:false};
}
function emails(value){return String(value||"").split(/[,;]/).map(function(v){return v.trim();}).filter(Boolean);}
function validRecipients(value){var all=emails(value);return all.length>0&&all.every(function(v){return /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(v);});}
function canSend(d){return !!d&&validRecipients(d.to)&&(!d.cc||validRecipients(d.cc))&&(!d.bcc||validRecipients(d.bcc))&&(d.body.trim()!==""||d.files.length>0);}
function matchesFolder(row, folder, account, filter) {
    if (account && account !== "All accounts" && accountKey(row) !== account) return false;
    if (folder === "Starred") { if (!row.starred || row.folder === "Trash") return false; }
    else if (folder === "Sent") { if (row.folder !== "Sent" && !row.gmailSent) return false; }
    else if (row.folder !== folder || folder === "Inbox" && row.gmailSent) return false;
    return !(filter === "Unread" && !row.unread) && !(filter === "Starred" && !row.starred)
        && !(filter === "With attachments" && !row.files.length);
}
function draftRows(state) {
    const query = state.ui.query.toLowerCase().trim();
    return state.drafts.filter(draft => state.ui.searching
        ? [draft.from, draft.address, draft.to, draft.cc, draft.bcc, draft.subject, draft.body,
            ...draft.files.map(file => file.name)].join(" ").toLowerCase().includes(query)
        : state.ui.account === "All accounts" || accountKey(draft) === state.ui.account)
        .map(draft => ({id: draft.id, draft: true, from: draft.agent ? "Your agent" : "You",
            subject: draft.subject || "No subject", body: draft.body, account: draft.account,
            day: "Drafts", time: "Not sent", unread: false, files: draft.files}));
}
function matchesGmailCategory(row, category) {
    if (!category) return true;
    if (!row.gmail) return false;
    const labels = row.gmailLabels || [];
    return labels.includes(category) || category === "CATEGORY_PERSONAL"
        && !labels.some(label => ["CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS"].includes(label));
}
function results(state) {
    if (state.ui.searching)
        return (state.search?.query === state.ui.query && (state.search?.filter || "All mail") === (state.ui.searchFilter || "All mail")
            ? searchMessages(state) : []).concat(draftRows(state).filter(row => !state.ui.searchFilter || state.ui.searchFilter === "All mail"
                || state.ui.searchFilter === "With attachments" && row.files.length > 0));
    if (state.ui.folder === "Drafts") return draftRows(state);
    const {folder, account, filter, sort} = state.ui;
    const view = state.backendViews?.[backendViewKey(folder, account, filter, sort, state.ui.gmailCategory || "")];
    if (!view) {
        const selected = current(state);
        return selected && matchesFolder(selected, folder, account, filter) && matchesGmailCategory(selected, state.ui.gmailCategory) ? [selected] : [];
    }
    return view.ids.map(id => find(state, id)).filter(row => row && matchesFolder(row, folder, account, filter) && matchesGmailCategory(row, state.ui.gmailCategory))
        .map(row => Object.assign({}, row, {
            folderMessageCount: view.metadata[row.id].count,
            starred: row.starred || view.metadata[row.id].starred
        }));
}
function folderCount(state, folder, account, unreadOnly = true) {
    if (folder === "Drafts") return state.drafts.filter(draft => !account || account === "All accounts" || accountKey(draft) === account).length;
    return mailboxMessages(state).filter(row => matchesFolder(row, folder, account, unreadOnly ? "Unread" : "All mail")).length;
}
function remember(s){s.ui.undo={records:copy(s.records),mailboxIds:s.mailboxIds.slice(),backendViews:s.backendViews?copy(s.backendViews):undefined,drafts:copy(s.drafts),jobs:copy(s.jobs),accounts:copy(s.accounts),selected:s.ui.selected};}
function showReplyDraft(state) {
    const row = current(state);
    if (!row || state.ui.view !== "read")
        return;
    const saved = state.drafts.find(draft => !draft.agent && (
        draft.conversation === row.id || (draft.backendConversation
            && draft.backendConversation === row.backendConversation && accountKey(draft) === accountKey(row))));
    if (saved && row.folder !== "Trash") {
        saved.conversation = row.id;
        state.ui.draftId = saved.id;
        state.ui.view = "draft";
    }
}
function editDraft(state, changes) {
    const active = draft(state);
    if (!active)
        return state;
    const updated = Object.assign({}, active);
    if (changes.body !== undefined && changes.bodyHtml === undefined)
        updated.bodyHtml = "";
    for (const key of Object.keys(changes)) {
        if (key !== "now")
            updated[key] = changes[key];
    }
    updated.edited = changes.edited === undefined ? true : changes.edited;
    return Object.assign({}, state, {
        drafts: state.drafts.map(item => item === active ? updated : item)
    });
}
function reduce(previous,action,p,queryRows = results){
    p=p||{};
    if (action === "draft") return editDraft(previous, p);
    if (["rail", "filter", "searchFilter", "sort", "gmailCategory", "preview", "closePreview", "settings", "back", "setup", "provider", "providerEmail", "notice", "clearNotice"].includes(action)) {
        const s = Object.assign({}, previous, {ui: Object.assign({}, previous.ui),
            now: p.now === undefined ? previous.now : p.now});
        const u = s.ui;
        switch (action) {
        case "rail":u.rail=!u.rail;break;
        case "filter":u.filter=p.value;break;
        case "searchFilter":u.searchFilter=p.value;break;
        case "sort":u.sort=p.value;break;
        case "gmailCategory":u.gmailCategory=p.value;break;
        case "preview":u.attachment=p.file;break;
        case "closePreview":u.attachment=null;break;
        case "settings":u.view="settings";u.rail=false;break;
        case "back":u.view="read";u.provider="";u.attachment=null;break;
        case "setup":u.view="setup";u.provider="";u.rail=false;break;
        case "provider":u.provider=p.name;break;
        case "providerEmail":u.providerEmail=p.text;break;
        case "notice":u.notice=p.text;break;
        case "clearNotice":u.notice="";u.undo=null;break;
        }
        return s;
    }
    if (action === "unread" || action === "star") {
        let next = Object.assign({}, previous, {ui: Object.assign({}, previous.ui),
            now: p.now === undefined ? previous.now : p.now});
        const row = current(previous);
        if (row) {
            const value = action === "star" ? !row.starred : p.value === undefined ? !row.unread : !!p.value;
            next = patchMessage(next, row.id, action === "star" ? {starred: value} : {unread: value});
            next.ui.notice = action === "star" ? value ? "Starred" : "Star removed"
                : value ? "Marked unread" : "Marked read";
        }
        return next;
    }
    // Navigation only copies the changed UI branch; message objects keep identity.
    if (["search", "closeSearch", "select"].includes(action) || (action === "escape" && previous.ui.searching && previous.ui.view === "read" && !previous.ui.attachment)) {
        const next = Object.assign({}, previous, {ui: Object.assign({}, previous.ui)});
        const ui = next.ui;
        if (action === "search") {
            ui.query = p.text; ui.searching = true; ui.view = "read";
        } else if (action === "closeSearch" || action === "escape") {
            ui.searching = false; ui.query = "";
            if (current(previous)?.gmail && !matchesGmailCategory(current(previous), ui.gmailCategory || "CATEGORY_PERSONAL"))
                ui.gmailCategory = current(previous).gmailLabels.find(label => ["CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES"].includes(label)) || "CATEGORY_PERSONAL";
            else if (current(previous) && !matchesGmailCategory(current(previous), ui.gmailCategory)) ui.gmailCategory = "";
            const selected = current(previous);
            if (selected) {
                const staysInFolder = selected.folder === ui.folder || (ui.folder === "Starred" && selected.starred)
                    || (ui.folder === "Sent" && selected.gmailSent);
                if (!staysInFolder) ui.folder = selected.gmailSent ? "Sent" : selected.folder || ui.folder;
                if ((ui.account !== "All accounts" && accountKey(selected) !== ui.account)
                    || (!selected.gmail && ui.account === "All accounts" && ui.folder === "Inbox"
                        && next.accounts.some(account => account.categoryProvider === "gmail")))
                    ui.account = accountKey(selected);
                if ((ui.filter === "Unread" && !selected.unread) || (ui.filter === "Starred" && !selected.starred)
                    || (ui.filter === "With attachments" && !selected.files.length)) ui.filter = "All mail";
                if (!next.mailboxIds.includes(selected.id)) next.mailboxIds = next.mailboxIds.concat([selected.id]);
            }
        } else {
            const chosen = next.drafts.find(row => row.id === p.id);
            if (chosen) { ui.draftId = chosen.id; ui.selected = chosen.conversation; ui.view = chosen.conversation ? "draft" : "compose"; }
            else {
                ui.selected = p.id; ui.view = "read";
                const selected = find(previous, p.id);
                if (selected?.unread) {
                    next.records = Object.assign(Object.create(null), previous.records, {
                        [p.id]: Object.assign({}, selected, {unread: false})
                    });
                }
                const source = find(next, p.id);
                if (next.search && ui.searching) next.search = Object.assign({}, next.search, {selectedId: source?.id ?? ""});
                const saved = source && next.drafts.find(draft => !draft.agent && (draft.conversation === source.id
                    || (draft.backendConversation && draft.backendConversation === source.backendConversation && accountKey(draft) === accountKey(source))));
                if (saved) next.drafts = next.drafts.map(draft => draft === saved ? Object.assign({}, draft) : draft);
                showReplyDraft(next);
            }
        }
        return next;
    }

    var s=copy(previous),u=s.ui,m=current(s),d=draft(s);s.now=p.now===undefined?s.now:p.now;
    switch(action){
    case "folder":u.gmailCategory="";u.folder=p.folder;u.account=p.account||"All accounts";u.searching=false;u.query="";u.view="read";u.selected="";var next=queryRows(s)[0];if(next){if(next.draft){u.draftId=next.id;u.view=next.id&&next.id.indexOf("draft-")===0?"compose":"read";var dd=s.drafts.find(function(x){return x.id===next.id;});u.selected=dd.conversation;u.view=dd.conversation?"draft":"compose";}else{u.selected=next.id;find(s,next.id).unread=false;}}break;
    case "new":var fresh=makeDraft(s,"","New message",false);s.drafts.push(fresh);u.draftId=fresh.id;u.view="compose";break;
    case "reply":
        if(!m)break;if(p.agent&&s.settings.agentScope!=="All accounts"&&s.settings.agentScope!==m.account+" only"){u.notice="This account is outside your agent’s allowed mail. Change it in Settings.";break;}var mode=p.mode||"Reply";var existing=p.agent?agentDraft(s,m.id):s.drafts.find(x=>!x.agent&&x.conversation===m.id);var reply=existing||makeDraft(s,m.id,mode,!!p.agent,p.sourceId);if(!existing)s.drafts.push(reply);u.draftId=reply.id;u.view="draft";break;
    case "mode":if(d){var thread=find(s,d.conversation);var source=replySource(s,thread,d.sourceId);d.mode=p.value;if(source){d.to=p.value==="Forward"?"":(source.replyAddress ?? source.address);d.cc=p.value==="Reply all"?(source.cc||""):"";d.showCc=p.value==="Reply all";d.subject=(p.value==="Forward"?"Fwd: ":"Re: ")+thread.subject;}}break;
    case "keepDraft":u.view="read";u.notice="Draft kept. Nothing was sent.";break;
    case "discard":if(d){remember(s);s.drafts=s.drafts.filter(function(x){return x.id!==d.id;});u.draftId="";u.view="read";u.notice="Draft moved to Trash";}break;
    case "attach":if(d&&p.url&&p.name){d.files.push({id:"local-"+(++s.sequence),name:p.name,kind:"document",inline:!!p.inline,url:p.url});}break;
    case "detach":if(d)d.files=d.files.filter(function(f){return f.id!==p.id;});break;
    case "move":if(m){remember(s);m.folder=p.folder;u.notice="Moved to "+p.folder;var rows=queryRows(s);if(!rows.some(function(x){return x.id===m.id;}))u.selected=rows.length?rows[0].id:"";}break;
    case "undo":if(u.undo){s.records=Object.assign(Object.create(null),s.records,u.undo.records);s.mailboxIds=u.undo.mailboxIds;s.drafts=u.undo.drafts;s.jobs=u.undo.jobs;s.accounts=u.undo.accounts;u.selected=u.undo.selected;if(u.undo.backendViews){s.backendViews=Object.assign({},s.backendViews,u.undo.backendViews);s.mailboxIds=backendViewIds(s.backendViews,u.selected);}u.undo=null;u.view="read";u.notice="Undone";s=pruneMessages(s);}break;
    case "expand":if(m){var h=(m.history||[]).find(function(x){return x.id===p.id;});if(h)h.expanded=!h.expanded;}break;
    case "setting":s.settings[p.key]=p.value;break;
    case "escape":if(u.attachment)u.attachment=null;else if(u.view==="draft"||u.view==="compose")u.view="read";else if(u.view!=="read")u.view="read";else if(u.rail)u.rail=false;else u.selected="";break;
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

// maild already identified these spans. Preserve their order and HTML context;
// this only adds visibility wrappers, never performs quotation detection.
function quotedBodyHTML(parts, fallback) {
    if (!parts?.length) return fallback;
    return parts.map(part => part.kind === "quotedHistory"
        ? '<div data-tacit-quoted-history="" hidden>' + part.content + '</div>'
        : part.content).join("");
}
function quotedBodyText(parts, fallback, expanded) {
    if (!parts?.length) return fallback;
    return parts.filter(part => expanded || part.kind !== "quotedHistory")
        .map(part => part.content).join("");
}
