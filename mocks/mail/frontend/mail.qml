// Tacit Mail workspace backed by the local mail daemon.
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import Tacit.Kit as K
import Tacit.Mailbox

ShellRoot {
    id:shell
    readonly property int sw:parseInt(Quickshell.env("DUNE_W") ?? "1720")
    readonly property int sh:parseInt(Quickshell.env("DUNE_H") ?? "972")
    readonly property var controller: workspace.controller
    PreviewMailbox { id: mailbox }
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        controller.draftQuery.refresh();
        mailbox.loadOutbox();
    }
    FloatingWindow {
        objectName:"mailWindow"
        implicitWidth:shell.sw;implicitHeight:shell.sh
        visible:true;color:"transparent"
        Item {
            id:scene
            objectName:"mailScene"
            anchors.fill:parent
            Item {
                id:win
                anchors.fill:parent
                Item {id:mask;anchors.fill:parent;visible:false;layer.enabled:true
                    Rectangle {anchors.fill:parent;radius:K.Kit.tokens.radius.window;color:K.Kit.tokens.inkMain}
                }
                Item {
                    anchors.fill:parent;layer.enabled:true
                    layer.effect:MultiEffect {maskEnabled:true;maskSource:mask}
                    K.WindowGround {}
                }
                MailWorkspace {id:workspace;anchors.fill:parent;mailboxClient:mailbox;prewarmHtml:true}
            }

        }
        Timer {
            interval:parseInt(Quickshell.env("DUNE_SHOT_DELAY") ?? "4500");running:!!Quickshell.env("DUNE_SHOT")
            onTriggered:scene.grabToImage(r=>{r.saveToFile(Quickshell.env("DUNE_SHOT"));Qt.quit();})
        }
    }
}
