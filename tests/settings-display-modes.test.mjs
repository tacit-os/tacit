// Settings > Display & power's Resolution choices (tacit-settings.qml): the row's options binding runs under node on a
// monitor's list as Hyprland gives it (availableModes), where one size comes at rates that round to the same whole
// hertz (60.00 and 59.94, 144.00 and 143.98) and a mode can be listed twice. No two choices may read the same.
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Resolution choices on Display & power (tacit-settings.qml)");
const src = read("tacit-settings.qml");
const at = src.indexOf("options:", src.indexOf(": resolution` : \"Resolution\""));
const expr = readExpression(src, at + "options:".length).expr;
const body = expr.startsWith("{") ? expr.slice(1, matchBrace(expr, 0)) : `return (${expr});`;
const options = modes => inScope({ modelData: { modes } }, "", body)();

const modes = ["2560x1440@144.00Hz", "2560x1440@143.98Hz", "2560x1440@59.95Hz", "1920x1080@60.00Hz", "1920x1080@59.94Hz",
  "1920x1080@50.00Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"];
const got = options(modes);
const labels = got.map(o => o.label);
const twice = labels.filter((l, i) => labels.indexOf(l) !== i);
check("no two choices read the same", twice.length === 0, `twice: ${[...new Set(twice)].join(", ")}`);
check("60.00 and 59.94 Hz of one size say which is which", labels.includes("1920 × 1080 · 60 Hz") && labels.includes("1920 × 1080 · 59.9 Hz"), labels.join(" | "));
check("144.00 and 143.98 Hz too", labels.includes("2560 × 1440 · 144 Hz") && labels.includes("2560 × 1440 · 143.98 Hz"), labels.join(" | "));
check("a rate with no twin stays in whole hertz", labels.includes("1280 × 720 · 60 Hz") && labels.includes("2560 × 1440 · 60 Hz"), labels.join(" | "));
check("each choice still picks its own mode", got.find(o => o.label === "1920 × 1080 · 59.9 Hz")?.value === "1920x1080@59.94", JSON.stringify(got));
check("a mode Hyprland lists twice is offered once", got.filter(o => o.value === "1920x1080@60.00").length === 1, JSON.stringify(got));
done();
