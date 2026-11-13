// The phone icons' backfill at the shell's start (scripts/notifications/phone-icon.py --all, read by
// services/Notifications.qml's phoneAll as a list it walks with for..of): one record that cannot be read is left out,
// and when nothing can be read the answer is still a list. phone-icon.py runs under python3 with a pretend busctl
// holding four phone notifications: one whose answer never comes (busctl's 3 s timeout) and one whose icon file is cut short.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the phone icons' backfill survives one bad record (scripts/notifications/phone-icon.py --all)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-phone-all-"));
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
writeFileSync(join(tmp, "icon-ok"), png);
writeFileSync(join(tmp, "icon-cut"), png.subarray(0, 45));
const record = (app, title, icon) => JSON.stringify({ type: "a{sv}", data: [{ appName: { type: "s", data: app }, title: { type: "s", data: title },
  text: { type: "s", data: `${title}!` }, hasIcon: { type: "b", data: true }, iconPath: { type: "s", data: join(tmp, icon) } }] });
const dev = "/modules/kdeconnect/devices/abc/notifications";
writeFileSync(join(tmp, "busctl"), `#!/bin/bash
case " $* " in
  *" tree org.kde.kdeconnect "*) [ -n "$TREE_HANGS" ] && exec sleep 5; printf '%s\\n' /modules/kdeconnect ${dev}/1 ${dev}/2 ${dev}/3 ${dev}/4 ;;
  *" ${dev}/4 "*) echo '${record("Signal", "Ana", "icon-ok")}' ;;
  *" ${dev}/3 "*) exec sleep 5 ;;
  *" ${dev}/2 "*) echo '${record("WhatsApp", "Bo", "icon-cut")}' ;;
  *" ${dev}/1 "*) echo '${record("Gmail", "Invoice", "icon-ok")}' ;;
esac
`);
chmodSync(join(tmp, "busctl"), 0o755);

try {
  const all = env => {
    const r = spawnSync("python3", ["-I", join(tree, "scripts/notifications/phone-icon.py"), "--all", join(tmp, "cache")],
      { encoding: "utf8", env: { PATH: `${tmp}:${process.env.PATH}`, HOME: tmp, ...env }, timeout: 30000 });
    try { return JSON.parse(r.stdout); } catch (e) { return r.stdout.trim(); }
  };
  const recs = all({});
  check("the answer is a list", Array.isArray(recs), JSON.stringify(recs));
  const apps = Array.isArray(recs) ? recs.map(r => r.app) : [];
  check("the readable records are in it, newest first, each with its icon copied",
    apps.includes("Signal") && apps.includes("Gmail") && apps.indexOf("Signal") < apps.indexOf("Gmail")
      && recs.filter(r => r.app !== "WhatsApp").every(r => r.path?.startsWith(join(tmp, "cache") + "/") && r.kind),
    JSON.stringify(recs));
  check("the one that never answered is left out", Array.isArray(recs) && !apps.includes(undefined) && recs.length >= 2 && recs.length <= 3, JSON.stringify(apps));
  const none = all({ TREE_HANGS: "1" });
  check("when the phone's records cannot be listed at all, the answer is an empty list", Array.isArray(none) && none.length === 0, JSON.stringify(none));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
