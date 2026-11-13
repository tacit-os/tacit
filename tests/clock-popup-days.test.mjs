// The week strip in the bar clock's popup tells the days apart in every language Tacit has a table for
// (modules/ii/bar/ClockWidgetPopup.qml): the day label's own text binding (and the popup's dayLabels, when it has them)
// runs under Qt's qml tool offscreen for each locale, so the day names are Qt's own.
import { readdirSync } from "fs";
import { join } from "path";
import { qmlProperty, readExpression } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the clock popup's week strip in each language (ClockWidgetPopup.qml)");
const src = read("modules/ii/bar/ClockWidgetPopup.qml");
const textAt = src.indexOf("text:", src.indexOf("model: 7"));
const label = readExpression(src, textAt + "text:".length).expr;
const labels = qmlProperty(src, "dayLabels");
const inLocale = e => e.replace(/Qt\.locale\(\)/g, "Qt.locale(n)");
const locales = readdirSync(join(tree, "translations")).filter(f => /^[a-z]{2}_[A-Z]{2}\.json$/.test(f)).map(f => f.slice(0, 5));
const scene = `import QtQuick
Item {
    Component.onCompleted: {
        const out = {}
        for (const n of ${JSON.stringify(locales)}) {
            const root = {}
            ${labels === null ? "" : `root.dayLabels = (function () { ${labels.startsWith("{") ? inLocale(labels).slice(1, -1) : `return (${inLocale(labels)})`} })()`}
            const days = []
            for (let i = 0; i < 7; i++) { const date = new Date(2026, 10, 8 + i); days.push(${inLocale(label)}) }
            out[n] = days
        }
        console.log("DAYS " + JSON.stringify(out))
        Qt.quit()
    }
}
`;
try {
  const days = logged(runScene({ "days.qml": scene }), "DAYS");
  for (const n of locales) {
    const d = days[n], same = d.filter((x, i) => d.indexOf(x) !== i);
    check(`${n}: the seven days have seven labels`, same.length === 0, `${d.join(" ")}, repeated: ${[...new Set(same)].join(", ")}`);
  }
  check("in English they still read Su Mo Tu We Th Fr Sa", days.en_US.join(" ") === "Su Mo Tu We Th Fr Sa", days.en_US.join(" "));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
