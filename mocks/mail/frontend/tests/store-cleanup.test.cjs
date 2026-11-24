const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const store = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../mail-store.js'), 'utf8'), store);
const fixtures = vm.createContext({Store: store});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname, 'fixtures/mailbox-responses.js'), 'utf8').replace(/^\.import[^\n]*\n/gm, ''), fixtures);
const cases = [
    ['rail', {}, {rail: false}],
    ['filter', {value: 'Unread'}, {filter: 'Unread'}],
    ['sort', {value: 'Sender'}, {sort: 'Sender'}],
    ['preview', {file: {id: 'attachment'}}, {attachment: {id: 'attachment'}}],
    ['closePreview', {}, {attachment: null}],
    ['settings', {}, {view: 'settings', rail: false}],
    ['back', {}, {view: 'read', provider: '', attachment: null}],
    ['setup', {}, {view: 'setup', provider: '', rail: false}],
    ['provider', {name: 'Provider'}, {provider: 'Provider'}],
    ['providerEmail', {text: 'me@example.test'}, {providerEmail: 'me@example.test'}],
    ['notice', {text: 'Notice'}, {notice: 'Notice'}],
    ['clearNotice', {}, {notice: '', undo: null}]
];
for (const [action, payload, changes] of cases) {
    let before = store.emptyMailbox();
    before = fixtures.replaceMailboxRows(before, [store.message('mail', 'Sender', 'Subject', 'Body', 'Work', 'Today', '12:00', false)]);
    Object.assign(before.ui, {view: 'draft', rail: true, provider: 'Old', attachment: {id: 'old'}, undo: {selected: 'mail'}});
    before = store.replaceSearchRows(before, store.mailboxMessages(before), 'retained');
    const originalUi = JSON.parse(JSON.stringify(before.ui));
    const fail = () => { throw new Error('A UI-only action must not serialize the mail store'); };
    Object.defineProperty(before, 'toJSON', {value: fail});
    Object.defineProperty(before.records, 'toJSON', {value: fail});
    const next = store.reduce(before, action, Object.assign({now: 1234}, payload));
    assert.notEqual(next, before, action);
    assert.notEqual(next.ui, before.ui, action);
    assert.equal(next.now, 1234, action);
    assert.equal(JSON.stringify(next.ui), JSON.stringify(Object.assign({}, originalUi, changes)), action);
    assert.equal(JSON.stringify(before.ui), JSON.stringify(originalUi), action);
    for (const field of ['records', 'mailboxIds', 'drafts', 'jobs', 'accounts', 'settings', 'search'])
        assert.equal(next[field], before[field], action + ': ' + field);
}
function freeze(value) {
    if (value && typeof value === 'object') {
        Object.values(value).forEach(freeze);
        Object.freeze(value);
    }
    return value;
}
const accounts = freeze([{id: 'work', name: 'Work account'}]);
const raw = freeze([
    {id: 'mail', account_id: 'work', conversation_id: 'thread', mailbox: 'Inbox',
        from: {email: 'sender@example.test'}, to: [{email: 'me@example.test'}], cc: [{email: 'other@example.test'}],
        subject: 'Subject', body_text: 'Plain body', body_html: '<p>HTML</p><img src="cid:picture">',
        date: '2026-11-16T12:00:00Z', unread: true, gmail_labels: ['SENT', 'STARRED', 'IMPORTANT'],
        remote_images: [{url: 'https://example.invalid/picture'}], remote_images_allowed: true,
        attachments: [{id: 'picture', filename: 'image.png', media_type: 'image/png', size: 42}]},
    {id: 'draft', mailbox: 'Drafts'}, {id: 'outbox', mailbox: 'Outbox'}
]);
const rows = store.mailboxRows(accounts, raw);
assert.equal(rows.length, 1);
const row = rows[0];
assert.equal(row.id, 'mail'); assert.equal(row.backendConversation, 'thread');
assert.equal(row.account, 'Work account'); assert.equal(row.backendAccount, 'work');
assert.equal(row.from, 'sender@example.test'); assert.equal(row.to, 'me@example.test');
assert.equal(row.cc, 'other@example.test'); assert.equal(row.body, 'Plain body');
assert.equal(row.bodyHtml, raw[0].body_html); assert.equal(row.timestamp, Date.parse(raw[0].date));
assert.equal(row.unread, true); assert.equal(row.gmailSent, true);
assert.equal(row.starred, true); assert.equal(row.important, true);
assert.equal(row.remoteImagesAllowed, true); assert.equal(row.remoteImages, raw[0].remote_images);
assert.equal(row.files[0].inline, true); assert.equal(row.files[0].kind, 'image');
assert.equal(row.files[0].messageId, 'mail'); assert.equal(row.files[0].bytes, 42);
console.log('Store cleanup: UI-only transitions preserve data and avoid serialization; mailbox row mapping preserves message metadata');
