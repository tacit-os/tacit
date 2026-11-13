// Setup's disk page when no disk is found (setup.qml): the page's own headline, sentence and Look again link under node,
// and setup.qml's receive() for the answer a read sends. A disk behind Intel RST or RAID is not seen by Linux, and the
// page said only that there was no disk, with Turn off as the one way on.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Setup's disk page with no disk found (setup.qml)");
const src = read("setup.qml");
const binding = (block, name) => readExpression(block, block.indexOf(`${name}:`) + name.length + 1).expr;
const headline = binding(objectWith(src, 'text: parent.c === "looking" ? "Looking at the disks…"'), "text");
const sentence = binding(objectWith(src, "id: whereSentence"), "text");
const page = c => ({ parent: { c, size: "0 GB", noNext: "", room: false }, backend: { disk: {}, disks: [] }, root: { windowsElsewhere: false } });
const say = (expr, c) => inScope(page(c), "", `return (${expr});`)();

check('the headline: "No disk found."', say(headline, "none") === "No disk found.", say(headline, "none"));
const words = "On computers set to Intel RST or RAID, the disk mode has to be AHCI in the firmware settings; prepare Windows for that first.";
check("the sentence says where a disk in Intel RST or RAID mode is found", say(sentence, "none") === words, say(sentence, "none"));
check("the page while it looks is as it was", say(headline, "looking") === "Looking at the disks…", say(headline, "looking"));

let link = null;
try { link = objectWith(src, 'text: "Look again"'); } catch (e) { /* none */ }
check("the page has a Look again link", link !== null);
if (link) {
  const visible = binding(link, "visible");
  const shows = c => inScope({ parent: { parent: { c } } }, "", `return (${visible});`)();
  check("it shows with no disk found, and on no other page", shows("none") && !["looking", "windows", "empty", "small", "choose", "linux"].some(shows));
  const row = binding(objectWith(src, "id: diskLinks"), "visible");
  check("and the row it is in shows then", inScope({ backend: { disksRead: true }, parent: { c: "none" } }, "", `return (${row});`)());

  // pressed: the page looks again, and a disk found since is the page's
  const sent = [];
  const backend = { disksRead: true, disk: { case: "none" }, send: m => sent.push(m) };
  inScope({ backend }, "", binding(link, "onClicked"))();
  const c = () => (backend.disksRead ? (backend.disk.case ?? "none") : "looking");
  check("pressing it reads the disks again, the page saying it is looking until they are",
    JSON.stringify(sent) === '[{"op":"disks"}]' && c() === "looking", `sent ${JSON.stringify(sent)}, page ${c()}`);
  const receive = qmlFunction(src, "receive");
  inScope({ backend, root: { keepParts() {} }, setup: {} }, receive.params, receive.body)(JSON.stringify({ ev: "disks", disks: [],
    disk: { name: "/dev/nvme0n1", case: "empty", size: 512e9 }, plan: { room: false }, parts: [] }));
  check("and the disk found then is shown", c() === "empty", `page ${c()}`);
}
done();
