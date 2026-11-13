// "Restart anyway" after a restart warning (services/Updates.qml): the notch's card that says the warning and offers
// Restart anyway is held for IslandController.holdFor("update") (run under node with the warning's payload), and the
// warning has to stay armed as long, or a press in the card's last seconds asks the same warning again.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const updates = read("services/Updates.qml");
const at = updates.indexOf("interval:", updates.indexOf("id: disarmTimer"));
const armed = +readExpression(updates, at + "interval:".length).expr;
const h = qmlFunction(read("services/IslandController.qml"), "holdFor");
const card = inScope({ root: { payload: { icon: "warning", text: "Uncommitted work", warning: true } } }, h.params, h.body)("update");

console.log("== Restart anyway after a warning (services/Updates.qml, services/IslandController.qml)");
check("the warning stays armed for as long as the notch shows its Restart anyway", armed >= card, `armed ${armed} ms, the card ${card} ms`);
done();
