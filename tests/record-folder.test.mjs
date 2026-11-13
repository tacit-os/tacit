// Where a screen recording is saved when Settings has no folder for it (scripts/videos/record.sh): the account's
// Videos folder by its own name, which the recorder's folder button opens (Directories.videos), not a new English
// ~/Videos beside it. record.sh runs under bash in a home of its own whose Videos folder is called Vidéos, with a
// pretend wf-recorder that writes a few bytes where it is told, and a pretend xdg-user-dir.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== a recording with no folder set goes to the account's own Videos folder (scripts/videos/record.sh)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-record-folder-"));
const bin = join(tmp, "bin");
mkdirSync(bin);
const tools = {
  "wf-recorder": `#!/bin/bash\nwhile [ $# -gt 0 ]; do [ "$1" = -f ] && printf x > "$2"; shift; done\n`,
  "xdg-user-dir": `#!/bin/bash\n[ "$1" = VIDEOS ] && echo "$VIDEOS_DIR" || echo "$HOME"\n`,
  pgrep: "#!/bin/sh\nexit 1\n", ffmpeg: "#!/bin/sh\nexit 1\n", "notify-send": "#!/bin/sh\n",
};
for (const [name, text] of Object.entries(tools)) { writeFileSync(join(bin, name), text); chmodSync(join(bin, name), 0o755); }

try {
  // where a recording went, with this config (null for none) and this answer from xdg-user-dir
  const recorded = (config, videosDir) => {
    const home = mkdtempSync(join(tmp, "home-"));
    const state = join(home, ".local/state/quickshell/states.json");
    mkdirSync(dirname(state), { recursive: true });
    writeFileSync(state, '{"record":{}}');
    if (config !== null) {
      mkdirSync(join(home, ".config/illogical-impulse"), { recursive: true });
      writeFileSync(join(home, ".config/illogical-impulse/config.json"), JSON.stringify(config));
    }
    const r = spawnSync("bash", [join(tree, "scripts/videos/record.sh"), "--fullscreen", "--output", "DP-1"], {
      encoding: "utf8", timeout: 20000,
      env: { PATH: `${bin}:${process.env.PATH}`, HOME: home, XDG_RUNTIME_DIR: home, VIDEOS_DIR: videosDir.replace("~", home) },
    });
    const file = JSON.parse(readFileSync(state, "utf8")).record.file ?? "";
    return { home, rc: r.status, file: file.replace(home, "~"), there: existsSync(file), videos: existsSync(join(home, "Videos")) };
  };
  for (const [what, config] of [["savePath cleared in Settings", { screenRecord: { savePath: "" } }], ["no config yet", null]]) {
    const r = recorded(config, "~/Vidéos");
    check(`${what}: the recording is in ~/Vidéos and no ~/Videos is made`,
      r.rc === 0 && r.there && r.file.startsWith("~/Vidéos/Screen recording ") && !r.videos, `exit ${r.rc}: ${r.file}, ~/Videos made: ${r.videos}`);
  }
  {
    const custom = join(tmp, "Mine");
    const r = recorded({ screenRecord: { savePath: custom } }, "~/Vidéos");
    check("a folder set in Settings is still used", r.rc === 0 && r.there && r.file.startsWith(`${custom}/Screen recording `), r.file);
  }
  {
    const r = recorded(null, "~");
    check("with Videos turned off in xdg-user-dirs (it names home) it is ~/Videos, as before", r.rc === 0 && r.there && r.file.startsWith("~/Videos/"), `${r.file}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
