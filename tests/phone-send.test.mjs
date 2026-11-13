// Send to phone (scripts/phone/phone-link.py send): the daemon is handed a file:// URL and reads it as one, so a name with
// #, ? or % in it must be encoded or it asks for another file. phone-link.py runs under python3 with a pretend busctl
// that says the phone is reachable and writes down the URL it was handed, which is read back as a URL.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Send to phone hands the daemon the file that was chosen (scripts/phone/phone-link.py)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-phone-send-"));
const bin = join(tmp, "bin"), docs = join(tmp, "Documents"), sent = join(tmp, "sent");
for (const d of [bin, docs]) mkdirSync(d);
writeFileSync(join(bin, "busctl"), `#!/bin/bash
case " $* " in
  *" get-property "*) echo '{"type":"b","data":true}' ;;
  *" shareUrl "*) for a; do u=$a; done; printf '%s' "$u" > "$SENT" ;;
esac
`);
chmodSync(join(bin, "busctl"), 0o755);

try {
  for (const name of ["Invoice #12.pdf", "what?.txt", "100% done.txt", "a%20b.txt", "naïve résumé.pdf"]) {
    const path = join(docs, name);
    writeFileSync(path, "x");
    rmSync(sent, { force: true });
    let rc = 0;
    try {
      execFileSync("python3", ["-I", join(tree, "scripts/phone/phone-link.py"), "send", "dev1", path],
        { env: { PATH: `${bin}:${process.env.PATH}`, SENT: sent }, stdio: ["ignore", "ignore", "pipe"] });
    } catch (e) { rc = e.status; }
    const url = existsSync(sent) ? readFileSync(sent, "utf8") : "";
    let back = "";
    try { back = fileURLToPath(new URL(url)); } catch (e) { back = `(${e.code ?? e.message})`; }
    check(`"${name}" is sent as itself`, rc === 0 && back === path, `exit ${rc}, handed ${JSON.stringify(url)}, read as ${back}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
