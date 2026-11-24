// SPDX-License-Identifier: GPL-3.0-or-later

package quotedbody

import "strings"

const (
	Content       = "content"
	QuotedHistory = "quotedHistory"
	// Version changes whenever detection rules change, to invalidate derived data.
	Version = 2
	// MaxBytes bounds work per body. Larger bodies remain fully visible.
	MaxBytes  = 2 << 20
	maxTokens = 100000
	maxDepth  = 256
)

// Part is a consecutive, unchanged span of a body in its original format.
// HTML parts are source segments, not independently balanced HTML documents.
// Consumers must preserve their order and document context.
type Part struct {
	Kind    string `json:"kind"`
	Content string `json:"content"`
}

type span struct{ start, end int }

func parts(body string, quote span) []Part { return splitSpans(body, []span{quote}) }

func splitSpans(body string, quotes []span) []Part {
	out := make([]Part, 0, 2*len(quotes)+1)
	offset := 0
	for _, q := range quotes {
		if q.start > offset {
			out = append(out, Part{Content, body[offset:q.start]})
		}
		out = append(out, Part{QuotedHistory, body[q.start:q.end]})
		offset = q.end
	}
	if offset < len(body) {
		out = append(out, Part{Content, body[offset:]})
	}
	return out
}

// SplitText identifies a quoted tail. Inline answers and signatures following
// >-quoted lines keep that quote visible. Header separators require corroborating
// quote lines or a From/Sent/To/Subject header block (English or German).
func SplitText(body string) []Part {
	if len(body) > MaxBytes {
		return nil
	}
	lines := strings.SplitAfterN(body, "\n", maxTokens+1)
	if len(lines) > maxTokens {
		return nil
	}
	offset, start := 0, -1
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, ">") {
			if start < 0 {
				start = offset
			}
		} else if trimmed != "" {
			start = -1
		}
		lower := strings.ToLower(trimmed)
		attribution := (strings.HasPrefix(lower, "on ") && strings.HasSuffix(lower, "wrote:")) ||
			(strings.HasPrefix(lower, "am ") && strings.Contains(lower, "schrieb") && strings.HasSuffix(lower, ":"))
		if attribution && onlyQuoteLines(lines[i+1:]) {
			start = offset
			break
		}
		marker := strings.Trim(strings.TrimSpace(lower), "- _")
		if (marker == "original message" || marker == "originalnachricht" || marker == "ursprüngliche nachricht") && headerBlock(lines[i+1:]) {
			start = offset
			break
		}
		if (strings.HasPrefix(lower, "from:") || strings.HasPrefix(lower, "von:")) && headerBlock(lines[i:]) {
			start = offset
			break
		}
		offset += len(line)
	}
	if start < 0 || strings.TrimSpace(body[:start]) == "" {
		return nil
	}
	return parts(body, span{start, len(body)})
}
func onlyQuoteLines(lines []string) bool {
	found := false
	for _, line := range lines {
		s := strings.TrimSpace(line)
		if s == "" {
			continue
		}
		if !strings.HasPrefix(s, ">") {
			return false
		}
		found = true
	}
	return found
}
func headerBlock(lines []string) bool {
	var from, date, to, subject bool
	for i, line := range lines {
		if i >= 8 {
			break
		}
		s := strings.ToLower(strings.TrimSpace(line))
		if s == "" {
			if from && date && to && subject {
				return true
			}
			continue
		}
		switch {
		case strings.HasPrefix(s, "from:"), strings.HasPrefix(s, "von:"):
			from = true
		case strings.HasPrefix(s, "sent:"), strings.HasPrefix(s, "date:"), strings.HasPrefix(s, "gesendet:"), strings.HasPrefix(s, "datum:"):
			date = true
		case strings.HasPrefix(s, "to:"), strings.HasPrefix(s, "an:"):
			to = true
		case strings.HasPrefix(s, "subject:"), strings.HasPrefix(s, "betreff:"):
			subject = true
		}
	}
	return from && date && to && subject
}
