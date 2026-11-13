// The pomodoro after its length changes in Settings (services/TimerService.qml): the file's own length handler and
// pomodoroPaused run under node. A timer nobody started stays not paused (IslandController keeps the notch's timer row
// while one is), and one that was paused keeps the time it had left.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/TimerService.qml");
const at = src.indexOf("onPomodoroLapDurationChanged:");
const h = at < 0 ? "" : readExpression(src, at + "onPomodoroLapDurationChanged:".length).expr;
const paused = qmlProperty(src, "pomodoroPaused");

function timer({ left, secondsLeft }) {
  const t = { pomodoroRunning: false, pomodoroSecondsLeft: secondsLeft, pomodoroLapDuration: 1500 };
  const scope = Object.assign(t, { root: t, Persistent: { states: { timer: { pomodoro: { left } } } } });
  return {
    t,
    setLength(s) { t.pomodoroLapDuration = s; if (h) inScope(scope, "", h.startsWith("{") ? h.slice(1, -1) : h)(); },
    paused: () => inScope(scope, "", `return (${paused});`)(),
  };
}

console.log("== the pomodoro after its length changes (services/TimerService.qml)");
{
  const reset = timer({ left: 0, secondsLeft: 1500 });
  reset.setLength(1800);
  check("reset at 25:00, focus raised to 30 min in Settings: not paused, and 30:00 to go",
    !reset.paused() && reset.t.pomodoroSecondsLeft === 1800, `paused ${reset.paused()}, ${reset.t.pomodoroSecondsLeft} s`);
  const held = timer({ left: 600, secondsLeft: 600 });
  held.setLength(1800);
  check("paused at 10:00 and then the length changed: still paused at 10:00", held.paused() && held.t.pomodoroSecondsLeft === 600,
    `paused ${held.paused()}, ${held.t.pomodoroSecondsLeft} s`);
}
done();
