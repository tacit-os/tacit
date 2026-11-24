const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const path = require('node:path');
const store = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../mail-store.js'), 'utf8'), store);
const row = (id, folder = 'Inbox', count = 1) => Object.assign(
    store.message(id, 'Sender', 'Subject', 'Body', 'Work', 'Today', '12:00', false),
    {folder, backendAccount: 'work', backendConversation: id, folderMessageCount: count, folderOtherStarred: false});
const key = folder => store.backendViewKey(folder, 'All accounts', 'All mail', 'Newest first');
let state = store.replaceBackendView(store.emptyMailbox(), [row('moved', 'Inbox', 3), row('next')], key('Inbox'));
state.ui.selected = 'moved';
state = store.reduce(state, 'move', {folder: 'Archive'});
assert.deepEqual(Array.from(store.results(state), entry => entry.id), ['next']);
state = store.replaceBackendView(state, [row('next')], key('Inbox'));
state = store.replaceBackendView(state, [row('moved', 'Archive'), row('arrived', 'Archive')], key('Archive'));
state = store.replaceSearchRows(state, [row('search-only', 'Spam')], 'needle');
const search = state.search;
state = store.reduce(state, 'undo');
assert.deepEqual(Array.from(store.results(state), entry => entry.id), ['moved', 'next']);
assert.equal(store.results(state)[0].folderMessageCount, 3);
assert.equal(store.find(state, 'moved').folder, 'Inbox');
assert.equal(state.search.query, search.query);
assert.deepEqual(Array.from(state.search.ids), ['search-only']);
assert.equal(store.find(state, 'arrived').folder, 'Archive');
assert.equal(Object.hasOwn(store.find(state, 'moved'), 'folderMessageCount'), false);
state = store.removeMessages(state, ['moved'], true);
assert.equal(store.find(state, 'moved'), null);
assert.equal(store.results(state).some(entry => entry.id === 'moved'), false);
console.log('Backend list views: ordered IDs, independent thread metadata, immediate Undo, new-query retention and deletion passed');
