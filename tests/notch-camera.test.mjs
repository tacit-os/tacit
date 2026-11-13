// The camera's mark in the notch (services/Camera.qml, IslandController's ambientGlyph): Camera's PipeWire link test
// on pretend link groups and its /proc look under bash with a pretend find first on PATH (nothing reads this
// computer's processes), then the resting glyph's binding, all under node. A camera in use shows videocam by the mic's
// rules; PipeWire's own hold on the nodes and a screen share do not.
import { spawnSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the camera's mark in the notch (Camera.qml, IslandController.qml)");
let cam = "";
try { cam = read("services/Camera.qml"); } catch (e) {}
const controller = read("services/IslandController.qml");

// PipeWire: a camera node linked to an app's stream
{
  const expr = qmlProperty(cam, "linked");
  const linked = groups => expr !== null && inScope({ Pipewire: { linkGroups: { values: groups } } }, "", `return (${expr});`)();
  const link = (source, target) => ({ source: { name: source }, target: { name: target } });
  check("a libcamera camera linked to an app's stream is the camera in use",
    linked([link("libcamera_input._base_soc_0_cci_ac15000_i2c-bus_0_camera_36", "thyris-camera")]) === true);
  check("so is a V4L2 one", linked([link("v4l2_input.pci-0000_00_14.0-usb-0_6_1.0", "WEBRTC VoiceEngine")]) === true);
  check("a screen share and the mic are not",
    linked([link("xdph-streaming-1", "thyris"), link("alsa_input.pci-0000_00_1f.3.analog-stereo", "WEBRTC VoiceEngine")]) === false);
  check("nothing linked, no camera", linked([]) === false);
}

// /proc: who holds a /dev/video* node, PipeWire's own processes aside
{
  const m = /command:\s*(\["bash"[\s\S]*?\])\s*\n\s*stdout:/.exec(cam);
  const command = m ? inScope({}, "", `return (${m[1]});`)() : null;
  const dir = mkdtempSync(join(tmpdir(), "notch-camera-"));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const held = holders => {
    const procs = holders.map((comm, i) => {
      const p = join(dir, "proc", String(100 + i));
      mkdirSync(join(p, "fd"), { recursive: true });
      writeFileSync(join(p, "comm"), comm + "\n");
      return join(p, "fd");
    });
    // the pretend find answers what the real one would: the fd folders with a link to /dev/video*
    writeFileSync(join(bin, "find"), `#!/bin/bash\nprintf '%s\\n' ${procs.map(p => `'${p}'`).join(" ")}\n`);
    chmodSync(join(bin, "find"), 0o755);
    if (!command) return null;
    const r = spawnSync(command[0], command.slice(1), { encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    rmSync(join(dir, "proc"), { recursive: true, force: true });
    return r.stdout.trim() === "held";
  };
  check("WirePlumber keeping the node open while nothing films is not the camera in use", held(["wireplumber"]) === false);
  check("nor PipeWire's own", held(["pipewire", "pipewire-pulse"]) === false);
  check("Firefox holding it is", held(["wireplumber", "firefox"]) === true);
  check("nobody holding it, no camera", held([]) === false);
  rmSync(dir, { recursive: true, force: true });
}

// the resting glyph
{
  const expr = qmlProperty(controller, "ambientGlyph");
  const quiet = {
    Audio: { source: { audio: { muted: false } }, sink: { name: "alsa_output" } }, AgentSessions: { waiting: false, justDone: false, sessions: [] },
    Claude: { waiting: false }, Notifications: { silent: false, unread: 0 }, Battery: { available: false }, Vpn: { connected: false },
    Idle: { inhibit: false }, DropShelf: { items: [] }, Hyprsunset: { temperatureActive: false }, Updates: { restartDue: false },
  };
  const glyph = ({ camera, mic = false, muted = false }) => inScope({
    ...quiet, Audio: { ...quiet.Audio, source: { audio: { muted } } }, Camera: { live: camera },
    root: { chargerFault: false, micLive: mic, prReviews: [], activityAmbient: false, diskPct: 10, memoryFull: false, workUnsaved: false },
  }, "", expr.slice(1, -1))();
  check("an app filming shows the camera's mark at rest", glyph({ camera: true }) === "videocam", glyph({ camera: true }));
  check("a call with the mic too keeps the mic's mark, muted or not",
    glyph({ camera: true, mic: true }) === "mic" && glyph({ camera: true, mic: true, muted: true }) === "mic_off");
  check("no camera, no mark", glyph({ camera: false }) === "");
}
done();
