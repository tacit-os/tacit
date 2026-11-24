const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const store = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../mail-store.js'), 'utf8'), store);
const parts = {text: [{kind: 'content', content: 'New\n'}, {kind: 'quotedHistory', content: '> Old'}],
    html: [{kind: 'content', content: '<style>p{color:red}</style><p>New</p>'},
        {kind: 'quotedHistory', content: '<blockquote>Old<img src="cid:old"></blockquote>'}]};
const row = store.mailboxRows([], [{id: 'q', account_id: 'a', mailbox: 'Inbox',
    from: {email: 'a@example.test'}, date: '2026-11-22', attachments: [], body_parts: parts}])[0];
assert.equal(row.bodyParts, parts, 'The projection retains the derived parts');
assert.equal(store.quotedBodyHTML(parts.html, 'fallback'),
    '<style>p{color:red}</style><p>New</p><div data-tacit-quoted-history="" hidden><blockquote>Old<img src="cid:old"></blockquote></div>');
assert.equal(store.quotedBodyHTML([], '<p>Unchanged</p>'), '<p>Unchanged</p>');
assert.equal(store.quotedBodyText(parts.text, 'fallback', false), 'New\n');
assert.equal(store.quotedBodyText(parts.text, 'fallback', true), 'New\n> Old');
assert.equal(store.quotedBodyText([], 'Original', false), 'Original');
console.log('Quoted bodies: projection, original HTML context, CID references, text and fallback passed');
