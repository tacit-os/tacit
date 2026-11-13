// Settings > About > Updates after a Restart whose download failed (services/Updates.qml, tacit-settings.qml): the
// restart's onExited runs under node as the download fails, then Settings' restartFailed binding with updates.json as
// later looks write it. A look after the failure that finds every update here (the shell's own download, online again,
// finished it) leaves "Couldn't finish the download" behind; the failure stays until then.
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a failed restart download, then the update downloaded (Updates.qml, tacit-settings.qml)");
const upd = read("services/Updates.qml");
const exAt = upd.indexOf("onExited:", upd.indexOf("id: restartProc"));
const exited = readExpression(upd, exAt + "onExited:".length).expr;
const root = { restartFailed: "", restartFailedAt: 0, failureCause: () => "offline", says: true };
const failedAt = Date.now();
inScope({ root, restartOut: { text: "error: failed retrieving file\n" }, IslandController: { request() {} } }, "", `return (${exited});`)()(1, 0);
check("the failed download is said", root.restartFailed === "prepare", root.restartFailed);

const app = read("tacit-settings.qml");
const group = app.slice(app.indexOf("id: updatesGroup"));
const m = /\n\s*readonly property string restartFailed:\s*/.exec(group);
const expr = readExpression(group, m.index + m[0].length).expr;
const shown = state => inScope({ Updates: root, updatesGroup: { state } }, "", `return (${expr});`)();
check("a look from before the failure leaves it said", shown({ ready: true, checked: failedAt - 60000 }) === "prepare", shown({ ready: true, checked: failedAt - 60000 }));
check("a later look that finds the updates not all here leaves it said", shown({ ready: false, checked: failedAt + 60000 }) === "prepare", shown({ ready: false, checked: failedAt + 60000 }));
check("a later look that finds them all here leaves it behind", shown({ ready: true, checked: failedAt + 60000 }) === "", shown({ ready: true, checked: failedAt + 60000 }));
root.restartFailed = "reboot";
check("a restart refused after the download is not touched", shown({ ready: true, checked: failedAt + 60000 }) === "reboot", shown({ ready: true, checked: failedAt + 60000 }));
done();
