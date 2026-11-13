// "Unlock saved passwords with the session" is gone (tacit-settings.qml, the old shell page InterfaceConfig.qml): the
// switch did nothing, since PAM opens the keyring with the lock's password either way (pam_gnome_keyring in
// /etc/pam.d/login) and the script it ran reads the password and drops it. What says the keyring is locked, Settings >
// Accounts and Praxis's sign-in steps (AgentSteps.qml), run under node with the old switch off: neither points to it.
import { inScope, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the keyring switch and what points to it");
const settings = read("tacit-settings.qml"), legacy = read("modules/ii/settings/pages/InterfaceConfig.qml");
check("Settings has no switch for it", !/checked:\s*Config\.options\.lock\.security\.unlockKeyring/.test(settings));
check("nor the old shell settings page", !/checked:\s*Config\.options\.lock\.security\.unlockKeyring/.test(legacy));

const Config = { options: { lock: { security: { unlockKeyring: false } } } };
const line = inScope({ Config }, "", `return (${qmlProperty(settings, "lockedLine")});`)();
check("Accounts says the keyring is locked, how it opens, and nothing about Lock & sleep",
  /^The keyring is locked/.test(line) && !/Lock & sleep/.test(line) && /password/.test(line), line);

{
  const expr = qmlProperty(read("modules/claude/AgentSteps.qml"), "view");
  const m = { agentName: () => "Claude", install: null, check() {} };
  const steps = { model: m, shown: "locked", agent: "claude", accountId: "a1", refusal: null, flow: null };
  const view = inScope({ steps, Config, SettingsApp: { open() {} }, Qt: {}, Quickshell: {} }, "", expr.slice(1, -1))();
  const words = (view.actions ?? []).map(a => a.word);
  check("Praxis's sign-in steps say how it opens and offer no Lock & sleep",
    !/Lock & sleep/.test(view.sub) && !words.includes("Lock & sleep") && words.includes("Check again"), `${view.sub} · ${words}`);
}
done();
