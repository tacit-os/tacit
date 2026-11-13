// The palette's own calculator, used when qalc is not installed (services/PaletteMath.js): run under node, its answers
// to the sums people type for a price with tax or a discount should be qalc's.
import { check, done, read } from "./lib/check.mjs";

const evaluate = new Function(`${read("services/PaletteMath.js").replace(/^\.pragma.*$/m, "")}\nreturn evaluate;`)();

console.log("== the palette's calculator without qalc (services/PaletteMath.js)");
// what qalc -t answers to each
const cases = [["100+10%", "110"], ["200-10%", "180"], ["100+10%+10%", "121"], ["100+(5+5)%", "110"], ["100+-10%", "90"],
  ["100+2*10%", "100.2"], ["100*10%", "10"], ["100/10%", "1000"], ["50%", "0.5"], ["10%+5", "5.1"], ["3x4", "12"], ["0 x 10", "0"]];
const wrong = cases.filter(([e, want]) => evaluate(e) !== want).map(([e, want]) => `${e} gave ${evaluate(e)}, not ${want}`);
check("a + b% is a plus b percent of a, and % elsewhere is a hundredth, as qalc reads them", wrong.length === 0, wrong.join("; "));
check("0x10 is not read as 0 times 10: no answer rather than a wrong one", evaluate("0x10") === null && evaluate("(0x1f)") === null,
  `0x10 gave ${evaluate("0x10")}, (0x1f) gave ${evaluate("(0x1f)")}`);
done();
