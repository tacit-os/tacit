pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool borderless: Config.options.bar.borderless

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0) 
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            updateProc.running = true
        }
    }

    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            Updates.refresh()
            Quickshell.execDetached(["notify-send",
                Translation.tr("Updates"),
                Translation.tr("Checking for updates..."),
                "-a", "Shell"
            ])
            mouse.accepted = false
        }
    }

    // The owner's update command (Config apps.update), as Settings > About runs it: Tacit's packages
    // come from pacman, and the terminal and helper are the ones that file names, not a fixed one.
    // In a session of its own, holding none of the shell's pipes: Quickshell kills a Process's child when the Process
    // goes (a reload, as the update of the shell's own package brings, or the bar rebuilt), which took the terminal and
    // the update in it along. setsid -w waits for it and gives back its exit; only setsid is killed then.
    Process {
        id: updateProc
        command: ["bash", "-c", 'exec setsid -f -w bash -c "$1" </dev/null >/dev/null 2>&1', "_", Config.options.apps.update]
        onExited: (exitCode, exitStatus) => {
            // 127: the command was not found, so nothing ran and there is no result to report
            if (exitCode === 127) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Update didn't start"),
                    Translation.tr("Could not run the update command in the config file (apps.update)."),
                    "-a", "Shell"
                ])
                return
            }
            Updates.refresh()
            notifyTimer.restart()
        }
    }

    Timer {
        id: notifyTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (Updates.count === 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Updates"),
                    Translation.tr("System up to date"),
                    "-a", "Shell"
                ])
            } else {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Updates"),
                    Translation.tr("Update cancelled — %1 updates still pending").arg(Updates.count),
                    "-a", "Shell", "-u", "normal"
                ])
            }
        }
    }

    Component {
        id: textComp
        StyledText {
            leftPadding: 5
            rightPadding: 3
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            text: Updates.count
        }
    }

    Component {
        id: spinnerComp
        MaterialSymbol {
            leftPadding: 5
            rightPadding: 3
            text: "progress_activity"
            iconSize: Appearance.font.pixelSize.normal
            color: root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: true
            }
        }
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: 4

            // Default
            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignVCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colOnLayer1
            }

            // Material
            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
            }

            AnimLoader {
                Layout.alignment: Qt.AlignVCenter
                sourceComp: Updates.checking ? spinnerComp : textComp   // spinner <-> count cross-fades
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 4

            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignHCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colOnLayer1
            }

            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignHCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
            }

            AnimLoader {
                Layout.alignment: Qt.AlignHCenter
                sourceComp: Updates.checking ? spinnerComp : textComp   // spinner <-> count cross-fades
            }
        }
    }
}