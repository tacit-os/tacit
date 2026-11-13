// The notch's reserved band through a lock (modules/ii/island/Island.qml): every `active:` binding in the file is run
// under node with the screen locked and unlocked, and matched to what it holds by the file's brackets. The window that
// reserves the band (its exclusiveZone) must stay mapped while locked, or every tiled window grows under the lock and
// shrinks back at unlock; the notch inside it still goes at lock and comes back at unlock.
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch's reserved band through a lock (Island.qml)");
const src = read("modules/ii/island/Island.qml");

// the bracket pair of the innermost object around index at
function around(at) {
  for (let i = at, depth = 0; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{" && depth-- === 0) return { open: i, close: matchBrace(src, i) };
  }
  return null;
}
const holds = (obj, at) => obj.open < at && at < obj.close;
const loaders = [...src.matchAll(/^\s*active:/gm)].map(m => {
  const start = m.index + m[0].length;
  const expr = readExpression(src, start).expr;
  const when = screenLocked => Boolean(inScope({ GlobalStates: { screenLocked } }, "", `return (${expr});`)());
  return { obj: around(m.index), expr, locked: when(true), unlocked: when(false) };
});

const zone = src.indexOf("exclusiveZone: Config.options.island.reservedHeight");
const notch = src.search(/\bIslandContent\s*\{/);
check("the file still has the window's reserve and the notch", zone > 0 && notch > 0);

const aroundZone = loaders.filter(l => holds(l.obj, zone));
const gone = aroundZone.filter(l => !l.locked);
check("the window that reserves the notch's band stays while the screen is locked", gone.length === 0,
  gone.map(l => `active: ${l.expr}`).join("; "));

const aroundNotch = loaders.filter(l => holds(l.obj, notch));
check("the notch inside it goes at lock", aroundNotch.some(l => !l.locked), aroundNotch.map(l => `active: ${l.expr}`).join("; "));
check("and is there unlocked", aroundNotch.every(l => l.unlocked), aroundNotch.map(l => `active: ${l.expr}`).join("; "));
done();
