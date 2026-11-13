// A power mode that cannot be written (an account outside the wheel group, a read-only disk): services/PowerMode.qml's
// own saveFailed and saved handlers run under node, then Settings > Display & power's two rows' descriptions
// (tacit-settings.qml). The choice snaps back to what the file holds, and the rows should say why.
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/PowerMode.qml"), app = read("tacit-settings.qml");
const handler = name => {
  const m = new RegExp(`\\b${name}:`).exec(src);
  if (!m) return "";
  const h = readExpression(src, m.index + m[0].length).expr;
  return h.startsWith("{") ? h.slice(1, -1) : h;
};
const description = label => readExpression(app, app.indexOf("description:", app.indexOf(label)) + "description:".length).expr;

console.log("== a power mode that cannot be written (services/PowerMode.qml, tacit-settings.qml)");
{
  const PowerMode = { charging: true, onCharger: "fastest", onBattery: "balanced", say: m => `says ${m}` };
  let reloaded = 0;
  const scope = { root: PowerMode, reload: () => reloaded++ };
  const rows = () => ['label: root.hasBattery ? "On the charger"', 'label: "On battery"']
    .map(l => inScope({ root: { hasBattery: true }, PowerMode }, "", `return (${description(l)});`)());
  const before = rows();
  inScope(scope, "", handler("onSaveFailed"))();
  const refused = rows();
  check("refused: the file's modes are read back", reloaded === 1);
  check("and both rows say only an administrator can change this", refused.every(d => /only an administrator can change this/i.test(d)), JSON.stringify(refused));
  inScope(scope, "", handler("onSaved"))();
  check("a later change that is written: the rows say what each mode does again", JSON.stringify(rows()) === JSON.stringify(before),
    JSON.stringify(rows()));
}
done();
