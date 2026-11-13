// The rail's "Now" rows leave once they are no longer news (modules/ii/files/FilesRail.qml): the rail's own nowItems
// and its timer run under qmltestrunner offscreen with a download that arrived 89.5 s ago, then the timer's tick after
// its 90 s have run out.
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the rail's Now forgets a download once its minute and a half is up (FilesRail.qml)");
const src = read("modules/ii/files/FilesRail.qml");
const from = src.indexOf("    // What is happening this minute");
const to = src.indexOf("\n", src.indexOf("Timer { interval: 15000", from));
const block = src.slice(from, to);
const scene = `import QtQuick
import QtTest
import qs.services
Item {
    id: rail
${block}
    TestCase {
        name: "now"; when: windowShown
        function test_age() {
            const before = rail.nowItems.length;
            let timer = null;
            for (let i = 0; i < rail.data.length; i++) if (rail.data[i].interval === 15000) timer = rail.data[i];
            wait(700);                // past the download's 90 s
            timer.triggered();        // the timer's next tick
            console.log("NOW " + JSON.stringify({ before, after: rail.nowItems.length }));
        }
    }
}
`;
const stubs = module("qs.services", {
  Jobs: `QtObject { property var running: []; function label(j) { return "" } }`,
  Recents: `QtObject { property var items: [{ kind: "download", text: "report.pdf", path: "/home/a/Downloads/report.pdf", at: Date.now() - 89500 }] }`,
  Devices: `QtObject { property var list: []; function glyphFor(d) { return "" } function nameFor(d) { return "" } }`,
});
try {
  const r = logged(runScene({ "tst_now.qml": scene, ...stubs }), "NOW");
  check("a download that just arrived is in Now", r.before === 1, `${r.before} rows`);
  check("after its 90 s, the next tick takes it out", r.after === 0, `${r.after} rows still`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
