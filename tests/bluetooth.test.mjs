// Bluetooth switched off, over a restart (services/BluetoothStatus.qml): its own togglePower() and keepChoice() run under
// node with a pretend adapter, and the state file's defaults read from modules/common/Persistent.qml. A restart is a new
// BluetoothStatus and a new adapter that BlueZ has powered on (AutoEnable), with the state file kept.
import { adapterDefaults, inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/BluetoothStatus.qml");
const stateDefaults = adapterDefaults(read("modules/common/Persistent.qml"));

// the shell starting, with this state file and Persistent read (ready) or not yet: { root, adapter, toggle, ready() }
function start(states, ready = true) {
  const adapter = { enabled: true };
  const Persistent = { ready, states };
  const root = { seenAdapters: [] };
  const scope = { root, Bluetooth: { defaultAdapter: adapter }, Persistent };
  for (const name of ["togglePower", "keepChoice"]) {
    const f = qmlFunction(src, name);
    root[name] = f ? inScope(scope, f.params, f.body) : () => {};
  }
  root.keepChoice();
  return { adapter, toggle: root.togglePower, ready() { Persistent.ready = true; root.keepChoice(); } };
}

console.log("Bluetooth switched off, over a restart (services/BluetoothStatus.qml)");

check("the state file has a place for it", stateDefaults.bluetooth?.off === false, JSON.stringify(stateDefaults.bluetooth));
const states = structuredClone(stateDefaults);
states.bluetooth ??= {};
{
  const first = start(states);
  check("a new install: Bluetooth is on", first.adapter.enabled);
  first.toggle();
  const next = start(states);
  check("switched off in Settings, it is off after a restart", !next.adapter.enabled, `on, the state file says ${JSON.stringify(states.bluetooth)}`);
  next.toggle();
  const again = start(states);
  check("switched on again, it is on after a restart", again.adapter.enabled);
}
{
  const s = structuredClone(states);
  s.bluetooth.off = true;
  const late = start(s, false);
  const before = late.adapter.enabled;
  late.ready();
  check("off, with the state file read after the adapter shows: off once it is read", before && !late.adapter.enabled);
  late.adapter.enabled = true;   // switched on by another program (bluetoothctl) after that
  late.ready();
  check("switched on afterwards by another program, it is left on", late.adapter.enabled);
}

done();
