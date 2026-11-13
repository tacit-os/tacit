// A crosshair code pasted into Settings (modules/ii/overlay/crosshair/CrosshairContent.qml): its propertyMap and
// loadFromCode(), run under node over the file's own defaults as reloadFromCode() runs them, the default code first.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a pasted crosshair code (CrosshairContent.qml)");
const src = read("modules/ii/overlay/crosshair/CrosshairContent.qml");
const load = qmlFunction(src, "loadFromCode");

function crosshair(code) {
  const root = {};
  // the raw properties, in the file's order, each from its own default
  for (const m of src.matchAll(/^    property (?:int|real|bool|string) (\w+): (.+)$/gm))
    root[m[1]] = inScope(root, "", `return (${m[2]});`)();
  root.propertyMap = inScope(root, "", `return (${qmlProperty(src, "propertyMap")});`)();
  root.root = root;
  const run = inScope(root, load.params.replace(/:\s*\w+/g, ""), load.body);
  run(root.defaultCode);
  run(code);
  return root;
}

// a dot only, as a Valorant code gives it: inner lines (0b) and outer lines (1b) off
{
  const c = crosshair("0;P;c;5;h;0;d;1;z;3;0b;0;1b;0");
  check("a dot-only code (0b;0;1b;0) turns the inner lines off", c.innerLines === false, `innerLines ${c.innerLines}`);
  check("and the outer lines, and shows the dot", c.outerLines === false && c.centerDot === true, `outerLines ${c.outerLines}, centerDot ${c.centerDot}`);
}
{
  const c = crosshair("0b;1");
  check("0b;1 keeps them on", c.innerLines === true, `innerLines ${c.innerLines}`);
}
done();
