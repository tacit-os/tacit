# quotedbody

A small Go package for identifying trailing email quotations in HTML and plain
text. Independent of maild, Qt, SQLite, providers and network access. The only
runtime dependency is `golang.org/x/net/html`.

`SplitText` and `SplitHTML` return ordered `Part` values with `Kind` (`content` or
`quotedHistory`) and `Content`. Concatenating all contents reconstructs the input
byte for byte. A nil slice means leave the original body fully visible. HTML
parts are source segments within the original document, not separate documents:
keep their order, head/style context, and enclosing elements when rendering.

Only quote tails with preceding new content are collapsed. New content or images
after a quote keep that quote visible. Signatures are not removed. Supported
signals include Gmail, Yahoo/AOL, Proton, blockquotes, Outlook separators,
English/German header blocks and plain-text reply attributions. Detection is
heuristic, not a proof of duplication. Malformed/unbalanced HTML, excessive
nesting, excessive token counts and bodies over 2 MiB are left intact.

The algorithm references and differences are documented in `doc.go`. These files
follow the containing repository's GPL-3.0-or-later license. No client source was
copied. For a standalone release, choose a public module path in `go.mod` and the
example import, and distribute the license text with the package. No publishing
or remote repository setup is needed to use the local module.

Run inside this directory:

```sh
go test -race ./...
go test -run '^$' -bench . -benchmem
go test -run '^$' -fuzz FuzzSplit -fuzztime 30s
```

maild stores both the original bodies and the versioned derived parts. Flag-only
writes reuse the stored result; changed bodies or a new algorithm version cause
recalculation on the next write. Existing messages without derived parts remain
readable in full; this change does not initiate a mailbox-wide backfill.
