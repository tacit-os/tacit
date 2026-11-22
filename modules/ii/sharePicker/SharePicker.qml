pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

/**
 * Window for the screen-share picker. tacit-share-picker (xdph's custom_picker_binary) asks the bridge for
 * kind "share.pick" (params in SharePickerContent.qml); this shows it on the asking window's monitor and
 * answers. Dialogs wait while the screen is locked (DialogBridge.asking).
 *
 * It is also the thing loaded at startup that references DialogBridge, which keeps that singleton connected.
 */
Scope {
    id: root

    Component.onCompleted: {
        DialogBridge.claim("share.pick");
    }
    Component.onDestruction: {
        DialogBridge.unclaim("share.pick");
    }

    readonly property bool wanted: DialogBridge.asking && DialogBridge.current.kind === "share.pick"
    // the ask being shown, held so the window can finish closing after the answer
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

    // a second ask queued behind the first replaces it the moment the first is answered
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
            screen: Quickshell.screens.find(s => s.name === win.req.monitor) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.namespace: "quickshell:sharePicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { left: true; right: true; top: true; bottom: true }

            SharePickerContent {
                id: content
                anchors.fill: parent
                request: win.req
                Component.onCompleted: { forceActiveFocus(); enterTimer.start(); }
                onDone: result => root.finish(result)
                onCancelled: root.finish(null)
            }
            Timer { id: enterTimer; interval: 250; onTriggered: content.entered = true }
        }
    }
}
