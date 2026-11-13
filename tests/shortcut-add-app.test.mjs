// Settings > Keyboard & touchpad > Shortcuts > "Add a shortcut for an app" (modules/settings/AddApp.qml): the apps its
// search lists and the help line under it, run under node on a pretend list of installed apps. A word the palette finds
// an app by (its GenericName or Keywords) finds it here too, and the help says when the 8 shown are not all.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Add a shortcut for an app (AddApp.qml)");
const src = read("modules/settings/AddApp.qml");
const help = readExpression(src, src.lastIndexOf("text:", src.indexOf('"Pick the app')) + 5).expr;

function opened(apps, query) {
  const add = { query, taken: [] };
  const scope = { add, DesktopEntries: { applications: { values: apps } }, Shortcuts: { apps: [] } };
  const value = e => (e.startsWith("{") ? inScope(scope, "", e.slice(1, -1)) : inScope(scope, "", `return (${e});`));
  for (const name of ["matching", "found"]) {
    const e = qmlProperty(src, name);
    if (e) Object.defineProperty(add, name, { get: value(e) });
  }
  return { names: add.found.map(e => e.name), help: inScope(scope, "", `return (${help});`)() };
}
const app = (name, more = {}) => ({ name, command: [name.toLowerCase()], noDisplay: false, runInTerminal: false, ...more });
const installed = [app("Thyris", { genericName: "Web Browser", keywords: ["internet", "www"] }),
  app("Foot", { genericName: "Terminal" }), app("Files"), app("Browser Tools")];

{
  const r = opened(installed, "browser");
  check(`"browser" finds Thyris, whose GenericName is Web Browser`, r.names.includes("Thyris"), `found ${JSON.stringify(r.names)}`);
  check("and an app with it in its name comes first", r.names[0] === "Browser Tools", JSON.stringify(r.names));
  check(`"www" finds it by its Keywords`, opened(installed, "www").names.includes("Thyris"));
  check(`"files" still finds Files by its name`, opened(installed, "files").names.join() === "Files");
}
{
  const many = Array.from({ length: 60 }, (_, i) => app(`App ${String(i).padStart(2, "0")}`));
  const r = opened(many, "");
  check("60 apps: the list shows 8", r.names.length === 8, String(r.names.length));
  check("and the help says there are more to find by typing", /type to find more/i.test(r.help), r.help);
  const few = opened(installed, "");
  check("4 apps: all shown, and the help says nothing of more", few.names.length === 4 && !/more/i.test(few.help), few.help);
  check("nothing matches: the help says so", opened(installed, "zzz").help === "No app has that name.");
}
done();
