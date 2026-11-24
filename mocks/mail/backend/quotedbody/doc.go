// SPDX-License-Identifier: GPL-3.0-or-later

// Package quotedbody identifies a conservative trailing quoted history in email
// bodies. It preserves every original byte: concatenating Part.Content always
// reconstructs the input. A nil result means no safe split was found, not an
// empty message. It does not sanitize HTML, remove signatures, resolve MIME,
// fetch resources, or prove that quoted text duplicates another message.
//
// Algorithm provenance:
//   - Mailspring, app/src/services/quoted-html-transformer.ts (GPL-3.0):
//     https://github.com/Foundry376/Mailspring/blob/master/app/src/services/quoted-html-transformer.ts
//     Recognize client quote containers and header separators; leave quotes
//     visible when followed by unquoted text or images; retain quote-only bodies.
//   - Roundcube, plugins/hide_blockquote/hide_blockquote.js and
//     program/lib/Roundcube/rcube_text2html.php (GPL-3.0-or-later):
//     https://github.com/roundcube/roundcubemail/tree/master/plugins/hide_blockquote
//     https://github.com/roundcube/roundcubemail/blob/master/program/lib/Roundcube/rcube_text2html.php
//     Treat consecutive >-prefixed text lines as quotation blocks and collapse
//     existing quote blocks rather than deleting their contents.
//
// Reviewed November 2026. This is a new Go implementation of those ideas, not a
// source translation. Unlike those implementations, it retains source byte
// ranges, never strips footers/signatures, and declines ambiguous/malformed HTML.
// HTML is tokenized once; work and allocations are bounded by MaxBytes and an
// internal token/depth limit. Returned strings share the input's backing storage.
// The package has no dependency on maild, its database, or its UI.
package quotedbody
