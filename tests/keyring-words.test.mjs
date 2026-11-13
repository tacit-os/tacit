// gnome-keyring's unlock ask in another language than English: Keyring.qml's own unlockAsk (the moot check runs only for
// it) and the sheet's title, run under node with the ask as gnome-keyring 51 words it in German, French and Russian, next
// to the asks that only look like it (gpg's pinentry, an ssh key's passphrase, a new password). Then
// scripts/keyring/unlock_words.py, which gives Keyring.qml those words, read against this computer's catalogues.
import { spawnSync } from "child_process";
import { existsSync } from "fs";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the keyring's unlock ask in any language");

// gnome-keyring 51's own catalogues (de.po, fr.po, ru.po): what unlock_words.py reads from them
const words = {
  named: ["An application wants access to the keyring “%s”, but it is locked",
    "Eine Anwendung versucht, auf den Schlüsselbund »%s« zuzugreifen, dieser ist jedoch gesperrt",
    "Une application veut accéder au trousseau de clés « %s », mais il est verrouillé",
    "Приложение хочет получить доступ к связке ключей «%s», но она заблокирована"],
  login: ["The login keyring did not get unlocked when you logged into your computer.",
    "Ihr Anmeldeschlüsselbund wurde nicht automatisch entsperrt, als Sie sich an diesem Rechner angemeldet haben."],
};

const keyring = read("modules/ii/keyring/Keyring.qml"), content = read("modules/ii/keyring/KeyringContent.qml");
const root = { unlockWords: words };
const named = qmlFunction(keyring, "keyringNamed");
if (named) root.keyringNamed = inScope({ root }, named.params.replace(/:\s*\w+/g, ""), named.body);   // (description: string)
const DialogBridge = { current: null };
const unlockAsk = () => value(keyring, "unlockAsk", { root, DialogBridge });
// what Keyring.qml hands the sheet for this ask (nothing, on a tree that has the sheet read the name itself)
const at = keyring.indexOf("named:", keyring.indexOf("KeyringContent {"));
const namedFor = at < 0 ? () => undefined
  : ask => inScope({ root: { ...root, ask } }, "", `return (${readExpression(keyring, at + 6).expr});`)();

const tr = s => Object.assign(new String(s), { arg: x => s.replace("%1", x) });
// a binding's value: an expression, or a block that returns one
const value = (src, name, scope) => {
  const e = qmlProperty(src, name);
  return inScope(scope, "", e.startsWith("{") ? e.slice(1, -1) : `return (${e});`)();
};
// the sheet's title for this ask, from KeyringContent's own bindings
function title(ask) {
  const r = { p: ask.params, confirm: false, isNew: false, weakConfirm: false, named: namedFor(ask) };
  for (const name of ["keyringName", "isLogin", "isPlain"]) r[name] = value(content, name, { root: r });
  return String(value(content, "headTitle", { root: r, Translation: { tr } }));
}

const ask = (description, more = {}) => ({ id: "k1", kind: "keyring.password",
  params: { mode: "password", message: "Legitimierung erforderlich", description, passwordNew: false, ...more } });
for (const [name, a, moot, head] of [
  ["German, the login keyring by name", ask("Eine Anwendung versucht, auf den Schlüsselbund »Login« zuzugreifen, dieser ist jedoch gesperrt"),
    true, "Unlock your keyring"],
  ["French, a keyring of its own", ask("Une application veut accéder au trousseau de clés « Travail », mais il est verrouillé"),
    true, "Unlock the “Travail” keyring"],
  ["Russian, the login keyring", ask("Приложение хочет получить доступ к связке ключей «Login», но она заблокирована"),
    true, "Unlock your keyring"],
  ["German, the login keyring's own sentence", ask(words.login[1]), true],
  ["English, as before", ask("An application wants access to the keyring “Login”, but it is locked"), true, "Unlock your keyring"],
  ["English, the login keyring's own sentence, as before", ask(words.login[0]), true],
  ["German, an ssh key's passphrase", ask("Eine Anwendung versucht, auf den privaten Schlüssel »id_ed25519« zuzugreifen, dieser ist jedoch gesperrt"),
    false, "Legitimierung erforderlich"],
  ["English, an ssh key's passphrase", ask("An application wants access to the private key “id_ed25519”, but it is locked"), false],
  ["gpg's pinentry", ask("Bitte geben Sie die Passphrase ein, um den OpenPGP-Schlüssel zu entsperren"), false],
  ["German, a new keyring's password", ask("Eine Anwendung versucht, auf den Schlüsselbund »Login« zuzugreifen, dieser ist jedoch gesperrt",
    { passwordNew: true }), false],
]) {
  DialogBridge.current = a;
  const got = unlockAsk() !== null;
  check(`${name}: ${moot ? "is gnome-keyring's unlock ask, refused once the keyring is open" : "is left to the person"}`, got === moot,
    `unlockAsk is ${got ? "set" : "null"}`);
  if (head) check(`${name}: the sheet's title is "${head}"`, title(a) === head, `it is "${title(a)}"`);
}

// the words themselves: English always, and each language this computer has gnome-keyring in
const script = join(tree, "scripts/keyring/unlock_words.py");
const run = existsSync(script) ? spawnSync("python3", ["-I", script], { encoding: "utf8" }) : null;
let got = null;
try { got = JSON.parse(run?.stdout ?? ""); } catch (e) {}
check("unlock_words.py gives both wordings in English", got && got.named.includes(words.named[0]) && got.login.includes(words.login[0]),
  run ? run.stderr || run.stdout : "there is no scripts/keyring/unlock_words.py");
if (existsSync("/usr/share/locale/de/LC_MESSAGES/gnome-keyring.mo")) {
  check("and in German, from gnome-keyring's own catalogue", got && got.named.includes(words.named[1]) && got.login.includes(words.login[1]));
  // an ask names its keyring between words: a wording that was only "%s" would take every ask, gpg's too, for the unlock
  check("each named wording has words around the name", got && got.named.every(w => w.split("%s").length === 2 && w.length > 12),
    JSON.stringify(got?.named.filter(w => w.length <= 12)));
} else console.log("  (gnome-keyring has no German catalogue here: the catalogue checks were not run)");
done();
