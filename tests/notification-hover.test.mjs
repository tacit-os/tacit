// A notification popup and the pointer (modules/common/widgets/NotificationGroup.qml): the group's own hover handler
// run under node against services/Notifications.qml's own cancelTimeout() and timeoutNotification() and its timer's
// handler. A pointer that crosses a popup must not take it away; a critical one (no clock) stays until dealt with.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== notification popups and the pointer (NotificationGroup.qml)");
const group = read("modules/common/widgets/NotificationGroup.qml"), service = read("services/Notifications.qml");

function desk(withTimer) {
  const svc = { list: [], timeout() {} };
  const timer = withTimer ? { running: true, restarts: 0, stop() { this.running = false; }, restart() { this.running = true; this.restarts++; } } : null;
  const n = { notificationId: 7, popup: true, leaving: false, replyActive: false, timer };
  svc.list.push(n);
  // a LeaveTimer runs out after the slide (Notifications.qml): the popup is gone
  const sscope = { root: svc, leaveTimerComponent: { createObject: () => { n.popup = false; n.leaving = false; } } };
  for (const name of ["cancelTimeout", "timeoutNotification"]) {
    const f = qmlFunction(service, name);
    svc[name] = inScope(sscope, f.params, f.body);
  }
  const g = { popup: true, containsMouse: false, notifications: [n] };
  const at = group.indexOf("onContainsMouseChanged:");
  const block = readExpression(group, at + "onContainsMouseChanged:".length).expr;
  const hover = inScope({ root: g, Notifications: svc }, "", block.slice(1, -1));
  const move = over => { g.containsMouse = over; hover(); };
  return { n, svc, move };
}
{
  const d = desk(false);    // critical: interval 0, no clock
  d.move(true); d.move(false);
  check("a critical popup the pointer crossed stays up", d.n.popup === true);
}
{
  const d = desk(true);
  d.move(true);
  check("resting on a popup stops its clock", d.n.timer.running === false);
  d.move(false);
  check("leaving it starts the clock again, and the popup stays until it runs out", d.n.popup === true && d.n.timer.running === true);
  d.svc.timeoutNotification(7);   // its clock runs out (NotifTimer)
  check("then it goes", d.n.popup === false);
}
done();
