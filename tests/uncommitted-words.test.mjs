// What the git watch finds is uncommitted work, not unsaved changes (SessionScreen.qml, Updates.qml, tacit-settings.qml):
// it is git status in the watched folders, so a file saved long ago was "unsaved" and a document open in an editor was
// nothing. The Session screen's line, the warning Updates' Restart stops at (in the notch and in Settings > About, whose
// line it fills) and the notch's Reminders rows in Settings run under node with their own bindings.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the git watch says \"Uncommitted work\" (SessionScreen.qml, Updates.qml, tacit-settings.qml)");
const tr = s => Object.assign(new String(s), { arg: a => String(s).replace("%1", a) });

const session = read("modules/ii/sessionScreen/SessionScreen.qml");
const at = session.indexOf("visible: IslandController.workUnsaved");
const textAt = session.indexOf("text:", at);
const line = String(inScope({ Translation: { tr }, IslandController: { unsavedLine: "app (3 files, 2 h)" } }, "",
  `return (${readExpression(session, textAt + "text:".length).expr});`)());
check("the Session screen says \"Uncommitted work: app (3 files, 2 h)\"", line === "Uncommitted work: app (3 files, 2 h)", `"${line}"`);

// Updates' Restart with the work found: the warning it stops at
const usrc = read("services/Updates.qml");
const checked = qmlFunction(usrc.slice(usrc.indexOf("target: SessionWarnings")), "onChecked");
const notch = [];
const root = { says: true, guarding: true, restartWarning: "", shellUnsaved: false, go() {} };
inScope({ root, IslandController: { workUnsaved: true, request: (n, d) => notch.push(d.text) }, disarmTimer: { restart() {} },
  SessionWarnings: { agentWorking: false, packageManagerRunning: false, downloadRunning: false, agentTitles: [] } }, checked.params, checked.body)();
check("Restart stops at \"Uncommitted work\" in the notch", root.restartWarning === "Uncommitted work" && notch.join() === "Uncommitted work",
  `"${root.restartWarning}", the notch: ${JSON.stringify(notch)}`);

const ssrc = read("tacit-settings.qml");
const descAt = ssrc.indexOf("Updates.restartWarning.length > 0 ? `");
const about = inScope({ Updates: { restartWarning: root.restartWarning } }, "", `return ${ssrc.slice(descAt, ssrc.indexOf("\n", descAt)).replace(/^[^?]*\?\s*/, "").replace(/\s*$/, "")};`)();
check("Settings > About says \"Uncommitted work · restart anyway, or wait\"", about === "Uncommitted work · restart anyway, or wait", `"${about}"`);

// Settings > Notch > Reminders: the watched folders
const remAt = ssrc.indexOf('label: "Reminders"');
const reminders = ssrc.slice(remAt, ssrc.indexOf("create_new_folder", remAt) + 400);
const said = [...reminders.matchAll(/(?:description|label):\s*[`"]([^`"]*)[`"]/g)].map(m => m[1]).concat([...reminders.matchAll(/pickFolder\("([^"]+)"/g)].map(m => m[1]));
const wrong = said.filter(t => /unsaved/i.test(t));
check("the Reminders rows call it uncommitted work, never unsaved", wrong.length === 0 && said.some(t => /^Uncommitted work in/.test(t)),
  wrong.length ? wrong.join(" | ") : said.join(" | "));
done();
