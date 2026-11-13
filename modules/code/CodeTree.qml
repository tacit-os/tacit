import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.claude as Praxis

/**
 * The project's folders and files, drawn the way the Files window draws a row:
 * glyph, name, the same quiet hover and selection layers. Changed files carry the
 * usual version-control colour and letter (M changed, U new, D deleted).
 * A click opens a file or folds a folder; Enter does the same from the keyboard.
 * Files git ignores are listed faint. A new file or folder is named in its own row, a rename happens in the row
 * (F2), Delete moves to the Trash, and a right click or the Menu key offers the same.
 */
ListView {
    id: tree

    property var project
    signal openFile(string rel)
    signal watchFile(string rel)        // f: watch the change type itself (a private preview)
    signal openElsewhere(string rel)    // not text: the desktop opens it
    signal menuFor(var row, real x, real y)       // a right click: the window draws the menu
    signal named(string name)                     // the draft row's name, Enter
    signal renamed(string path, string name)
    signal trash(var row)
    property string renaming: ""                  // the row whose name is being edited
    // what has been typed into it: a refresh of the rows (git moved underneath) rebuilds the field, not the name
    property string editText: ""
    readonly property bool editing: tree.renaming.length > 0 || !!(tree.project && tree.project.draft)


    model: project ? project.rows : []
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: true
    highlightMoveDuration: 0
    Praxis.FastWheel { view: tree; ease: true }
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    // the row of the file the window is showing, so the cursor and the view follow it
    readonly property int activeRow: tree.project ? tree.project.activeRow : -1
    onActiveRowChanged: if (tree.activeRow >= 0) Qt.callLater(tree.follow)
    function follow() {
        // a new current row takes the keyboard, which would end a name being typed
        if (tree.editing || tree.activeRow < 0 || tree.activeRow >= tree.count) return;
        tree.currentIndex = tree.activeRow;
        tree.positionViewAtIndex(tree.activeRow, ListView.Contain);
    }

    function activate(i) {
        const r = tree.model[i];
        if (!r || r.draft || r.status === "D") return;
        if (r.dir) tree.project.toggle(r.path);
        else if (tree.isText(r.name)) tree.openFile(r.path);
        else tree.openElsewhere(r.path);
    }

    // A picture or an archive read as text is mojibake, and a save would write that back over
    // the file, so those rows never reach the editor.
    function isText(name) {
        const g = tree.glyphFor(name);
        return g !== "image" && g !== "movie" && g !== "music_note" && g !== "picture_as_pdf"
            && g !== "folder_zip" && g !== "description";
    }

    Keys.onReturnPressed: tree.activate(tree.currentIndex)
    Keys.onEnterPressed: tree.activate(tree.currentIndex)
    Keys.onPressed: event => {
        const r = tree.model[tree.currentIndex];
        if (event.key === Qt.Key_F2 && r && !r.draft && r.status !== "D") { tree.renaming = r.path; event.accepted = true; return; }
        if (event.key === Qt.Key_Delete && r && !r.draft && r.status !== "D") { tree.trash(r); event.accepted = true; return; }
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            const item = tree.itemAtIndex(tree.currentIndex);
            if (r && item) { const at = item.mapToItem(tree, 40, item.height); tree.menuFor(r, at.x, at.y); }
            event.accepted = true; return;
        }
        if (event.key === Qt.Key_F && !(event.modifiers & Qt.ControlModifier)) {
            const r = tree.model[tree.currentIndex];
            if (r && !r.dir && r.status !== "D" && tree.isText(r.name)) tree.watchFile(r.path);
            event.accepted = true;
        }
    }

    // the glyph vocabulary of the Files window (Things.glyphFor), by extension
    function glyphFor(name) {
        const ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
        if (["png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "avif"].includes(ext)) return "image";
        if (["mp4", "mkv", "webm", "mov"].includes(ext)) return "movie";
        if (["mp3", "flac", "ogg", "wav", "m4a"].includes(ext)) return "music_note";
        if (ext === "pdf") return "picture_as_pdf";
        if (["zip", "tar", "gz", "xz", "zst", "7z"].includes(ext)) return "folder_zip";
        if (["md", "txt", "rst"].includes(ext)) return "notes";
        if (["doc", "docx", "odt", "pptx", "xlsx"].includes(ext)) return "description";
        if (["kt", "kts", "swift", "ts", "tsx", "js", "jsx", "qml", "py", "rs", "go", "c", "h", "cpp", "java", "lua",
             "sh", "fish", "json", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sql", "gradle"].includes(ext)) return "code";
        return "draft";
    }

    MouseArea {
        z: -1
        width: tree.width
        height: Math.max(tree.height, tree.contentHeight)
        acceptedButtons: Qt.RightButton
        onClicked: mouse => tree.menuFor(null, mouse.x, mouse.y - tree.contentY)
    }

    delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool isActive: !modelData.dir && !modelData.draft && !!row.view && !!row.view.project && row.view.project.active === modelData.path
        readonly property var view: ListView.view
        readonly property bool editing: !!modelData.draft || (!!row.view && row.view.renaming === modelData.path)
        width: ListView.view.width
        property real grow: 1
        height: 32 * row.grow
        opacity: row.grow
        clip: row.grow < 1
        Anim { id: growIn; target: row; property: "grow"; from: 0; to: 1; type: Anim.DefaultSpatial }
        // a row that was not there a moment ago grows in (CodeProject.fresh), as Praxis's rows do
        Component.onCompleted: if (tree.project && tree.project.fresh[tree.project.keyOf(row.modelData)]) { row.grow = 0; growIn.start(); }

        Rectangle {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
            radius: 8
            color: row.isActive ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                : (area.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent")
            Behavior on color { ColorAnimation { duration: 80 } }
        }
        // the file you are in: Praxis's sand bar at the row's edge
        Rectangle {
            visible: row.isActive
            x: 8
            y: 8
            width: 3
            height: 16
            radius: 1.5
            color: Tacit.accent
        }
        Rectangle {   // keyboard cursor without selection: a hairline, as in Files
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
            radius: 8
            color: "transparent"
            border.width: 1
            border.color: Tacit.hairline
            visible: !!row.view && row.view.activeFocus && row.view.currentIndex === row.index && !row.isActive
            opacity: 0.7
        }

        MaterialSymbol {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: 20 + row.modelData.depth * 16
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.dir ? (row.modelData.open ? "folder_open" : "folder") : (row.view ? row.view.glyphFor(row.modelData.name) : "draft")
            fill: row.modelData.dir ? 1 : 0
            iconSize: 17
            color: row.modelData.ignored ? Tacit.inkFaint : row.modelData.dir ? Tacit.inkSec
                : (row.isActive ? Tacit.inkMain : Tacit.inkMeta)
        }

        StyledText {
            anchors.left: glyph.right
            anchors.leftMargin: 8
            anchors.right: letter.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.editing
            text: row.modelData.name
            elide: Text.ElideRight
            font.pixelSize: 15
            font.family: Appearance.font.family.compact
            font.weight: row.isActive ? Font.Medium : Font.Normal
            color: row.modelData.status === "D" ? Appearance.colors.colError
                : row.modelData.status === "U" ? Appearance.m3colors.m3primary
                : row.modelData.status === "M" ? Appearance.m3colors.m3tertiary
                : row.modelData.ignored ? Tacit.inkFaint
                : row.isActive || area.containsMouse ? Tacit.inkMain : Tacit.inkSec
            font.strikeout: row.modelData.status === "D"
        }

        // naming: the draft's name, or a rename, typed where the name stands
        Loader {
            anchors { left: glyph.right; leftMargin: 6; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            height: 24
            active: row.editing
            sourceComponent: Rectangle {
                radius: 6
                color: "transparent"
                border.width: 1
                border.color: Tacit.accent
                TextInput {
                    id: nameField
                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                    verticalAlignment: TextInput.AlignVCenter
                    font.hintingPreference: Font.PreferNoHinting
                    font.pixelSize: 15
                    font.family: Appearance.font.family.compact
                    color: Tacit.inkMain
                    selectionColor: Appearance.colors.colSecondaryContainer
                    clip: true
                    property bool done: false
                    property bool had: false        // only a field that had the keyboard is left by losing it
                    Component.onCompleted: {
                        if (tree.editText.length) text = tree.editText;
                        else if (!row.modelData.draft) {
                            text = row.modelData.name.split("/").pop();
                            const dot = text.lastIndexOf(".");
                            select(0, row.modelData.dir || dot <= 0 ? text.length : dot);   // the name, not its extension
                        }
                        // after the list has settled on its new rows: focus taken mid-update was lost again
                        Qt.callLater(() => { if (!nameField.done) nameField.forceActiveFocus(); });
                    }
                    onTextChanged: if (row.view) row.view.editText = text
                    function finish(keep) {
                        if (done) return;
                        done = true;
                        tree.editText = "";
                        if (row.modelData.draft) { if (keep && text.trim().length) tree.named(text.trim()); else tree.project.endDraft(); }
                        else { const path = row.modelData.path; tree.renaming = "";
                            if (keep && text.trim().length && text.trim() !== row.modelData.name) tree.renamed(path, text.trim()); }
                        tree.forceActiveFocus();
                    }
                    Keys.onReturnPressed: finish(true)
                    Keys.onEnterPressed: finish(true)
                    Keys.onEscapePressed: finish(false)
                    onActiveFocusChanged: { if (activeFocus) had = true; else if (had) finish(false); }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: nameField.text.length === 0
                        text: row.modelData.dir ? "Folder name" : "File name"
                        font.pixelSize: 15
                        color: Tacit.inkFaint
                    }
                }
            }
        }

        StyledText {
            id: letter
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.editing
            text: row.modelData.dir ? "" : row.modelData.status
            font.pixelSize: 13
            font.family: Appearance.font.family.numbers
            color: row.modelData.status === "D" ? Appearance.colors.colError
                : row.modelData.status === "U" ? Appearance.m3colors.m3primary : Appearance.m3colors.m3tertiary
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: !row.editing
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                tree.currentIndex = row.index;
                if (mouse.button === Qt.RightButton) { const at = mapToItem(tree, mouse.x, mouse.y); tree.menuFor(row.modelData, at.x, at.y); }
                else tree.activate(row.index);
            }
        }
    }
}
