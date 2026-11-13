pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.tacit.card
import qs.modules.tacit.overlay
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "images"

    property list<var> formatOptions: [
        { displayName: "PNG",  icon: "image",            value: "png"  },
        { displayName: "JPG",  icon: "photo",            value: "jpg"  },
        { displayName: "WEBP", icon: "motion_photos_on", value: "webp" },
        { displayName: "AVIF", icon: "hd",               value: "avif" },
        { displayName: "BMP",  icon: "grid_on",          value: "bmp"  },
        { displayName: "TIFF", icon: "photo_library",    value: "tiff" },
        { displayName: "PDF",  icon: "picture_as_pdf",   value: "pdf"  },
    ]

    property string selectedFormat: "webp"
    property string dropStatus: "idle"   // idle | hover | converting | done | error
    property string statusMessage: ""

    readonly property var acceptedExtensions: ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]

    property var fileQueue: []
    property int queueTotal: 0
    property int queueDone: 0
    property var batchPaths: []
    readonly property bool busy: converter.running || pdfMaker.running

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Process {
        id: converter
        property string inputPath: ""
        property string outputPath: ""
        command: ["ffmpeg", "-y", "-i", inputPath, outputPath]
        onExited: (exitCode) => {
            root.queueDone++
            if (exitCode !== 0) {
                root.dropStatus = "error"
                root.statusMessage = Translation.tr("Failed: %1").arg(inputPath.replace(/.*\//, ""))
                root.fileQueue = []
                root.queueTotal = 0
                root.queueDone = 0
                resetTimer.start()
                return
            }
            if (root.fileQueue.length > 0) {
                root.statusMessage = Translation.tr("Converting %1 / %2...").arg(root.queueDone).arg(root.queueTotal)
                processNext()
            } else {
                root.dropStatus = "done"
                root.statusMessage = root.queueTotal === 1
                    ? Translation.tr("Saved: %1").arg(outputPath.replace(/.*\//, ""))
                    : Translation.tr("%1 files converted").arg(root.queueTotal)
                root.queueTotal = 0
                root.queueDone = 0
                resetTimer.start()
            }
        }
    }

    Process {
        id: pdfMaker
        property string outputPath: ""
        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.dropStatus = "done"
                root.statusMessage = root.batchPaths.length === 1
                    ? Translation.tr("Saved: %1").arg(outputPath.replace(/.*\//, ""))
                    : Translation.tr("%1 pages → %2").arg(root.batchPaths.length).arg(outputPath.replace(/.*\//, ""))
            } else {
                root.dropStatus = "error"
                root.statusMessage = Translation.tr("PDF failed.\nIs ImageMagick installed?")
            }
            root.batchPaths = []
            resetTimer.start()
        }
    }

    Timer {
        id: resetTimer
        interval: 3500
        repeat: false
        onTriggered: root.dropStatus = "idle"
    }

    function processNext() {
        var next = root.fileQueue[0]
        root.fileQueue = root.fileQueue.slice(1)
        converter.inputPath  = next
        converter.outputPath = next.replace(/\.[^/.]+$/, "") + "_converted." + root.selectedFormat
        converter.running = true
    }

    function enqueueFiles(urls) {
        // A drop while one is being converted would overwrite the file in hand and its queue
        if (root.busy) return
        resetTimer.stop()
        var valid = []
        for (var i = 0; i < urls.length; i++) {
            var cleanPath
            try {
                cleanPath = FileUtils.trimFileProtocol(decodeURIComponent(urls[i].toString()))
            } catch (e) {
                continue
            }
            var ext = cleanPath.split(".").pop().toLowerCase()
            if (root.acceptedExtensions.indexOf(ext) !== -1)
                valid.push(cleanPath)
        }
        if (valid.length === 0) {
            root.dropStatus = "error"
            root.statusMessage = Translation.tr("No supported files dropped.")
            resetTimer.start()
            return
        }

        root.dropStatus = "converting"

        if (root.selectedFormat === "pdf") {
            root.batchPaths = valid
            root.statusMessage = valid.length === 1
                ? Translation.tr("Converting to PDF...")
                : Translation.tr("Merging %1 images into PDF...").arg(valid.length)
            var outPdf = valid[0].replace(/\.[^/.]+$/, "") + (valid.length > 1 ? "_merged" : "_converted") + ".pdf"
            pdfMaker.outputPath = outPdf
            pdfMaker.command = ["convert"].concat(valid).concat([outPdf])
            pdfMaker.running = true
            return
        }

        root.fileQueue  = valid.slice(1)
        root.queueTotal = valid.length
        root.queueDone  = 0
        root.statusMessage = valid.length > 1 ? Translation.tr("Converting %1 / %2...").arg(0).arg(valid.length) : Translation.tr("Converting...")
        converter.inputPath  = valid[0]
        converter.outputPath = valid[0].replace(/\.[^/.]+$/, "") + "_converted." + root.selectedFormat
        converter.running = true
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        configKey: "images"
        glyph: "image"
        title: Translation.tr("Image converter")

        ColumnLayout {
            width: parent.width
            spacing: 10

            Rectangle {
                id: dropZone
                Layout.fillWidth: true
                implicitHeight: 112
                radius: 14
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, root.dropStatus === "hover" ? 0.86 : 0.93)
                Behavior on color {
                    CAnim {}
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -14
                    visible: root.dropStatus === "converting"
                    loading: root.dropStatus === "converting"
                    colBg: Appearance.colors.colPrimary
                    colShape: Appearance.colors.colOnPrimary
                    implicitSize: 40
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -14
                    visible: root.dropStatus !== "converting"
                    iconSize: 28
                    fill: root.dropStatus === "done" ? 1 : 0
                    color: {
                        switch (root.dropStatus) {
                            case "hover":
                            case "done":  return Appearance.colors.colPrimary
                            case "error": return Appearance.colors.colError
                            default:      return Appearance.colors.colSubtext
                        }
                    }
                    text: {
                        switch (root.dropStatus) {
                            case "hover": return "download"
                            case "done":  return "check_circle"
                            case "error": return "error"
                            default:      return root.selectedFormat === "pdf" ? "picture_as_pdf" : "add_photo_alternate"
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 20
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 13
                    width: parent.width - 24
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    color: root.dropStatus === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: {
                        switch (root.dropStatus) {
                            case "idle":       return Translation.tr("Drop pictures here\nto convert to .%1").arg(root.selectedFormat.toUpperCase())
                            case "hover":      return Translation.tr("Release to convert to .%1").arg(root.selectedFormat.toUpperCase())
                            default:           return root.statusMessage
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    // While busy a drag is still taken here, and its drop turned down: one refused on entering
                    // goes on to the desktop underneath, which copies the pictures into the Desktop folder
                    onEntered: (drag) => {
                        if (root.busy)
                            return
                        drag.accept(Qt.CopyAction)
                        root.dropStatus = "hover"
                    }
                    onExited: {
                        if (root.dropStatus === "hover")
                            root.dropStatus = "idle"
                    }
                    onDropped: (drop) => {
                        if (root.busy) {
                            drop.accepted = false
                            return
                        }
                        if (drop.hasUrls && drop.urls.length > 0) {
                            root.enqueueFiles(drop.urls)
                        } else {
                            root.dropStatus = "error"
                            root.statusMessage = Translation.tr("Could not read file path.")
                            resetTimer.start()
                        }
                    }
                }
            }

            StyledText {
                text: Translation.tr("Convert to")
                font.pixelSize: 14
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.formatOptions
                    delegate: OverlayPill {
                        required property var modelData
                        label: modelData.displayName
                        on: root.selectedFormat === modelData.value
                        onClicked: root.selectedFormat = modelData.value
                    }
                }
            }
        }
    }
}
