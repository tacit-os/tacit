.pragma library

// Syntax colour for one line of code, as rich text. A diff is a long run of single lines in a lazy
// list, so this is a small regex tokenizer, not KSyntaxHighlighting (one highlighter per line is
// heavy, and a highlighter on a recycled document has crashed the app before). It sees one line at
// a time: a block comment opened on an earlier line is coloured only where a line starts with `*`.
// Colours are the Martida theme's roles, passed in from the palette: kw, type, str, num, com, text.

const C_LIKE = ["js", "jsx", "ts", "tsx", "mjs", "cjs", "qml", "rs", "kt", "kts", "java", "c", "h", "cc", "cpp", "hpp", "go", "swift", "cs", "css", "scss", "php", "dart"];
const HASH = ["py", "sh", "bash", "zsh", "fish", "yml", "yaml", "toml", "conf", "ini", "rb", "pl", "r", "mk", "makefile", "service", "desktop", "env"];
const KEYWORDS = new Set(("if else elif for while do switch case default break continue return function fn func def class struct enum trait impl interface type import export from as " +
    "const let var val mut pub use mod static final abstract async await yield new delete in of is not and or try catch finally throw throws raise except with pass lambda " +
    "property signal readonly required id Item Rectangle Text Row Column Component Loader Repeater import package extends implements where self this super override fn match " +
    "then end local elseif nil true false null undefined None True False echo exit fi esac done set unset export").split(" "));
const TYPES = new Set("string number boolean int float double bool void char u8 u16 u32 u64 usize i8 i16 i32 i64 isize str String Vec Option Result Self Map Set Array Object Promise real color url var list alias".split(" "));

function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
function ext(path) { const m = /\.([A-Za-z0-9]+)$/.exec(path || ""); const base = (path || "").split("/").pop().toLowerCase(); return m ? m[1].toLowerCase() : base; }

function html(line, path, pal) {
    const e = ext(path);
    const c = C_LIKE.includes(e), h = HASH.includes(e) || e === "makefile" || e === "dockerfile", lua = e === "lua" || e === "sql" || e === "hs";
    const markup = ["html", "xml", "svg", "htm"].includes(e), json = e === "json";
    if (e === "md" || (!c && !h && !lua && !markup && !json)) return "<span style=\"white-space:pre-wrap\">" + esc(line) + "</span>";
    const parts = [];
    if (c || h || lua) parts.push(c ? "\\/\\/.*|\\/\\*.*?\\*\\/" : h ? "#.*" : "--.*");
    if (markup) parts.push("<!--.*?-->");
    parts.push("\"(?:\\\\.|[^\"\\\\])*\"?|'(?:\\\\.|[^'\\\\])*'?|`(?:\\\\.|[^`\\\\])*`?");
    parts.push("\\b0[xX][0-9a-fA-F_]+\\b|\\b\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?[a-zA-Z]*\\b");
    if (markup) parts.push("<\\/?[A-Za-z][^>]*>");
    parts.push("[A-Za-z_$][\\w$]*");
    const re = new RegExp(parts.join("|"), "g");
    let out = "", last = 0, m;
    const span = (txt, col, extra) => `<span style="color:${col};${extra ?? ""}">${esc(txt)}</span>`;
    // a doc-comment continuation line
    if (c && /^\s*\*(\s|\/|$)/.test(line)) return `<span style="white-space:pre-wrap;color:${pal.com};font-style:italic">${esc(line)}</span>`;
    while ((m = re.exec(line)) !== null) {
        const t = m[0];
        out += esc(line.substring(last, m.index));
        last = m.index + t.length;
        if (t.startsWith("//") || t.startsWith("/*") || (h && t.startsWith("#")) || (lua && t.startsWith("--")) || t.startsWith("<!--")) out += span(t, pal.com, "font-style:italic");
        else if (t[0] === "\"" || t[0] === "'" || t[0] === "`") {
            // a JSON key reads as a name, not a string
            const isKey = json && /^\s*:/.test(line.substring(last));
            out += span(t, isKey ? pal.kw : pal.str);
        }
        else if (/^\d/.test(t)) out += span(t, pal.num);
        else if (t[0] === "<") out += span(t, pal.kw);
        else if (KEYWORDS.has(t)) out += span(t, pal.kw);
        else if (TYPES.has(t) || /^[A-Z][A-Za-z0-9]+$/.test(t) && !json) out += span(t, pal.type);
        else out += esc(t);
    }
    out += esc(line.substring(last));
    return "<span style=\"white-space:pre-wrap\">" + out + "</span>";
}
