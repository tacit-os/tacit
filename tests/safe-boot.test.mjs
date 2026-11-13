// tacit-install's boot entries (scripts/setup/tacit-install over a throwaway root): "Tacit (safe start)" beside tacit.conf,
// with its root and resume and none of the quiet options, so a kernel option that stops the start has a way back from the
// menu without the stick (Discord, OYINOS, 2026-11-13: video= options, a blank screen, editing off)
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree } from "./lib/check.mjs";
console.log("== the safe start entry (scripts/setup/tacit-install)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "safe_boot.py"), join(tree, "scripts/setup/tacit-install")], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
process.exit(r.status ?? 1);
