// A wallpaper smaller than the screen (modules/ii/background/WallpaperImage.qml, with Wallpapers.focusFor and sizeFor from
// services/Wallpapers.qml): the item runs under qmltestrunner offscreen on real pictures smaller than the box (800x450
// into 1920x1080, a tall 400x900), as large and larger (3840x2160), at the middle and the corners, on a 16:10 box and on
// a 1.25 panel (its device pixels larger than the box), and its pixels are read back. Each picture's colour says where
// in it a pixel is (red across, green down, blue 128), so black and a wrong part both show. sizeFor's Process is
// answered with the pictures' sizes here; its Pillow line runs under python3 on the same files.
import { spawnSync } from "child_process";
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { crc32, deflateSync } from "zlib";
import { matchBrace, qmlFunction } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a wallpaper smaller than the screen fills it, at the chosen part (WallpaperImage.qml)");

// an RGB PNG whose red is x across it and green y down it, blue 128
function png(w, h) {
  const row = 1 + w * 3, raw = Buffer.alloc(row * h);
  for (let y = 0; y < h; y++) {
    const g = Math.round(y * 255 / (h - 1));
    for (let x = 0; x < w; x++) raw.set([Math.round(x * 255 / (w - 1)), g, 128], y * row + 1 + x * 3);
  }
  const chunk = (type, data) => {
    const head = Buffer.alloc(8), crc = Buffer.alloc(4);
    head.writeUInt32BE(data.length);
    head.write(type, 4);
    crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])));
    return Buffer.concat([head, data, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr.set([8, 2], 8);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0))]);
}
const sizes = { small: [800, 450], tall: [400, 900], same: [1920, 1080], large: [3840, 2160] };
const pictures = Object.fromEntries(Object.entries(sizes).map(([k, [w, h]]) => [k, png(w, h)]));

// picture, box (the item), view (the device pixels it covers), focus
const fullHd = [1920, 1080], wide = [1920, 1200], panel = { box: [1536, 864], view: fullHd };
const cases = [
  ["small", fullHd, fullHd, [0.5, 0.5]],
  ["tall", fullHd, fullHd, [0.5, 0.5]],
  ["tall", fullHd, fullHd, [0, 0]],
  ["tall", fullHd, fullHd, [1, 1]],
  ["same", fullHd, fullHd, [0.5, 0.5]],
  ["large", fullHd, fullHd, [0.5, 0.5]],
  ["small", wide, wide, [0.5, 0.5]],
  ["small", wide, wide, [0, 0]],
  ["small", wide, wide, [1, 1]],
  ["large", wide, wide, [1, 0]],
  ["small", panel.box, panel.view, [0.5, 0.5]],
  ["tall", panel.box, panel.view, [0.3, 0.8]],
  ["large", panel.box, panel.view, [0.5, 0.5]],
].map(([pic, box, view, focus], i) => ({ pic, box, view, focus, file: `case${i}-${pic}.png` }));
// one item given a large picture, then a small one, then a large one again, as changes of wallpaper do
const switching = [["large", [0.5, 0.5]], ["tall", [0.2, 0.9]], ["large", [0, 1]]]
  .map(([pic, focus], i) => ({ pic, focus, box: wide, view: wide, file: `switch${i}-${pic}.png` }));
const all = [...cases, ...switching];

const wallpapers = read("services/Wallpapers.qml");
// Wallpapers.sizeFor with its cache and Process, as the tree has it (none before this fix: the item never asked)
const sizeBlock = (() => {
  const start = wallpapers.indexOf("property var sizes");
  if (start < 0) return "";
  const proc = objectWith(wallpapers, "id: sizeProc");
  return wallpapers.slice(start, wallpapers.indexOf(proc) + proc.length);
})();
const focusFor = qmlFunction(wallpapers, "focusFor");

