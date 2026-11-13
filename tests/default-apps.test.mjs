// Settings › Default apps (scripts/settings/default_apps.py set): choosing another app for pictures, video, music or text
// must take over every type Tacit gives Viewer or Graphis (session/xdg/mimeapps.list), not only the first few, or a .mov,
// .svg or .md keeps opening in Tacit's app while Settings shows the other one. default_apps.py runs under python3 in a
// home of its own with one app of each kind and a pretend xdg-mime that writes down what it is asked to set.
import { execFileSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a default app chosen in Settings opens every type of its kind (scripts/settings/default_apps.py)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-default-apps-"));
const bin = join(tmp, "bin"), apps = join(tmp, "data/applications"), set = join(tmp, "set");
for (const d of [bin, apps, join(tmp, "none")]) mkdirSync(d, { recursive: true });
writeFileSync(join(bin, "xdg-mime"), `#!/bin/bash\n[ "$1" = default ] && { shift; printf '%s\\n' "$@" >> "$SET"; }\nexit 0\n`);
chmodSync(join(bin, "xdg-mime"), 0o755);

// what Tacit gives its own apps, by the role a person would choose another one under
const given = {};
for (const line of read("session/xdg/mimeapps.list").split("\n")) {
  const m = line.match(/^([\w.+-]+\/[\w.+-]+)=(viewer|graphis-file)\.desktop$/);
  if (!m) continue;
  const role = m[2] === "graphis-file" ? "text" : m[1] === "application/pdf" ? "pdf"
    : { image: "images", video: "video", audio: "music" }[m[1].split("/")[0]];
  (given[role] ??= []).push(m[1]);
}
const roles = { images: "image/png", video: "video/mp4", music: "audio/mpeg", pdf: "application/pdf", text: "text/plain" };

try {
  for (const [role, mime] of Object.entries(roles)) {
    writeFileSync(join(apps, `other-${role}.desktop`), `[Desktop Entry]\nType=Application\nName=Other ${role}\nExec=other %f\nMimeType=${mime};\n`);
    rmSync(set, { force: true });
    execFileSync("python3", ["-I", join(tree, "scripts/settings/default_apps.py"), "set", role, `other-${role}.desktop`], { env: {
      PATH: `${bin}:${process.env.PATH}`, HOME: join(tmp, "home"), XDG_DATA_HOME: join(tmp, "data"), XDG_DATA_DIRS: join(tmp, "none"), SET: set } });
    const lines = readFileSync(set, "utf8").trim().split("\n"), written = lines.slice(1);
    const missed = (given[role] ?? []).filter(t => !written.includes(t));
    check(`choosing another app for ${role} sets it for all ${given[role]?.length ?? 0} types Tacit gives its own`,
      lines[0] === `other-${role}.desktop` && given[role]?.length > 0 && missed.length === 0, `still Tacit's: ${missed.join(" ")}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
