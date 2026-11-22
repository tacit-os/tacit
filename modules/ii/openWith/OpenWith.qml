pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

/**
 * Window for "Open with". tacit-portal's AppChooser asks the bridge for kind "open.choose" (params in
 * OpenWithContent.qml); this shows it over the window that asked and answers. Dialogs wait while the screen is
 * locked (DialogBridge.asking).
 */
Scope {
    id: root

    Component.onCompleted: {
        DialogBridge.claim("open.choose");
    }
    Component.onDestruction: {
        DialogBridge.unclaim("open.choose");
    }

    readonly property bool wanted: DialogBridge.asking && DialogBridge.current.kind === "open.choose"
    property var ask: null
    property bool up: false

    onWantedChanged: {
        if (wanted) {
            ask = DialogBridge.current;
            up = true;
        } else {
            up = false;
        }
    }

    Connections {
        target: DialogBridge
        function onCurrentChanged() {
            // finish() has folded the window; an ask queued behind the answered one needs it back
            if (root.wanted) {
                root.ask = DialogBridge.current;
                root.up = true;
            }
        }
    }

    function finish(result): void {
        const id = root.ask?.id;
        root.up = false;
        if (!id) return;
        root.ask = null;
        if (result) DialogBridge.answer(id, result);
        else DialogBridge.refuse(id, "cancelled");
    }

    LazyLoader {
        active: root.up
        PanelWindow {
            id: win
            readonly property var req: root.ask?.params ?? ({})
            screen: Quickshell.screens.find(s => Hyprland.monitorFor(s)?.id === req.asker?.monitor) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.namespace: "quickshell:openWith"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { left: true; right: true; top: true; bottom: true }

            OpenWithContent {
                anchors.fill: parent
                request: win.req
                monitorX: win.screen?.x ?? 0
                monitorY: win.screen?.y ?? 0
                Component.onCompleted: forceActiveFocus()
                onDone: result => root.finish(result)
                onCancelled: root.finish(null)
            }
        }
    }
}
