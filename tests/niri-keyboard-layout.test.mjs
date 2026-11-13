// The keyboard layout services/NiriConfig.qml writes into niri's qssettings/shell.kdl: the settings' defaults, a
// settings.json from before read as the JsonAdapter reads it and put through migrate() (when the file has one), then
// generateShellKdl() under node on what came of it.
import { adapterDefaults, inScope, loadInto, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the keyboard layout in niri's shell.kdl (NiriConfig.qml)");
const src = read("services/NiriConfig.qml");
const defaults = adapterDefaults(src);
const gen = qmlFunction(src, "generateShellKdl"), esc = qmlFunction(src, "kdlEscape"), migrate = qmlFunction(src, "migrate");

// a settings.json as it is on disk; what shell.kdl then says about the keyboard
function shellKdl(file) {
  const adapter = loadInto(defaults, file);
  if (migrate) inScope({ adapter }, migrate.params, migrate.body)();
  let kdl = "";
  const root = { generatedHeader: inScope({}, "", `return (${qmlProperty(src, "generatedHeader")});`)() };
  root.kdlEscape = inScope({ root }, esc.params, esc.body);
  inScope({ root, adapter, shellKdlFile: { setText: t => (kdl = t) } }, gen.params, gen.body)();
  return { adapter, xkb: kdl.split("\n").filter(l => l.includes("xkb")).map(l => l.trim()) };
}

check("a new settings file has no layout of its own", defaults.input.kbLayout === "", JSON.stringify(defaults.input.kbLayout));
{
  const r = shellKdl(null);
  check("so a first start writes no xkb line, and niri keeps its layout", r.xkb.length === 0, r.xkb.join(" | "));
}
{
  const r = shellKdl({ input: { kbLayout: "us", repeatDelay: 600 } });
  check("a settings.json the first start wrote with the old \"us\" no longer sets a US keyboard", r.xkb.length === 0, r.xkb.join(" | "));
}
{
  const r = shellKdl({ input: { kbLayout: "ch" } });
  check("a layout chosen in Settings is written", r.xkb.join() === 'xkb { layout "ch"; }', r.xkb.join(" | "));
}
{
  const r = shellKdl({ version: 1, input: { kbLayout: "us" } });
  check("and \"us\" chosen after the update is kept", r.xkb.join() === 'xkb { layout "us"; }', r.xkb.join(" | "));
}
{
  const r = shellKdl({ version: 1, input: { kbLayout: 'us"' } });
  check("a quote typed in the layout cannot end the KDL string", r.xkb.join() === 'xkb { layout "us\\""; }', r.xkb.join(" | "));
}
done();
