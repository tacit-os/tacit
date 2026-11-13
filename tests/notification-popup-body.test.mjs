// A notification pop-up's message before any click (modules/common/widgets/NotificationGroup.qml and NotificationItem.qml
// with NotificationUtils.qml): the tree's own files under Qt's qml tool offscreen, at the pop-up's width, beside stand-ins
// for the services. A row is read as a person sees it: a text counts only when it is in view, whole, inside the row's
// clipped height. A body that began with a picture showed the picture's top and none of the words.
import { deflateSync } from "zlib";
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the message in a notification pop-up, before a click (NotificationItem.qml)");
// ScriptModel is Quickshell's (not loadable under qml): its values as a plain array model, which gives the same modelData
const plainModel = s => s.replace(/model:\s*ScriptModel\s*\{\s*values:\s*([\s\S]*?)\n\s*\}/g, (m, e) => `model: ${e}`);
const anim = `QtObject { property int duration: 0; property int type: Easing.Linear; property var bezierCurve: []; property Component numberAnimation: Component { NumberAnimation { duration: 0 } } }`;
// the pop-up's row width: the panel's width less its padding (NotificationPopup.qml)
const width = Number(/notificationPopupWidth:\s*(\d+)/.exec(read("modules/common/Appearance.qml"))[1])
  - 2 * Number(/readonly property int pad:\s*(\d+)/.exec(read("modules/ii/notificationPopup/NotificationPopup.qml"))[1]);
const files = {
  "scene.qml": "",
  "widgets/NotificationGroup.qml": plainModel(read("modules/common/widgets/NotificationGroup.qml")),
  "widgets/NotificationItem.qml": plainModel(read("modules/common/widgets/NotificationItem.qml")),
  "widgets/StyledText.qml": `import QtQuick\nText { verticalAlignment: Text.AlignVCenter; font.pixelSize: 16 }`,
  "widgets/StyledListView.qml": `import QtQuick\nListView {}`,
  "widgets/StyledFlickable.qml": `import QtQuick\nFlickable {}`,
  "widgets/ScrollEdgeFade.qml": `import QtQuick\nItem { property var target; property bool vertical }`,
  "widgets/PointingHandLinkHover.qml": `import QtQuick\nItem {}`,
  "widgets/StyledToolTip.qml": `import QtQuick\nItem { property string text }`,
  "widgets/MaterialSymbol.qml": `import QtQuick\nText { property real iconSize }`,
  "widgets/NotificationAppIcon.qml": `import QtQuick\nItem { implicitWidth: 38; implicitHeight: 38; property var appIcon; property var summary; property var urgency; property var image; property bool message; property string appName; property string iconKind; property string glyph }`,
  "widgets/NotificationGroupExpandButton.qml": `import QtQuick\nItem { implicitWidth: 24; implicitHeight: 20; property int count; property bool expanded; property real fontSize; property var altAction; signal clicked() }`,
  "widgets/NotificationActionButton.qml": `import QtQuick\nimport QtQuick.Controls\nButton { property string buttonText; property string tip; property string urgency; text: buttonText; implicitHeight: 26 }`,
  "widgets/ToolbarTextField.qml": `import QtQuick\nimport QtQuick.Controls\nTextField { property color colBackground; property real radius }`,
  "widgets/DragManager.qml": `import QtQuick\nMouseArea { property bool interactive; property bool automaticallyReset; property real dragDiffX; property bool dragging; signal dragReleased(real x, real y); function resetDrag() {} }`,
  "qs/modules/common/functions/qmldir": "module qs.modules.common.functions\nsingleton NotificationUtils 1.0 NotificationUtils.qml\nsingleton ColorUtils 1.0 ColorUtils.qml\n",
  "qs/modules/common/functions/NotificationUtils.qml": read("modules/common/functions/NotificationUtils.qml"),
  "qs/modules/common/functions/ColorUtils.qml": `pragma Singleton\nimport QtQuick\nQtObject { function mix(a, b, t) { return a } function transparentize(c, t) { return c } }`,
  ...module("qs", { GlobalStates: `QtObject { property bool notificationCenterOpen: false }` }),
  ...module("qs.services", {
    Translation: `QtObject { function tr(s) { return s } }`,
    Notifications: `QtObject { signal expandRequested(string appName); property var appGlyphs: ({}); property var invoked: []
      function cancelTimeout(id) {} function discardNotification(id) {} function attemptInvokeAction(id, a) { invoked = invoked.concat([a]) }
      function open(n) { return false } function bumpExpanding() {} function fileFor(n) { return "" } function linkFor(n) { return "" }
      function windowFor(n) { return null } function isMuted(a) { return false } function toggleMute(a) {} function focusApp(n) {}
      function openLink(l) {} function revealFile(f) {} }`,
  }),
  ...module("qs.modules.common", { Appearance: `QtObject {
      property QtObject font: QtObject { property QtObject pixelSize: QtObject { property int small: 16; property int smaller: 13; property int larger: 19 } }
      property QtObject colors: QtObject { property color colError: "red"; property color colLayer0Border: "grey"; property color colLayer2: "#222"; property color colLayer3: "#333"; property color colLayer4: "#444"; property color colOnLayer2: "white"; property color colOnLayer3: "white"; property color colSecondaryContainer: "#555"; property color colSubtext: "#aaa" }
      property QtObject m3colors: QtObject { property color m3onSurface: "white"; property color m3onSurfaceVariant: "#ccc" }
      property QtObject rounding: QtObject { property int small: 8; property int normal: 12 }
      property QtObject animation: QtObject { property QtObject elementMove: ${anim}; property QtObject elementMoveSmall: ${anim}; property QtObject elementMoveFast: ${anim} }
      property QtObject animationCurves: QtObject { property var expressiveFastSpatial: [] } }` }),
  ...module("Quickshell", { Quickshell: `QtObject { property string clipboardText }` }, { Singleton: `QtObject {}` }),
  ...module("Quickshell.Services.Notifications", {}, { NotificationUrgency: `QtObject { enum Urgency { Low, Normal, Critical } }` }),
};

