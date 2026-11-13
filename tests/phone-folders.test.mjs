// Folders sent to the phone (scripts/phone/phone-link.py files, services/PhoneLink.qml): only files can go, and a folder
// was left out without a word, alone or in a mix. phone-link.py runs under python3 on a scratch folder; PhoneLink's own
// add(), pump() and the send's onExited run under node with a pretend notch, for a mix, folders alone, a mix whose last
// file fails, and files alone.
import { execFileSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { adapterDefaults, inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== folders sent to the phone (phone-link.py files, PhoneLink.qml)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-phone-folders-"));
let listed = [];
try {
  writeFileSync(join(tmp, "a.jpg"), "x");
  mkdirSync(join(tmp, "Photos"));
  listed = execFileSync("python3", ["-I", join(tree, "scripts/phone/phone-link.py"), "files", join(tmp, "a.jpg"), join(tmp, "Photos"), join(tmp, "gone.txt")],
    { encoding: "utf8" }).split("\n").filter(l => l);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
check("files keeps a file, marks a folder with a / after it, and leaves out a missing path",
  listed.length === 2 && listed[0] === join(tmp, "a.jpg") && listed[1] === join(tmp, "Photos") + "/", JSON.stringify(listed));

const src = read("services/PhoneLink.qml");
const options = adapterDefaults(read("modules/common/Config.qml"));
const exitedAt = src.indexOf("onExited:", src.indexOf("id: sendProc"));
const exited = readExpression(src, exitedAt + "onExited:".length).expr;
function phone(results) {
  const said = [];
  const IslandController = {
    request: (name, data) => said.push({ name, ...data }),
    startActivity() {},
    endActivity: (status, text, extra) => said.push({ name: status === "ok" ? "activityDone" : "activityFail", text, ...(extra ?? {}) }),
  };
  const sendProc = { running: false, command: [] };
  const root = { usable: true, paired: true, phoneName: "Pixel", phoneId: "dev1", script: "phone-link.py", sends: [], counter: 0, current: 0,
    sentTo: "", batches: [], batchCounter: 0, batchFolders: {}, pageRequested() {} };
  const scope = { root, IslandController, sendProc, Config: { options } };
  for (const name of ["add", "pump", "patch"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const onExited = inScope(scope, "", `return (${exited});`)();
  // the daemon takes each file handed over (0) or not (1), one after another
  const run = checked => {
    root.add(checked);
    for (let i = 0; i < 20 && root.sends.some(s => s.state === "sending"); i++) {
      sendProc.running = false;
      onExited(results.shift() ?? 0);
    }
  };
  return { run, said, root };
}
const lines = said => said.map(s => `${s.name}: ${s.text}`);
{
  const p = phone([0, 0, 0]);
  p.run(["/h/1.jpg", "/h/2.jpg", "/h/3.jpg", "/h/Photos/"]);
  const last = p.said.at(-1);
  check("three files and a folder: the last line says \"Sent 3 files · folders can't be sent\"",
    last?.name === "activityDone" && last.text === "Sent 3 files · folders can't be sent", lines(p.said).join(" | "));
  check("the folder never becomes a row", p.root.sends.length === 3 && !p.root.sends.some(s => s.path.endsWith("/")), `${p.root.sends.length} rows`);
}
{
  const p = phone([]);
  p.run(["/h/Photos/", "/h/Music/"]);
  check("folders alone: the notch says \"Folders can't be sent\"", p.said.length === 1 && p.said[0].text === "Folders can't be sent", lines(p.said).join(" | ") || "nothing");
}
{
  const p = phone([0, 1]);
  p.run(["/h/1.jpg", "/h/2.jpg", "/h/Photos/"]);
  const fail = p.said.findIndex(s => s.name === "activityFail"), note = p.said.findIndex(s => /folders can't be sent/.test(s.text ?? ""));
  check("when the last file fails, the failure is said, then \"Sent 1 file · folders can't be sent\"",
    fail >= 0 && note > fail && p.said[note].text === "Sent 1 file · folders can't be sent", lines(p.said).join(" | "));
}
{
  const p = phone([0, 0]);
  p.run(["/h/1.jpg", "/h/2.jpg"]);
  check("files alone end as before, \"Sent to Pixel · 2.jpg\", with no word of folders",
    p.said.at(-1)?.text === "Sent to Pixel · 2.jpg" && !p.said.some(s => /olders/.test(s.text ?? "")), lines(p.said).join(" | "));
}
done();
