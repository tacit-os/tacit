// A link or a picture dragged from a browser onto the notch (modules/ii/island/IslandContent.qml): the drop area's own
// onEntered and onDropped run under node with the drags a browser and a file manager hand over. A browser gives a link
// or a picture as its https address (text/uri-list) beside the address as text; the shelf parks only file addresses, so
// such a drop is text for Praxis, as the area's comment says, not an empty shelf.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a web link or picture dropped on the notch (IslandContent.qml)");
const src = read("modules/ii/island/IslandContent.qml");
const area = src.indexOf("keys: [\"text/uri-list\", \"text/plain\"]");
const handler = name => readExpression(src, src.indexOf(`${name}:`, area) + name.length + 1).expr;
const entered = handler("onEntered"), dropped = handler("onDropped");
const own = ["isOwn", "hasFiles"].map(n => [n, qmlFunction(src, n)]).filter(([, f]) => f);

function drag({ urls = [], text = "" }) {
  const ev = { hasUrls: urls.length > 0, urls, hasText: text.length > 0, text, accepted: false, source: null, accept() { this.accepted = true; } };
  const parked = [], handed = [];
  const root = { signinShown: false, signinStage: "", sheetHeld: false, open: false, view: "home", dragOver: false, textDragOver: false,
    droppedThisDrag: false, pinnedUntilVisit: false };
  const scope = { root, leaveTimer: { stop() {} }, hoverTimer: { stop() {} }, IslandController: { snapshotRows() {} },
    DropShelf: { addItems: list => parked.push(...list.map(String)) }, Vpn: { isVpnFile: () => false, importFile() {} },
    Recents: { handText: t => handed.push(t) } };
  for (const [n, f] of own) root[n] = inScope(scope, f.params, f.body);
  inScope(scope, "", `return (${entered});`)()(ev);
  const over = { accepted: ev.accepted, view: root.view, shelf: root.dragOver, text: root.textDragOver };
  if (ev.accepted) inScope(scope, "", `return (${dropped});`)()(ev);
  return { over, parked, handed, accepted: ev.accepted, open: root.open };
}
const url = s => ({ toString: () => s });

{
  const link = "https://example.org/a/post";
  const r = drag({ urls: [url(link)], text: link });
  check("a link from the browser opens the sheet for text, not the shelf", r.over.accepted && r.over.view === "home" && r.over.text && !r.over.shelf,
    JSON.stringify(r.over));
  check("and dropped, it goes to Praxis", r.handed.length === 1 && r.handed[0] === link && r.parked.length === 0, JSON.stringify(r));
  check("and the sheet folds", r.open === false);
}
{
  const pic = "https://example.org/images/sunset.jpg";
  const r = drag({ urls: [url(pic)], text: pic });
  check("so does a picture from a web page", r.handed.join() === pic && r.parked.length === 0, JSON.stringify(r));
  const bare = drag({ urls: [url(pic)] });
  check("a web address with no text is not taken at all, rather than swallowed", !bare.accepted && bare.handed.length === 0, JSON.stringify(bare));
}
{
  const file = "file:///home/a/Downloads/report%20%233.pdf";
  const r = drag({ urls: [url(file)], text: "/home/a/Downloads/report #3.pdf" });
  check("a file from Pinax still opens the shelf", r.over.view === "shelf" && r.over.shelf && !r.over.text, JSON.stringify(r.over));
  check("and is parked there", r.parked.join() === file && r.handed.length === 0, JSON.stringify(r));
  const both = drag({ urls: [url("https://example.org/x"), url(file)], text: "" });
  check("a file dragged with a web address is parked", both.over.view === "shelf" && both.parked.includes(file), JSON.stringify(both));
}
{
  const r = drag({ text: "Fix the login bug" });
  check("plain text still goes to Praxis", r.over.view === "home" && r.handed.join() === "Fix the login bug", JSON.stringify(r));
}
done();
