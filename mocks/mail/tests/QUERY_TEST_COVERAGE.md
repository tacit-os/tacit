# List-query regression coverage

The old JavaScript query evaluator and Go `referenceView` have been removed.
Expected query results are authored in `backend/internal/backend/testdata/list-contract.json`; neither
SQLite nor a second evaluator computes the expected IDs, representatives or counters.
The Go store tests embed it as a compile-time input, so edits invalidate the test cache.
The native API integration tests read this same data file.

| Previous reference-dependent checks | Replacement |
| --- | --- |
| Folder/account/filter/sort comparison loops | `TestListViewExplicitContract`: every authored case at page sizes 1, 2, 7 and 100; native `test_explicitBackendContract` also checks the real transport and frontend projection |
| Trash grouping of three messages, account isolation, unread message counters | `trash-thread-star`, `trash-unread`, `trash-account-isolation`, and explicit account/folder counters |
| Archive grouping and unread counts | `archive-thread`, `archive-unread`, explicit counters |
| Gmail received vs sent representatives and message-level search | `inbox-newest`, `sent-received-label-and-explicit`, fixed search ID lists |
| Star on an older thread member; own vs other-member star | Explicit `starred` / `other_starred` fields; `inbox-starred-representative`, `trash-thread-star`; frontend state test consumes pre-grouped responses |
| Gmail STARRED label without flagged=true | `TestListViewGmailLabelStarWithoutFlag` and the frontend DTO/projection assertion |
| Duplicate display names and draft/source account IDs | Existing frontend state mapping/draft assertions retained |
| Equal dates, missing conversation IDs, deterministic ordering | `inbox-newest`, `inbox-oldest`, `inbox-sender`, `inbox-unread-first` at page size 1 |
| Prefix search with umlauts, multiple AND terms, empty results | Fixed `searches` entries; store reopen test and native `test_explicitSearchAndCounters` |
| Cache upgrade previously compared against referenceView | `TestListViewBackfillsExistingCacheAndChecksSelection` compares the authored Inbox rows |

Existing mutation/version, large 215-message HTTP pagination, sender-locale,
normalized-record, deletion, Undo, selection, scroll, retained HTML identity,
three-view retention, initial viewport prefetch and menu/layout tests remain.

UI doubles return prepared, ordered responses. `mailbox-responses.js` only maps
those responses into production store state. The named visual fixture has explicit
ID lists for its UI interactions; it contains no search, sorting or grouping engine.
Local draft display and optimistic updates run through the production store.

The integration runner executes the contract suite once against its own temporary
database. The existing create/send/read workflow keeps its separate persistent
test database, so contract drafts/outbox records cannot alter its assumptions.
