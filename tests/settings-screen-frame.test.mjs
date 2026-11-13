// The screen frame has a switch again: Settings > Appearance, the page that holds the desktop's look, has a "Screen
// frame" row on bar.showFrame (the key modules/ii/frame/ScreenFrame.qml reads, its default kept off), which went with the
// Bar page. The row's own bindings run under node, and Settings' search for "screen frame" finds the page.
import { adapterDefaults, inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the screen frame's switch (tacit-settings.qml's Appearance page)");
const src = read("tacit-settings.qml");
const pageAt = src.indexOf("id: lookPage");
const page = src.slice(pageAt, matchBrace(src, src.indexOf("{", pageAt)));
const at = page.indexOf('label: "Screen frame"');
check("Appearance has a Screen frame row", at >= 0);
if (at >= 0) {
  const open = page.lastIndexOf("SwitchRow {", at);
  const row = page.slice(open, matchBrace(page, open + "SwitchRow ".length));
  const expr = name => readExpression(row, row.indexOf(`${name}:`) + name.length + 1).expr;
  const Config = { options: { bar: { showFrame: false } } };
  const value = e => inScope({ Config }, "", `return (${e});`)();
  check("it is a switch, off while the frame is off", value(expr("checked")) === false);
  value(expr("onToggled"))(true);
  check("turning it on turns bar.showFrame on", Config.options.bar.showFrame === true);
  check("and it reads back on", value(expr("checked")) === true);
  value(expr("onToggled"))(false);
  check("turning it off turns it off", Config.options.bar.showFrame === false);
}
check("the frame's default is still off", adapterDefaults(read("modules/common/Config.qml")).bar.showFrame === false);
check("ScreenFrame.qml still draws from bar.showFrame", read("modules/ii/frame/ScreenFrame.qml").includes("Config.options.bar.showFrame"));

const categories = inScope({}, "", `return (${qmlProperty(read("services/SettingsCatalog.qml"), "categories")});`)();
const m = qmlFunction(src, "matches");
const found = query => categories.filter(cat => inScope({ root: { query } }, m.params, m.body)(cat)).map(c => c.key);
check('searching "screen frame" finds Appearance', found("screen frame").includes("look"), JSON.stringify(found("screen frame")));
done();
