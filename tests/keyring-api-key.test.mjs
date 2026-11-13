// An API key given in the palette (/unsplash KEY, services/LauncherSearch.qml) while the keyring is locked or open
// (services/KeyringStorage.qml): the action's own execute(), the storage's setNestedField(), flushPendingWrites() and
// its lookup process's handlers under node, with the lookup answering as scripts/keyring/try_lookup.sh does ("locked",
// exit 2). The notice may say "saved" only of a key that was written.
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== an API key given while the keyring is locked (LauncherSearch.qml, KeyringStorage.qml)");
const search = read("services/LauncherSearch.qml"), store = read("services/KeyringStorage.qml");
const block = (src, marker, from) => { const at = src.indexOf(marker, from); const open = src.indexOf("{", at + marker.length); return src.slice(open + 1, matchBrace(src, open)); };
const getAt = store.indexOf("id: getData");
const streamBody = block(store, "onStreamFinished:", getAt), exitBody = block(store, "onExited: (exitCode, exitStatus) =>", getAt);

function desk(loaded = false) {
  const notices = [], written = [];
  const collector = { text: "" };
  const ks = { loaded, keyringData: loaded ? {} : {}, pendingWrites: [], saveQueued: false };
  const getData = { running: false };
  const scope = { root: ks, getData, keyringDataOutputCollector: collector, retryLocked: { restart() {} },
    saveData: { running: false, stdinEnabled: false }, console: { error() {} } };
  for (const name of ["setNestedField", "flushPendingWrites", "fetchKeyringData"]) { const f = qmlFunction(store, name); ks[name] = inScope(scope, f.params, f.body); }
  scope.saveKeyringData = ks.saveKeyringData = () => written.push(JSON.stringify(ks.keyringData));
  const stream = inScope(scope, "", streamBody), exited = inScope(scope, "exitCode, exitStatus", exitBody);
  // the lookup answers: "locked" with exit 2, or the stored JSON with exit 0
  const lookup = (out, code) => { getData.running = false; collector.text = out; stream(); exited(code, 0); };

  const root = {};
  const f = qmlFunction(search, "keySaid");
  if (f) root.keySaid = inScope({ root, Translation: { tr: s => s }, Quickshell: { execDetached: c => notices.push(c[2]) } }, f.params, f.body);
  const actions = inScope({ root, KeyringStorage: ks, Translation: { tr: s => s }, Quickshell: { execDetached: c => notices.push(c[2]) } }, "",
    `return (${qmlProperty(search, "searchActions")});`)();
  const unsplash = actions.find(a => a.action === "unsplash");
  return { notices, written, lookup, give: key => unsplash.execute(key), getData };
}

{
  const d = desk();
  d.give("abc123");
  d.lookup("locked", 2);
  check("with the keyring locked, the notice does not say the key was saved", !d.notices.some(n => /saved!/.test(n)), JSON.stringify(d.notices));
  check("it says the keyring is locked and when the key is kept", d.notices.length === 1 && /keyring is locked/.test(d.notices[0]), JSON.stringify(d.notices));
  d.lookup("locked", 2);                  // the look again 10 s later
  check("and says it once, not at every look again", d.notices.length === 1, JSON.stringify(d.notices));
  d.lookup('{"apiKeys":{"wallhaven":"w1"}}', 0);   // the keyring opens
  check("once it opens, the key is written beside the others", d.written.some(w => /"unsplash":"abc123"/.test(w) && /"wallhaven":"w1"/.test(w)), JSON.stringify(d.written));
}
{
  const d = desk();
  d.give("abc123");
  d.lookup("{}", 0);                      // the first read, the keyring open
  check("with the keyring open, the first key given says saved once it is written", JSON.stringify(d.notices) === '["API key saved!"]' && d.written.length === 1,
    `${JSON.stringify(d.notices)}, ${d.written.length} written`);
}
{
  const d = desk(true);
  d.give("abc123");
  check("and a key given once the keyring was read says saved at once", JSON.stringify(d.notices) === '["API key saved!"]' && d.written.length === 1,
    `${JSON.stringify(d.notices)}, ${d.written.length} written`);
}
done();
