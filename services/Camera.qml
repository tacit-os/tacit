pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.common

/**
 * Whether an app has the camera, for the notch's mark at rest (IslandController.ambientGlyph), as micLive is for the
 * mic. An app reaches it two ways: through PipeWire, as Thyris and the portal's apps do, which links a camera node to
 * the app's stream; or by opening a /dev/video* node itself, as apps that skip PipeWire do, which only
 * /proc shows, so it is looked for every few seconds. PipeWire and WirePlumber keep the nodes open while nothing
 * films, and a screen share is a video source too: neither counts.
 */
Singleton {
    id: root

    // a node of PipeWire's two camera plugins (libcamera_input.*, v4l2_input.*) linked to anything; a screen share's
    // node is named by its portal
    readonly property bool linked: Pipewire.linkGroups.values.some(group =>
        /^(libcamera|v4l2)_input\./.test(group.source?.name ?? ""))
    // an app other than PipeWire's own holds a /dev/video* node
    property bool held: false
    readonly property bool live: root.linked || root.held

    Timer {
        running: Config.options.island.enable
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!holders.running)
                holders.running = true;
        }
    }
    Process {
        id: holders
        command: ["bash", "-c", "for d in $(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' -printf '%h\\n' 2>/dev/null | sort -u); do\n"
            + "  case $(cat \"${d%/fd}/comm\" 2>/dev/null) in pipewire*|wireplumber|'') ;; *) echo held; exit 0 ;; esac\n"
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: root.held = text.trim() === "held"
        }
    }
}
