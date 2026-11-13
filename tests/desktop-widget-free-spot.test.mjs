// A desktop widget switched on lands at the next free spot, not on its saved one under a widget already shown (every
// widget's saved spot starts at 400,100): Background.qml's switchedOn handler, AbstractBackgroundWidget.qml's
// Component.onCompleted under node, and takeFreeSpot() with WidgetCanvas.qml's rectsIntersect() under Qt's qml tool
// offscreen, on a 1920 x 1080 desktop with stand-in widgets.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a widget switched on takes the next free spot (Background.qml, AbstractBackgroundWidget.qml)");
const widget = read("modules/ii/background/widgets/AbstractBackgroundWidget.qml");
const background = read("modules/ii/background/Background.qml");
const intersect = qmlFunction(read("modules/common/widgets/widgetCanvas/WidgetCanvas.qml"), "rectsIntersect");
const box = (x, y, width, height) => ({ x, y, width, height, visible: true, enabled: true });

// takeFreeSpot() runs under Qt's qml tool offscreen, so the script engine is the one the desktop runs it in
const f = qmlFunction(widget, "takeFreeSpot");
check("AbstractBackgroundWidget has takeFreeSpot()", f !== null);
if (f) {
  const weather = box(400, 100, 360, 200), clock = box(784, 100, 300, 150);
  const cases = [
    ["the clock switched on over the weather lands to its right, 24 px on", box(400, 100, 300, 150), [weather], "free", [784, 100]],
    ["a third over both lands right of the clock, the first free spot in reading order", box(400, 100, 320, 200), [weather, clock], "free", [1108, 100]],
    ["the first widget on keeps its spot", box(400, 100, 300, 150), [], "free", [400, 100]],
    ["one whose saved spot is clear keeps it", box(1200, 600, 300, 150), [weather], "free", [1200, 600]],
    ["a widget not shown (hidden at the lock) does not count", box(400, 100, 300, 150), [{ ...weather, visible: false }], "free", [400, 100]],
    ["with no free spot big enough it stays where it was", box(400, 100, 1500, 900), [weather], "free", [400, 100]],
    ["one placed by the wallpaper (not free) is left to that", box(400, 100, 300, 150), [weather], "leastBusy", [400, 100]],
  ];
  const scene = `import QtQuick
Item {
    function rectsIntersect(${intersect.params}) {${intersect.body}}
    function take(me, others, strategy) {
        const root = Object.assign({}, me, { targetX: me.x, targetY: me.y, placementStrategy: strategy,
            scaledScreenWidth: 1920, scaledScreenHeight: 1080, configEntry: { x: me.x, y: me.y } })
        root.registeredCanvas = { registeredWidgets: others.concat([root]), rectsIntersect: rectsIntersect }
        ;(function (root) {${f.body}})(root)
        return [root.configEntry.x, root.configEntry.y]
    }
    Component.onCompleted: {
        const out = []
        try { for (const c of ${JSON.stringify(cases.map(c => c.slice(1, 4)))}) out.push(take(c[0], c[1], c[2])) } catch (e) { out.push(String(e)) }
        console.log("SPOTS " + JSON.stringify(out))
        Qt.quit()
    }
}
`;
  try {
    const got = logged(runScene({ "spots.qml": scene }), "SPOTS");
    cases.forEach(([name, , , , want], i) => check(`${name}: ${want}`, JSON.stringify(got[i]) === JSON.stringify(want), JSON.stringify(got[i])));
  } catch (e) {
    check("the scene ran", false, String(e.message ?? e));
  }
}

// Background.qml's own Instantiator under Qt with a stand-in Config: a switch noted only once the settings are read
const inst = background.indexOf("Instantiator {", background.indexOf("property var switchedOn"));
check("Background.qml has the Instantiator that notes the switches", inst >= 0);
if (inst >= 0) {
  const keys = ["visualizer", "customImage", "calendar", "weather", "clock", "notes", "media", "images", "resources", "worldClock", "userCard", "todo", "timers"];
  const config = `QtObject {
    property bool ready: false
    property QtObject options: QtObject { property QtObject background: QtObject { property QtObject widgets: QtObject {
        ${keys.map(k => `property QtObject ${k}: QtObject { property bool enable: false }`).join("\n        ")}
    } } }
}`;
  const scene = `pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
Item {
    id: widgetCanvas
    property var switchedOn: ({})
    ${background.slice(inst, matchBrace(background, background.indexOf("{", inst)) + 1)}
    Component.onCompleted: {
        Config.options.background.widgets.weather.enable = true
        const atStart = JSON.stringify(switchedOn)
        Config.ready = true
        Config.options.background.widgets.clock.enable = true
        Config.options.background.widgets.timers.enable = true
        Config.options.background.widgets.timers.enable = false
        console.log("NOTED " + JSON.stringify([atStart, switchedOn]))
        Qt.quit()
    }
}
`;
  try {
    const [atStart, noted] = logged(runScene({ "noted.qml": scene, ...module("qs.modules.common", { Config: config }) }), "NOTED");
    check("the weather read on with the settings is not noted", !JSON.parse(atStart).weather && !noted.weather, `${atStart}, then ${JSON.stringify(noted)}`);
    check("the clock switched on after is, and the timers switched on and off again are not", noted.clock === true && noted.timers === false,
      JSON.stringify(noted));
  } catch (e) {
    check("the scene ran", false, String(e.message ?? e));
  }
}

// only a switch made while the desktop runs, not the file read at the start
const handler = /function onEnableChanged\(\)\s*\{([^\n]*)\}/.exec(background);
check("Background.qml notes each widget switched on", handler !== null);
if (handler) {
  const note = (ready, enable) => {
    const widgetCanvas = { switchedOn: {} };
    inScope({ widgetCanvas, Config: { ready }, target: { enable }, modelData: "clock" }, "", handler[1])();
    return widgetCanvas.switchedOn.clock;
  };
  check("a switch turned on once the settings are read is noted", note(true, true) === true);
  check("one read with the settings at the start, or turned off, is not", note(false, true) === false && note(true, false) === false);
}
const at = widget.indexOf("Component.onCompleted:");
check("the widget looks for a spot as it comes", at >= 0);
if (at >= 0) {
  const done_ = readExpression(widget, at + "Component.onCompleted:".length).expr;
  const comes = noted => {
    const canvas = { switchedOn: { clock: noted } }, later = [];
    const root = { configEntryName: "clock", parent: {}, findCanvas: () => canvas, takeFreeSpot: () => {} };
    inScope({ root, Qt: { callLater: f => later.push(f) } }, "", done_.startsWith("{") ? done_.slice(1, -1) : done_)();
    return { looked: later.includes(root.takeFreeSpot), left: canvas.switchedOn.clock };
  };
  const on = comes(true), loaded = comes(false);
  check("one switched on looks for a free spot once it has a size, and only once", on.looked && on.left === false, JSON.stringify(on));
  check("one loaded with the desktop stays where it was saved", !loaded.looked, JSON.stringify(loaded));
}
done();
