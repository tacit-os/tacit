import QtQuick
import Tacit.Kit as K
import ".." as Mail

FocusScope {
    id: scene

    readonly property var controller: workspace.controller
    readonly property real groundRadius: K.Kit.tokens.radius.window
    focus: true

    Component.onCompleted: {
        scene.controller.draftQuery.refresh();
        previewMailbox.loadOutbox();
    }

    K.WindowGround {
        anchors.fill: parent
        DragHandler {
            enabled: typeof previewWindow !== "undefined"
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            acceptedButtons: Qt.LeftButton
            grabPermissions: PointerHandler.ApprovesTakeOverByAnything
            onActiveChanged: if (active) previewWindow.dragBackground()
        }
    }

    Mail.MailWorkspace {
        id: workspace
        objectName: "mailScene"
        prewarmHtml: true
        anchors.fill: parent
        mailboxClient: previewMailbox
    }

    function snapshot() { return JSON.stringify(scene.controller.ui); }
    function restore(snapshot) {
        const ui = JSON.parse(snapshot);
        scene.controller.data = Object.assign({}, scene.controller.data, {
            ui: Object.assign({}, scene.controller.ui, {
                folder: ui.folder, account: ui.account, rail: ui.rail,
                query: ui.query, searching: ui.searching, filter: ui.filter, sort: ui.sort
            })
        });
    }

    Connections {
        target: previewMailbox
        function onDemoMailReceived(ok) {
            if (!ok)
                scene.controller.act("notice", {text: qsTr("Could not receive demo mail.")});
        }
    }

    function simulate(action) { scene.controller.act(action); }
}
