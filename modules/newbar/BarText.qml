import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.functions

// A line of bar text with a shadow under it. Over Clear the words sit on the picture itself, and
// where the blur is bright they lose their edge; the shadow is the ground seen dark, a hair below
// the letters, so they keep their contrast without a plate behind them. Solid and Frosted have a
// ground of their own, but the shadow costs nothing there and keeps the bar one thing.
Text {
    id: root

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: ColorUtils.applyAlpha(Tacit.ground, 0.65)
        shadowVerticalOffset: 1
        shadowHorizontalOffset: 0
        shadowBlur: 0.35
    }
}
