// The volume OSD, the media popup and the equalizer open below the notch however far from the top edge the notch is set
// (Settings > Notch distance, island.topMargin), and the control panel grows no higher than that: each one's top, from its
// own file, is evaluated under node with Config.qml's defaults on a 1080 px screen and compared with where the notch's
// reserved band ends, its exclusiveZone in Island.qml.
import { adapterDefaults, inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the OSD, the media popups and the control panel under a lowered notch (OnScreenDisplay.qml, MediaControls.qml, EqualizerPopup.qml, SidebarRight.qml)");
const island = read("modules/ii/island/Island.qml");
const zone = readExpression(island, island.indexOf("exclusiveZone:") + "exclusiveZone:".length).expr;
const osd = read("modules/ii/onScreenDisplay/OnScreenDisplay.qml");
const osdTop = readExpression(osd, osd.indexOf("top:", osd.indexOf("margins {")) + "top:".length).expr;
// the control panel's window is as tall as it may ever be, bottom-anchored: its top is the screen less that height
const sidebar = read("modules/ii/sidebarRight/SidebarRight.qml");
// (its binding goes on to a second line, which readExpression does not follow)
const cove = qmlProperty(sidebar, "cove");
const maxHeight = /panelMaxHeight:\s*([\s\S]*?)\n\s*\/\//.exec(sidebar)[1];
const panelTop = `1080 - (${maxHeight.replace(/\bscreen\?\.height/g, "1080").replace(/\bcove\b/g, cove)} + ${cove})`;
const surfaces = {
  "the volume OSD": osdTop,
  "the media popup": qmlProperty(read("modules/ii/mediaControls/MediaControls.qml"), "topReserved"),
  "the equalizer": qmlProperty(read("modules/ii/equalizer/EqualizerPopup.qml"), "topReserved"),
  "the control panel's tallest": panelTop,
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