// a sender's picture as a page sends it in the body (Chromium's <img>, which the server says it takes)
const png = (() => {
  const crc = b => { let c = ~0; for (const x of b) { c ^= x; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); } return ~c >>> 0; };
  const chunk = (t, d) => { const b = Buffer.concat([Buffer.from(t), d]); const out = Buffer.alloc(12 + d.length); out.writeUInt32BE(d.length); b.copy(out, 4); out.writeUInt32BE(crc(b), 8 + d.length); return out; };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(200); ihdr.writeUInt32BE(200, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.alloc(200 * 601, 0x60);
  for (let y = 0; y < 200; y++) raw[y * 601] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
})();
files["ana.png"] = png;

const words = "are you coming tonight?";
const chrome = { summary: "Ana", appName: "Google Chrome", appIcon: "google-chrome", image: "/tmp/ana-avatar.png",
  body: `<a href="https://web.whatsapp.com/">web.whatsapp.com</a>\n\n${words}\n`,
  actions: [{ identifier: "default", text: "Activate" }, { identifier: "settings", text: "Settings" }] };
const rows = [
  { what: "WhatsApp from Chrome (its site's link first, Activate and Settings)", n: chrome },
  { what: "WhatsApp from a page that names no browser (the site's link kept)", n: { ...chrome, appName: "Thyris", actions: [] } },
  { what: "a chat app's own notification", n: { summary: "Ana", appName: "WhatsApp", appIcon: "whatsapp", body: words } },
  { what: "the sender's picture first in the body, then the message", n: { summary: "Ana", appName: "Chromium", appIcon: "chromium", body: `<img src="PICTURE" alt=""/>\n${words}` } },
  { what: "two messages from one app, stacked", many: [{ summary: "Ben", appName: "WhatsApp", body: "see you at 8" }, { summary: "Ana", appName: "WhatsApp", body: `<img src="PICTURE" alt=""/>\n${words}` }] },
  { what: "no body", n: { summary: "Ana is calling", appName: "WhatsApp", body: "" } },
];

