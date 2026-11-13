// A tile's thumbnail (modules/common/widgets/ThumbnailImage.qml): its own requestGeneration(), start and size handlers,
// exit handler and retry timer run under node with a pretend Process that counts its runs and ends each with the exit
// code the script gives for that tile; and the script its command binding builds runs under bash, with a pretend magick
// first on PATH, on pictures dated before, at and after now.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a tile's thumbnail (ThumbnailImage.qml)");
const src = read("modules/common/widgets/ThumbnailImage.qml");
const after = (key, from = 0) => readExpression(src, src.indexOf(key, from) + key.length).expr;
const block = e => (e.startsWith("{") ? e.slice(1, -1) : e);

// a tile for sourcePath whose script run ends with code; how many times the script ran, retries included
function runs(sourcePath, code) {
  let count = 0, timer = null;
  const proc = { command: ["bash", "-c", "thumbgen", sourcePath], _running: false };
  const root = { sourcePath, generateThumbnail: true, holdsThumbnailSlot: false, generatingCommand: "", tries: 0,
    thumbnailPath: sourcePath ? "/cache/x.png" : "", status: 0, source: "" };
  const scope = { root, thumbnailGeneration: proc, Image: { Error: 3 }, Qt: { callLater: f => f(), binding: f => f },
    Images: { requestThumbnailSlot: () => true, releaseThumbnailSlot() {} }, retryTimer: { restart: () => (timer = root.requestGeneration) } };
  for (const name of ["requestGeneration", "releaseThumbnailSlot"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const onExited = inScope(scope, "", `return (${after("onExited:", src.indexOf("id: thumbnailGeneration"))});`)();
  Object.defineProperty(proc, "running", { get: () => proc._running, set: v => { if (v && !proc._running) { count++; proc._running = true; } } });
  const start = inScope(scope, "", block(after("Component.onCompleted:")));
  const sized = inScope(scope, "", block(after("onSourceSizeChanged:")));
  start();
  sized();
  // each run ends, and a retry the timer holds fires, until none is left
  for (let i = 0; i < 20 && proc._running; i++) {
    proc._running = false;
    onExited(code, 0);
    if (timer) { const t = timer; timer = null; t(); }
  }
  return count;
}

check("a tile with no file starts no thumbnail run", runs("", 2) === 0, `the script ran ${runs("", 2)} times`);
check("a picture's tile still makes its thumbnail, once", runs("/home/someone/Pictures/a.jpg", 1) === 1, `${runs("/home/someone/Pictures/a.jpg", 1)} runs`);

// the script on a picture whose modified time is secs from now: its exit code (1 made, 3 still being written) and
// whether the thumbnail is there after
const dir = mkdtempSync(join(tmpdir(), "tacit-thumb-"));
try {
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "magick"), '#!/bin/bash\nprintf png > "${@: -1}"\n');
  chmodSync(join(bin, "magick"), 0o755);
  const thumbFor = (secs, n) => {
    const pic = join(dir, `${n}.jpg`), thumb = join(dir, "thumbnails", "normal", `${n}.png`);
    writeFileSync(pic, "jpeg");
    const t = Date.now() / 1000 + secs;
    utimesSync(pic, t, t);
    const root = { sourcePath: pic, thumbnailPath: thumb, thumbnailSizeName: "normal" };
    const command = inScope({ root, Images: { thumbnailSizes: { normal: 128 } }, FileUtils: { trimFileProtocol: p => p.replace(/^file:\/\//, "") } },
      "", block(after("command:", src.indexOf("id: thumbnailGeneration"))))();
    const r = spawnSync(command[0], command.slice(1), { env: { PATH: `${bin}:${process.env.PATH}` } });
    return { code: r.status, made: existsSync(thumb) };
  };
  const future = thumbFor(86400, "tomorrow"), now = thumbFor(0, "now"), old = thumbFor(-3600, "old");
  check("a picture dated tomorrow (a camera's clock ahead) gets its thumbnail", future.code === 1 && future.made,
    `the script exits ${future.code}${future.code === 3 ? ", \"still being written\"" : ""}`);
  check("a picture written this second is still waited for", now.code === 3 && !now.made, `the script exits ${now.code}`);
  check("a picture from an hour ago gets its thumbnail", old.code === 1 && old.made, `the script exits ${old.code}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
