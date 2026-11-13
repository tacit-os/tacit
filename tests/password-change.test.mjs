// Settings > Your account > Change your password (tacit-settings.qml): what is left in the three fields once passwd has
// answered. Only the field that was refused is emptied: a wrong password now counts toward pam_faillock like a miss at
// the lock screen, and two long new ones typed again for nothing invite the next miss. The row's submit() and the
// answer's handler run under node, with the words scripts/settings/passwd.py prints.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the fields after a password change (tacit-settings.qml)");
const app = read("tacit-settings.qml");
const submit = qmlFunction(app.slice(app.indexOf("id: passwordRow")), "submit");
const answerAt = app.indexOf("{", app.indexOf("onStreamFinished:", app.indexOf("id: passwdProc")));
const answer = app.slice(answerAt + 1, matchBrace(app, answerAt));
const passwd = read("scripts/settings/passwd.py");

function change(now, next, said) {
  let focused = "";
  const field = (name, text) => ({ text, focusInput() { focused = name; } });
  const scope = {
    nowField: field("now", now), newField: field("new", next), againField: field("again", next),
    passwordRow: { said: "", asking: true }, passwdProc: { running: false, secret: "" },
  };
  inScope(scope, "", submit.body)();
  const sent = scope.passwdProc.running && scope.passwdProc.secret === `${now}\n${next}\n`;
  inScope({ ...scope, text: `${said}\n` }, "", answer)();
  return { sent, now: scope.nowField.text, next: scope.newField.text, again: scope.againField.text, focused, ...scope.passwordRow };
}
const show = r => JSON.stringify(r);

for (const words of ["That is not your password now", "The new one is too short", "The new one is too easy to guess", "changed"])
  check(`passwd.py says "${words}"`, passwd.includes(`print("${words}")`));
{
  const r = change("tpyo", "a long new passphrase", "That is not your password now");
  check("the one now refused: both new ones are still there, the one now is emptied and has the keys",
    r.sent && r.now === "" && r.next === "a long new passphrase" && r.again === "a long new passphrase" && r.focused === "now", show(r));
}
{
  const r = change("right one", "short", "The new one is too short");
  check("the new one refused: the one now is still there, both new ones are emptied and the first has the keys",
    r.sent && r.now === "right one" && r.next === "" && r.again === "" && r.focused === "new", show(r));
}
{
  const r = change("right one", "a long new passphrase", "changed");
  check("changed: all three are emptied and the fields close", r.now + r.next + r.again === "" && !r.asking && r.said === "Changed", show(r));
  const odd = change("right one", "a long new passphrase", "It did not change");
  check("refused for no reason known: all three are emptied", odd.now + odd.next + odd.again === "" && odd.focused === "now", show(odd));
}
done();
