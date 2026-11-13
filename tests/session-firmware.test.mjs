// Firmware and Hibernate on the Session screen where the computer cannot do them (modules/common/functions/Session.qml,
// modules/ii/sessionScreen/SessionScreen.qml): Session's logind answers, the screen's shown() and its key handler, and
// what opening the screen asks again, run under node.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Firmware and Hibernate on the Session screen (Session.qml, SessionScreen.qml)");
const session = read("modules/common/functions/Session.qml"), screen = read("modules/ii/sessionScreen/SessionScreen.qml");
const handler = (src, key) => { const at = src.indexOf(`${key}:`); return at < 0 ? null : readExpression(src, at + key.length + 1).expr; };

// logind's answer to CanRebootToFirmwareSetup, as busctl prints it
const firmware = session.includes('"CanRebootToFirmwareSetup"') ? objectWith(session, '"CanRebootToFirmwareSetup"') : null;
check("Session asks logind whether the computer can restart into its firmware's setup", firmware !== null);
if (firmware) {
  const said = text => { const root = {}; inScope({ root, text }, "", handler(firmware, "onStreamFinished"))(); return root.canRebootToFirmware; };
  check('"na" (no firmware setup to restart into) is no, "yes" and "challenge" are yes',
    said('s "na"\n') === false && said('s "no"\n') === false && said('s "yes"\n') === true && said('s "challenge"\n') === true,
    `na ${said('s "na"\n')}, no ${said('s "no"\n')}, yes ${said('s "yes"\n')}, challenge ${said('s "challenge"\n')}`);
}

// the screen on a computer that can do neither
const Session = { canHibernate: false, canRebootToFirmware: false };
const shownFn = qmlFunction(screen, "shown");
const sessionRoot = { actions: Array.from({ length: 8 }, () => ({})), focusIndex: 4, activate() {}, hide() {} };
sessionRoot.shown = inScope({ Session, sessionRoot }, shownFn.params, shownFn.body);
check("Firmware is left out where it cannot work", sessionRoot.shown(6) === false && sessionRoot.shown(5) === false && sessionRoot.shown(4) === true,
  `Log out ${sessionRoot.shown(4)}, Hibernate ${sessionRoot.shown(5)}, Firmware ${sessionRoot.shown(6)}`);
Session.canRebootToFirmware = true;
check("and shown where it can", sessionRoot.shown(6) === true);
Session.canRebootToFirmware = false;

const keys = inScope({ sessionRoot, Qt: { Key_Escape: 1, Key_Right: 2, Key_Tab: 3, Key_Left: 4, Key_Backtab: 5, Key_Down: 6, Key_Up: 7, Key_Return: 8, Key_Enter: 9, Key_Space: 10 } },
  "", `return (${handler(objectWith(screen, "id: keys"), "Keys.onPressed")});`)();
const press = (from, key) => { sessionRoot.focusIndex = from; keys({ key, accepted: false }); return sessionRoot.focusIndex; };
check("Right from Log out steps over both to Tasks", press(4, 2) === 7, `lands on ${press(4, 2)}`);
check("Left from Tasks steps back over both to Log out", press(7, 4) === 4, `lands on ${press(7, 4)}`);
check("Down from Restart lands past them on Tasks", press(1, 6) === 7, `lands on ${press(1, 6)}`);

// opening the screen asks logind again, so a swap file made since counts
{
  const runs = [];
  const refresh = qmlFunction(session, "refreshCapabilities");
  const proc = name => ({ set running(v) { if (v) runs.push(name); } });
  const S = { refreshCapabilities: refresh ? inScope({ hibernateCheck: proc("CanHibernate"), firmwareCheck: proc("CanRebootToFirmwareSetup") }, refresh.params, refresh.body) : () => {} };
  const globals = { sidebarRightOpen: true };
  inScope({ sessionLoader: { active: true }, SessionWarnings: { refresh() {} }, Session: S, GlobalStates: globals }, "",
    handler(objectWith(screen, "id: sessionLoader"), "onActiveChanged"))();
  check("opening the screen asks logind both again", runs.join() === "CanHibernate,CanRebootToFirmwareSetup", `asked ${runs.join(", ") || "nothing"}`);
}
done();
