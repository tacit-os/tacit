// Praxis on files and folders (modules/claude/FileViewer.qml, SidePanel.qml, FolderModel.qml, SessionList.qml): a file
// followed in the side panel as it changes on disk, the panel's width, the rail's folders and the words of its rows. The
// files' own code runs under node; Quickshell's Process is played as its source (src/io/process.cpp) has it.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const viewerSrc = read("modules/claude/FileViewer.qml");

console.log("Praxis on files and folders (modules/claude/FileViewer.qml, SidePanel.qml, FolderModel.qml, SessionList.qml)");

// later-praxis-2 [6] a file growing fast: a second file-changed asks a second stat while the first runs. Quickshell stops
// the first (SIGTERM), and its stream still ends, with nothing in it, before the second starts: Number("") is 0, under
// 8 MB, so the whole file was loaded however large it had grown
{
  const h = viewerSrc.indexOf("{", viewerSrc.indexOf("onStreamFinished:", viewerSrc.indexOf("id: sizeProc")));
  const handler = viewerSrc.slice(h + 1, matchBrace(viewerSrc, h)).replace(/this\.text/g, "__text");
  const asked = qmlFunction(viewerSrc, "check");
  const run = ({ checks, says }) => {
    let reloads = 0;
    const viewer = { path: "/home/a/logs/build.log", isImage: false, readPath: "/home/a/logs/build.log", problem: "", loaded: true };
    // Process as Quickshell runs it: running is "a process exists"; false sends SIGTERM; true starts one only when none is
    // left, else once the old one has finished, after its stream has ended
    const sizeProc = { forPath: "", stale: false, command: [], proc: null, target: false,
      get running() { return this.proc !== null; },
      set running(v) { this.target = v; if (v) this.start(); else if (this.proc) this.proc.killed = true; },
      start() { if (this.proc || !this.target) return; this.target = false; this.proc = { killed: false }; } };
    const scope = { viewer, sizeProc, disk: { reload() { reloads++; } }, __text: "" };
    for (let i = 0; i < checks; i++) inScope(scope, asked.params, asked.body)();
    const out = [];
    for (const text of says) {
      const p = sizeProc.proc;
      sizeProc.proc = null;
      scope.__text = p.killed ? "" : text;
      inScope(scope, "", handler)();
      out.push({ reloads, problem: viewer.problem });
      sizeProc.start();
    }
    return out;
  };
  const twice = run({ checks: 2, says: ["", "9000000\n"] });
  check("a stat stopped for the next one says nothing: the file is not loaded, and the next one finds it too large",
    twice[0].reloads === 0 && twice[1].reloads === 0 && twice[1].problem === "Too large to show here.", JSON.stringify(twice));
  const once = run({ checks: 1, says: ["4096\n"] }), gone = run({ checks: 1, says: [""] });
  check("one stat that answers loads the file again, and one that fails (the file gone) still goes on to the read that says so",
    once[0].reloads === 1 && gone[0].reloads === 1, `${JSON.stringify(once)}, ${JSON.stringify(gone)}`);
}

// later-praxis-2 [7] a file with Windows line endings, changed on disk while open: take() placed the change by the
// string's positions, which count \r\n as two, while the view's document holds each as one line break, so the edit
// removed and inserted in the wrong place and every later one drifted further
{
  const take = qmlFunction(viewerSrc, "take"), patch = qmlFunction(viewerSrc, "patch");
  // the view's TextEdit: QTextCursor::insertText makes \r\n, \r and \n each one block break
  const area = { doc: "", readOnly: true,
    set text(v) { this.doc = v.replace(/\r\n?/g, "\n"); }, get text() { return this.doc; },
    remove(a, b) { this.doc = this.doc.slice(0, a) + this.doc.slice(b); },
    insert(at, v) { this.doc = this.doc.slice(0, at) + v.replace(/\r\n?/g, "\n") + this.doc.slice(at); } };
  const viewer = { text: "", problem: "", loaded: false, refreshMarks() {} };
  const codeLoader = { item: null, active: false };
  const scope = { viewer, codeLoader, area };
  viewer.take = inScope(scope, take.params, take.body);
  const lines = n => Array.from({ length: n }, (_, i) => `echo step ${i + 1}`);
  const before = lines(6), after = lines(6);
  after[3] = "echo step four, now with a note";
  viewer.take(before.join("\r\n") + "\r\n");
  area.text = viewer.text;   // the view, made with the text as it is (Component.onCompleted)
  codeLoader.item = { patch: inScope(scope, patch.params, patch.body), scrollTo() {}, flash() {} };
  viewer.take(after.join("\r\n") + "\r\n");
  after.push("echo step 7");
  viewer.take(after.join("\r\n") + "\r\n");
  const want = after.join("\n") + "\n";
  check("a CRLF file changed twice on disk reads as the file now is, each line once and in its place",
    area.text === want, JSON.stringify(area.text.split("\n").slice(2, 6)));
}

