// settings-open <page> (scripts/settings/open.sh, then tacit-settings.qml showPage()): the page asked for is the one
// Settings shows. showPage() runs under node with SettingsApp's own keyFor() and SettingsCatalog's pages; open.sh runs
// under bash with a pretend qs that is still starting (it holds the instance and does not answer yet) or not running.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== settings-open's page (scripts/settings/open.sh, services/SettingsApp.qml, tacit-settings.qml)");
{
  const categories = inScope({}, "", `return (${qmlProperty(read("services/SettingsCatalog.qml"), "categories")});`)();
  const appSrc = read("services/SettingsApp.qml");
  const SettingsApp = { oldPages: inScope({}, "", `return (${qmlProperty(appSrc, "oldPages")});`)() };
  const kf = qmlFunction(appSrc, "keyFor");
  SettingsApp.keyFor = inScope({ root: SettingsApp, SettingsCatalog: { categories } }, kf.params.replace(/:\s*\w+/g, ""), kf.body);
  const sp = qmlFunction(read("tacit-settings.qml"), "showPage");
  const shown = key => {
    const root = { categories, current: 0, pageAnchor: "", anchorAsked() {} };
    inScope({ root, SettingsApp }, sp.params, sp.body)(key);
    return `${categories[root.current].key}${root.pageAnchor ? `:${root.pageAnchor}` : ""}`;
  };
  const cases = [["sound", "sound"], ["Sound", "sound"], ["Network", "network"], ["NETWORK", "network"], ["Bluetooth", "bluetooth"],
    ["hyprland", "windows"], ["Desktop", "look"], ["desktop", "desktop"], ["about:updates", "about:updates"], ["nothing", "look"]];
  const wrong = cases.filter(([k, want]) => shown(k) !== want).map(([k, want]) => `${k} showed ${shown(k)}, not ${want}`);
  check("a page's key in any case and the old panel's names show their page; the old Desktop is still Appearance", wrong.length === 0, wrong.join("; "));
}
{
  const tmp = mkdtempSync(join(tmpdir(), "tacit-settings-open-"));
  try {
    writeFileSync(join(tmp, "qs"), `#!/bin/bash
case "$*" in
  *"ipc call settingsApp page"*)
    n=$(cat "$STATE/fails"); [ "$n" -gt 0 ] && { echo $((n - 1)) > "$STATE/fails"; exit 1; }
    echo "page \${@: -1}" >> "$STATE/log" ;;
  *"-n -d"*)
    echo "start $TACIT_SETTINGS_PAGE" >> "$STATE/log"
    [ -e "$STATE/running" ] || { touch "$STATE/running"; echo 0 > "$STATE/fails"; } ;;
esac
`);
    writeFileSync(join(tmp, "hyprctl"), "#!/bin/bash\nexit 0\n");
    for (const n of ["qs", "hyprctl"]) chmodSync(join(tmp, n), 0o755);
    const run = (page, { running, fails }) => {
      rmSync(join(tmp, "log"), { force: true });
      rmSync(join(tmp, "running"), { force: true });
      if (running) writeFileSync(join(tmp, "running"), "");
      writeFileSync(join(tmp, "fails"), `${fails}`);
      execFileSync("bash", [join(tree, "scripts/settings/open.sh"), page], { env: { PATH: `${tmp}:${process.env.PATH}`, STATE: tmp } });
      return existsSync(join(tmp, "log")) ? readFileSync(join(tmp, "log"), "utf8").trim().split("\n") : [];
    };
    const starting = run("sound", { running: true, fails: 3 });
    check("opened again while the first Settings is still starting: it is turned to the page once it answers",
      starting.includes("page sound"), JSON.stringify(starting));
    const fresh = run("sound", { running: false, fails: 1 });
    check("not running: Settings starts on the page", fresh[0] === "start sound", JSON.stringify(fresh));
    const plain = run("", { running: false, fails: 1 });
    check("with no page, it starts and asks nothing more", JSON.stringify(plain) === JSON.stringify(["start"]), JSON.stringify(plain));
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
done();