const scene = `import QtQuick
import QtCore
import QtTest
Item {
    id: scene
    width: 1920; height: 1200
    readonly property string dir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace("file://", "") + "/"
    // [x, y, r, g, b] at 9 x 9 places, edges included
    function samples(g) {
        const out = [];
        for (let j = 0; j <= 8; j++)
            for (let i = 0; i <= 8; i++) {
                const x = Math.round(i * (g.width - 1) / 8), y = Math.round(j * (g.height - 1) / 8), c = g.pixel(x, y);
                out.push([x, y, Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]);
            }
        return out;
    }
    Repeater {
        id: items
        model: ${JSON.stringify(cases)}
        WallpaperImage {
            required property var modelData
            width: modelData.box[0]; height: modelData.box[1]
            view: Qt.size(modelData.view[0], modelData.view[1])
            target: scene.dir + modelData.file
        }
    }
    WallpaperImage {
        id: switcher
        width: 1920; height: 1200
        view: Qt.size(1920, 1200)
    }
    TestCase {
        name: "wallpaper"; when: windowShown
        // grabImage reads the window where the item is, so it is put above the others first
        function grab(item) {
            item.z = 1;
            const g = grabImage(item);
            item.z = 0;
            return { w: g.width, h: g.height, px: scene.samples(g), decoded: [item.implicitWidth, item.implicitHeight] };
        }
        function test_pixels() {
            const out = [];
            for (let i = 0; i < items.count; i++) {
                const item = items.itemAt(i);
                tryVerify(() => item.loaded, 15000, item.target);
            }
            wait(50);
            for (let i = 0; i < items.count; i++)
                out.push(grab(items.itemAt(i)));
            for (const file of ${JSON.stringify(switching.map(c => c.file))}) {
                switcher.target = scene.dir + file;
                tryVerify(() => switcher.loaded, 15000, switcher.target);
                wait(50);
                out.push(grab(switcher));
            }
            console.log("WALL " + JSON.stringify(out));
        }
    }
}
`;

const answers = Object.fromEntries(all.map(c => [c.file, sizes[c.pic]]));
const files = {
  "tst_wallpaper.qml": scene,
  "WallpaperImage.qml": read("modules/ii/background/WallpaperImage.qml"),
  ...module("qs.services", { Wallpapers: `import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
Item {
    id: root
    function focusFor(${focusFor.params}) {${focusFor.body}}
    ${sizeBlock}
}` }),
  ...module("qs.modules.common", {
    Config: `import QtCore
QtObject {
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace("file://", "")
    function focusMap() {
        const out = {}, given = ${JSON.stringify(Object.fromEntries(all.map(c => [c.file, c.focus])))};
        for (const name in given)
            out[home + "/" + name] = given[name];
        return out;
    }
    property var options: ({ background: { wallpaperFocus: focusMap() } })
}`,
    Appearance: `QtObject {
    property Component instant: Component { NumberAnimation { duration: 0 } }
    property var animation: ({ elementMoveEnter: { numberAnimation: instant } })
}`,
  }),
  ...module("qs.modules.common.widgets", {}, { StyledImage: read("modules/common/widgets/StyledImage.qml").replace(/^import QtQuick\n/, "") }),
  "qs/modules/common/functions/FileUtils.qml": read("modules/common/functions/FileUtils.qml"),
  "qs/modules/common/functions/qmldir": "module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n",
  ...module("Quickshell", {}, { Singleton: "QtObject {}" }),
  // python3 run on the picture named last: its size from the list, as the Pillow line prints it
  ...module("Quickshell.Io", {}, {
    StdioCollector: `QtObject { property string text; signal streamFinished() }`,
    Process: `Item {
    id: p
    property bool running: false
    property QtObject stdout
    property var argv: []
    function exec(command) { p.argv = command; p.running = true; Qt.callLater(p.finish) }
    function finish() {
        const size = (${JSON.stringify(answers)})[String(p.argv[p.argv.length - 1]).split("/").pop()];
        p.stdout.text = size ? size.join(" ") + "\\n" : "0 0\\n";
        p.stdout.streamFinished();
        p.running = false;
    }
}`,
  }),
  ...Object.fromEntries(all.map(c => [c.file, pictures[c.pic]])),
};

