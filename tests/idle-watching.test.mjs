// What keeps the screen awake on its own (services/Idle.qml): `watching`, with MprisController's own playsIn(), run
// under node on pretend players and windows. A fullscreen window playing counts; the window in front counts only when
// its player reports no album, a video; music, in front or behind, does not.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== what keeps the screen awake (Idle.qml)");
const src = read("services/Idle.qml");
const mpris = read("services/MprisController.qml");
const plays = qmlFunction(mpris, "playsIn");
const expr = qmlProperty(src, "watching");

const spotify = { class: "spotify", address: "0x1", pid: 40, fullscreen: 0 };
const browser = { class: "browser-cef", address: "0x2", pid: 41, fullscreen: 0 };
const song = { desktopEntry: "spotify", identity: "Spotify", isPlaying: true, trackAlbum: "Discovery" };
const tab = album => ({ desktopEntry: "", identity: "Chromium", dbusName: "org.mpris.MediaPlayer2.chromium.instance41", isPlaying: true, trackAlbum: album });

function watching({ players, windows, focused, locked = false }) {
  const MprisController = { players };
  MprisController.playsIn = inScope({ root: MprisController }, plays.params, plays.body);
  const scope = { root: { focusedWindow: focused ?? null }, GlobalStates: { screenLocked: locked }, HyprlandData: { windowList: windows }, MprisController };
  return inScope(scope, "", expr.slice(1, -1))();
}

check("music playing in the window in front does not keep the screen awake",
  watching({ players: [song], windows: [spotify, browser], focused: spotify }) === false);
check("nor a music tab in the browser in front (YouTube Music names the album)",
  watching({ players: [tab("Random Access Memories")], windows: [spotify, browser], focused: browser }) === false);
check("a video in the window in front does (its player names no album)",
  watching({ players: [tab("")], windows: [spotify, browser], focused: browser }) === true);
check("a fullscreen window playing always does, album or not",
  watching({ players: [{ ...song }], windows: [{ ...spotify, fullscreen: 2 }, browser], focused: browser }) === true
  && watching({ players: [tab("")], windows: [spotify, { ...browser, fullscreen: 2 }], focused: spotify }) === true);
check("a video playing behind other work does not",
  watching({ players: [tab("")], windows: [spotify, browser], focused: spotify }) === false);
check("a paused video in front does not",
  watching({ players: [{ ...tab(""), isPlaying: false }], windows: [browser], focused: browser }) === false);
check("nothing does while the screen is locked",
  watching({ players: [tab("")], windows: [{ ...browser, fullscreen: 2 }], focused: browser, locked: true }) === false);
done();
