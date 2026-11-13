// The on-screen keyboard's labels (modules/ii/onScreenKeyboard): what scripts/hyprland/xkb_labels.py reads from the
// keymap for French and UK keymaps, and OskContent.qml's own bindings and relabelled() run under node with what it gave,
// then the header's text as OnScreenKeyboard.qml shows it. Its keys send scancodes, so a key's label has to be what the
// compositor's layout types on it; a layout layouts.js has no labels for used to show US labels and say nothing.
import { spawnSync } from "child_process";
import { existsSync } from "fs";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the on-screen keyboard's labels (OskContent.qml, xkb_labels.py)");
const script = join(tree, "scripts/hyprland/xkb_labels.py");
const xkb = (...args) => {
  if (!existsSync(script)) return { status: -1, labels: null };
  const r = spawnSync("python3", ["-I", script, ...args], { encoding: "utf8" });
  let labels = null;
  try { labels = JSON.parse(r.stdout); } catch {}
  return { status: r.status, labels };
};
const fr = xkb("us,fr", ",", "French"), gb = xkb("gb", "", "English (UK)");
const same = (l, code, want) => JSON.stringify(l?.[code]) === JSON.stringify(want);
check("a French keymap: q's key types a, the 1 key & and 1, the [ key the circumflex accent",
  same(fr.labels, 16, ["a", "A"]) && same(fr.labels, 2, ["&", "1"]) && same(fr.labels, 26, ["^", "¨"]), JSON.stringify(fr.labels?.[16]));
check("a UK keymap: the \\ key types # and ~, Shift 2 types \"", same(gb.labels, 43, ["#", "~"]) && same(gb.labels, 3, ["2", '"']));
const none = xkb("us", "", "French");
check("a layout that is not in the keymap gives nothing", none.status !== 0 && none.labels === null, `exit ${none.status}`);

// OskContent with the compositor's layout and what xkb_labels.py answered for it; the header's text
const Layouts = new Function(`${read("modules/ii/onScreenKeyboard/layouts.js")}\nreturn { byName, defaultLayout };`)();
const src = read("modules/ii/onScreenKeyboard/OskContent.qml");
const header = (() => {
  const s = read("modules/ii/onScreenKeyboard/OnScreenKeyboard.qml");
  const m = /StyledText \{\s*Layout\.fillWidth: true\s*text: ([^\n]+)/.exec(s);
  return m[1];
})();
function osk(compositor, keymap) {
  const root = { layouts: Layouts.byName, keymap: keymap ?? { name: "", labels: null } };
  const scope = { root, ...root, Layouts, HyprlandXkb: { currentLayoutName: compositor }, Config: { options: { osk: { layout: "English (US)" } } },
    Translation: { tr: s => Object.assign(new String(s), { arg: a => s.replace("%1", a) }) } };
  const rel = qmlFunction(src, "relabelled");
  if (rel) scope.relabelled = root.relabelled = inScope(scope, rel.params, rel.body);
  for (const name of ["activeLayoutName", "compositorLayout", "unlabelled", "keymapRead", "fromKeymap", "currentLayout", "heading"]) {
    const expr = qmlProperty(src, name);
    if (expr !== null) scope[name] = root[name] = inScope(scope, "", `return (${expr});`)();
  }
  const keys = root.currentLayout.keys.flat();
  return { key: code => keys.find(k => k.keycode === code), heading: String(inScope({ oskContent: root }, "", `return (${header});`)()) };
}
{
  const de = osk("German");
  check("German, which layouts.js has: its own labels, \"DE, QWERTZ\"", de.key(21).label === "z" && de.heading === "DE, QWERTZ", de.heading);
  const french = osk("French", { name: "French", labels: fr.labels });
  check("French, read from the keymap: the q key says a, Shift says A, the 1 key &",
    french.key(16)?.label === "a" && french.key(16)?.labelShift === "A" && french.key(2)?.label === "&", JSON.stringify(french.key(16)));
  check("French: the right Alt says AltGr, Shift and Enter keep theirs",
    french.key(100)?.label === "AltGr" && french.key(42)?.label === "Shift" && french.key(28)?.label === "Enter");
  check("French: the header names it", french.heading === "French", french.heading);
  const failed = osk("French", { name: "French", labels: null });
  check("French when the keymap cannot be read: US labels, and the header says they are",
    failed.key(16)?.label === "q" && failed.heading === "US labels, typing French", failed.heading);
  const waiting = osk("French");
  check("French while the keymap is being read: the header names it, nothing about US yet", waiting.heading === "French", waiting.heading);
  const start = osk("");
  check("before Hyprland has said its layout: the setting's, \"US, QWERTY\"", start.key(16)?.label === "q" && start.heading === "US, QWERTY", start.heading);
}
done();
