// Setup's helper (scripts/setup/setupd.py) gone before Install: setup.qml's own startInstall(), startManual(),
// helperStopped() and Try again's forward() under node, with a pretend helper process. A request written to a stopped
// process is dropped (Quickshell's Process.write), so Install led to "Installing" for good, and Back, Esc and closing
// the window are refused while an install runs.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Setup with its helper stopped (setup.qml)");
const src = read("setup.qml");
const fns = ["startInstall", "startManual", "helperStopped"].map(n => [n, qmlFunction(src, n)]);
const forward = qmlFunction(src, "forward");

function setupWith(running) {
  const sent = [];
  const proc = { running };
  const backend = { ready: true, disksRead: true, send: m => { if (proc.running) sent.push(m); } };
  const setup = { page: "erase", trail: ["welcome", "wifi", "where"], place: "instead", partRoot: "/dev/sda2", partEfi: "/dev/sda1",
    partBoot: "", installState: "", installUntouched: true, installReason: "", backend, proc,
    get installing() { return this.installState === "running" || this.installState === "done"; },
    go(p) { this.trail = this.trail.concat([this.page]); this.page = p; } };
  for (const [n, f] of fns) if (f) setup[n] = inScope(setup, f.params, f.body);
  return { setup, backend, proc, sent };
}

for (const how of ["startInstall", "startManual"]) {
  const { setup, sent } = setupWith(false);
  setup[how]();
  check(`${how}() with the helper stopped: the failed page, not "Installing"`,
    setup.installState === "failed" && setup.page === "failed", `state "${setup.installState}", page ${setup.page}`);
  check("and it says the helper stopped and nothing on the disk changed",
    setup.installReason === "Setup's helper stopped" && setup.installUntouched === true && sent.length === 0,
    `reason "${setup.installReason}", untouched ${setup.installUntouched}`);
}
{
  const { setup, sent } = setupWith(true);
  setup.startInstall();
  check("with the helper there, Install still starts the install", setup.installState === "running" && setup.page === "you"
    && JSON.stringify(sent) === '[{"op":"install","place":"instead"}]', `state "${setup.installState}", sent ${JSON.stringify(sent)}`);
}
function tryAgain(untouched) {
  const { setup, backend, proc, sent } = setupWith(false);
  Object.assign(setup, { page: "failed", installState: "failed", installUntouched: untouched });
  inScope({ shownPage: "failed", setup, backend, proc, root: {} }, forward.params, forward.body)();
  return { setup, backend, proc, sent };
}
{
  const { setup, backend, proc, sent } = tryAgain(true);
  check("Try again starts the helper again, which reads the disks for the page",
    proc.running === true && backend.ready === false && setup.page === "where" && JSON.stringify(sent) === '[{"op":"disks"}]',
    `helper running ${proc.running}, ready ${backend.ready}, page ${setup.page}, sent ${JSON.stringify(sent)}`);
}
{
  const { proc } = tryAgain(false);
  check("but not a helper that stopped mid-install, whose installer may still run", proc.running === false, `helper running ${proc.running}`);
}
done();
