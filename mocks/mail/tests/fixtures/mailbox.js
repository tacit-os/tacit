.import "../../mail-store.js" as Store

function initial(surface) {
    var messages = [
        Store.message("mara","Mara Klein","The Dusk and Moss pass","Hi Lorenz,\n\nThe final design review is ready. I have attached our notes on the Dusk and Moss palettes.\n\nCould you take a look at the navigation and the message header before Thursday? The interface should stay quiet, with the content doing most of the talking.\n\nThanks,\nMara","Work","Today","09:42",false),
        Store.message("studio","Tactical Studio","Monday notes, prototype review","Good morning,\n\nThe prototype is ready for a short review. We have updated the keyboard map and the spacing in the header, as discussed on Monday.\n\nCould you try it this week and tell us what still feels slow?\n\nBest,\nTactical Studio","Work","Today","08:15",true),
        Store.message("nils","Nils Berger","Train details for Friday","Hi Lorenz,\n\nThe train leaves at 08:34 from platform 7. Our seats are in carriage 24. I have attached the ticket and the rest of the travel notes.\n\nSee you on Friday,\nNils","Work","Yesterday","18:20",false),
        Store.message("quiet","Quiet Hours","Your weekly summary","You made room for three focused sessions and kept two evenings free.\n\nTake a little time for yourself this week.","Personal","Yesterday","07:00",false),
        Store.message("newsletter","Studio Newsletter","A few things worth reading","Quieter interfaces, thoughtful tools, and making software feel calm.\n\nThis week's reading list is ready.","Personal","Monday","16:02",true),
        Store.message("anna","Anna Richter","A small question about Tuesday","Hi Lorenz,\n\nWould Tuesday still work for you? I can make either 11:00 or 14:30.\n\nAnna","Personal","Monday","11:47",true),
        Store.message("lea","Lea Hoffmann","Feedback on the reading view","The denser overview is much easier to scan. A little more room around the sender would help.\n\nThanks for sharing it!","Personal","Monday","09:30",true),
        Store.message("book","Bookshop","Your reservation is ready","The book you asked us to set aside has arrived.\n\nYou can collect it any time this week.","Personal","Sunday","18:40",false),
        Store.message("felix","Felix Braun","Photos from the weekend","Here are a few pictures from our walk. The light by the lake was lovely.","Personal","Sunday","12:05",false),
        Store.message("lena","Lena Fischer","Re: The Dusk and Moss pass","Here are the two palettes as we left them on Friday.","Work","Monday","10:05",false),
        Store.message("colour","Studio Newsletter","Colour for calm software","Three palettes that stay quiet on dark grounds.","Personal","12 Oct","12:00",false)
    ];
    messages[4].bodyHtml = [
        "<style>.stories{width:100%;max-width:600px}.stories td{width:50%;padding:12px;vertical-align:top}",
        "@media(max-width:420px){.stories td{display:block;width:auto}}</style>",
        "<h2>This week's reading list</h2>",
        "<table class='stories' width='600' cellspacing='0'><tr>",
        "<td><strong>Quieter interfaces</strong><p>How to make software feel calm.</p></td>",
        "<td><strong>Thoughtful tools</strong><p>Small choices that help people focus.</p></td>",
        "</tr></table>"
    ].join("");
    messages[0].files=[{id:"review",name:"Review summary.pdf",path:"fixtures/review-summary.pdf",bytes:895,detail:"6 pages, 180 kB",kind:"document",content:"Design review\n\nDusk and Moss palettes\n\nKeep the navigation quiet. Give the sender and date one line. Put attachments with the message they belong to.\n\nKeyboard review\nTab moves between controls. Escape returns to the inbox. Every action has a keyboard equivalent."}];
    messages[0].files.push({id: "header-notes", name: "Header notes.md",
        path: "fixtures/header-notes.md", kind: "document"});
    messages[0].history=[{id:"lena-first",from:"Lena Fischer",date:"Monday",body:"Here are the two palettes as we left them on Friday.",expanded:false},{id:"nils-first",from:"Nils Berger",date:"Yesterday",body:"The moss reads well on dark. The header spacing still feels tight.",expanded:false}];
    messages[0].cc="nils.berger@example.com, lena.fischer@example.com";
    Object.assign(messages[0].history[0], {address:"lena.fischer@example.com", to:"lorenz@moss.example", cc:"mara.klein@example.com, nils.berger@example.com"});
    Object.assign(messages[0].history[1], {address:"nils.berger@example.com", to:"lorenz@moss.example", cc:"mara.klein@example.com, lena.fischer@example.com"});
    var packet = ["01 Overview", "02 Navigation", "03 Keyboard shortcuts", "04 Layout and spacing",
        "05 Dusk palette", "06 Moss palette", "07 Accessibility", "08 Attachment previews",
        "09 Review questions", "10 Next steps"];
    messages[1].files = packet.map(function(name, index) {
        return {id:"prototype-"+(index+1), name:name+".md", path:"fixtures/prototype-review/"+name+".md", bytes:[89,79,104,98,75,87,89,91,91,80][index]};
    });
    messages[1].body += "\n\nThe ten notes in the review packet are attached.";
    messages[2].starred=true;messages[2].files=[{id:"ticket",name:"Train ticket.pdf",path:"fixtures/train-ticket.pdf",bytes:790,detail:"1 page, 94 kB",kind:"document",content:"Friday\nDeparture 08:34 · Platform 7\nCarriage 24 · Seat 42"}];
    var travelNotes = [
        ["Seat reservation", "Carriage 24 · Seats 42 and 43"],
        ["Friday itinerary", "08:34 departure · Meet at platform 7 at 08:20."],
        ["Transfer instructions", "Follow the signs to platform 3 after arrival."],
        ["Hotel confirmation", "Check-in from 15:00. Reservation under Berger."],
        ["Return journey", "Sunday · 17:12 departure from platform 4."]
    ];
    messages[2].files.push(...travelNotes.map(function(note, index) {
        return {id:"travel-"+(index+1), name:note[0]+".md", kind:"document", content:note[1], bytes:encodeURIComponent(note[1]).replace(/%[0-9A-F]{2}/g, "x").length};
    }));
    messages[2].files.push(
        {id:"travel-cells", name:"Cells.jpg", path:"fixtures/Cells.jpg", kind:"image", bytes:398499},
        {id:"travel-moss", name:"Moss.jpg", path:"fixtures/Moss.jpg", kind:"image", bytes:309416},
        {id:"travel-terracotta", name:"Terracotta.jpg", path:"fixtures/Terracotta.jpg", kind:"image", bytes:170341},
        Object.assign({}, messages[0].files[0], {id:"travel-review"})
    );
    messages[7].category="Receipts";messages[5].category="Family";messages[1].category="Clients";messages[9].folder="Archive";messages[10].folder="Archive";
    var s = Store.emptyMailbox();
    s.accounts = [{name:"Personal",email:"lorenz@example.com",provider:"Google"},{name:"Work",email:"lorenz@moss.example",provider:"Fastmail"}];
    s.messages = messages;
    s.ui.selected = "mara";
    var d=Store.makeDraft(s,"mara","Reply all",true);s.drafts.push(d);
    const roastmarket = Store.message("roastmarket", "roastmarket", "Roastmarket Newsletter",
        "Hallo Kaffeefan,\n\nEntdecke die aktuellen Kaffeeangebote von roastmarket.",
        "Personal", "12 Oct", "10:30", false);
    roastmarket.bodyHtmlFixture = "roastmarket";
    messages.push(roastmarket);
    const richText = Store.message("rich-text", "Moss Studio", "Rich-Text-Beispiel · Notizen zur Designrunde",
        "Hallo Lorenz,\n\nDie Designrunde ist am Donnerstag. Bitte prüfe bis dahin den Mail-Editor.\n\n"
        + "1. Öffne einen Entwurf.\n2. Prüfe Listen, Links und Schriftgrößen.\n\n"
        + "Merker: Der Fokus soll beim Schreiben sichtbar bleiben.\n\n"
        + "Vorschau: tacit-mail --preview\nDesignsystem: https://design.tacitos.co/\n\nDanke!\nMoss Studio",
        "Work", "Yesterday", "12:30", false);
    richText.bodyHtml = [
        "<p>Hallo Lorenz,</p>",
        "<p>Die Designrunde ist am <strong>Donnerstag</strong>. Bitte prüfe bis dahin den <em>Mail-Editor</em>.</p>",
        "<ol><li>Öffne einen Entwurf.</li><li>Prüfe Listen, Links und Schriftgrößen.</li></ol>",
        "<blockquote><mark>Merker:</mark> Der Fokus soll beim Schreiben sichtbar bleiben.</blockquote>",
        "<p>Vorschau: <code>tacit-mail --preview</code><br>Designsystem: <a href='https://design.tacitos.co/'>Tacit</a></p>",
        "<p><img width='470' height='278' alt='Katze mit Lauchstange' src='tacit-fixture:funny-cat-52'></p>",
        "<p>Danke!<br>Moss Studio</p>"
    ].join("");
    richText.bodyHtmlFixture = "rich-text";
    richText.files = [{
        id: "rich-text-cat",
        inline: true,
        name: "funny-cat-52.gif",
        path: "fixtures/funny-cat-52.gif",
        kind: "image",
        bytes: 410569
    }];
    messages.push(richText);
    if(surface==="switch")s.ui.rail=true;
    if(surface==="plain"){s.ui.selected="studio";messages[1].unread=false;}
    if(surface==="html"){s.ui.selected="newsletter";messages[4].unread=false;}
    if(surface==="roastmarket")s.ui.selected="roastmarket";
    if(surface==="draft"){s.ui.view="draft";s.ui.draftId=d.id;}
    if(surface==="compose"){var n=Store.makeDraft(s,"","New message",false);n.to="Anna Ri";s.drafts.push(n);s.ui.draftId=n.id;s.ui.view="compose";}
    if(surface==="search"){s.ui.query="palettes";s.ui.searching=true;}
    if(surface==="empty"){s.ui.folder="Spam";s.ui.selected="";}
    if(surface==="setup"||surface==="settings")s.ui.view=surface;

    if(surface==="importing"){s.ui.view="importing";s.ui.imported=1240;}
    if(surface==="notify"){s.ui.view="read";s.ui.selected="anna";}
    if(surface==="sent"||surface==="offline"){s.ui.draftId=d.id;s.ui.online=surface!=="offline";s=reduce(s,"send",{now:0});s.ui.notice="";}
    return s;
}

