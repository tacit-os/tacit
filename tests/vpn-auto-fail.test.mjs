// The VPN set to come on by itself (Persistent's autoVpn) that does not come up, or drops, on a network that is not
// trusted: the notch says "VPN didn't connect · <reason>" (services/Vpn.qml, services/IslandController.qml). Vpn's own
// applyRule(), connect(), disconnect(), toggle(), failReason(), its wait timer, the action Process's onExited, the
// list's onStreamFinished and the drop check run under node with a pretend nmcli and clock, and the notch's onFailed
// and holdFor() hear them. Settings runs a Vpn of its own: a second one, sharing the shell's clock and Persistent.
import { adapterDefaults, inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the VPN set to come on by itself says when it is not on (Vpn.qml, IslandController.qml)");
const vpnSrc = read("services/Vpn.qml");
const ic = read("services/IslandController.qml");
const Translation = { tr: s => Object.assign(new String(s), { arg: a => s.replace("%1", a) }) };
const untyped = f => f && { params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body };
// the { ... } after "<key>" in the block that starts at "id: <id>", or null
function blockAfter(src, id, key) {
  const from = src.indexOf(`id: ${id}`);
  if (from < 0) return null;
  const open = src.indexOf("{", src.indexOf(key, from));
  return src.slice(open + 1, matchBrace(src, open));
}

// what the notch says
const hold = adapterDefaults(read("modules/common/Config.qml")).island.hold;
const said = [];
const notch = { request: (name, data, priority) => said.push({ name, ...data, text: String(data.text), priority }) };
const holdFor = untyped(qmlFunction(ic, "holdFor"));
notch.holdFor = inScope({ root: notch, Config: { options: { island: { hold } } } }, holdFor.params, holdFor.body);
const failedAt = ic.indexOf("function onFailed", ic.indexOf("target: Vpn"));
const onFailed = failedAt < 0 ? null : (() => { const f = qmlFunction(ic.slice(failedAt), "onFailed"); return inScope({ root: notch, Translation }, f.params, f.body); })();

function desktop({ ssid = "Cafe", trusted = [], shell = null } = {}) {
  const time = shell ? shell.time : { clock: 1000 };
  const Date = { now: () => time.clock };
  const Persistent = shell ? shell.Persistent : { states: { network: { vpnDownAt: 0 } } };
  const net = { active: ssid ? { ssid } : null, ethernet: false, isTrusted: s => trusted.includes(s), splitTerse: l => l.split(":") };
  const vpn = { lastError: "", pendingConnect: "", ruleSkipped: false, connections: [{ name: "Proton", kind: "wireguard", active: false }],
    refresh() {}, busy: false, connecting: "", downing: false, droppedAt: 0, ruleTriedAt: 0 };
  Object.defineProperty(vpn, "autoVpn", { get: () => "Proton" });
  Object.defineProperty(vpn, "active", { get: () => vpn.connections.find(c => c.active) ?? null });
  vpn.failed = reason => onFailed?.(String(reason));
  const proc = { exec(cmd) { proc.cmd = cmd; } };
  const timer = { restart() {}, stop() {} };
  const drop = { running: false, restart() { drop.running = true; }, stop() { drop.running = false; } };
  const scope = { root: vpn, Network: net, Translation, Date, Persistent, waitTimer: timer, ruleLater: timer, refreshLater: timer, dropCheck: drop,
    actionProc: proc };
  for (const name of ["applyRule", "connect", "disconnect", "start", "toggle", "failReason"]) {
    const f = untyped(qmlFunction(vpnSrc, name));
    if (f) vpn[name] = inScope(scope, f.params, f.body);
  }
  const run = (id, key, params = "") => { const b = blockAfter(vpnSrc, id, key); return b === null ? () => {} : inScope(scope, params, b); };
  const waited = run("waitTimer", "onTriggered:");
  const exited = run("actionProc", "onExited:", "code");
  const stderr = inScope(scope, "text", "root.lastError = text.trim();");
  const listed = run("listProc", "onStreamFinished:", "text");
  const dropCheck = run("dropCheck", "onTriggered:");
  return {
    vpn, net, time, Persistent,
    later: ms => { time.clock += ms; },
    // nmcli connection up/down ends: its stderr, then its exit
    nmcli: (code, err = "") => { stderr(err); exited(code); },
    timeout: () => waited(),
    // nmcli monitor saw a change: the list read again
    list: (...up) => listed(["Proton", "Work"].map(n => `${n}:wireguard:${up.includes(n) ? "yes" : "no"}`).join("\n") + "\n"),
    // dropCheck's 4 s, if it was started
    settle: () => { time.clock += 4000; if (drop.running) { drop.running = false; dropCheck(); } },
  };
}
const lines = from => said.slice(from).filter(s => s.name === "vpn" || /VPN didn't connect/.test(s.text));
const refused = "Error: Connection activation failed: The VPN service stopped unexpectedly.\nHint: use 'journalctl -xe NM_CONNECTION=1a2b' to get more details.";

{
  const n = said.length, d = desktop();
  d.vpn.applyRule();                       // a café's Wi-Fi, not trusted: the rule brings Proton up
  d.nmcli(4, refused);
  const l = lines(n);
  check("the rule's try refused: the notch says it did not connect, and why, in nmcli's words",
    l.length === 1 && l[0].text === "VPN didn't connect · The VPN service stopped unexpectedly", JSON.stringify(l.map(x => x.text)));
  check("in the error tone, held long enough to read", l[0]?.tone === "error" && notch.holdFor("vpn") >= 4000 && notch.holdFor("vpn") > hold.network,
    `${notch.holdFor("vpn")} ms`);
}
{
  const n = said.length, d = desktop();
  d.vpn.applyRule();
  d.timeout();                             // 30 s and no answer
  d.nmcli(4, "Error: Timeout expired (90 seconds)");   // its late exit
  const l = lines(n);
  check("no answer after 30 seconds says so once, not again at the late exit",
    l.length === 1 && l[0].text === "VPN didn't connect · no answer after 30 seconds", JSON.stringify(l.map(x => x.text)));
}
{
  const n = said.length, d = desktop();
  d.vpn.toggle("Work");                    // the pill, another VPN than the one set to come on by itself
  d.nmcli(4, refused);
  check("another VPN failing from the pill is the panel's to say, not the notch's", lines(n).length === 0, JSON.stringify(lines(n)));
}
{
  const n = said.length, d = desktop();
  d.vpn.applyRule();
  d.list("Proton"); d.nmcli(0);            // up
  d.later(600000);
  d.list();                                // gone, with nobody asking, still on the café's Wi-Fi
  d.settle();
  const l = lines(n);
  check("the VPN dropping on a network that is not trusted says so", l.length === 1 && l[0].text === "VPN didn't connect · it dropped",
    JSON.stringify(l.map(x => x.text)));
}
{
  const n = said.length, d = desktop({ ssid: "Home", trusted: ["Home"] });
  d.vpn.connections = [{ name: "Proton", active: true }];
  d.vpn.applyRule();                       // home: the rule takes it down
  d.nmcli(0); d.list(); d.settle();
  const e = desktop();
  e.vpn.connections = [{ name: "Proton", active: true }];
  e.vpn.toggle("Proton");                  // the pill turns it off at the café
  e.nmcli(0); e.list(); e.settle();
  const f = desktop();
  f.vpn.connections = [{ name: "Proton", active: true }];
  f.vpn.toggle("Work");                    // from the pill, Proton for another VPN: down first, then Work up
  f.nmcli(0);
  f.list(); f.nmcli(4, refused); f.settle();
  check("a down that was asked for (the rule at home, the pill, a switch to another VPN) says nothing", lines(n).length === 0,
    JSON.stringify(lines(n).map(x => x.text)));
}
{
  const n = said.length, d = desktop();
  d.vpn.connections = [{ name: "Proton", active: true }];
  d.later(600000);
  d.list();                                // leaving the café's Wi-Fi drops the tunnel
  d.net.active = { ssid: "Station" };      // another network that is not trusted
  d.later(2500);
  d.vpn.applyRule();                       // its rule brings Proton back up
  d.list("Proton"); d.nmcli(0);
  d.settle();
  const e = desktop();
  e.vpn.connections = [{ name: "Proton", active: true }];
  e.later(600000);
  e.net.active = null;                     // Wi-Fi off: no network, no tunnel
  e.list(); e.settle();
  check("a drop the rule brings back, or one with no network left, says nothing", lines(n).length === 0, JSON.stringify(lines(n).map(x => x.text)));
}
{
  const n = said.length, d = desktop();
  d.vpn.connections = [{ name: "Proton", active: true }];
  d.later(600000);
  d.list();                                // the café's Wi-Fi left for another, and the tunnel with it
  d.net.active = { ssid: "Station" };
  d.later(2500);
  d.vpn.applyRule();                       // the rule's try on the new network is refused
  d.nmcli(4, refused);
  d.settle();
  const l = lines(n);
  check("a drop whose retry by the rule is refused says it once, with the refusal's reason",
    l.length === 1 && /stopped unexpectedly/.test(l[0].text), JSON.stringify(l.map(x => x.text)));
}
{
  const n = said.length, d = desktop();
  d.vpn.connections = [{ name: "Proton", active: true }];
  const settings = desktop({ shell: d });   // Settings > Network, its own process, with Proton up too
  settings.vpn.connections = [{ name: "Proton", active: true }];
  d.later(600000);
  settings.vpn.toggle("Proton");           // its switch turns Proton off at the café
  settings.nmcli(0);
  d.later(700);
  d.list();                                // the shell sees it go, with no down of its own
  d.settle();
  check("the auto VPN turned off in Settings says nothing in the notch", lines(n).length === 0, JSON.stringify(lines(n).map(x => x.text)));
  d.vpn.connections = [{ name: "Proton", active: true }];
  d.later(600000);
  d.list();                                // ten minutes on, back up and then gone with nobody asking
  d.settle();
  const l = lines(n);
  check("and a drop long after it is still said", l.length === 1 && l[0].text === "VPN didn't connect · it dropped", JSON.stringify(l.map(x => x.text)));
}
done();