// where in the picture the box's pixel (gx, gy) should come from, as PreserveAspectCrop with the focus would place it
function expected(c, gx, gy) {
  const [nw, nh] = sizes[c.pic], [bw, bh] = c.box, [vw, vh] = c.view;
  const s = Math.max(vw / nw, vh / nh);
  const px = ((gx + 0.5) * vw / bw + c.focus[0] * (nw * s - vw)) / s - 0.5;
  const py = ((gy + 0.5) * vh / bh + c.focus[1] * (nh * s - vh)) / s - 0.5;
  const clamp = (v, n) => Math.min(n - 1, Math.max(0, v));
  return [clamp(px, nw) * 255 / (nw - 1), clamp(py, nh) * 255 / (nh - 1)];
}
function judge(c, grab, name) {
  const black = grab.px.filter(([, , , , b]) => Math.abs(b - 128) > 6);
  check(`${name}: every pixel is the picture`, black.length === 0 && grab.w === c.box[0] && grab.h === c.box[1],
    `${black.length} of ${grab.px.length} are not, as ${black.slice(0, 3).map(p => `(${p[0]},${p[1]}) rgb ${p.slice(2).join(" ")}`).join(", ")}; grab ${grab.w}x${grab.h}`);
  // what Qt decoded: a picture larger than the panel never at its own size, a smaller one no larger than itself
  const [nw, nh] = sizes[c.pic], [dw, dh] = grab.decoded;
  if (nw > c.view[0] && nh > c.view[1])
    check(`${name}: decoded at the panel's size, not its own`, dw === c.view[0] && dh === c.view[1], `decoded ${dw}x${dh}`);
  else
    check(`${name}: decoded as a cut of its own pixels`, dw <= nw && dh <= nh, `decoded ${dw}x${dh}`);
  const off = grab.px.map(([x, y, r, g]) => [x, y, r, g, ...expected(c, x, y)]).filter(([, , r, g, er, eg]) => Math.abs(r - er) > 5 || Math.abs(g - eg) > 5);
  check(`${name}: it is the chosen part`, off.length === 0,
    `${off.length} pixels from elsewhere, as ${off.slice(0, 3).map(p => `(${p[0]},${p[1]}) red ${p[2]} green ${p[3]}, wanted ${Math.round(p[4])} ${Math.round(p[5])}`).join("; ")}`);
}

try {
  // Qt's own word on every picture asked for, as it is asked (before a later change cancels it):
  // "adding QQuickPixmapKey("<url>" frame=0 region=... size=w, h)", with no size= when it is asked for whole
  const out = runScene(files, { env: { QT_LOGGING_RULES: "qt.quick.image.debug=true" } });
  const grabs = logged(out, "WALL");
  cases.forEach((c, i) => judge(c, grabs[i],
    `${sizes[c.pic].join("x")} in a ${c.box.join("x")} box${c.view[0] !== c.box[0] ? ` of ${c.view.join("x")} panel pixels` : ""} at ${c.focus.join(",")}`));
  switching.forEach((c, i) => judge(c, grabs[cases.length + i],
    `one item's ${["first", "second", "third"][i]} picture, ${sizes[c.pic].join("x")} at ${c.focus.join(",")}`));
  const asked = out.split("\n").filter(l => l.includes("adding QQuickPixmapKey(")).map(l => l.slice(l.indexOf("QQuickPixmapKey(")));
  const whole = asked.filter(l => /-large\.png"/.test(l) && !l.includes(" size="));
  check("Qt's log has the pictures asked for", asked.length >= all.length, `${asked.length} lines`);
  check("a 3840x2160 picture is never asked for whole, not even between two pictures", whole.length === 0, whole.slice(0, 2).join(" | "));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}

// the Pillow line sizeFor runs, as it is in the tree, on a picture, a file that is none, and a name a shell would read
if (!sizeBlock) {
  check("Wallpapers.sizeFor reads a picture's size", false, "services/Wallpapers.qml has no sizeFor");
} else if (spawnSync("python3", ["-I", "-c", "import PIL"]).status !== 0) {
  console.log("  skip  no Pillow for python3 here (a dependency of the shell): its size line was not run");
} else {
  const at = sizeBlock.indexOf("[", sizeBlock.indexOf("sizeProc.exec("));
  const argv = [...sizeBlock.slice(at, matchBrace(sizeBlock, at)).matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m => JSON.parse(`"${m[1]}"`));
  const dir = mkdtempSync(join(tmpdir(), "tacit-sizes-"));
  try {
    const size = file => spawnSync(argv[0], [...argv.slice(1), file], { encoding: "utf8" }).stdout.trim();
    writeFileSync(join(dir, "tall.png"), pictures.tall);
    writeFileSync(join(dir, "it's $(touch x).png"), pictures.small);
    writeFileSync(join(dir, "notes.png"), "not a picture");
    check("a picture's size is read from its header", size(join(dir, "tall.png")) === "400 900", size(join(dir, "tall.png")));
    check("a name with a quote and $( ) is read as a name", size(join(dir, "it's $(touch x).png")) === "800 450", size(join(dir, "it's $(touch x).png")));
    check("a file that is no picture reads 0 0", size(join(dir, "notes.png")) === "0 0", size(join(dir, "notes.png")));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
done();
