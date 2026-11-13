// tacit-install keeps NVIDIA's open driver (nvidia-open, nvidia-utils) only for a card it drives, Turing and newer: an
// older one is left to nouveau, which nvidia-utils blacklists, so a GTX 1060 alone had no graphics driver at all
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree } from "./lib/check.mjs";
console.log("== NVIDIA's driver kept or removed (scripts/setup/tacit-install)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "nvidia_driver.py"), join(tree, "scripts/setup/tacit-install")], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
process.exit(r.status ?? 1);
