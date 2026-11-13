// The notch never shows notifications (the owner, 2026-11-13): Settings has no switch for it, and a file that saved one
// on from before 1.2.15 gets Settings > Notifications' two pop-up rows (how long, where) as everyone does, with no line
// sending them to the notch and no second corner row in Notch > Advanced. The rows' visible, current and run bindings
// (tacit-settings.qml) go under node with Config's own defaults and a saved file read as its JsonAdapter reads one (the
// keys it declares, nothing else). Notch > Advanced still opens in view from "notch:advanced": the page's own anchor
// handling runs under qmltestrunner offscreen, in a Flickable and Qt Layouts as Settings has them, with stand-in rows
// of the real rows' heights (48 px, 62 with a description).
import { adapterDefaults, inScope, loadInto, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the pop-up rows, with the notch's notifications saved on and off (tacit-settings.qml)");
const src = read("tacit-settings.qml");
// the objects directly inside a block, with their type
function children(block) {
  const out = [], body = block.indexOf("{") + 1;
  for (let i = body, depth = 0; i < block.length - 1; i++) {
    if (block[i] === "{") {
      if (depth === 0) {
        const m = /(\w+)\s*$/.exec(block.slice(body, i));
        if (m && /^[A-Z]/.test(m[1])) out.push({ type: m[1], text: block.slice(body + m.index, matchBrace(block, i) + 1) });
      }
      depth++;
    } else if (block[i] === "}") depth--;
  }
  return out;
}
const expr = (block, name) => {
  const m = new RegExp(`\\n\\s*${name}:`).exec(block);
  return m ? readExpression(block, m.index + m[0].length).expr : null;
};
const label = row => (/label:\s*"([^"]*)"/.exec(row) ?? [])[1];