files["scene.qml"] = `import QtQuick
import qs.services
import "widgets"
Item {
    width: ${width}; height: 800
    property var rows: ${JSON.stringify(rows.map(r => r.many ?? [r.n]))}
    property int at: 0
    property var out: []
    Loader { id: loader; width: ${width} }
    // the texts a person sees in the row: shown, not faded out, and whole inside the row's clipped height
    function seen(row) {
        const r = [];
        const walk = (it, op) => {
            if (!it || !it.visible) return;
            const o = op * it.opacity;
            if (typeof it.text === "string" && it.text.length > 0 && o > 0.01 && it.width > 0 && it.height > 0 && it.lineCount !== undefined) {
                const p = it.mapToItem(row, 0, 0);
                r.push({ text: it.text.replace(/<style>[^<]*<\\/style>/, ""), whole: p.y >= 0 && p.y + it.height <= row.height + 0.5, h: Math.round(it.height) });
            }
            for (let i = 0; i < it.children.length; i++) walk(it.children[i], o);
        };
        walk(row, 1);
        return r;
    }
    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            if (loader.item) {
                const g = loader.item;
                const before = { expanded: g.expanded, height: Math.round(g.height), texts: seen(g) };
                Notifications.invoked = [];
                g.activate();   // the row's left click
                out = out.concat([Object.assign(before, { clicked: Notifications.invoked, after: g.expanded })]);
            }
            if (at === rows.length) { console.log("ROWS " + JSON.stringify(out)); Qt.quit(); return; }
            const ns = rows[at].map((m, k) => Object.assign({ notificationId: at * 10 + k, summary: "", body: "", appName: "", appIcon: "", image: "", iconKind: "",
                urgency: "1", actions: [], hasInlineReply: false, time: Date.now(), popup: true, leaving: false, timer: null, category: "",
                inlineReplyPlaceholder: "", replyActive: false }, m, { body: (m.body ?? "").replace("PICTURE", Qt.resolvedUrl("ana.png")) }));
            at++;
            loader.sourceComponent = null;
            loader.setSource("widgets/NotificationGroup.qml", { popup: true, width: ${width},
                notificationGroup: { appName: ns[0].appName, appIcon: ns[0].appIcon, time: ns[0].time, notifications: ns } });
        }
    }
}
`;

const plain = t => t.replace(/<br\s*\/?>/g, "\n").replace(/<[^>]+>/g, "");
let seen = null;
try { seen = logged(runScene(files), "ROWS"); } catch (e) { check("the pop-up's row ran under Qt", false, String(e.message ?? e)); }
if (seen) {
  const shows = (row, text) => row.texts.some(t => t.whole && plain(t.text).includes(text));
  const say = row => row.texts.map(t => `${JSON.stringify(plain(t.text).slice(0, 60))}${t.whole ? "" : ` (cut, ${t.h} px in a ${row.height} px row)`}`).join(", ");
  rows.forEach((r, i) => {
    const row = seen[i];
    if (r.n?.body === "") {
      check(`${r.what}: its summary, as before`, shows(row, r.n.summary), say(row));
      return;
    }
    for (const n of r.many ?? [r.n]) {
      const message = n.summary === "Ben" ? "see you at 8" : words;
      check(`${r.what}: "${n.summary}" and "${message}", without a click`, shows(row, n.summary) && shows(row, message), say(row));
    }
  });
  // the click is as it was: an action to take is taken; a stack opens
  check("a click on Chrome's row still takes its default action", JSON.stringify(seen[0].clicked) === '["default"]', JSON.stringify(seen[0].clicked));
  check("a click on a stack still opens it", seen[4].expanded === false && seen[4].after === true, `${seen[4].expanded} -> ${seen[4].after}`);
}
done();
