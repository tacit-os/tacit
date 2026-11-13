// Which pull requests the notch marks "review requested from you" (bin/notch-prs), run under bash with a pretend gh:
// one pull request asking a team, one asking you, and `gh api user` (who you are) failing, as a rate limit or a token
// refresh between the calls makes it, and then answering.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== review requested from you (bin/notch-prs)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-notch-prs-"));
try {
  const bin = join(tmp, "bin"), run = join(tmp, "run");
  mkdirSync(bin); mkdirSync(run);
  const prs = [
    { number: 7, title: "Team review", state: "OPEN", url: "u7", updatedAt: "2026-11-13T09:00:00Z", statusCheckRollup: [],
      reviewRequests: [{ __typename: "Team", name: "core", slug: "core" }] },
    { number: 8, title: "Yours", state: "OPEN", url: "u8", updatedAt: "2026-11-13T09:00:00Z", statusCheckRollup: [],
      reviewRequests: [{ __typename: "User", login: "sam" }] },
  ];
  writeFileSync(join(tmp, "prs.json"), JSON.stringify(prs));
  writeFileSync(join(bin, "gh"), `#!/bin/sh
case "$1 $2" in
"auth status") exit 0 ;;
"pr list") cat "${join(tmp, "prs.json")}" ;;
"api user") [ -n "$ME" ] || exit 1; echo "$ME" ;;
esac
`, { mode: 0o755 });
  writeFileSync(join(bin, "busctl"), '#!/bin/sh\necho "b false"\n', { mode: 0o755 });
  const poll = me => Object.fromEntries(spawnSync("bash", [join(tree, "bin/notch-prs"), "acme/app"], { encoding: "utf8",
    env: { PATH: `${bin}:${process.env.PATH}`, XDG_RUNTIME_DIR: run, ME: me } }).stdout.split("\n").filter(Boolean)
    .map(l => JSON.parse(l)).map(p => [p.number, p.review]));

  const failed = poll("");
  check("who you are not known: a pull request asking a team is not marked as asking you", failed[7] === false, JSON.stringify(failed));
  check("who you are not known: nor is any other", failed[8] === false, JSON.stringify(failed));
  const known = poll("sam");
  check("known: the one asking you is marked, the team's is not", known[8] === true && known[7] === false, JSON.stringify(known));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
