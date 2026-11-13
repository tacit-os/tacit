import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.tacit.card
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "userCard"
    hoverEnabled: true

    property string username: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    // One action: a row that takes the click.
    component ActionRow: Item {
        id: action
        property string glyph: ""
        property string label: ""
        property bool first: false
        signal clicked

        Layout.fillWidth: true
        implicitHeight: row.implicitHeight
        implicitWidth: row.implicitWidth

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            radius: 12
            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, area.containsMouse ? 0.93 : 1)
            Behavior on color {
                CAnim {}
            }
        }
        TacitRow {
            id: row
            width: parent.width
            first: action.first
            glyph: action.glyph
            label: action.label
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.clicked()
        }
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        configKey: "userCard"
        glyph: "person"
        title: Translation.tr("You")

        ColumnLayout {
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                spacing: 12
                TacitPicture {
                    id: avatar
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 54
                    // Settings copies the picture to ~/.face and leaves avatarPicture empty
                    readonly property string path: Config.options.profile.avatarPicture !== ""
                        ? Config.options.profile.avatarPicture
                        : Directories.userAvatarPathRicersAndWeirdSystems
                    // and copies a new one over the same file from its own process: the file is watched, and the
                    // query changes the url, so the new picture is read again rather than the one Image kept for it
                    property int version: 0
                    source: `file://${avatar.path}?${avatar.version}`
                    cache: false
                    sourceSize: Qt.size(108, 108)
                    FileView {
                        path: avatar.path
                        preload: false
                        watchChanges: true
                        printErrors: false
                        onFileChanged: avatar.version++
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        visible: avatar.status !== Image.Ready
                        color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "account_circle"
                            iconSize: 28
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Hi, %1").arg(root.username)
                        font.pixelSize: 17
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer0
                    }
                    TacitCaption {
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        text: Qt.locale().toString(DateTime.clock.date, "dddd d MMMM")
                    }
                    TacitCaption {
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        text: Translation.tr("Up %1").arg(DateTime.uptime)
                    }
                }
            }
            ActionRow {
                glyph: "lock"
                label: GlobalStates.screenLocked ? Translation.tr("Locked") : Translation.tr("Lock")
                // Same command as Super+L (keybinds.lua); LockScreen.lock() honours lock.useHyprlock
                onClicked: Quickshell.execDetached(["bash", "-c", 'qs -p "$1" ipc call lock activate || pidof hyprlock || hyprlock', "bash", Quickshell.shellPath("")])
            }
            ActionRow {
                glyph: "settings"
                label: Translation.tr("Settings")
                onClicked: SettingsApp.open("account")
            }
            ActionRow {
                glyph: "power_settings_new"
                label: Translation.tr("Session")
                onClicked: GlobalStates.sessionOpen = true
            }
        }
    }
}
