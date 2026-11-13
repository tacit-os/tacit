// Settings > Network's IPv4 Apply on a connection whose method its list does not have, and on fields that would leave the
// link without names or a route (modules/ii/settings/pages/NetworkConfig.qml): the Address list's model and onSelected and
// the Apply button's enabled binding run under node, with what services/Network.qml's setIpv4Config() would write.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== IPv4 Apply on a hotspot's shared connection and on fields it cannot use (NetworkConfig.qml)");
const src = read("modules/ii/settings/pages/NetworkConfig.qml");
const combo = objectWith(src, 'buttonIcon: "settings_ethernet"');
const apply = objectWith(src, 'Translation.tr("Applying")');
const expr = (block, key) => readExpression(block, block.indexOf(`${key}:`) + key.length + 1).expr;

const Translation = { tr: s => s };
const methodBox = { model: inScope({ Translation }, "", `return (${expr(combo, "model")});`)() };
function state(method, { address = "192.168.0.50/24", dns = "1.1.1.1, 9.9.9.9" } = {}) {
  const ipSection = { loaded: true, saving: false, method };
  const scope = { ipSection, methodBox, Translation, addressField: { value: address }, gatewayField: { value: "192.168.0.1" }, dnsField: { value: dns } };
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
// the fields: custom DNS with none typed, and a manual address without its prefix
for (const [method, fields, on, what] of [
  ["auto-dns", { dns: "" }, false, "custom DNS with the DNS field empty"],
  ["auto-dns", { dns: "   " }, false, "custom DNS with only spaces in the DNS field"],
  ["manual", { address: "192.168.0.50" }, false, "a manual address without /prefix"],
  ["manual", { address: "192.168.0.50/24 " }, true, "a manual address with /24"],
  ["manual", { address: "10.0.0.2/8", dns: "" }, true, "a manual address with /8 and no DNS"],
  ["auto", { dns: "", address: "" }, true, "automatic with every field empty"],
]) {
  const s = state(method, fields);
  check(`${what}: Apply is ${on ? "on" : "off"}`, s.enabled() === on, `Apply ${s.enabled() ? "on" : "off"}`);
}
// what Apply would have written for "shared", and for custom DNS with none typed
{
  const set = qmlFunction(read("services/Network.qml"), "setIpv4Config");
  let cmd = null;
  inScope({ root: { run: c => (cmd = cmd ?? c) } }, set.params.replace(/:\s*\w+/g, ""), set.body)("Hotspot", { method: "shared", address: "", gateway: "", dns: "" }, () => {});
  check("setIpv4Config writes a method it does not know as automatic, which Apply did to them", cmd?.includes("auto"), JSON.stringify(cmd));
  cmd = null;
  inScope({ root: { run: c => (cmd = cmd ?? c) } }, set.params.replace(/:\s*\w+/g, ""), set.body)("Home", { method: "auto-dns", address: "", gateway: "", dns: "" }, () => {});
  const at = cmd?.indexOf("ipv4.dns") ?? -1;
  check("and custom DNS with none typed as no DNS, ignoring the network's own", cmd?.[at + 1] === "" && cmd?.[at + 3] === "yes", JSON.stringify(cmd));
}
done();
