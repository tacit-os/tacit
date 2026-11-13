// The volume OSD, the media popup and the equalizer open below the notch however far from the top edge the notch is set
// (Settings > Notch distance, island.topMargin): each one's top, from its own file, is evaluated under node with
// Config.qml's defaults and compared with where the notch's reserved band ends, its exclusiveZone in Island.qml.
import { adapterDefaults, inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the OSD and the media popups under a lowered notch (OnScreenDisplay.qml, MediaControls.qml, EqualizerPopup.qml)");
const island = read("modules/ii/island/Island.qml");
const zone = readExpression(island, island.indexOf("exclusiveZone:") + "exclusiveZone:".length).expr;
const osd = read("modules/ii/onScreenDisplay/OnScreenDisplay.qml");
const osdTop = readExpression(osd, osd.indexOf("top:", osd.indexOf("margins {")) + "top:".length).expr;
const surfaces = {
  "the volume OSD": osdTop,
  "the media popup": qmlProperty(read("modules/ii/mediaControls/MediaControls.qml"), "topReserved"),
  "the equalizer": qmlProperty(read("modules/ii/equalizer/EqualizerPopup.qml"), "topReserved"),
};
for (const topMargin of [40, 0]) {
  const options = adapterDefaults(read("modules/common/Config.qml"));
  options.island.topMargin = topMargin;
  const value = e => inScope({ Config: { options } }, "", `return (${e});`)();
  const end = value(zone);
  for (const [name, e] of Object.entries(surfaces))
    check(`with the notch ${topMargin} px from the top, ${name} starts at ${end}, where the notch's band ends`, value(e) === end, `it starts at ${value(e)}`);
}
done();
