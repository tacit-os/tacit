// VPN files added from a drop or a pick (services/Vpn.qml): its own importFile() and the import Process's onExited run
// under node, with a stand-in for Quickshell's Process that does what 0.3.2's does: exec() on a running one ends it,
// and the newest command starts once the ended one has exited. A failed import goes on to what the notch does with it
// (IslandController.qml's onImportFailed).
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== adding VPN files (Vpn.qml)");
const src = read("services/Vpn.qml");
const untyped = f => f && { params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body };
const Translation = { tr: s => Object.assign(new String(s), { arg: v => s.replace("%1", v) }) };

// the notch's side: what it parks and what it says
const notch = { parked: [], said: [] };
{
  const f = qmlFunction(read("services/IslandController.qml"), "onImportFailed");
  notch.onImportFailed = inScope({ Translation, DropShelf: { addItems: urls => notch.parked.push(...urls) },
    root: { request: (name, data) => notch.said.push(String(data.text)) } }, f.params, f.body);
}

function vpn() {
  const proc = { running: false, path: "", out: "", current: null, next: null, runs: [] };
  proc.exec = argv => {
    proc.argv = argv;
    const run = { file: argv[argv.length - 1], killed: false };
    if (proc.current) { proc.current.killed = true; proc.next = run; return; }
    proc.current = run;
    proc.runs.push(run);
    proc.running = true;
  };
  const root = { importQueue: [], lastError: "", added: [], failed: [], refresh() {},
    imported(name) { root.added.push(name); }, importFailed(path, ...rest) { root.failed.push(path); notch.onImportFailed(path, ...rest); } };
  const scope = { root, importProc: proc, Translation };
  for (const name of ["importFile", "importNext", "importReason"]) {
    const f = untyped(qmlFunction(src, name));
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  const at = src.indexOf("id: importProc"), m = /\bonExited:\s*/g;
  m.lastIndex = at;
  const exited = inScope(scope, "", `return (${readExpression(src, m.exec(src).index + "onExited: ".length).expr});`)();
  // the running command ends: nmcli added the file unless the run was ended first, or the run says otherwise (its exit
  // code and what it wrote to stderr, which Quickshell hands over before the exit)
  proc.finish = (code = 0, stderr = "") => {
    const run = proc.current;
    proc.current = null;
    proc.running = false;
    proc.out = run.killed || code ? "" : run.file.replace(/^.*\//, "").replace(/\.conf$/, "");
    if (stderr) root.lastError = stderr;
    exited(run.killed ? 15 : code);
    if (proc.next && !proc.current) { proc.current = proc.next; proc.next = null; proc.runs.push(proc.current); proc.running = true; }
  };
  return { root, proc };
}

{
  const { root, proc } = vpn();
  const files = ["se-got.conf", "se-sto.conf", "no-osl.conf"].map(f => `file:///home/a/Downloads/${f}`);
  for (const u of files) root.importFile(u);     // IslandContent's drop handler
  while (proc.current) proc.finish();
  check("three files dropped together are three VPNs added", root.added.join() === "se-got,se-sto,no-osl",
    `added ${JSON.stringify(root.added)}, failed for ${JSON.stringify(root.failed)}`);
  check("and no import is cut off by the next", proc.runs.every(r => !r.killed), JSON.stringify(proc.runs));
}

// a provider's WireGuard file whose name is too long for an interface: nmcli refuses it (exit 1, in its own words)
{
  notch.parked.length = notch.said.length = 0;
  const { root, proc } = vpn();
  root.importFile("file:///home/a/Downloads/mullvad-se-got-wg-001.conf");
  proc.finish(1, "Error: failed to import '/home/a/Downloads/mullvad-se-got-wg-001.conf': The name of the WireGuard config must be a valid interface name followed by \".conf\".");
  const line = notch.said[0] ?? "";
  check("a WireGuard file nmcli refuses stays where it is, not parked as a file", notch.parked.length === 0, JSON.stringify(notch.parked));
  check("and the notch says why, in plain words", !/Not a VPN/.test(line) && /15 characters/.test(line), JSON.stringify(line));
}
// the import's own script under bash, with an nmcli that refuses: 1 for a VPN file nmcli refused, 2 only for a file
// that is no VPN at all (what the notch parks)
{
  const { root, proc } = vpn();
  const dir = mkdtempSync(join(tmpdir(), "vpn-import-"));
  writeFileSync(join(dir, "nmcli"), "#!/bin/sh\necho \"Error: failed to import '$5': The name of the WireGuard config must be a valid interface name followed by \\\".conf\\\".\"\nexit 1\n");
  chmodSync(join(dir, "nmcli"), 0o755);
  const exitOf = (name, text) => {
    writeFileSync(join(dir, name), text);
    root.importFile(join(dir, name));
    const r = spawnSync(proc.argv[0], proc.argv.slice(1), { env: { PATH: `${dir}:/usr/bin:/bin` }, encoding: "utf8" });
    proc.finish(r.status, r.stderr);
    return r.status;
  };
  const wg = exitOf("mullvad-se-got-wg-001.conf", "[Interface]\nPrivateKey = x\n"), notes = exitOf("notes.conf", "just notes\n");
  check("the import script exits 1 for a WireGuard file nmcli refuses, 2 for a file that is no VPN", wg === 1 && notes === 2, `${wg}, ${notes}`);
  // OpenVPN is not offered: no networkmanager-openvpn, and nowhere to type the user name and password its files ask for
  notch.parked.length = notch.said.length = 0;
  const ovpn = exitOf("work.ovpn", "client\nremote vpn.example.com 1194\nauth-user-pass\n");
  const inConf = exitOf("work.conf", "client\nremote vpn.example.com 1194\n");
  rmSync(dir, { recursive: true });
  check("an OpenVPN file typed into Settings is refused, not handed to nmcli, and the notch says which kind can be added",
    ovpn === 1 && inConf === 1 && notch.parked.length === 0 && notch.said[0] === "Couldn't add the VPN · only WireGuard .conf files can be added",
    `${ovpn}, ${inConf}, ${JSON.stringify(notch.said)}`);
}
// what a drop on the notch takes as a VPN (Vpn.isVpnFile), and what the panel and Settings invite
{
  const f = untyped(qmlFunction(src, "isVpnFile"));
  const isVpn = inScope({}, f.params, f.body);
  check("a dropped .conf is a VPN to add, a dropped .ovpn a file like any other", isVpn("file:///home/a/se.conf") === true && isVpn("file:///home/a/work.ovpn") === false);
  const said = read("modules/ii/sidebarRight/vpn/VpnSection.qml") + read("modules/ii/settings/pages/NetworkConfig.qml");
  check("the panel and Settings ask for a WireGuard .conf and never an .ovpn", !/\.ovpn/.test(said.replace(/^\s*(\/\/|\*).*$/gm, "")) && /WireGuard \.conf file on the notch/.test(said));
}
// a file that is neither (the script's exit 2): parked on the shelf, as before
{
  notch.parked.length = notch.said.length = 0;
  const { root, proc } = vpn();
  root.importFile("file:///home/a/Downloads/notes.conf");
  proc.finish(2, "not a VPN file");
  check("a .conf that is not a VPN is parked on the shelf and said so",
    notch.parked.join() === "file:///home/a/Downloads/notes.conf" && notch.said[0] === "Not a VPN file · parked", JSON.stringify(notch));
}
done();
