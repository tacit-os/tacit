// The notch must not show over a fullscreen game or film, but must still sit above the bar strip. It rides Top, which
// Hyprland buries under fullscreen, and switches to Overlay only for the deliberate showInFullscreenWhilePlaying case
// with music from a different app. On Top, the panel family loads the bar after the notch so the notch stacks above
// the strip. All of this is read from Island.qml / the panel family and run under node.
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch over the bar and under fullscreen (Island.qml, panel family)");
const src = read("modules/ii/island/Island.qml");
const after = name => readExpression(src, src.indexOf(name) + name.length).expr;
const layer = after("WlrLayershell.layer:");
const overFullscreenExpr = after("readonly property bool overFullscreen:");
const family = read("panelFamilies/IllogicalImpulseFamily.qml");
const islandAt = family.indexOf("component: Island {}");
const barAt = family.indexOf("component: NewBar {}");

check("the notch rides Top, switching to Overlay only for the media case", /overFullscreen\s*\?\s*WlrLayer\.Overlay\s*:\s*WlrLayer\.Top/.test(layer), layer);
check("the bar loads after the notch so the notch stacks above it", islandAt > 0 && barAt > islandAt, `island@${islandAt} bar@${barAt}`);

const fullscreenWindow = { id: 1 };
function overFullscreen({ fullscreen = false, showInFullscreen = true, media = false, playing = false, itsOwnPlayer = false }) {
  const Config = { options: { island: { showInFullscreenWhilePlaying: showInFullscreen } } };
  const scope = {
    fullscreenWindow: fullscreen ? fullscreenWindow : null,
    Config,
    IslandController: { mediaPresent: media },
    MprisController: { isPlaying: playing, playsIn: () => itsOwnPlayer, activePlayer: "player" },
  };
  return inScope(scope, "", `return (${overFullscreenExpr});`)();
}
const layerFor = over => inScope({ overFullscreen: over, WlrLayer: { Overlay: "Overlay", Top: "Top" } }, "", `return (${layer});`)();

let over = overFullscreen({});
check("with no fullscreen the notch stays on Top and shows", !over && layerFor(over) === "Top");
over = overFullscreen({ fullscreen: true });
check("a fullscreen game keeps the notch on Top, buried", !over && layerFor(over) === "Top");
over = overFullscreen({ fullscreen: true, media: true, playing: true });
check("music from another app lifts the notch to Overlay", over && layerFor(over) === "Overlay");
over = overFullscreen({ fullscreen: true, media: true, playing: true, itsOwnPlayer: true });
check("the fullscreen app's own player does not", !over && layerFor(over) === "Top");
over = overFullscreen({ fullscreen: true, showInFullscreen: false, media: true, playing: true });
check("turning the setting off does not", !over && layerFor(over) === "Top");
done();
