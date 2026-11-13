// What the shelf drops when the shell starts (modules/common/widgets/DropShelf.qml, pruneProc): its own command, built
// by its own binding from a shelf list, runs under bash with a pretend mountpoint first on PATH for which one drive,
// /run/media/someone/MOUNTED, is mounted; every path it prints is removed from the shelf.
import { execFileSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the shelf at the next start (DropShelf.qml prune)");
const src = read("modules/common/widgets/DropShelf.qml");
const esc = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");
const StringUtils = { shellSingleQuoteEscape: inScope({}, esc.params, esc.body) };
const expr = readExpression(src, src.indexOf("command:", src.indexOf("id: pruneProc")) + 8).expr;

const dir = mkdtempSync(join(tmpdir(), "tacit-shelf-"));
try {
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "mountpoint"), '#!/bin/bash\n[ "$2" = /run/media/someone/MOUNTED ]\n');
  chmodSync(join(bin, "mountpoint"), 0o755);
  const here = join(dir, "here.jpg");
  writeFileSync(here, "");
  const items = {
    [here]: "kept",
    [join(dir, "deleted.jpg")]: "dropped",
    [join(dir, "it's gone.jpg")]: "dropped",
    "/run/media/someone/STICK/photos/beach.jpg": "kept",
    "/media/someone/CARD/DCIM/1.jpg": "kept",
    "/mnt/backup/report.pdf": "kept",
    "/run/media/someone/MOUNTED/deleted.jpg": "dropped",
  };
  const command = inScope({ root: { items: Object.keys(items) }, StringUtils }, "", `return (${expr});`)();
  const out = execFileSync(command[0], command.slice(1), { env: { PATH: `${bin}:${process.env.PATH}` }, encoding: "utf8" });
  const dropped = out.split("\n").map(l => l.trim()).filter(Boolean);
  for (const [path, want] of Object.entries(items)) {
    const got = dropped.includes(path) ? "dropped" : "kept";
    const what = path.startsWith(dir) ? path.slice(dir.length + 1) : path;
    check(`${what} is ${want}`, got === want, `it was ${got}`);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
