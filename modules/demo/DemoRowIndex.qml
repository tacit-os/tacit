pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

StyledText {
    required property int number
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    font.family: Appearance.font.family.numbers
    font.pixelSize: Appearance.font.pixelSize.smaller
    font.letterSpacing: 1
    color: Tacit.inkFaint
    text: String(number).padStart(2, "0")
}
