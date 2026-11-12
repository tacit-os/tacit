.pragma library

// Agent markdown to the HTML subset Qt's rich text draws, so spacing and colour are ours:
// Qt's own MarkdownText gives no line height, bare inline code, 40px list indents and link
// blue. Fenced code is split out before this (StringUtils.splitMarkdownBlocks → CodeBlock).
// Lists and quotes are tables: that is the only way to set their indent and marker colour.
// Single newlines stay line breaks, as the agent's terminal renderer keeps them.
//
// t: { text, strong, dim, link, code, codeBg, rule, mono, size, codeSize, lh, gap, h1, h2, h3 }

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// codes: the code spans taken out, shared with a link's label, which holds their placeholders when it comes back here
function inline(s, t, codes = []) {
    s = s.replace(/`([^`\n]+)`/g, (m, c) => { codes.push(c); return "\u0001" + (codes.length - 1) + "\u0001"; });
    const links = [];
    s = s.replace(/\[([^\]\n]+)\]\(([^)\s]+)\)/g, (m, label, url) => { links.push([label, url]); return "\u0002" + (links.length - 1) + "\u0002"; });
    s = esc(s);
    s = s.replace(/(^|[\s(])(https?:\/\/[^\s<)\]]+[^\s<)\].,;:!?'"])/g, (m, pre, url) => `${pre}<a href="${url}" style="color:${t.link}; text-decoration:none">${url}</a>`);
    s = s.replace(/\*\*([^*\n]+)\*\*/g, `<span style="font-weight:600; color:${t.strong}">$1</span>`);
    s = s.replace(/__([^_\n]+)__/g, `<span style="font-weight:600; color:${t.strong}">$1</span>`);
    s = s.replace(/(^|[^*\w])\*([^*\s][^*\n]*?)\*(?![*\w])/g, "$1<i>$2</i>");
    s = s.replace(/(^|[^_\w])_([^_\s][^_\n]*?)_(?![_\w])/g, "$1<i>$2</i>");
    s = s.replace(/~~([^~\n]+)~~/g, "<s>$1</s>");
    s = s.replace(/\u0002(\d+)\u0002/g, (m, i) => `<a href="${links[i][1]}" style="color:${t.link}; text-decoration:none">${inline(links[i][0], t, codes)}</a>`);
    // Padded with thin spaces, except where punctuation follows: Qt breaks lines after any
    // space (even U+202F), so "`x`," could leave the comma alone at the start of a line.
    s = s.replace(/\u0001(\d+)\u0001([.,;:!?)]?)/g, (m, i, p) =>
        `<span style="font-family:'${t.mono}'; font-size:${t.codeSize}px; color:${t.code}; background-color:${t.codeBg}">&#8201;${esc(codes[i])}${p ? "" : "&#8201;"}</span>${p}`);
    return s;
}

function para(inner, t, extra) {
    return `<p style="margin-top:0px; margin-bottom:${t.gap}px; line-height:${t.lh}%;${extra ?? ""}">${inner}</p>`;
}

