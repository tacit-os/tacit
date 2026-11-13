// Importing a preset zip (scripts/presets.sh --import-zip, Settings' presets) whose JSON is broken: the import fails and
// says so, and no empty preset is left (nor one imported before under that name lost). The script runs under bash in a
// home of its own on zips made here.
import { execFileSync, spawnSync } from "child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== a preset zip with broken JSON is refused (scripts/presets.sh --import-zip)");
const home = mkdtempSync(join(tmpdir(), "tacit-preset-import-"));
const zip = (name, text) => {
  const path = join(home, `${name}.zip`);
  execFileSync("python3", ["-I", "-c", "import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], 'w'); z.writestr('mine/mine.json', sys.argv[2]); z.close()", path, text]);
  return path;
};
const imported = join(home, ".cache/quickshell/presets_imported/mine.json");
const run = path => spawnSync("bash", [join(tree, "scripts/presets.sh"), "--import-zip", path], { encoding: "utf8", env: { PATH: process.env.PATH, HOME: home } });
const preset = () => (existsSync(imported) ? readFileSync(imported, "utf8") : null);

try {
  let r = run(zip("good", JSON.stringify({ appearance: { transparency: { enable: true } }, apps: { terminal: "foot" } })));
  const good = preset();
  check("a good zip is imported, less what a preset never carries", r.status === 0 && JSON.parse(good ?? "{}").appearance?.transparency?.enable === true && !JSON.parse(good ?? "{}").apps,
    `exit ${r.status}: ${good}`);
  for (const [what, text] of [["cut short", '{"appearance": {"transparency": '], ["empty", ""]]) {
    r = run(zip("bad", text));
    check(`a zip whose JSON is ${what} fails and says so`, r.status !== 0 && /not valid JSON/.test(r.stderr), `exit ${r.status}, said ${JSON.stringify(r.stdout + r.stderr)}`);
    check("and the preset imported before under that name is as it was", preset() === good, JSON.stringify(preset()));
  }
} finally {
  rmSync(home, { recursive: true, force: true });
}
done();
