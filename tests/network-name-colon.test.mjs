// The connected network's name (services/Network.qml, updateNetworkName), which Settings > Network shows and reads the
// IPv4 settings by: the Process's own command, run with a pretend nmcli first on PATH that prints the active
// connections as nmcli -t does (a ":" in a name written as "\:"), and its own stdout handler, with the file's
// splitTerse(), run under node.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the connected network's name with a colon in it (Network.qml)");
const src = read("services/Network.qml");
const proc = objectWith(src, "id: updateNetworkName");
const command = inScope({}, "", `return (${readExpression(proc, proc.indexOf("command:") + 8).expr});`)();
const handler = readExpression(proc, proc.indexOf("onStreamFinished:") + 17).expr;
const split = qmlFunction(src, "splitTerse");
const root = { networkName: "?" };
root.splitTerse = inScope({}, split.params.replace(/:\s*\w+/g, ""), split.body);

const dir = mkdtempSync(join(tmpdir(), "tacit-nmcli-"));
try {
  // what the handler makes of nmcli's active connections
  function name(lines) {
    writeFileSync(join(dir, "active"), lines);
    writeFileSync(join(dir, "nmcli"), `#!/bin/bash\ncat "${join(dir, "active")}"\n`);
    chmodSync(join(dir, "nmcli"), 0o755);
    const r = spawnSync(command[0], command.slice(1), { encoding: "utf8", env: { PATH: `${dir}:/usr/bin:/bin` } });
    const scope = { root, text: r.stdout ?? "" };
    inScope(scope, "", handler.startsWith("{") ? handler.slice(1, -1) : handler)();
    return root.networkName;
  }
  const n1 = name("wg0:wireguard\nCafe\\: Guest:802-11-wireless\n");
  check('"Cafe: Guest", behind a VPN listed first, is named in full', n1 === "Cafe: Guest", JSON.stringify(n1));
  const n2 = name("Home:802-11-wireless\n");
  check("a plain name is as it was", n2 === "Home", JSON.stringify(n2));
  const n3 = name("Office\\\\LAN:802-3-ethernet\n");
  check("a backslash in a wired profile's name is kept", n3 === "Office\\LAN", JSON.stringify(n3));
  const n4 = name("");
  check("no link: no name", n4 === "", JSON.stringify(n4));
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
