// SPDX-License-Identifier: GPL-3.0-or-later

package quotedbody

import (
	"strings"
	"testing"
)

func TestText(t *testing.T) {
	for _, tt := range []struct{ name, body, quote string }{
		{"plain", "Just a new message", ""},
		{"english", "Thanks!\n\nOn Tuesday, Alex wrote:\n> Old message\n> more", "On Tuesday, Alex wrote:\n> Old message\n> more"},
		{"german", "Danke!\r\n\r\nAm 21.11.2026 schrieb Alex:\r\n> Alte Nachricht", "Am 21.11.2026 schrieb Alex:\r\n> Alte Nachricht"},
		{"quote only", "> Everything is quoted", ""},
		{"inline reply", "New\n> Question\nMy answer", ""},
		{"signature after", "New\n> Old\n-- \nMy signature", ""},
		{"original", "New\n\n-----Original Message-----\nFrom: Alex\nSent: Tuesday\nTo: Pat\nSubject: Hello\n\nOld", "-----Original Message-----\nFrom: Alex\nSent: Tuesday\nTo: Pat\nSubject: Hello\n\nOld"},
		{"outlook german", "Neu\n\nVon: Alex <a@example.org>\nGesendet: Dienstag\nAn: Pat\nBetreff: Hallo\n\nAlt", "Von: Alex <a@example.org>\nGesendet: Dienstag\nAn: Pat\nBetreff: Hallo\n\nAlt"},
		{"prose", "Here is an example\nOn Tuesday we wrote:\nSomething new", ""},
	} {
		t.Run(tt.name, func(t *testing.T) { check(t, tt.body, SplitText(tt.body), tt.quote) })
	}
}
func check(t *testing.T, body string, parts []Part, quote string) {
	t.Helper()
	if quote == "" {
		if len(parts) != 0 {
			t.Fatalf("unexpected split: %#v", parts)
		}
		return
	}
	var original, quoted strings.Builder
	for _, p := range parts {
		original.WriteString(p.Content)
		if p.Kind == QuotedHistory {
			quoted.WriteString(p.Content)
		} else if p.Kind != Content {
			t.Fatalf("unknown kind %q", p.Kind)
		}
	}
	if original.String() != body {
		t.Fatal("split changed original bytes")
	}
	if quoted.String() != quote {
		t.Fatalf("quote = %q, want %q", quoted.String(), quote)
	}
}
func TestHTML(t *testing.T) {
	for _, tt := range []struct{ name, body, quote string }{
		{"empty quote", "New<blockquote><br></blockquote>", ""},
		{"outlook header", "<p>New</p><div><b>From:</b> Alex<br><b>Sent:</b> Tuesday<br><b>To:</b> Pat<br><b>Subject:</b> Hello</div><p>Old</p>", "<div><b>From:</b> Alex<br><b>Sent:</b> Tuesday<br><b>To:</b> Pat<br><b>Subject:</b> Hello</div><p>Old</p>"},
		{"german header", "<p>Neu</p><div><b>Von:</b> Alex<br><b>Gesendet:</b> Dienstag<br><b>An:</b> Pat<br><b>Betreff:</b> Hallo</div><p>Alt</p>", "<div><b>Von:</b> Alex<br><b>Gesendet:</b> Dienstag<br><b>An:</b> Pat<br><b>Betreff:</b> Hallo</div><p>Alt</p>"},
		{"original marker", "<p>New</p><div>-----Original Message-----</div><p>Old</p>", "<div>-----Original Message-----</div><p>Old</p>"},
		{"different ancestors", "<div>New<blockquote>Old</blockquote></div><div><blockquote>Older</blockquote></div>", "<blockquote>Old</blockquote><blockquote>Older</blockquote>"},
		{"signature after quote", "New<blockquote>Old</blockquote><div class='gmail_signature'>My signature</div>", ""},
		{"metadata only", "<style>p{color:red}</style><blockquote>Only quote</blockquote>", ""},
		{"broken close", "New<div><blockquote>Old</div></blockquote>", ""},
		{"table unsafe insertion", "New<table><tr><blockquote>Old</blockquote></tr></table>", ""},
		{"unchanged", "<style>p{color:red}</style><p>Hello &amp; bye</p>", ""},
		{"gmail", "<p>New</p><div class='gmail_quote'><p>Old</p></div>", "<div class='gmail_quote'><p>Old</p></div>"},
		{"yahoo", "<p>New</p><div class='yahoo_quoted_123'>Old</div>", "<div class='yahoo_quoted_123'>Old</div>"},
		{"proton", "New<div class='protonmail_quote'>Old</div>", "<div class='protonmail_quote'>Old</div>"},
		{"apple", "<p>New</p><blockquote type='cite'>Old</blockquote>", "<blockquote type='cite'>Old</blockquote>"},
		{"nested", "<html><head><style>p{color:red}</style></head><body><div><p>New</p><blockquote>Old<blockquote>Older</blockquote></blockquote></div></body></html>", "<blockquote>Old<blockquote>Older</blockquote></blockquote>"},
		{"inline", "<p>New</p><blockquote>Question</blockquote><p>Answer</p>", ""},
		{"image answer", "New<blockquote>Old</blockquote><img src='cid:answer'>", ""},
		{"quote only", "<div class='gmail_quote'>Newly composed content</div>", ""},
		{"outlook", "<div>New<div id='divRplyFwdMsg'>From: Alex</div><p>Old</p></div>", "<div id='divRplyFwdMsg'>From: Alex</div><p>Old</p>"},
		{"malformed", "New<blockquote>Old", ""},
		{"script marker", "<script>var x='<blockquote>Old</blockquote>'</script><p>New</p>", ""},
		{"void", "New<br><blockquote>Old<img src='cid:x'></blockquote>", "<blockquote>Old<img src='cid:x'></blockquote>"},
		{"separate quote", "New<blockquote>Question</blockquote>Answer<blockquote>Old tail</blockquote>", "<blockquote>Old tail</blockquote>"},
	} {
		t.Run(tt.name, func(t *testing.T) { check(t, tt.body, SplitHTML(tt.body), tt.quote) })
	}
}
func TestLimits(t *testing.T) {
	if len(SplitHTML(strings.Repeat("x", MaxBytes+1)+"<blockquote>Old</blockquote>")) != 0 {
		t.Fatal("oversized HTML was parsed")
	}
	if len(SplitText(strings.Repeat("x", MaxBytes+1)+"\n> Old")) != 0 {
		t.Fatal("oversized text was parsed")
	}
}
func FuzzSplit(f *testing.F) {
	f.Add("New<blockquote>Old</blockquote>")
	f.Add("New\n> Old")
	f.Fuzz(func(t *testing.T, s string) {
		for _, parts := range [][]Part{SplitHTML(s), SplitText(s)} {
			if len(parts) == 0 {
				continue
			}
			var b strings.Builder
			for _, p := range parts {
				b.WriteString(p.Content)
			}
			if b.String() != s {
				t.Fatal("lost original bytes")
			}
		}
	})
}
func BenchmarkHTML(b *testing.B) {
	body := "<html><body><p>New message</p><div class='gmail_quote'>" + strings.Repeat("<p>Old message</p>", 1000) + "</div></body></html>"
	b.ReportAllocs()
	b.SetBytes(int64(len(body)))
	for i := 0; i < b.N; i++ {
		SplitHTML(body)
	}
}
