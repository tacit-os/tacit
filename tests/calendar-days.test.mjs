// The desktop calendar's day names tell the days apart in every language Tacit has a table for, by the clock popup's
// rule (modules/ii/background/widgets/calendar/CalendarWidget.qml): its dayHeads binding runs under Qt's qml tool
// offscreen for each locale, with that locale's first day of the week, so the day names are Qt's own.
import { readdirSync } from "fs";
import { join } from "path";
import { qmlProperty } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the desktop calendar's day names in each language (CalendarWidget.qml)");
const src = read("modules/ii/background/widgets/calendar/CalendarWidget.qml");
const heads = qmlProperty(src, "dayHeads").replace(/Qt\.locale\(\)/g, "Qt.locale(n)");
const locales = readdirSync(join(tree, "translations")).filter(f => /^[a-z]{2}_[A-Z]{2}\.json$/.test(f)).map(f => f.slice(0, 5));
const scene = `import QtQuick
Item {
    Component.onCompleted: {
        const out = {}
        for (const n of ${JSON.stringify(locales)}) {
            const root = { weekStart: Qt.locale(n).firstDayOfWeek }
            out[n] = (function () { ${heads.slice(1, -1)} })()
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
    check(`${n}: the seven days have seven names`, d.length === 7 && same.length === 0, `${d.join(" ")}, repeated: ${[...new Set(same)].join(", ")}`);
  }
  check("in English they still read Su Mo Tu We Th Fr Sa", days.en_US.join(" ") === "Su Mo Tu We Th Fr Sa", days.en_US.join(" "));
  check("and in German, from Monday, Mo Di Mi Do Fr Sa So", days.de_DE.join(" ") === "Mo Di Mi Do Fr Sa So", days.de_DE.join(" "));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
