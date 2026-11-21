import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.systemDrawer
import Tacit.Kit
import QtQuick
import QtQuick.Layouts

/**
 * The brightness drawer's body: one slider for the screen's backlight and the night light
 * switch beside it. The panel hugs this content; the shared drawer draws the surface.
 */
Item {
    id: root

    readonly property var monitor: Brightness.panel ?? Brightness.monitors?.[0] ?? null
    readonly property bool live: monitor?.ready ?? false
    readonly property int percent: Math.round((monitor?.multipliedBrightness ?? monitor?.brightness ?? 0) * 100)

    implicitWidth: 340
    implicitHeight: column.implicitHeight + Kit.tokens.space.l * 2

    DockedRect {
        anchors.fill: parent
        visible: !Config.options.bar.show || (Config.options.bar.showBackground && Config.options.bar.drawerStyle === "attached")
        edge: "top"
        cornerRadius: Appearance.rounding.verylarge
        fillet: 12
        color: Appearance.colors.colBarSurface
    }
    Rectangle {
        anchors.fill: parent
        visible: Config.options.bar.show && (!Config.options.bar.showBackground || Config.options.bar.drawerStyle !== "attached")
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colBarSurface
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        id: column
        anchors {
            fill: parent
            leftMargin: Kit.tokens.space.l
            rightMargin: Kit.tokens.space.l
            topMargin: Kit.tokens.space.l
            bottomMargin: Kit.tokens.space.xl
        }
        spacing: Kit.tokens.space.m

        RowLayout {
            Layout.fillWidth: true
            spacing: Kit.tokens.space.s

            MaterialSymbol {
                text: "brightness_6"
                iconSize: 18
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Brightness")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: root.live ? root.percent + "%" : Translation.tr("Unavailable")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        LineSlider {
            Layout.fillWidth: true
            glyph: "brightness_6"
            label: Translation.tr("Brightness")
            value: monitor?.brightness ?? 0
            enabledControl: root.live
            onMoved: v => {
                if (Hyprsunset.gamma !== 100 && (monitor?.brightness ?? 1) < 0.01)
                    Hyprsunset.setGamma(100);
                if (monitor) monitor.setBrightness(Math.max(0.02, v));
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kit.tokens.space.s

            MaterialSymbol {
                text: "dark_mode"
                iconSize: 18
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Night light")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledSwitch {
                checked: Hyprsunset.temperatureActive
                onClicked: Hyprsunset.toggleTemperature()
            }
        }
    }
}
