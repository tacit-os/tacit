// Graphis scrolls a long line sideways with two fingers on a touchpad (Discord, Lorenz: a MacBook's trackpad, the window
// tiled beside another, where long lines run past its edge). CodeDoc's text is a Flickable with modules/claude/
// FastWheel.qml in it, which scrolls up and down itself and leaves a sideways wheel to the Flickable. A scene with the
// same Flickable and the tree's own FastWheel.qml is shown offscreen by a small harness (tests/lib/wheel_gesture.cpp,
// built here with g++), which sends it wheel events as Qt's Wayland client makes them: a touchpad's swipe is a
// ScrollBegin, updates with pixel deltas (a sideways one with a pixel or so of up and down in it) and a ScrollEnd; a
// mouse's tilt wheel is plain notches. Without a compiler or Qt's headers it is not built and says so.
import { spawnSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, read } from "./lib/check.mjs";

console.log("== Graphis scrolls sideways with a touchpad (modules/claude/FastWheel.qml in CodeDoc)");
const sh = cmd => spawnSync("sh", ["-c", cmd], { encoding: "utf8" });
const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "wheel_gesture.cpp");
const qt = "Qt6Quick Qt6Qml Qt6Gui Qt6Core";
const doc = read("modules/code/CodeDoc.qml");
check("CodeDoc's text is a Flickable with FastWheel in it", /Flickable \{\s*id: flick[\s\S]*?Praxis\.FastWheel \{ view: flick; ease: true \}/.test(doc));

const missing = [sh("command -v g++").status ? "g++" : "", sh(`pkg-config --exists ${qt}`).status ? "Qt 6's headers" : ""].filter(Boolean);
if (missing.length) {
  console.log(`  skip  not built here: no ${missing.join(", ")}`);
} else {
  const tmp = mkdtempSync(join(tmpdir(), "tacit-sideways-"));
  try {
    const harness = join(tmp, "harness");
    const built = sh(`g++ -std=c++20 -fPIC -O0 $(pkg-config --cflags ${qt}) '${helper}' -o '${harness}' $(pkg-config --libs ${qt})`);
    check("the harness builds", built.status === 0, built.stderr.trim().split("\n").slice(-3).join(" | "));
    const files = {
      "FastWheel.qml": read("modules/claude/FastWheel.qml"),
      "qs/modules/common/qmldir": "module qs.modules.common\nsingleton Config 1.0 Config.qml\nsingleton Appearance 1.0 Appearance.qml\n",
      "qs/modules/common/Config.qml": "pragma Singleton\nimport QtQuick\nQtObject { property var options: ({ interactions: { scrolling: { mouseScrollDeltaThreshold: 120, mouseScrollFactor: 120, touchpadScrollFactor: 450 } } }) }\n",
      "qs/modules/common/Appearance.qml": "pragma Singleton\nimport QtQuick\nQtObject { property var animation: ({ scroll: { duration: 200, type: Easing.OutCubic, bezierCurve: [] } }) }\n",
      // CodeDoc's Flickable as it is for code (no wrapping): a long line wider than the window, a long file
      "scene.qml": `import QtQuick
Item {
    width: 400
    height: 300
    Flickable {
        id: flick
        objectName: "flick"
        anchors.fill: parent
        clip: true
        topMargin: 6
        bottomMargin: height / 2
        contentWidth: Math.max(width, area.contentWidth + 40)
        contentHeight: area.contentHeight
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { view: flick; ease: true }
        TextEdit {
            id: area
            width: Math.max(flick.width, contentWidth)
            wrapMode: TextEdit.NoWrap
            font.pixelSize: 15
            text: Array.from({ length: 200 }, (_, i) => i + " " + "a long line of code ".repeat(8)).join("\\n")
        }
    }
}
`,
    };
    for (const [path, text] of Object.entries(files)) {
      mkdirSync(dirname(join(tmp, path)), { recursive: true });
      writeFileSync(join(tmp, path), text);
    }
    const run = events => {
      const r = spawnSync(harness, [join(tmp, "scene.qml"), tmp, JSON.stringify(events)], { encoding: "utf8", timeout: 30000,
        env: { PATH: process.env.PATH, HOME: tmp, QT_QPA_PLATFORM: "offscreen", QT_LOGGING_RULES: "*.warning=false" } });
      try { return JSON.parse(r.stdout); } catch (e) { return { error: (r.stderr || r.stdout || String(r.error)).trim().split("\n").slice(-2).join(" | ") }; }
    };
    // Qt's phases: 1 ScrollBegin, 2 ScrollUpdate, 3 ScrollEnd, 0 none (a mouse wheel); a touchpad's angle is 12 per pixel
    const swipe = (dx, dy, n = 20) => [[1, false, 0, 0, 0, 0],
      ...Array.from({ length: n }, (_, i) => { const y = typeof dy === "function" ? dy(i) : dy; return [2, true, dx, y, dx * 12, y * 12]; }),
      [3, true, 0, 0, 0, 0]];
    if (built.status === 0) {
      const start = run([]);
      check("the scene runs", start.error === undefined, start.error);
      const sideways = run(swipe(-8, i => (i % 3 === 0 ? 1 : i % 3 === 1 ? -1 : 0)));
      check("a sideways swipe with a little up and down in it scrolls the long line", sideways.x > 100 && Math.abs(sideways.y - start.y) < 20, JSON.stringify(sideways));
      const straight = run(swipe(-8, 0));
      check("a swipe straight sideways scrolls it", straight.x > 100 && straight.y === start.y, JSON.stringify(straight));
      const back = run([...swipe(-8, 0), ...swipe(6, 0)]);
      check("and a second swipe the other way brings it back", back.x >= 0 && back.x < straight.x - 60, JSON.stringify(back));
      const down = run(swipe(0, -8));
      check("a swipe up and down still scrolls the file", down.y > start.y + 100 && down.x === 0, JSON.stringify(down));
      const tilt = run(Array.from({ length: 4 }, () => [0, false, -15, 0, -120, 0]));
      check("a mouse's tilt wheel scrolls sideways too", tilt.x > 50, JSON.stringify(tilt));
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
done();
