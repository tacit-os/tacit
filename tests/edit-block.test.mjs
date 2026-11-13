// Graphis's one-step edits (native/edit/editblock.cpp, Tacit.Edit), built here with g++ and moc around a small harness
// (tests/lib/edit_block.cpp) and run offscreen on a TextEdit's own document: two inserts at one offset, which the
// comment toggle sends for an empty line in a CSS, HTML or Markdown file (CodeDoc.toggleComment), and edits at several.
// Without a compiler, Qt's headers or KSyntaxHighlighting's, it is not built and says so.
import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Graphis's one-step edits (native/edit/editblock.cpp)");
const sh = cmd => spawnSync("sh", ["-c", cmd], { encoding: "utf8" });
const moc = ["/usr/lib/qt6/moc", "/usr/lib/qt6/libexec/moc"].find(existsSync);
const ksh = "/usr/include/KF6/KSyntaxHighlighting";
const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "edit_block.cpp");
const qt = "Qt6Quick Qt6Qml Qt6Gui Qt6Core";
const missing = [sh("command -v g++").status ? "g++" : "", moc ? "" : "moc", sh(`pkg-config --exists ${qt}`).status ? "Qt 6's headers" : "",
  existsSync(ksh) ? "" : "KSyntaxHighlighting's headers"].filter(Boolean);
if (missing.length) {
  console.log(`  skip  not built here: no ${missing.join(", ")}`);
} else {
  const tmp = mkdtempSync(join(tmpdir(), "tacit-edit-block-"));
  try {
    const src = join(tree, "native/edit"), harness = join(tmp, "harness");
    const built = sh(`${moc} $(pkg-config --cflags-only-I ${qt}) '${src}/editblock.h' -o '${tmp}/moc_editblock.cpp' && ` +
      `g++ -std=c++20 -fPIC -O0 -I'${src}' $(pkg-config --cflags ${qt}) -I${ksh} '${helper}' '${src}/editblock.cpp' ` +
      `'${tmp}/moc_editblock.cpp' -o '${harness}' $(pkg-config --libs ${qt}) -lKF6SyntaxHighlighting`);
    check("the harness builds", built.status === 0, built.stderr.trim().split("\n").slice(-3).join(" | "));
    const apply = (text, edits) => spawnSync(harness, [text, JSON.stringify(edits)], { encoding: "utf8",
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_LOGGING_RULES: "*.warning=false" } }).stdout;
    if (built.status === 0) {
      for (const [what, text, edits, want] of [
        ["an empty line's comment marks", "a {\n\n}", [[4, 4, "/* "], [4, 4, " */"]], "a {\n/*  */\n}"],
        ["a blank line's, after its spaces", "  \nb", [[2, 2, "<!-- "], [2, 2, " -->"]], "  <!--  -->\nb"],
        ["three inserts at one offset", "ab", [[1, 1, "1"], [1, 1, "2"], [1, 1, "3"]], "a123b"],
        ["a line's comment marks", "p { }", [[0, 0, "/* "], [5, 5, " */"]], "/* p { } */"],
        ["edits at several offsets, in any order", "hello world", [[11, 11, ">"], [0, 0, "<"], [5, 6, "_"]], "<hello_world>"],
      ]) {
        const got = apply(text, edits);
        check(`${what}: ${JSON.stringify(want)}`, got === want, `gave ${JSON.stringify(got)}`);
      }
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
done();