// later-praxis-2 [8] xdg-user-dirs turns a folder off by pointing it at home (XDG_MUSIC_DIR="$HOME/"), and Qt then gives
// home for it: the rail's folder names were written Home first and Music over it, so sessions in ~ sat under "Music"
{
  const fmSrc = read("modules/claude/FolderModel.qml");
  const names = dirs => {
    const url = p => `file://${p}`;
    const Directories = Object.fromEntries(Object.entries(Object.assign({ downloads: "/home/a/Downloads", documents: "/home/a/Documents",
      pictures: "/home/a/Pictures", music: "/home/a/Music", videos: "/home/a/Videos" }, dirs)).map(([k, v]) => [k, url(v)]));
    const FileUtils = { trimFileProtocol: u => String(u).replace(/^file:\/\//, "") };
    const e = qmlProperty(fmSrc, "placeNames");
    return inScope({ fm: { home: "/home/a" }, Directories, FileUtils }, "", e.startsWith("{") ? e.slice(1, -1) : `return (${e});`)();
  };
  const off = names({ music: "/home/a", videos: "/home/a" }), usual = names({});
  check("with Music and Videos pointed at home, home is still named Home; the other places keep their names",
    off["/home/a"] === "Home" && off["/home/a/Downloads"] === "Downloads" && usual["/home/a/Music"] === "Music" && usual["/home/a"] === "Home",
    `home is "${off["/home/a"]}"`);
}

// later-praxis-2 [17] the rail's search snippets and the open row's last reply took every _ # > out as markdown: a search
// for my_func_name showed "myfuncname" unhighlighted, and "use C# or x >= 5" read "use C or x = 5"
{
  const listSrc = read("modules/claude/SessionList.qml");
  const rail = {};
  const scope = { rail, Appearance: { colors: { colPrimary: "#p" } } };
  for (const f of ["unmarked", "markedSnippet", "replyOf"]) { const q = qmlFunction(listSrc, f); if (q) rail[f] = inScope(scope, q.params, q.body); }
  const hit = rail.markedSnippet("call my_func_name(x) when x >= 5", "my_func_name");
  const reply = rail.replyOf({ session: { lastReply: "## Done\n> Use C# or x >= 5, **not** `my_func` _yet_. See [the notes](notes.md)." } });
  check("a snippet keeps an identifier's underscores and a comparison, and the word searched for is lit",
    hit === 'call <font color="#p"><b>my_func_name</b></font>(x) when x &gt;= 5', hit);
  check("the last reply keeps C#, >= and my_func, and loses the heading, quote, bold, italic, code and link marks",
    reply === "Done Use C# or x >= 5, not my_func yet. See the notes.", reply);
}

// later-praxis-2 [18] a Text left at AutoText draws a string starting with a known tag as rich text: a session named from
// its prompt "<div> not centering" read " not centering" in the rail, and one named "<img> not loading" read nothing
{
  const listSrc = read("modules/claude/SessionList.qml");
  const formatOf = id => {
    const at = listSrc.indexOf(`id: ${id}\n`), open = listSrc.lastIndexOf("{", at);
    const item = at < 0 ? "" : listSrc.slice(open, matchBrace(listSrc, open) + 1);
    return (item.match(/\btextFormat:\s*([\w.]+)/) ?? [])[1] ?? "AutoText";
  };
  const got = ["title", "fullTitle", "nameText"].map(id => `${id} ${formatOf(id)}`);
  check("a session's title (one line and whole) and a folder's name are drawn as plain text",
    got.every(g => g.endsWith("Text.PlainText")), got.join(", "));
}

// later-praxis-2 [19] a file page on the Agents trail widens the panel to 640: a drag of its edge started from that width
// and wrote it as yours, so a few pixels' drag kept the panel 640 wide after Back and after a restart
{
  const src = read("modules/claude/SidePanel.qml");
  const at = src.indexOf("id: grip"), open = src.lastIndexOf("{", at), grip = src.slice(open, matchBrace(src, open) + 1);
  const on = name => { const i = grip.search(new RegExp(`\\b${name}:`)); return readExpression(grip, i + name.length + 1).expr; };
  const drag = ({ wantsWide, chosen, by }) => {
    let written = null;
    const agentsPane = { wantsWide };
    const side = { shownTab: "agents", chosenWidth: chosen, maxWidth: 1400 };
    const sscope = { side, agentsPane };
    const wideE = qmlProperty(src, "wide");
    if (wideE) Object.defineProperty(side, "wide", { get: () => inScope(sscope, "", `return (${wideE});`)() });
    Object.defineProperty(side, "wideBy", { get: () => inScope(sscope, "", `return (${qmlProperty(src, "wideBy")});`)() });
    const iw = readExpression(src, src.search(/\n\s*implicitWidth:/) + src.slice(src.search(/\n\s*implicitWidth:/)).indexOf(":") + 1).expr;
    Object.defineProperty(side, "implicitWidth", { get: () => inScope(sscope, "", `return (${iw});`)() });
    const g = { side, pressed: true, startX: 0, startWidth: 0, startChosen: 0, mapToGlobal: (x, y) => ({ x: x + 900, y }), widthFile: { setText(t) { written = t; } } };
    const run = (name, m) => inScope(g, "", `return (${on(name)});`)()(m);
    run("onPressed", { x: 0 });
    run("onPositionChanged", { x: by });
    const during = side.implicitWidth;
    g.pressed = false;
    inScope(g, "", `${on("onReleased")};`)();
    agentsPane.wantsWide = false;   // Back
    return { during, saved: written?.trim(), after: side.implicitWidth };
  };
  const nudge = drag({ wantsWide: true, chosen: 420, by: 3 }), wider = drag({ wantsWide: true, chosen: 420, by: -80 });
  const plain = drag({ wantsWide: false, chosen: 420, by: -30 }), was = drag({ wantsWide: true, chosen: 700, by: 100 });
  check("a few pixels' drag of a panel a file page holds at 640 leaves your width as it was: 420 after Back",
    nudge.during === 640 && nudge.saved === "420" && nudge.after === 420, JSON.stringify(nudge));
  check("dragged past 640 it is yours; without a file page a drag is as before; from 700 down to the floor, 640",
    wider.during === 720 && wider.saved === "720" && plain.saved === "450" && plain.during === 450 && was.during === 640 && was.saved === "640",
    `${JSON.stringify(wider)}, ${JSON.stringify(plain)}, ${JSON.stringify(was)}`);
}

done();
