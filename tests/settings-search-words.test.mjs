// Settings' search (tacit-settings.qml matches(), run under node over services/SettingsCatalog.qml's pages, which the
// palette's Settings rows read too): the names of rows a page has find that page.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const categories = inScope({}, "", `return (${qmlProperty(read("services/SettingsCatalog.qml"), "categories")});`)();
const m = qmlFunction(read("tacit-settings.qml"), "matches");
const found = query => categories.filter(cat => inScope({ root: { query } }, m.params, m.body)(cat)).map(c => c.key);

console.log("== Settings' search finds the page a row is on (services/SettingsCatalog.qml)");
// each query is a row on that page: Wired and This computer's address (Network), Restart, Tonight and Check for updates
// (About), Line on windows (Windows), Battery and charger sounds and A timer finishing (Sound)
const cases = [["ethernet", "network"], ["wired", "network"], ["ip address", "network"], ["restart", "about"], ["tonight", "about"],
  ["check for updates", "about"], ["window line", "windows"], ["battery sounds", "sound"], ["timer", "sound"], ["battery", "display"]];
const wrong = cases.filter(([q, key]) => !found(q).includes(key)).map(([q, key]) => `"${q}" found ${JSON.stringify(found(q))}, not ${key}`);
check("each row's words find its page", wrong.length === 0, wrong.join("; "));
done();
