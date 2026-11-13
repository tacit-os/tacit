// Typing into a settings number box (modules/common/widgets/StyledSpinBox.qml): the field's own handlers run under
// node, with its "text: root.value" binding, a SpinBox that clamps to from..to, the Basic style's IntValidator, and a
// TextInput as Qt 6.12 has it (editingFinished only for text the validator accepts, Return then goes on). A number
// typed digit by digit must not be clamped on the way, nor saved before it is whole.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== typing into a number box (StyledSpinBox.qml)");
const src = read("modules/common/widgets/StyledSpinBox.qml");
const open = src.indexOf("{", src.indexOf("StyledTextInput {"));
const block = src.slice(open + 1, matchBrace(src, open));
const handlers = {};
for (const m of block.matchAll(/^ {12}((?:Keys\.)?on\w+)\s*:/gm))
  handlers[m[1]] = readExpression(block, m.index + m[0].length).expr;

// Settings > Services > update check interval: 60 to 1440 minutes, now 360
function box({ from = 60, to = 1440, value = 360 } = {}) {
  const saved = [];
  let v = value, text = "", binding = null;
  const root = {
    from, to,
    get value() { return v; },
    set value(n) {
      n = Math.max(from, Math.min(to, Math.trunc(n)));
      if (n === v) return;
      v = n;
      saved.push(n);   // ConfigSpinBox's onValueChanged writes Config
      if (binding) setText(String(binding()));
    },
  };
  const acceptable = t => /^[+-]?\d+$/.test(t) && +t >= from && +t <= to;
  // QIntValidator refuses a key that leaves no way to a number in range: not a digit, or more digits than "to" has
  const refused = t => !/^[+-]?\d*$/.test(t) || (+t > to && t.replace(/^[+-]/, "").length > String(to).length);
  const field = {
    root, activeFocus: false,
    Qt: { binding: f => ({ binding: f }) },
    get text() { return text; },
    set text(t) {   // a script's write: a binding replaces the one there, a value drops it
      if (t && t.binding) { binding = t.binding; setText(String(binding())); }
      else { binding = null; setText(String(t)); }
    },
  };
  const commit = qmlFunction(block, "commit");
  if (commit) field.commit = inScope(field, commit.params, commit.body);
  const run = {};
  for (const [name, expr] of Object.entries(handlers)) {
    run[name] = /^(\([^)]*\)|\w+)\s*=>/.test(expr) ? inScope(field, "", `return (${expr});`)()
      : inScope(field, "event", expr.startsWith("{") ? expr.slice(1, -1) : expr);
  }
  function setText(t) {
    if (t === text) return;
    text = t;
    run.onTextChanged?.();
  }
  binding = () => root.value;
  setText(String(binding()));
  const finished = () => { if (acceptable(text)) { run.onEditingFinished?.(); run.onAccepted?.(); } };
  return {
    saved, root,
    get text() { return text; },
    focus() { field.activeFocus = true; run.onActiveFocusChanged?.(); },
    // the person selects the number and types over it, one key at a time; what the field shows after each key
    type(keys) {
      const shown = [];
      [...keys].forEach((k, i) => {
        const next = i === 0 ? k : text + k;
        if (!refused(next)) setText(next);
        shown.push(text);
      });
      return shown;
    },
    empty() { setText(""); },
    enter() {
      const event = { key: "Return", accepted: true };
      if (run["Keys.onReturnPressed"]) run["Keys.onReturnPressed"](event); else event.accepted = false;
      if (!event.accepted) finished();
    },
    leave() { finished(); field.activeFocus = false; run.onActiveFocusChanged?.(); },
  };
}

{
  const b = box();
  b.focus();
  const shown = b.type("120");
  check("typing 1, 2, 0 over 360 shows 1, 12, 120", shown.join() === "1,12,120", `the field showed ${shown.join(", ")}`);
  check("nothing is saved while the number is being typed", b.saved.length === 0, `saved ${b.saved.join(", ")}`);
  b.enter();
  check("Enter takes 120 and saves it once", b.root.value === 120 && b.saved.join() === "120" && b.text === "120",
    `value ${b.root.value}, saved ${b.saved.join(", ")}, field "${b.text}"`);
}
{
  const b = box();
  b.focus(); b.type("120"); b.leave();
  check("leaving the field takes what was typed", b.root.value === 120 && b.saved.join() === "120",
    `value ${b.root.value}, saved ${b.saved.join(", ")}`);
}
{
  const b = box();
  b.focus(); b.type("1"); b.leave();
  check("a number below the minimum becomes the minimum when the field is left", b.root.value === 60 && b.text === "60",
    `value ${b.root.value}, field "${b.text}"`);
  const c = box();
  c.focus(); c.type("2000"); c.enter();
  check("one above the maximum becomes the maximum on Enter", c.root.value === 1440 && c.text === "1440",
    `value ${c.root.value}, field "${c.text}"`);
}
{
  const b = box();
  b.focus(); b.empty(); b.leave();
  check("an emptied field keeps the number and shows it again when left", b.root.value === 360 && b.text === "360" && b.saved.length === 0,
    `value ${b.root.value}, field "${b.text}"`);
}
{
  const b = box({ from: 0, to: 40, value: 8 });
  b.focus(); b.type("12"); b.root.value = 13;   // the + button
  check("the buttons still change the number shown", b.text === "13", `field "${b.text}"`);
}
done();
