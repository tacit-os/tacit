// The rail's "Now" rows in Pinax (FilesWindow.qml's onNow): the window's own handler, run under node on each kind of row
// FilesRail makes (a file that arrived, a download growing, a disk that appeared). A click on each does something. And
// the page of a folder on a drive that was pulled out, which says how to see it again.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a click on a row of the rail's Now does something (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const open = src.indexOf("{", src.indexOf("onNow: item =>"));
const parent = qmlFunction(read("services/Files.qml"), "parent");
const Files = { trim: p => p.replace(/\/+$/, "") || "/" };
Files.parent = inScope({ root: Files }, parent.params, parent.body);
function click(item) {
  const did = [];
  const scope = { Files, win: { show: (folder, select) => did.push(`show ${folder} ${select}`), go: p => did.push(`go ${p}`) },
    Jobs: { cancel: id => did.push(`cancel ${id}`) }, railView: { device: d => did.push(`device ${d.path}`) } };
  inScope(scope, "item", src.slice(open + 1, matchBrace(src, open)))(item);
  return did;
}

const part = "/home/a/Downloads/tacit-1.2.15.iso.part";
const download = { kind: "job", glyph: "downloading", text: "tacit-1.2.15.iso · 1.2 GB", job: { id: `download:${part}`, kind: "download", path: part, name: "tacit-1.2.15.iso" } };
check("a download's row shows the download in its folder", click(download).join() === `show /home/a/Downloads ${part}`, JSON.stringify(click(download)));
// a stick plugged in again: Tacit mounts nothing by itself, so it is listed with no mountpoint
const stick = { path: "/dev/sdb1", label: "STICK", size: "14G", mountpoint: "", usb: true, at: Date.now() };
const appeared = { kind: "device", glyph: "usb", text: "STICK appeared", dev: stick };
check("a disk that appeared opens on a click, mounted first as under Devices", click(appeared).join() === "device /dev/sdb1", JSON.stringify(click(appeared)));
const mounted = { ...appeared, dev: { ...stick, mountpoint: "/run/media/a/STICK" } };
check("one already mounted opens too", ["device /dev/sdb1", "go /run/media/a/STICK"].includes(click(mounted).join()), JSON.stringify(click(mounted)));

// the page of a folder on a drive that was pulled out says how to get back to it
const pageAt = src.indexOf("id: pageState");
const textAt = src.indexOf("{", src.indexOf("text:", pageAt));
const pageText = inScope({ win: { searching: false, gone: "/run/media/a/STICK", unreadable: false, folder: "/run/media/a/STICK/Photos" },
  pageState: { drive: "STICK" }, Files: { placeName: p => p.split("/").pop() } }, "", src.slice(textAt + 1, matchBrace(src, textAt)))();
check("the page of a pulled-out drive says to open it under Devices once it is back", /under Devices/.test(pageText), `it says "${pageText}"`);
done();