function restoreJob(s,job){var m=Store.find(s,job.conversation);if(m)m.replies=m.replies.filter(function(r){return r.id!==job.id;});if(!s.drafts.some(function(d){return d.id===job.draft.id;}))s.drafts.push(Store.copy(job.draft));s.ui.draftId=job.draft.id;s.ui.selected=job.conversation;s.ui.view=job.draft.conversation?"draft":"compose";s.jobs=s.jobs.filter(function(j){return j.id!==job.id;});if(job.created){s.messages=s.messages.filter(function(m){return m.id!==job.conversation;});s.ui.selected="";}}
function reduce(previous, action, p) {
    p = p || {};
    var s = Store.copy(previous), u = s.ui, m = Store.current(s), d = Store.draft(s);
    s.now = p.now === undefined ? s.now : p.now;
    switch (action) {
    case "attach":
        return Store.reduce(previous, action, Object.assign({name:"Notes.md", url:"file:///test/Notes.md"}, p));
    case "send":
        if (d && typeof p.body === "string" && typeof p.bodyHtml === "string") {
            d.body = p.body;
            d.bodyHtml = p.bodyHtml;
        }
        if(!Store.canSend(d)){u.notice="Add valid recipients and a message or attachment.";break;}
        var originalDraft=Store.copy(d);var created=!d.conversation;if(created){var own=Store.message("sent-"+(++s.sequence),"You",d.subject||"No subject",d.body,d.account,"Today","Now",false);own.folder="Sent";own.outgoing=true;own.address=d.to;own.files=[];s.messages.unshift(own);d.conversation=own.id;u.selected=own.id;m=own;}else m=Store.find(s,d.conversation);
        var sendId="send-"+(++s.sequence),expires=s.now+s.settings.undoSeconds*1000;var sent={id:sendId,body:d.body,bodyHtml:d.bodyHtml??"",to:d.to,cc:d.cc,files:Store.copy(d.files),agent:d.agent,edited:d.edited,status:u.online?"sending":"queued",date:"Now"};m.replies.push(sent);s.jobs.push({id:sendId,conversation:m.id,draft:originalDraft,expires:expires,created:created});s.drafts=s.drafts.filter(function(x){return x.id!==d.id;});u.view="read";u.notice=u.online?"Sending · you can still undo":"No connection. Your message is waiting safely.";u.undo=null;break;
    case "tick":
        s.jobs=s.jobs.filter(function(j){if(s.now<j.expires||!u.online)return true;var thread=Store.find(s,j.conversation);if(thread){var r=thread.replies.find(function(x){return x.id===j.id;});if(r)r.status="sent";}u.notice="Message sent (local preview)";return false;});
        if(u.view==="importing"){u.imported=Math.min(8600,u.imported+1240);if(u.imported===8600){u.view="read";u.account="All accounts";u.selected="studio";s.messages[1].unread=false;u.notice="Your mail is ready (local preview)";}}break;
    case "undoSend":if(s.jobs.length){var last=s.jobs[s.jobs.length-1];if(s.now<=last.expires||!u.online){restoreJob(s,last);u.notice="Sending cancelled. Your draft is ready.";}}break;
    case "editQueued":var j=s.jobs.find(function(x){return x.conversation===u.selected;});if(j)restoreJob(s,j);break;
    case "retry":if(u.online){s.jobs.forEach(function(j){if(j.conversation===u.selected)j.expires=s.now;});return reduce(s,"tick",{now:s.now});}u.notice="Still offline. Your message remains queued.";break;
    case "online":u.online=p.value===undefined?!u.online:!!p.value;s.jobs.forEach(function(j){var mail=Store.find(s,j.conversation);var reply=mail&&mail.replies.find(function(r){return r.id===j.id;});if(reply)reply.status=u.online?"sending":"queued";});u.notice=u.online?"Back online (local preview)":"Working offline";break;
    case "connect":
        if(!Store.validRecipients(u.providerEmail)){u.notice="Enter a valid email address for the preview.";break;}
        if(!s.accounts.some(function(a){return a.email===u.providerEmail;}))s.accounts.push({name:u.providerEmail.split("@")[0],email:u.providerEmail,provider:u.provider||"Another provider"});u.provider="";u.view="importing";u.imported=0;u.notice="Connecting locally · no sign-in or network request";break;
    case "removeAccount":
        if(s.accounts.length<=1){u.notice="Keep one account in this preview.";break;}var account=s.accounts.find(function(a){return a.email===p.email;});if(account){Store.remember(s);s.accounts=s.accounts.filter(function(a){return a.email!==p.email;});s.messages=s.messages.filter(function(x){return x.account!==account.name;});s.drafts=s.drafts.filter(function(x){return x.account!==account.name;});u.notice="Account removed from this preview";}break;
    case "notify":u.notification=s.settings.notifications!=="Off";if(!Store.find(s,"anna-notification")){var incoming=Store.message("anna-notification","Anna Richter","A small question about Tuesday","Hi Lorenz,\n\nWould Tuesday still work for you? I can make either 11:00 or 14:30.\n\nAnna","Personal","Today","Now",true);if(s.settings.agentSort)incoming.category="Family";s.messages.unshift(incoming);if(s.settings.agentDrafts&&(s.settings.agentScope==="All accounts"||s.settings.agentScope==="Personal only"))s.drafts.push(Store.makeDraft(s,incoming.id,"Reply",true));}else Store.find(s,"anna-notification").unread=true;break;
    case "openNotification":u.notification=false;u.view="read";u.folder="Inbox";u.account="All accounts";u.selected=Store.find(s,"anna-notification")?"anna-notification":"anna";Store.find(s,u.selected).unread=false;if(p.reply||p.agent)return reduce(s,"reply",{mode:"Reply",agent:!!p.agent});break;
    case "readNotification":var n=Store.find(s,"anna-notification")||Store.find(s,"anna");n.unread=false;u.notification=false;break;
    case "dismissNotification":u.notification=false;if(u.view==="notification")u.view="read";break;
    case "saveAttachment":u.notice="Save to Files requested for "+p.name+" (local preview)";break;
    default: return Store.reduce(previous, action, p);
    }
    return s;
}
