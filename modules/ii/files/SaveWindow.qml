import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Save As for another app (the file-chooser portal, `files save` / `files savefolder`): a strip
 * docked into the bottom edge, grown and folded like the wallpaper filmstrip (WallpaperStrip.qml). The name with the part before the extension selected, the
 * folders Save As used last as chips, "Other folder" for a folder browser inside the window, and
 * Save. A name already in the folder asks Replace / Keep both. The answer goes back over the pick
 * protocol (Files.pickDone): the full path, or [] on Cancel or close. Files writes nothing.
 * The owner's pick 2026-09-30: the save card's parts, "like the one when changing wallpaper".
 * A layer surface: it grows upward when the folder browser opens (a toplevel keeps its first size).
 */
PanelWindow {
    id: win

    property string folder: Files.home
    readonly property bool forFolder: Files.picking?.dir === true
    property string name: Files.picking?.name ?? ""
    property bool browsing: false
    property bool asking: false
    property bool answered: false

    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:saveAs"
    // the answer is asked for: the keys stay here until Save or Cancel, as the password request's do
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    // One fixed surface, as large as the strip can grow (plus the coves the DockedRect draws outside
    // its width); only the strip takes input. Resizing the surface itself on every change was janky.
    implicitWidth: strip.wideWidth + 2 * strip.fillet
    implicitHeight: 700
    mask: Region { item: strip }
    visible: true
    signal closing()

    // the folder the request named first, then where Save As went lately, then the usual places
    readonly property var chips: {
        const seen = new Set(), out = [];
        for (const f of [win.startFolder].concat(Files.saveFolders, [Files.places[2].path, Files.places[1].path, Files.places[6].path])) {
            const p = Files.trim(f ?? "");
            if (p.length > 0 && !seen.has(p)) { seen.add(p); out.push(p); }
        }
        return out.slice(0, 4);
    }
    property string startFolder: ""

    readonly property string trimmed: win.name.trim()
    readonly property bool nameOk: win.trimmed.length > 0 && win.trimmed !== "." && win.trimmed !== ".." && !win.trimmed.includes("/")
    // what is already in the folder, for "already here"
    property var names: ({})
    property var dirs: ({})
    readonly property bool taken: win.nameOk && win.names[win.trimmed] === true
    readonly property bool isFolder: win.nameOk && win.dirs[win.trimmed] === true
    readonly property bool ready: win.forFolder || (win.nameOk && !win.isFolder)
    readonly property string target: (win.folder === "/" ? "" : win.folder) + "/" + win.trimmed

    FolderListModel {
        id: here
        folder: "file://" + win.folder.split("/").map(encodeURIComponent).join("/")
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: true
        onStatusChanged: if (status === FolderListModel.Ready) win.relist()
        onCountChanged: win.relist()
    }
    function relist() {
        let n = ({}), d = ({});
        for (let i = 0; i < here.count; i++) {
            const nm = here.get(i, "fileName") + "";
            n[nm] = true;
            if (here.get(i, "fileIsDir"))
                d[nm] = true;
        }
        win.names = n;
        win.dirs = d;
    }

    // "name 2", "name 3" ... as the job runner's keep_name does (scripts/files/job.sh): before a file's extension, its last
    // dot-word or .tar.<x> as Rename many takes it ("notes 2.markdown", "x 2.tar.gz"); a folder has none
    function keepName(nm) {
        if (win.names[nm] !== true)
            return nm;
        const m = win.dirs[nm] === true ? null : /^(.+?)(\.tar\.[^.\s]+|\.[^.\s]+)$/.exec(nm);
        const stem = m ? m[1] : nm, ext = m ? m[2] : "";
        let k = 2;
        while (win.names[`${stem} ${k}${ext}`] === true)
            k++;
        return `${stem} ${k}${ext}`;
    }
    function go(path) {
        win.folder = Files.trim(path);
        win.asking = false;
    }
    function answer(paths) {
        if (win.answered)
            return;
        win.answered = true;
        if (paths.length > 0)
            Files.savedIn(win.folder);
        Files.pickDone(paths);
        strip.shown = false;   // folds back, then the window goes
        foldTimer.restart();
    }
    Timer {
        id: foldTimer
        interval: 450
        onTriggered: win.visible = false
    }
    function accept() {
        if (!win.ready)
            return;
        if (win.forFolder)
            win.answer([win.folder]);
        else if (win.taken)
            win.asking = true;
        else
            win.answer([win.target]);
    }

    Component.onCompleted: {
        win.folder = win.startFolder.length > 0 ? win.startFolder : (win.chips[0] ?? Files.home);
        focusTimer.restart();
    }
    onVisibleChanged: {
        if (!visible) {
            if (!win.answered) {
                win.answered = true;
                Files.pickDone([]);
            }
            win.closing();
            win.destroy();
        }
    }
    // a moment late: the window takes its own focus as it maps
    Timer {
        id: focusTimer
        interval: 250
        onTriggered: {
            if (win.forFolder)
                return;
            field.forceActiveFocus();
            const dot = win.name.lastIndexOf(".");
            field.select(0, dot > 0 ? dot : win.name.length);
        }
    }

    component Pill: Rectangle {
        id: pill
        property string label
        property bool main: false
        property bool danger: false
        property bool enabledPill: true
        signal clicked()
        implicitWidth: pillText.implicitWidth + 32
        implicitHeight: 36
        radius: Appearance.rounding.full
        opacity: enabledPill ? 1 : 0.45
        color: main ? (pillArea.containsMouse && enabledPill ? ColorUtils.mix(Appearance.m3colors.m3primary, Appearance.m3colors.m3onPrimary, 0.9) : Appearance.m3colors.m3primary)
                    : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, pillArea.containsMouse ? 0.9 : 1)
        StyledText {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.pixelSize: 15
            font.weight: pill.main ? Font.DemiBold : Font.Normal
            color: pill.main ? Appearance.m3colors.m3onPrimary : pill.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (pill.enabledPill) pill.clicked()
        }
    }
    // A folder to save in, as the filmstrip's source tabs: words, the chosen one in weight with the
    // accent dot under it (WallpaperStrip.qml)
    component Chip: StyledText {
        id: chip
        property string label
        property bool on: false
        signal clicked()
        text: chip.label
        font.pixelSize: 16
        font.weight: chip.on ? Font.DemiBold : Font.Normal
        color: chip.on || chipArea.containsMouse ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
        Rectangle {
            visible: chip.on
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 3
            width: 4
            height: 4
            radius: 2
            color: Appearance.colors.colPrimary
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
    component Row2: Rectangle {
        id: r
        property string glyph
        property string label
        property bool on: false
        property bool dim: false
        signal clicked()
        width: parent?.width ?? 0
        height: 38
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, r.on ? 0.92 : (rArea.containsMouse && !r.dim ? 0.95 : 1))
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8
            MaterialSymbol { text: r.glyph; iconSize: 18; color: r.on ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
            StyledText {
                Layout.fillWidth: true
                text: r.label
                elide: Text.ElideRight
                font.pixelSize: 15
                color: r.dim ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
            }
        }
        MouseArea {
            id: rArea
            anchors.fill: parent
            hoverEnabled: !r.dim
            cursorShape: r.dim ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: r.clicked()
        }
    }

    Item {
        id: strip
        property bool shown: false
        readonly property real fillet: 12
        readonly property real compactWidth: 720
        // the space other folders need: wide enough for real names, tall enough for a folder's worth
        readonly property real wideWidth: 1040
        readonly property real fullWidth: win.browsing ? strip.wideWidth : strip.compactWidth
        readonly property real fullHeight: column.implicitHeight + 40
        // Grows out of the bottom edge as the wallpaper filmstrip does (WallpaperStrip.qml): the
        // notch's spring to open and to widen for other folders, its close curve to fold back; the
        // content follows the strip's width and is uncovered as it grows.
        width: strip.shown ? strip.fullWidth : 360
        height: strip.shown ? strip.fullHeight : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        focus: true
        readonly property int duration: strip.shown ? Appearance.animationCurves.expressiveDefaultSpatialDuration : 450
        readonly property list<real> curve: strip.shown ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.emphasizedDecel
        Behavior on width {
            NumberAnimation { duration: strip.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: strip.curve }
        }
        Behavior on height {
            NumberAnimation { duration: strip.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: strip.curve }
        }
        Component.onCompleted: strip.shown = true

        Keys.onPressed: event => {   // Escape without a name field (a folder only)
            if (event.key === Qt.Key_Escape) {
                if (win.asking) win.asking = false;
                else win.answer([]);
                event.accepted = true;
            }
        }

        DockedRect {
            anchors.fill: parent
            edge: "bottom"
            cornerRadius: Appearance.rounding.verylarge
            fillet: strip.fillet
            // solid, as the filmstrip's (WallpaperStrip.qml): it sits over another app's own glass,
            // and frost on glass left the words unreadable
            color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.04)
        }

        Item {
            id: clipper
            anchors.fill: parent
            clip: true
            Item {
                width: strip.width
                height: strip.fullHeight
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                opacity: strip.shown ? 1 : 0
                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: strip.shown ? 120 : 0 }
                        NumberAnimation { duration: Appearance.animationCurves.expressiveEffectsDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveEffects }
                    }
                }

        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 26; rightMargin: 26; topMargin: 20 }
            spacing: 14

            RowLayout {   // what is asked, and for whom; the folder browser on request
                spacing: 10
                MaterialSymbol { text: win.forFolder ? "drive_folder_upload" : "download"; iconSize: 20; color: Appearance.colors.colPrimary }
                StyledText { text: win.forFolder ? "Save here" : "Save"; font.pixelSize: 16; font.weight: Font.Medium; color: Appearance.colors.colOnLayer0 }
                StyledText {
                    Layout.fillWidth: true
                    text: (Files.picking?.asker ?? "").length > 0 ? `for ${Files.picking.asker}` : ""
                    elide: Text.ElideRight
                    font.pixelSize: 15
                    color: Appearance.colors.colSubtext
                }
                Item {
                    implicitWidth: otherRow.implicitWidth
                    implicitHeight: otherRow.implicitHeight
                    Row {
                        id: otherRow
                        spacing: 4
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: win.browsing ? "Fewer" : "Other folder"; font.pixelSize: 14; color: otherArea.containsMouse ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext }
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: win.browsing ? "expand_less" : "expand_more"; iconSize: 18; color: Appearance.colors.colSubtext }
                    }
                    MouseArea {
                        id: otherArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.browsing = !win.browsing
                    }
                }
            }

            RowLayout {   // the name, and the answer
                spacing: 8
                ToolbarTextField {   // the header search field's look (FilesWindow.qml)
                    id: field
                    visible: !win.forFolder
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 0
                    colBackground: "transparent"   // the filmstrip's search field: words, no box
                    font.pixelSize: 17
                    leftPadding: 2
                    rightPadding: 2
                    text: win.name
                    color: win.taken || win.isFolder ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                    onTextChanged: {
                        if (win.name !== text) {
                            win.name = text;
                            win.asking = false;
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.accept();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (win.asking) win.asking = false;
                            else win.answer([]);
                            event.accepted = true;
                        }
                    }
                    Rectangle {   // the line it is written on: the accent while typing, the error colour when taken
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: field.activeFocus || win.taken || win.isFolder ? 2 : 1
                        radius: 1
                        color: win.taken || win.isFolder ? Appearance.colors.colError
                            : field.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outlineVariant
                    }
                }
                StyledText {   // a folder only: where it goes, in place of a name
                    visible: win.forFolder
                    Layout.fillWidth: true
                    text: win.folder.replace(Files.home, "~")
                    elide: Text.ElideMiddle
                    font.pixelSize: 15
                    color: Appearance.colors.colOnLayer1
                }
                Pill { label: "Cancel"; onClicked: win.asking ? (win.asking = false) : win.answer([]) }
                Pill { visible: win.asking; label: "Keep both"; onClicked: win.answer([(win.folder === "/" ? "" : win.folder) + "/" + win.keepName(win.trimmed)]) }
                Pill { visible: win.asking; label: "Replace"; main: true; onClicked: win.answer([win.target]) }
                Pill { visible: !win.asking; label: "Save"; main: true; enabledPill: win.ready; onClicked: win.accept() }
            }

            RowLayout {   // where: the folders Save As used last, or the clash
                spacing: 8
                Flow {
                    visible: !win.asking
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 22
                    Repeater {
                        model: win.chips
                        Chip {
                            required property string modelData
                            label: Files.placeName(modelData)
                            on: win.folder === modelData
                            onClicked: win.go(modelData)
                        }
                    }
                    Chip {   // the folder shown when it is none of the chips
                        visible: !win.chips.includes(win.folder)
                        label: Files.placeName(win.folder)
                        on: true
                    }
                }
                RowLayout {
                    visible: win.asking
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    spacing: 8
                    MaterialSymbol { text: "error"; iconSize: 18; color: Appearance.colors.colError }
                    StyledText {
                        Layout.fillWidth: true
                        text: `${win.trimmed} is already in ${Files.placeName(win.folder)}`
                        elide: Text.ElideMiddle
                        font.pixelSize: 15
                        color: Appearance.colors.colError
                    }
                }
            }

            Rectangle {   // the folder browser, only when asked for
                visible: win.browsing
                Layout.fillWidth: true
                Layout.preferredHeight: 360
                color: "transparent"
                Rectangle {   // a hairline between the question and the folders
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.3)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.topMargin: 10
                    spacing: 8
                    ListView {   // places and your pinned folders
                        Layout.preferredWidth: 200
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: Files.places.map(p => ({ "path": p.path, "name": Files.placeName(p.path), "glyph": p.glyph })).concat(Files.pins.filter(p => !Files.places.some(x => x.path === p)).map(p => ({ "path": p, "name": Files.placeName(p), "glyph": "push_pin" })))
                        delegate: Row2 {
                            required property var modelData
                            glyph: modelData.glyph
                            label: modelData.name
                            on: win.folder === modelData.path
                            onClicked: win.go(modelData.path)
                        }
                    }
                    ListView {   // this folder: folders to go into; files shown dim, a click takes the name
                        id: listing
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        header: Row2 {
                            width: listing.width
                            visible: win.folder !== "/"
                            height: visible ? 34 : 0
                            glyph: "arrow_upward"
                            label: `Up to ${Files.placeName(Files.parent(win.folder))}`
                            onClicked: win.go(Files.parent(win.folder))
                        }
                        model: here
                        delegate: Row2 {
                            required property string fileName
                            required property string filePath
                            required property bool fileIsDir
                            width: listing.width
                            glyph: fileIsDir ? "folder" : "draft"
                            label: fileName
                            dim: !fileIsDir
                            onClicked: {
                                if (fileIsDir)
                                    win.go(filePath);
                                else if (!win.forFolder) {
                                    win.name = fileName;
                                    focusTimer.restart();
                                }
                            }
                        }
                    }
                }
            }
        }
            }
        }
    }
}
