// Config.migrate() on the settings files past releases left behind (tests/config/releases, from git): an updated
// computer must come out with what this release means, not only a new install. 1.2.14 changed "Loudest allowed" from 99
// to 100 and every file already holding 99 kept it, so the volume stopped at 99% everywhere but on new installs.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { adapterDefaults, leaves, loadInto, runMigrate } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const releases = join(dirname(fileURLToPath(import.meta.url)), "config", "releases");
const index = JSON.parse(readFileSync(join(releases, "index.json"), "utf8"));
const oldFile = name => JSON.parse(readFileSync(join(releases, name), "utf8"));

const src = read("modules/common/Config.qml");
const defaults = adapterDefaults(src);
const migrate = file => runMigrate(src, loadInto(defaults, file));
const fresh = migrate({});                       // a new install: the defaults written, read back and migrated
const now = fresh.version;
const TACIT_APPS = ["praxis", "org.quickshell", "foot", "thyris", "graphis", "settings"];
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// the settings whose value differs from a new install's after the update, leaving out the ones the person set
function stuck(options, set = []) {
  const a = leaves(options), b = leaves(fresh.options);
  return Object.keys(b).filter(k => !set.includes(k) && !same(a[k], b[k])).map(k => `${k} is ${JSON.stringify(a[k])}, a new install has ${JSON.stringify(b[k])}`);
}

console.log(`Config.migrate() on old settings files (this Config.qml writes version ${now})`);
const groups = new Map();
for (const e of index) groups.set(e.file, [...(groups.get(e.file) ?? []), e.version]);

for (const [file, versions] of groups) {
  const old = oldFile(file);
  const from = `${versions.join(", ")} (v${old.configVersion})`;

  // as the release left it
  const r = migrate(structuredClone(old));
  const o = r.options, why = [];
  const writes = old.configVersion < now ? 1 : 0;
  if (o.configVersion !== now || r.wrote !== writes) why.push(`version ${o.configVersion}, written ${r.wrote} times, not ${writes}`);
  if (o.audio.protection.maxAllowed !== 100) why.push(`Loudest allowed ${o.audio.protection.maxAllowed}, not 100`);
  if (!same(o.dock.pinnedApps, TACIT_APPS)) why.push(`the dock holds ${JSON.stringify(o.dock.pinnedApps)}`);
  why.push(...stuck(o, ["configVersion", "audio.protection.maxAllowed", "dock.pinnedApps"]));
  check(`${from}: comes out as a new install would`, !why.length, why.join("; "));

  // lived in: a wallpaper, an app of the person's own pinned after foot, Graphis taken off, Loudest allowed 95
  const mine = structuredClone(old);
  mine.background.wallpaperPath = "/home/someone/Pictures/beach.jpg";
  mine.dock.pinnedApps = ["praxis", "org.quickshell", "foot", "org.mozilla.firefox", "thyris", "settings"];
  mine.audio.protection.maxAllowed = 95;
  const m = migrate(mine).options, whyMine = [];
  if (m.background.wallpaperPath !== "/home/someone/Pictures/beach.jpg") whyMine.push(`the wallpaper is ${JSON.stringify(m.background.wallpaperPath)}`);
  const pins = m.dock.pinnedApps;
  if (pins[pins.indexOf("foot") + 1] !== "org.mozilla.firefox") whyMine.push(`the person's pin moved: ${JSON.stringify(pins)}`);
  // Tacit's apps came back once, at version 4; one taken off after that stays off
  const graphis = old.configVersion < 4;
  if (pins.includes("graphis") !== graphis) whyMine.push(`Graphis ${graphis ? "did not come back" : "came back"}: ${JSON.stringify(pins)}`);
  if (m.audio.protection.maxAllowed !== 95) whyMine.push(`Loudest allowed 95 became ${m.audio.protection.maxAllowed}`);
  whyMine.push(...stuck(m, ["background.wallpaperPath", "dock.pinnedApps", "audio.protection.maxAllowed"]));
  check(`${from}, lived in: keeps the person's wallpaper, pins and limit`, !whyMine.length, whyMine.join("; "));
}

// a limit the person chose is theirs: 150 from an old file, and a 99 set after this migration
const loud = structuredClone(oldFile(index.find(e => e.version === "1.2.13").file));
loud.audio.protection.maxAllowed = 150;
check("Loudest allowed 150 in an old file stays 150", migrate(loud).options.audio.protection.maxAllowed === 150);
const chosen = migrate({ ...structuredClone(fresh.options), audio: { protection: { enable: true, maxAllowedIncrease: 10, maxAllowed: 99 } } });
check(`a 99 chosen in a version ${now} file stays 99, and the file is not written`, chosen.options.audio.protection.maxAllowed === 99 && chosen.wrote === 0,
  `${chosen.options.audio.protection.maxAllowed}, written ${chosen.wrote} times`);
const again = migrate(structuredClone(migrate(structuredClone(oldFile("lived.json"))).options));
check("a migrated file migrates to itself, unwritten", same(again.options, migrate(structuredClone(oldFile("lived.json"))).options) && again.wrote === 0);
// a newer build's file (a build tried and left, or a dev checkout beside the installed shell): its stamp stays, unwritten
const newer = migrate({ ...structuredClone(fresh.options), configVersion: now + 1 });
check(`a file stamped ${now + 1} by a newer build keeps its stamp and is not written`, newer.options.configVersion === now + 1 && newer.wrote === 0,
  `version ${newer.options.configVersion}, written ${newer.wrote} times`);

done();
