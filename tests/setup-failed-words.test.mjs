// What Setup's failed page says happened to the disk (setup.qml): the page's own sentence binding under node, for each
// way an install goes and how far it got. "Choose partitions myself" erases only the partitions chosen for Tacit, and
// the page said the disk had been erased.
import { inScope, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the failed page's words about the disk (setup.qml)");
const sentence = objectWith(read("setup.qml"), "Tacit stopped partway, after the disk was erased.");
const expr = readExpression(sentence, sentence.indexOf("text:") + "text:".length).expr;
const says = setup => inScope({ root: { shownPage: "failed", other: "Windows", zoneNote: "", a11yNote: "" },
  setup: { otherSystem: "", partBoot: "", ...setup } }, "", `return (${expr});`)();

check("a manual install that stopped partway: only the partition chosen was erased",
  says({ installUntouched: false, place: "manual" }) === "Tacit stopped partway, after the partition chosen for it was erased. You can try again.",
  says({ installUntouched: false, place: "manual" }));
check("with a boot partition chosen too: the two of them",
  says({ installUntouched: false, place: "manual", partBoot: "/dev/sda2" }) === "Tacit stopped partway, after the two partitions chosen for it were erased. You can try again.",
  says({ installUntouched: false, place: "manual", partBoot: "/dev/sda2" }));
check("instead of Windows: the disk was erased", says({ installUntouched: false, place: "instead" }) === "Tacit stopped partway, after the disk was erased. You can try again.",
  says({ installUntouched: false, place: "instead" }));
check("next to Windows: Windows should start as before", says({ installUntouched: false, place: "next" }).startsWith("Tacit stopped partway. Windows should start as before"),
  says({ installUntouched: false, place: "next" }));
check("nothing changed yet: the disk is as it was", says({ installUntouched: true, place: "manual" }).startsWith("Nothing on the disk was changed"),
  says({ installUntouched: true, place: "manual" }));
done();
