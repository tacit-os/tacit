// SPDX-License-Identifier: GPL-3.0-or-later

package quotedbody

import (
	"io"
	"strings"

	"golang.org/x/net/html"
)

type element struct {
	headerBits           int
	textBeforeHeader     bool
	textBytes            int
	hasMedia             bool
	tag                  string
	start, innerEnd, end int
	quote, separator     bool
	parent               *element
}
type atom struct{ start, end int }

// SplitHTML recognizes trailing client quote containers. It tokenizes without
// reserializing HTML, preserving styles, entities, CID references and whitespace.
// A separator includes following siblings in the same container. Ambiguous HTML
// and bodies consisting entirely of quotes are left intact.
func SplitHTML(body string) []Part {
	if len(body) > MaxBytes {
		return nil
	}
	root := &element{end: len(body), innerEnd: len(body)}
	stack := []*element{root}
	elements := []*element{}
	atoms := []atom{}
	z := html.NewTokenizer(strings.NewReader(body))
	offset := 0
	for count := 0; ; count++ {
		if count > maxTokens || len(stack) > maxDepth {
			return nil
		}
		kind := z.Next()
		raw := z.Raw()
		start := offset
		offset += len(raw)
		parent := stack[len(stack)-1]
		if kind == html.ErrorToken {
			if z.Err() != io.EOF {
				return nil
			}
			break
		}
		switch kind {
		case html.StartTagToken, html.SelfClosingTagToken:
			token := z.Token()
			n := &element{tag: token.Data, start: start, parent: parent}
			n.quote = token.Data == "blockquote"
			for _, a := range token.Attr {
				if a.Key == "class" {
					for _, c := range strings.Fields(a.Val) {
						if c == "gmail_quote" || strings.HasPrefix(c, "yahoo_quoted") || c == "protonmail_quote" {
							n.quote = true
						}
					}
				}
				if a.Key == "id" && (a.Val == "divRplyFwdMsg" || a.Val == "appendonsend") {
					n.separator = true
				}
			}
			elements = append(elements, n)
			if token.Data == "img" || token.Data == "video" || token.Data == "audio" || token.Data == "hr" {
				atoms = append(atoms, atom{start, offset})
				for n := parent; n != nil; n = n.parent {
					n.hasMedia = true
				}
			}
			if kind == html.SelfClosingTagToken || voidElement(token.Data) {
				n.end = offset
				n.innerEnd = offset
			} else {
				stack = append(stack, n)
			}
		case html.EndTagToken:
			token := z.Token()
			if len(stack) == 1 || parent.tag != token.Data {
				return nil
			}
			parent.innerEnd = start
			parent.end = offset
			stack = stack[:len(stack)-1]
		case html.TextToken:
			text := strings.TrimSpace(string(z.Text()))
			if text != "" && !inMetadata(parent) {
				atoms = append(atoms, atom{start, offset})
				if parent.tag == "b" || parent.tag == "span" || parent.tag == "strong" {
					container := parent.parent
					// Outlook nests labels inside different inline wrappers.
					for inlineElement(container.tag) && container.parent != nil {
						container = container.parent
					}
					bit := headerLabel(strings.ToLower(text))
					if bit != 0 && container != root && container.tag != "body" && container.tag != "html" {
						if container.headerBits == 0 {
							container.textBeforeHeader = container.textBytes > 0
						}
						container.headerBits |= bit
					}
				}
				marker := strings.Trim(strings.ToLower(text), "- _")
				if parent.textBytes == 0 && strings.Contains(text, "---") && (parent.tag == "div" || parent.tag == "p" || parent.tag == "i") &&
					(marker == "original message" || marker == "ursprüngliche nachricht" || marker == "originalnachricht") {
					parent.separator = true
				}
				for n := parent; n != nil; n = n.parent {
					n.textBytes += len(text)
				}
			}
		}
	}
	if len(stack) != 1 {
		return nil
	}
	// Candidates are ordered and nested source intervals. Merge them in one pass
	// so checking text after quotes stays linear even for deeply nested histories.
	ranges := []span{}
	for _, n := range elements {
		header := n.headerBits == 15 && !n.textBeforeHeader && n.textBytes < 4096
		if !n.quote && !n.separator && !header {
			continue
		}
		if header {
			// Word often puts the ruled header in one or more otherwise empty
			// divs, while the old body follows outside those wrappers.
			for n.parent != root && (n.parent.tag == "div" || n.parent.tag == "p") &&
				n.parent.textBytes == n.textBytes && !n.parent.hasMedia {
				n = n.parent
			}
		}
		end := n.end
		if n.separator || header {
			end = n.parent.innerEnd
		}
		if end <= n.start || invalidContainer(n.parent.tag) {
			continue
		}
		s := span{n.start, end}
		if len(ranges) > 0 && s.start <= ranges[len(ranges)-1].end {
			if s.end > ranges[len(ranges)-1].end {
				ranges[len(ranges)-1].end = s.end
			}
		} else {
			ranges = append(ranges, s)
		}
	}
	lastContent := -1
	i := 0
	for _, a := range atoms {
		for i < len(ranges) && ranges[i].end <= a.start {
			i++
		}
		if i == len(ranges) || a.start < ranges[i].start {
			lastContent = a.end
		}
	}
	if lastContent < 0 {
		return nil
	}
	var trailing []span
	atomIndex := 0
	for _, s := range ranges {
		if s.start < lastContent {
			continue
		}
		// Do not offer an accordion for empty decorative blockquotes.
		for atomIndex < len(atoms) && atoms[atomIndex].start < s.start {
			atomIndex++
		}
		if atomIndex < len(atoms) && atoms[atomIndex].end <= s.end {
			trailing = append(trailing, s)
		}
	}
	if len(trailing) == 0 {
		return nil
	}
	return splitSpans(body, trailing)
}
func inMetadata(n *element) bool {
	for ; n != nil; n = n.parent {
		switch n.tag {
		case "head", "style", "script", "title", "noscript":
			return true
		}
	}
	return false
}
func invalidContainer(tag string) bool {
	switch tag {
	case "table", "thead", "tbody", "tfoot", "tr", "select", "ul", "ol":
		return true
	}
	return false
}
func voidElement(tag string) bool {
	switch tag {
	case "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr":
		return true
	}
	return false
}

func headerLabel(text string) int {
	switch text {
	case "from:", "von:":
		return 1
	case "sent:", "date:", "gesendet:", "datum:":
		return 2
	case "to:", "an:":
		return 4
	case "subject:", "betreff:":
		return 8
	}
	return 0
}

func inlineElement(tag string) bool {
	switch tag {
	case "span", "b", "strong", "i", "em", "font":
		return true
	}
	return false
}
