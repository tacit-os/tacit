// The notch's pill when agent-host goes away mid-answer (services/Claude.qml): an update restarts the host, and the old
// Claude Code goes on finishing the turn. The pill ended red, "Claude stopped.", though the work may still finish.
// Claude.qml's own onConnectedChanged runs under node with IslandController's own endActivity(), request() and holds, and
// the header's parts() splits the line as the notch draws it.
import { adapterDefaults, inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the pill when agent-host goes away mid-answer (Claude.qml)");
const src = read("services/Claude.qml");
const at = src.indexOf("onConnectedChanged: {"), open = src.indexOf("{", at);
const connectedChanged = src.slice(open + 1, matchBrace(src, open));
const isrc = read("services/IslandController.qml");
const options = adapterDefaults(read("modules/common/Config.qml"));
const hsrc = read("modules/ii/island/IslandHeader.qml");

const ic = { enabled: true, suppressed: false, warmedUp: true, transientState: "", transientPriority: -1, payload: {}, queue: [],
  activityRunning: true, activityName: "Praxis", activityMuted: false, activityDemoted: false, activityTouchedAt: 0 };
Object.defineProperty(ic, "transientShowing", { get: () => ic.transientState !== "" });
const timer = { interval: 0, running: false, restart() {}, start() {}, stop() {} };
const iscope = { root: ic, Config: { options }, holdTimer: timer, stallTimer: timer, demoteTimer: timer, Translation: { tr: s => s } };
for (const name of ["request", "enqueue", "activate", "dismiss", "holdFor", "wingFor", "signinHeldBack", "cancelState", "endActivity", "activityFailLine"]) {
  const f = qmlFunction(isrc, name);
  if (f) ic[name] = inScope(iscope, f.params, f.body);
}
ic.activate("activity", { name: "Praxis", text: "Running make check" }, 35);

const root = { activityId: "s1", queue: [], attach() {} };
inScope({ root, connected: false, IslandController: ic, Config: { options }, titlesLater: timer, Qt: { callLater() {} } }, "", connectedChanged)();

const p = ic.payload;
const words = `${p.text ?? ""}${p.value ? ` ${p.value}` : ""}`;
check("the pill says \"Lost touch with Praxis; the work may still finish\"", words === "Lost touch with Praxis; the work may still finish", `"${words}"`);
check("in the plain tone, not the failure's", ic.transientState !== "activityFail" && (p.tone ?? "neutral") !== "error" && p.icon !== "error",
  `${ic.transientState}, tone ${p.tone ?? "neutral"}, glyph ${p.icon}`);
check("long enough to read it", ic.holdFor(ic.transientState) >= 4000, `${ic.holdFor(ic.transientState)} ms`);
check("a click opens that conversation", p.claudeId === "s1", `claudeId ${p.claudeId}`);
check("the activity is over", !ic.activityRunning && root.activityId === "");

// the header's split: the point left, the rest right, each in its wing
const parts = qmlFunction(hsrc, "parts"), lower = qmlFunction(hsrc, "lower");
const hroot = {};
hroot.lower = inScope({ root: hroot }, lower.params, lower.body);
const split = inScope({ root: hroot }, parts.params, parts.body)(ic.transientState, p);
check("the notch draws it as \"Lost touch with Praxis;\" and \"the work may still finish\"",
  split.point === "Lost touch with Praxis;" && split.rest === "the work may still finish", JSON.stringify(split));
check("on wings wider than a plain line's", ic.wingFor(ic.transientState) > 140, `${ic.wingFor(ic.transientState)}`);
done();
