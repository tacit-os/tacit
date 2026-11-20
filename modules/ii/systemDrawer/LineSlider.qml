import qs.modules.common
import Tacit.Kit
import QtQuick
import QtQuick.Layouts

/**
 * The control panel's one-line slider, shared with the bar drawers: the pill's glyph on the
 * left, the kit's own Slider for the bar and the keyboard, and the value as a word at the
 * right. Same as SidebarRightContent.qml's LineSlider, so the two read as one control.
 */
RowLayout {
    id: line
    property string glyph: "tune"
    property string label: ""
    // The setting as it is: a volume past 100% fills the bar, which ends at 1, and its word
    // says how far. The kit's Slider does not move itself: it says where it was moved to,
    // and the value follows the setting.
    property real value: 0
    property bool enabledControl: true
    signal moved(real value)

    spacing: Kit.tokens.space.s

    Symbol {
        text: line.glyph
        size: Kit.tokens.icon.row
        color: Tacit.inkMain
    }
    Slider {
        Layout.fillWidth: true
        enabled: line.enabledControl
        label: line.label
        value: Math.min(1, line.value)
        word: `${Math.round(line.value * 100)}%`
        onMoved: v => line.moved(v)
    }
}
