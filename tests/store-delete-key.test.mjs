// Apps (store.qml): what is typed with no control holding the keys starts a search, and Delete is not typed. The window's
// own key handler (the item `keys`) runs under node on Delete, whose text is "\x7f", and on a letter.
import { inScope, matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("store.qml");
const at = src.indexOf("Keys.onPressed: e =>", src.indexOf("id: keys"));
const open = src.indexOf("{", at);
const handler = src.slice(open + 1, matchBrace(src, open));

function press(text) {
  const field = { activeFocus: false, cursorPosition: 0, text: "", focused: false,
    forceActiveFocus() { this.focused = true; }, insert(at, t) { this.text = this.text.slice(0, at) + t + this.text.slice(at); } };
  const e = { text, modifiers: 0, accepted: false };
  inScope({ field, root: { askUpdate: null }, Qt: { ControlModifier: 0x4000000, AltModifier: 0x8000000, MetaModifier: 0x10000000 } }, "e", handler)(e);
  return { typed: field.text, codes: [...field.text].map(c => c.charCodeAt(0)), focused: field.focused, accepted: e.accepted };
}

console.log("== Delete in the Apps window is not typed into the search (store.qml)");
const del = press("\x7f");
check("Delete puts nothing in the search and leaves the keys where they were", del.typed === "" && !del.focused && !del.accepted, `characters ${JSON.stringify(del.codes)}, focus ${del.focused}`);
const k = press("k");
check("a letter still starts a search", k.typed === "k" && k.focused && k.accepted, JSON.stringify(k));
done();
