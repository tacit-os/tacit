// Open on an app in Apps (store.qml): the capsule says "Opening" until the app's window comes up, then Open again, so an
// app closed by mistake can be opened again at once; while it is still starting a second press does nothing, as before.
// The window's own launch() and its handler for the list of windows run under node, the windows and launcher entries
// stood in for, the window known by its entry as AppScope.hasWindow knows it.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("store.qml");
const at = src.indexOf("target: ToplevelManager.toplevels");
const onValues = at < 0 ? null : (() => { const open = src.indexOf("{", src.indexOf("function onValuesChanged()", at)); return src.slice(open + 1, matchBrace(src, open)); })();

const started = [];
const toplevels = { values: [] };
const entries = { "org.kde.krita": { id: "org.kde.krita", execute: () => started.push("krita") } };
const root = { opening: "", openingId: "", openingTimer: { restart() {} }, notOpen() {} };
const scope = Object.assign(root, { root, openingTimer: root.openingTimer,
  DesktopEntries: { byId: id => entries[id] ?? null, heuristicLookup: appId => ({ krita: entries["org.kde.krita"], firefox: { id: "firefox" } })[appId] ?? null },
  ToplevelManager: { toplevels } });
const f = qmlFunction(src, "launch");
const launch = inScope(scope, f.params, f.body);
const windows = appIds => { toplevels.values = appIds.map(appId => ({ appId })); if (onValues) inScope(scope, "", onValues)(); };
const krita = { pkg: "krita", desktop: "org.kde.krita.desktop" };

console.log("== Open on an app, once its window has come up (store.qml)");
launch(krita);
windows(["firefox"]);
launch(krita);
check("starting, another app's window comes up: still Opening, and a second press does nothing", root.opening === "krita" && started.length === 1,
  `"${root.opening}", started ${started.length}`);
windows(["firefox", "krita"]);
check("Krita's window comes up: the capsule says Open", root.opening === "", `"${root.opening}"`);
windows(["firefox"]);
launch(krita);
check("closed again by mistake: Open starts it again", started.length === 2 && root.opening === "krita", `started ${started.length}, "${root.opening}"`);
done();
