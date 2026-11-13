// Settings offers nothing for the bar, which is off and which nothing turns on (panelFamilies/IllogicalImpulseFamily.qml
// loads it only with bar.enable, in no Settings row): services/SettingsPages.qml's list, run under node, has no Bar page
// and names only pages that are there; no Settings file writes island.hideBar; and Config.qml's migrate() leaves a saved
// value of it as it was.
import { existsSync, readdirSync } from "fs";
import { join } from "path";
import { adapterDefaults, inScope, loadInto, qmlProperty, runMigrate } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Settings offers nothing for the bar (SettingsPages.qml, NotchConfig.qml)");
const list = qmlProperty(read("services/SettingsPages.qml"), "list");
const pages = compositor => inScope({ WM: { compositor }, Translation: { tr: s => s } }, "", list.slice(1, -1))();
const all = [...pages("hyprland"), ...pages("niri")];
check("the settings panel has no Bar page", !all.some(p => p.key === "Bar" || p.path === "BarConfig.qml"),
  all.map(p => p.key).join(", "));
const missing = all.filter(p => !existsSync(join(tree, "modules/ii/settings/pages", p.path)));
check("and every page it lists is there", missing.length === 0, missing.map(p => p.path).join(", "));

// every Settings surface: the old panel's pages, the Settings app and its modules
const files = ["tacit-settings.qml",
  ...readdirSync(join(tree, "modules/ii/settings/pages")).map(f => `modules/ii/settings/pages/${f}`),
  ...(existsSync(join(tree, "modules/settings")) ? readdirSync(join(tree, "modules/settings")).filter(f => f.endsWith(".qml")).map(f => `modules/settings/${f}`) : [])];
const writers = files.filter(f => /island\.hideBar\s*=[^=]/.test(read(f)));
check("no Settings switch writes island.hideBar (\"Hide the bar\")", writers.length === 0, writers.join(", "));

const config = read("modules/common/Config.qml");
const saved = loadInto(adapterDefaults(config), { island: { hideBar: false } });
const { options } = runMigrate(config, saved);
check("a hideBar saved as off is left as it was", options.island.hideBar === false, String(options.island.hideBar));
check("and the default is still on", adapterDefaults(config).island.hideBar === true);
done();
