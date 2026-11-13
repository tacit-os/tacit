import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.tacit.card
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock"

    implicitHeight: card.implicitHeight
    implicitWidth: card.implicitWidth

    readonly property bool forceCenter: (GlobalStates.screenLocked && Config.options.lock.centerClock)
    readonly property bool shouldShow: (!Config.options.background.widgets.clock.showOnlyWhenLocked || GlobalStates.screenLocked)
    property bool wallpaperSafetyTriggered: false
    readonly property bool lockedShown: GlobalStates.screenLocked && Config.options.lock.showLockedText
    readonly property string quoteText: Config.options.background.widgets.clock.quote.enable ? Config.options.background.widgets.clock.quote.text : ""
    // The card is all there is of the clock: with nothing on it (only when locked, while unlocked) the widget goes too,
    // or its empty place on the desktop kept taking right clicks, drags and the rubber band.
    visible: opacity > 0 && (root.shouldShow || root.wallpaperSafetyTriggered || root.lockedShown)
    x: forceCenter ? ((root.screenWidth - root.width) / 2) : targetX
    y: forceCenter ? ((root.screenHeight - root.height) / 2) : targetY
    visibleWhenLocked: true

    function restoreXYBinding() {
        root.x = Qt.binding(() => root.forceCenter ? ((root.screenWidth - root.width) / 2) : root.targetX);
        root.y = Qt.binding(() => root.forceCenter ? ((root.screenHeight - root.height) / 2) : root.targetY);
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        configKey: "clock"
        glyph: "schedule"
        title: Translation.tr("Clock")
        closable: !GlobalStates.screenLocked

        ColumnLayout {
            width: parent.width
            spacing: 0

            RowLayout {
                visible: root.shouldShow
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                TacitFigure {
                    text: DateTime.time
                    font.pixelSize: 44
                }
                Item {
                    Layout.fillWidth: true
                }
                TacitCaption {
                    horizontalAlignment: Text.AlignRight
                    text: Qt.locale().toString(DateTime.clock.date, "dddd\nd MMMM")
                }
            }
            TacitRow {
                visible: root.wallpaperSafetyTriggered
                first: !root.shouldShow
                glyph: "hide_image"
                label: Translation.tr("Wallpaper safety enforced")
            }
            TacitRow {
                visible: root.lockedShown
                first: !root.shouldShow && !root.wallpaperSafetyTriggered
                glyph: "lock"
                label: Translation.tr("Locked")
            }
            TacitRow {
                visible: root.quoteText.length > 0 && root.shouldShow
                glyph: "format_quote"
                label: root.quoteText
            }
        }
    }
}
