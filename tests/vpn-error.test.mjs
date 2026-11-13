// A VPN that does not come up while the panel's VPN section is folded (the pill, the "On when not trusted" rule): what
// the section says once it is opened (modules/ii/sidebarRight/vpn/VpnSection.qml). Vpn.qml's own applyRule(), connect()
// and start(), its wait timer and its action Process's handlers run under node, and the section's handlers hear them.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a VPN that did not come up, in the panel (VpnSection.qml, Vpn.qml)");
const vpnSrc = read("services/Vpn.qml");
const sectionSrc = read("modules/ii/sidebarRight/vpn/VpnSection.qml");
const Translation = { tr: s => s };
const untyped = f => f && { params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body };

// the { ... } after "<key>" in the block that starts at "id: <id>"
function blockAfter(src, id, key) {
  const at = src.indexOf(key, src.indexOf(`id: ${id}`));
  const open = src.indexOf("{", at);
  return src.slice(open + 1, matchBrace(src, open));
}
const shownAt = sectionSrc.indexOf("onShownChanged:");
const onShown = sectionSrc.slice(shownAt + "onShownChanged:".length, matchBrace(sectionSrc, sectionSrc.indexOf("{", shownAt)) + 1);

function desktop() {
  const section = { shown: false, errorText: "" };
  const vpn = { lastError: "", pendingConnect: "", ruleSkipped: false, connections: [{ name: "Proton", active: false }], refresh() {},
    failed() {} };
  let busy = false;
  const hear = name => handlers[name]?.();
  Object.defineProperty(vpn, "busy", { get: () => busy, set: v => { if (v === busy) return; busy = v; hear("onBusyChanged"); } });
  Object.defineProperty(vpn, "autoVpn", { get: () => "Proton" });
  Object.defineProperty(vpn, "active", { get: () => vpn.connections.find(c => c.active) ?? null });
  Object.defineProperty(vpn, "connected", { get: () => vpn.active !== null });
  const proc = { exec(cmd) { proc.cmd = cmd; } };
  const timer = { restart() {}, stop() {} };
  const vscope = { root: vpn, Network: { active: { ssid: "Cafe" }, ethernet: false, isTrusted: () => false }, Translation,
    waitTimer: timer, ruleLater: timer, actionProc: proc };
  for (const name of ["applyRule", "connect", "disconnect", "start", "toggle", "failReason"]) {
    const f = untyped(qmlFunction(vpnSrc, name));
    if (f) vpn[name] = inScope(vscope, f.params, f.body);
  }
  const waited = inScope(vscope, "", blockAfter(vpnSrc, "waitTimer", "onTriggered:"));
  const exited = inScope(vscope, "code", blockAfter(vpnSrc, "actionProc", "onExited:"));   // nmcli's exit code
  const stderr = inScope(vscope, "text", "root.lastError = text.trim();");
  // nmcli monitor: the list read again
  const listed = active => { const was = vpn.connected; vpn.connections = [{ name: "Proton", active }]; if (vpn.connected !== was) hear("onConnectedChanged"); };

  const sscope = { root: section, Vpn: vpn, Translation, refreshLater: timer };
  const clear = untyped(qmlFunction(sectionSrc, "clearError"));
  section.clearError = inScope(sscope, clear.params, clear.body);
  const handlers = {};
  for (const name of ["onBusyChanged", "onConnectedChanged", "onImported"]) {
    const f = qmlFunction(sectionSrc, name);
    if (f) handlers[name] = inScope(sscope, f.params, f.body);
  }
  const open = () => { section.shown = true; inScope(sscope, "", onShown)(); };
  return { vpn, section, waited, exited, stderr, listed, open, imported: () => hear("onImported") };
}

const refused = "Error: Connection activation failed: The VPN service stopped unexpectedly.";
{
  const d = desktop();
  d.vpn.applyRule();                       // a café's Wi-Fi, not trusted: the rule brings Proton up, the section folded
  d.stderr(refused + "\n");
  d.exited(1);
  d.open();
  check("a VPN the rule could not bring up says why once the section is opened", d.section.errorText === refused,
    d.section.errorText ? `it says "${d.section.errorText}"` : "it says nothing");
}
{
  const d = desktop();
  d.vpn.toggle("Proton");                  // the pill
  d.waited();                              // 30 s and no answer
  d.open();
  check("a VPN the pill asked for with no answer says so once opened", /No answer after 30 seconds/.test(d.section.errorText),
    d.section.errorText ? `it says "${d.section.errorText}"` : "it says nothing");
  d.listed(true);                          // it came up after all
  d.stderr("");
  d.exited(0);
  check("and the line goes once the VPN is up", d.section.errorText === "", `it still says "${d.section.errorText}"`);
}
{
  const d = desktop();
  d.vpn.applyRule();
  d.stderr(refused);
  d.exited(1);
  d.vpn.applyRule();                       // the next network: this time it comes up
  d.stderr("");
  d.listed(true);
  d.exited(0);
  d.open();
  check("a VPN that comes up on the next try shows no old error", d.section.errorText === "", `it says "${d.section.errorText}"`);
}
{
  const d = desktop();
  d.section.errorText = "the file's name must be 15 characters or fewer, with no spaces";   // an import refused
  d.imported();                            // the next file is taken
  d.open();
  check("a refused import's line goes once another file is taken", d.section.errorText === "", `it says "${d.section.errorText}"`);
}

done();
