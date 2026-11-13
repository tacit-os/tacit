// The terminal's colours for the Monochrome palette type (scripts/colors/generate_colors_material.py, as switchwall.sh
// runs it: --termscheme scheme-base.json --blend_bg_fg): grey throughout, with the ground and the text from the palette
// as for every other type. Runs under the colour helpers' own Python environment (scripts/venv.sh's places); without
// one that has materialyoucolor and Pillow it is not run and says so.
import { spawnSync } from "child_process";
import { existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Monochrome gives the terminal grey colours on the palette's ground (generate_colors_material.py)");
const python = [process.env.ILLOGICAL_IMPULSE_VIRTUAL_ENV, join(process.env.XDG_STATE_HOME || join(homedir(), ".local/state"), "quickshell/.venv"), "/usr/lib/tacit/venv"]
  .filter(Boolean).map(v => join(v, "bin/python3")).concat(["python3"])
  .find(p => (p === "python3" || existsSync(p)) && spawnSync(p, ["-I", "-c", "import materialyoucolor, PIL"]).status === 0);
if (!python) {
  console.log("  skip  no Python here with materialyoucolor and Pillow (the colour helpers' environment)");
} else {
  const colours = scheme => {
    const r = spawnSync(python, ["-I", join(tree, "scripts/colors/generate_colors_material.py"), "--color", "#3a6ea5", "--mode", "dark",
      "--scheme", scheme, "--termscheme", join(tree, "scripts/colors/terminal/scheme-base.json"), "--blend_bg_fg"], { encoding: "utf8" });
    return Object.fromEntries([...r.stdout.matchAll(/^\$(\w+): (#[0-9A-F]{6});$/gm)].map(m => [m[1], m[2]]));
  };
  const grey = hex => hex && hex.slice(1, 3) === hex.slice(3, 5) && hex.slice(3, 5) === hex.slice(5, 7);
  const level = hex => parseInt(hex.slice(1, 3), 16);
  const mono = colours("scheme-monochrome");
  const terms = Object.keys(mono).filter(k => /^term\d+$/.test(k));
  check("all 16 terminal colours are made", terms.length === 16, terms.join(" "));
  check("every one of them is grey", terms.every(k => grey(mono[k])), terms.filter(k => !grey(mono[k])).map(k => `${k} ${mono[k]}`).join(", "));
  check("the ground is the palette's, not Gruvbox's #282828",
    mono.term0 !== "#282828" && grey(mono.surfaceContainerLow) && Math.abs(level(mono.term0) - level(mono.surfaceContainerLow)) <= 4,
    `term0 ${mono.term0}, surfaceContainerLow ${mono.surfaceContainerLow}`);
  check("the bright text is the palette's", grey(mono.onSurface) && Math.abs(level(mono.term15) - level(mono.onSurface)) <= 2, `term15 ${mono.term15}, onSurface ${mono.onSurface}`);
  const tonal = colours("scheme-tonal-spot");
  check("another palette type keeps coloured terminal colours", tonal.term1 && !grey(tonal.term1) && !grey(tonal.term2), `${tonal.term1} ${tonal.term2}`);
}
done();
