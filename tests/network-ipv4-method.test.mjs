// Settings > Network's IPv4 Apply on a connection whose method its list does not have (modules/ii/settings/pages/
// NetworkConfig.qml): the Address list's model and onSelected and the Apply button's enabled binding run under node, with
// what services/Network.qml's setIpv4Config() would write for that method.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== IPv4 Apply on a hotspot's shared connection (NetworkConfig.qml)");
const src = read("modules/ii/settings/pages/NetworkConfig.qml");
const combo = objectWith(src, 'buttonIcon: "settings_ethernet"');
const apply = objectWith(src, 'Translation.tr("Applying")');
const expr = (block, key) => readExpression(block, block.indexOf(`${key}:`) + key.length + 1).expr;

const Translation = { tr: s => s };
const methodBox = { model: inScope({ Translation }, "", `return (${expr(combo, "model")});`)() };
function state(method) {
  const ipSection = { loaded: true, saving: false, method };
  const scope = { ipSection, methodBox, Translation };
  return {
    ipSection,
    enabled: () => inScope(scope, "", `return (${expr(apply, "enabled")});`)(),
    select: v => inScope(scope, "", `return (${expr(combo, "onSelected")});`)()(v),
  };
}
for (const method of ["shared", "link-local", "disabled"]) {
  const s = state(method);
  check(`a connection that is "${method}": Apply is off`, s.enabled() === false, `Apply ${s.enabled() ? "on" : "off"}`);
}
{
  const s = state("shared");
  s.select("auto");
  check("until a method from the list is picked", s.enabled() === true, `Apply ${s.enabled() ? "on" : "off"} with ${s.ipSection.method}`);
}
for (const method of ["auto", "auto-dns", "manual"]) {
  const s = state(method);
  check(`a connection that is "${method}": Apply is on`, s.enabled() === true, `Apply ${s.enabled() ? "on" : "off"}`);
}
// what Apply would have written for "shared"
{
  const set = qmlFunction(read("services/Network.qml"), "setIpv4Config");
  let cmd = null;
  inScope({ root: { run: c => (cmd = cmd ?? c) } }, set.params.replace(/:\s*\w+/g, ""), set.body)("Hotspot", { method: "shared", address: "", gateway: "", dns: "" }, () => {});
  check("setIpv4Config writes a method it does not know as automatic, which Apply did to them", cmd?.includes("auto"), JSON.stringify(cmd));
}
done();