const LIST = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
const RULE = /^\s*([-*_])(\s*\1){2,}\s*$/;
const HEAD = /^(#{1,6})\s+(.*?)\s*#*\s*$/;

function startsBlock(line) {
    return LIST.test(line) || HEAD.test(line) || RULE.test(line) || /^\s*>/.test(line) || /^\s*\|/.test(line);
}

function list(lines, i, t) {
    const base = LIST.exec(lines[i])[1].length;
    const ordered = /\d/.test(LIST.exec(lines[i])[2]);
    let rows = "";
    let n = 0;
    while (i < lines.length) {
        const m = LIST.exec(lines[i]);
        if (!m || m[1].length < base) break;
        if (m[1].length > base) {   // a nested list belongs to the item above
            const sub = list(lines, i, t);
            rows = rows.replace(/<\/td><\/tr>$/, sub.html + "</td></tr>");
            i = sub.next;
            continue;
        }
        n++;
        let body = m[3];
        i++;
        while (i < lines.length && lines[i].trim().length && !LIST.test(lines[i]) && !startsBlock(lines[i].replace(/^\s+/, "")) && /^\s/.test(lines[i])) {
            body += "\n" + lines[i].trim();
            i++;
        }
        const marker = ordered ? `${n}.` : "•";
        rows += `<tr><td width="${ordered ? 22 : 16}" valign="top" style="color:${t.dim}">${para(marker, t, " margin-bottom:4px;")}</td>`
            + `<td valign="top">${para(inline(body, t).replace(/\n/g, "<br/>"), t, " margin-bottom:4px;")}</td></tr>`;
        while (i < lines.length && !lines[i].trim().length && i + 1 < lines.length && LIST.test(lines[i + 1]) && LIST.exec(lines[i + 1])[1].length >= base) i++;
    }
    return { html: `<table cellspacing="0" cellpadding="0" style="margin-bottom:${t.gap - 4}px">${rows}</table>`, next: i };
}

function table(lines, i, t) {
    const cells = l => l.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => c.trim());
    const head = cells(lines[i]);
    i += 2;
    // rules between rows only, drawn as one-pixel rows (Qt has no per-side cell borders), padding on
    // each cell so a rule row stays one pixel; the header row on the code tint in the strong tone:
    // lighter than the full grid, which out-weighed the words in it
    const n = head.length;
    const ruleRow = `<tr><td colspan="${n}" height="1" style="background-color:${t.rule}; font-size:1px; padding:0px"></td></tr>`;
    const pad = "padding:8px 12px 8px 0px";
    let html = `<table cellspacing="0" cellpadding="0" style="margin-top:4px; margin-bottom:${t.gap + 4}px"><tr>`
        + head.map(c => `<td style="${pad}; font-weight:600; color:${t.strong}">${inline(c, t)}</td>`).join("") + "</tr>" + ruleRow;
    while (i < lines.length && /^\s*\|/.test(lines[i])) {
        html += "<tr>" + cells(lines[i]).map(c => `<td style="${pad}">${inline(c, t)}</td>`).join("") + "</tr>" + ruleRow;
        i++;
    }
    return { html: html + "</table>", next: i };
}

// A row is built again each time it scrolls back into view: the same message is converted once and kept
// (by its text and the colours it was drawn with), up to 3000 of them.
var htmlCache = ({});
var htmlCount = 0;
function toHtml(md, t) {
    const key = t.text + t.strong + t.dim + t.link + t.code + t.codeBg + t.rule + "\u0001" + md;
    const hit = htmlCache[key];
    if (hit !== undefined)
        return hit;
    if (++htmlCount > 3000) { htmlCache = ({}); htmlCount = 1; }
    return (htmlCache[key] = toHtmlUncached(md, t));
}
function toHtmlUncached(md, t) {
    const lines = md.replace(/\r/g, "").split("\n");
    let html = "";
    let i = 0;
    while (i < lines.length) {
        const line = lines[i];
        if (!line.trim().length) { i++; continue; }
        let m;
        if ((m = HEAD.exec(line))) {
            const size = m[1].length === 1 ? t.h1 : m[1].length === 2 ? t.h2 : t.h3;
            html += `<p style="margin-top:${html.length ? t.gap + 6 : 0}px; margin-bottom:${Math.round(t.gap / 2)}px; font-size:${size}px; font-weight:600; color:${t.strong}">${inline(m[2], t)}</p>`;
            i++;
        } else if (RULE.test(line)) {
            html += `<table width="100%" cellspacing="0" cellpadding="0" style="margin-bottom:${t.gap}px"><tr><td height="1" style="background-color:${t.rule}"></td></tr></table>`;
            i++;
        } else if (/^\s*>/.test(line)) {
            const quote = [];
            while (i < lines.length && /^\s*>/.test(lines[i])) quote.push(lines[i++].replace(/^\s*>\s?/, ""));
            html += `<table cellspacing="0" cellpadding="0" style="margin-bottom:${t.gap}px"><tr><td width="3" style="background-color:${t.rule}"></td>`
                + `<td width="12"></td><td style="color:${t.dim}">${toHtml(quote.join("\n"), t)}</td></tr></table>`;
        } else if (/^\s*\|/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}/.test(lines[i + 1])) {
            const r = table(lines, i, t);
            html += r.html;
            i = r.next;
        } else if (LIST.test(line)) {
            const r = list(lines, i, t);
            html += r.html;
            i = r.next;
        } else {
            const body = [];
            while (i < lines.length && lines[i].trim().length && !(body.length && startsBlock(lines[i]))) body.push(lines[i++].trim());
            html += para(inline(body.join("\n"), t).replace(/\n/g, "<br/>"), t);
        }
    }
    return html;
}

function plain(text) {
    return esc(text).replace(/\n/g, "<br/>");
}
