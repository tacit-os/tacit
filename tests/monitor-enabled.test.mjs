// Settings > Displays' "Enabled" switch on the Hyprland and the Niri pages (modules/ii/settings/pages/HyprlandConfig.qml,
// NiriConfig.qml): the last enabled screen cannot be switched off, since the setting is saved and survives a restart.
// Each page's switch, its enabled binding and its onSwitched, runs under node on pretend monitors.
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== switching off the last screen (HyprlandConfig.qml, NiriConfig.qml)");

function enabledSwitch(path) {
  const src = read(path);
  const open = src.lastIndexOf("ConfigSwitch {", src.indexOf('buttonIcon: "tv_off"')) + "ConfigSwitch ".length;
  const block = src.slice(open, matchBrace(src, open) + 1);
  const expr = name => { const m = new RegExp(`\\n\\s*${name}:\\s*`).exec(block); return m ? readExpression(block, m.index + m[0].length).expr : null; };
  return { enabled: expr("enabled"), onSwitched: expr("onSwitched") };
}

function screens(sw, monitors, selected) {
  const saved = [];
  const monitorConfig = { monitors, updateMonitor: (i, change) => saved.push([i, change]), applyAndSave() {} };
  const scope = { monitorConfig, monitorCanvas: { selectedIndex: selected } };
  const enabled = sw.enabled === null ? true : inScope(scope, "", `return (${sw.enabled});`)();
  const flip = value => inScope(scope, "", `return (${sw.onSwitched});`)()(value);
  return { enabled, flip, saved };
}

for (const [page, path] of [["Hyprland", "modules/ii/settings/pages/HyprlandConfig.qml"], ["Niri", "modules/ii/settings/pages/NiriConfig.qml"]]) {
  const sw = enabledSwitch(path);
  {
    const s = screens(sw, [{ name: "eDP-1", disabled: false }], 0);
    check(`${page}: with one screen, its Enabled switch cannot be used`, !s.enabled, "it can be switched");
    s.flip(false);
    check(`${page}: switching the one screen off anyway changes and saves nothing`, s.saved.length === 0, `it saved ${JSON.stringify(s.saved)}`);
  }
  {
    const s = screens(sw, [{ name: "eDP-1", disabled: false }, { name: "HDMI-A-1", disabled: false }], 1);
    s.flip(false);
    check(`${page}: with two screens on, one can be switched off`, s.enabled && s.saved.length === 1 && s.saved[0][1].disabled === true, `saved ${JSON.stringify(s.saved)}`);
  }
  {
    const s = screens(sw, [{ name: "eDP-1", disabled: false }, { name: "HDMI-A-1", disabled: true }], 1);
    s.flip(true);
    check(`${page}: a screen that is off can be switched back on`, s.enabled && s.saved.length === 1 && s.saved[0][1].disabled === false, `saved ${JSON.stringify(s.saved)}`);
  }
}

done();
