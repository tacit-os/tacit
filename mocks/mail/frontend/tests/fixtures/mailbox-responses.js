.import "../../mail-store.js" as Store

// These helpers materialize already ordered provider responses. They do not
// decide membership, search, sorting, grouping or counters.
function replaceMailboxRows(state, rows) {
    return Store.pruneMessages(Object.assign({}, Store.upsertMessages(state, rows), {
        mailboxIds: Store.stableIds(state.mailboxIds, Array.from(new Set(rows.map(row => row.id))))
    }));
}

function fromMailbox(state, messages, sourceRows) {
    const rows = Store.mailboxRows(state.accounts, messages);
    const drafts = Store.mailboxDrafts(state.accounts, messages, sourceRows || rows);
    return orderedView(Object.assign({}, replaceMailboxRows(state, rows), {
        drafts, jobs: [],
        ui: Object.assign({}, state.ui, {
            selected: rows.some(row => row.id === state.ui.selected)
                ? state.ui.selected : rows.find(row => row.folder === "Inbox")?.id || "",
            view: drafts.some(draft => draft.id === state.ui.draftId) ? state.ui.view : "read"
        })
    }));
}



function orderedView(state) {
    if (state.ui.searching || state.ui.folder === "Drafts") return state;
    const rows = Store.mailboxMessages(state).map(row => Object.assign({}, row, {
        folderMessageCount: row.folderMessageCount ?? 1,
        folderOtherStarred: row.folderOtherStarred ?? false
    }));
    return Store.replaceBackendView(state, rows,
        Store.backendViewKey(state.ui.folder, state.ui.account, state.ui.filter, state.ui.sort));
}
function projected(state, ids) {
    const rows = ids.map(id => Store.find(state, id)).filter(Boolean).map(row => Object.assign({}, row, {
        folderMessageCount: 1, folderOtherStarred: false
    }));
    return Store.results(Store.replaceBackendView(state, rows,
        Store.backendViewKey(state.ui.folder, state.ui.account, state.ui.filter, state.ui.sort)));
}
