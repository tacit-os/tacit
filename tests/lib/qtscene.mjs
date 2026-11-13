// Runs QML under Qt's own tools offscreen, in a folder of its own: a scene with the tree's blocks in it, beside stand-in
// modules for the shell's singletons and types. With a TestCase it runs under qmltestrunner, whose clicks, keys and
// pointer moves go through Qt's own delivery as a person's do, so Qt decides which item takes them. No desktop is used.
import { spawnSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { matchBrace } from "./qml.mjs";

const tool = name => [`/usr/lib/qt6/bin/${name}`, ...(process.env.PATH ?? "").split(":").map(d => join(d, name))].find(existsSync) ?? name;

// files: { "tst_scene.qml": text, "qs/qmldir": text, ... }, the scene first; what the run printed
export function runScene(files, { env = {} } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "tacit-scene-"));
  try {
    for (const [path, text] of Object.entries(files)) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      writeFileSync(join(dir, path), text);
    }
    const scene = join(dir, Object.keys(files)[0]);
    const test = /^\s*TestCase\s*\{/m.test(Object.values(files)[0]);
    const r = spawnSync(tool(test ? "qmltestrunner" : "qml"), test ? ["-platform", "offscreen", "-import", dir, "-input", scene] : ["-I", dir, scene],
      { encoding: "utf8", timeout: 30000, cwd: dir,
        env: { PATH: process.env.PATH, HOME: dir, LANG: "en_US.UTF-8", QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1", ...env } });
    return `${r.stdout ?? ""}${r.stderr ?? ""}${r.error ? r.error.message : ""}`;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// what the scene logged as "<tag> <json>"; throws with the start of what it said when it logged nothing so
export function logged(out, tag) {
  const line = out.split("\n").find(l => l.includes(`${tag} `));
  if (!line) throw new Error(`Qt said: ${out.trim().split("\n").filter(l => !/^(PASS|Totals|\*|Config)/.test(l)).slice(0, 4).join(" | ")}`);
  return JSON.parse(line.slice(line.indexOf(`${tag} `) + tag.length + 1));
}

// a module folder: "qs/modules/common" with singletons { Config: "QtObject { ... }" }, as a files entry set
export function module(name, singletons = {}, types = {}) {
  const dir = name.replace(/\./g, "/"), files = {};
  const lines = [`module ${name}`];
  for (const [n, body] of Object.entries(singletons)) {
    lines.push(`singleton ${n} 1.0 ${n}.qml`);
    files[`${dir}/${n}.qml`] = `pragma Singleton\nimport QtQuick\n${body}\n`;
  }
  for (const [n, body] of Object.entries(types)) {
    lines.push(`${n} 1.0 ${n}.qml`);
    files[`${dir}/${n}.qml`] = `import QtQuick\n${body}\n`;
  }
  files[`${dir}/qmldir`] = lines.join("\n") + "\n";
  return files;
}

// the QML object, type name to closing brace, whose own lines hold marker ("id: menuCard")
export function objectWith(src, marker) {
  const at = src.indexOf(marker);
  if (at < 0) throw new Error(`no ${marker}`);
  for (let i = at, depth = 0; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{" && depth-- === 0) {
      const start = src.slice(0, i).search(/[\w.]+\s*$/);
      return src.slice(start, matchBrace(src, i) + 1);
    }
  }
  throw new Error(`no object holds ${marker}`);
}

// block without its child objects of the given types (a widget's loaders, an overlay's visuals)
export function without(block, ...types) {
  let out = block;
  for (const type of types) {
    for (let m; (m = new RegExp(`\\n(\\s*)${type}\\s*\\{`).exec(out.slice(out.indexOf("{") + 1)));) {
      const at = out.indexOf("{") + 1 + m.index, open = out.indexOf("{", at + 1);
      out = out.slice(0, at) + out.slice(matchBrace(out, open) + 1);
    }
  }
  return out;
}
