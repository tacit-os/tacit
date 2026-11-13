// The keys list (Super+/, the palette's keys section): services/HyprlandKeybinds.qml's keybinds from the tree's own key
// files, read by its own parser (scripts/hyprland/get_keybinds.py), and what the person changed in Settings > Shortcuts
// (services/Shortcuts.qml's state: a key moved, a key taken off, an app given keys), flattened as PaletteSearch does.
// The list must name the keys the compositor holds (tacit/shortcuts.lua applies the same moves).
import { execFileSync } from "child_process";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the keys list and Settings > Shortcuts (HyprlandKeybinds.qml, Shortcuts.qml)");
const src = read("services/HyprlandKeybinds.qml"), shortcutsSrc = read("services/Shortcuts.qml");
const parse = file => JSON.parse(execFileSync("python3", [join(tree, "scripts/hyprland/get_keybinds.py"), "--path", join(tree, file)], { encoding: "utf8" }));
// a binding's value: an expression, or a block that returns one ({ const m = {}; ...; return m; })
const value = (scope, expr) => /^\{[\s\S]*\breturn\b/.test(expr) ? inScope(scope, "", expr.slice(1, -1))() : inScope(scope, "", `return (${expr});`)();
const shipped = parse("session/hypr/hyprland/keybinds.lua"), session = parse("session/hypr/tacit/keybinds.lua");

function shortcuts(changed, apps) {
  const S = { changed, apps };
  for (const name of ["groups", "modOrder", "rowIndex"]) S[name] = value({ root: S, Qt: {} }, qmlProperty(shortcutsSrc, name));
  for (const name of ["norm", "forHypr", "moves", "slotsOf", "keysOf", "capName", "said"]) {
    const f = qmlFunction(shortcutsSrc, name);
    S[name] = inScope({ root: S }, f.params.replace(/:\s*\w+/g, ""), f.body);
  }
  return S;
}
function list(changed = {}, apps = []) {
  const root = { defaultKeybinds: shipped, sessionKeybinds: session, userKeybinds: { children: [], keybinds: [] } };
  // the binding names the singleton's own properties bare, as QML lets it
  const scope = { root, Shortcuts: shortcuts(changed, apps), defaultKeybinds: root.defaultKeybinds, sessionKeybinds: root.sessionKeybinds,
    userKeybinds: root.userKeybinds };
  for (const name of ["topSection", "asBind", "withShortcuts"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  const keybinds = value(scope, qmlProperty(src, "keybinds"));
  const flat = node => [...(node.keybinds ?? []), ...(node.children ?? []).flatMap(flat)];
  return flat(keybinds).filter(b => b.comment).map(b => `${[...b.mods, b.key].join(" + ")}: ${b.comment}`);
}
const has = (rows, row) => rows.includes(row);

{
  const rows = list();
  check("Super+Space, the notch, is in the list", has(rows, "SUPER + Space: Shell: Open the notch"));
  check("and Super+Escape, the session menu", has(rows, "SUPER + Escape: Shell: Session (lock, log out, power)"));
  check("with nothing changed, Files is on Super+E", has(rows, "SUPER + E: Shell: Files"));
}
{
  // Files moved to Super+Shift+E; the Text editor's Super+X taken off; Viewer given Super+B
  const rows = list({ files: ["Super+Shift+E"], text: [""] }, [{ name: "Viewer", run: "gtk-launch viewer", icon: "image", keys: "Super+B" }]);
  check("Files moved to Super+Shift+E is listed there", has(rows, "SUPER + SHIFT + E: Shell: Files"), rows.filter(r => /Files$/.test(r)).join("; "));
  check("and no longer on Super+E", !rows.some(r => r.startsWith("SUPER + E: ")), rows.filter(r => r.startsWith("SUPER + E: ")).join("; "));
  check("a key taken off a shortcut is not listed", !rows.some(r => /: App: Text editor$/.test(r)), rows.filter(r => /Text editor/.test(r)).join("; "));
  check("an app given a key is listed with it", has(rows, "SUPER + B: App: Viewer"), rows.filter(r => /Viewer/.test(r)).join("; ") || "no Viewer row");
}
done();
