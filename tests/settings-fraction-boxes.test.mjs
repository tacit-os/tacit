// The legacy panel's boxes that show a stored fraction rounded (Niri's and Hyprland's pages, modules/ii/settings/pages/):
// each ConfigSpinBox whose value is Math.round(<stored> * 10 or 100) has its value binding and its onValueChanged run under
// node on a stored value the box cannot show exactly. Filling the box is not a change, so nothing may be saved; one step
// on from there is, and is saved.
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the legacy panel's fraction boxes on a value they show rounded (NiriConfig.qml, HyprlandConfig.qml)");
// what each box's stored value is, as niri and a person leave it: 200/120 is niri's 1.6666666
const stored = { "Scale": 5 / 3, "Scroll factor": 0.85, "Acceleration speed": -0.25, "Blur Offset": 2.75, "Blur Noise (%)": 0.025,
  "Blur Saturation (%)": 1.234, "Slowdown (×10)": 1.25, "Active Opacity": 0.875, "Inactive Opacity": 0.825 };

// a scope whose objects say every write and call made through them
function store(obj, saved, path) {
  return new Proxy(obj, {
    get(t, k) {
      const v = t[k];
      if (typeof v === "function") return (...a) => { saved.push(`${[...path, k].join(".")}(${a.map(x => JSON.stringify(x)).join(", ")})`); };
      return v && typeof v === "object" ? store(v, saved, [...path, String(k)]) : v;
    },
    set(t, k, v) { saved.push(`${[...path, k].join(".")} = ${v}`); t[k] = v; return true; },
  });
}
function scopeWith(storedExpr, v, saved) {
  const objects = {
    monitorConfig: { monitors: [{ scale: 1 }], updateMonitor() {}, applyAndSave() {} },
    monitorCanvas: { selectedIndex: 0 },
    HyprlandConfig: { set() {} },
  };
  if (/monitors\[.*\]\?\.scale/.test(storedExpr)) objects.monitorConfig.monitors[0].scale = v;
  else {
    const keys = storedExpr.split(".");
    let o = objects;
    keys.slice(0, -1).forEach(k => (o = o[k] ??= {}));
    o[keys.at(-1)] = v;
  }
  return Object.fromEntries(Object.entries(objects).map(([k, o]) => [k, store(o, saved, [k])]));
}

for (const file of ["modules/ii/settings/pages/NiriConfig.qml", "modules/ii/settings/pages/HyprlandConfig.qml"]) {
  const src = read(file), page = file.replace(/.*\//, "").replace("Config.qml", "");
  let boxes = 0;
  for (const m of src.matchAll(/\bConfigSpinBox\s*\{/g)) {
    const block = src.slice(m.index, matchBrace(src, m.index + m[0].length - 1) + 1);
    const valueAt = block.search(/\n\s*value:/);
    if (valueAt < 0) continue;
    const valueExpr = readExpression(block, block.indexOf("value:", valueAt) + 6).expr;
    const shown = valueExpr.match(/^Math\.round\((.+) \* (10|100)\)$/);
    if (!shown) continue;
    boxes++;
    const label = block.match(/text:\s*Translation\.tr\("([^"]+)"\)/)?.[1] ?? "?";
    const storedExpr = shown[1].replace(/^\((.*)\s*\?\?\s*[\d.]+\)$/, "$1").trim();
    const from = Number(block.match(/\bfrom:\s*(-?\d+)/)?.[1] ?? 0), n = Number(shown[2]);
    const v = stored[label] ?? (from + 2.5) / n;
    const changedAt = block.indexOf("onValueChanged:"), open = block.indexOf("{", changedAt);
    const handler = block.slice(open + 1, matchBrace(block, open));
    const run = value => {
      const saved = [];
      const scope = scopeWith(storedExpr, v, saved);
      const filled = value ?? inScope(scope, "", `return (${valueExpr});`)();
      inScope({ ...scope, value: filled }, "", handler)();
      return { filled, saved };
    };
    const opened = run();
    check(`${page} ${label}: a stored ${+v.toFixed(4)} shown as ${opened.filled} is not saved again`, opened.saved.length === 0, opened.saved.join("; "));
    const stepped = run(opened.filled + 1);
    check(`${page} ${label}: one more is saved`, stepped.saved.length > 0, "nothing was saved");
  }
  check(`${page}: its fraction boxes were found`, boxes > 0, "none");
}
done();
