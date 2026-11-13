// The bar's dark/light buttons start the colour script with its path as the program, not spliced into a bash -c line
// (modules/ii/bar/UtilButtons.qml): each button's onClicked runs under node, light and dark, with the shell installed
// under a path that has a space in it, and what it hands Quickshell.execDetached is compared with a list of arguments.
import { inScope, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the bar's dark/light buttons start switchwall.sh (UtilButtons.qml)");
const src = read("modules/ii/bar/UtilButtons.qml");
const script = "/home/a/my shell/scripts/colors/switchwall.sh";
for (const id of ["darkModeM3", "legacyDarkMode"]) {
  const block = objectWith(src, `id: ${id}`);
  const clicked = readExpression(block, block.indexOf("onClicked:") + "onClicked:".length).expr;
  for (const darkmode of [true, false]) {
    const ran = [];
    inScope({ Appearance: { m3colors: { darkmode } }, Directories: { wallpaperSwitchScriptPath: script },
      Quickshell: { execDetached: argv => ran.push(argv) } }, "", `return (${clicked});`)()({});
    const want = [script, "--mode", darkmode ? "light" : "dark", "--noswitch"];
    check(`${id}, ${darkmode ? "dark" : "light"} now: the script's path is the program, whole`, JSON.stringify(ran) === JSON.stringify([want]),
      JSON.stringify(ran));
  }
}
done();
