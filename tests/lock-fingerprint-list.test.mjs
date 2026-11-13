// Whether the lock offers the fingerprint (modules/common/panels/lock/LockContext.qml and BootLockContext.qml): each
// one's fprintd-list command runs under bash in a German session, with a pretend fprintd-list first on PATH that
// translates its heading as a gettext-translated tool does (LANGUAGE, then LC_ALL, LC_MESSAGES and LANG; none of them
// in the C locale), and the output goes through the context's own onStreamFinished.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the fingerprint is offered in any language (fprintd-list)");
const dir = mkdtempSync(join(tmpdir(), "tacit-fprintd-"));
try {
  writeFileSync(join(dir, "fprintd-list"), `#!/bin/bash
loc=\${LC_ALL:-\${LC_MESSAGES:-$LANG}}
case "$loc" in C | C.* | POSIX) lang=C ;; *) lang=\${LANGUAGE:-$loc} ;; esac
case "$lang" in
de*) printf 'Fingerabdrücke für Benutzer %s auf Synaptics (press):\\n - #0: right-index-finger\\n' "$1" ;;
*) printf 'Fingerprints for user %s on Synaptics (press):\\n - #0: right-index-finger\\n' "$1" ;;
esac
`);
  chmodSync(join(dir, "fprintd-list"), 0o755);
  const env = { PATH: `${dir}:${process.env.PATH}`, LANG: "de_DE.UTF-8", LANGUAGE: "de", HOME: dir };

  for (const file of ["modules/common/panels/lock/LockContext.qml", "modules/common/panels/lock/BootLockContext.qml"]) {
    const src = read(file);
    const at = src.indexOf("id: fingerprintCheckProc");
    const command = inScope({}, "", `return (${readExpression(src, src.indexOf("command:", at) + 8).expr});`)();
    const handler = readExpression(src, src.indexOf("onStreamFinished:", at) + 17).expr.slice(1, -1);
    const root = { fingerprintsConfigured: false };
    const text = execFileSync(command[0], command.slice(1), { env, encoding: "utf8" });
    inScope({ root, fingerprintOutputCollector: { text } }, "", handler)();
    check(`${file.split("/").pop()}: a German session with a finger enrolled offers the fingerprint`, root.fingerprintsConfigured === true,
      `fprintd-list said ${JSON.stringify(text.split("\n")[0])}`);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
