// The You card shows a new account picture chosen while the desktop runs (modules/ii/background/widgets/usercard/
// UserCardWidget.qml): its picture's bindings and its file watch run under node. Settings (tacit-settings.qml) copies the
// new picture over ~/.face from its own process and leaves the settings as they were, so nothing but the file changes.
// Image loads a url once and keeps it, so the card has to know the file changed and ask with another url.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the You card after a new picture is chosen in Settings (UserCardWidget.qml)");
const pic = objectWith(read("modules/ii/background/widgets/usercard/UserCardWidget.qml"), "id: avatar");
const settings = read("tacit-settings.qml");
const expr = (block, key) => { const m = new RegExp(`^\\s*${key}:\\s*`, "m").exec(block); return m ? readExpression(block, m.index + m[0].length).expr : null; };

const Directories = { userAvatarPathRicersAndWeirdSystems: "/home/a/.face" };
function card(avatarPicture = "") {
  const avatar = {};
  const scope = { avatar, Config: { options: { profile: { avatarPicture, avatarPath: "/home/a/.face" } } }, Directories };
  for (const name of ["path", "version"]) {
    const e = qmlProperty(pic, name);
    if (e !== null) avatar[name] = inScope(scope, "", `return (${e});`)();
  }
  const source = () => String(inScope(scope, "", `return (${expr(pic, "source")});`)());
  // the file watches in the picture: { path, changed() }
  const watch = pic.includes("FileView {") ? objectWith(pic, "watchChanges:") : "";
  const watches = watch && /watchChanges:\s*true/.test(watch)
    ? { path: inScope(scope, "", `return (${expr(watch, "path")});`)(), changed: inScope(scope, "", `${expr(watch, "onFileChanged")};`) } : null;
  return { source, watches };
}

check("Settings still puts the new picture over ~/.face, the file the card shows", /cp -f "\$1" "\$2\/\.face"/.test(settings));
{
  const c = card(), before = c.source();
  check("the card watches the file it shows", c.watches?.path === "/home/a/.face", c.watches ? `it watches ${c.watches.path}` : "nothing watches it");
  c.watches?.changed();
  const after = c.source();
  check("once the file changes, the card asks for the picture again", after !== before && /^file:\/\/\/home\/a\/\.face\b/.test(after),
    `the url stays ${after}`);
}
{
  const c = card("/home/a/Pictures/me.png");
  check("a picture set in the settings file is the one shown and watched",
    c.source().startsWith("file:///home/a/Pictures/me.png") && c.watches?.path === "/home/a/Pictures/me.png", `${c.source()}, watching ${c.watches?.path}`);
}
done();
