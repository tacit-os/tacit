import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Tacit.Kit
import QtQuick
import QtQuick.Layouts

/**
 * The battery drawer's body: the charge at a glance, what the pack is doing now, and its
 * health. The panel hugs this content; the shared drawer draws the surface.
 */
Item {
    id: root

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h, ${m}m` : `${m}m`;
    }

    readonly property bool showTime: !(Battery.chargeState == 4
        || (Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty) <= 0
        || Battery.energyRate <= 0.01)
    readonly property string stateText: {
        if (!Battery.available) return Translation.tr("No battery");
        if (Battery.chargeState == 4) return Translation.tr("Fully charged");
        if (Battery.drainingOnAc) return Translation.tr("Plugged in, not charging");
        if (Battery.isCharging) return Translation.tr("Charging")
            + (root.showTime ? " · " + root.formatTime(Battery.timeToFull) : "");
        return Translation.tr("Time to empty")
            + (root.showTime ? " · " + root.formatTime(Battery.timeToEmpty) : "");
    }

    implicitWidth: 340
    implicitHeight: column.implicitHeight + Kit.tokens.space.l * 2

    DockedRect {
        anchors.fill: parent
        edge: "top"
        cornerRadius: Appearance.rounding.verylarge
        fillet: 12
        color: Config.options.bar.showBackground ? Appearance.colors.colBarSurface : "transparent"
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
                // Tacit's symbol set names this "battery-charging"; the Material spelling
                // has no ligature here and would print the name instead of a glyph.
                text: Battery.isCharging ? "battery-charging"
                    : Battery.isLowAndNotCharging ? "battery_alert" : "battery"
                iconSize: 22
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: Translation.tr("Battery")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: Battery.available ? Math.round(Battery.percentage * 100) + "%" : "—"
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.stateText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kit.tokens.space.s
            StyledText {
                text: Translation.tr("Health")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: Battery.available ? Math.round(Battery.health) + "%" : "—"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kit.tokens.space.s
            StyledText {
                text: Translation.tr("Cycles")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: Battery.chargeCycles > 0 ? String(Battery.chargeCycles) : "—"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kit.tokens.space.s
            StyledText {
                text: Battery.isCharging ? Translation.tr("Charging") : Translation.tr("Draw")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: Battery.chargeState == 4 ? Translation.tr("Full")
                    : Battery.energyRate.toFixed(2) + " W"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }
        }
    }
}
