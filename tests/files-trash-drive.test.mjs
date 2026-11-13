// A stick's trash in Files' Trash view: services/Files.qml's trash counter (its own bash command, run over a home of
// its own and a pretend stick mounted in it, and its onStreamFinished), FilesWindow.qml's trashOf(), crumbs, the
// folder model's rebuild() and restoreSelection() under node, and scripts/files/job.sh restore under bash with what
// restoreSelection asked for. gio trash puts a file deleted on a stick in <top>/.Trash-UID, whose records give the
// path from the stick's top; stat is wrapped so the pretend stick is a mount.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a stick's trash in the Trash view (Files.qml, FilesWindow.qml, job.sh restore)");
const files = read("services/Files.qml"), win_ = read("modules/ii/files/FilesWindow.qml"), devices = read("services/Devices.qml");
const tmp = mkdtempSync(join(tmpdir(), "tacit-trash-drive-"));
const fn = (src, name) => qmlFunction(src, name);

try {
  const home = join(tmp, "home"), homeTrash = join(home, ".local/share/Trash"), stick = join(tmp, "media/STICK"), bin = join(tmp, "bin");
  const stickTrash = join(stick, `.Trash-${process.getuid()}`);
  for (const d of [join(homeTrash, "files"), join(homeTrash, "info"), join(stick, "DCIM"), join(stickTrash, "files"), join(stickTrash, "info"), bin])
    mkdirSync(d, { recursive: true });
  writeFileSync(join(homeTrash, "files", "old.txt"), "x");
  writeFileSync(join(homeTrash, "info", "old.txt.trashinfo"), `[Trash Info]\nPath=${join(home, "old.txt")}\n`);
  for (const n of ["IMG_1.jpg", "IMG 2.jpg"]) {
    writeFileSync(join(stickTrash, "files", n), n);
    writeFileSync(join(stickTrash, "info", `${n}.trashinfo`), `[Trash Info]\nPath=DCIM/${encodeURIComponent(n)}\nDeletionDate=2026-11-13T10:00:00\n`);
  }
  writeFileSync(join(bin, "stat"), `#!/bin/bash\nif [ "$1" = -c ] && [ "$2" = %m ]; then for a in "$@"; do case "$a" in "${stick}"|"${stick}"/*) echo "${stick}"; exit 0 ;; esac; done; fi\nexec /usr/bin/stat "$@"\n`);
  chmodSync(join(bin, "stat"), 0o755);

  // ---- Files: the count and the drives' trashes
  const dev = { path: "/dev/sdb1", name: "sdb1", label: "", mountpoint: stick, size: "14.9G", usb: true, loop: false };
  const Devices = { list: [dev] };
  Devices.nameFor = inScope({ root: Devices }, fn(devices, "nameFor").params, fn(devices, "nameFor").body);
  const F = { trashDir: join(homeTrash, "files"), trashCount: 0, driveTrashes: [] };
  const fscope = { root: F, Devices, StringUtils: { shellSingleQuoteEscape: s => s.replace(/'/g, "'\\''") } };
  if (fn(files, "driveOf")) F.driveOf = inScope(fscope, fn(files, "driveOf").params, fn(files, "driveOf").body);
  const counterAt = files.lastIndexOf("Process {", files.indexOf("id: trashCounter"));
  const counter = files.slice(counterAt, matchBrace(files, counterAt + "Process ".length) + 1);
  const cmd = inScope(fscope, "", `return (${readExpression(counter, counter.indexOf("command:") + "command:".length).expr});`)();
  const out = execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8" });
  const finished = /onStreamFinished:\s*\{/.exec(counter);
  const body = finished ? counter.slice(finished.index + finished[0].length, matchBrace(counter, finished.index + finished[0].length - 1))
    : `root.trashCount = parseInt(text.trim()) || 0`;
  inScope({ ...fscope, text: out }, "", body)();
  check("the rail's count has what is in the stick's trash too", F.trashCount === 3, `count ${F.trashCount}`);
  check("and Files knows the stick's trash by the stick's name", JSON.stringify(F.driveTrashes) === JSON.stringify([{ name: "USB 14.9G", path: join(stickTrash, "files"), count: 2 }]),
    JSON.stringify(F.driveTrashes));

  // ---- the window
  const ran = [];
  // FileUtils' own, which cantList and the window's rows ask
  const fileUtils = {};
  for (const name of ["fileUrl", "folderUrl", "listedPath"]) { const f = fn(read("modules/common/functions/FileUtils.qml"), name); if (f) fileUtils[name] = inScope({ root: fileUtils }, f.params, f.body); }
  const win = { trashDir: F.trashDir, home, folder: F.trashDir, selectedPaths: [], cursorPath: "", run: (op, items) => ran.push([op, items]), clearSelection() {} };
  const Files = { ...F, parent: inScope({ root: { trim: p => p.replace(/\/+$/, "") } }, fn(files, "parent").params, fn(files, "parent").body),
    placeName: p => p.split("/").pop(), driveOf: F.driveOf ?? (() => null),
    cantList: fn(files, "cantList") ? inScope({ FileUtils: fileUtils }, fn(files, "cantList").params, fn(files, "cantList").body) : () => "" };
  const wscope = { win, Files, Devices, FileUtils: fileUtils, Things: { kindOf: () => "image" } };
  const bindWin = () => {
    if (fn(win_, "trashOf")) win.trashOf = inScope(wscope, fn(win_, "trashOf").params, fn(win_, "trashOf").body);
    const inTrash = inScope(wscope, "", `return (${qmlProperty(win_, "inTrash")});`), trashRoot = qmlProperty(win_, "trashRoot");
    Object.defineProperty(win, "trashRoot", { configurable: true, get: () => (trashRoot ? inScope(wscope, "", `return (${trashRoot});`)() : "") });
    Object.defineProperty(win, "inTrash", { configurable: true, get: inTrash });
    Object.defineProperty(win, "atTrashRoot", { configurable: true, get: inScope(wscope, "", `return (${qmlProperty(win_, "atTrashRoot")});`) });
  };
  bindWin();
  const crumbs = () => inScope(wscope, "", qmlProperty(win_, "crumbs").replace(/^\{|\}$/g, ""))().map(c => c.name);
  for (const name of ["kindGroup", "passesFilter", "compareRows"]) { const f = fn(win_, name); win[name] = inScope(wscope, f.params, f.body); }
  Object.assign(win, { grouped: "", sortField: 0, sortReversed: false, kindOrder: [], fKinds: [], fWhen: "", fSize: "" });
  wscope.FolderListModel = { Name: 0, Time: 1, Size: 2, Type: 3 };
  const rows = folder => {
    win.folder = folder;
    const names = execFileSync("ls", ["-1A", folder], { encoding: "utf8" }).split("\n").filter(Boolean);
    const raw = { count: names.length, get: (i, role) => ({ fileName: names[i], filePath: join(folder, names[i]), fileIsDir: false, fileSize: 1, fileModified: new Date() })[role] };
    const model = {};
    const reb = fn(win_, "rebuild");
    inScope({ ...wscope, raw, folderModel: model }, reb.params, reb.body)();
    return model.rows ?? [];
  };
  const atRoot = rows(F.trashDir);
  const row = atRoot.find(r => r.fileName === "USB 14.9G");
  check("the Trash view's root lists the stick's trash as a folder under the stick's name, beside the home trash's file",
    !!row && row.fileIsDir && row.filePath === join(stickTrash, "files") && atRoot.some(r => r.fileName === "old.txt"), JSON.stringify(atRoot.map(r => r.fileName)));
  const inside = rows(join(stickTrash, "files"));
  check("opened, it is the trash: its root, read as Trash › USB 14.9G", win.inTrash && win.atTrashRoot && JSON.stringify(crumbs()) === JSON.stringify(["Trash", "USB 14.9G"])
    && inside.length === 2, `inTrash ${win.inTrash}, at its root ${win.atTrashRoot}, crumbs ${JSON.stringify(crumbs())}, ${inside.length} rows`);
  const upTo = [];
  inScope({ ...wscope, win: { ...win, folder: join(stickTrash, "files"), atTrashRoot: true, go: f => upTo.push(f) } }, "", fn(win_, "up").body)();
  check("and up from it is the Trash, as its crumbs read", upTo[0] === F.trashDir, JSON.stringify(upTo));
  win.folder = F.trashDir;
  check("the home trash still reads Trash", win.atTrashRoot && JSON.stringify(crumbs()) === JSON.stringify(["Trash"]), JSON.stringify(crumbs()));

  // Put back, there
  const restore = fn(win_, "restoreSelection");
  const putBack = (folder, picked) => {
    win.folder = folder;
    win.selectedPaths = picked;
    ran.length = 0;
    inScope(wscope, restore.params, restore.body)();
    return ran[0]?.[1] ?? null;
  };
  const items = putBack(join(stickTrash, "files"), [join(stickTrash, "files", "IMG 2.jpg")]);
  const env = { PATH: `${bin}:${process.env.PATH}`, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_STATE_HOME: join(home, ".local/state") };
  let r = { state: "not run" };
  if (items) {
    execFileSync("bash", [join(tree, "scripts/files/job.sh"), "pb", "restore", ...items], { env });
    r = JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs/pb.json"), "utf8"));
  }
  check("Put back there puts the photo back where it was on the stick", r.state === "done" && existsSync(join(stick, "DCIM", "IMG 2.jpg"))
    && !existsSync(join(stickTrash, "files", "IMG 2.jpg")) && !existsSync(join(stickTrash, "info", "IMG 2.jpg.trashinfo")), `asked ${JSON.stringify(items)}: ${r.state} ${r.error ?? ""}`);
  check("at the home trash's root the stick's own trash is not a thing to put back", putBack(F.trashDir, [join(stickTrash, "files")]) === null, JSON.stringify(ran));
  // nor renamed, deleted or offered anything but Open there: it holds the drive's own trash
  win.folder = F.trashDir;
  win.isDriveTrash = fn(win_, "isDriveTrash") ? inScope(wscope, fn(win_, "isDriveTrash").params, fn(win_, "isDriveTrash").body) : () => false;
  const asked = [];
  win.selectedPaths = [join(stickTrash, "files"), join(F.trashDir, "old.txt")];
  inScope({ ...wscope, win: { ...win, askDelete: p => asked.push(p) } }, "", fn(win_, "deleteSelection").body)();
  check("Delete for good at the trash's root leaves the stick's trash out", JSON.stringify(asked) === JSON.stringify([[join(F.trashDir, "old.txt")]]), JSON.stringify(asked));
  let menu;
  try {
    menu = inScope({ ...wscope, win: { ...win, pathAt: () => join(stickTrash, "files") }, folderModel: { get: () => true } }, fn(win_, "actionsFor").params, fn(win_, "actionsFor").body)(0).map(a => a.id);
  } catch (e) {
    menu = [`a folder's menu (${e.message})`];
  }
  check("its row offers Open, nothing that would rename, put back or delete it", JSON.stringify(menu) === JSON.stringify(["open"]), JSON.stringify(menu));
  let editing = -1;
  inScope({ ...wscope, win: { ...win, pathAt: () => join(stickTrash, "files"), rowShown: () => true, searching: false, view: "list", selectOnly() {},
    set editingIndex(v) { editing = v; } }, folderModel: { count: 1 } }, fn(win_, "renameAt").params, fn(win_, "renameAt").body)(0);
  check("and F2 does not rename it", editing === -1, `editing row ${editing}`);
  check("and the home trash's own are still put back by name", JSON.stringify(putBack(F.trashDir, [join(F.trashDir, "old.txt")])) === JSON.stringify(["old.txt"]), JSON.stringify(ran));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
