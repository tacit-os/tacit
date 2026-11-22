// The notch must not show over a fullscreen game or film, but it must still stack above the bar strip. Riding Overlay
// keeps the stacking; a fullscreen window hides the notch through contentShown (an empty mask, so no unmap and no
// flicker). The one exception is showInFullscreenWhilePlaying with music from a different app. Both the layer and the
// hide expression are read from Island.qml and run under node.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch over the bar and under fullscreen (Island.qml)");
const src = read("modules/ii/island/Island.qml");
const exprAfter = name => {
  const at = src.indexOf(name);
  return readExpression(src, at + name.length).expr;
};
const layer = exprAfter("WlrLayershell.layer:");
const hide = exprAfter("readonly property bool hideForFullscreen:");
let shown = qmlProperty(src, "contentShown");
// contentShown is a readonly property, so qmlProperty above finds it; use the binding directly to be sure.
shown = exprAfter("readonly property bool contentShown:");

check("the notch rides Overlay so it stacks above the bar", /WlrLayer\.Overlay/.test(layer) && !/\?/.test(layer), layer);

const fullscreenWindow = { id: 1 };
function policy({ fullscreen = false, showInFullscreen = true, media = false, playing = false, itsOwnPlayer = false, loaded = true }) {
  const Config = { options: { island: { showInFullscreenWhilePlaying: showInFullscreen } } };
  const scope = {
    fullscreenWindow: fullscreen ? fullscreenWindow : null,
    Config,
    IslandController: { mediaPresent: media },
    MprisController: { isPlaying: playing, playsIn: () => itsOwnPlayer, activePlayer: "player" },
  };
  const overFullscreen = inScope(scope, "", `return (fullscreenWindow !== null && Config.options.island.showInFullscreenWhilePlaying && IslandController.mediaPresent && MprisController.isPlaying && !MprisController.playsIn(fullscreenWindow, MprisController.activePlayer));`)();
  const hidden = inScope({ ...scope, overFullscreen }, "", `return (${hide});`)();
  const visible = inScope({ contentLoader: { item: loaded ? {} : null }, hideForFullscreen: hidden }, "", `return (${shown});`)();
  return { hidden, visible };
}

let p = policy({});
check("with no fullscreen the notch shows", !p.hidden && p.visible, JSON.stringify(p));
p = policy({ fullscreen: true });
check("a fullscreen game hides the notch", p.hidden && !p.visible, JSON.stringify(p));
p = policy({ fullscreen: true, media: true, playing: true });
check("music from another app keeps the notch over fullscreen", !p.hidden && p.visible, JSON.stringify(p));
p = policy({ fullscreen: true, media: true, playing: true, itsOwnPlayer: true });
check("the fullscreen app's own player does not", p.hidden && !p.visible, JSON.stringify(p));
p = policy({ fullscreen: true, showInFullscreen: false, media: true, playing: true });
check("turning the setting off hides it", p.hidden && !p.visible, JSON.stringify(p));
done();
