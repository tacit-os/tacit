pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio?.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node.nickname || node.description || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    // The default sink is null between a sink disappearing and the next one arriving, and a
    // volume key pressed in that window must do nothing rather than throw.
    function toggleMute() {
        if (!Audio.sink?.audio) return;
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    function toggleMicMute() {
        if (!Audio.source?.audio) return;
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    // What the volume keys may reach: the "Loudest allowed" setting (up to hardMaxValue), or 100% with the protection off
    readonly property real keyMaxValue: Config.options.audio.protection.enable
        ? Math.min(root.hardMaxValue, Config.options.audio.protection.maxAllowed / 100) : 1

    function incrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.max(0, Math.min(root.keyMaxValue, Audio.sink.audio.volume + step));
    }
    
    function decrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.max(0, Math.min(root.keyMaxValue, Audio.sink.audio.volume - step));
    }

    // A bar pressed far above the level (the control panel's): the protection below takes back any rise over "Largest
    // jump allowed at once", every time, so the level is climbed to in steps under that instead, as a drag would and as
    // Settings > Sound's bar does. Down, or with the protection off, it is one write.
    property var climbAudio: null
    property real climbTarget: 0
    property real climbWrote: 0
    function setVolume(value) {
        if (!root.sink?.audio) return;
        root.climbAudio = root.sink.audio;
        root.climbTarget = value;
        root.climbWrote = root.climbAudio.volume;
        root.climbVolume();
    }
    function climbVolume() {
        const audio = root.climbAudio;
        // another output now, or the last step was taken back since: stop where it is
        if (!audio || audio !== root.sink?.audio || audio.volume < root.climbWrote - 0.005) {
            volumeClimb.stop();
            return;
        }
        const p = Config.options.audio.protection;
        // a little under the limit: the level is kept as a float, a hair off what was written
        const step = p.enable ? p.maxAllowedIncrease / 100 * 0.9 : Infinity;
        const was = audio.volume;
        audio.volume = Math.min(root.climbTarget, was + step);
        root.climbWrote = audio.volume;
        // there, or taken back at once (over "Loudest allowed")
        if (Math.abs(audio.volume - root.climbTarget) < 0.005 || audio.volume <= was) volumeClimb.stop();
        else volumeClimb.start();
    }
    Timer {
        id: volumeClimb
        interval: 50
        repeat: true
        onTriggered: root.climbVolume()
    }

    // The volume keys (keybinds.lua) go through these, so they stop where "Loudest allowed" says: they ran wpctl with
    // its own limit of 100% (-l 1.0), which stays only for when the shell is not there to answer.
    IpcHandler {
        target: "audio"
        function volumeUp(): void {
            root.incrementVolume();
        }
        function volumeDown(): void {
            root.decrementVolume();
        }
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    // ---------------------------------------------------------------- headphones that arrive
    // A pinned default beats WirePlumber's own switching, and this desk pins the tuned speaker
    // chain (EQ, limiter, echo canceller). So a headset could connect, get a working sink, and
    // every app would carry on playing to the laptop speakers. Hand the output to a Bluetooth
    // sink when one appears, and give it back to whatever was playing before when it leaves.
    // Only the shell hands it over (shell.qml sets handsOver): Settings loads this file too, and a copy that started
    // with the headset already on had nothing memorised, so as it left it released the pin the shell had just put back.
    property bool handsOver: false
    property PwNode sinkBeforeBluetooth: null
    readonly property var bluetoothSink: {
        for (const n of Pipewire.nodes.values)
            if (n.isSink && !n.isStream && (n.name + "").startsWith("bluez_output."))
                return n;
        return null;
    }
    onBluetoothSinkChanged: {
        if (!root.handsOver)
            return;
        if (root.bluetoothSink) {
            // The pin reads null whenever its configured name resolves to no live node, so fall
            // back to the effective default; and never memorise a Bluetooth node, or one headset
            // of two leaving would hand the output to the other instead of the speakers.
            const previous = Pipewire.preferredDefaultAudioSink ?? Pipewire.defaultAudioSink;
            if (previous && !((previous.name + "").startsWith("bluez_output.")))
                root.sinkBeforeBluetooth = previous;
            Pipewire.preferredDefaultAudioSink = root.bluetoothSink;
        } else {
            // Release the pin even with nothing memorised: leaving it on a departed headset is
            // what strands the default away from the tuned chain. Only while the pin is still a
            // headset's (null once its node has gone): an output chosen since stays.
            const pin = Pipewire.preferredDefaultAudioSink;
            if (!pin || (pin.name + "").startsWith("bluez_output."))
                Pipewire.preferredDefaultAudioSink = root.sinkBeforeBluetooth;
            root.sinkBeforeBluetooth = null;
        }
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source, root.bluetoothSink, root.sinkBeforeBluetooth]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        property var seenAudio: null
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            // A new default sink starts from its own level, not the old device's
            if (seenAudio !== sink.audio) {
                seenAudio = sink.audio;
                lastReady = false;
                lastVolume = 0;
            }
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("a jump over %1%").arg(Config.options.audio.protection.maxAllowedIncrease));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("the limit is %1%").arg(Config.options.audio.protection.maxAllowed));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
