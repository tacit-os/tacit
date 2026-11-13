import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Super+G's card: near-opaque ground (as the palette's), radius 24, the notch's 34 px strip
// (glyph, 14 px title, buttons) with a hairline under it. The body goes below the strip.
// Plain component, no services: the login lock's tree may load it.
Rectangle {
    id: root
    property string glyph: ""
    property string title: ""
    // false: no ground and no hairline (a see-through widget keeps its header's ground only).
    property bool fancy: true
    // false: the ground is transparent (a pinned widget with the overlay closed, own picture).
    property bool grounded: true
    property bool masked: true
    // 34 px strip and its hairline; 0 hides the header.
    property real headerHeight: 35
    property bool headerShown: true
    // Buttons after the title.
    property alias headerData: titleBarRow.data
    default property alias content: column.data
    readonly property alias column: column
    readonly property alias titleBar: titleBar

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight
    radius: 24
    color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, (root.fancy && root.grounded) ? 0.04 : 1)

    layer.enabled: root.masked
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }

    ColumnLayout {
        id: column
        z: root.fancy ? 0 : -1
        anchors.fill: parent
        spacing: 0

        Item {
            id: titleBar
            opacity: root.headerShown ? 1 : 0
            clip: true
            Layout.fillWidth: true
            implicitWidth: titleBarRow.implicitWidth + 24
            implicitHeight: root.headerHeight
            // a layout keeps an item's last height when its implicit height falls to 0: a folded header kept 1 or 2 px
            Layout.preferredHeight: root.headerHeight
            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Rectangle {
                visible: !root.fancy
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.04)
            }

            RowLayout {
                id: titleBarRow
                x: 12
                width: parent.width - 24
                height: 34
                spacing: 6

                MaterialSymbol {
                    text: root.glyph
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer0
                }
            }
            Rectangle {
                visible: root.fancy
                x: 12
                y: 34
                width: parent.width - 24
                height: 1
                color: Appearance.colors.colLayer0Border
            }
        }
    }
}
