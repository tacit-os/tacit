// The lock screen, the boot lock and an app's password request (polkit), run under node: their own functions, with a
// pretend PAM that counts the attempts it is given, the lock's Shut down and Restart discs pressed in turn, and the
// password sheets' windows on two screens.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("Sign-in: the lock, the boot lock and an app's password request");

// tryUnlock() of a lock context with this text typed: how many times PAM was started, and whether the field was focused
function unlock(file, text) {
  const f = qmlFunction(read(file), "tryUnlock");
  let started = 0, refocused = 0;
  const root = { currentText: text, alsoInhibitIdle: false, authUnavailable: false, unlockInProgress: false,
    shouldReFocus() { refocused++; } };
  const pam = { start() { started++; return true; } };
  inScope({ root, pam }, f.params, f.body)();
  return { started, refocused, busy: root.unlockInProgress };
}
for (const [name, file] of [["the lock", "modules/common/panels/lock/LockContext.qml"], ["the boot lock", "modules/common/panels/lock/BootLockContext.qml"]]) {
  const empty = unlock(file, "");
  check(`${name}: Enter on an empty field is not sent to PAM, and the field keeps the keys`,
    empty.started === 0 && !empty.busy && empty.refocused === 1, `PAM started ${empty.started} times`);
  const typed = unlock(file, "hunter2");
  check(`${name}: a typed password is`, typed.started === 1 && typed.busy, `PAM started ${typed.started} times`);
}

// PolkitContent's submit() with this text in the field: what was answered
function polkit(text) {
  const f = qmlFunction(read("modules/ii/polkit/PolkitContent.qml"), "submit");
  const sent = [];
  const scope = { root: { submitted: false }, field: { text, forceActiveFocus() {} },
    PolkitService: { interactionAvailable: true, submit: t => sent.push(t) }, console: { warn() {} } };
  inScope(scope, f.params, f.body)();
  return sent;
}
check("an app's password request: an empty field is not answered", polkit("").length === 0, `answered ${JSON.stringify(polkit(""))}`);
check("an app's password request: a typed password is", JSON.stringify(polkit("hunter2")) === '["hunter2"]');

// the sheet's way out by pointer: its Cancel, pressed, and a press on the dim around it; what reached polkit
{
  const src = read("modules/ii/polkit/PolkitContent.qml");
  const run = handler => {
    const did = [];
    inScope({ PolkitService: { cancel: () => did.push("cancel"), submit: () => did.push("submit") }, root: { submit: () => did.push("submit") },
      field: { forceActiveFocus: () => did.push("focus") } }, "", handler)();
    return did.join(",");
  };
  const cancel = /\bTextAction\s*\{\s*label:\s*Translation\.tr\("Cancel"\);\s*onClicked:\s*([^}\n]+?)\s*\}/.exec(src);
  check("an app's password request has a Cancel to click, which cancels it", cancel !== null && run(cancel[1]) === "cancel",
    cancel ? run(cancel[1]) : "no Cancel on the sheet");
  const dim = /\/\/ WindowDialog's dim[\s\S]*?MouseArea\s*\{[\s\S]*?onPressed:\s*([^\n]+)/.exec(src);
  check("a click on the dim around it still does nothing but give the field the keys", dim !== null && run(dim[1]) === "focus",
    dim ? run(dim[1]) : "no dim");
}

// power() of a lock surface: the discs pressed in turn, each "S" (Shut down) or "R" (Restart); what ran
const ActionEnum = { Unlock: 0, Poweroff: 1, Reboot: 2 };
function press(file, presses, requirePasswordToPower = false) {
  const f = qmlFunction(read(file), "power");
  const ran = [];
  const root = { requirePasswordToPower, armedPower: ActionEnum.Unlock, forceFieldFocus() {},
    context: { targetAction: ActionEnum.Unlock, resetTargetAction() { this.targetAction = ActionEnum.Unlock; } } };
  const power = inScope({ root, disarmPower: { restart() {} }, LockContext: { ActionEnum }, BootLockContext: { ActionEnum } }, f.params, f.body);
  for (const p of presses)
    power(p === "S" ? ActionEnum.Poweroff : ActionEnum.Reboot, () => ran.push(p));
  return { ran: ran.join(""), target: root.context.targetAction };
}
for (const [name, file] of [["the lock", "modules/ii/lock/LockSurface.qml"], ["the boot lock", "modules/ii/lock/BootLockSurface.qml"]]) {
  const once = press(file, ["S"]), twice = press(file, ["S", "S"]), mixed = press(file, ["R", "S"]);
  check(`${name}: one press on Shut down does not shut down, a second does`, once.ran === "" && twice.ran === "S",
    `one press ran "${once.ran}", two ran "${twice.ran}"`);
  check(`${name}: Restart then Shut down runs neither`, mixed.ran === "", `ran "${mixed.ran}"`);
  const pw = press(file, ["S", "S", "S"], true);
  check(`${name}: with the password asked for, the disc only arms the password`, pw.ran === "" && pw.target === ActionEnum.Poweroff,
    `ran "${pw.ran}", the password would ${pw.target === ActionEnum.Poweroff ? "shut down" : "unlock"}`);
}

// A sheet that asks for a password over every screen (the keyring's, an app's): which screens' windows hold the keys,
// with the focused monitor the second of two. Each window's own takesKeys and keyboardFocus bindings, evaluated per screen.
function keyWindows(file, scope) {
  const src = read(file);
  const screens = [{ name: "eDP-1" }, { name: "HDMI-A-1" }];
  const root = scope.root;
  const pick = qmlFunction(src, "pickKeyScreen");
  if (pick) inScope({ ...scope, root, WM: { compositor: "hyprland" }, Hyprland: { focusedMonitor: screens[1] } }, "", pick.body)();
  else root.keyScreenName = screens[1].name;
  const takes = qmlProperty(src, "takesKeys");
  const at = src.indexOf("WlrLayershell.keyboardFocus:");
  const focus = readExpression(src, at + "WlrLayershell.keyboardFocus:".length).expr;
  return screens.filter(screen => {
    const panelWindow = { screen };
    const s = { ...scope, root, panelWindow, Quickshell: { screens }, WlrKeyboardFocus: { None: 0, Exclusive: 1 } };
    if (takes) panelWindow.takesKeys = inScope(s, "", `return (${takes});`)();
    return inScope(s, "", `return (${focus});`)() === 1;
  }).map(s => s.name);
}
{
  const keyring = keyWindows("modules/ii/keyring/Keyring.qml", { root: { asking: true, keyScreenName: "" } });
  check("the keyring sheet on two screens: only the focused one's window holds the keys", JSON.stringify(keyring) === '["HDMI-A-1"]',
    `held by ${JSON.stringify(keyring)}`);
  const polkit = keyWindows("modules/common/widgets/FullscreenPolkitWindow.qml", { root: { keyScreenName: "" }, PolkitService: { active: true } });
  check("an app's password request on two screens: the same", JSON.stringify(polkit) === '["HDMI-A-1"]', `held by ${JSON.stringify(polkit)}`);
}

done();