const defaults = adapterDefaults(read("modules/common/Config.qml"));
for (const saved of [true, false]) {
  const options = loadInto(defaults, { island: { enable: true, states: { notification: saved } }, notifications: { position: "bottom" } });
  const Config = { options };
  const root = { pages: [], showPage: p => root.pages.push(p) };
  for (const name of ["notificationCorners", "notificationCorner", "notchShowsNotifications"]) {
    const e = qmlProperty(src, name);
    if (e) root[name] = inScope({ Config, root }, "", `return (${e});`)();
  }
  const value = e => (e === null ? true : inScope({ Config, root }, "", `return (${e});`)());
  const rows = children(objectWith(src, 'title: "Pop-ups"'));
  const words = rows.filter(r => value(expr(r.text, "visible"))).map(r => label(r.text));
  check(`notifications in the notch saved ${saved ? "on" : "off"}: Pop-ups has its two rows`,
    JSON.stringify(words) === '["How long a pop-up stays","Where pop-ups appear"]', JSON.stringify(words));
  const corner = rows.find(r => label(r.text) === "Where pop-ups appear");
  if (corner) {
    check("with the six corners, an old \"bottom\" read as bottom right",
      value(expr(corner.text, "options")).length === 6 && value(expr(corner.text, "current")) === "bottom_right", value(expr(corner.text, "current")));
    value(expr(corner.text, "onPicked"))("top_left");
    check("and picking one sets where notifications open", Config.options.notifications.position === "top_left");
  }
}
check("no line sends the pop-ups to the notch", !src.includes("Notifications show in the notch"));
{
  const notchPage = objectWith(src, "id: notchPage"), advAt = notchPage.indexOf("Advanced {");
  const advanced = children(notchPage.slice(advAt, matchBrace(notchPage, notchPage.indexOf("{", advAt)) + 1));
  const corners = advanced.filter(r => (expr(r.text, "onPicked") ?? "").includes("notifications.position"));
  check("Notch › Advanced has no second corner row", corners.length === 0, `${corners.length} such rows`);
  const held = advanced.filter(r => /hold\.notification/.test(r.text)).map(r => label(r.text));
  check("nor a time a notification is held in the notch", held.length === 0, JSON.stringify(held));
  const tells = children(objectWith(notchPage, 'title: "What it tells you about"'));
  const switches = tells.filter(r => /states\.notification/.test(r.text)).map(r => label(r.text));
  check("Notch › What it tells you about has no Notifications switch", switches.length === 0, JSON.stringify(switches));
  const keys = inScope({}, "", `return (${readExpression(notchPage, notchPage.indexOf("tellKeys:") + "tellKeys:".length).expr});`)();
  check("and its count leaves notifications out", !keys.includes("notification"), JSON.stringify(keys));
}
// notch:advanced, to the end: Advanced's last row in view once the page has laid out
{
  const nt = objectWith(src, "id: notchPage");
  const fn = (block, name) => { const f = qmlFunction(block, name); return f ? `function ${name}(${f.params}) {${f.body}}` : ""; };
  const piece = (block, marker) => { try { return objectWith(block, marker); } catch (e) { return ""; } };
  // what the tree has of it; release-1.2.15 runs here too, with its takeAnchor alone
  const pieces = [(nt.match(/\n\s*property bool toAdvanced[^\n]*/) ?? [""])[0], fn(nt, "takeAnchor"), fn(nt, "showAdvanced"),
    (nt.match(/\n\s*onImplicitHeightChanged:[^\n]*/) ?? [""])[0], piece(nt, "id: toAdvancedEnd"), piece(nt, "function onMovementStarted()"),
    "Component.onCompleted: nt.takeAnchor(root.pageAnchor)"].join("\n");
  const scene = `import QtQuick
import QtQuick.Layouts
import QtTest
import qs.services
TestCase {
    id: root
    name: "NotchAdvanced"
    when: windowShown
    // a TestCase is not shown itself, and a layout leaves out what is not shown
    visible: true
    width: 1120
    height: 780
    property string pageAnchor: ""
    property int current: 0
    readonly property var categories: [{ key: "notifications" }, { key: "notch" }]
    signal anchorAsked(string anchor)
    // a page switch starts at the top of the scroll (revealPage)
    onCurrentChanged: pageScroll.contentY = 0
    ${fn(src, "showPage")}
    component Rows: ColumnLayout {
        property int rows: 0
        Layout.fillWidth: true
        Layout.topMargin: 24
        spacing: 0
        Repeater { model: rows; Item { implicitHeight: 48; Layout.fillWidth: true } }
    }
    Flickable {
        id: pageScroll
        y: 12
        width: 800
        height: parent.height - y
        contentHeight: pageColumn.implicitHeight + 28
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: pageColumn
            width: pageScroll.width
            Item { implicitHeight: 90 }
            Loader {
                id: pageLoader
                Layout.fillWidth: true
                Layout.topMargin: 10
                sourceComponent: root.current === 1 ? notchPage : otherPage
            }
        }
    }
    Component { id: otherPage; ColumnLayout { Item { implicitHeight: 1400 } } }
    Component {
        id: notchPage
        ColumnLayout {
            id: nt
            spacing: 0
            property string viewing: ""
            ${pieces}
            Rows { rows: 4 }
            Rows { rows: 3 }
            // Advanced.qml's shape: its line, then its rows while open
            ColumnLayout {
                id: notchAdvanced
                property bool open: false
                visible: nt.viewing === ""
                Layout.fillWidth: true
                Layout.topMargin: 40
                spacing: 0
                Item { implicitHeight: 32 }
                ColumnLayout {
                    visible: notchAdvanced.open
                    Layout.topMargin: 6
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater { model: 3; Item { implicitHeight: 48; Layout.fillWidth: true } }
                    Item { implicitHeight: 62; Layout.fillWidth: true }
                    Item { objectName: "last"; implicitHeight: 48; Layout.fillWidth: true }
                }
            }
        }
    }
    function find(item, name) {
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const hit = root.find(item.children[i], name);
            if (hit)
                return hit;
        }
        return null;
    }
    function place(name) {
        const it = root.find(pageLoader.item, name);
        const y = it.mapToItem(pageColumn, 0, 0).y + pageColumn.y;
        return { top: y, bottom: y + it.height, from: pageScroll.contentY, to: pageScroll.contentY + pageScroll.height };
    }
    function test_link() {
        const out = {};
        wait(100);
        root.showPage("notch:advanced");
        wait(400);
        out.last = root.place("last");
        out.anchor = root.pageAnchor;
        root.current = 0;
        wait(100);
        root.showPage("notch");
        wait(400);
        out.plain = pageScroll.contentY;
        console.log("LINK " + JSON.stringify(out));
    }
}
`;
  let out = null;
  try {
    out = logged(runScene({ "tst_notch.qml": scene, ...module("qs.services", { SettingsApp: `QtObject { function keyFor(k) { return k; } }` }) }), "LINK");
  } catch (e) {
    check("the scene ran", false, String(e.message ?? e));
  }
  if (out) {
    const c = out.last;
    check("notch:advanced lands with Advanced's last row in view, not at the top of the page",
      c.top >= c.from && c.bottom <= c.to && out.anchor === "", JSON.stringify(out));
    check("and the Notch page opened from the rail still starts at its top", out.plain === 0, JSON.stringify(out));
  }
}
done();
