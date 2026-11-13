import qs.modules.common
import QtQuick
import QtQuick.Controls

// The shell runs the Basic style (shell.qml's QT_QUICK_CONTROLS_STYLE), whose bar is palette.dark on palette.midlight;
// a Material.accent was never read, and the bar was the style's grey. The colours are StyledProgressBar's.
ProgressBar {
    indeterminate: true
    palette.dark: Appearance.colors.colPrimary
    palette.midlight: Appearance.m3colors.m3secondaryContainer
}
