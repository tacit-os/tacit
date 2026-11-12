// tacit-install's shared EFI partition rule (Setup, "Choose partitions myself" with no boot partition): replacing CachyOS
// or reinstalling Tacit is allowed, another kept system with Tacit's file names is refused (Discord, OYINOS, 2026-11-12)
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree } from "./lib/check.mjs";
console.log("== the shared EFI partition rule (scripts/setup/tacit-install)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "efi_share.py"), join(tree, "scripts/setup/tacit-install")], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
process.exit(r.status ?? 1);
