// Settings > About > Updates, "Checked ..." (tacit-settings.qml checkedText): the binding runs under node with the
// tree's Voice.qml (its day words) on checks of different ages. A check from another day says which day: the background
// check skips a metered link or a low battery without a word, and "Checked at 14:05" from four days ago read as today.
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== when About says the last check was (tacit-settings.qml checkedText)");
const voiceSrc = read("services/Voice.qml");
const Voice = {};
for (const p of ["weekdays", "months"]) Voice[p] = inScope({}, "", `return (${qmlProperty(voiceSrc, p)});`)();
for (const f of ["daysAgo", "clock", "when"]) { const fn = qmlFunction(voiceSrc, f); Voice[f] = inScope({ root: Voice, Qt }, fn.params, fn.body); }
const two = n => String(n).padStart(2, "0");
var Qt = { formatTime: d => `${two(d.getHours())}:${two(d.getMinutes())}` };

const expr = qmlProperty(read("tacit-settings.qml"), "checkedText");
const body = expr.startsWith("{") ? expr.slice(1, matchBrace(expr, 0)) : `return (${expr});`;
// now: Friday 13 November 2026, 16:00
const now = new Date(2026, 10, 13, 16, 0).getTime();
const said = at => inScope({ Updates: { lastChecked: at }, updatesGroup: { now, state: {} }, Voice, Qt }, "", body)();

check("a check minutes ago says how long ago", said(now - 5 * 60000) === "Checked 5 min ago", said(now - 5 * 60000));
check("one earlier today says the time", said(new Date(2026, 10, 13, 9, 12).getTime()) === "Checked at 09:12", said(new Date(2026, 10, 13, 9, 12).getTime()));
check("one yesterday says yesterday", said(new Date(2026, 10, 12, 14, 5).getTime()) === "Checked yesterday at 14:05", said(new Date(2026, 10, 12, 14, 5).getTime()));
check("one this week says the day", said(new Date(2026, 10, 9, 14, 5).getTime()) === "Checked Monday at 14:05", said(new Date(2026, 10, 9, 14, 5).getTime()));
check("one older says the date", said(new Date(2026, 9, 30, 14, 5).getTime()) === "Checked on 30 Oct", said(new Date(2026, 9, 30, 14, 5).getTime()));
done();
