// Settings > Appearance > Lock screen picture (tacit-settings.qml): the row's own description binding under node, with a
// picture chosen and without. The picture shows only on the lock after sign-in: the boot lock and the login screen keep
// the ground tacit-boot-ground bakes from the desktop's picture, and the row said nothing of it.
import { inScope, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the lock screen picture's row in Settings (tacit-settings.qml)");
const row = objectWith(read("tacit-settings.qml"), 'label: "Lock screen picture"');
const expr = readExpression(row, row.indexOf("description:") + "description:".length).expr;
const says = lockWall => inScope({ Config: { options: { background: { lockWall } } } }, "", `return (${expr});`)();

check("a picture chosen: its name, and that it shows after sign-in", says("/home/you/Pictures/beach.jpg") === "beach.jpg · shows after sign-in",
  says("/home/you/Pictures/beach.jpg"));
check("none chosen: the desktop's, as before", says("") === "The same picture as the desktop", says(""));
done();
