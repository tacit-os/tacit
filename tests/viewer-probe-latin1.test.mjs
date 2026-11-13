// The Viewer's facts for a photo (scripts/viewer/probe.py facts) when one of its EXIF tags holds a byte that is not
// UTF-8: exiv2 prints an Ascii tag as it is, so a camera's Latin-1 Copyright ("\xa9 2020") reaches the probe raw. The
// probe runs under python3 with a pretend exiv2 that prints what the real one prints for such a JPEG, in a home of its own.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== a photo with a Latin-1 byte in its EXIF keeps its facts (scripts/viewer/probe.py)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-probe-latin1-"));
writeFileSync(join(tmp, "exiv2"), `#!/bin/bash
if [ "$2" = -Pkt ]; then
  printf 'Exif.Image.Make                              Canon\\n'
  printf 'Exif.Image.Model                             Canon EOS 5D\\n'
  printf 'Exif.Image.Copyright                         \\xa9 2020 Jo\\n'
  printf 'Exif.Photo.DateTimeOriginal                  2020:06:01 10:20:30\\n'
else
  printf 'File name       : %s\\nImage size      : 4368 x 2912\\nCopyright       : \\xa9 2020 Jo\\n' "$3"
fi
`);
chmodSync(join(tmp, "exiv2"), 0o755);
const photo = join(tmp, "IMG_0001.JPG");
writeFileSync(photo, "not read: exiv2 here is pretend");

try {
  const r = spawnSync("python3", ["-I", join(tree, "scripts/viewer/probe.py"), "facts", photo],
    { encoding: "utf8", env: { PATH: `${tmp}:${process.env.PATH}`, HOME: tmp } });
  let f = {};
  try { f = JSON.parse(r.stdout); } catch (e) {}
  check("no error", !f.error, f.error ?? r.stderr.trim());
  check("its pixel size, camera and date are read", f.w === 4368 && f.h === 2912 && f.exif?.make === "Canon" && f.exif?.model === "Canon EOS 5D" && f.exif?.taken === "2020:06:01 10:20:30",
    JSON.stringify(f));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
