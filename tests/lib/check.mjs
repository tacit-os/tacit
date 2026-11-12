// What every node test shares: where the tree under test is, and ok / FAIL lines with an exit code to match.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

// the shell tree the tests read: this checkout, or TACIT_TREE (an older one, to show a test fails on the old code)
export const tree = process.env.TACIT_TREE || join(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const read = path => readFileSync(join(tree, path), "utf8");

let failed = 0;
export function check(name, ok, why = "") {
  if (ok) console.log(`  ok    ${name}`);
  else { failed++; console.log(`  FAIL  ${name}${why ? `: ${why}` : ""}`); }
}
export function done() {
  process.exitCode = failed ? 1 : 0;
}
