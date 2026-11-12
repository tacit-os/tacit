// The public IP lookup (services/Network.qml, modules/ii/bar/NetworkSpeedPopup.qml): Network's own publicIpKey, its
// handler and curl's answer handler, with the bar popup's own open and close handlers, run under node. The address goes
// to a third party (api.ipify.org), so it may be asked for only while something that shows it is open.
import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const net = read("services/Network.qml");
const pop = read("modules/ii/bar/NetworkSpeedPopup.qml");

// the body of "<key>: { ... }" or "<key>: <statement>", the first one found after from; null when there is none
function handler(src, key, from = 0) {
  const at = src.indexOf(`${key}:`, from);
  if (at < 0) return null;
  let i = at + key.length + 1;
  while (/\s/.test(src[i])) i++;
  return src[i] === "{" ? src.slice(i + 1, matchBrace(src, i)) : readExpression(src, i).expr;
}

// Network as far as the lookup touches it: what QML does when a property the key reads changes (the key is read again,
// and its handler runs when it moved), with curl's runs counted instead of made
function network() {
  const state = { publicIpViewers: 0, connectivity: "", ipAddress: "", publicIpAddress: "" };
  const curl = { asked: 0, set running(v) { if (v) this.asked++; } };
  let root, last = "";
  const key = inScope({ get root() { return root; } }, "", `return (${qmlProperty(net, "publicIpKey")});`);
  const moved = inScope({ get root() { return root; }, updatePublicIp: curl }, "", handler(net, "onPublicIpKeyChanged"));
  root = new Proxy(state, {
    get: (t, k) => (k === "publicIpKey" ? key() : t[k]),
    set: (t, k, v) => {
      t[k] = v;
      const now = key();
      if (now !== last) { last = now; moved(); }
      return true;
    },
  });
  const answer = inScope({ root }, "text", handler(net, "onStreamFinished", net.indexOf("id: updatePublicIp")));
  return { root, curl, answer };
}

// the popup as far as its own handlers go: a LazyLoader whose active is the popup being shown
function popup(Network) {
  const p = { active: false };
  const body = k => handler(pop, k) ?? "";
  const changed = inScope({ root: p, Network }, "", body("onActiveChanged"));
  const destroyed = inScope({ root: p, Network }, "", body("Component.onDestruction"));
  return {
    open() { p.active = true; changed(); },
    close() { p.active = false; changed(); },
    destroy() { destroyed(); },
  };
}

console.log("The public IP lookup (services/Network.qml, modules/ii/bar/NetworkSpeedPopup.qml)");

{
  const { root, curl, answer } = network();
  const view = popup(root);
  root.ipAddress = "192.168.1.20";
  root.connectivity = "full";
  check("joining a network with nothing open that shows the public IP asks nobody", curl.asked === 0,
    `curl ran ${curl.asked} time(s) for a value nothing showed`);

  const before = curl.asked;
  view.open();
  answer("203.0.113.7\n");
  check("opening the network popup asks once, and the popup has the answer",
    curl.asked - before === 1 && root.publicIpAddress === "203.0.113.7",
    `opening ran curl ${curl.asked - before} time(s), public IP "${root.publicIpAddress}"`);

  root.ipAddress = "10.0.0.5";
  check("a new link while the popup is open asks again", curl.asked === 2, `curl ran ${curl.asked} time(s)`);

  view.close();
  root.ipAddress = "172.16.0.9";
  check("closing the popup lets the address go, and a new link after that asks nobody",
    root.publicIpAddress === "" && curl.asked === 2, `public IP "${root.publicIpAddress}", curl ran ${curl.asked} time(s)`);

  view.open();
  view.close();
  answer("198.51.100.4\n");
  check("an answer that lands after the popup closed is not kept for the next opening to show",
    curl.asked === 3 && root.publicIpAddress === "", `curl ran ${curl.asked} time(s), public IP "${root.publicIpAddress}"`);

  view.open();
  view.destroy();   // the bar turned off, or its screen gone, with the popup open
  root.ipAddress = "192.168.1.21";
  check("a popup taken away while open stops asking", root.publicIpViewers === 0 && curl.asked === 4,
    `viewers ${root.publicIpViewers}, curl ran ${curl.asked} time(s)`);
}

// every other file that shows the public IP has to count itself in the same way, or it would never get one
{
  const readers = [];
  const walk = dir => {
    for (const d of readdirSync(join(tree, dir), { withFileTypes: true })) {
      const rel = dir ? `${dir}/${d.name}` : d.name;
      if (d.name === ".git" || d.name === "node_modules") continue;
      if (d.isDirectory()) walk(rel);
      else if (d.isFile() && rel.endsWith(".qml") && rel !== "services/Network.qml"
        && readFileSync(join(tree, rel), "utf8").includes("publicIpAddress")) readers.push(rel);
    }
  };
  walk("");
  const uncounted = readers.filter(f => !read(f).includes("publicIpViewers"));
  check("every surface that shows the public IP counts itself in while it is open",
    readers.length > 0 && uncounted.length === 0, `not counted: ${uncounted.join(", ")}`);
}

done();
