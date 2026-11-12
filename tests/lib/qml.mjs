// Reads the parts of a QML file the tests run under node: a function's body, a property's expression, and the settings
// JsonAdapter's tree of defaults. A text reader, not a QML engine: it knows strings, comments, regular expressions and
// brackets, which is all these files need.

// the index just past the string, comment, template or regular expression that starts at i, or i when none starts there
function skipQuoted(src, i) {
  const c = src[i];
  if (c === "/" && src[i + 1] === "/") { const n = src.indexOf("\n", i); return n < 0 ? src.length : n; }
  if (c === "/" && src[i + 1] === "*") { const n = src.indexOf("*/", i + 2); return n < 0 ? src.length : n + 2; }
  // a regular expression, told from a division by what comes before it: an operator, an opening bracket, return or
  // nothing (its brackets, as in /^\s*listener\s*\{/, are not the code's); one that does not end on its line is not one
  if (c === "/") {
    let k = i - 1;
    while (k >= 0 && /\s/.test(src[k])) k--;
    if (k < 0 || /[(,=:[!&|?{};+\-*%<>~^]/.test(src[k]) || /(^|[^\w$])return$/.test(src.slice(Math.max(0, k - 6), k + 1))) {
      let inClass = false;
      for (let j = i + 1; j < src.length && src[j] !== "\n"; j++) {
        if (src[j] === "\\") j++;
        else if (src[j] === "[") inClass = true;
        else if (src[j] === "]") inClass = false;
        else if (src[j] === "/" && !inClass) return j + 1;
      }
    }
    return i;
  }
  if (c === '"' || c === "'" || c === "`") {
    for (let j = i + 1; j < src.length; j++) {
      if (src[j] === "\\") { j++; continue; }
      if (c === "`" && src[j] === "$" && src[j + 1] === "{") { j = matchBrace(src, j + 1); continue; }
      if (src[j] === c) return j + 1;
    }
    return src.length;
  }
  return i;
}

// the index of the bracket that closes the one at open
export function matchBrace(src, open) {
  const pairs = { "{": "}", "(": ")", "[": "]" };
  const stack = [pairs[src[open]]];
  for (let i = open + 1; i < src.length; i++) {
    const j = skipQuoted(src, i);
    if (j !== i) { i = j - 1; continue; }
    if (pairs[src[i]]) stack.push(pairs[src[i]]);
    else if (src[i] === stack[stack.length - 1] && stack.pop() && !stack.length) return i;
  }
  throw new Error(`no closing bracket for ${src[open]} at ${open}`);
}

// function <name>(<params>) { <body> }: the nth one in the file (0 the first), or null
export function qmlFunction(src, name, nth = 0) {
  const re = new RegExp(`\\bfunction\\s+${name}\\s*\\(`, "g");
  let m;
  for (let k = 0; (m = re.exec(src)); k++) {
    if (k < nth) continue;
    const open = m.index + m[0].length - 1, close = matchBrace(src, open);
    const brace = src.indexOf("{", close);
    return { params: src.slice(open + 1, close), body: src.slice(brace + 1, matchBrace(src, brace)) };
  }
  return null;
}

// the expression after "<name>:" (a property binding), read to the end of its line; a line ending in an operator, or a
// next line starting with one, carries on
export function readExpression(src, start) {
  let out = "", i = start;
  while (i < src.length) {
    const j = skipQuoted(src, i);
    if (j !== i) { if (!(src[i] === "/" && "/*".includes(src[i + 1]))) out += src.slice(i, j); i = j; continue; }
    const c = src[i];
    if ("([{".includes(c)) { const e = matchBrace(src, i); out += src.slice(i, e + 1); i = e + 1; continue; }
    if (c === "\n" || c === ";" || c === "}") {
      const rest = src.slice(i + 1).match(/^\s*(\S\S?)/);
      const more = c === "\n" && (/[-+*/%?:,&|=<>!]$/.test(out.trim()) || (rest && /^(\?|:|\.|&&|\|\||\+|-[^-])/.test(rest[1])));
      if (!more) break;
    }
    out += c; i++;
  }
  return { expr: out.trim(), end: i };
}

// "property <type> <name>: <expr>" in the file: the expression's text, or null
export function qmlProperty(src, name) {
  const m = new RegExp(`\\bproperty\\s+[\\w.<>]+\\s+${name}\\s*:`).exec(src);
  return m ? readExpression(src, m.index + m[0].length).expr : null;
}

// Runs code with the names in scope looked up in scope first (a QML file's ids and properties), then in node's own
// globals. Sloppy mode on purpose: "with" is how QML's scope lookup is put back.
export function inScope(scope, params, body) {
  const proxy = new Proxy(scope, {
    has: (t, k) => k in t || !(k in globalThis),
    get: (t, k) => (k === Symbol.unscopables ? undefined : k in t ? t[k] : unknown(String(k))),
    set: (t, k, v) => ((t[k] = v), true),
  });
  const fn = new Function("__scope", `with (__scope) { return function (${params}) {${body}\n}; }`)(proxy);
  return (...args) => fn(...args);
}

// a name the scope does not have: any use of it reads as one more unknown, so a default that names the machine
// (Directories.home) stays a recognisable placeholder instead of throwing
const UNKNOWN = Symbol("unknown");
function unknown(path) {
  const f = function () { return unknown(`${path}()`); };
  return new Proxy(f, {
    get: (t, k) => (k === UNKNOWN ? path : k === Symbol.toPrimitive ? () => `<${path}>` : k === "toString" ? () => `<${path}>` : unknown(`${path}.${String(k)}`)),
    apply: () => unknown(`${path}()`),
  });
}
const isUnknown = v => typeof v === "function" && v[UNKNOWN] !== undefined;

const typeDefault = { bool: false, int: 0, real: 0, double: 0, string: "", url: "", color: "", var: undefined };

function coerce(type, v) {
  if (isUnknown(v)) return `<${v[UNKNOWN]}>`;
  if (type === "int" && typeof v === "number") return Math.trunc(v);
  if (/^list</.test(type)) return Array.from(v ?? []);
  return v;
}

// The settings tree a Config.qml's JsonAdapter writes when nothing is set: { key: default, nested: { ... } }, in
// declaration order, as JSON would hold it.
export function adapterDefaults(src) {
  const at = src.indexOf("JsonAdapter {");
  if (at < 0) throw new Error("no JsonAdapter in this file");
  return readObject(src, src.indexOf("{", at) + 1).obj;
}

function readObject(src, i) {
  const obj = {};
  for (;;) {
    while (i < src.length) {
      const j = skipQuoted(src, i);
      if (j !== i) { i = j; continue; }
      if (/\s|;/.test(src[i])) { i++; continue; }
      break;
    }
    if (i >= src.length || src[i] === "}") return { obj, end: i + 1 };
    const line = src.slice(i, src.indexOf("\n", i) < 0 ? src.length : src.indexOf("\n", i));
    const m = /^(?:(?:readonly|required|default)\s+)*property\s+([\w.]+(?:<[\w.]+>)?)\s+(\w+)\s*(:)?\s*/.exec(line);
    if (!m) {
      // id:, a handler, a function or a child object: not part of the file
      const brace = line.search(/[{(]/);
      const end = brace < 0 ? i + line.length : matchBrace(src, i + brace) + 1;
      i = brace < 0 ? end : readExpression(src, end).end;
      continue;
    }
    const [, type, name, colon] = m;
    i += m[0].length;
    if (!colon) { obj[name] = typeDefault[type] ?? null; continue; }
    if (/^JsonObject\s*\{/.test(src.slice(i))) {
      const r = readObject(src, src.indexOf("{", i) + 1);
      obj[name] = r.obj;
      i = r.end;
      continue;
    }
    const { expr, end } = readExpression(src, i);
    i = end;
    let v;
    try { v = inScope({}, "", `return (${expr});`)(); } catch (e) { v = `<${expr}>`; }
    obj[name] = coerce(type, v);
  }
}

// A file read into an adapter: each key the adapter declares takes the file's value when the file has one, nested
// objects key by key; what the adapter does not declare is not kept.
export function loadInto(defaults, file) {
  const out = {};
  for (const [k, d] of Object.entries(defaults)) {
    const f = file?.[k];
    if (d && typeof d === "object" && !Array.isArray(d)) out[k] = loadInto(d, f && typeof f === "object" ? f : {});
    else out[k] = f === undefined ? structuredClone(d) : structuredClone(f);
  }
  return out;
}

// Config.qml's migrate() run over options, as Config would: { options, wrote } (wrote: how many times it wrote the
// file). A Config.qml without a migrate() leaves options as they are.
export function runMigrate(src, options) {
  const f = qmlFunction(src, "migrate");
  const ver = +(src.match(/currentConfigVersion:\s*(\d+)/)?.[1] ?? 0);
  let wrote = 0;
  const root = { options, currentConfigVersion: ver, writeNow() { wrote++; } };
  if (f) inScope({ root }, f.params, f.body)();
  return { options, wrote, version: ver };
}

// the leaves of a settings tree as "a.b.c" -> value
export function leaves(obj, prefix = "", out = {}) {
  for (const [k, v] of Object.entries(obj)) {
    const p = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) leaves(v, p, out);
    else out[p] = v;
  }
  return out;
}
