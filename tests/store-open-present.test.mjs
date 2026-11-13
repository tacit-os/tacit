// store-open (bin/store-open), which the launcher's Apps runs with no page named: Apps is brought forward on the page it
// is on, so an app's page with its install going stays, and a page named (yours, discover, a search) still goes there.
// Run under sh with tacit-app replaced by one that notes its calls; store.qml's IPC handler has the present it calls.
import { spawnSync } from "child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read, tree } from "./lib/check.mjs";

function calls(...args) {
  const dir = mkdtempSync(join(tmpdir(), "tacit-store-open-"));
  try {
    writeFileSync(join(dir, "tacit-app"), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$LOG"\n', { mode: 0o755 });
    const r = spawnSync("sh", [join(tree, "bin/store-open"), ...args],
      { encoding: "utf8", env: { PATH: process.env.PATH, HOME: dir, TACIT_BIN: dir, LOG: join(dir, "log") } });
    if (r.status !== 0) throw new Error(`store-open ${args.join(" ")}: ${r.status} ${r.stderr}`);
    return existsSync(join(dir, "log")) ? readFileSync(join(dir, "log"), "utf8").trim().split("\n") : [];
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

console.log("== Apps opened again from the launcher stays on its page (bin/store-open, store.qml)");
const plain = calls();
check("no page named: the window is brought forward as it is, not turned back to Discover",
  same(plain, ["ensure store", "call store present", "focus store"]), JSON.stringify(plain));
check("and store.qml's IPC handler has present", /IpcHandler\s*\{[^]*?target:\s*"store"[^]*?function present\(\): void/.test(read("store.qml")));
check("Your apps named: goes there", same(calls("yours")[1], "call store page yours"), JSON.stringify(calls("yours")));
check("Discover named: goes there", same(calls("discover")[1], "call store page discover"), JSON.stringify(calls("discover")));
check("a search: searches", same(calls("search", "edit", "photos")[1], "call store search edit photos"), JSON.stringify(calls("search", "edit", "photos")));
done();
