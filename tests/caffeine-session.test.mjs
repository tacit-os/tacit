// Caffeine (services/Idle.qml): it was saved and came back after every restart, so one turned on for a Friday download
// held off the lock, sleep and the night's update for good, and its notch glyph sat below the VPN's, an agent's and
// others, which hid it. Now it lasts the session and always shows. Persistent.qml's own onReadyChanged and the
// isNewHyprlandInstance binding, Idle's restore() and toggleInhibit(), IslandController's ambientGlyph and coffeeAside,
// and the header's coffee mark run under node over three starts: a sign-in, a shell restart, the next sign-in.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Caffeine lasts the session and always shows (Idle.qml, IslandController.qml)");
const psrc = read("modules/common/Persistent.qml");
const isrc = read("services/Idle.qml");
const csrc = read("services/IslandController.qml");
const hsrc = read("modules/ii/island/IslandHeader.qml");
const block = (src, at) => { const open = src.indexOf("{", at); return src.slice(open + 1, matchBrace(src, open)); };
const persistentReady = block(psrc, psrc.indexOf("onReadyChanged: {"));
const isNew = qmlProperty(psrc, "isNewHyprlandInstance");
const idleReady = block(isrc, isrc.indexOf("function onReadyChanged()"));

// states.json as it is between starts
const saved = { hyprlandInstanceSignature: "", idle: { inhibit: false }, record: { enable: false } };
// one start of the shell inside the Hyprland whose signature is given: what Caffeine is once the state is read
function start(signature) {
  const P = { ready: true, states: saved, previousHyprlandInstanceSignature: "" };
  const pscope = { root: P, Quickshell: { env: k => (k === "HYPRLAND_INSTANCE_SIGNATURE" ? signature : "") , execDetached() {} }, Directories: {} };
  inScope(pscope, "", persistentReady)();
  Object.defineProperty(P, "isNewHyprlandInstance", { get: () => inScope({ root: P, ...P }, "", `return (${isNew});`)() });
  const idle = { inhibit: false };
  const iscope = { root: idle, Persistent: P };
  for (const name of ["restore", "toggleInhibit", "inhibitForSession"]) {
    const f = qmlFunction(isrc, name);
    if (f) idle[name] = inScope(iscope, f.params, f.body);
  }
  inScope(iscope, "", idleReady)();
  return idle;
}

{
  let idle = start("A");
  idle.toggleInhibit();                       // Caffeine on, for a long download
  check("turned on, it is on", idle.inhibit === true);
  idle = start("A");                          // the shell restarts (a reload, a crash) in the same session
  check("a restart of the shell in the same session keeps it on", idle.inhibit === true, `inhibit ${idle.inhibit}`);
  idle = start("B");                          // signed out and in, or the next boot
  check("the next sign-in starts with it off", idle.inhibit === false, `inhibit ${idle.inhibit}`);
  idle = start("B");
  check("and a shell restart after that does not bring it back", idle.inhibit === false, `inhibit ${idle.inhibit}`);
}

// the notch's marks: Caffeine on while a VPN is up, which ranks above it
const glyphBody = qmlProperty(csrc, "ambientGlyph").replace(/^\{|\}$/g, "");
const aside = qmlProperty(csrc, "coffeeAside");
function marks({ vpn, coffee }) {
  const root = { chargerFault: false, micLive: false, prReviews: [], activityAmbient: false, diskPct: 40, memoryFull: false, workUnsaved: false };
  const scope = { root, Audio: { source: null, sink: { name: "alsa_output.pci" } }, Camera: { live: false },
    AgentSessions: { waiting: false, justDone: false, sessions: [] }, Claude: { waiting: false }, Notifications: { silent: false, unread: 0 },
    Battery: { available: true, isCharging: false }, Vpn: { connected: vpn }, Idle: { inhibit: coffee }, DropShelf: { items: [] },
    Updates: { restartDue: false }, Hyprsunset: { temperatureActive: false } };
  root.ambientGlyph = inScope(scope, "", glyphBody)();
  const shown = [root.ambientGlyph];
  if (aside) {
    root.coffeeAside = inScope(scope, "", `return (${aside});`)();
    const at = hsrc.indexOf("id: coffeeMark");
    const mark = at < 0 ? "" : hsrc.slice(hsrc.lastIndexOf("{", at), matchBrace(hsrc, hsrc.lastIndexOf("{", at)) + 1);
    const vis = mark.match(/\n\s*visible:\s*/);
    const glyph = mark.match(/\n\s*text:\s*"([^"]+)"/);
    if (vis && glyph && inScope({ IslandController: root, statusSlot: { visible: true } }, "", `return (${readExpression(mark, vis.index + vis[0].length).expr});`)())
      shown.push(glyph[1]);
  }
  return shown.filter(g => g);
}
{
  const m = marks({ vpn: true, coffee: true });
  check("with a VPN up, Caffeine on still shows its coffee, beside the VPN's key", m.includes("coffee") && m.includes("vpn_key"), m.join(", ") || "nothing");
  const alone = marks({ vpn: false, coffee: true });
  check("alone, the coffee is the one mark, not two", alone.length === 1 && alone[0] === "coffee", alone.join(", "));
  const off = marks({ vpn: true, coffee: false });
  check("with Caffeine off there is no coffee", !off.includes("coffee"), off.join(", "));
}
done();
