// The shapes' morphs (modules/common/widgets/shapes, a port of androidx.graphics.shapes; ShapeCanvas and
// MaterialLoadingIndicator morph one Material shape into another): the library's own files under node, each loaded as
// QML loads a .pragma library (its .import lines given as namespaces), on the shapes material-shapes.js makes.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { check, done, tree } from "./lib/check.mjs";

const loaded = new Map();
function load(file) {
  if (loaded.has(file)) return loaded.get(file);
  const ns = {};
  loaded.set(file, ns);
  const src = readFileSync(file, "utf8");
  const imports = [...src.matchAll(/^\.import\s+"([^"]+)"\s+as\s+(\w+)/gm)].map(m => [m[2], load(join(dirname(file), m[1]))]);
  const body = src.replace(/^\.(pragma|import)\b.*$/gm, "");
  const names = [...new Set([...body.matchAll(/^(?:class|function|var|let|const)\s+(\w+)/gm)].map(m => m[1]))];
  Object.assign(ns, new Function(...imports.map(i => i[0]), `${body}\nreturn { ${names.join(", ")} };`)(...imports.map(i => i[1])));
  return ns;
}
const lib = join(tree, "modules/common/widgets/shapes");
const Shapes = load(join(lib, "material-shapes.js"));
const { Morph } = load(join(lib, "shapes/morph.js"));
const { MeasuredPolygon, LengthMeasurer } = load(join(lib, "shapes/polygon-measure.js"));
const { featureMapper } = load(join(lib, "shapes/feature-mapping.js"));
const { Corner } = load(join(lib, "shapes/feature.js"));
const { Cubic } = load(join(lib, "shapes/cubic.js"));

console.log("== shape morphs match corner to corner (shapes/polygon-measure.js, feature-mapping.js)");
const names = Object.keys(Shapes).filter(k => /^get[A-Z]/.test(k));
const shape = Object.fromEntries(names.map(n => [n, Shapes[n]()]));
const measure = p => MeasuredPolygon.measurePolygon(new LengthMeasurer(), p);

// a cubic's length is its whole length, and a cut at its end is at its end (t = 1)
{
  const m = new LengthMeasurer(), line = Cubic.straightLine(0, 0, 3, 0);
  check("a straight line 3 long measures 3", Math.abs(m.measureCubic(line) - 3) < 1e-9, `it measures ${m.measureCubic(line)}`);
  // cutAtProgress cuts at a share of the measured length: all of it is the cubic's end
  const end = m.findCubicCutPoint(line, m.measureCubic(line));
  check("a cut at its whole measured length is at its end", Math.abs(end - 1) < 1e-9, `t ${end.toFixed(3)}`);
  const fine = c => { let s = 0, p = c.pointOnCurve(0); for (let i = 1; i <= 1000; i++) { const q = c.pointOnCurve(i / 1000); s += Math.hypot(q.x - p.x, q.y - p.y); p = q; } return s; };
  const worst = Math.min(...shape.getCookie12Sided.cubics.map(c => m.measureCubic(c) / fine(c)).filter(isFinite));
  check("each cubic of a shape measures nearly its length", worst > 0.95, `one measures ${(worst * 100).toFixed(0)} % of it`);
}

// every corner of a shape is measured, at its middle cubic, as Kotlin's measurePolygon does
for (const n of ["getCircle", "getSquare", "getCookie12Sided", "getPill", "getBoom"]) {
  const corners = shape[n].features.filter(f => f instanceof Corner).length, measured = measure(shape[n]).features.length;
  check(`${n.slice(3)}: its ${corners} corners are measured`, measured === corners && corners > 0, `${measured} measured`);
}

// the corners of two shapes are mapped onto each other, in order round both outlines
const inOrder = v => v.filter((x, i) => v[(i + 1) % v.length] < x).length <= 1;
let mapped = 0, shuffled = 0, pairs = 0;
for (const a of names) for (const b of names) {
  const m = featureMapper(measure(shape[a]).features, measure(shape[b]).features);
  pairs++;
  mapped += m.sourceValues.length;
  if (!inOrder(m.sourceValues) || !inOrder(m.targetValues)) shuffled++;
}
check(`corners are mapped between the ${names.length} shapes (more than the 2 points of no mapping)`, mapped / pairs > 2,
  `${(mapped / pairs).toFixed(2)} points a pair`);
check("every mapping runs in order round both outlines", shuffled === 0, `${shuffled} of ${pairs} out of order`);

// a morph starts as the first shape and ends as the second, and to itself it is the shape
const sample = cubics => cubics.flatMap(c => Array.from({ length: 12 }, (_, i) => c.pointOnCurve(i / 12)));
const off = (cubics, p) => { const ref = sample(p.cubics); return Math.max(...sample(cubics).map(q => Math.min(...ref.map(r => Math.hypot(q.x - r.x, q.y - r.y))))); };
let worst = 0, threw = [];
for (const [a, b] of [...names.map(n => [n, n]), ["getSquare", "getCookie12Sided"], ["getCircle", "getBoom"], ["getPill", "getHeart"],
  ["getTriangle", "getFlower"], ["getSunny", "getPuffyDiamond"], ["getPixelCircle", "getClover8Leaf"]]) {
  try {
    const m = new Morph(shape[a], shape[b]);
    worst = Math.max(worst, off(m.asCubics(0), shape[a]), off(m.asCubics(1), shape[b]));
  } catch (e) { threw.push(`${a}→${b}: ${e.message}`); }
}
check("no morph fails", threw.length === 0, threw.join("; "));
check("each morph starts as its first shape and ends as its second", worst < 0.06, `${worst.toFixed(3)} off the outline`);

done();
