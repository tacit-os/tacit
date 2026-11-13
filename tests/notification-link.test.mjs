// The link a notification's row opens (modules/common/functions/NotificationUtils.qml, firstLink() and urlPattern, which
// Notifications.linkFor() hands to Qt.openUrlExternally): its own code under node on bodies a script, an agent or an app
// sends. A file's name is not a site.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the link a notification opens (NotificationUtils.firstLink)");
const src = read("modules/common/functions/NotificationUtils.qml");
const scope = { urlPattern: inScope({}, "", `return (${qmlProperty(src, "urlPattern")});`)() };
const f = qmlFunction(src, "firstLink");
const firstLink = inScope(scope, f.params, f.body);

for (const [body, want] of [
  ["Finished install.sh", ""],
  ["Saved backup.sh in your home", ""],
  ["Edit app.config to change it", ""],
  ["Wrote report.de.pdf", ""],
  ["Read notes.dev.md first", ""],
  ["Docs at github.com/tacit-os/tacit.", "https://github.com/tacit-os/tacit"],
  ["Visit example.com.", "https://example.com"],
  ["Ask claude.ai", "https://claude.ai"],
  ["Get it from https://brew.sh", "https://brew.sh"],
  ["See www.example.sh/page", "https://www.example.sh/page"],
  ['Open <a href="https://example.org/a?b=1&amp;c=2">this</a>', "https://example.org/a?b=1&c=2"],
]) {
  const got = firstLink(body);
  check(`"${body}" ${want ? `opens ${want}` : "has no link"}`, got === want, `firstLink gives ${JSON.stringify(got)}`);
}

done();
