// tacit-install next to Windows, stopped partway (scripts/setup/tacit-install, its own functions under python on a
// made-up partition table): the two partitions it had made stayed, held the free room, and Try again offered to shrink
// Windows a second time beside them
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree } from "./lib/check.mjs";
console.log("== Try again after a stopped install next to Windows (scripts/setup/tacit-install)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "next_to_retry.py"), join(tree, "scripts/setup/tacit-install")], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
process.exit(r.status ?? 1);
