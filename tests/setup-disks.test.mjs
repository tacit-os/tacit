// Setup's disk page on made-up disks: setupd.py's answers (under python, its disk reads faked) and setup.qml's own button
// and forward() for them. A disk under the 32 GB tacit-install refuses was offered as "Tacit will use the whole disk"
// with Install, and refused only after the person had been moved on to the account page.
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Setup's disks (scripts/setup/setupd.py, setup.qml)");
const cases = name => {
  const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "setupd_cases.py"),
    join(tree, "scripts/setup/setupd.py"), name], { encoding: "utf8" });
  process.stdout.write(r.stdout + r.stderr);
  return r.status === 0;
};
check("setupd tells a disk under 32 GB from one Tacit can go on", cases("small"));

// the disk page for the case "small": its button, and what pressing it does
const src = read("setup.qml");
const primary = qmlProperty(src, "primaryText"), forward = qmlFunction(src, "forward");
function press(disks, practice) {
  const sent = [], pages = [];
  let ended = false;
  const backend = { disksRead: true, disk: { name: "/dev/mmcblk0", case: "small", size: 29e9 }, plan: { room: false }, disks, practice,
    send: m => sent.push(m) };
  const setup = { place: "next", go: p => pages.push(p), startInstall: () => sent.push({ op: "install" }) };
  const scope = { shownPage: "where", backend, setup, root: { other: "it", endPractice: () => { ended = true; } } };
  const text = inScope(scope, "", `return (${primary});`)();
  inScope(scope, forward.params, forward.body)();
  return { text, sent, pages, ended };
}
const alone = press([], false);
check("a lone disk under 32 GB: the button says Turn off and turns the computer off",
  alone.text === "Turn off" && JSON.stringify(alone.sent) === '[{"op":"off"}]' && alone.pages.length === 0,
  `"${alone.text}", sent ${JSON.stringify(alone.sent)}, went to ${JSON.stringify(alone.pages)}`);
const practice = press([], true);
check("in a practice run it ends the practice", practice.ended && practice.sent.length === 0, `sent ${JSON.stringify(practice.sent)}`);
const beside = press([{ name: "/dev/nvme0n1" }, { name: "/dev/mmcblk0" }], false);
check("one of several disks: the button says Choose a disk and goes to the list",
  beside.text === "Choose a disk" && JSON.stringify(beside.pages) === '["disks"]' && beside.sent.length === 0,
  `"${beside.text}", sent ${JSON.stringify(beside.sent)}, went to ${JSON.stringify(beside.pages)}`);
check("the page offers no erase for it", /"nouefi", "empty", "small"\]\.includes\(parent\.parent\.c\)/.test(src));

// the disks as last read, for a disk chosen from the list and for Install; Try again waits for them to be read again
check("setupd reads the disks for the list only, not again for a choice or Install", cases("reuse"));
{
  const sent = [];
  const backend = { disksRead: true, send: m => sent.push(m) };
  const setup = { installState: "failed", trail: [], page: "failed" };
  inScope({ shownPage: "failed", backend, setup, root: {} }, forward.params, forward.body)();
  check("Try again shows the disk page as looking until the disks are read again",
    setup.page === "where" && backend.disksRead === false && JSON.stringify(sent) === '[{"op":"disks"}]',
    `page ${setup.page}, disksRead ${backend.disksRead}, sent ${JSON.stringify(sent)}`);
}
// Try again after "Choose partitions myself" failed: the disk page, read again with room next to Windows, has its first
// choice on and its button says so; it had none on, and Continue went to "Erase this disk?"
{
  const backend = { disksRead: true, send: () => {} };
  const setup = { installState: "failed", trail: [], page: "failed", place: "manual", installUntouched: false };
  inScope({ shownPage: "failed", backend, setup, proc: { running: true }, root: {} }, forward.params, forward.body)();
  Object.assign(backend, { disksRead: true, disk: { name: "/dev/nvme0n1", case: "windows", size: 512e9 },
    plan: { room: true, windowsKeeps: 300e9, tacitGets: 210e9 }, disks: [] });
  const went = [];
  Object.assign(setup, { go: p => went.push(p), startInstall: () => went.push("install") });
  const scope = { shownPage: "where", backend, setup, root: { other: "Windows" } };
  const text = inScope(scope, "", `return (${primary});`)();
  inScope(scope, forward.params, forward.body)();
  check("Try again after a failed install on partitions chosen: Next to Windows is on, and the button installs next to it",
    setup.place === "next" && text === "Install next to Windows" && JSON.stringify(went) === '["install"]',
    `place ${setup.place}, "${text}", went to ${JSON.stringify(went)}`);
}
done();
