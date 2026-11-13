// While the notch shows notifications, Settings > Notifications' two pop-up rows (how long, where) do nothing: the notch
// holds them for its own time. They are one line then, "Notifications show in the notch · Notch › Advanced", which opens
// that page's Advanced, and the corner they set, which is still where the notification centre opens, is a row there.
// The rows' visible, current and run bindings (tacit-settings.qml) go under node with a stand-in Config.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the pop-up rows while the notch shows notifications (tacit-settings.qml)");
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

for (const notch of [true, false]) {
  const Config = { options: { island: { enable: true, states: { notification: notch } }, notifications: { position: "bottom" } } };
  const root = { pages: [], showPage: p => root.pages.push(p) };
  for (const name of ["notificationCorners", "notificationCorner", "notchShowsNotifications"]) {
    const e = qmlProperty(src, name);
    if (e) root[name] = inScope({ Config, root }, "", `return (${e});`)();
  }
  const value = e => (e === null ? true : inScope({ Config, root }, "", `return (${e});`)());
  const rows = children(objectWith(src, 'title: "Pop-ups"'));
  const shown = rows.filter(r => value(expr(r.text, "visible")));
  const words = shown.map(r => label(r.text));
  if (notch) {
    check("with the notch showing notifications, Pop-ups is one line: \"Notifications show in the notch · Notch › Advanced\"",
      JSON.stringify(words) === JSON.stringify(["Notifications show in the notch · Notch › Advanced"]), JSON.stringify(words));
    const line = shown.find(r => label(r.text)?.startsWith("Notifications show in the notch"));
    if (line) {
      value(expr(line.text, "onActivated"));
      check("and the line opens Notch › Advanced", JSON.stringify(root.pages) === '["notch:advanced"]', JSON.stringify(root.pages));
    }
    // the Notch page takes that anchor by opening its Advanced
    const take = qmlFunction(objectWith(src, "id: notchPage"), "takeAnchor");
    const notchAdvanced = { open: false };
    inScope({ nt: { viewing: "" }, notchAdvanced, root: { pageAnchor: "advanced" } }, take.params, take.body)("advanced");
    check("which the Notch page opens at its Advanced", notchAdvanced.open === true);
  } else {
    check("with the notch not showing them, Pop-ups has its two rows", JSON.stringify(words) === '["How long a pop-up stays","Where pop-ups appear"]',
      JSON.stringify(words));
  }

  // the corner, in the Notch page's Advanced while the notch shows notifications
  const notchPage = objectWith(src, "id: notchPage"), advAt = notchPage.indexOf("Advanced {");
  const advanced = children(notchPage.slice(advAt, matchBrace(notchPage, notchPage.indexOf("{", advAt)) + 1)).filter(r => r.type === "ChoiceRow"
    && (expr(r.text, "onPicked") ?? "").includes("notifications.position"));
  const corner = advanced.find(r => value(expr(r.text, "visible")));
  if (notch) {
    check("Notch › Advanced has the notification centre's corner", !!corner, `${advanced.length} such rows`);
    if (corner) {
      const options = value(expr(corner.text, "options")).map(o => o.value);
      check("with the six corners, an old \"bottom\" read as bottom right",
        options.length === 6 && value(expr(corner.text, "current")) === "bottom_right", `${JSON.stringify(options)}, ${value(expr(corner.text, "current"))}`);
      value(expr(corner.text, "onPicked"))("top_left");
      check("and picking one sets where notifications open", Config.options.notifications.position === "top_left");
    }
  } else {
    check("and the Notch page has no second corner row then", !corner);
  }
}
done();
