// Saving over a preset (scripts/presets.sh --save, Settings' Overwrite) when the config cannot be read: the preset is
// kept as it was and the save says so, instead of the preset being left an empty file. The script runs under bash in
// a home of its own.
import { spawnSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Overwrite of a preset with a config that cannot be read keeps the preset (scripts/presets.sh --save)");
const home = mkdtempSync(join(tmpdir(), "tacit-preset-save-"));
const dir = join(home, ".config/illogical-impulse"), config = join(dir, "config.json"), saved = join(dir, "presets/mine.json");
mkdirSync(dir, { recursive: true });
const save = (...args) => spawnSync("bash", [join(tree, "scripts/presets.sh"), "--save", "mine", ...args], { encoding: "utf8", env: { PATH: process.env.PATH, HOME: home } });
const preset = () => (existsSync(saved) ? readFileSync(saved, "utf8") : null);

try {
  writeFileSync(config, JSON.stringify({ appearance: { transparency: { enable: true } }, time: { format: "hh:mm" } }));
  let r = save("my look");
  const first = preset();
  let p = {};
  try { p = JSON.parse(first); } catch (e) {}
  check("a preset is saved with its description, less what a preset never carries",
    r.status === 0 && p.appearance?.transparency?.enable === true && !p.time && p._presetMeta?.description === "my look", `exit ${r.status}: ${first}`);
  for (const [what, text] of [["not valid JSON", '{"appearance": {"transparency": '], ["empty", ""]]) {
    writeFileSync(config, text);
    r = save();
    check(`Overwrite with a config that is ${what} fails and says so`, r.status !== 0 && /could not read/.test(r.stderr), `exit ${r.status}, said ${JSON.stringify(r.stderr)}`);
    check("and the preset is as it was", preset() === first, JSON.stringify(preset()));
  }
  rmSync(config);
  r = save();
  check("with no config at all the preset is kept too", r.status !== 0 && preset() === first, `exit ${r.status}: ${JSON.stringify(preset())}`);
  check("nothing is left beside it", readdirSync(join(dir, "presets")).join() === "mine.json", readdirSync(join(dir, "presets")).join());
} finally {
  rmSync(home, { recursive: true, force: true });
}
done();
