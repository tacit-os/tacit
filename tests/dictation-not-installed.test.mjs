// Dictation on a computer without Flow (services/Dictation.qml, tacit-settings.qml): Flow is not packaged, so most
// computers have no flowd user service. The look at its unit, the key's press and the knocking Timer in Dictation.qml,
// and Settings' look and its Dictation group's visible binding, run under node on what systemctl says of the unit.
// Without it the key says dictation isn't set up (not "Flow isn't running", as if it could be started), nothing knocks,
// and Settings shows no word list and key for it. Where systemctl cannot say, all stays as before.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== dictation where Flow is not installed (services/Dictation.qml, tacit-settings.qml)");
const src = read("services/Dictation.qml");
const at = src.indexOf('"show", "-P", "LoadState", "flowd.service"');
const seen = at < 0 ? null : readExpression(src, src.indexOf("onStreamFinished:", at) + "onStreamFinished:".length).expr;
const installedFor = text => { const root = { installed: true }; if (seen) inScope({ root, text }, "", `${seen};`)(); return root.installed; };
check("a unit systemd does not know is not installed", installedFor("not-found\n") === false, String(installedFor("not-found\n")));
check("one it knows is", installedFor("loaded\n") === true, String(installedFor("loaded\n")));
check("no answer counts as installed, as before", installedFor("") === true, String(installedFor("")));

const retryAt = src.indexOf("id: retry");
const knocking = readExpression(src, src.indexOf("running:", retryAt) + "running:".length).expr;
check("without it nothing knocks or starts flowd.service", inScope({ root: { connected: false, installed: false } }, "", `return (${knocking});`)() === false, knocking);

const press = qmlFunction(src, "press");
const pressed = installed => {
  const said = [];
  const scope = { root: { connected: false, installed }, GlobalStates: { screenLocked: false }, Voice: { cant: r => `Can't: ${r}` },
    retry: { tries: 3 }, installedProc: { running: false }, IslandController: { request: (n, d) => said.push(d.text) } };
  inScope(scope, press.params, press.body)();
  return said.join();
};
check("its key says dictation isn't set up on this computer", pressed(false) === "Can't: dictation isn't set up on this computer", pressed(false));
check("with Flow installed but not answering, it still says Flow isn't running", pressed(true) === "Can't: Flow isn't running", pressed(true));

const app = read("tacit-settings.qml");
const lookAt = app.indexOf('"show", "-P", "LoadState", "flowd.service"');
const look = lookAt < 0 ? null : readExpression(app, app.indexOf("onStreamFinished:", lookAt) + "onStreamFinished:".length).expr;
const settingsFor = text => { const root = { flowInstalled: true }; if (look) inScope({ root, text }, "", `${look};`)(); return root.flowInstalled; };
const groupAt = app.lastIndexOf("Group {", app.indexOf('title: "Dictation"'));
const group = app.slice(groupAt, matchBrace(app, groupAt + "Group ".length));
const visible = readExpression(group, group.indexOf("visible:") + "visible:".length).expr;
const shown = text => inScope({ inputCol: { viewing: "" }, root: { flowInstalled: settingsFor(text) } }, "", `return (${visible});`)();
check("Settings hides the Dictation group without Flow", shown("not-found\n") === false, visible);
check("and shows it with Flow", shown("loaded\n") === true, visible);
done();
