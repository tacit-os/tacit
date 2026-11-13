// What Settings' rows say about what they do (tacit-settings.qml), where a row's words left out something it changes.
import { check, done, read } from "./lib/check.mjs";

console.log("== what Settings' rows say (tacit-settings.qml)");
const app = read("tacit-settings.qml");
// a row's description, found by its label
const said = label => app.slice(app.indexOf(`label: "${label}"`)).match(/description: "([^"]*)"/)?.[1] ?? "";

// Windows > Look and motion: turning the line off unloads tacit-frame, and the three-finger swipes (general.lua) run
// hyprctl tacitgrip, which only that plugin answers
check(`"Line on windows" says the three-finger swipes need it`, /three-finger swipes/i.test(said("Line on windows")), said("Line on windows"));
// Accounts > Keys: a key added here is for any agent's account, Claude Code's and Codex's too ("Use a key instead…")
check(`"Add a key" does not say it is only for pi and opencode`, !/pi and opencode/.test(said("Add a key")), said("Add a key"));
done();
