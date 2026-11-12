// The login screen's keyboard (session/sddm/tacit-login-ground): the weston.ini its own main() writes on a throwaway
// root, through tests/lib/login_ground.py. The greeter must type in the layout the person uses at the lock: the one
// chosen in Settings, else Setup's, and a pair of layouts must be switchable there.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the login screen's keyboard (session/sddm/tacit-login-ground)");
const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "login_ground.py");
const ini = (vconsole, config) => {
  const r = spawnSync("python3", ["-I", "-B", helper, join(tree, "session/sddm/tacit-login-ground"), vconsole, config ? JSON.stringify(config) : ""], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return Object.fromEntries(r.stdout.split("\n").filter(l => l.includes("=")).map(l => l.split("=")));
};
const conf = (kbLayout, configVersion = 5) => ({ configVersion, hyprland: { input: { kbLayout } } });
{
  const k = ini("XKBLAYOUT=us\n", conf("de"));
  check("installed with us, German chosen in Settings: the greeter types German", k.keymap_layout === "de", JSON.stringify(k));
}
{
  const k = ini("XKBLAYOUT=de\nXKBVARIANT=nodeadkeys\n", conf(""));
  check("nothing chosen in Settings: Setup's layout and variant", k.keymap_layout === "de" && k.keymap_variant === "nodeadkeys", JSON.stringify(k));
}
{
  const k = ini("XKBLAYOUT=de\n", conf("us", 4));
  check("an old settings file's \"us\" (the old default) is not taken for a choice", k.keymap_layout === "de", JSON.stringify(k));
}
{
  const k = ini("XKBLAYOUT=de\nXKBVARIANT=nodeadkeys\n", conf("fr"));
  check("a layout chosen in Settings does not take Setup's variant", k.keymap_layout === "fr" && !k.keymap_variant, JSON.stringify(k));
}
{
  const k = ini("XKBLAYOUT=us,ru\nXKBOPTIONS=grp:alt_shift_toggle\n", conf(""));
  check("a pair of layouts can be switched at the greeter", k.keymap_layout === "us,ru" && k.keymap_options === "grp:alt_shift_toggle", JSON.stringify(k));
}
{
  const k = ini("XKBLAYOUT=de\n", conf("xx"));
  check("a layout this computer does not have falls back to Setup's", k.keymap_layout === "de", JSON.stringify(k));
}
done();
