import QtQuick
import Tacit.Kit as K

Column {
    id: preview

    required property var controller
    readonly property var attachment: controller.ui.attachment
    readonly property bool isImage: /\.(png|jpg|jpeg|webp|gif)$/i.test(attachment?.name ?? "")
    readonly property var t: K.Kit.tokens

    spacing: t.space.xl

    K.TacitText {
        text: preview.attachment?.detail ?? ""
        size: "meta"
        ink: "quiet"
    }

    Image {
        id: picture
        visible: preview.isImage
        source: visible ? (preview.attachment?.url ?? "") : ""
        width: preview.width
        height: preview.t.width.panel
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        Accessible.ignored: true
    }

    K.TacitText {
        width: preview.width
        wrapMode: Text.Wrap
        size: "body"
        text: {
            if (picture.status === Image.Error)
                return qsTr("Image preview unavailable");
            return preview.attachment?.content ?? qsTr("Local attachment");
        }
    }

    MailAction {
        visible: !!preview.attachment?.url || !!preview.attachment?.path
        text: qsTr("Open with default app")
        onActivated: Qt.openUrlExternally(preview.attachment.url || Qt.resolvedUrl(preview.attachment.path))
    }

    MailAction {
        text: qsTr("Save to Files")
        onActivated: preview.controller.saveAttachment(preview.attachment)
    }
}
