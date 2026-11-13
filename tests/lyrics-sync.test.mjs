// Synced lyrics following the song (services/LyricsService.qml): the sync timer's own trigger and buildSlots() under node
// with a player whose position, as Quickshell's MprisPlayer has it, changes only when positionChanged() asks for it, and
// nothing else on screen asking (the desktop's media widget alone). The highlighted line must keep up with the song.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== synced lyrics following the song (LyricsService.qml)");
const src = read("services/LyricsService.qml");
const at = src.indexOf("onTriggered:", src.indexOf("id: syncTimer"));
const open = src.indexOf("{", at);
const tickBody = src.slice(open + 1, matchBrace(src, open));

function play(playing = true) {
  const clock = { t: 0 };
  // the song's real place, and what .position says: the place when it was last asked for
  const player = { isPlaying: playing, asked: 0, positionChanged() { this.asked = clock.t; } };
  Object.defineProperty(player, "position", { get: () => player.asked });
  const lines = [0, 4, 8, 12, 16].map((time, i) => ({ time, text: `line ${i + 1}` }));
  const root = { activePlayer: player, lyricsLines: lines, activeIndex: -1, slots: [], before: 3, after: 3, total: 7 };
  const f = qmlFunction(src, "buildSlots");
  root.buildSlots = inScope({ root }, f.params, f.body);
  const tick = inScope({ root }, "", tickBody);
  // seconds of the song, a tick every 300 ms
  const run = seconds => { for (let n = 0; n < seconds / 0.3; n++) { if (player.isPlaying) clock.t += 0.3; tick(); } };
  return { root, run };
}

{
  const p = play();
  p.run(9);
  check("nine seconds in, the line sung at 8 s is the one lit", p.root.activeIndex === 2, `the lit line is ${p.root.lyricsLines[p.root.activeIndex]?.text ?? "none"}`);
  p.run(8);
  check("and at 17 s the last one", p.root.activeIndex === 4, `the lit line is ${p.root.lyricsLines[p.root.activeIndex]?.text ?? "none"}`);
}
{
  const p = play(false);
  p.run(3);
  check("a paused song stays on its line without asking the player", p.root.activeIndex === 0 && p.root.activePlayer.asked === 0);
}
done();
