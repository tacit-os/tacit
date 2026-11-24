// SPDX-License-Identifier: GPL-3.0-or-later
package quotedbody

import (
	"strings"
	"testing"
)

// Anonymized structural reproduction of an Outlook mail: the ruled header and
// its quoted body are siblings, with labels nested at differing inline depths.
func TestOutlookNestedLabelsAndRuledHeader(t *testing.T) {
	header := `<div><div style="border:none;border-top:solid #E1E1E1 1pt;padding:3pt 0 0"><p class="MsoNormal"><b><span style="font-size:11pt">Von:</span></b><span style="font-size:11pt"> Author &lt;author@example.test&gt;<br><b>Gesendet:</b> Monday<br><b>An:</b> Recipient &lt;recipient@example.test&gt;<br><b>Betreff:</b> Example<o:p></o:p></span></p></div></div>`
	history := header + `<p>Unindented old mail</p><blockquote>Older mail</blockquote>`
	body := `<html><body><div><p>New answer</p><p>Signature</p>` + history + `</div></body></html>`
	got := SplitHTML(body)
	check(t, body, got, history)
	for _, part := range got {
		if part.Kind == Content && strings.Contains(part.Content, "Unindented old mail") {
			t.Fatal("old mail remained in main body")
		}
	}
}

func TestHeaderLabelsInNewProseAreNotEnough(t *testing.T) {
	body := `<p>New answer listing these fields: <b>From:</b> author <b>Sent:</b> today <b>To:</b> recipient <b>Subject:</b> example</p><p>Still new content</p>`
	check(t, body, SplitHTML(body), "")
}
