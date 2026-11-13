// The notch's sand (native/sand, Tacit.Sand) against the clock: the tree's module built here (gen_shaders.py, CMake) and
// run in a window offscreen on Qt's Null graphics backend, which draws nothing but runs a frame every few milliseconds,
// as a 144 Hz screen does and faster, with the voice coming 20 times a second as Flow sends it. Once listening ends the
// bed is tuned to level for one second before settled(), timed here. Without CMake, Qt's shader tools or the qml tool
// it is not built and says so.
import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the notch's sand against the clock (native/sand/sanditem.cpp)");
const sh = cmd => spawnSync("sh", ["-c", cmd], { encoding: "utf8" });
const qml = "/usr/lib/qt6/bin/qml";
const missing = [sh("command -v cmake").status ? "cmake" : "", existsSync("/usr/lib/qt6/bin/qsb") ? "" : "qsb", existsSync(qml) ? "" : "the qml tool"]
  .filter(Boolean);
if (missing.length) {
  console.log(`  skip  not built here: no ${missing.join(", ")}`);
} else {
  const tmp = mkdtempSync(join(tmpdir(), "tacit-sand-"));
  try {
    const src = join(tree, "native/sand"), b = join(tmp, "build");
    const built = sh(`python3 -I '${src}/gen_shaders.py' '${b}/shaders' >/dev/null && cmake -S '${src}' -B '${b}' ` +
      `${sh("command -v ninja").status ? "" : "-G Ninja"} -DCMAKE_BUILD_TYPE=Release -DQT_NO_PRIVATE_MODULE_WARNING=ON >/dev/null && cmake --build '${b}'`);
    check("the module builds", built.status === 0, (built.stderr || built.stdout).trim().split("\n").slice(-3).join(" | "));
    writeFileSync(join(tmp, "clock.qml"), `import QtQuick
import Tacit.Sand
Window {
    id: w
    width: 150; height: 40; visible: true
    property real startAt: Date.now()
    property real offAt: 0
    property real settledAt: 0
    property int frames: 0
    property int framesAtOff: 0
    onFrameSwapped: frames++
    Sand { id: s; anchors.fill: parent; active: true; onSettled: w.settledAt = Date.now() }
    Timer { interval: 50; repeat: true; running: true; onTriggered: s.mid = s.mid > 0 ? 0 : 0.01 }
    Timer { interval: 1000; running: true; onTriggered: { w.framesAtOff = w.frames; w.offAt = Date.now(); s.active = false; } }
    Timer { interval: 2800; running: true; onTriggered: { console.log(JSON.stringify({ fps: Math.round(w.framesAtOff * 1000 / (w.offAt - w.startAt)),
        settled: w.settledAt ? w.settledAt - w.offAt : -1 })); Qt.quit(); } }
}
`);
    if (built.status === 0) {
      const r = spawnSync("timeout", ["15", qml, join(tmp, "clock.qml")], { encoding: "utf8", env: { ...process.env, QT_QPA_PLATFORM: "offscreen",
        QT_QUICK_BACKEND: "rhi", QSG_RHI_BACKEND: "null", QML_IMPORT_PATH: join(b, "qml"), QT_FORCE_STDERR_LOGGING: "1" } });
      let m = null;
      try { m = JSON.parse(/qml: (\{.*\})/.exec(r.stderr)[1]); } catch {}
      check("it ran", m !== null, r.stderr.trim().split("\n").slice(-3).join(" | "));
      if (m && m.fps < 90) console.log(`  (frames came ${m.fps} a second here, too few to tell a fast screen's pace apart: not judged)`);
      else if (m) check(`at ${m.fps} frames a second the bed levels for its second before it settles`, m.settled >= 900,
        m.settled < 0 ? "it never settled" : `settled ${m.settled} ms after listening ended`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
done();
