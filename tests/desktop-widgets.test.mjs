// The desktop's widgets and Settings > Desktop > Widgets (tacit-settings.qml widgetList): every widget the wallpaper can
// show (modules/common/Config.qml, background.widgets.<name>.enable) is one Settings has a switch for, or off. The five
// left out of the list (calendar, notes, to do, media, visualiser) are turned off once by Config's migrate(), run under
// node on a 1.2.14 file that has them on; and Settings' search does not send people to Desktop for them.
import { adapterDefaults, inScope, loadInto, qmlProperty, runMigrate } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the desktop's widgets and their switches (Config.qml, tacit-settings.qml)");
const config = read("modules/common/Config.qml");
const defaults = adapterDefaults(config);
const listed = inScope({}, "", `return (${qmlProperty(read("tacit-settings.qml"), "widgetList")});`)().map(w => w.key);
const drawn = Object.keys(defaults.background.widgets).filter(k => typeof defaults.background.widgets[k]?.enable === "boolean");
const unlisted = drawn.filter(k => !listed.includes(k));
const allOn = version => ({ configVersion: version, background: { widgets: Object.fromEntries(drawn.map(k => [k, { enable: true }])) } });

{
  const { options, wrote } = runMigrate(config, loadInto(defaults, allOn(5)));
  const w = options.background.widgets;
  const left = unlisted.filter(k => w[k].enable);
  check("a 1.2.14 file with every widget on: none is left on that Settings has no switch for", unlisted.length > 0 && left.length === 0 && wrote === 1,
    `still on: ${left.join(", ")} (Settings lists ${listed.join(", ")})`);
  const off = listed.filter(k => !w[k].enable);
  check("and the widgets Settings lists stay as they were", off.length === 0, `turned off: ${off.join(", ")}`);
}
{
  const { version } = runMigrate(config, loadInto(defaults, {}));
  const { options, wrote } = runMigrate(config, loadInto(defaults, allOn(version)));
  check("a file already at this version is left as it is", unlisted.every(k => options.background.widgets[k].enable) && wrote === 0);
}
{
  const desktop = inScope({}, "", `return (${qmlProperty(read("services/SettingsCatalog.qml"), "categories")});`)().find(c => c.key === "desktop");
  const words = ["calendar", "notes", "todo"].filter(w => desktop.words.split(" ").includes(w));
  check("Settings' search does not send \"calendar\", \"notes\" or \"todo\" to Desktop, which has no switch for them",
    words.length === 0, words.join(", "));
}
done();
