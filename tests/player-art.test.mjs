// The media card's cover (modules/common/widgets/Player.qml): its own updateArt() and the download's onExited run under
// node, with the Process as Quickshell 0.3.2 has it (process.cpp: running = true on a running one only queues another
// run, and exited is emitted before that run starts). A track skipped while the last cover downloads gets its own.
import { createHash } from "crypto";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the media card's cover (Player.qml)");
const src = read("modules/common/widgets/Player.qml");
const update = qmlFunction(src, "updateArt");
const at = src.indexOf("onExited:");
const exitedExpr = readExpression(src, at + "onExited:".length).expr;

function card() {
  const files = new Set(), shown = [];
  let running = null, queued = false, downloaded = false;
  const root = {
    artUrl: "", artFilePath: "",
    get downloaded() { return downloaded; },
    set downloaded(v) { downloaded = v; show(); },
  };
  // the Image's source (displayedArtFilePath): each new one is loaded once, there and then
  let source = "";
  function show() {
    const s = !downloaded ? "" : root.artUrl.startsWith("file://") ? root.artUrl : root.artFilePath;
    if (s !== source && s) shown.push({ path: s, there: s.startsWith("file://") || files.has(s) });
    source = s;
  }
  const proc = {
    targetFile: "", artFilePath: "",
    get running() { return running !== null; },
    set running(v) { queued = v; start(); },
  };
  function start() {
    if (running || !queued) return;
    queued = false;
    running = { url: proc.targetFile, path: proc.artFilePath };
  }
  const updateArt = inScope({ root, coverArtDownloader: proc }, update.params, update.body);
  root.updateArt = updateArt;
  const pscope = { root, get artFilePath() { return proc.artFilePath; }, get targetFile() { return proc.targetFile; } };
  const onExited = inScope(pscope, "", `return (${exitedExpr});`)();
  return {
    files, shown, root,
    get source() { return source; },
    get running() { return running; },
    play(url) {
      root.artUrl = url;
      root.artFilePath = `/cache/coverart/${createHash("md5").update(url).digest("hex")}`;
      show();   // the source follows the path at once (it reads artFilePath)
      updateArt();   // onArtFilePathChanged
    },
    // the running curl ends: its file is written when it worked, then exited, then a queued run starts
    finish(code) {
      if (!running) throw new Error("no download is running");
      if (code === 0) files.add(running.path);
      running = null;
      onExited(code, 0);
      start();
    },
  };
}

{
  const c = card();
  c.play("https://i.scdn.co/image/one");
  const two = "https://i.scdn.co/image/two";
  c.play(two);
  c.finish(0);   // track one's cover arrives
  check("track one's download ending does not mark track two's cover as fetched", c.source === "",
    `the card loaded ${c.source}`);
  if (c.running) c.finish(0);
  const last = c.shown[c.shown.length - 1];
  check("a track skipped to while the last cover downloaded ends with its own cover, loaded once it is there",
    c.source === c.root.artFilePath && last?.path === c.root.artFilePath && last.there,
    JSON.stringify(c.shown));
}
{
  const c = card();
  c.play("https://i.scdn.co/image/one");
  const first = c.root.artFilePath;
  c.play("https://i.scdn.co/image/two");
  c.play("https://i.scdn.co/image/one");   // and back, before the first download ends
  c.finish(0);
  if (c.running) c.finish(0);
  check("skipping back to the track that was downloading shows its cover", c.source === first && c.shown.every(s => s.there),
    JSON.stringify(c.shown));
}
{
  const c = card();
  c.play("https://i.scdn.co/image/one");
  c.play("file:///home/me/Music/cover.jpg");
  c.finish(0);
  check("a track with a cover on disk shows it, the download running for the last one or not",
    c.source === "file:///home/me/Music/cover.jpg" && !c.running);
}
{
  const c = card();
  c.play("https://i.scdn.co/image/one");
  c.finish(22);   // curl -f on a 404
  check("a cover that failed to download is not shown", c.source === "" && c.shown.length === 0);
}
done();
