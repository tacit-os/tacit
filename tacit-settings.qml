//@ pragma UseQApplication
//@ pragma AppId settings
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Tacit's settings: an ordinary window, its own process
// (`qs -p ~/.config/quickshell/tacit/tacit-settings.qml`), so a fault here cannot take the
// notch or the panels with it - the same rule Praxis and Graphis follow.
//
// The categories are what a person is looking for ("the screen", "sound"), not which file the
// setting lives in. End4's pages were named after their implementation; the settings themselves
// are carried over unchanged.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.tacit
import "modules/settings"
import "modules/claude" as Praxis

ApplicationWindow {
    id: root

    visible: true
    // An app does not reload itself when a file in the shared config changes: a reload rebuilt the
    // window as visible, so every deploy (even one only for the shell) popped a closed app back up.
    // New code arrives the next time the app starts.
    Binding { target: Quickshell; property: "watchFiles"; value: false }
    title: "Settings"
    minimumWidth: 760
    minimumHeight: 540
    width: 1120
    height: 780
    // Transparent window with the shell's own layer colour painted inside it: the compositor
    // blurs what is behind, so this window sits on the wallpaper the way the panels do instead
    // of being an opaque grey box on a frosted desktop.
    color: "transparent"

    property int current: 0
    // bumped when ~/.face has been copied over, so the rail's picture and the account page's read it again
    property int faceVersion: 0
    Process {
        id: faceCopy
        onExited: root.faceVersion += 1
    }
    // A page switch: the new page is built and laid out unseen (its rows settled over the first
    // frames, a flicker), then comes in from the top of the scroll, rising 6 px as it fades in.
    onCurrentChanged: { root.revealPage(); Qt.callLater(root.revealInRail); }
    // The open place stays in view in the rail: a page opened from outside (a link to About, Down
    // from the search) used to light a row that was scrolled out of sight.
    function revealInRail() {
        const row = railRepeater.itemAt(root.current);
        if (!row || !row.visible)
            return;
        const max = Math.max(0, railScroll.contentHeight - railScroll.height);
        if (row.y < railScroll.contentY)
            railScroll.contentY = Math.max(0, row.y);
        else if (row.y + row.height > railScroll.contentY + railScroll.height)
            railScroll.contentY = Math.min(max, row.y + row.height - railScroll.height + 4);
    }
    function revealPage() {
        pageScroll.contentY = 0;
        pageIn.stop();
        pageColumn.opacity = 0;
        pageRise.y = 6;
        pageReveal.restart();
    }
    Timer { id: pageReveal; interval: 40; onTriggered: pageIn.restart() }
    ParallelAnimation {
        id: pageIn
        Anim { target: pageColumn; property: "opacity"; to: 1; type: Anim.DefaultEffects }
        Anim { target: pageRise; property: "y"; to: 0; type: Anim.FastSpatial }
    }

    // Singletons are lazy: nothing here referenced the theme loader, so this process never read
    // the generated palette and drew everything in Appearance.qml's grey defaults. Starting it
    // also watches the palette file, so a wallpaper change reaches Settings the way it reaches
    // the shell.
    // open.sh passes the page to start on when it has to start Settings
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        root.showPage(Quickshell.env("TACIT_SETTINGS_PAGE") ?? "");
    }
    // Closing ends the process. ApplicationWindow only hides on close, so each closed Settings
    // left a quickshell instance running with nothing on screen, and a relaunch added another.
    // Graphis ends itself the same way (code.qml).
    onClosing: {
        // a Files window still open for a pick would answer a Settings that is gone: it is closed with us
        if (root.pickDone !== null)
            Quickshell.execDetached(["qs", "-p", Directories.shellFile, "ipc", "call", "files", "cancelpick", "settingsApp"]);
        // a display change not kept yet goes back, as when the countdown ends: the countdown ends with this process
        if (root.displayKeepLeft > 0)
            root.restoreDisplay();
        Qt.quit();
    }
    property string query: ""
    // installed families, for the two font rows; picking from these cannot name a missing font
    readonly property var fontOptions: [...new Set(Qt.fontFamilies())].map(f => ({ value: f, label: f }))

    readonly property var categories: SettingsCatalog.categories

    // ── the frame ────────────────────────────────────────────────────────────
    // The photo editor mock's Studio form: the window's ground, a top line with the name and the
    // search, the places on an inset slab, the page beside it. The ground is Praxis's
    // (claude.qml): the terminal's own background, which the compositor blurs the wallpaper through.
    FileView {
        id: termColors
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/terminal/sequences.txt`)
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property color termBase: {
        const m = /\]11;(#[0-9a-fA-F]{6})/.exec(termColors.text() || "");
        return m ? m[1] : Appearance.m3colors.m3surfaceContainerLow;
    }
    // Praxis's frosted window (15 % through), whatever See-through is set to: the apps keep one look
    readonly property real seeThrough: Tacit.windowSeeThrough
    // what See-through is set to, for the notch and panels (the Appearance preview shows it)
    readonly property real seeThroughSetting: !Config.options.appearance.transparency.enable ? 0
        : Config.options.appearance.transparency.automatic ? 0.15 : Config.options.appearance.transparency.backgroundTransparency
    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(root.termBase, root.seeThrough)
    }

    readonly property var clusterNames: ["Look and feel", "Connections", "This computer", "Apps and accounts"]

    function matches(cat) {
        const q = root.query.trim().toLowerCase();
        return q.length === 0 || `${cat.name} ${cat.note} ${cat.words ?? ""}`.toLowerCase().includes(q);
    }
    // Typing narrows the places; when the page on show falls out of them, the first match takes over.
    onQueryChanged: {
        if (root.matches(root.categories[root.current])) return;
        const i = root.categories.findIndex(c => root.matches(c));
        if (i >= 0) root.current = i;
    }

    // ── no top bar: you and the search head the rail (Apple's account row, Windows' search above
    // the places); the page starts at the top beside it
    Item {
        id: topLine
        height: 12
    }

    // ── the places: names only, in four groups; the open one on the raised wash
    Rectangle {
        id: rail
        x: 16
        y: topLine.height
        // a tiled window can be far narrower than minimumWidth: the rail gives way before the page does
        width: Math.min(264, Math.max(176, Math.round(root.width * 0.34)))
        height: parent.height - y - 16
        // on the window's ground, as Praxis's sessions rail: no slab of its own
        color: "transparent"

        // you: your picture and name, opening Your account
        Rectangle {
            id: meRow
            readonly property int page: root.categories.findIndex(c => c.key === "account")
            x: 8
            y: 2
            width: rail.width - 16
            height: 58
            radius: 10
            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface,
                meArea.pressed ? 0.88 : root.current === meRow.page ? 0.9 : meArea.containsMouse ? 0.95 : 1)
            Behavior on color { enabled: !meArea.pressed; ColorAnimation { duration: 110 } }
            Rectangle {
                id: meFace
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 20
                color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: meFace.width; height: meFace.height; radius: meFace.radius }
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: meImage.status !== Image.Ready
                    text: Array.from(Config.options.profile.displayName || SystemInfo.username || "?")[0].toUpperCase()
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colInkMain
                }
                Image {
                    id: meImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    // the query changes the url, so a new picture over the same file is read again
                    source: `file://${Quickshell.env("HOME")}/.face?${root.faceVersion}`
                    sourceSize: Qt.size(72, 72)
                }
            }
            Column {
                anchors.left: meFace.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                StyledText {
                    width: parent.width
                    text: Config.options.profile.displayName || SystemInfo.username
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    color: Appearance.colors.colInkMain
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: "Your account"
                    font.pixelSize: 13
                    color: Tacit.inkMeta
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                id: meArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (meRow.page >= 0) root.current = meRow.page
            }
        }

        Rectangle {
            id: searchBox
            x: 8
            y: meRow.y + meRow.height + 10
            width: rail.width - 16
            height: 38
            radius: 10
            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95)
            border.width: 1
            border.color: searchInput.activeFocus ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.15)
                : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93)
            Behavior on border.color { ColorAnimation { duration: 120 } }

            MaterialSymbol {
                id: searchGlyph
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                iconSize: 18
                color: Tacit.inkMeta
            }
            TextInput {
                id: searchInput
                anchors.left: searchGlyph.right
                anchors.leftMargin: 9
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 15
                font.family: Appearance.font.family.main
                color: Appearance.colors.colInkMain
                selectionColor: Appearance.colors.colPrimary
                clip: true
                focus: true
                onTextChanged: root.query = text
                // Up and Down walk the pages that match; Tab goes on into the page
                Keys.onDownPressed: root.stepPage(1)
                Keys.onUpPressed: root.stepPage(-1)
                Keys.onEscapePressed: {
                    if (text.length > 0) text = "";
                    else root.close();
                }
            }
            StyledText {
                anchors.left: searchInput.left
                anchors.verticalCenter: parent.verticalCenter
                visible: searchInput.text.length === 0
                text: "Search settings"
                font.pixelSize: 15
                color: Tacit.inkMeta
            }
        }

        // a search that finds no place says so, and how to get the places back
        StyledText {
            visible: root.query.trim().length > 0 && !root.categories.some(c => root.matches(c))
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: searchBox.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 20
            text: `No setting is named "${root.query.trim()}". Clear the search to see them all.`
            font.pixelSize: 15
            color: Tacit.inkSec
            wrapMode: Text.Wrap
        }

        Flickable {
            id: railScroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.top: searchBox.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 6
            contentHeight: railList.implicitHeight + 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: railList
                width: railScroll.width
                spacing: 2

                Repeater {
                    id: railRepeater
                    model: root.categories
                    Column {
                        id: catRow
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: root.current === index
                        readonly property bool opensCluster: root.query.length === 0
                            && (catRow.index === 0 || root.categories[catRow.index - 1].cluster !== catRow.modelData.cluster)
                        visible: root.matches(catRow.modelData)
                        width: railList.width

                        Item {
                            visible: catRow.opensCluster
                            width: parent.width
                            height: catRow.index === 0 ? 30 : 54
                            StyledText {
                                x: 12
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 7
                                text: root.clusterNames[catRow.modelData.cluster] ?? ""
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: Tacit.inkSec
                            }
                        }
                        Rectangle {
                            // the Accounts row carries a second line: how many agents are ready, or what the first needs
                            readonly property string line: catRow.modelData.key === "accounts" ? root.accountsLine : ""
                            width: parent.width
                            height: line.length > 0 ? 52 : 38
                            radius: 9
                            color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, catArea.pressed ? 0.82 : catRow.isCurrent ? 0.86 : catArea.containsMouse ? 0.95 : 1)
                            Behavior on color { enabled: !catArea.pressed; ColorAnimation { duration: 110 } }

                            MaterialSymbol {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: catRow.modelData.glyph
                                iconSize: 19
                                color: catRow.isCurrent ? Appearance.colors.colInkMain : Tacit.inkMeta
                            }
                            StyledText {
                                x: 44
                                width: parent.width - x - 10
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: parent.line.length > 0 ? -8 : 0
                                text: catRow.modelData.name
                                font.pixelSize: 15
                                color: catRow.isCurrent ? Appearance.colors.colInkMain : Tacit.inkSec
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: parent.line.length > 0
                                x: 44
                                y: parent.height / 2 + 4
                                width: parent.width - x - 10
                                text: parent.line
                                font.pixelSize: 12
                                color: Tacit.inkMeta
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                id: catArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.current = catRow.index
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Display changes are kept only when asked. A scale, resolution or position is written to monitors.lua and
    // loaded at once; a mode the monitor or cable cannot carry leaves a blank screen with nothing to click, so the
    // old file waits in the runtime folder for 15 s and comes back unless Keep is pressed (the way other desktops
    // ask). It lives here and not on the Display page, so leaving the page does not lose the way back.
    property int displayKeepLeft: 0
    readonly property string displayBackupBase: 'b="${XDG_RUNTIME_DIR:-/tmp}/tacit-monitors"; '
    Timer {
        interval: 1000
        repeat: true
        running: root.displayKeepLeft > 0
        onTriggered: {
            root.displayKeepLeft -= 1;
            if (root.displayKeepLeft === 0)
                root.restoreDisplay();
        }
    }
    function keepDisplay() {
        root.displayKeepLeft = 0;
        Quickshell.execDetached(["bash", "-c", root.displayBackupBase + 'rm -f "$b.previous" "$b.absent"']);
    }
    // the file as it was, or none when there was none (then Hyprland's own monitor lines apply again)
    function restoreDisplay() {
        root.displayKeepLeft = 0;
        Quickshell.execDetached(["bash", "-c", 'f="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitors.lua"; ' + root.displayBackupBase
            + 'if [ -e "$b.previous" ]; then cp -f "$b.previous" "$f"; elif [ -e "$b.absent" ]; then rm -f "$f"; else exit 0; fi; '
            + 'rm -f "$b.previous" "$b.absent"; hyprctl reload >/dev/null']);
    }
    // Esc goes back, as the bar says
    Shortcut {
        sequence: "Escape"
        enabled: root.displayKeepLeft > 0
        onActivated: root.restoreDisplay()
    }
    Rectangle {
        z: 10
        visible: root.displayKeepLeft > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        width: keepRow.implicitWidth + 40
        height: 52
        radius: 18
        // solid, as the Files pick bar: frost over this window's own glass does not read
        color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.04)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.4)
        Row {
            id: keepRow
            anchors.centerIn: parent
            spacing: 12
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "desktop_windows"
                iconSize: 20
                color: Appearance.colors.colPrimary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `Keep these display settings? Going back in ${root.displayKeepLeft} s`
                font.pixelSize: 15
                color: Tacit.inkMain
            }
            TextButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Go back"
                onPressed: root.restoreDisplay()
            }
            TextButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Keep"
                onPressed: root.keepDisplay()
            }
        }
    }

    // ── the page: its name, one line of what it covers, then its groups
    Flickable {
        id: pageScroll
        x: rail.x + rail.width + 24
        y: topLine.height
        width: parent.width - x - 16
        height: parent.height - y
        contentHeight: pageColumn.implicitHeight + 28
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: pageColumn
            transform: Translate { id: pageRise }
            // Escape from anywhere in the page closes Settings, as it does from the search; a row
            // that uses Escape itself (a field, a menu) takes it first
            Keys.onEscapePressed: root.close()
            // up to 1000 wide (Windows Settings' content width), in the middle of the room beside the
            // rail (left-aligned read as lopsided full screen)
            x: Math.max(16, Math.floor((pageScroll.width - width) / 2))
            width: Math.min(1000, pageScroll.width - 40)
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.leftMargin: 20
                text: root.categories[root.current].name
                font.pixelSize: 30
                font.weight: Font.DemiBold
                color: Appearance.colors.colInkMain
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 20
                text: root.categories[root.current].note
                font.pixelSize: 15
                color: Tacit.inkSec
                wrapMode: Text.Wrap
            }

            // config.json has a mistake in it: what is set here looks set but is not kept (Config.fileBroken)
            Group {
                visible: Config.fileBroken
                SettingRow {
                    clickable: false
                    glyph: "warning"
                    label: "Changes here aren't saved"
                    description: Config.backupUsable
                        ? "Your settings file has a mistake in it, so Tacit is using its defaults. Restore puts back the last good copy."
                        : `Your settings file has a mistake in it, so Tacit is using its defaults until it's fixed: ${Config.filePath}`
                    control: TextButton {
                        visible: Config.backupUsable
                        label: "Restore"
                        onPressed: Config.restoreBackup()
                    }
                }
            }

            Loader {
                id: pageLoader
                Layout.fillWidth: true
                Layout.topMargin: 10
                sourceComponent: root.categories[root.current].key === "look" ? lookPage
                    : root.categories[root.current].key === "desktop" ? desktopPage
                    : root.categories[root.current].key === "bluetooth" ? bluetoothPage
                    : root.categories[root.current].key === "sound" ? soundPage
                    : root.categories[root.current].key === "network" ? networkPage
                    : root.categories[root.current].key === "notch" ? notchPage
                    : root.categories[root.current].key === "windows" ? windowsPage
                    : root.categories[root.current].key === "notifications" ? notificationsPage
                    : root.categories[root.current].key === "access" ? accessPage
                    : root.categories[root.current].key === "palette" ? palettePage
                    : root.categories[root.current].key === "time" ? timePage
                    : root.categories[root.current].key === "account" ? accountPage
                    : root.categories[root.current].key === "accounts" ? accountsPage
                    : root.categories[root.current].key === "display" ? displayPage
                    : root.categories[root.current].key === "lock" ? lockPage
                    : root.categories[root.current].key === "input" ? inputPage
                    : root.categories[root.current].key === "apps" ? appsPage
                    : root.categories[root.current].key === "about" ? aboutPage
                    : soonPage
            }
        }
    }

    // A sound device in plain words: "Built-in Audio Speaker playback" is Speakers, a bracketed
    // kind ("(echo cancelled)") goes to the second line, and the card's own device beside a tuned or
    // echo-cancelled one says what it lacks. Only beside one: where no such chain is set up (only the
    // Book4 Edge's package sets one up) the card's own device is all there is and lacks nothing.
    function soundName(d, alone) {
        let s = (d.description || d.nickname || d.name || "").replace(/^Built-in Audio\s+/i, "");
        let line = "";
        const m = /\s*\(([^)]+)\)\s*$/.exec(s);
        if (m) { line = m[1].charAt(0).toUpperCase() + m[1].slice(1); s = s.slice(0, m.index); }
        s = s.replace(/\s+(playback|capture)$/i, "");
        if (/^speakers?$/i.test(s)) s = "Speakers";
        else if (/^(internal )?microphones?$/i.test(s)) s = "Microphones";
        // the chain: another device of the same name, not the card's, with a kind of its own ("Speakers (tuned)")
        const chain = list => !alone && list.some(o => o !== d && !/^alsa_/.test(o.name ?? "")
            && root.soundName(o, true).label === s && root.soundName(o, true).line !== "");
        if (!line && /^alsa_output/.test(d.name ?? "") && s === "Speakers" && chain(Audio.outputDevices)) line = "Without tuning";
        if (!line && /^alsa_input/.test(d.name ?? "") && s === "Microphones" && chain(Audio.inputDevices)) line = "Without echo cancelling";
        return { label: s, line: line };
    }

    // The Lock page's times, read from hypridle.conf rather than written into this file: they were
    // literals that stayed "5 min" whatever the config said. A listener is told apart by what its
    // on-timeout runs.
    property var idleTimes: ({})
    // a few durations in minutes as choices, plus the current one when the config holds another
    function minuteOptions(list, now) {
        return (list.includes(now) ? list : [...list, now].sort((x, y) => x - y)).map(m => ({ value: m, label: root.durationText(m * 60) }));
    }
    function durationText(secs) {
        return secs < 60 ? `${secs} s` : secs < 3600 ? `${Math.round(secs / 60)} min` : `${+(secs / 3600).toFixed(1)} h`;
    }
    // the offered times, plus the current one when the file holds a value not among them
    function idleOptions(kind, times) {
        const cur = root.idleTimes[kind];
        const all = cur !== undefined && !times.includes(cur) ? [...times, cur].sort((a, b) => a - b) : times;
        return all.map(t => ({ value: t, label: root.durationText(t) }));
    }
    function idleKind(run) {
        return /suspend|hibernate/.test(run) ? "sleep" : /dpms/.test(run) ? "screen" : /lock/.test(run) ? "lock" : "";
    }
    // The first line of the copy Settings makes: at each login the rest of a copy so marked is brought up to the packaged
    // file, the times kept (scripts/hyprland/hypridle_refresh.py, its MARK), so a later fix to that file still reaches it
    readonly property string idleMark: "# Made by Settings > Lock & sleep from Tacit's hypridle.conf, with your times: the rest is Tacit's again at each login. Delete this line to keep edits of your own."
    // Rewrites one listener's timeout line and nothing else, comments and commands kept, then
    // restarts hypridle, which reads its config only when it starts.
    function setIdleTime(kind, secs) {
        // a fresh install has only the packaged file: the edited copy becomes the user's own, which hypridle reads first
        const own = idleFile.text() !== "";
        const lines = (own ? idleFile.text() : idlePackaged.text()).split("\n");
        let inBlock = false, at = -1, run = "";
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (/^\s*listener\s*\{/.test(l)) {
                inBlock = true;
                at = -1;
                run = "";
                continue;
            }
            if (!inBlock)
                continue;
            if (/^\s*timeout\s*=/.test(l))
                at = i;
            const m = l.match(/^\s*on-timeout\s*=\s*(.*)$/);
            if (m)
                run = m[1];
            if (/^\s*\}/.test(l)) {
                inBlock = false;
                if (root.idleKind(run) !== kind || at < 0)
                    continue;
                lines[at] = `${lines[at].match(/^\s*/)[0]}timeout = ${secs}`;
                const restart = "if systemctl --user -q is-active hypridle; then systemctl --user restart hypridle; else pkill -x hypridle; hyprctl dispatch 'hl.dsp.exec_cmd(\"hypridle\")'; fi";
                if (own) {
                    // the write is asynchronous: idleFile's onSaved restarts hypridle once the new timeout is in the file
                    idleFile.setText(lines.join("\n"));
                } else {
                    Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1" && ' + restart, "_", FileUtils.trimFileProtocol(`${Directories.config}/hypr/hypridle.conf`), [root.idleMark, ...lines].join("\n")]);
                    root.idleTimes = Object.assign({}, root.idleTimes, { [kind]: secs });
                    idleReload.restart();
                }
                return;
            }
        }
    }
    function parseIdle(text) {
        const t = {};
        for (const block of text.split(/^\s*listener\s*\{/m).slice(1)) {
            const secs = parseInt((block.match(/^\s*timeout\s*=\s*(\d+)/m) ?? [])[1]);
            const run = (block.match(/^\s*on-timeout\s*=\s*(.*)$/m) ?? [])[1] ?? "";
            const kind = root.idleKind(run);
            if (kind && !isNaN(secs) && !(kind in t)) t[kind] = secs;
        }
        return t;
    }
    // XDG_CONFIG_DIRS holds the packaged hypridle.conf; ~/.config/hypr has one only once the times were changed
    FileView {
        id: idlePackaged
        path: "/usr/share/tacit/xdg/hypr/hypridle.conf"
        printErrors: false
        onLoaded: {
            if (idleFile.text() === "")
                root.idleTimes = root.parseIdle(idlePackaged.text());
        }
    }
    // the user's copy was just created: read it, so the next change edits it and not the packaged one again
    Timer {
        id: idleReload
        interval: 400
        onTriggered: idleFile.reload()
    }
    FileView {
        id: idleFile
        path: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hypridle.conf`)
        watchChanges: true
        printErrors: false
        onFileChanged: idleFile.reload()
        // the write is asynchronous: hypridle is restarted once the new timeout is in the file
        onSaved: Quickshell.execDetached(["bash", "-c", "if systemctl --user -q is-active hypridle; then systemctl --user restart hypridle; else pkill -x hypridle; hyprctl dispatch 'hl.dsp.exec_cmd(\"hypridle\")'; fi"]);
        onLoaded: {
            root.idleTimes = root.parseIdle(idleFile.text());
        }
    }

    // The battery, read from UPower here for its level and health, chosen the way the shell's Battery
    // service chooses it (services/Battery.qml). Its times are that service's: only the shell suspends
    // with it (Battery.suspends), and its notices are the shell's IslandController's.
    readonly property var batteryDevice: UPower.devices.values.find(d => d.isLaptopBattery && (d.nativePath ?? "").includes("book4-ec")) ?? UPower.displayDevice
    readonly property bool hasBattery: root.batteryDevice?.isLaptopBattery ?? false
    function batteryTime(secs) {
        const t = Math.round(secs / 60), h = Math.floor(t / 60), m = t % 60;
        return h > 0 ? `${h} h ${m} min` : `${m} min`;
    }
    // "7:5" or "19.30" to "07:05" / "19:30"; null when it is not a time of day
    function clockTime(text) {
        const m = String(text).trim().match(/^(\d{1,2})[:.](\d{2})$/);
        if (!m || +m[1] > 23 || +m[2] > 59)
            return null;
        return `${m[1].padStart(2, "0")}:${m[2]}`;
    }

    // Startup apps are {cmd, workspace, delay}; scripts/hyprland/autostart.py runs them at login.
    readonly property var appEntries: Array.from(DesktopEntries.applications.values).filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property var appOptions: root.appEntries.map(e => ({ value: e.id, label: e.name }))
    function plainExec(entry) {
        return (entry?.execString ?? "").replace(/\s*%[fFuUdDnNickvm]/g, "").trim();
    }
    function appName(cmd) {
        const e = root.appEntries.find(x => root.plainExec(x) === cmd);
        return e ? e.name : (cmd.split(" ")[0].split("/").pop() || cmd);
    }
    function startupList() {
        return Config.options.hyprland.autostartApps.apps.map(o => ({ cmd: o.cmd, workspace: o.workspace ?? 1, delay: o.delay ?? 0 }));
    }
    function addStartup(id) {
        const e = root.appEntries.find(x => x.id === id);
        if (!e)
            return;
        Config.options.hyprland.autostartApps.apps = [...root.startupList(), { cmd: root.plainExec(e), workspace: 1, delay: 0 }];
    }
    function setStartup(index, workspace) {
        const list = root.startupList();
        list[index].workspace = workspace;
        Config.options.hyprland.autostartApps.apps = list;
    }
    function removeStartup(index) {
        Config.options.hyprland.autostartApps.apps = root.startupList().filter((o, i) => i !== index);
    }

    // Dictation: Flow's words (~/.config/flow/words.txt, one per line, # for comments kept as they
    // are) and the key bound to quickshell:flowHold.
    // Flow is not packaged (session/flow/README.md): without flowd's user service the Dictation group, a word list and a
    // key for a dictation that is not there, is hidden. Unknown is installed, as Dictation.qml has it.
    property bool flowInstalled: false
    Process {
        running: true
        command: ["systemctl", "--user", "show", "-P", "LoadState", "flowd.service"]
        stdout: StdioCollector { onStreamFinished: root.flowInstalled = text.trim() !== "not-found" }
    }
    readonly property string flowWordsPath: FileUtils.trimFileProtocol(`${Directories.config}/flow/words.txt`)
    property var flowWords: []
    property string flowWordsHeader: ""
    FileView {
        id: flowWordsFile
        path: root.flowWordsPath
        printErrors: false
        watchChanges: true
        onFileChanged: flowWordsFile.reload()
        onLoaded: {
            const lines = flowWordsFile.text().split("\n");
            root.flowWordsHeader = lines.filter(l => l.trim().startsWith("#")).join("\n");
            root.flowWords = lines.map(l => l.trim()).filter(l => l.length > 0 && !l.startsWith("#"));
        }
        // the list on show is the saved one: it takes the new words only once they are written
        onSaved: root.flowWords = root.flowWordsPending
    }
    // FileView does not create missing folders, so make the flow folder first and write when mkdir is done.
    property var flowWordsPending: []
    Process {
        id: flowDirMaker
        command: ["mkdir", "-p", FileUtils.trimFileProtocol(`${Directories.config}/flow`)]
        onExited: {
            const head = root.flowWordsHeader.length > 0 ? root.flowWordsHeader : "# One term per line: Flow spells these exactly.";
            flowWordsFile.setText(`${head}\n${root.flowWordsPending.join("\n")}\n`);
        }
    }
    function setFlowWords(words) {
        root.flowWordsPending = words;
        flowDirMaker.running = false;
        flowDirMaker.running = true;
    }
    // The key: Tacit's binds (session/hypr/tacit/keybinds.lua, in the flow submap too) are on TACIT_FLOW_KEY where
    // Settings' block in custom/variables.lua sets it, else on the Copilot key. A copy appended to custom/keybinds.lua
    // before they were packaged binds a key of its own, so where there is one it goes along to the same key.
    readonly property string flowDefaultKey: "SUPER + SHIFT + F23"
    property string flowKeyChosen: ""
    property string flowKeyOld: ""
    readonly property string flowKey: root.flowKeyChosen || root.flowKeyOld || root.flowDefaultKey
    readonly property var flowKeyOptions: {
        const known = [
            { value: "SUPER + SHIFT + F23", label: "Copilot key (tap)" },
            { value: "SUPER + SHIFT + D", label: "Super + Shift + D" },
            { value: "SUPER + ALT + D", label: "Super + Alt + D" }
        ];
        return known.some(k => k.value === root.flowKey) || root.flowKey.length === 0 ? known
            : [...known, { value: root.flowKey, label: root.flowKey }];
    }
    FileView {
        id: customKeybinds
        path: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
        printErrors: false
        watchChanges: true
        onFileChanged: customKeybinds.reload()
        // the write is asynchronous: Hyprland reloads once the new key is in the file
        onSaved: Quickshell.execDetached(["hyprctl", "reload"])
        onLoaded: {
            const m = customKeybinds.text().match(/hl\.bind\("([^"]+)", hl\.dsp\.global\("quickshell:flowHold"\)/);
            root.flowKeyOld = m ? m[1] : "";
        }
    }
    FileView {
        id: customVariables
        path: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/variables.lua`)
        printErrors: false
        watchChanges: true
        onFileChanged: customVariables.reload()
        onLoaded: root.flowKeyChosen = customVariables.text().match(/^TACIT_FLOW_KEY = "([^"]+)"$/m)?.[1] ?? ""
        onLoadFailed: root.flowKeyChosen = ""
    }
    function setFlowKey(key) {
        if (root.flowKeyOld.length > 0 && root.flowKeyOld !== key) {
            customKeybinds.setText(customKeybinds.text().split(`hl.bind("${root.flowKeyOld}", hl.dsp.global("quickshell:flowHold")`)
                .join(`hl.bind("${key}", hl.dsp.global("quickshell:flowHold")`));
            root.flowKeyOld = key;
        }
        // the Copilot key is Tacit's own: no block
        root.flowKeyChosen = key === root.flowDefaultKey ? "" : key;
        Quickshell.execDetached(["bash", "-c", 'python3 "$@" && hyprctl reload >/dev/null', "_", `${Directories.scriptPath}/settings/managed_block.py`,
            FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/variables.lua`), "flowkey"].concat(root.flowKeyChosen ? [`TACIT_FLOW_KEY = "${key}"`] : []));
    }

    // Files and folders are picked in Tacit's own Files (Pinax), the pick mode Praxis attaches
    // with (services/Files.qml pick): a Files window with a Choose bar, whose choice comes back
    // through `settingsApp picked`. The callback gets the first path; Cancel calls nothing.
    // A folder is `pickdir`: Choose with nothing selected takes the folder the window shows, where
    // `pick` waits for a file to be selected and would hand back a picture for a wallpaper folder.
    readonly property string selfPath: FileUtils.trimFileProtocol(Quickshell.shellPath("tacit-settings.qml"))
    property var pickDone: null
    property bool pickImages: false
    function startPick(folder, label, images, dir, done) {
        root.pickDone = done;
        root.pickImages = images;
        Quickshell.execDetached(["qs", "-p", Directories.shellFile, "ipc", "call", "files", dir ? "pickdir" : "pick",
            folder || Quickshell.env("HOME"), root.selfPath, "settingsApp", label]);
    }
    function pickFile(label, folder, done) {
        root.startPick(folder, label, true, false, done);
    }
    function pickFolder(label, folder, done) {
        root.startPick(folder, `${label} · select it, then Choose`, false, true, done);
    }
    // A pick's callback runs long after it was made, so it must not reach for a page's ids: a page is
    // built only while it is shown, and the wallpaper tile's callback calls this, not the page
    function applyWallpaper(path) {
        Quickshell.execDetached(["qs", "-p", Directories.shellFile, "ipc", "call", "wallpapers", "apply", path]);
    }
    // the list arrives as JSON text, as one path, or already unwrapped (claude.qml's picked)
    function receivePick(json) {
        let paths;
        try {
            paths = JSON.parse(json);
        } catch (e) {
            paths = json;
        }
        if (typeof paths === "string")
            paths = paths.split("\n");
        const path = (paths ?? []).map(p => String(p).trim()).find(p => p.length > 0
            && (!root.pickImages || /\.(png|jpe?g|webp|avif|gif|bmp)$/i.test(p)));
        const done = root.pickDone;
        root.pickDone = null;
        if (path && done)
            done(path);
    }

    // xkb's own list of layouts, code and name, for the keyboard page
    property var xkbLayouts: []
    FileView {
        id: xkbRules
        path: "/usr/share/X11/xkb/rules/base.lst"
        printErrors: false
        onLoaded: {
            const out = [];
            let inLayouts = false;
            for (const l of xkbRules.text().split("\n")) {
                if (l.startsWith("!")) {
                    inLayouts = l.trim() === "! layout";
                    continue;
                }
                const m = inLayouts ? l.match(/^\s+(\S+)\s+(.+)$/) : null;
                if (m)
                    out.push({ value: m[1], label: m[2].trim() });
            }
            root.xkbLayouts = out.sort((a, b) => a.label.localeCompare(b.label));
        }
    }
    // Layouts that cannot type Latin letters (a Wi-Fi name, the password at the lock), as Setup has them (setupd.py's
    // NON_LATIN): Setup puts US before one, with Alt + Shift to switch, and so does the keyboard page
    readonly property var nonLatinLayouts: ["af", "am", "ara", "bd", "bg", "bt", "by", "eg", "et", "ge", "gr", "il", "in", "iq", "ir",
        "kg", "kh", "kz", "la", "lk", "ma", "mk", "mm", "mn", "mv", "my", "np", "pk", "rs", "ru", "sy", "th", "tj", "ua", "uz"]
    // the layout typed in, of the ones Hyprland has: the second of Setup's US + non-Latin pair, else the first
    function typedLayout(codes) {
        return codes.length > 1 && codes[0] === "us" && root.nonLatinLayouts.includes(codes[1]) ? codes[1] : codes[0];
    }
    // The layouts once that one is replaced by the one picked, the ones after it kept: { layout, options }. A non-Latin
    // pick comes after US with Alt + Shift to switch (options), or a Latin password could not be typed at the lock.
    function pickLayout(codes, value) {
        const rest = codes.slice(root.typedLayout(codes) === codes[0] ? 1 : 2).filter(c => c !== value);
        if (!root.nonLatinLayouts.includes(value))
            return { layout: [value, ...rest].join(","), options: "" };
        return { layout: ["us", value, ...rest.filter(c => c !== "us")].join(","), options: "grp:alt_shift_toggle" };
    }

    // Pairs asked for on the Bluetooth page, by address. Held here, not on the row: the row leaves
    // the Nearby list the moment the device bonds, before it could trust and connect it.
    property var pendingPairs: []
    // when each was asked, in ms: a row that is gone before its own 15 s timer fires (the page closed, the device
    // left the scan) leaves its pair here, which would read "Pairing…" for ever and trust the device on a later pair
    property var pairAsked: ({})
    Timer {
        interval: 5000
        running: root.pendingPairs.length > 0
        repeat: true
        onTriggered: root.pendingPairs = root.pendingPairs.filter(a => Date.now() - (root.pairAsked[a] ?? 0) < 20000)
    }
    Variants {
        model: Bluetooth.devices.values
        Connections {
            required property var modelData
            target: modelData
            function onPairedChanged() {
                if (!modelData.paired || !root.pendingPairs.includes(modelData.address))
                    return;
                root.pendingPairs = root.pendingPairs.filter(a => a !== modelData.address);
                modelData.trusted = true;
                modelData.connect();
            }
        }
    }

    // Opening a given page from outside: scripts/settings/open.sh calls this for every way into
    // Settings (the keys, the control panel, the palette), so they land where the thing is.
    IpcHandler {
        target: "settingsApp"
        function page(key: string): void {
            root.showPage(key);
            root.raise();
            root.requestActivate();
        }
        function close(): void {
            root.close();
        }
        // Files' pick mode answers here
        function picked(json: string): void {
            root.receivePick(json);
        }
    }
    // "de_DE" as its speakers write it: "Deutsch (Deutschland)"; the code when Qt has no name
    function languageName(code) {
        const l = Qt.locale(code);
        if (l.name === "C" || !l.nativeLanguageName)
            return code;
        return l.nativeTerritoryName ? `${l.nativeLanguageName} (${l.nativeTerritoryName})` : l.nativeLanguageName;
    }
    function stepPage(by) {
        const shown = root.categories.map((c, i) => i).filter(i => root.matches(root.categories[i]));
        const at = shown.indexOf(root.current);
        const next = shown[Math.max(0, Math.min(shown.length - 1, at + by))];
        if (next !== undefined)
            root.current = next;
    }
    // Tab moves through the page's rows; the page scrolls to keep the focused one in view.
    onActiveFocusItemChanged: {
        const item = root.activeFocusItem;
        if (!item || !pageColumn || !root.isInside(item, pageColumn))
            return;
        const y = item.mapToItem(pageColumn, 0, 0).y + pageColumn.y;
        if (y < pageScroll.contentY + 20)
            pageScroll.contentY = Math.max(0, y - 40);
        else if (y + item.height > pageScroll.contentY + pageScroll.height - 20)
            pageScroll.contentY = Math.min(pageScroll.contentHeight - pageScroll.height, y + item.height - pageScroll.height + 40);
    }
    function isInside(item, ancestor) {
        for (let p = item; p; p = p.parent)
            if (p === ancestor)
                return true;
        return false;
    }
    // A page, or a place on it after a colon ("accounts:keys:openai"): the Accounts page scrolls to
    // that row, opens what it names and washes it once.
    property string pageAnchor: ""
    signal anchorAsked(string anchor)
    signal anchorArrived(string anchor)
    function showPage(key) {
        // a page's key, or the old panel's name for it, in any case ("Network" from a script written for the old panel)
        const parts = (key ?? "").split(":");
        const head = SettingsApp.keyFor(parts[0]);
        const i = root.categories.findIndex(c => c.key === head);
        if (i < 0)
            return;
        root.pageAnchor = parts.slice(1).join(":");
        root.current = i;
        if (root.pageAnchor.length > 0)
            root.anchorAsked(root.pageAnchor);
    }

    // What agent-host last wrote about the agents' accounts (accounts.json, which holds no secret):
    // the rail's line, and the Accounts page's rows while the host does not answer. A watched file,
    // so the rail runs no command to say it.
    property var accountsSaved: null
    FileView {
        id: accountsFile
        path: FileUtils.trimFileProtocol(`${Directories.config}/agent-host/accounts.json`)
        watchChanges: true
        printErrors: false
        onFileChanged: accountsFile.reload()
        onLoaded: {
            try {
                root.accountsSaved = JSON.parse(accountsFile.text());
            } catch (e) {
                root.accountsSaved = null;
            }
        }
        onLoadFailed: root.accountsSaved = null
    }
    readonly property var agentNames: ({ claude: "Claude Code", codex: "Codex", pi: "pi", opencode: "opencode" })
    // what an agent's default account needs before it can start a session, or ""
    function agentNeed(agent, step) {
        const name = root.agentNames[agent] ?? agent;
        switch (step) {
        case "notInstalled": return `${name} is not installed`;
        case "needsNode": return `${name} needs one more install first`;
        case "installing": return `Installing ${name}`;
        case "signedOut": return agent === "pi" || agent === "opencode" ? `${name} needs a provider` : `${name} needs a sign-in`;
        case "noProvider": return `${name} needs a provider connected here`;
        case "expired": return `${name} needs to sign in again`;
        case "noKey": return `${name} needs a key`;
        case "keyRefused": return `${name}'s key was refused`;
        case "signingIn": return `${name} is signing in`;
        }
        return "";
    }
    // "3 ready", or the first thing an agent needs
    readonly property string accountsLine: {
        const f = root.accountsSaved;
        if (!f || !Array.isArray(f.accounts))
            return "";
        let ready = 0;
        let need = "";
        for (const agent of ["claude", "codex", "pi", "opencode"]) {
            const own = f.accounts.filter(a => a.agent === agent);
            if (!own.length)
                continue;
            const id = f.default?.[agent] ?? (own.find(a => !(a.home ?? "").includes("/agent-host/accounts/")) ?? own[0]).id;
            const state = f.status?.[id]?.state ?? "";
            if (state === "ready")
                ready++;
            else if (!need)
                need = root.agentNeed(agent, state);
        }
        return need || (ready > 0 ? `${ready} ready` : "");
    }

    // ── Appearance ───────────────────────────────────────────────────────────
    // The approved mock (settings-mock-2026-10-06 round 4): this screen in miniature beside the
    // pictures to choose from, then colour and light as presets, the exact values under Advanced.
    Component {
        id: lookPage
        ColumnLayout {
            id: look
            spacing: 0

            readonly property string folder: Config.options.wallpaperSelector.userPath.length > 0
                ? Config.options.wallpaperSelector.userPath : `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers`
            readonly property string wallPath: Config.options.background.wallpaperPath
            // where a pick starts: the folder the last picture came from (Discord, Axy: it always went back to Pictures)
            readonly property string pickFrom: Config.options.wallpaperSelector.userPath.length > 0
                ? Config.options.wallpaperSelector.userPath : FileUtils.trimFileProtocol(Directories.pictures)
            // a video wallpaper is drawn from its still
            readonly property string stillPath: /\.(mp4|webm|mkv|mov|avi)$/i.test(look.wallPath)
                ? Config.options.background.thumbnailPath : look.wallPath
            property bool showAll: false
            // The accent eyedropper is hyprpicker, run by switchwall.sh. Without it Pick ended at once and said
            // nothing, so the button is shown only where it is installed (as the control panel's picker is), and a
            // second press waits for the first picker to end instead of stacking another.
            property bool pickerFound: false
            Process {
                running: true
                command: ["bash", "-c", "command -v hyprpicker"]
                onExited: code => look.pickerFound = code === 0
            }
            Process {
                id: accentPicker
                command: [Directories.wallpaperSwitchScriptPath, "--noswitch", "--color"]
            }
            FolderListModel {
                id: wallFiles
                // each part encoded: a # or % in the folder's name would cut or change the url
                folder: "file://" + look.folder.split("/").map(encodeURIComponent).join("/")
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif"]
                caseSensitive: false
                showDirs: false
                sortField: FolderListModel.Time
            }
            // the picture in use first, then the folder's; the last tile adds one from elsewhere.
            // Only files inside the folder: for a folder that does not exist FolderListModel lists
            // the working directory instead, which offered stray PNGs from ~ as wallpapers.
            readonly property var pictures: {
                const out = look.stillPath.length > 0 ? [look.stillPath] : [];
                for (let i = 0; i < wallFiles.count; i++) {
                    const f = wallFiles.get(i, "filePath");
                    if (f && f.startsWith(`${look.folder}/`) && f !== look.wallPath && f !== look.stillPath)
                        out.push(f);
                }
                return out;
            }
            // 14 pictures and the add tile make five full rows of three: the Horizons Tacit gives every account (14) show in
            // full, and only a bigger folder waits behind "All". With 5 it looked as if the others did not exist.
            readonly property int shownPictures: 14
            readonly property var tiles: [...(look.showAll ? look.pictures : look.pictures.slice(0, look.shownPictures)), ""]

            // see-through as three looks: Solid is off, Frosted decides itself per wallpaper,
            // Clear is a hand-set amount (raised to 40 % when it was lower, so it reads clearer than Frosted)
            readonly property string glass: !Config.options.appearance.transparency.enable ? "solid"
                : Config.options.appearance.transparency.automatic ? "frosted" : "clear"
            readonly property real clearAmount: look.glass === "clear" ? Config.options.appearance.transparency.backgroundTransparency : 0.4
            function setGlass(kind) {
                const t = Config.options.appearance.transparency;
                t.enable = kind !== "solid";
                if (kind === "frosted")
                    t.automatic = true;
                if (kind === "clear") {
                    t.automatic = false;
                    if (t.backgroundTransparency < 0.4)
                        t.backgroundTransparency = 0.4;
                }
            }

            Group {
                title: "Wallpaper"
                Item {
                    id: wallRow
                    Layout.fillWidth: true
                    readonly property bool wide: width >= 760
                    readonly property real screenW: wide ? Math.min(480, (width - 40) * 0.56) : width - 40
                    readonly property real choicesX: wide ? 20 + screenW + 28 : 20
                    readonly property real choicesW: wide ? width - choicesX - 20 : width - 40
                    readonly property real tileW: Math.min(150, (choicesW - 24) / 3)
                    implicitHeight: (wide ? Math.max(mini.height, choices.implicitHeight) : mini.height + 20 + choices.implicitHeight) + 16

                    Miniature {
                        id: mini
                        x: 20
                        y: 4
                        width: wallRow.screenW
                        height: width * 9 / 16
                        wallpaper: look.stillPath
                        ground: root.termBase
                        seeThrough: root.seeThroughSetting
                    }

                    Column {
                        id: choices
                        x: wallRow.choicesX
                        y: wallRow.wide ? 4 : mini.height + 24
                        width: wallRow.choicesW
                        spacing: 18

                        Grid {
                            columns: 3
                            spacing: 12
                            Repeater {
                                model: look.tiles
                                Rectangle {
                                    id: tile
                                    required property string modelData
                                    readonly property bool adds: modelData.length === 0
                                    readonly property bool inUse: modelData === look.stillPath
                                    readonly property bool keyboardFocus: tile.activeFocus
                                        && (tile.focusReason === Qt.TabFocusReason || tile.focusReason === Qt.BacktabFocusReason)
                                    width: wallRow.tileW
                                    height: width * 9 / 16
                                    radius: 9
                                    color: tile.adds ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, tileArea.containsMouse ? 0.92 : 0.96) : "transparent"
                                    border.width: tile.inUse || tile.keyboardFocus ? 2 : (tile.adds ? 1 : 0)
                                    border.color: tile.inUse ? Appearance.colors.colPrimary
                                        : tile.keyboardFocus ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.5)
                                        : ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93)
                                    activeFocusOnTab: true
                                    function choose() {
                                        if (tile.adds)
                                            root.pickFile("A picture for the desktop", look.pickFrom, path => {
                                                // its folder is the wallpaper folder from now on: the pictures here, the rotation
                                                Config.options.wallpaperSelector.userPath = path.replace(/\/[^/]*$/, "");
                                                root.applyWallpaper(path);
                                            });
                                        else if (!tile.inUse)
                                            root.applyWallpaper(tile.modelData);
                                    }
                                    Keys.onReturnPressed: tile.choose()
                                    Keys.onEnterPressed: tile.choose()
                                    Keys.onSpacePressed: tile.choose()

                                    ThumbnailImage {
                                        id: thumb
                                        visible: !tile.adds
                                        anchors.fill: parent
                                        anchors.margins: tile.inUse ? 4 : 0
                                        sourcePath: tile.modelData
                                        sourceSize.width: 256
                                        sourceSize.height: 256
                                        fillMode: Image.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: thumb.width
                                                height: thumb.height
                                                radius: tile.inUse ? 6 : 9
                                            }
                                        }
                                    }
                                    MaterialSymbol {
                                        visible: tile.adds
                                        anchors.centerIn: parent
                                        text: "add"
                                        iconSize: 20
                                        color: Tacit.inkSec
                                    }
                                    MouseArea {
                                        id: tileArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tile.choose()
                                    }
                                }
                            }
                        }
                        StyledText {
                            visible: look.pictures.length <= 1
                            width: parent.width
                            // the folder by its name, not its path
                            text: `Your ${look.folder.split("/").filter(x => x).pop() ?? "wallpaper"} folder has no pictures yet`
                            font.pixelSize: 13
                            color: Tacit.inkMeta
                            wrapMode: Text.Wrap
                        }
                        TextButton {
                            visible: look.pictures.length > look.shownPictures
                            x: -10
                            glyph: look.showAll ? "expand_less" : "expand_more"
                            label: look.showAll ? "Fewer" : `All ${look.pictures.length}`
                            onPressed: look.showAll = !look.showAll
                        }
                        // Wallpapers.qml's timer; the other intervals are under Advanced
                        Column {
                            spacing: 8
                            StyledText {
                                text: "New wallpaper"
                                font.pixelSize: 15
                                color: Tacit.inkSec
                            }
                            Words {
                                readonly property int now: Config.options.wallpaperSelector.changeInterval
                                options: {
                                    const base = [{ value: 0, label: "Never" }, { value: 3600000, label: "Every hour" }, { value: 86400000, label: "Every day" }];
                                    return base.some(o => o.value === now) ? base : [...base, { value: now, label: root.durationText(now / 1000) }];
                                }
                                current: now
                                onPicked: value => Config.options.wallpaperSelector.changeInterval = value
                            }
                        }
                        TextButton {
                            x: -10
                            glyph: "folder_open"
                            label: "Change the folder"
                            onPressed: root.pickFolder("Your wallpaper folder", look.pickFrom, path => Config.options.wallpaperSelector.userPath = path)
                        }
                    }
                }
            }

            Group {
                title: "Colour and light"
                SettingRow {
                    label: "Colours from the wallpaper"
                    clickable: false
                    control: Row {
                        spacing: 8
                        Repeater {
                            model: [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.m3colors.m3tertiary,
                                Appearance.m3colors.m3primaryContainer, Appearance.colors.colSecondaryContainer, Appearance.m3colors.m3surfaceContainerHighest]
                            Rectangle {
                                required property var modelData
                                width: 22
                                height: 22
                                radius: 11
                                color: modelData
                                border.width: 1
                                border.color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                            }
                        }
                    }
                }
                ChoiceRow {
                    label: "Colour style"
                    description: ({
                        "auto": "Picks a style that suits each wallpaper",
                        "scheme-fidelity": "Keeps the picture's own colours",
                        "scheme-content": "One quiet tone taken from the picture"
                    })[Config.options.appearance.palette.type] ?? ""
                    options: [
                        { value: "auto", label: "Automatic" },
                        { value: "scheme-fidelity", label: "True to the picture" },
                        { value: "scheme-content", label: "One tone" }
                    ]
                    current: Config.options.appearance.palette.type
                    onPicked: value => {
                        Config.options.appearance.palette.type = value;
                        // config.json is written late; the script would read the previous scheme
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--type", value]);
                    }
                }
                SettingRow {
                    label: "Accent"
                    description: accentPicker.running ? "Click any colour on the screen, or press Esc"
                        : (Config.options.appearance.palette.accentColor ?? "").length > 0 ? "Picked by you" : "Taken from the wallpaper"
                    clickable: false
                    control: Row {
                        spacing: 4
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 11
                            color: (Config.options.appearance.palette.accentColor ?? "").length > 0
                                ? Config.options.appearance.palette.accentColor : Appearance.colors.colPrimary
                            border.width: 1
                            border.color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                        }
                        Item { width: 4; height: 1 }
                        TextButton {
                            visible: look.pickerFound
                            enabled: !accentPicker.running
                            label: "Pick"
                            onPressed: accentPicker.running = true
                        }
                        TextButton {
                            visible: (Config.options.appearance.palette.accentColor ?? "").length > 0
                            label: "Use the wallpaper's"
                            onPressed: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", "clear"])
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 130
                    Column {
                        x: 20
                        y: 14
                        width: parent.width - glassRow.width - 60
                        spacing: 3
                        StyledText {
                            text: "See-through"
                            font.pixelSize: 15
                            color: Appearance.colors.colInkMain
                        }
                        StyledText {
                            width: parent.width
                            text: "How much of the wallpaper shows behind the notch and the panels"
                            font.pixelSize: 13
                            color: Tacit.inkMeta
                            wrapMode: Text.Wrap
                        }
                    }
                    Row {
                        id: glassRow
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        y: 10
                        spacing: 14
                        Repeater {
                            model: [
                                { kind: "clear", word: "Clear", see: look.clearAmount, blur: false },
                                { kind: "frosted", word: "Frosted", see: 0.15, blur: true },
                                { kind: "solid", word: "Solid", see: 0, blur: true }
                            ]
                            GlassChoice {
                                required property var modelData
                                word: modelData.word
                                wallpaper: look.stillPath
                                ground: root.termBase
                                seeThrough: modelData.see
                                blurred: modelData.blur
                                chosen: look.glass === modelData.kind
                                onPicked: look.setGlass(modelData.kind)
                            }
                        }
                    }
                }
            }

            Group {
                title: "Type"
                ChoiceRow {
                    label: "Interface"
                    options: root.fontOptions
                    current: Config.options.appearance.fonts.main
                    onPicked: value => Config.options.appearance.fonts.main = value
                }
                ChoiceRow {
                    label: "Monospace"
                    options: root.fontOptions
                    current: Config.options.appearance.fonts.monospace
                    onPicked: value => Config.options.appearance.fonts.monospace = value
                }
            }

            Advanced {
                ChoiceRow {
                    label: "Change the wallpaper"
                    description: "Each change recolours the whole desktop from the new picture"
                    options: [
                        { value: 0, label: "Never" }, { value: 900000, label: "Every 15 min" },
                        { value: 1800000, label: "Every 30 min" }, { value: 3600000, label: "Every hour" },
                        { value: 10800000, label: "Every 3 hours" }, { value: 86400000, label: "Every day" }
                    ]
                    current: Config.options.wallpaperSelector.changeInterval
                    onPicked: value => Config.options.wallpaperSelector.changeInterval = value
                }
                SwitchRow {
                    label: "Blur the wallpaper"
                    description: "A soft picture behind the desktop instead of a sharp one"
                    checked: Config.options.background.showBlur
                    onToggled: value => Config.options.background.showBlur = value
                }
                SettingRow {
                    label: "Lock screen picture"
                    description: Config.options.background.lockWall.length > 0
                        ? Config.options.background.lockWall.split("/").pop() : "The same picture as the desktop"
                    clickable: false
                    control: Row {
                        spacing: 2
                        TextButton {
                            visible: Config.options.background.lockWall.length > 0
                            label: "Use the desktop's"
                            onPressed: Config.options.background.lockWall = ""
                        }
                        TextButton {
                            label: "Choose"
                            onPressed: root.pickFile("A picture for the lock screen", look.pictures.length > 1 ? look.folder : FileUtils.trimFileProtocol(Directories.pictures),
                                path => Config.options.background.lockWall = path)
                        }
                    }
                }
                StepperRow {
                    visible: look.glass === "clear"
                    label: "How clear"
                    description: "The share of the wallpaper that shows through when see-through is Clear"
                    value: Math.round(Config.options.appearance.transparency.backgroundTransparency * 100)
                    from: 5
                    to: 60
                    stepSize: 5
                    suffix: "%"
                    onMoved: value => Config.options.appearance.transparency.backgroundTransparency = value / 100
                }
                // switchwall.sh reads these each time the wallpaper changes
                SwitchRow {
                    label: "Colours follow the wallpaper"
                    description: "The desktop and apps are recoloured each time the wallpaper changes"
                    checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    onToggled: value => Config.options.appearance.wallpaperTheming.enableAppsAndShell = value
                }
                SwitchRow {
                    visible: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    label: "Qt and KDE apps follow too"
                    checked: Config.options.appearance.wallpaperTheming.enableQtApps
                    onToggled: value => Config.options.appearance.wallpaperTheming.enableQtApps = value
                }
                SwitchRow {
                    visible: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    label: "The terminal follows too"
                    checked: Config.options.appearance.wallpaperTheming.enableTerminal
                    onToggled: value => Config.options.appearance.wallpaperTheming.enableTerminal = value
                }
            }
        }
    }

    // ── Bluetooth ────────────────────────────────────────────────────────────
    Component {
        id: bluetoothPage
        ColumnLayout {
            id: btPage
            spacing: 0

            // Looks for devices while this page is open, the way the control panel does while its
            // Bluetooth section is (BluetoothSection.qml): pairable goes on with discovery, because
            // the adapter comes up unpairable after boot and BlueZ then refuses to bond.
            readonly property var adapter: Bluetooth.defaultAdapter
            // one split for both groups: a device is in the paired list when it is paired, bonded or
            // connected, and Nearby holds the rest (a connected one would otherwise be in neither)
            readonly property var knownDevices: Bluetooth.devices.values.filter(d => d.paired || d.bonded || d.connected)
            readonly property var nearbyDevices: BluetoothStatus.unpairedDevices.filter(d => !d.bonded)
            function look() {
                if (!btPage.adapter || !btPage.adapter.enabled)
                    return;
                btPage.adapter.discovering = true;
                Qt.callLater(() => { if (btPage.adapter) btPage.adapter.pairable = true; });
                keepLooking.left = 8;
                keepLooking.restart();
            }
            Component.onCompleted: lookLater.restart()
            Component.onDestruction: {
                if (btPage.adapter) {
                    btPage.adapter.discovering = false;
                    btPage.adapter.pairable = false;
                }
            }
            onAdapterChanged: btPage.look()
            Connections {
                target: btPage.adapter
                function onEnabledChanged() { lookLater.restart(); }
            }
            Timer {
                id: lookLater
                interval: 500
                onTriggered: btPage.look()
            }
            Timer {
                id: keepLooking
                // a freshly powered adapter answers "Resource Not Ready" for a second or two
                property int left: 0
                interval: 900
                repeat: true
                onTriggered: {
                    if (!btPage.adapter || !btPage.adapter.enabled || btPage.adapter.discovering || keepLooking.left <= 0) {
                        keepLooking.stop();
                        return;
                    }
                    keepLooking.left -= 1;
                    btPage.adapter.discovering = true;
                }
            }

            Group {
                title: BluetoothStatus.available ? "" : "No adapter"
                note: BluetoothAgent.connected ? "" : "Devices that show a code to confirm cannot pair yet: the pairing helper is not running."
                SwitchRow {
                    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
                    label: "Bluetooth"
                    glyph: connected.length > 0 ? "bluetooth_connected" : (BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled")
                    // what is connected now, with its battery when it reports one
                    description: !BluetoothStatus.enabled ? "Off"
                        : connected.length === 0 ? "Nothing connected"
                        : `Connected to ${connected.map(d => BluetoothStatus.hasBattery(d) ? `${d.name} (${Math.round(d.battery * 100)}%)` : d.name).join(", ")}`
                    enabled: BluetoothStatus.available
                    checked: BluetoothStatus.enabled
                    onToggled: value => BluetoothStatus.togglePower()
                }
                SwitchRow {
                    label: "Visible to other devices"
                    description: "Only needed while another device is looking for this one"
                    glyph: "visibility"
                    enabled: BluetoothStatus.enabled
                    checked: Bluetooth.defaultAdapter?.discoverable ?? false
                    onToggled: value => { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discoverable = value }
                }
            }

            Group {
                title: "Devices you have paired"
                visible: btPage.knownDevices.length > 0
                Repeater {
                    model: ScriptModel { values: btPage.knownDevices }
                    SettingRow {
                        id: dev
                        required property var modelData
                        // The control panel's rule (BluetoothSection.qml DeviceRow): connect() and disconnect() return
                        // nothing and no signal reports a failure, so what was asked is remembered from the press, the
                        // row reads it at once, and a device that has not answered after a while says so.
                        property string asked: ""
                        property string failed: ""
                        function ask(what) {
                            dev.failed = "";
                            dev.asked = what;
                            waitTimer.restart();
                        }
                        label: dev.modelData?.name || "Unknown device"
                        description: dev.modelData.state === BluetoothDeviceState.Connecting || dev.asked === "connect" ? "Connecting…"
                            : dev.modelData.state === BluetoothDeviceState.Disconnecting || dev.asked === "disconnect" ? "Disconnecting…"
                            : dev.modelData.connected
                            ? (BluetoothStatus.hasBattery(dev.modelData) ? `Connected · ${Math.round(dev.modelData.battery * 100)}%` : "Connected")
                            : dev.failed.length > 0 ? dev.failed
                            : "Paired"
                        glyph: Icons.getBluetoothDeviceMaterialSymbol(dev.modelData?.icon || "")
                        Timer {
                            id: waitTimer
                            interval: 12000
                            onTriggered: {
                                const d = dev.modelData;
                                if (!d || dev.asked === "")
                                    return;
                                if (dev.asked === "connect" && !d.connected)
                                    dev.failed = "Did not connect. Turn it on and try again";
                                else if (dev.asked === "disconnect" && d.connected)
                                    dev.failed = "Did not disconnect";
                                dev.asked = "";
                            }
                        }
                        // An adapter that has just powered on rejects Connect for a second or two: ask again a few times
                        Timer {
                            id: keepTrying
                            property int left: 0
                            interval: 900
                            repeat: true
                            onTriggered: {
                                const d = dev.modelData;
                                if (!d || dev.asked !== "connect" || d.connected || d.state === BluetoothDeviceState.Connecting || keepTrying.left <= 0) {
                                    keepTrying.stop();
                                    return;
                                }
                                keepTrying.left -= 1;
                                d.connect();
                            }
                        }
                        Connections {
                            target: dev.modelData
                            function onConnectedChanged() {
                                if (dev.modelData.connected || dev.asked === "disconnect") {
                                    dev.asked = "";
                                    dev.failed = "";
                                    waitTimer.stop();
                                    keepTrying.stop();
                                }
                            }
                        }
                        control: RowLayout {
                            spacing: 4
                            TextButton {
                                label: dev.modelData.connected ? "Disconnect" : "Connect"
                                enabled: dev.asked === "" && dev.modelData.state !== BluetoothDeviceState.Connecting && dev.modelData.state !== BluetoothDeviceState.Disconnecting
                                onPressed: {
                                    const d = dev.modelData;
                                    if (d.connected) {
                                        dev.ask("disconnect");
                                        d.disconnect();
                                        return;
                                    }
                                    // BlueZ refuses a connect with the radio off and the refusal arrives nowhere
                                    if (!BluetoothStatus.enabled) {
                                        dev.failed = "Bluetooth is off";
                                        return;
                                    }
                                    // trusted first, so it may come back on its own after a drop
                                    if (!d.trusted)
                                        d.trusted = true;
                                    dev.ask("connect");
                                    d.connect();
                                    keepTrying.left = 3;
                                    keepTrying.restart();
                                }
                            }
                            RowMenu {
                                items: [{ label: "Forget this device", run: () => dev.modelData.forget() }]
                            }
                        }
                    }
                }
            }

            Group {
                title: "Nearby"
                visible: BluetoothStatus.enabled
                note: btPage.nearbyDevices.length > 0
                    ? (BluetoothStatus.hiddenUnnamedCount > 0 ? `${BluetoothStatus.hiddenUnnamedCount} more without a name are hidden.` : "")
                    : "Looking for devices. Put yours in pairing mode to see it here."
                Repeater {
                    // kept row by row while discovery updates the list (a plain array rebuilt every row)
                    model: ScriptModel { values: btPage.nearbyDevices }
                    PairRow {}
                }
            }
            Advanced {
                SwitchRow {
                    label: "Hide devices with only a random address"
                    description: "Phones and watches nearby rotate an address every few minutes and carry no name"
                    checked: Config.options.bluetooth.hideUnnamedDevices
                    onToggled: value => Config.options.bluetooth.hideUnnamedDevices = value
                }
            }
        }
    }

    // ── Notch ─────────────────────────────────────────────────────────────────
    Component {
        id: notchPage
        ColumnLayout {
            id: nt
            spacing: 0
            // the notch's own few settings stay on the page; the longer sections open as pages
            property string viewing: ""
            onViewingChanged: root.revealPage()
            // notch:<section>; the link is spent once the page has taken it, so choosing the page again opens its list
            function takeAnchor(anchor) {
                if (["tells", "reminders", "music"].includes(anchor)) nt.viewing = anchor;
                root.pageAnchor = "";
            }
            Component.onCompleted: nt.takeAnchor(root.pageAnchor)
            Connections {
                target: root
                function onAnchorAsked(anchor) { nt.takeAnchor(anchor); }
            }
            readonly property var tellKeys: ["notification", "power", "network", "workspace", "focus", "download", "activity"]
            readonly property int tellsOn: nt.tellKeys.filter(k => Config.options.island.states[k]).length

            Group {
                visible: nt.viewing === ""
                title: "The notch"
                // No "Show the notch" switch: the notch is always on in Tacit (the shell holds
                // island.enable true, panelFamilies/IllogicalImpulseFamily.qml).
                ChoiceRow {
                    label: "Opens"
                    enabled: Config.options.island.enable
                    options: [{ value: true, label: "When you point at it" }, { value: false, label: "When you click it" }]
                    current: Config.options.island.hoverExpand
                    onPicked: value => Config.options.island.hoverExpand = value
                }
                SwitchRow {
                    label: "Scroll over it to change the volume"
                    enabled: Config.options.island.enable
                    checked: Config.options.island.scrollVolume
                    onToggled: value => Config.options.island.scrollVolume = value
                }
                SwitchRow {
                    label: "Stay over full-screen windows while music plays"
                    enabled: Config.options.island.enable
                    checked: Config.options.island.showInFullscreenWhilePlaying
                    onToggled: value => Config.options.island.showInFullscreenWhilePlaying = value
                }
                SwitchRow {
                    label: "Say hello when you log in"
                    enabled: Config.options.island.enable
                    checked: Config.options.island.greeting.enable
                    onToggled: value => Config.options.island.greeting.enable = value
                }
            }

            Group {
                visible: nt.viewing === ""
                OpenRow {
                    label: "What it tells you about"
                    value: `${nt.tellsOn} of ${nt.tellKeys.length} on`
                    description: "Notifications, battery, network and more, shown briefly as they happen"
                    onActivated: nt.viewing = "tells"
                }
                OpenRow {
                    label: "Reminders"
                    readonly property int watched: Config.options.island.unsavedRepos.length + Config.options.island.prRepos.length
                    value: watched > 0 ? `${watched} watched` : ""
                    description: "Unsaved work in your folders, and pull requests"
                    onActivated: nt.viewing = "reminders"
                }
                OpenRow {
                    label: "Music"
                    value: Config.options.island.media.enable ? "On" : "Off"
                    description: "What is playing, and how long a paused song stays"
                    onActivated: nt.viewing = "music"
                }
            }
            BackLine {
                visible: nt.viewing !== ""
                text: "Notch"
                onClicked: nt.viewing = ""
            }
            Group {
                visible: nt.viewing === "tells"
                title: "What it tells you about"
                note: "Each of these shows briefly in the notch when it happens, then gets out of the way."
                EyeRow {
                    glyph: "notifications"
                    label: "Notifications"
                    checked: Config.options.island.states.notification
                    onToggled: value => Config.options.island.states.notification = value
                }
                // No Volume or Brightness switch: the notch always shows both (held true,
                // panelFamilies/IllogicalImpulseFamily.qml); off, end-4's on-screen meter loaded.
                EyeRow {
                    visible: false
                    glyph: "volume_up"
                    label: "Volume"
                    checked: Config.options.island.states.volume
                    onToggled: value => Config.options.island.states.volume = value
                }
                EyeRow {
                    visible: false
                    glyph: "light_mode"
                    label: "Brightness"
                    checked: Config.options.island.states.brightness
                    onToggled: value => Config.options.island.states.brightness = value
                }
                EyeRow {
                    glyph: "battery_charging_full"
                    label: "Battery and charging"
                    checked: Config.options.island.states.power
                    onToggled: value => Config.options.island.states.power = value
                }
                EyeRow {
                    glyph: "wifi"
                    label: "Network changes"
                    checked: Config.options.island.states.network
                    onToggled: value => Config.options.island.states.network = value
                }
                EyeRow {
                    glyph: "space_dashboard"
                    label: "Workspace switches"
                    checked: Config.options.island.states.workspace
                    onToggled: value => Config.options.island.states.workspace = value
                }
                EyeRow {
                    glyph: "timer"
                    label: "Timers"
                    checked: Config.options.island.states.focus
                    onToggled: value => Config.options.island.states.focus = value
                }
                EyeRow {
                    glyph: "download"
                    label: "New downloads and screenshots"
                    checked: Config.options.island.states.download
                    onToggled: value => Config.options.island.states.download = value
                }
                EyeRow {
                    glyph: "smart_toy"
                    label: "Agents and long jobs"
                    description: "An agent session or a build at work, waiting for you, or done"
                    checked: Config.options.island.states.activity
                    onToggled: value => Config.options.island.states.activity = value
                }
            }

            // Watched folders and pull requests (IslandController): a quiet glyph for work left
            // uncommitted, a peek when a pull request is merged, fails or wants a review.
            Group {
                visible: nt.viewing === "reminders"
                title: "Reminders"
                note: "The folders your agent works in are always watched. Pull request reminders only work when GitHub is signed in on this computer."
                Repeater {
                    model: Config.options.island.unsavedRepos
                    SettingRow {
                        required property var modelData
                        required property int index
                        clickable: false
                        glyph: "folder_managed"
                        label: modelData.split("/").pop()
                        description: `Unsaved work in ${modelData.replace(Quickshell.env("HOME"), "~")}`
                        control: RowMenu {
                            items: [{ label: "Stop watching", run: () => Config.options.island.unsavedRepos = Config.options.island.unsavedRepos.filter((r, i) => i !== index) }]
                        }
                    }
                }
                SettingRow {
                    glyph: "create_new_folder"
                    label: "Watch a folder for unsaved work"
                    onActivated: root.pickFolder("A folder to watch for unsaved work", Quickshell.env("HOME"), path => {
                        if (!Config.options.island.unsavedRepos.includes(path))
                            Config.options.island.unsavedRepos = [...Config.options.island.unsavedRepos, path];
                    })
                }
                ChoiceRow {
                    glyph: "hourglass_bottom"
                    label: "Remind after"
                    options: root.minuteOptions([30, 60, 120, 240], Config.options.island.unsavedAfterMinutes)
                    current: Config.options.island.unsavedAfterMinutes
                    onPicked: value => Config.options.island.unsavedAfterMinutes = value
                }
                Repeater {
                    model: Config.options.island.prRepos
                    SettingRow {
                        required property var modelData
                        required property int index
                        clickable: false
                        glyph: "merge"
                        label: modelData
                        description: "Pull requests"
                        control: RowMenu {
                            items: [{ label: "Stop watching", run: () => Config.options.island.prRepos = Config.options.island.prRepos.filter((r, i) => i !== index) }]
                        }
                    }
                }
                SettingRow {
                    id: repoRow
                    property string said: ""
                    clickable: false
                    glyph: "add"
                    label: "Watch pull requests"
                    description: repoRow.said
                    control: RowLayout {
                        spacing: 6
                        LineField {
                            id: newRepo
                            placeholder: "owner/name"
                            onAccepted: addRepo.pressed()
                            onTextChanged: repoRow.said = ""
                        }
                        TextButton {
                            id: addRepo
                            label: "Add"
                            // a refused entry stays in the box, with the reason under the label
                            onPressed: {
                                const r = newRepo.text.trim();
                                if (!/^[\w.-]+\/[\w.-]+$/.test(r)) {
                                    repoRow.said = "Use owner/name, like acme/app";
                                    return;
                                }
                                if (Config.options.island.prRepos.includes(r)) {
                                    repoRow.said = "Already watched";
                                    return;
                                }
                                Config.options.island.prRepos = [...Config.options.island.prRepos, r];
                                newRepo.text = "";
                            }
                        }
                    }
                }
            }

            Group {
                visible: nt.viewing === "music"
                title: "Music"
                SwitchRow {
                    label: "Show what is playing"
                    checked: Config.options.island.media.enable
                    onToggled: value => Config.options.island.media.enable = value
                }
                SwitchRow {
                    label: "Moving waveform while it plays"
                    enabled: Config.options.island.media.enable
                    checked: Config.options.island.media.waveform
                    onToggled: value => Config.options.island.media.waveform = value
                }
                SwitchRow {
                    label: "Keep a paused song in the notch"
                    enabled: Config.options.island.media.enable
                    checked: Config.options.island.media.keepWhenPaused
                    onToggled: value => Config.options.island.media.keepWhenPaused = value
                }
                ChoiceRow {
                    label: "For how long"
                    visible: Config.options.island.media.keepWhenPaused
                    options: root.minuteOptions([5, 15, 30, 60], Config.options.island.media.keepPausedMinutes)
                    current: Config.options.island.media.keepPausedMinutes
                    onPicked: value => Config.options.island.media.keepPausedMinutes = value
                }
            }

            // how long the notch shows things, and where it sits
            Advanced {
                visible: nt.viewing === ""
                StepperRow {
                    label: "A notification"
                    value: Config.options.island.hold.notification
                    from: 1000
                    to: 15000
                    stepSize: 500
                    format: v => `${v / 1000} s`
                    onMoved: value => Config.options.island.hold.notification = value
                }
                StepperRow {
                    label: "Volume and brightness"
                    value: Config.options.island.hold.meter
                    from: 500
                    to: 5000
                    stepSize: 250
                    format: v => `${v / 1000} s`
                    onMoved: value => Config.options.island.hold.meter = value
                }
                StepperRow {
                    label: "A job that finished"
                    value: Config.options.island.hold.activityDone
                    from: 1000
                    to: 15000
                    stepSize: 500
                    format: v => `${v / 1000} s`
                    onMoved: value => Config.options.island.hold.activityDone = value
                }
                StepperRow {
                    label: "A new download"
                    value: Config.options.island.hold.download
                    from: 1000
                    to: 15000
                    stepSize: 500
                    format: v => `${v / 1000} s`
                    onMoved: value => Config.options.island.hold.download = value
                }
                StepperRow {
                    label: "Notch distance from the top edge"
                    description: "Raise it to sit below a camera cut into the screen"
                    value: Config.options.island.topMargin
                    from: 0
                    to: 80
                    stepSize: 2
                    suffix: " px"
                    onMoved: value => Config.options.island.topMargin = value
                }
                StepperRow {
                    label: "Notifications waiting behind the one on show"
                    value: Config.options.island.notificationQueueDepth
                    from: 0
                    to: 10
                    onMoved: value => Config.options.island.notificationQueueDepth = value
                }
            }
        }
    }

    Component {
        id: desktopPage
        ColumnLayout {
            id: dk
            spacing: 0
            // the page shows its sections as rows; one opened shows only that section
            property string viewing: ""
            onViewingChanged: root.revealPage()
            // desktop:<section>; spent once the page has taken it, as the Notch page does
            function takeAnchor(anchor) {
                if (["corners", "overview", "widgets"].includes(anchor)) dk.viewing = anchor;
                root.pageAnchor = "";
            }
            Component.onCompleted: dk.takeAnchor(root.pageAnchor)
            Connections {
                target: root
                function onAnchorAsked(anchor) { dk.takeAnchor(anchor); }
            }
            readonly property var widgetList: [
                { key: "clock", label: "Clock", glyph: "schedule" },
                { key: "weather", label: "Weather", glyph: "partly_cloudy_day" },
                { key: "worldClock", label: "World clock", glyph: "public" },
                { key: "resources", label: "System resources", glyph: "monitor_heart" },
                { key: "timers", label: "Timers", glyph: "timer" },
                { key: "images", label: "Image converter", glyph: "photo_library" },
                { key: "customImage", label: "Custom image", glyph: "image" },
                { key: "userCard", label: "Your name and picture", glyph: "person" }
            ]
            readonly property var widgetKeys: dk.widgetList.map(w => w.key)
            readonly property int widgetsShown: dk.widgetKeys.filter(k => Config.options.background.widgets[k]?.enable).length
            function cornerName(v) { return CornerActions.list.find(o => o.value === v)?.displayName ?? ""; }
            Group {
                visible: dk.viewing === ""
                OpenRow {
                    label: "Corners of the screen"
                    value: Config.options.sidebar.cornerOpen.enable ? "On" : "Off"
                    description: Config.options.sidebar.cornerOpen.enable
                        ? `Bottom left ${dk.cornerName(Config.options.sidebar.cornerOpen.bottomLeftAction)} · bottom right ${dk.cornerName(Config.options.sidebar.cornerOpen.bottomRightAction)}`
                        : "Push the pointer into a corner to open something"
                    onActivated: dk.viewing = "corners"
                }
                OpenRow {
                    label: "Workspace overview"
                    value: Config.options.overview.enable ? "On" : "Off"
                    description: "Super + Tab shows every workspace"
                    onActivated: dk.viewing = "overview"
                }
                OpenRow {
                    label: "Widgets"
                    value: dk.widgetsShown > 0 ? `${dk.widgetsShown} shown` : "None shown"
                    description: "On the desktop, and the weather they show"
                    onActivated: dk.viewing = "widgets"
                }
            }
            BackLine {
                visible: dk.viewing !== ""
                text: "Desktop"
                onClicked: dk.viewing = ""
            }
            // Hidden: end-4's dock options. That dock is gone; Tacit's dock is the palette's (PaletteDock.qml).
            Group {
                visible: false
                title: "The dock"
                SwitchRow {
                    label: "Show the dock"
                    checked: Config.options.dock.enable
                    onToggled: value => Config.options.dock.enable = value
                }
                SwitchRow {
                    label: "Hide until the pointer reaches the edge"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.hoverToReveal
                    onToggled: value => Config.options.dock.hoverToReveal = value
                }
                SwitchRow {
                    label: "Background behind the icons"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.showBackground
                    onToggled: value => Config.options.dock.showBackground = value
                }
                SwitchRow {
                    label: "Icons in one colour"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.monochromeIcons
                    onToggled: value => Config.options.dock.monochromeIcons = value
                }
                SwitchRow {
                    label: "Stay shown after login"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.pinnedOnStartup
                    onToggled: value => Config.options.dock.pinnedOnStartup = value
                }
                SwitchRow {
                    label: "Pin button"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.showPinButton
                    onToggled: value => Config.options.dock.showPinButton = value
                }
                SwitchRow {
                    label: "All-apps button"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.showAppsButton
                    onToggled: value => Config.options.dock.showAppsButton = value
                }
                SwitchRow {
                    label: "What is playing"
                    enabled: Config.options.dock.enable
                    checked: Config.options.dock.showMedia
                    onToggled: value => Config.options.dock.showMedia = value
                }
                // pinnedApps holds desktop entry ids, the dock's own pins
                Repeater {
                    model: Config.options.dock.enable ? Config.options.dock.pinnedApps : []
                    SettingRow {
                        required property var modelData
                        required property int index
                        clickable: false
                        glyph: "keep"
                        label: root.appEntries.find(e => e.id === modelData)?.name ?? modelData
                        control: RowMenu {
                            items: [{ label: "Unpin", run: () => Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter((a, i) => i !== index) }]
                        }
                    }
                }
                ChoiceRow {
                    visible: Config.options.dock.enable
                    glyph: "add"
                    label: "Pin an app"
                    options: root.appOptions.filter(o => !Config.options.dock.pinnedApps.includes(o.value))
                    current: ""
                    onPicked: value => Config.options.dock.pinnedApps = [...Config.options.dock.pinnedApps, value]
                }
            }

            Group {
                visible: dk.viewing === "corners"
                title: "Corners of the screen"
                // each corner its own row, saying what it opens: before, a note had to explain which
                SwitchRow {
                    label: "Use the corners"
                    description: "Push the pointer into a corner of the screen to open something"
                    checked: Config.options.sidebar.cornerOpen.enable
                    onToggled: value => Config.options.sidebar.cornerOpen.enable = value
                }
                SettingRow {
                    label: "Top left"
                    clickable: false
                    enabled: Config.options.sidebar.cornerOpen.enable
                    control: StyledText { text: "Palette"; font.pixelSize: 15; color: Tacit.inkSec }
                }
                SettingRow {
                    label: "Top right"
                    clickable: false
                    enabled: Config.options.sidebar.cornerOpen.enable
                    control: StyledText { text: "Notifications"; font.pixelSize: 15; color: Tacit.inkSec }
                }
                SwitchRow {
                    label: "Top corners open on touch"
                    description: "Off: push into them, as the bottom corners always need"
                    enabled: Config.options.sidebar.cornerOpen.enable
                    checked: Config.options.sidebar.cornerOpen.clickless
                    onToggled: value => Config.options.sidebar.cornerOpen.clickless = value
                }
                ChoiceRow {
                    label: "Bottom left"
                    enabled: Config.options.sidebar.cornerOpen.enable
                    options: CornerActions.list.map(o => ({ value: o.value, label: o.displayName }))
                    current: Config.options.sidebar.cornerOpen.bottomLeftAction
                    onPicked: value => Config.options.sidebar.cornerOpen.bottomLeftAction = value
                }
                ChoiceRow {
                    label: "Bottom right"
                    enabled: Config.options.sidebar.cornerOpen.enable
                    options: CornerActions.list.map(o => ({ value: o.value, label: o.displayName }))
                    current: Config.options.sidebar.cornerOpen.bottomRightAction
                    onPicked: value => Config.options.sidebar.cornerOpen.bottomRightAction = value
                }
            }


            // Super+Tab (modules/ii/overview/Overview.qml)
            Group {
                visible: dk.viewing === "overview"
                title: "Workspace overview"
                SwitchRow {
                    glyph: "grid_view"
                    label: "Overview on Super + Tab"
                    checked: Config.options.overview.enable
                    onToggled: value => Config.options.overview.enable = value
                }
                // Hidden: SUPER+Tab is always the grid; "Stacked" was end-4's niri layout (held,
                // panelFamilies/IllogicalImpulseFamily.qml).
                ChoiceRow {
                    visible: false
                    glyph: "view_quilt"
                    label: "Layout"
                    options: [{ value: "default", label: "Grid" }, { value: "niri", label: "Stacked" }]
                    current: Config.options.overview.style
                    onPicked: value => Config.options.overview.style = value
                }
            }
            Group {
                visible: dk.viewing === "widgets"
                title: "Desktop widgets"
                note: "Drag a widget to move it, or let it find a calm or busy spot on the wallpaper from ⋯, unless they are kept in place."
                Repeater {
                    model: dk.widgetList
                    SettingRow {
                        id: wRow
                        required property var modelData
                        readonly property var cfg: Config.options.background.widgets[modelData.key]
                        readonly property bool isShown: cfg?.enable ?? false
                        readonly property string strategy: cfg?.placementStrategy ?? "free"
                        glyph: modelData.glyph
                        label: modelData.label
                        description: strategy === "leastBusy" ? "Calm spot"
                            : strategy === "mostBusy" ? "Busy spot" : "Free to drag"
                        muted: !isShown
                        onActivated: if (cfg) cfg.enable = !isShown
                        control: Row {
                            spacing: 4
                            RowMenu {
                                items: [
                                    { label: "Free to drag", checked: wRow.strategy === "free", run: () => { if (wRow.cfg) wRow.cfg.placementStrategy = "free"; } },
                                    { label: "Calm spot", checked: wRow.strategy === "leastBusy", run: () => { if (wRow.cfg) wRow.cfg.placementStrategy = "leastBusy"; } },
                                    { label: "Busy spot", checked: wRow.strategy === "mostBusy", run: () => { if (wRow.cfg) wRow.cfg.placementStrategy = "mostBusy"; } }
                                ]
                            }
                            Item {
                                width: 32
                                height: 32
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: wRow.isShown ? "visibility" : "visibility_off"
                                    iconSize: 18
                                    color: wRow.isShown ? Appearance.colors.colInkMain : Appearance.colors.colInkFaint
                                }
                            }
                        }
                    }
                }
                SwitchRow {
                    label: "Keep them in place"
                    checked: Config.options.background.widgetsLocked
                    onToggled: value => Config.options.background.widgetsLocked = value
                }
                SwitchRow {
                    label: "Hide them behind full-screen windows"
                    checked: Config.options.background.hideWhenFullscreen
                    onToggled: value => Config.options.background.hideWhenFullscreen = value
                }
            }
            Group {
                visible: dk.viewing === "widgets"
                title: "Weather"
                note: "Weather needs your own free OpenWeather key. Nothing is shown without one."
                FieldRow {
                    label: "OpenWeather key"
                    placeholder: "Paste your key"
                    secret: true
                    text: Config.options.bar.weather.apiKey
                    onCommitted: value => Config.options.bar.weather.apiKey = value
                }
                SwitchRow {
                    label: "Use my location"
                    checked: Config.options.bar.weather.enableGPS
                    onToggled: value => Config.options.bar.weather.enableGPS = value
                }
                FieldRow {
                    label: "City"
                    visible: !Config.options.bar.weather.enableGPS
                    placeholder: "Stockholm"
                    text: Config.options.bar.weather.city
                    onCommitted: value => Config.options.bar.weather.city = value
                }
                SwitchRow {
                    label: "US units"
                    description: "°F, mph, miles, inches"
                    checked: Config.options.bar.weather.useUSCS
                    onToggled: value => Config.options.bar.weather.useUSCS = value
                }
                ChoiceRow {
                    label: "Check every"
                    options: root.minuteOptions([10, 15, 30, 60], Config.options.bar.weather.fetchInterval)
                    current: Config.options.bar.weather.fetchInterval
                    onPicked: value => Config.options.bar.weather.fetchInterval = value
                }
            }

            Advanced {
                visible: dk.viewing === ""
                // the on-screen meters run whenever the notch does not show both volume and brightness
                // (panelFamilies/IllogicalImpulseFamily.qml, the OnScreenDisplay loader)
                StepperRow {
                    visible: !(Config.options.island.enable && Config.options.island.states.volume && Config.options.island.states.brightness)
                    label: "On-screen volume and brightness stay for"
                    value: Config.options.osd.timeout
                    from: 500
                    to: 5000
                    stepSize: 250
                    format: v => `${v / 1000} s`
                    onMoved: value => Config.options.osd.timeout = value
                }
            }
        }
    }

    // ── Sound ────────────────────────────────────────────────────────────────
    // Where sound goes and where it comes from, as lists to pick from; the volume as the ruler
    // under them. The ear protection's numbers are under Advanced.
    Component {
        id: soundPage
        ColumnLayout {
            spacing: 0

            // where sound plays now and how loud, before the lists: the page's main thing
            Summary {
                readonly property var now: Audio.sink ? root.soundName(Audio.sink) : ({ label: "Nothing to play through", line: "" })
                glyph: (Audio.sink?.audio.muted ?? false) ? "volume_off" : "volume_up"
                eyebrow: "Playing through"
                title: now.label
                subtitle: now.line
                live: !!Audio.sink && !(Audio.sink?.audio.muted ?? false)
                // Written through the sink like the volume keys, so the ear protection that watches
                // the sink catches a jump from here the same way. It takes back any rise over "Largest
                // jump allowed at once", here and in the shell, so a click far up the bar or an arrow
                // key's tenth is climbed to in steps under that instead, as a drag would.
                Ruler {
                    id: volumeSlider
                    property real target: 0
                    property real wrote: 0
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    label: (Audio.sink?.audio.muted ?? false) ? "Muted" : `${Math.round(volumeSlider.value * 100)}%`
                    from: 0
                    to: 1
                    enabled: !!Audio.sink
                    onMoved: {
                        volumeSlider.target = volumeSlider.value;
                        volumeSlider.wrote = Audio.sink?.audio.volume ?? 0;
                        volumeSlider.climb();
                    }
                    function climb() {
                        const audio = Audio.sink?.audio;
                        // gone, or the last step was taken back since (by the shell): stop where it is
                        if (!audio || audio.volume < volumeSlider.wrote - 0.005) {
                            climbTimer.stop();
                            return;
                        }
                        const p = Config.options.audio.protection;
                        // a little under the limit: the level is kept as a float, a hair off what was written
                        const step = p.enable ? p.maxAllowedIncrease / 100 * 0.9 : Infinity;
                        const was = audio.volume;
                        audio.volume = Math.min(volumeSlider.target, was + step);
                        volumeSlider.wrote = audio.volume;
                        // there, or taken back at once (over "Loudest allowed")
                        if (Math.abs(audio.volume - volumeSlider.target) < 0.005 || audio.volume <= was) climbTimer.stop();
                        else climbTimer.start();
                    }
                    Timer {
                        id: climbTimer
                        interval: 50
                        repeat: true
                        onTriggered: volumeSlider.climb()
                    }
                    Binding on value {
                        value: Audio.sink?.audio.volume ?? 0
                        when: !volumeSlider.pressed
                    }
                }
            }

            Group {
                title: "Sound comes out of"
                note: Audio.outputDevices.length > 0 ? "" : "No speakers or headphones were found. Plug some in, or connect them on the Bluetooth page."
                Repeater {
                    model: Audio.outputDevices
                    SettingRow {
                        id: outRow
                        required property var modelData
                        readonly property bool inUse: modelData.name === (Audio.sink?.name ?? "")
                        glyph: /head|ear|bluez/i.test(`${modelData.name} ${modelData.description}`) ? "headphones"
                            : /hdmi|displayport|usb/i.test(`${modelData.name} ${modelData.description}`) ? "tv" : "laptop"
                        label: root.soundName(modelData).label
                        description: root.soundName(modelData).line
                        selected: inUse
                        onActivated: if (!inUse) Audio.setDefaultSink(modelData)
                        control: MaterialSymbol {
                            visible: outRow.inUse
                            text: "check"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
            // the microphone's level and mute, as the speakers' are above: a recording that comes out too loud is
            // turned down here, through the source like the mic key (Audio.toggleMicMute)
            Summary {
                visible: !!Audio.source
                readonly property var now: Audio.source ? root.soundName(Audio.source) : ({ label: "", line: "" })
                glyph: (Audio.source?.audio.muted ?? false) ? "mic_off" : "mic"
                eyebrow: "Listening through"
                title: now.label
                subtitle: now.line
                live: !(Audio.source?.audio.muted ?? false)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Ruler {
                        id: micSlider
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        label: (Audio.source?.audio.muted ?? false) ? "Muted" : `${Math.round(micSlider.value * 100)}%`
                        from: 0
                        to: 1
                        enabled: !!Audio.source
                        onMoved: if (Audio.source) Audio.source.audio.volume = micSlider.value
                        Binding on value {
                            value: Audio.source?.audio.volume ?? 0
                            when: !micSlider.pressed
                        }
                    }
                    TextButton {
                        label: (Audio.source?.audio.muted ?? false) ? "Unmute" : "Mute"
                        onPressed: Audio.toggleMicMute()
                    }
                }
            }
            Group {
                title: "Sound goes in through"
                note: Audio.inputDevices.length > 0 ? "" : "No microphone was found. Plug one in, or connect one on the Bluetooth page."
                Repeater {
                    model: Audio.inputDevices
                    SettingRow {
                        id: inRow
                        required property var modelData
                        readonly property bool inUse: modelData.name === (Audio.source?.name ?? "")
                        glyph: /head|bluez/i.test(`${modelData.name} ${modelData.description}`) ? "headset_mic" : "mic"
                        label: root.soundName(modelData).label
                        description: root.soundName(modelData).line
                        selected: inUse
                        onActivated: if (!inUse) Audio.setDefaultSource(modelData)
                        control: MaterialSymbol {
                            visible: inRow.inUse
                            text: "check"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
            Group {
                title: "Protecting your ears"
                SwitchRow {
                    label: "Stop sudden jumps in volume"
                    description: "When a device changes or an app misbehaves"
                    checked: Config.options.audio.protection.enable
                    onToggled: value => Config.options.audio.protection.enable = value
                }
            }
            Group {
                title: "Sounds the desktop makes"
                SwitchRow {
                    label: "Battery and charger sounds"
                    checked: Config.options.sounds.battery
                    onToggled: value => Config.options.sounds.battery = value
                }
                SwitchRow {
                    label: "A timer finishing"
                    checked: Config.options.sounds.pomodoro
                    onToggled: value => Config.options.sounds.pomodoro = value
                }
            }
            Advanced {
                StepperRow {
                    label: "Largest jump allowed at once"
                    enabled: Config.options.audio.protection.enable
                    value: Config.options.audio.protection.maxAllowedIncrease
                    from: 1
                    to: 50
                    suffix: "%"
                    onMoved: value => Config.options.audio.protection.maxAllowedIncrease = value
                }
                StepperRow {
                    label: "Loudest allowed"
                    enabled: Config.options.audio.protection.enable
                    value: Config.options.audio.protection.maxAllowed
                    from: 10
                    to: 150
                    stepSize: 5
                    suffix: "%"
                    onMoved: value => Config.options.audio.protection.maxAllowed = value
                }
            }
        }
    }

    // ── Network ──────────────────────────────────────────────────────────────
    Component {
        id: networkPage
        ColumnLayout {
            id: netPage
            spacing: 0
            // the Wi-Fi network you are on: with a cable up networkName may be the cable's profile, so
            // the scan's active access point names it then
            readonly property string wifiName: Network.ethernet ? (Network.active?.ssid ?? "") : Network.networkName
            // what its trust is kept under and Forget forgets: the network's own name, as the VPN's rule and forgetWifiNetwork()
            // ask; wifiName can be the profile's
            // ("MyWifi 1"), so that is looked up when the scan has not named the network
            readonly property string wifiSsid: Network.active?.ssid ?? Network.savedConnections.find(c => c.name === netPage.wifiName)?.ssid ?? netPage.wifiName
            // a computer with only a cable: the device list has been read and holds no Wi-Fi device. NetworkManager
            // can still report the radio as enabled then, so the switch is judged by the device, not the radio.
            readonly property bool noAdapter: Network.devicesKnown && Network.wifiDevice.length === 0
            // a fresh list each time the page opens, not whatever the last scan left
            Component.onCompleted: if (Network.wifiEnabled) Network.rescanWifi()

            Group {
                SwitchRow {
                    glyph: netPage.wifiName.length > 0 ? "wifi" : (Network.wifiEnabled && !netPage.noAdapter ? "wifi_find" : "wifi_off")
                    label: "Wi-Fi"
                    description: netPage.noAdapter ? "No Wi-Fi adapter"
                        : !Network.wifiEnabled ? (Network.wifiActionError.length > 0 ? Network.wifiActionError : "Off") : netPage.wifiName.length > 0 ? "" : "Not connected"
                    enabled: !netPage.noAdapter
                    checked: Network.wifiEnabled && !netPage.noAdapter
                    onToggled: value => Network.enableWifi(value)
                }
                SettingRow {
                    visible: Network.ethernet
                    clickable: false
                    glyph: "lan"
                    label: "Wired"
                    description: "Connected"
                }
                // the network you are on, under the switch, with what you can do to it: before, it was
                // a line of text here and its menu sat in Saved networks
                SettingRow {
                    id: current
                    visible: Network.wifiEnabled && netPage.wifiName.length > 0
                    readonly property bool portal: Network.connectivity === "portal"
                    clickable: current.portal
                    leading: Signal { strength: Network.networkStrength }
                    label: netPage.wifiName
                    selected: true
                    description: current.portal ? "Sign in to use this network"
                        : ["Connected", Network.wifiStatus === "limited" ? "No internet" : "", Network.isTrusted(netPage.wifiSsid) ? "Trusted" : ""].filter(x => x).join(" · ")
                    onActivated: if (current.portal) Network.openPublicWifiPortal()
                    control: RowMenu {
                        items: [
                            { label: "Disconnect", run: () => Network.disconnectWifiNetwork() },
                            { label: "Trusted: home or work", checked: Network.isTrusted(netPage.wifiSsid),
                              run: () => Network.setTrusted(netPage.wifiSsid, !Network.isTrusted(netPage.wifiSsid)) },
                            { label: "Forget this network", run: () => Network.forgetWifiNetwork(netPage.wifiSsid) }
                        ]
                    }
                }
            }
            Group {
                id: nearbyNetworks
                title: "Nearby"
                visible: Network.wifiEnabled && !netPage.noAdapter
                // saved ones first, then by strength in three steps, then by name: a steady order, as the
                // exact strength changes between scans and reshuffled the rows
                readonly property var others: Network.friendlyWifiNetworks.filter(n => !n.active && (n.ssid ?? "").length > 0)
                    .map(n => ({ n: n, saved: Network.isKnown(n.ssid) ? 1 : 0, step: Math.min(2, Math.floor((n.strength ?? 0) / 34)) }))
                    .sort((a, b) => (b.saved - a.saved) || (b.step - a.step) || a.n.ssid.localeCompare(b.n.ssid))
                    .map(x => x.n)
                property bool showAll: false
                note: Network.wifiActionError.length > 0 ? Network.wifiActionError
                    : others.length > 0 ? "" : (Network.wifiScanning ? "Looking for networks." : "No other networks in range.")
                Repeater {
                    // kept row by row: the list is read each second while scanning, and a plain array
                    // made every row anew each time (the page flickered)
                    model: ScriptModel { values: nearbyNetworks.showAll ? nearbyNetworks.others : nearbyNetworks.others.slice(0, 6) }
                    JoinRow {}
                }
                SettingRow {
                    visible: !nearbyNetworks.showAll && nearbyNetworks.others.length > 6
                    glyph: "expand_more"
                    label: `Show ${nearbyNetworks.others.length - 6} more`
                    onActivated: nearbyNetworks.showAll = true
                }
            }
            Group {
                id: farSaved
                // saved networks out of range: the one you are on and the ones nearby are above, so none
                // shows twice
                readonly property var list: [...Network.savedConnections]
                    .filter(c => c.name !== Network.networkName && !Network.friendlyWifiNetworks.some(n => (n.ssid ?? "") === c.ssid))
                    .sort((a, b) => (b.lastUsed - a.lastUsed) || a.name.localeCompare(b.name))
                title: "Saved, not in range"
                visible: farSaved.list.length > 0
                Repeater {
                    model: ScriptModel { values: farSaved.list; objectProp: "name" }
                    SettingRow {
                        id: net
                        required property var modelData
                        clickable: false
                        glyph: net.modelData.name === Network.networkName ? "wifi" : "wifi_find"
                        label: net.modelData.name
                        description: [net.modelData.name === Network.networkName ? "Connected now"
                            : (net.modelData.lastUsed > 0 ? `Last used ${new Date(net.modelData.lastUsed).toLocaleDateString(Qt.locale(), "d MMM")}` : "Never joined"),
                            Network.isTrusted(net.modelData.ssid) ? "Trusted" : ""].filter(x => x.length > 0).join(" · ")
                        // Trusted is a property of the network, not something done to it often: it
                        // shows in the line under the name and is set from the menu with Forget.
                        control: RowMenu {
                            items: [
                                { label: "Trusted: home or work", checked: Network.isTrusted(net.modelData.ssid),
                                  run: () => Network.setTrusted(net.modelData.ssid, !Network.isTrusted(net.modelData.ssid)) },
                                { label: "Forget this network", run: () => Network.forgetWifiNetwork(net.modelData.ssid, net.modelData.name) }
                            ]
                        }
                    }
                }
            }
            Group {
                title: "VPN"
                visible: Vpn.connections.length > 0
                Repeater {
                    model: Vpn.connections
                    SwitchRow {
                        required property var modelData
                        glyph: "vpn_key"
                        label: modelData.name
                        description: modelData.kind ?? ""
                        checked: modelData.active
                        enabled: !Vpn.busy
                        onToggled: Vpn.toggle(modelData.name)
                    }
                }
            }
            Advanced {
                SettingRow {
                    clickable: false
                    label: "This computer's address"
                    description: "On the network you are connected to"
                    control: StyledText {
                        text: Network.ipAddress || "None"
                        font.pixelSize: 15
                        font.features: { "tnum": 1 }
                        color: Tacit.inkSec
                    }
                }
            }
        }
    }

    // ── Windows ──────────────────────────────────────────────────────────────
    // Written the way the shell's own panel wrote them (modules/ii/settings/pages/HyprlandConfig.qml):
    // the value into the config, and the Hyprland key through HyprlandConfig, which rewrites the
    // override file and reloads.
    Component {
        id: windowsPage
        ColumnLayout {
            spacing: 0
            Group {
                title: "Tiling"
                ChoiceRow {
                    glyph: "dashboard"
                    label: "New windows"
                    description: Config.options.hyprland.general.layout === "master" ? "One large window, the others stacked beside it"
                        : Config.options.hyprland.general.layout === "scrolling" ? "Side by side in a row you scroll through"
                        : "Each new window takes half the space of the one in focus"
                    options: [{ value: "dwindle", label: "Split" }, { value: "master", label: "Main" }, { value: "scrolling", label: "Scrolling" }]
                    current: Config.options.hyprland.general.layout
                    onPicked: value => {
                        Config.options.hyprland.general.layout = value;
                        HyprlandConfig.set("general:layout", value);
                    }
                }
                // the two gaps together; Snug is Tacit's own 2 px between, 5 px at the edge (Config.qml)
                ChoiceRow {
                    readonly property var spaces: [
                        { value: "none", label: "None", inner: 0, outer: 0 },
                        { value: "snug", label: "Snug", inner: 2, outer: 5 },
                        { value: "roomy", label: "Roomy", inner: 8, outer: 12 }
                    ]
                    readonly property string now: (spaces.find(o => o.inner === Config.options.hyprland.general.gapsIn
                        && o.outer === Config.options.hyprland.general.gapsOut) ?? { value: "own" }).value
                    label: "Space around windows"
                    options: spaces.concat(now === "own" ? [{ value: "own", label: "Your own" }] : [])
                    current: now
                    onPicked: value => {
                        const o = spaces.find(x => x.value === value);
                        if (!o) return;
                        Config.options.hyprland.general.gapsIn = o.inner;
                        Config.options.hyprland.general.gapsOut = o.outer;
                        HyprlandConfig.setMany({ "general:gaps_in": o.inner, "general:gaps_out": o.outer });
                    }
                }
            }
            Group {
                title: "Look and motion"
                // The window band's line (tacit-frame, the plugin Hyprland loads at the start): a short line at the top of
                // every window to carry it to the notch, the dock or a side. Off, the plugin is let go at once and not
                // loaded at the next start (session/hypr/hyprland/general.lua reads the same file); held windows come back.
                SwitchRow {
                    id: lineRow
                    readonly property string plugin: "/usr/lib/tacit/hyprland/tacit-frame.so"
                    readonly property string flag: FileUtils.trimFileProtocol(`${Directories.state}/user/window-line-off`)
                    property bool installed: false
                    property bool lineOn: true
                    visible: installed
                    glyph: "drag_handle"
                    label: "Line on windows"
                    description: "Carry a window by it to the notch to close, the dock to hide, or a side; the three-finger swipes need it too"
                    checked: lineRow.lineOn
                    onToggled: value => {
                        lineRow.lineOn = value;
                        Quickshell.execDetached(["sh", "-c", value
                            ? 'rm -f "$1"; hyprctl plugin load "$2"'
                            : 'mkdir -p "$(dirname "$1")" && : > "$1"; hyprctl plugin unload "$2"', "sh", lineRow.flag, lineRow.plugin]);
                    }
                    Process {
                        running: true
                        command: ["sh", "-c", 'test -e "$1" && { test -e "$2" && echo off || echo on; }', "sh", lineRow.plugin, lineRow.flag]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                lineRow.installed = this.text.trim().length > 0;
                                lineRow.lineOn = this.text.trim() !== "off";
                            }
                        }
                    }
                }
                SwitchRow {
                    glyph: "blur_on"
                    label: "Blur behind see-through windows"
                    checked: Config.options.hyprland.decoration.blur.enabled
                    onToggled: value => {
                        Config.options.hyprland.decoration.blur.enabled = value;
                        HyprlandConfig.set("decoration:blur:enabled", value ? 1 : 0);
                    }
                }
                SwitchRow {
                    glyph: "animation"
                    label: "Animate windows"
                    description: "Opening, closing, moving and switching workspaces"
                    checked: Config.options.hyprland.animations.enable
                    onToggled: value => {
                        Config.options.hyprland.animations.enable = value;
                        HyprlandConfig.set("animations:enabled", value ? 1 : 0);
                        // the same switch as Reduce motion (Accessibility), so apps follow it too
                        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", value ? "true" : "false"]);
                    }
                }
            }
            Advanced {
                StepperRow {
                    glyph: "width_normal"
                    label: "Space between windows"
                    value: Config.options.hyprland.general.gapsIn
                    from: 0
                    to: 40
                    suffix: " px"
                    onMoved: value => {
                        Config.options.hyprland.general.gapsIn = value;
                        HyprlandConfig.set("general:gaps_in", value);
                    }
                }
                StepperRow {
                    glyph: "fit_screen"
                    label: "Space at the screen edge"
                    value: Config.options.hyprland.general.gapsOut
                    from: 0
                    to: 60
                    suffix: " px"
                    onMoved: value => {
                        Config.options.hyprland.general.gapsOut = value;
                        HyprlandConfig.set("general:gaps_out", value);
                    }
                }
                StepperRow {
                    glyph: "rounded_corner"
                    label: "Corner rounding"
                    value: Config.options.hyprland.decoration.rounding
                    from: 0
                    to: 30
                    suffix: " px"
                    onMoved: value => {
                        Config.options.hyprland.decoration.rounding = value;
                        HyprlandConfig.set("decoration:rounding", value);
                    }
                }
                StepperRow {
                    glyph: "border_style"
                    label: "Border"
                    value: Config.options.hyprland.general.borderSize
                    from: 0
                    to: 10
                    suffix: " px"
                    onMoved: value => {
                        Config.options.hyprland.general.borderSize = value;
                        HyprlandConfig.set("general:border_size", value);
                    }
                }
                StepperRow {
                    glyph: "opacity"
                    label: "Windows not in use"
                    description: "How solid the windows you are not typing in are"
                    value: Math.round(Config.options.hyprland.decoration.inactiveOpacity * 100)
                    from: 50
                    to: 100
                    stepSize: 5
                    suffix: "%"
                    onMoved: value => {
                        Config.options.hyprland.decoration.inactiveOpacity = value / 100;
                        HyprlandConfig.set("decoration:inactive_opacity", value / 100);
                    }
                }
                StepperRow {
                    visible: Config.options.hyprland.decoration.blur.enabled
                    glyph: "blur_medium"
                    label: "Blur strength"
                    value: Config.options.hyprland.decoration.blur.size
                    from: 1
                    to: 20
                    onMoved: value => {
                        Config.options.hyprland.decoration.blur.size = value;
                        HyprlandConfig.set("decoration:blur:size", value);
                    }
                }
            }
        }
    }

    // ── Notifications ────────────────────────────────────────────────────────
    Component {
        id: notificationsPage
        ColumnLayout {
            id: np
            spacing: 0
            // Do not disturb is the shell's; asked over IPC, since a second notification server
            // cannot run in this process.
            property bool silent: false
            Process {
                id: readSilent
                running: true
                command: ["qs", "-p", Directories.shellFile, "ipc", "call", "notifications", "silent"]
                // a reply that was already on its way when the switch moved would flip it back; and with
                // no shell to answer, the state is not Do not disturb
                stdout: SplitParser { onRead: data => { if (!writeSilent.running) np.silent = data.trim() === "true"; } }
                onExited: exitCode => { if (exitCode !== 0) np.silent = false; }
            }
            Process {
                id: writeSilent
                onExited: readSilent.running = true
            }
            Connections {
                target: root
                function onActiveChanged() {
                    if (root.active)
                        readSilent.running = true;
                }
            }
            Group {
                SwitchRow {
                    glyph: "do_not_disturb_on"
                    label: "Do not disturb"
                    description: "Notifications arrive without a pop-up and wait in the notification centre"
                    checked: np.silent
                    onToggled: value => {
                        np.silent = value;
                        writeSilent.command = ["qs", "-p", Directories.shellFile, "ipc", "call", "notifications", "setSilent", value ? "true" : "false"];
                        writeSilent.running = true;
                    }
                }
            }
            Group {
                title: "Pop-ups"
                ChoiceRow {
                    glyph: "timer"
                    label: "How long a pop-up stays"
                    options: [3000, 5000, 7000, 10000].concat([3000, 5000, 7000, 10000].includes(Config.options.notifications.timeout) ? [] : [Config.options.notifications.timeout])
                        .map(ms => ({ value: ms, label: `${ms / 1000} s` }))
                    current: Config.options.notifications.timeout
                    onPicked: value => Config.options.notifications.timeout = value
                }
                ChoiceRow {
                    glyph: "picture_in_picture"
                    label: "Where pop-ups appear"
                    options: [
                        { value: "top_right", label: "Top right" }, { value: "top_center", label: "Top centre" },
                        { value: "top_left", label: "Top left" }, { value: "bottom_right", label: "Bottom right" },
                        { value: "bottom_center", label: "Bottom centre" }, { value: "bottom_left", label: "Bottom left" }
                    ]
                    current: Config.options.notifications.position === "top" ? "top_right"
                        : Config.options.notifications.position === "bottom" ? "bottom_right" : Config.options.notifications.position
                    onPicked: value => Config.options.notifications.position = value
                }
            }
        }
    }

    // ── Date & time ──────────────────────────────────────────────────────────
    Component {
        id: timePage
        ColumnLayout {
            id: tp
            spacing: 0
            property string zone: ""
            property bool ntp: true
            property var zones: []
            // each preset sets the three formats the shell reads, so they never disagree
            readonly property var datePresets: [
                { value: "day", long: "ddd, dd/MM", short: "dd/MM", year: "dd/MM/yyyy" },
                { value: "month", long: "ddd, MM/dd", short: "MM/dd", year: "MM/dd/yyyy" },
                { value: "iso", long: "ddd, MM-dd", short: "MM-dd", year: "yyyy-MM-dd" },
                { value: "written", long: "ddd d MMM", short: "d MMM", year: "d MMM yyyy" }
            ]
            Process {
                id: readTime
                running: true
                command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP"]
                stdout: SplitParser {
                    onRead: data => {
                        if (data.startsWith("Timezone="))
                            tp.zone = data.slice(9);
                        else if (data.startsWith("NTP="))
                            tp.ntp = data.slice(4) === "yes";
                    }
                }
            }
            Process {
                running: true
                command: ["timedatectl", "list-timezones"]
                stdout: StdioCollector { onStreamFinished: tp.zones = text.split("\n").filter(z => z.length > 0) }
            }
            // timedated asks for the password through the shell's polkit window
            Process {
                id: setTime
                onExited: readTime.running = true
            }

            Summary {
                glyph: "schedule"
                eyebrow: tp.zone.replace(/_/g, " ")
                title: DateTime.time
                subtitle: DateTime.longDate
            }
            // Translation.qml lists the languages it has files for; Settings' own words are not
            // translated yet, the rest of the desktop is.
            Group {
                title: "Language"
                ChoiceRow {
                    glyph: "translate"
                    label: "The desktop's language"
                    options: [{ value: "auto", label: `Same as the system (${Qt.locale().nativeLanguageName})` }]
                        .concat(Translation.availableLanguages.map(code => ({ value: code, label: root.languageName(code) })))
                    current: Config.options.language.ui
                    onPicked: value => Config.options.language.ui = value
                }
            }
            Group {
                title: "Format"
                ChoiceRow {
                    glyph: "schedule"
                    label: "Clock"
                    options: [
                        { value: "hh:mm", label: `24-hour · ${Qt.locale().toString(new Date(2026, 0, 1, 14, 30), "hh:mm")}` },
                        { value: "h:mm AP", label: `12-hour · ${Qt.locale().toString(new Date(2026, 0, 1, 14, 30), "h:mm AP")}` }
                    ]
                    current: Config.options.time.format
                    onPicked: value => Config.options.time.format = value
                }
                ChoiceRow {
                    glyph: "calendar_today"
                    label: "Date"
                    options: tp.datePresets.map(p => ({ value: p.value, label: Qt.locale().toString(new Date(), p.year) }))
                    current: (tp.datePresets.find(p => p.long === Config.options.time.dateFormat) ?? { value: Config.options.time.dateFormat }).value
                    onPicked: value => {
                        const p = tp.datePresets.find(q => q.value === value);
                        Config.options.time.dateFormat = p.long;
                        Config.options.time.shortDateFormat = p.short;
                        Config.options.time.dateWithYearFormat = p.year;
                    }
                }
            }
            Group {
                title: "Time zone"
                note: "Changing these asks for your password."
                ChoiceRow {
                    glyph: "public"
                    label: "Time zone"
                    options: tp.zones.map(z => ({ value: z, label: z.replace(/_/g, " ") }))
                    current: tp.zone
                    onPicked: value => {
                        setTime.command = ["timedatectl", "set-timezone", value];
                        setTime.running = true;
                    }
                }
                SwitchRow {
                    glyph: "sync"
                    label: "Set the time automatically"
                    description: "From time servers on the internet"
                    checked: tp.ntp
                    onToggled: value => {
                        setTime.command = ["timedatectl", "set-ntp", value ? "true" : "false"];
                        setTime.running = true;
                    }
                }
            }
        }
    }

    // ── Palette & search ─────────────────────────────────────────────────────
    Component {
        id: palettePage
        ColumnLayout {
            spacing: 0
            // The palette reads only a query's first character, so a prefix is one character and
            // no other section's (the hidden ones too); anything else goes back with the reason.
            function setPrefix(row, key, value) {
                const prefix = Config.options.search.prefix;
                const taken = ["action", "app", "clipboard", "dictation", "emojis", "files", "keybinds", "math", "shellCommand", "symbols", "webSearch", "windows"]
                    .some(k => k !== key && prefix[k] === value);
                row.description = value.length !== 1 ? "One character" : taken ? "Another section starts with it" : "";
                if (row.description.length > 0)
                    row.revert();
                else
                    prefix[key] = value;
            }
            Group {
                title: "What the palette shows"
                note: "A hidden section is gone from the palette, its shortcut included."
                Repeater {
                    model: [
                        { key: "apps", label: "Apps", glyph: "apps" },
                        { key: "windows", label: "Open windows", glyph: "select_window" },
                        { key: "files", label: "Files", glyph: "folder" },
                        { key: "calculator", label: "Calculator", glyph: "calculate" },
                        { key: "clipboard", label: "Clipboard history", glyph: "content_paste" },
                        { key: "emoji", label: "Emoji", glyph: "mood" },
                        { key: "symbols", label: "Symbols", glyph: "special_character" },
                        { key: "actions", label: "Actions", glyph: "bolt" },
                        { key: "system", label: "System", glyph: "power_settings_new" },
                        { key: "settings", label: "Settings", glyph: "settings" },
                        { key: "keybinds", label: "Keyboard shortcuts", glyph: "keyboard" },
                        { key: "flow", label: "Past dictations", glyph: "mic" },
                        { key: "claude", label: "Your agent", glyph: "chat" },
                        { key: "command", label: "Run a command", glyph: "terminal" },
                        { key: "web", label: "Web search", glyph: "public" }
                    ]
                    EyeRow {
                        required property var modelData
                        // its shortcut said under it (it was a second list of the same sections)
                        readonly property string prefix: ({
                            apps: Config.options.search.prefix.app, actions: Config.options.search.prefix.action,
                            clipboard: Config.options.search.prefix.clipboard, emoji: Config.options.search.prefix.emojis,
                            keybinds: Config.options.search.prefix.keybinds, command: Config.options.search.prefix.shellCommand,
                            web: Config.options.search.prefix.webSearch
                        })[modelData.key] ?? ""
                        glyph: modelData.glyph
                        label: modelData.label
                        description: prefix.length > 0 ? `Start with ${prefix} to search only here` : ""
                        checked: Config.options.commandPalette.sections[modelData.key] ?? true
                        onToggled: value => Config.options.commandPalette.sections[modelData.key] = value
                    }
                }
            }
            Group {
                title: "Files"
                SwitchRow {
                    glyph: "folder_open"
                    label: "Find files by name"
                    checked: Config.options.commandPalette.files.enable
                    onToggled: value => Config.options.commandPalette.files.enable = value
                }
                FieldRow {
                    visible: Config.options.commandPalette.files.enable
                    label: "Look in"
                    placeholder: "Your home folder"
                    text: Config.options.commandPalette.files.root
                    onCommitted: value => Config.options.commandPalette.files.root = value
                }
            }
            Group {
                title: "Search"
                SwitchRow {
                    label: "Forgive typos"
                    description: "Finds apps even when a name is misspelled; clipboard search then covers your last 100 items"
                    checked: Config.options.search.sloppy
                    onToggled: value => Config.options.search.sloppy = value
                }
                FieldRow {
                    id: engineRow
                    label: "Web search address"
                    text: Config.options.search.engineBaseUrl
                    // the words are added to it as they are: with none, a web search opened nothing
                    onCommitted: value => {
                        if (value.length === 0)
                            engineRow.revert();
                        else
                            Config.options.search.engineBaseUrl = value;
                    }
                }
            }
            // the characters that start a search in one section, rarely changed
            Advanced {
                FieldRow { id: pfxApp; label: "Search apps with"; compact: true; text: Config.options.search.prefix.app; onCommitted: value => setPrefix(pfxApp, "app", value) }
                FieldRow { id: pfxAction; label: "Search actions with"; compact: true; text: Config.options.search.prefix.action; onCommitted: value => setPrefix(pfxAction, "action", value) }
                FieldRow { id: pfxClipboard; label: "Search the clipboard with"; compact: true; text: Config.options.search.prefix.clipboard; onCommitted: value => setPrefix(pfxClipboard, "clipboard", value) }
                FieldRow { id: pfxEmojis; label: "Search emoji with"; compact: true; text: Config.options.search.prefix.emojis; onCommitted: value => setPrefix(pfxEmojis, "emojis", value) }
                FieldRow { id: pfxKeybinds; label: "Search keyboard shortcuts with"; compact: true; text: Config.options.search.prefix.keybinds; onCommitted: value => setPrefix(pfxKeybinds, "keybinds", value) }
                FieldRow { id: pfxCommand; label: "Run a command with"; compact: true; text: Config.options.search.prefix.shellCommand; onCommitted: value => setPrefix(pfxCommand, "shellCommand", value) }
                FieldRow { id: pfxWeb; label: "Search the web with"; compact: true; text: Config.options.search.prefix.webSearch; onCommitted: value => setPrefix(pfxWeb, "webSearch", value) }
            }
        }
    }

    // ── Your account ─────────────────────────────────────────────────────────
    Component {
        id: accountPage
        ColumnLayout {
            id: acct
            spacing: 0
            // ~/.face is the picture login screens and apps read for the account; the shell's own
            // widgets read profile.avatarPath, so both point at it.
            readonly property string facePath: `${Quickshell.env("HOME")}/.face`

            Group {
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 20
                    spacing: 16
                    Rectangle {
                        id: faceTile
                        implicitWidth: 64
                        implicitHeight: 64
                        radius: 32
                        color: ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.9)
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: faceTile.width
                                height: faceTile.height
                                radius: faceTile.radius
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: "person"
                            iconSize: 32
                            color: Tacit.inkMeta
                        }
                        Image {
                            id: face
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            // the query changes the url, so a new picture over the same file is read again
                            source: `file://${acct.facePath}?${root.faceVersion}`
                            cache: false
                            asynchronous: true
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        StyledText {
                            text: Config.options.profile.displayName || SystemInfo.username
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: Appearance.colors.colInkMain
                        }
                        StyledText {
                            text: `${SystemInfo.username} on ${SystemInfo.hostname}`
                            font.pixelSize: 15
                            color: Tacit.inkMeta
                        }
                    }
                }
            }
            Group {
                title: "You"
                FieldRow {
                    glyph: "badge"
                    label: "Your name"
                    description: "The notch uses it to say hello"
                    placeholder: SystemInfo.username
                    text: Config.options.profile.displayName
                    // the notch says hello by the first word of it: Setup's first name was kept on its own and won
                    onCommitted: value => {
                        Config.options.profile.displayName = value;
                        Config.options.island.greeting.name = value.trim().split(/\s+/)[0] ?? "";
                    }
                }
                SettingRow {
                    id: pictureRow
                    glyph: "account_circle"
                    label: "Picture"
                    description: "For login screens and apps that show who is signed in"
                    clickable: false
                    control: TextButton {
                        label: "Choose…"
                        // the picture it replaces is kept once, as ~/.face.previous
                        onPressed: root.pickFile("Your picture", `${FileUtils.trimFileProtocol(Directories.pictures)}`, path => {
                            const home = Quickshell.env("HOME");
                            faceCopy.command = ["bash", "-c", '[ -e "$2/.face" ] && cp -f "$2/.face" "$2/.face.previous"; cp -f "$1" "$2/.face"', "_", path, home];
                            faceCopy.running = true;
                            Config.options.profile.avatarPath = `${home}/.face`;
                        })
                    }
                }
            }
            // the one you have now and the new one twice, on a line under the row (as a Wi-Fi password is asked);
            // scripts/settings/passwd.py changes it, the passwords on its stdin
            Group {
                title: "Password"
                SettingRow {
                    id: passwordRow
                    property bool asking: false
                    property string said: ""
                    glyph: "password"
                    label: "Change your password"
                    description: passwdProc.running ? "Changing…"
                        : passwordRow.said.length > 0 ? passwordRow.said : "Asks for the one you have now, then the new one"
                    onActivated: {
                        passwordRow.said = "";
                        passwordRow.asking = true;
                        nowField.focusInput();
                    }
                    function submit() {
                        if (passwdProc.running)
                            return;
                        if (newField.text.length === 0) {
                            passwordRow.said = "Type a new one";
                            newField.focusInput();
                            return;
                        }
                        if (newField.text !== againField.text) {
                            passwordRow.said = "The new ones are not the same";
                            againField.text = "";
                            againField.focusInput();
                            return;
                        }
                        passwdProc.secret = `${nowField.text}\n${newField.text}\n`;
                        passwdProc.running = true;
                    }
                }
                SettingRow {
                    visible: passwordRow.asking
                    topRule: true
                    clickable: false
                    // three fields and two words do not fit beside a label in a narrow window: under it, the row's width
                    stacked: true
                    label: "Now, then new"
                    onVisibleChanged: if (visible) nowField.focusInput()
                    control: RowLayout {
                        spacing: 6
                        LineField { id: nowField; Layout.fillWidth: true; implicitWidth: 100; secret: true; placeholder: "Now"; onAccepted: newField.focusInput(); onCancelled: passwordCancel.picked() }
                        LineField { id: newField; Layout.fillWidth: true; implicitWidth: 100; secret: true; placeholder: "New"; onAccepted: againField.focusInput(); onCancelled: passwordCancel.picked() }
                        LineField { id: againField; Layout.fillWidth: true; implicitWidth: 100; secret: true; placeholder: "Again"; onAccepted: passwordRow.submit(); onCancelled: passwordCancel.picked() }
                        Slab {
                            id: passwordCancel
                            text: "Cancel"
                            onPicked: {
                                nowField.text = newField.text = againField.text = "";
                                passwordRow.said = "";
                                passwordRow.asking = false;
                            }
                        }
                        Slab { text: "Change"; key: "↵"; tone: "default"; onPicked: passwordRow.submit() }
                    }
                }
                Process {
                    id: passwdProc
                    property string secret: ""
                    stdinEnabled: true
                    command: ["python3", "-I", Quickshell.shellPath("scripts/settings/passwd.py")]
                    onStarted: {
                        passwdProc.write(passwdProc.secret);
                        passwdProc.secret = "";
                    }
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const said = text.trim();
                            passwordRow.said = said === "changed" ? "Changed" : (said || "It did not change");
                            // only what was refused is typed again (passwd.py's words): the one now, a try that counts
                            // toward the lock-out like one at the lock screen, or the new one twice; all three otherwise
                            const wrongNow = said === "That is not your password now";
                            const wrongNew = said.startsWith("The new one");
                            if (!wrongNew)
                                nowField.text = "";
                            if (!wrongNow)
                                newField.text = againField.text = "";
                            if (said === "changed")
                                passwordRow.asking = false;
                            else if (wrongNew)
                                newField.focusInput();
                            else
                                nowField.focusInput();
                        }
                    }
                }
            }
        }
    }

    // ── Accounts ─────────────────────────────────────────────────────────────
    // The agents' sign-ins and keys (praxis-composer-accounts-plan §2.11). agent-host keeps them, so
    // every change here is a request to it through AccountsModel, which exists only while this page
    // shows. With the host down the rows are what it last wrote to accounts.json, without controls.
    Component {
        id: accountsPage
        ColumnLayout {
            id: accPage
            spacing: 0

            Praxis.AccountsModel {
                id: accountsModel
                visible: false
            }
            readonly property var am: accountsModel
            readonly property bool fromHost: accountsModel.available
            // accounts.json in the shape of the host's state; it says nothing of installs or providers
            readonly property var saved: {
                const f = root.accountsSaved;
                if (!f || !Array.isArray(f.accounts))
                    return { accounts: [], keys: [] };
                const folders = f.defaults?.folders ?? {};
                return {
                    accounts: f.accounts.map(a => Object.assign({}, a, f.status?.[a.id] ?? {}, {
                        personal: !(a.home ?? "").includes("/agent-host/accounts/"),
                        default: f.default?.[a.agent] === a.id,
                        folders: Object.keys(folders).filter(p => folders[p]?.run?.[a.agent]?.account === a.id)
                    })),
                    keys: (f.keys ?? []).map(k => Object.assign({}, k, { use: k.use ?? [], state: k.check?.state ?? k.state ?? "unchecked" }))
                };
            }
            readonly property var accounts: accPage.fromHost ? accountsModel.accounts : accPage.saved.accounts
            readonly property var keys: accPage.fromHost ? accountsModel.keys : accPage.saved.keys

            // The host answers a moment after the page opens; until then no state of the link shows.
            property bool settled: false
            readonly property bool down: accPage.settled && !(accountsModel.link?.connected ?? false)
            // connected, and its hello named no accounts feature: a host older than this page
            property bool old: false
            readonly property bool oldNow: (accountsModel.link?.connected ?? false) && !accountsModel.available
            onOldNowChanged: {
                if (accPage.oldNow) {
                    oldWait.restart();
                } else {
                    oldWait.stop();
                    accPage.old = false;
                }
            }
            Timer {
                interval: 1500
                running: true
                onTriggered: accPage.settled = true
            }
            Timer {
                id: oldWait
                interval: 1200
                onTriggered: accPage.old = accPage.oldNow
            }
            // the host's state has arrived at least once
            property bool heard: false
            Connections {
                target: accountsModel
                function onAgentsChanged() { accPage.heard = true; }
                function onAccountsChanged() { accPage.heard = true; }
                function onSigninChanged() {
                    const s = accountsModel.signin;
                    if (s && accPage.pending[s.account])
                        accPage.put("pending", s.account, undefined);
                    if (s?.step === "done" || s?.step === "cancelled")
                        accPage.put("started", s.account, undefined);
                }
                function onInstallChanged() {
                    const i = accountsModel.install;
                    if (i && accPage.installPending[i.agent])
                        accPage.put("installPending", i.agent, undefined);
                }
            }

            readonly property var shownAgents: accountsModel.agentOrder.filter(a => !!accountsModel.agents[a])
            readonly property string needsLine: accPage.shownAgents.filter(a => !accountsModel.readyAgents.includes(a))
                .map(a => root.agentNeed(a, accountsModel.stepOf(a, ""))).filter(s => s.length > 0).join(" · ")
            // PAM opens the keyring with the password the lock is given (pam_gnome_keyring); a fingerprint gives it none
            readonly property string lockedLine: "The keyring is locked; keys open when you unlock the screen with your password"

            // Repeaters take these by id, and get a new list only when the ids change: a state push
            // keeps every row, with whatever is typed into it.
            function keep(obj, name, value) {
                if (JSON.stringify(obj[name]) !== JSON.stringify(value))
                    obj[name] = value;
            }
            readonly property var agentListNow: accountsModel.agentOrder.filter(a => accPage.fromHost ? !!accountsModel.agents[a]
                : accPage.accounts.some(x => x.agent === a))
            property var agentList: []
            onAgentListNowChanged: accPage.keep(accPage, "agentList", accPage.agentListNow)

            // ── reading
            function accountsOf(agent) { return accPage.accounts.filter(a => a.agent === agent); }
            function account(id) { return accPage.accounts.find(a => a.id === id) ?? null; }
            function defaultOf(agent) {
                const l = accPage.accountsOf(agent);
                return l.find(a => a.default) ?? l.find(a => a.personal) ?? l[0] ?? null;
            }
            function name(agent) { return accountsModel.agentName(agent); }
            // the page shows four rows (and Keys); one opened shows only that agent, or the keys
            property string viewing: ""
            onViewingChanged: root.revealPage()
            // who an agent is signed in as: the email and plan, or the providers it can use
            function whoOf(agent) {
                const a = accPage.defaultOf(agent);
                if (!a) return "";
                if (agent === "pi" || agent === "opencode")
                    return (a.providers ?? []).filter(p => p.state === "ready" && (agent !== "pi" || p.via !== "file"))
                        .map(p => accPage.providerName(p.id, p.via)).join(", ");
                return [a.email ?? "", accPage.planText(a)].filter(s => s).join(" · ");
            }
            function providerName(id, via) {
                if (via === "oauth" && id === "openai")
                    return "ChatGPT";
                const n = accountsModel.providerName(id);
                return n !== id ? n : ({ xai: "xAI", "kimi-coding": "Kimi", gitlab: "GitLab", modal: "Modal" })[id] ?? id;
            }
            // "a", "a and b", "a, b and c"
            function list(words) {
                return words.length > 1 ? `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}` : (words[0] ?? "");
            }
            function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""; }
            function keyProvider(a) {
                return accPage.keys.find(k => k.id === a?.key)?.provider ?? ({ claude: "anthropic", codex: "openai" })[a?.agent] ?? "";
            }
            function envOf(provider) { return accountsModel.providers.find(p => p.id === provider)?.env ?? {}; }
            // a key pi or opencode keeps in its own file, into the keyring and given to it (host key_import)
            function importKey(agent, provider) {
                const line = `import:${agent}|${provider}`;
                accPage.put("keyNotes", line, "Connecting…");
                accountsModel.send({ op: "key_import", agent: agent, provider: provider }, r => {
                    if (r.ev === "key" && r.state !== "refused" && r.id) accPage.put("keyNotes", line, undefined);
                    else accPage.put("keyNotes", line, r.ev === "key" ? "The key was refused" : `Not connected: ${r.message ?? ""}`);
                });
            }
            // a key pasted on an agent's page: kept, then given to that agent, in one step
            function pasteKey(agent, provider, secret) {
                const line = `paste:${agent}`;
                accPage.put("keyNotes", line, "Checking…");
                accountsModel.setKey(provider, "", secret, r => {
                    if (r.ev === "key" && r.state !== "refused" && r.id) {
                        accountsModel.useKey(r.id, agent, true);
                        accPage.put("keyNotes", line, undefined);
                        if (accPage.open === line) accPage.open = "";
                    } else
                        accPage.put("keyNotes", line, r.ev === "key" ? "The key was refused" : `Not saved: ${r.message ?? ""}`);
                });
            }
            // what an account signs in with: a plan, the Console, or a key by its last four
            function planText(a) {
                if (a.use === "key") {
                    const k = accPage.keys.find(x => x.id === a.key);
                    return `${accPage.providerName(accPage.keyProvider(a))} key` + (k?.last4 ? ` ••••${k.last4}` : "");
                }
                if (a.agent === "codex")
                    return a.plan ? `ChatGPT · ${accPage.cap(a.plan)} plan` : "ChatGPT";
                if (a.use === "console")
                    return "Console";
                return a.plan ? `${accPage.cap(a.plan)} plan` : "";
            }
            // the line under an account's name when no sign-in is in progress
            function facts(a) {
                const words = [];
                const byProvider = a.agent === "pi" || a.agent === "opencode";
                switch (a.state) {
                case "ready": words.push(a.email ?? "", byProvider ? "" : accPage.planText(a)); break;
                case "signedOut": words.push(byProvider ? "Needs a provider" : "Not signed in"); break;
                case "noProvider": words.push("Needs a provider"); break;
                case "expired": words.push(a.since ? `Signed out on ${Qt.formatDate(new Date(a.since), "d MMM")}` : "Signed out"); break;
                case "noKey": words.push(`There is no ${accPage.providerName(accPage.keyProvider(a))} key for it`); break;
                case "keyRefused": words.push(`The ${accPage.providerName(accPage.keyProvider(a))} key was refused`); break;
                case "locked": words.push("The keyring is locked"); break;
                case "checking": words.push("Checking…"); break;
                case "signingIn": words.push("Signing in…"); break;
                }
                if (a.state === "ready" && !words.some(w => w))
                    words.push("Ready");
                if (accPage.accountsOf(a.agent).length > 1 && accPage.defaultOf(a.agent)?.id === a.id)
                    words.push("default");
                const used = (a.folders ?? []).map(p => p.split("/").filter(s => s).pop() ?? p);
                if (used.length)
                    words.push(`used in ${used.join(", ")}`);
                return words.filter(w => w).join(" · ");
            }

            // ── the one second line open on the page
            // rename:<account>, useKey:<account>, signOut:<account>[|<provider>], remove:<account>,
            // code:<account>, add:<agent>, key:<provider>, replace:<key>, removeKey:<key>
            property string open: ""
            // the account an open Add key line adds a key for (it then signs in with it), or ""
            property string keyFor: ""
            onOpenChanged: accPage.keyFor = ""
            function toggle(line) { accPage.open = accPage.open === line ? "" : line; }
            function put(map, key, value) {
                const o = Object.assign({}, accPage[map]);
                if (value === undefined)
                    delete o[key];
                else
                    o[key] = value;
                accPage[map] = o;
            }

            // ── signing in
            // by account: the sign-ins started here ({ method, provider, at }, for Try again and the
            // ten minutes), the ones the host has not reported on yet, and its refusals (the message)
            property var started: ({})
            property var pending: ({})
            property var refusals: ({})
            property double now: Date.now()
            Timer {
                interval: 15000
                repeat: true
                running: Object.keys(accPage.started).length > 0
                onTriggered: accPage.now = Date.now()
            }
            function signIn(id, method, provider) {
                accPage.put("started", id, { method: method, provider: provider, at: Date.now() });
                accPage.now = Date.now();
                accPage.put("refusals", id, undefined);
                accPage.put("pending", id, true);
                accPage.open = "";
                accountsModel.login(id, method, provider, r => {
                    if (r.ev !== "error")
                        return;
                    accPage.put("pending", id, undefined);
                    accPage.put("refusals", id, r.message ?? "");
                });
            }
            // the way the last one began; a sign-in still open in the host is cancelled first
            function again(a, provider) {
                const s = accPage.started[a.id];
                const live = accountsModel.signin?.account === a.id && !accountsModel.ended(accountsModel.signin.step);
                if (live)
                    accountsModel.cancel(a.id);
                accPage.signIn(a.id, s?.method ?? (provider ? "" : a.use === "console" ? "console" : "browser"), s?.provider ?? provider ?? "");
            }
            // Cancel: the host's sign-in, or only a refusal shown here
            function cancelSignIn(id) {
                accPage.put("started", id, undefined);
                accPage.put("pending", id, undefined);
                if (accPage.open === `code:${id}`)
                    accPage.open = "";
                const refusedOnly = accPage.refusals[id] !== undefined && accountsModel.signin?.account !== id;
                accPage.put("refusals", id, undefined);
                if (!refusedOnly)
                    accountsModel.cancel(id);
            }
            // a sign-in shown on an account's row, or for pi and opencode on the provider's row:
            // starting | waiting | code | device | busy | failed | late | ""
            function flowOf(id, provider) {
                const s = accountsModel.signin?.account === id ? accountsModel.signin : null;
                const p = s?.provider ?? accPage.started[id]?.provider ?? "";
                if (provider !== undefined && p !== provider)
                    return "";
                const late = accPage.now - (accPage.started[id]?.at ?? accPage.now) >= 600000;
                switch (s?.step ?? "") {
                case "waiting":
                case "code":
                    return late ? "late" : s.step;
                case "device":
                case "busy":
                    return s.step;
                case "failed":
                    return late ? "late" : "failed";
                }
                if (accPage.pending[id])
                    return "starting";
                if (accPage.refusals[id] !== undefined)
                    return "failed";
                return provider === undefined && accPage.account(id)?.state === "signingIn" ? "waiting" : "";
            }
            // the holder of a busy port: one of the host's sign-ins (an account or an agent), else
            // what the host could name
            function holder(h) {
                const held = accPage.account(h) ?? accPage.accounts.find(a => a.agent === h && a.state === "signingIn") ?? null;
                return { account: held, name: held ? accPage.name(held.agent) : h ? accPage.name(h) : "" };
            }
            function flowText(flow, id) {
                const s = accountsModel.signin?.account === id ? accountsModel.signin : null;
                switch (flow) {
                case "starting": return "Starting the sign-in…";
                case "waiting": return s?.opened === false && s.url ? "Open the page to sign in" : "Finish signing in in your browser…";
                case "code": return "Finish signing in in your browser…";
                case "device": return "Waiting for the code to be entered…";
                case "busy": {
                    const who = accPage.holder(s?.holder ?? "").name;
                    return who ? `Another sign-in is open (${who})` : "Another ChatGPT sign-in is open";
                }
                case "failed": {
                    const why = s ? (s.message ?? "") : (accPage.refusals[id] ?? "");
                    return "Sign-in didn't finish" + (why ? `: ${why}` : "");
                }
                case "late": return "Sign-in didn't finish in 10 minutes";
                }
                return "";
            }

            // ── accounts
            function check(id) { accountsModel.send({ op: "account_check", account: id }, accPage.noted(id, "check it")); }
            function setUse(id, use, key) {
                const req = { op: "account_set", account: id, use: use };
                if (key)
                    req.key = key;
                accPage.open = "";
                accountsModel.send(req, accPage.noted(id, "change how it signs in"));
            }
            // pi's and opencode's rows, "<account>|<provider>": each connected provider, then one
            // being connected
            function providerRows(agent) {
                let rows = [];
                for (const a of accPage.accountsOf(agent)) {
                    const ps = a.providers ?? [];
                    rows = rows.concat(ps.map(p => `${a.id}|${p.id}`));
                    const s = accountsModel.signin?.account === a.id ? accountsModel.signin : null;
                    const p = s?.provider ?? accPage.started[a.id]?.provider ?? "";
                    const live = s ? !["done", "cancelled"].includes(s.step) : (!!accPage.pending[a.id] || accPage.refusals[a.id] !== undefined);
                    if (p && live && !ps.some(x => x.id === p))
                        rows.push(`${a.id}|${p}`);
                }
                return rows;
            }
            // Connect a provider: pi's and opencode's own sign-ins (pi's Claude plan is left out: it
            // bills as extra usage), then a key from Keys the agent can read
            function connectOptions(agent) {
                const have = (accPage.defaultOf(agent)?.providers ?? []).filter(p => !p.state || p.state === "ready").map(p => p.id);
                const oauth = agent === "pi"
                    ? [["openai-codex", "ChatGPT"], ["github-copilot", "GitHub Copilot"], ["openrouter", "OpenRouter"], ["xai", "xAI"], ["kimi-coding", "Kimi"]]
                    : [["opencode", "OpenCode Zen"], ["openai", "ChatGPT"], ["github-copilot", "GitHub Copilot"], ["gitlab", "GitLab"]];
                // the services it signs in to (keys are rows of their own on its page)
                return oauth.filter(o => !have.includes(o[0])).map(o => ({ value: `oauth:${o[0]}`, label: o[1] }));
            }
            function connect(agent, value) {
                const a = accPage.defaultOf(agent);
                const kind = value.split(":")[0];
                const id = value.split(":").slice(1).join(":");
                if (a && kind === "oauth")
                    accPage.signIn(a.id, "", id);
            }

            // ── installs
            property var installPending: ({})
            property var installRefusals: ({})
            // what stands before an agent's accounts: notInstalled | needsNode | installing | ""
            function installStep(agent) {
                if (!accPage.fromHost)
                    return "";
                const s = accountsModel.stepOf(agent, "");
                if (accPage.installPending[agent] && (s === "notInstalled" || s === "needsNode"))
                    return "installing";
                return ["notInstalled", "needsNode", "installing"].includes(s) ? s : "";
            }
            function install(agent, withNode) {
                accPage.put("installRefusals", agent, undefined);
                accPage.put("installPending", agent, true);
                accountsModel.installAgent(agent, withNode, r => {
                    if (r.ev !== "error")
                        return;
                    accPage.put("installPending", agent, undefined);
                    accPage.put("installRefusals", agent, r.message ?? "");
                });
            }
            function installFacts(agent, step) {
                const i = accountsModel.install?.agent === agent ? accountsModel.install : null;
                if (step === "installing")
                    return i?.step === "running" ? (i.line ?? "") : "Starting the install…";
                const why = accPage.installRefusals[agent] ?? (i?.step === "failed" ? (i.line ?? "") : null);
                const failed = why !== null ? "The install didn't finish" + (why ? `: ${why}` : "") : "";
                if (step === "needsNode")
                    return failed || `${accPage.name(agent)} needs one more install first. Installing both asks for your password.`;
                return failed;
            }

            // ── keys
            // no row for a provider without a key (four "Not set" rows led the list): it is in Add a key,
            // and a link to one (an account's Add key) puts its row here (extraProviders)
            readonly property var fixedProviders: []
            property var extraProviders: []
            // "k:<key>" for each key, "p:<provider>" for a provider with none
            readonly property var keyRowsNow: {
                const out = [];
                const provs = accPage.fixedProviders.concat(accPage.keys.map(k => k.provider), accPage.extraProviders)
                    .filter((p, i, all) => all.indexOf(p) === i);
                for (const p of provs) {
                    const ks = accPage.keys.filter(k => k.provider === p);
                    if (ks.length > 0)
                        ks.forEach(k => out.push(`k:${k.id}`));
                    else
                        out.push(`p:${p}`);
                }
                return out;
            }
            property var keyRows: []
            onKeyRowsNowChanged: accPage.keep(accPage, "keyRows", accPage.keyRowsNow)
            readonly property var keyProviders: accPage.keyRowsNow.map(r => r.startsWith("p:") ? r.slice(2)
                : (accPage.keys.find(k => `k:${k.id}` === r)?.provider ?? ""))
            // by add or replace line: "Checking…", or why nothing was stored
            property var keyNotes: ({})
            // by account id: why the host refused the last change to it, until the next change
            property var accountNotes: ({})
            // The reply of a change to an account or a key: the host's refusal goes on its row, and
            // nothing shows when it went through.
            function noted(id, what) {
                accPage.put("accountNotes", id, undefined);
                return r => { if (r.ev === "error") accPage.put("accountNotes", id, `Couldn't ${what}: ${r.message ?? ""}`); };
            }
            function keyNoted(line) {
                accPage.put("keyNotes", line, undefined);
                return r => { if (r.ev === "error") accPage.put("keyNotes", line, `Not changed: ${r.message ?? ""}`); };
            }
            function keyFacts(k) {
                const by = (k.use ?? []).filter(a => a === "pi" || a === "opencode").map(a => accPage.name(a))
                    .concat(accPage.signsInWith(k.id).map(a => `${a.label} (${accPage.name(a.agent)})`));
                const state = accPage.fromHost && accountsModel.keyring === "locked" ? "the keyring is locked"
                    : ({ ok: "works", refused: "refused", offline: "not checked: offline", unchecked: "not checked yet" })[k.state] ?? "";
                return ["In your keyring", `••••${k.last4}`, by.length ? `used by ${accPage.list(by)}` : "", state].filter(s => s).join(" · ");
            }
            function noKeyFacts(provider) {
                const env = accPage.envOf(provider);
                const who = ["pi", "opencode"].filter(a => env[a]).map(a => accPage.name(a));
                return who.length ? `Not set · works with ${accPage.list(who)}` : "Not set";
            }
            // The secret is only passed on: the line it came from was cleared by its caller, and the
            // reply's callback is made where it cannot see it.
            function saveKey(line, provider, old, secret) {
                accPage.put("keyNotes", line, "Checking…");
                const forAccount = line === accPage.open ? accPage.keyFor : "";
                accountsModel.setKey(provider, "", secret, accPage.keySaved(line, provider, old, forAccount));
            }
            function keySaved(line, provider, old, forAccount) {
                return r => {
                    if (r.ev === "key" && r.state !== "refused" && r.id) {
                        if (old)
                            accPage.moveKey(old, r.id);
                        if (forAccount)
                            accountsModel.send({ op: "account_set", account: forAccount, use: "key", key: r.id });
                        accPage.put("keyNotes", line, undefined);
                        if (accPage.open === line)
                            accPage.open = "";
                        return;
                    }
                    accPage.put("keyNotes", line, r.ev === "key" ? `${accPage.providerName(provider)} refused this key` : `Not saved: ${r.message ?? ""}`);
                };
            }
            // a replaced key's accounts and agents move to the new one before it goes
            function moveKey(old, id) {
                for (const a of accPage.accounts.filter(x => x.key === old.id))
                    accountsModel.send({ op: "account_set", account: a.id, key: id });
                for (const agent of old.use ?? [])
                    accountsModel.useKey(id, agent, true);
                accountsModel.removeKey(old.id, true);
            }
            function checkKey(k, line) {
                accPage.put("keyNotes", line, "Checking…");
                accountsModel.checkKey(k.id, r => accPage.put("keyNotes", line, r.ev === "error" ? `Not checked: ${r.message ?? ""}` : undefined));
            }
            // by key: the accounts the host named when it refused to remove it
            property var keyUsers: ({})
            // the accounts that use a key now; one back on its plan may still name it
            function signsInWith(id) { return accPage.accounts.filter(a => a.use === "key" && a.key === id); }
            // A key an account signs in with is removed only after its confirm line, and so is one the
            // host refuses to remove because an account still names it. The confirm's Remove forces.
            function removeKey(k, sure) {
                if (!sure)
                    accPage.put("keyUsers", k.id, undefined);
                if (!sure && accPage.signsInWith(k.id).length > 0) {
                    accPage.open = `removeKey:${k.id}`;
                    return;
                }
                accPage.open = "";
                accountsModel.removeKey(k.id, sure, r => {
                    if (r.ev !== "error")
                        return;
                    if ((r.usedBy ?? []).length > 0) {
                        accPage.put("keyUsers", k.id, r.usedBy);
                        accPage.open = `removeKey:${k.id}`;
                    }
                    else
                        accPage.put("keyNotes", `replace:${k.id}`, `Not removed: ${r.message ?? ""}`);
                });
            }
            // ── deep links: accounts:<agent>, accounts:keys, accounts:keys:<provider>, and
            // accounts:keys:<provider>:<account> for the key that account signs in with
            property string wanted: ""
            function goTo(anchor) {
                root.pageAnchor = "";
                // a link opens the page it lands on: the keys, or an agent's
                const first = String(anchor).split(":")[0];
                if (first === "keys") accPage.viewing = "keys";
                else if (accountsModel.agentOrder.includes(first)) accPage.viewing = first;   // the list may not be read yet
                accPage.wanted = anchor;
                seek.opened = false;
                seek.target = "";
                seek.left = 60;
                seek.restart();
            }
            Connections {
                target: root
                function onAnchorAsked(anchor) { accPage.goTo(anchor); }
            }
            Timer {
                id: seek
                property int left: 0
                property bool opened: false
                property string target: ""     // a key's row, when the anchor names a provider
                interval: 50
                repeat: true
                onTriggered: accPage.arrive()
            }
            function findAnchor(item, name) {
                if (item.objectName === name)
                    return item;
                for (let i = 0; i < item.children.length; i++) {
                    const hit = accPage.findAnchor(item.children[i], name);
                    if (hit)
                        return hit;
                }
                return null;
            }
            // Waits for the host's state (or for it to be down), opens the provider's Add key line
            // (or, for an account with its own key, that key's Replace line), then scrolls once the
            // row is laid out. An Add line opened for an account makes the new key its sign-in.
            function arrive() {
                if (!accPage.heard && !accPage.down && --seek.left > 0)
                    return;
                const parts = accPage.wanted.split(":");
                const provider = parts[0] === "keys" ? (parts[1] ?? "") : "";
                if (provider && !seek.opened) {
                    seek.opened = true;
                    const a = parts.length > 2 ? accPage.account(parts.slice(2).join(":")) : null;
                    const own = a?.use === "key" ? accPage.keys.find(k => k.id === a.key && k.provider === provider) ?? null : null;
                    const theirs = accPage.keys.filter(k => k.provider === provider);
                    const row = own ?? theirs[theirs.length - 1] ?? null;
                    seek.target = row ? `acc-anchor:key:${row.id}` : `acc-anchor:keys:${provider}`;
                    if (accPage.fromHost) {
                        if (!row && !accPage.keyProviders.includes(provider))
                            accPage.extraProviders = [...accPage.extraProviders, provider];
                        accPage.open = own ? `replace:${own.id}` : `key:${provider}`;
                        accPage.keyFor = !own && a ? a.id : "";
                        return;   // the line is laid out by the next tick, and the scroll counts it
                    }
                }
                const it = accPage.findAnchor(accPage, seek.target || `acc-anchor:${accPage.wanted}`);
                if (!it || !it.visible || it.height <= 0) {
                    if (--seek.left <= 0)
                        seek.stop();
                    return;
                }
                seek.stop();
                Qt.callLater(() => accPage.land(it));
            }
            // the focus scroll's rule (onActiveFocusItemChanged), then the arrival wash
            function land(it) {
                const y = it.mapToItem(pageColumn, 0, 0).y + pageColumn.y;
                if (y < pageScroll.contentY + 20)
                    pageScroll.contentY = Math.max(0, y - 40);
                else if (y + it.height > pageScroll.contentY + pageScroll.height - 20)
                    pageScroll.contentY = Math.min(pageScroll.contentHeight - pageScroll.height, y + it.height - pageScroll.height + 40);
                // a group washes its tile (Group.qml: title, tile, note), a row its hover inset
                const tile = it.title !== undefined && it.children.length > 1 ? it.children[1] : null;
                const target = tile ?? it;
                const inset = tile ? 0 : 4;
                const at = target.mapToItem(pageScroll.contentItem, 0, 0);
                wash.x = at.x + inset;
                wash.y = at.y + inset;
                wash.width = target.width - 2 * inset;
                wash.height = target.height - 2 * inset;
                wash.radius = tile ? Appearance.rounding.normal : Appearance.rounding.small;
                washFade.restart();
                if (it.focusAdd)
                    it.focusAdd();
                root.anchorArrived(accPage.wanted);
            }
            Rectangle {
                id: wash
                parent: pageScroll.contentItem
                z: 1
                opacity: 0
                visible: opacity > 0
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                NumberAnimation on opacity {
                    id: washFade
                    running: false
                    from: 1
                    to: 0
                    duration: 1200
                    easing.type: Easing.OutCubic
                }
            }

            Component.onCompleted: {
                accPage.agentList = accPage.agentListNow;
                accPage.keyRows = accPage.keyRowsNow;
                if (root.pageAnchor.length > 0)
                    accPage.goTo(root.pageAnchor);
            }

            Summary {
                visible: accPage.down
                glyph: "key"
                title: "Can't reach the background service"
                subtitle: accPage.accounts.length > 0 ? "The accounts below are as it last saw them" : ""
                live: false
                TextButton {
                    label: "Start it"
                    onPressed: Quickshell.execDetached(["systemctl", "--user", "start", "agent-host.service"])
                }
            }
            Summary {
                visible: !accPage.down && accPage.viewing === "" && (accPage.old
                    || (accPage.fromHost && (accountsModel.keyring === "locked" || !accountsModel.anyReady)))
                glyph: "key"
                title: accPage.old ? "The background service can't manage accounts"
                    : accountsModel.anyReady ? `${accountsModel.readyAgents.length} of ${accPage.shownAgents.length} agents ready`
                    : "No agent is ready yet"
                subtitle: accPage.old ? "Restart the computer to get the newer one"
                    : accountsModel.keyring === "locked" ? accPage.lockedLine
                    : accountsModel.anyReady ? accPage.needsLine
                    : "Install or sign in to one below. Praxis and the notch's Ask use it."
                live: !accPage.old && accountsModel.anyReady
            }

            // ── the overview: one row per agent and one for the keys, each opening its own page
            Group {
                visible: accPage.viewing === ""
                Repeater {
                    model: accPage.agentList
                    SettingRow {
                        id: ov
                        required property string modelData
                        readonly property string agent: ov.modelData
                        readonly property string stateNow: accPage.installStep(ov.agent) || (accPage.defaultOf(ov.agent)?.state ?? "")
                        readonly property bool ready: ov.stateNow === "ready"
                        readonly property string need: {
                            const n = root.agentNeed(ov.agent, ov.stateNow), nm = accPage.name(ov.agent);
                            return n.startsWith(nm + " ") ? n.charAt(nm.length + 1).toUpperCase() + n.slice(nm.length + 2) : n;
                        }
                        label: accPage.name(ov.agent)
                        description: ov.ready ? (accPage.whoOf(ov.agent) || "Ready")
                            : ov.stateNow === "checking" ? "Checking…" : (ov.need || "Not set up")
                        onActivated: accPage.viewing = ov.agent
                        control: Row {
                            spacing: 10
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: ov.ready
                                text: "Ready"
                                font.pixelSize: 15
                                color: Tacit.inkMeta
                            }
                            TextButton {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !ov.ready && ov.stateNow !== "checking"
                                label: "Set up"
                                onPressed: accPage.viewing = ov.agent
                            }
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "chevron_right"
                                iconSize: 18
                                color: Tacit.inkMeta
                            }
                        }
                    }
                }
                SettingRow {
                    label: "Keys"
                    description: accPage.keys.length > 0 ? `${accPage.keys.length} in your keyring · for your agents` : "For your agents"
                    onActivated: accPage.viewing = "keys"
                    control: MaterialSymbol { text: "chevron_right"; iconSize: 18; color: Tacit.inkMeta }
                }
            }
            // back to the four rows
            BackLine {
                visible: accPage.viewing !== ""
                text: "Accounts"
                onClicked: accPage.viewing = ""
            }

            Repeater {
                model: accPage.agentList
                Group {
                    id: ag
                    required property string modelData
                    readonly property string agent: ag.modelData
                    readonly property var info: accountsModel.agents[ag.agent] ?? null
                    readonly property string step: accPage.installStep(ag.agent)
                    // pi and opencode list what they sign in to, one row per provider
                    readonly property bool providerAgent: ag.agent === "pi" || ag.agent === "opencode"
                    readonly property bool byProvider: ag.providerAgent && accPage.fromHost
                    readonly property var idsNow: ag.byProvider ? accPage.providerRows(ag.agent) : accPage.accountsOf(ag.agent).map(a => a.id)
                    property var ids: []
                    onIdsNowChanged: accPage.keep(ag, "ids", ag.idsNow)
                    Component.onCompleted: ag.ids = ag.idsNow
                    objectName: `acc-anchor:${ag.agent}`
                    title: accPage.name(ag.agent)
                    visible: accPage.viewing === ag.agent
                    // the agent's state on its heading's line: Ready, or what it needs in sand; its version
                    // on hover (as a line under the list it read as an account)
                    readonly property string stateNow: ag.step || (accPage.defaultOf(ag.agent)?.state ?? "")
                    readonly property string need: {
                        const n = root.agentNeed(ag.agent, ag.stateNow), nm = accPage.name(ag.agent);
                        return n.startsWith(nm + " ") ? n.charAt(nm.length + 1).toUpperCase() + n.slice(nm.length + 2) : n;
                    }
                    aside: ag.stateNow === "ready" ? "Ready" : ag.stateNow === "checking" ? "Checking…" : ag.need
                    asideAttention: ag.stateNow !== "ready" && ag.stateNow !== "checking" && ag.need.length > 0
                    asideTip: ag.info?.installed && ag.info.version ? `Version ${ag.info.version}` : ""

                    property string pasteProvider: ""
                    // Add another account: the way it signs in, its key, then its name
                    property string addUse: "plan"
                    property string addKey: ""
                    property string addError: ""
                    readonly property string addProvider: ag.agent === "claude" ? "anthropic" : "openai"
                    readonly property var addKeys: accPage.keys.filter(k => k.provider === ag.addProvider)
                    function add() {
                        const label = nameField.text.trim();
                        if (!label.length) {
                            nameField.focusInput();
                            return;
                        }
                        if (ag.addUse === "key" && !ag.addKey) {
                            ag.addError = "Choose the key it signs in with";
                            return;
                        }
                        const use = ag.addUse;
                        ag.addError = "";
                        accountsModel.addAccount(ag.agent, label, use, use === "key" ? ag.addKey : "", r => {
                            if (r.ev !== "account") {
                                ag.addError = `Not added: ${r.message ?? ""}`;
                                return;
                            }
                            accPage.open = "";
                            if (use !== "key")
                                accPage.signIn(r.id, use === "console" ? "console" : "browser", "");
                        });
                    }

                    SettingRow {
                        visible: ag.step.length > 0
                        clickable: false
                        label: ag.step === "installing" ? `Installing ${accPage.name(ag.agent)}…`
                            : ag.step === "needsNode" ? "Needs one more install" : "Not installed"
                        description: accPage.installFacts(ag.agent, ag.step)
                        control: TextButton {
                            label: ag.step === "installing" ? "Cancel" : ag.step === "needsNode" ? "Install both" : "Install"
                            onPressed: {
                                if (ag.step !== "installing") {
                                    accPage.install(ag.agent, ag.step === "needsNode");
                                    return;
                                }
                                accPage.put("installPending", ag.agent, undefined);
                                accountsModel.cancelInstall(ag.agent);
                            }
                        }
                    }
                    Repeater {
                        model: ag.step || ag.byProvider ? [] : ag.ids
                        AccountBlock { page: accPage }
                    }
                    Repeater {
                        model: ag.step || !ag.byProvider ? [] : ag.ids
                        ProviderBlock { page: accPage }
                    }

                    SettingRow {
                        visible: accPage.fromHost && !ag.step && !ag.providerAgent
                        glyph: "add"
                        label: "Add another account"
                        onActivated: {
                            ag.addUse = "plan";
                            ag.addKey = "";
                            ag.addError = "";
                            accPage.toggle(`add:${ag.agent}`);
                        }
                    }
                    ChoiceRow {
                        visible: accPage.open === `add:${ag.agent}`
                        topRule: true
                        label: "Sign in with"
                        options: ag.agent === "claude"
                            ? [{ value: "plan", label: "Plan" }, { value: "console", label: "Console" }, { value: "key", label: "Key" }]
                            : [{ value: "plan", label: "Plan" }, { value: "key", label: "Key" }]
                        current: ag.addUse
                        onPicked: value => {
                            ag.addUse = value;
                            ag.addKey = value === "key" ? (ag.addKeys[0]?.id ?? "") : "";
                        }
                    }
                    ChoiceRow {
                        visible: accPage.open === `add:${ag.agent}` && ag.addUse === "key" && ag.addKeys.length > 0
                        topRule: true
                        asList: true
                        label: "Key"
                        options: ag.addKeys.map(k => ({ value: k.id, label: `${accPage.providerName(k.provider)} key ••••${k.last4}` }))
                        current: ag.addKey
                        onPicked: value => ag.addKey = value
                    }
                    SettingRow {
                        visible: accPage.open === `add:${ag.agent}` && ag.addUse === "key" && ag.addKeys.length === 0
                        topRule: true
                        clickable: false
                        label: `There is no ${accPage.providerName(ag.addProvider)} key yet`
                        control: TextButton {
                            label: "Add one"
                            onPressed: accPage.goTo(`keys:${ag.addProvider}`)
                        }
                    }
                    SettingRow {
                        visible: accPage.open === `add:${ag.agent}`
                        topRule: true
                        clickable: false
                        label: "Name"
                        description: ag.addError || (ag.agent === "claude"
                            ? "Shares settings, skills and history with Personal. Its MCP servers are its own."
                            : "Shares settings and sessions with Personal.")
                        onVisibleChanged: if (visible) {
                            nameField.text = "";
                            nameField.focusInput();
                        }
                        control: RowLayout {
                            spacing: 6
                            LineField {
                                id: nameField
                                placeholder: "Work"
                                onAccepted: ag.add()
                                onCancelled: accPage.open = ""
                            }
                            TextButton {
                                label: ag.addUse === "key" ? "Add" : "Sign in"
                                onPressed: ag.add()
                            }
                        }
                    }

                    // ── connecting pi or opencode to a service: sign in, a key you already have, or paste one
                    // here (it was one "Choose" list whose key choice sent you off to Keys and back)
                    ChoiceRow {
                        readonly property var choices: accPage.connectOptions(ag.agent)
                        visible: accPage.fromHost && !ag.step && ag.providerAgent && choices.length > 0
                        glyph: "login"
                        asList: true
                        label: "Sign in with a service"
                        description: ["signedOut", "noProvider"].includes(accPage.defaultOf(ag.agent)?.state ?? "")
                            ? `${accPage.name(ag.agent)} needs one before it can start a session` : "Opens your browser"
                        options: choices
                        current: ""
                        onPicked: value => accPage.connect(ag.agent, value)
                    }
                    Repeater {
                        model: !accPage.fromHost || ag.step || !ag.providerAgent ? []
                            : accPage.keys.filter(k => accPage.envOf(k.provider)[ag.agent] && !(k.use ?? []).includes(ag.agent))
                        SettingRow {
                            required property var modelData
                            glyph: "key"
                            clickable: false
                            label: `Your ${accPage.providerName(modelData.provider)} key`
                            description: `In your keyring · ••••${modelData.last4}`
                            control: TextButton { label: "Use"; onPressed: accountsModel.useKey(modelData.id, ag.agent, true, accPage.keyNoted(`paste:${ag.agent}`)) }
                        }
                    }
                    SettingRow {
                        visible: accPage.fromHost && !ag.step && ag.providerAgent
                        glyph: "add"
                        label: "Paste a key"
                        description: accPage.keyNotes[`paste:${ag.agent}`] ?? "From Anthropic, OpenAI, OpenRouter or Google"
                        onActivated: accPage.toggle(`paste:${ag.agent}`)
                    }
                    ChoiceRow {
                        visible: accPage.open === `paste:${ag.agent}`
                        label: "Service"
                        options: (accountsModel.providers ?? []).filter(x => x.env?.[ag.agent]).map(x => ({ value: x.id, label: x.name ?? x.id }))
                        current: ag.pasteProvider || (options[0]?.value ?? "")
                        onPicked: value => ag.pasteProvider = value
                    }
                    SettingRow {
                        visible: accPage.open === `paste:${ag.agent}`
                        clickable: false
                        label: "Key"
                        onVisibleChanged: if (visible) pasteField.focusInput()
                        control: RowLayout {
                            spacing: 6
                            LineField {
                                id: pasteField
                                secret: true
                                placeholder: "Paste it here"
                                onAccepted: connectPasted.picked()
                                onCancelled: accPage.open = ""
                            }
                            Slab { text: "Cancel"; onPicked: accPage.open = "" }
                            Slab {
                                id: connectPasted
                                text: "Connect"
                                key: "↵"
                                tone: "default"
                                onPicked: {
                                    const secret = pasteField.text.trim();
                                    const provider = ag.pasteProvider || ((accountsModel.providers ?? []).find(x => x.env?.[ag.agent])?.id ?? "");
                                    pasteField.text = "";
                                    if (secret && provider) accPage.pasteKey(ag.agent, provider, secret);
                                }
                            }
                        }
                    }
                }
            }

            Group {
                objectName: "acc-anchor:keys"
                visible: accPage.viewing === "keys" && (accPage.fromHost || accPage.keys.length > 0)
                title: "Keys"
                note: "Keys stay in your keyring; an agent can read its key only while it runs."
                Repeater {
                    model: accPage.keyRows
                    KeyBlock { page: accPage }
                }
                ChoiceRow {
                    readonly property var choices: accountsModel.providers.filter(p => !accPage.keyProviders.includes(p.id))
                        .map(p => ({ value: p.id, label: p.name ?? p.id }))
                    visible: accPage.fromHost && choices.length > 0
                    glyph: "add"
                    asList: true
                    label: "Add a key"
                    description: "For your agents"
                    options: choices
                    current: ""
                    onPicked: value => accPage.goTo(`keys:${value}`)
                }
            }
        }
    }

    // ── Accessibility ────────────────────────────────────────────────────────
    Component {
        id: accessPage
        ColumnLayout {
            id: acc
            spacing: 0
            property real textScale: 1
            property int cursorSize: 24
            Process {
                running: true
                command: ["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"]
                stdout: SplitParser { onRead: data => acc.textScale = parseFloat(data) || 1 }
            }
            Process {
                running: true
                command: ["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"]
                stdout: SplitParser { onRead: data => acc.cursorSize = parseInt(data.replace(/^int32 /, "")) || 24 }
            }

            Group {
                title: "Text"
                note: "For apps. The desktop's own text grows with the scale in Display & power."
                ChoiceRow {
                    glyph: "format_size"
                    label: "Text size in apps"
                    options: [{ value: 1, label: "Default" }, { value: 1.25, label: "Larger" }, { value: 1.5, label: "Largest" }]
                    current: [1, 1.25, 1.5].reduce((best, v) => Math.abs(v - acc.textScale) < Math.abs(best - acc.textScale) ? v : best, 1)
                    onPicked: value => {
                        acc.textScale = value;
                        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", String(value)]);
                    }
                }
            }
            Group {
                title: "Motion"
                SwitchRow {
                    glyph: "motion_mode"
                    label: "Reduce motion"
                    description: "Windows and apps stop animating. The desktop's own panels keep their short fades."
                    checked: !Config.options.hyprland.animations.enable
                    onToggled: value => {
                        Config.options.hyprland.animations.enable = !value;
                        HyprlandConfig.set("animations:enabled", value ? 0 : 1);
                        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", value ? "false" : "true"]);
                    }
                }
            }
            Group {
                title: "Pointer"
                // Hyprland takes the size from XCURSOR_SIZE at login and from setcursor while
                // running; apps take it from gsettings. All three are set.
                ChoiceRow {
                    glyph: "arrow_selector_tool"
                    label: "Cursor size"
                    options: [{ value: 24, label: "Default" }, { value: 32, label: "Larger" }, { value: 48, label: "Largest" }]
                    current: acc.cursorSize
                    onPicked: value => {
                        acc.cursorSize = value;
                        const lines = value === 24 ? [] : [`hl.env("XCURSOR_SIZE", "${value}")`, `hl.env("HYPRCURSOR_SIZE", "${value}")`];
                        Quickshell.execDetached(["bash", "-c",
                            'theme=$(gsettings get org.gnome.desktop.interface cursor-theme | tr -d "\x27"); hyprctl setcursor "$theme" "$1" >/dev/null; gsettings set org.gnome.desktop.interface cursor-size "$1"; shift; python3 "$@"',
                            "_", String(value), `${Directories.scriptPath}/settings/managed_block.py`, FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/variables.lua`), "cursor"].concat(lines));
                    }
                }
            }
        }
    }

    // ── Display & power ──────────────────────────────────────────────────────
    Component {
        id: displayPage
        ColumnLayout {
            id: dp
            spacing: 0

            // Brightness and night light are the shell's: the level is left where this page watches
            // it as the keys and the control panel change it, and the night light is asked over
            // IPC, so the slider holds one value with the keys and there is one night-light schedule.
            property real brightness: -1
            property real wantBrightness: -1
            property bool nightOn: false
            // hyprctl monitors: name, description, width, height, refreshRate, x, y, scale, transform
            property var screens: []
            // monitors.lua is also nwg-displays' file: written only when absent or ours
            property bool monitorsFileOurs: false
            property bool monitorsWriteFailed: false

            function setNight(on) {
                dp.nightOn = on;
                Quickshell.execDetached(["qs", "-p", Directories.shellFile, "ipc", "call", "nightLight", "set", on ? "true" : "false"]);
                nightCheck.restart();
            }
            function scaleOptions(m) {
                const fits = [1, 1.25, 1.5, 1.75, 2].filter(s => Number.isInteger(m.width / s) && Number.isInteger(m.height / s));
                const all = fits.includes(m.scale) ? fits : [...fits, m.scale].sort((a, b) => a - b);
                return all.map(s => ({ value: s, label: `${Math.round(s * 100)}%` }));
            }
            // A monitor's line is for the monitor, not the port: "desc:" and what Hyprland calls it (make, model,
            // serial), so one plugged into another dock port keeps its scale and place, and the next one on that port
            // does not take them. Hyprland matches the start of a description: one that is not the only screen it
            // starts (two alike with no serial), or that has none, goes by its connector as before. So does the
            // laptop's own panel, which never changes port, and whose lines general.lua's lid adds to by connector.
            function outputOf(m) {
                const d = m.description ?? "";
                return /^(eDP|LVDS|DSI)-/.test(m.name) || d.length === 0 || /["\\]/.test(d)
                    || dp.screens.filter(o => (o.description ?? "").startsWith(d)).length > 1 ? m.name : `desc:${d}`;
            }
            // Every screen keeps its present mode, position, scale, rotation and mirroring; only what
            // was asked for on the one screen changes.
            function monitorLine(m, o) {
                const mode = o.mode ?? `${m.width}x${m.height}@${m.refreshRate.toFixed(3)}`;
                const position = o.position ?? `${m.x}x${m.y}`;
                const mirrorName = o.mirror !== undefined ? o.mirror : (m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "");
                const source = dp.screens.find(x => x.name === mirrorName);
                const mirror = source ? dp.outputOf(source) : mirrorName;
                return `hl.monitor({ output = "${dp.outputOf(m)}", mode = "${mode}", position = "${position}", scale = ${o.scale ?? m.scale}${m.transform ? `, transform = ${m.transform}` : ""}${mirror ? `, mirror = "${mirror}"` : ""} })`;
            }
            // Positions are in logical pixels, so a new scale or mode on one screen moves the screens
            // that sat beyond its far edge by the change in its logical size.
            function shiftedPosition(m, name, change) {
                const c = dp.screens.find(x => x.name === name);
                if (!c || (change.scale === undefined && change.mode === undefined))
                    return undefined;
                const md = change.mode ? change.mode.match(/^(\d+)x(\d+)@/) : null;
                const sc = change.scale ?? c.scale;
                const dw = Math.round((md ? +md[1] : c.width) / sc) - Math.round(c.width / c.scale);
                const dh = Math.round((md ? +md[2] : c.height) / sc) - Math.round(c.height / c.scale);
                const x = m.x >= c.x + Math.round(c.width / c.scale) ? m.x + dw : m.x;
                const y = m.y >= c.y + Math.round(c.height / c.scale) ? m.y + dh : m.y;
                return `${x}x${y}`;
            }
            // A change picked while the last one is still being written (hyprctl reload can take a second) waits for it
            // and for the screens read after it, and is built on them: running = true on a running Process does
            // nothing, so it was dropped without a word.
            property bool settling: false
            property var waitingChanges: []
            function setMonitor(name, change) {
                if (dp.settling) {
                    dp.waitingChanges = dp.waitingChanges.concat([{ name, change }]);
                    return;
                }
                const lines = ["-- Written by Tacit Settings (Display & power). Delete it to go back to hyprland/general.lua."]
                    .concat(dp.screens.map(m => dp.monitorLine(m, m.name === name ? change : { position: dp.shiftedPosition(m, name, change) })));
                // the file as it is now is put by for the Keep bar, unless an earlier change is still waiting on it
                // the lines of screens that are not plugged in now stay as they were, for when they are back; a line for
                // one that is, by its connector or its description, gives way to the new one (the last line that fits wins)
                const drop = dp.screens.flatMap(m => [m.name, `desc:${m.description ?? ""}`]).join("\n");
                writeMonitors.command = ["bash", "-c", 'mode=$1; drop=$2; shift 2; f="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitors.lua"; ' + root.displayBackupBase
                    + 'if [ "$mode" = fresh ]; then rm -f "$b.previous" "$b.absent"; if [ -e "$f" ]; then cp -f "$f" "$b.previous"; else : > "$b.absent"; fi; fi; '
                    + 'new=$(printf "%s\\n" "$@"); keep=$(grep -sE "^hl\\.monitor\\(" "$f" | while IFS= read -r l; do o=${l#*output = \\"}; o=${o%%\\"*}; printf "%s\\n" "$drop" | grep -qxF -- "$o" || printf "%s\\n" "$l"; done); { printf "%s\\n" "$new"; [ -z "$keep" ] || printf "%s\\n" "$keep"; } > "$f" && hyprctl reload >/dev/null', "_", root.displayKeepLeft > 0 ? "again" : "fresh", drop].concat(lines);
                dp.settling = true;
                writeMonitors.running = true;
            }

            Component.onCompleted: {
                readBrightness.running = true;
                readNight.running = true;
                readScreens.running = true;
                readMonitorsFile.running = true;
            }
            // Brightness keys and the night light are the shell's; read again when the window comes forward.
            Connections {
                target: root
                function onActiveChanged() {
                    if (!root.active)
                        return;
                    if (!brightnessSlider.pressed && !brightnessWrite.running)
                        readBrightness.running = true;
                    readNight.running = true;
                    if (!writeMonitors.running)
                        readScreens.running = true;
                }
            }
            // a screen plugged in or out while the page is open (Hyprland says so; no polling), and a reload, which is
            // how Go back and the Keep bar running out put the old file back (Hyprland applies the monitor lines
            // before it says configreloaded), so the next change is not built on the screens as refused; not while a
            // write is landing
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (["monitoradded", "monitorremoved", "configreloaded"].includes(event.name) && !writeMonitors.running) {
                        readScreens.running = true;
                        readMonitorsFile.running = true;
                    }
                }
            }
            Timer {
                id: brightnessWrite
                interval: 120
                onTriggered: Quickshell.execDetached(["qs", "-p", Directories.shellFile, "ipc", "call", "brightness", "set", String(dp.wantBrightness)])
            }
            Timer {
                id: nightCheck
                interval: 1500
                onTriggered: readNight.running = true
            }
            // The shell's level as it changes - a brightness key, the control panel, this slider once
            // the write landed - so the knob follows while the page is open and does not fall back to
            // the level read before a drag.
            FileView {
                id: brightnessLevelFile
                path: Directories.brightnessLevelPath
                blockLoading: true
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    const v = parseFloat(text());
                    if (!isNaN(v))
                        dp.brightness = v;
                }
            }
            Process {
                id: readBrightness
                command: ["qs", "-p", Directories.shellFile, "ipc", "call", "brightness", "get"]
                stdout: SplitParser {
                    onRead: data => {
                        const v = parseFloat(data);
                        if (!isNaN(v))
                            dp.brightness = v;
                    }
                }
            }
            Process {
                id: readNight
                command: ["qs", "-p", Directories.shellFile, "ipc", "call", "nightLight", "active"]
                stdout: SplitParser { onRead: data => dp.nightOn = data.trim() === "true" }
            }
            Process {
                id: readScreens
                command: ["hyprctl", "monitors", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            // mirrorOf names the source by its id in Hyprland's JSON; the rest of the page
                            // and monitors.lua go by name
                            const list = JSON.parse(text);
                            const nameOf = id => list.find(o => String(o.id) === String(id))?.name ?? id;
                            const next = list.map(m => ({ name: m.name, description: m.description, width: m.width, height: m.height, refreshRate: m.refreshRate, x: m.x, y: m.y, scale: m.scale, transform: m.transform ?? 0, modes: m.availableModes ?? [], mirrorOf: nameOf(m.mirrorOf ?? "none") }));
                            // the rows are rebuilt when the list is replaced, so only a change replaces it
                            if (JSON.stringify(next) !== JSON.stringify(dp.screens))
                                dp.screens = next;
                        } catch (e) {}
                        // the read after a write: the next change that waited for it
                        if (dp.settling && !writeMonitors.running) {
                            dp.settling = false;
                            const waited = dp.waitingChanges[0];
                            dp.waitingChanges = dp.waitingChanges.slice(1);
                            if (waited)
                                dp.setMonitor(waited.name, waited.change);
                        }
                    }
                }
            }
            Process {
                id: readMonitorsFile
                command: ["bash", "-c", 'f="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitors.lua"; [ -s "$f" ] && head -1 "$f" || echo absent']
                stdout: SplitParser { onRead: data => dp.monitorsFileOurs = data === "absent" || data.startsWith("-- Written by Tacit Settings") }
            }
            Process {
                id: writeMonitors
                onExited: exitCode => {
                    dp.monitorsWriteFailed = exitCode !== 0;
                    if (exitCode === 0)
                        root.displayKeepLeft = 15;
                    readScreens.running = true;
                    readMonitorsFile.running = true;
                }
            }

            Summary {
                visible: root.hasBattery
                readonly property var b: root.batteryDevice
                readonly property int pct: Math.round((b?.percentage ?? 0) * 100)
                // plugged in while the pack drains (a capped charger) is not charging, as the notch says
                readonly property bool charging: b?.state === UPowerDeviceState.Charging && !Battery.drainingOnAc
                glyph: charging ? "battery_charging_full" : pct >= 95 ? "battery_full" : `battery_${Math.min(6, Math.floor(pct / 15))}_bar`
                eyebrow: "Battery"
                title: `${pct}%`
                // The times are Battery's, from the pack's own energy over the last minutes, as the notch shows
                // them: UPower's swung between 3, 4 and 9 h. One shows once there are four minutes of it. A trickle
                // charge gives a day or more; past 12 h it is "slowly".
                subtitle: [Battery.drainingOnAc ? "Plugged in, not charging"
                        : charging ? (Battery.timeToFull > 43200 ? "Charging slowly"
                            : Battery.timeToFull > 0 ? `Charging · full in ${root.batteryTime(Battery.timeToFull)}` : "Charging")
                        : !UPower.onBattery ? "Plugged in"
                        : (Battery.timeToEmpty > 0 ? `${root.batteryTime(Battery.timeToEmpty)} left` : "On battery"),
                    (b?.healthSupported ?? false) ? `health ${Math.round(b.healthPercentage)}%` : ""].filter(x => x.length > 0).join(" · ")
                live: charging
            }

            // the power mode for the charger and for the battery, as Windows has it (services/PowerMode.qml); the one in
            // use now says so. It asked power-profiles-daemon before, which Tacit does not install: it did nothing.
            Group {
                title: root.hasBattery ? "Power and battery" : "Power"
                visible: root.hasBattery || PowerMode.available
                ChoiceRow {
                    visible: PowerMode.available
                    glyph: "power"
                    label: root.hasBattery ? "On the charger" : "Power mode"
                    description: PowerMode.refused ? "Only an administrator can change this" : (root.hasBattery && PowerMode.charging ? "In use now. " : "") + PowerMode.say(PowerMode.onCharger)
                    options: PowerMode.modes
                    current: PowerMode.onCharger
                    onPicked: value => PowerMode.set("charger", value)
                }
                ChoiceRow {
                    visible: PowerMode.available && root.hasBattery
                    glyph: "battery_full"
                    label: "On battery"
                    description: PowerMode.refused ? "Only an administrator can change this" : (!PowerMode.charging ? "In use now. " : "") + PowerMode.say(PowerMode.onBattery)
                    options: PowerMode.modes
                    current: PowerMode.onBattery
                    onPicked: value => PowerMode.set("battery", value)
                }
                SwitchRow {
                    visible: root.hasBattery
                    glyph: "bedtime"
                    label: "Sleep before the battery runs out"
                    checked: Config.options.battery.automaticSuspend
                    onToggled: value => Config.options.battery.automaticSuspend = value
                }
            }
            Group {
                title: "Screen"
                note: dp.monitorsWriteFailed ? "The screen settings could not be saved."
                    : dp.screens.length === 0 && dp.brightness < 0 ? "Tacit could not read your screens. Reopen Settings to try again." : ""
                SettingRow {
                    visible: dp.brightness >= 0
                    clickable: false
                    glyph: "brightness_6"
                    label: "Brightness"
                    stacked: true
                    control: Ruler {
                        fill: true
                        id: brightnessSlider
                        implicitWidth: 260
                        label: `${Math.round(brightnessSlider.value * 100)}%`
                        from: 0.01
                        to: 1
                        onMoved: {
                            dp.wantBrightness = brightnessSlider.value;
                            // The shell's level comes back in a moment through the file above; until
                            // then the knob stays where it was dragged instead of jumping back to the
                            // value read before it.
                            dp.brightness = brightnessSlider.value;
                            if (!brightnessWrite.running)
                                brightnessWrite.start();
                        }
                        Binding on value {
                            value: dp.brightness
                            when: !brightnessSlider.pressed
                        }
                    }
                }
                Repeater {
                    model: dp.screens
                    ChoiceRow {
                        required property var modelData
                        enabled: dp.monitorsFileOurs
                        glyph: "fit_screen"
                        label: dp.screens.length > 1 ? (modelData.description || modelData.name) : "Scale"
                        description: dp.monitorsFileOurs
                            ? `Looks like ${Math.round(modelData.width / modelData.scale)} × ${Math.round(modelData.height / modelData.scale)}`
                            : "Set in ~/.config/hypr/monitors.lua, which another tool wrote"
                        options: dp.scaleOptions(modelData)
                        current: modelData.scale
                        onPicked: value => dp.setMonitor(modelData.name, { scale: value })
                    }
                }
                Repeater {
                    model: dp.screens
                    ChoiceRow {
                        required property var modelData
                        visible: modelData.modes.length > 1
                        enabled: dp.monitorsFileOurs
                        glyph: "aspect_ratio"
                        label: dp.screens.length > 1 ? `${modelData.description || modelData.name}: resolution` : "Resolution"
                        description: dp.monitorsFileOurs ? "" : "Set in ~/.config/hypr/monitors.lua, which another tool wrote"
                        // "1920x1080@60.00Hz" as Hyprland lists it; the rate in whole hertz, unless another rate of the
                        // same size rounds the same (60.00 and 59.94 Hz both read "60 Hz"): those get the decimals that
                        // tell them apart, "60 Hz" and "59.9 Hz"
                        options: {
                            const all = modelData.modes.filter((md, i, a) => a.indexOf(md) === i).map(md => ({ md, m: md.match(/^(\d+)x(\d+)@([\d.]+)Hz$/) }));
                            return all.map(({ md, m }) => {
                                if (!m)
                                    return { value: md, label: md };
                                const twins = all.filter(o => o.m && o.m[1] === m[1] && o.m[2] === m[2] && Math.round(+o.m[3]) === Math.round(+m[3]));
                                const d = [0, 1, 2, 3].find(d => new Set(twins.map(o => (+o.m[3]).toFixed(d))).size === twins.length) ?? 3;
                                return { value: `${m[1]}x${m[2]}@${m[3]}`, label: `${m[1]} × ${m[2]} · ${+(+m[3]).toFixed(d)} Hz` };
                            });
                        }
                        current: `${modelData.width}x${modelData.height}@${modelData.refreshRate.toFixed(2)}`
                        onPicked: value => dp.setMonitor(modelData.name, { mode: value })
                    }
                }
                // Where each other screen sits against the first one, or mirrors it.
                Repeater {
                    model: dp.screens.slice(1)
                    ChoiceRow {
                        id: place
                        required property var modelData
                        readonly property var main: dp.screens[0]
                        readonly property int mainW: Math.round(place.main.width / place.main.scale)
                        readonly property int mainH: Math.round(place.main.height / place.main.scale)
                        readonly property int w: Math.round(place.modelData.width / place.modelData.scale)
                        readonly property int h: Math.round(place.modelData.height / place.modelData.scale)
                        enabled: dp.monitorsFileOurs
                        glyph: "splitscreen_right"
                        label: `${place.modelData.description || place.modelData.name}: position`
                        description: dp.monitorsFileOurs ? "" : "Set in ~/.config/hypr/monitors.lua, which another tool wrote"
                        options: [
                            { value: "right", label: `Right of ${place.main.name}` }, { value: "left", label: `Left of ${place.main.name}` },
                            { value: "above", label: `Above ${place.main.name}` }, { value: "below", label: `Below ${place.main.name}` },
                            { value: "mirror", label: `Mirror ${place.main.name}` }
                        ]
                        current: place.modelData.mirrorOf === place.main.name ? "mirror"
                            : place.modelData.x >= place.main.x + place.mainW ? "right"
                            : place.modelData.x + place.w <= place.main.x ? "left"
                            : place.modelData.y + place.h <= place.main.y ? "above" : "below"
                        onPicked: value => {
                            const p = place.main;
                            const at = value === "right" ? `${p.x + place.mainW}x${p.y}`
                                : value === "left" ? `${p.x - place.w}x${p.y}`
                                : value === "above" ? `${p.x}x${p.y - place.h}`
                                : value === "below" ? `${p.x}x${p.y + place.mainH}` : "auto";
                            dp.setMonitor(place.modelData.name, { position: at, mirror: value === "mirror" ? p.name : "" });
                        }
                    }
                }
            }

            Group {
                title: "Night light"
                // one choice where two switches overrode each other (on now, and on by the clock)
                ChoiceRow {
                    glyph: "nightlight"
                    label: "Night light"
                    description: Config.options.light.night.automatic
                        ? (dp.nightOn ? `On now, until ${Config.options.light.night.to}` : `Comes on at ${Config.options.light.night.from}`)
                        : "Warmer colours, easier on the eyes in the evening"
                    options: [{ value: "off", label: "Off" }, { value: "on", label: "On" }, { value: "auto", label: "By time of day" }]
                    current: Config.options.light.night.automatic ? "auto" : (dp.nightOn ? "on" : "off")
                    onPicked: value => {
                        Config.options.light.night.automatic = value === "auto";
                        if (value !== "auto") dp.setNight(value === "on");
                    }
                }
                FieldRow {
                    // set when what was typed is not a time, so the field's snap back has a reason
                    property bool badTime: false
                    visible: Config.options.light.night.automatic
                    label: "From"
                    description: badTime ? "Use 24-hour time, like 19:30" : ""
                    fieldWidth: 80
                    text: Config.options.light.night.from
                    onCommitted: value => { const t = root.clockTime(value); badTime = !t; if (t) Config.options.light.night.from = t; revert(); }
                }
                FieldRow {
                    // set when what was typed is not a time, so the field's snap back has a reason
                    property bool badTime: false
                    visible: Config.options.light.night.automatic
                    label: "Until"
                    description: badTime ? "Use 24-hour time, like 19:30" : ""
                    fieldWidth: 80
                    text: Config.options.light.night.to
                    onCommitted: value => { const t = root.clockTime(value); badTime = !t; if (t) Config.options.light.night.to = t; revert(); }
                }
                SettingRow {
                    clickable: false
                    glyph: "thermostat"
                    label: "Warmth"
                    description: `${Math.round(Config.options.light.night.colorTemperature / 100) * 100} K`
                    // left is cooler, right is warmer: 6500 K is daylight, 1200 K candlelight
                    stacked: true
                    control: Ruler {
                        fill: true
                        id: warmthSlider
                        implicitWidth: 260
                        label: warmthSlider.value < 0.34 ? "Mild" : warmthSlider.value < 0.67 ? "Warm" : "Very warm"
                        from: 0
                        to: 1
                        onMoved: Config.options.light.night.colorTemperature = Math.round((6500 - warmthSlider.value * 5300) / 100) * 100
                        Binding on value {
                            value: (6500 - Config.options.light.night.colorTemperature) / 5300
                            when: !warmthSlider.pressed
                        }
                    }
                }
            }

            Advanced {
                StepperRow {
                    visible: root.hasBattery
                    label: "Warn when the battery falls to"
                    value: Config.options.battery.low
                    from: 5
                    to: 50
                    stepSize: 5
                    suffix: "%"
                    // the later steps never sit above the earlier ones: low >= critical >= suspend
                    onMoved: value => {
                        Config.options.battery.low = value;
                        if (Config.options.battery.critical > value)
                            Config.options.battery.critical = value;
                        if (Config.options.battery.suspend > Config.options.battery.critical)
                            Config.options.battery.suspend = Config.options.battery.critical;
                    }
                }
                StepperRow {
                    visible: root.hasBattery
                    label: "Warn again when it falls to"
                    value: Config.options.battery.critical
                    from: 1
                    to: Math.min(30, Config.options.battery.low)
                    suffix: "%"
                    onMoved: value => {
                        Config.options.battery.critical = value;
                        if (Config.options.battery.suspend > value)
                            Config.options.battery.suspend = value;
                    }
                }
                StepperRow {
                    visible: root.hasBattery && Config.options.battery.automaticSuspend
                    label: "Sleep when it falls to"
                    value: Config.options.battery.suspend
                    from: 1
                    to: Math.min(20, Config.options.battery.critical)
                    suffix: "%"
                    onMoved: value => Config.options.battery.suspend = value
                }
            }
        }
    }

    // ── Lock & sleep ─────────────────────────────────────────────────────────
    Component {
        id: lockPage
        ColumnLayout {
            spacing: 0
            Group {
                title: "The lock screen"
                // Hidden (sweep D9): Tacit's lock draws a fixed ground and clock (LockSurface.qml),
                // so these three end-4 options change nothing on it. Code and settings stay.
                SwitchRow {
                    visible: false
                    label: "Blur the wallpaper behind it"
                    checked: Config.options.lock.blur.enable
                    onToggled: value => Config.options.lock.blur.enable = value
                }
                SwitchRow {
                    visible: false
                    label: "Clock in the middle"
                    checked: Config.options.lock.centerClock
                    onToggled: value => Config.options.lock.centerClock = value
                }
                SwitchRow {
                    visible: false
                    label: "Show widgets"
                    checked: Config.options.lock.showWidgets
                    onToggled: value => Config.options.lock.showWidgets = value
                }
                SwitchRow {
                    label: "Varied shapes for the password dots"
                    checked: Config.options.lock.materialShapeChars
                    onToggled: value => Config.options.lock.materialShapeChars = value
                }
                SwitchRow {
                    label: "Music controls"
                    checked: Config.options.lock.showMedia
                    onToggled: value => Config.options.lock.showMedia = value
                }
            }
            Group {
                title: "Security"
                // Hidden: the lock is always Tacit's (held off, panelFamilies/IllogicalImpulseFamily.qml).
                // hypridle.conf and keybinds.lua read this too: with it on, hyprlock took the screen everywhere.
                SwitchRow {
                    visible: false
                    glyph: "shield_lock"
                    label: "Use the stricter lock screen"
                    description: "Stays locked even if the desktop stops working; it looks plainer"
                    checked: Config.options.lock.useHyprlock
                    onToggled: value => Config.options.lock.useHyprlock = value
                }
                SwitchRow {
                    glyph: "power_settings_new"
                    label: "Ask for the password to shut down or restart"
                    checked: Config.options.lock.security.requirePasswordToPower
                    onToggled: value => Config.options.lock.security.requirePasswordToPower = value
                }
            }
            Group {
                title: "When you step away"
                note: Object.keys(root.idleTimes).length > 0 ? "" : "No time is set for locking or sleeping, so nothing happens when you step away."
                ChoiceRow {
                    visible: root.idleTimes.lock !== undefined
                    glyph: "lock_clock"
                    label: "Lock the screen after"
                    options: root.idleOptions("lock", [60, 120, 180, 300, 600, 900, 1800, 3600])
                    current: root.idleTimes.lock ?? 0
                    onPicked: value => root.setIdleTime("lock", value)
                }
                ChoiceRow {
                    visible: root.idleTimes.screen !== undefined
                    glyph: "monitor"
                    label: "Turn the screen off after"
                    options: root.idleOptions("screen", [60, 120, 180, 300, 600, 900, 1800, 3600])
                    current: root.idleTimes.screen ?? 0
                    onPicked: value => root.setIdleTime("screen", value)
                }
                ChoiceRow {
                    visible: root.idleTimes.sleep !== undefined
                    glyph: "bedtime"
                    label: "Sleep after"
                    options: root.idleOptions("sleep", [300, 600, 900, 1800, 3600, 7200])
                    current: root.idleTimes.sleep ?? 0
                    onPicked: value => root.setIdleTime("sleep", value)
                }
            }
        }
    }

    // ── Keyboard & touchpad ──────────────────────────────────────────────────
    // Each change is written twice: to the shell's config, which remembers it, and through
    // HyprlandConfig to the compositor, which applies it now - the same pair the old page wrote.
    Component {
        id: inputPage
        ColumnLayout {
            id: inputCol
            spacing: 0
            // "shortcuts" opens the Shortcuts page in place of the groups, as the Notch page opens its sections
            property string viewing: ""
            // The pointer runs on a custom curve (slow moves under 1:1, swipes faster), and libinput ignores the speed
            // setting under a custom curve, so a speed scales the curve itself: -1 halves it, +1 doubles it.
            function curve(speed) {
                const points = [];
                for (let i = 0; i <= 12; i++) {
                    const v = i * 0.5;
                    points.push(Number((v * (0.6 + 1.6 * Math.pow(v / 6, 1.2)) * Math.pow(2, speed)).toFixed(3)));
                }
                return `custom 0.5 ${points.join(" ")}`;
            }
            // a speed said as a word, by how it compares with the usual one (1)
            function speedWord(ratio) {
                return ratio < 0.6 ? "Slowest" : ratio < 0.9 ? "Slower" : ratio <= 1.12 ? "Normal" : ratio <= 1.6 ? "Faster" : "Fastest";
            }
            // Hyprland gives a speed to every pointer, or to one device by its name, not to touchpads as such: the
            // touchpads are the devices named so ("...-touchpad", Apple's "...-trackpad"). Every pointer is written
            // here as its own, mouse and touchpad alike, per Hyprland 0.57, which refuses a curve on
            // input:accel_profile but takes one per device - and so a mouse plugged in later has its class's
            // Settings (the hotplug layer in tacit/general.lua reads the resolutions the configurator keeps).
            property var pointers: []
            readonly property var touchpads: pointers.filter(p => p.touch).map(p => p.name)
            // the device list has been read once; until then the Touchpad group shows as it always did
            property bool devicesKnown: false
            // the layout the keyboard is running now: Setup's, from /etc/vconsole.conf, is not in the config
            property string liveLayout: ""
            // resampled while the page is open: a mouse plugged in after it is one of the
            // pointers, not the ones a setting already named
            Process {
                id: devicesProcess
                running: true
                command: ["hyprctl", "devices", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const devices = JSON.parse(text);
                            const pointers = devices.mice.map(m => ({ name: m.name, touch: /touchpad|trackpad/i.test(m.name) }));
                            // a replaced list is a changed one: only a real change reaches the rows
                            if (JSON.stringify(pointers) !== JSON.stringify(inputCol.pointers))
                                inputCol.pointers = pointers;
                            // the first read only: later the choice made here is ahead of what Hyprland reports
                            if (!inputCol.devicesKnown)
                                inputCol.liveLayout = (devices.keyboards.find(k => k.main) ?? devices.keyboards[0])?.layout ?? "";
                            inputCol.devicesKnown = true;
                        } catch (e) {}
                    }
                }
            }
            Timer {
                interval: 5000
                running: true
                repeat: true
                onTriggered: {
                    devicesProcess.running = false;
                    devicesProcess.running = true;
                }
            }
            function writeSpeeds() {
                const input = Config.options.hyprland.input;
                // input:sensitivity is the mouse's own; the compositor refuses a curve on the global
                // input:accel_profile (0.57), so every pointer is said as its device instead - the reset
                // takes the one the old generator left in a main.lua the GUI already owns the feel through
                const entries = {
                    "input:sensitivity": input.sensitivity,
                    "input:accel_profile": "[[EMPTY]]"
                };
                for (const pointer of inputCol.pointers) {
                    const profile = pointer.touch ? input.touchpad.profile : input.mouseProfile;
                    const speed = pointer.touch ? input.touchpad.speed : input.sensitivity;
                    entries[`device:${pointer.name}:accel_profile`] = profile === "tacit" ? inputCol.curve(speed) : profile;
                    // the curve carries the speed itself; flat and adaptive read the device's sensitivity, and a
                    // curve can take an old one back
                    entries[`device:${pointer.name}:sensitivity`] = profile === "tacit" ? "[[EMPTY]]" : speed;
                }
                HyprlandConfig.setMany(entries);
            }
            Group {
                visible: inputCol.viewing === ""
                title: "Keyboard"
                ChoiceRow {
                    id: layoutRow
                    glyph: "keyboard"
                    label: "Layout"
                    readonly property var codes: (inputCol.liveLayout || Config.options.hyprland.input.kbLayout || HyprlandXkb.layoutCodes.join(",") || "us").split(",")
                    options: root.xkbLayouts
                    current: root.typedLayout(layoutRow.codes)
                    // with several layouts this replaces the one typed in and keeps the ones after it (root.pickLayout)
                    onPicked: value => {
                        const v = root.pickLayout(layoutRow.codes, value);
                        Config.options.hyprland.input.kbLayout = v.layout;
                        inputCol.liveLayout = v.layout;
                        HyprlandConfig.setMany(v.options ? { "input:kb_layout": v.layout, "input:kb_options": v.options } : { "input:kb_layout": v.layout });
                    }
                }
                SwitchRow {
                    label: "Num Lock on at start"
                    checked: Config.options.hyprland.input.numlock
                    onToggled: value => {
                        Config.options.hyprland.input.numlock = value;
                        HyprlandConfig.set("input:numlock_by_default", value ? 1 : 0);
                    }
                }
                // delay and rate together; Normally is Tacit's own 250 ms / 35 a second
                ChoiceRow {
                    readonly property var speeds: [
                        { value: "slow", label: "Slowly", delay: 500, rate: 20 },
                        { value: "normal", label: "Normally", delay: 250, rate: 35 },
                        { value: "quick", label: "Quickly", delay: 180, rate: 50 }
                    ]
                    readonly property string now: (speeds.find(o => o.delay === Config.options.hyprland.input.repeatDelay
                        && o.rate === Config.options.hyprland.input.repeatRate) ?? { value: "own" }).value
                    label: "Held keys repeat"
                    options: speeds.concat(now === "own" ? [{ value: "own", label: "Your own" }] : [])
                    current: now
                    onPicked: value => {
                        const o = speeds.find(x => x.value === value);
                        if (!o) return;
                        Config.options.hyprland.input.repeatDelay = o.delay;
                        Config.options.hyprland.input.repeatRate = o.rate;
                        HyprlandConfig.setMany({ "input:repeat_delay": o.delay, "input:repeat_rate": o.rate });
                    }
                }
                OpenRow {
                    glyph: "keyboard"
                    label: "Shortcuts"
                    value: Object.keys(Shortcuts.changed).length + Shortcuts.apps.length > 0 ? "Some are yours" : ""
                    description: "What each key combination does, and your own"
                    onActivated: inputCol.viewing = "shortcuts"
                }
            }
            Group {
                // none on a desktop with a mouse. The name is how a touchpad is told (touchpad, trackpad), and some
                // are named otherwise, so a laptop keeps the group whatever the names say.
                visible: inputCol.viewing === "" && (!inputCol.devicesKnown || inputCol.touchpads.length > 0 || root.hasBattery)
                title: "Touchpad"
                // the profile: Tacit's curve (slow moves land precisely, quick moves travel far), flat sends
                // each movement 1:1, adaptive is libinput's usual acceleration
                ChoiceRow {
                    label: "Acceleration"
                    options: [
                        { value: "tacit", label: "Tacit curve" },
                        { value: "flat", label: "Flat" },
                        { value: "adaptive", label: "Adaptive" }
                    ]
                    current: Config.options.hyprland.input.touchpad.profile
                    onPicked: value => {
                        Config.options.hyprland.input.touchpad.profile = value;
                        inputCol.writeSpeeds();
                    }
                }
                SettingRow {
                    visible: inputCol.touchpads.length > 0
                    clickable: false
                    label: "Speed"
                    // written once settled (released, or the keys at rest): every write reloads Hyprland
                    stacked: true
                    control: Ruler {
                        fill: true
                        id: touchpadSpeedSlider
                        implicitWidth: 260
                        label: inputCol.speedWord(Math.pow(2, touchpadSpeedSlider.value))
                        from: -1
                        to: 1
                        onSettled: {
                            Config.options.hyprland.input.touchpad.speed = Math.round(touchpadSpeedSlider.value * 20) / 20;
                            inputCol.writeSpeeds();
                        }
                        Binding on value {
                            value: Config.options.hyprland.input.touchpad.speed
                            when: !touchpadSpeedSlider.pressed
                        }
                    }
                }
                ChoiceRow {
                    label: "Scrolling"
                    description: Config.options.hyprland.input.touchpad.naturalScroll ? "Natural: the page follows your fingers" : "Traditional: the page moves against your fingers"
                    options: [{ value: true, label: "Natural" }, { value: false, label: "Traditional" }]
                    current: Config.options.hyprland.input.touchpad.naturalScroll
                    onPicked: value => {
                        Config.options.hyprland.input.touchpad.naturalScroll = value;
                        HyprlandConfig.set("input:touchpad:natural_scroll", value ? 1 : 0);
                    }
                }
                SettingRow {
                    clickable: false
                    label: "Scroll speed"
                    stacked: true
                    control: Ruler {
                        fill: true
                        id: scrollSlider
                        implicitWidth: 260
                        label: inputCol.speedWord(scrollSlider.value / 0.7)   // 0.7: Tacit's usual scroll
                        from: 0.1
                        to: 3
                        stepSize: 0.1
                        onSettled: {
                            const v = Math.round(scrollSlider.value * 10) / 10;
                            Config.options.hyprland.input.touchpad.scrollFactor = v;
                            HyprlandConfig.set("input:touchpad:scroll_factor", v);
                        }
                        Binding on value {
                            value: Config.options.hyprland.input.touchpad.scrollFactor
                            when: !scrollSlider.pressed
                        }
                    }
                }
                SwitchRow {
                    label: "Ignore the touchpad while typing"
                    checked: Config.options.hyprland.input.touchpad.disableWhileTyping
                    onToggled: value => {
                        Config.options.hyprland.input.touchpad.disableWhileTyping = value;
                        HyprlandConfig.set("input:touchpad:disable_while_typing", value ? 1 : 0);
                    }
                }
                SwitchRow {
                    label: "Two fingers click to right-click"
                    checked: Config.options.hyprland.input.touchpad.clickfingerBehavior
                    onToggled: value => {
                        Config.options.hyprland.input.touchpad.clickfingerBehavior = value;
                        HyprlandConfig.set("input:touchpad:clickfinger_behavior", value ? 1 : 0);
                    }
                }
                SwitchRow {
                    label: "Tap to click"
                    checked: Config.options.hyprland.input.touchpad.tapToClick
                    onToggled: value => {
                        Config.options.hyprland.input.touchpad.tapToClick = value;
                        HyprlandConfig.set("input:touchpad:tap_to_click", value ? 1 : 0);
                    }
                }
            }
            Group {
                visible: inputCol.viewing === ""
                title: "Mouse"
                ChoiceRow {
                    label: "Acceleration"
                    options: [
                        { value: "tacit", label: "Tacit curve" },
                        { value: "flat", label: "Flat" },
                        { value: "adaptive", label: "Adaptive" }
                    ]
                    current: Config.options.hyprland.input.mouseProfile
                    onPicked: value => {
                        Config.options.hyprland.input.mouseProfile = value;
                        inputCol.writeSpeeds();
                    }
                }
                SettingRow {
                    clickable: false
                    label: "Speed"
                    // written once settled (released, or the keys at rest): every write reloads Hyprland
                    stacked: true
                    control: Ruler {
                        fill: true
                        id: speedSlider
                        implicitWidth: 260
                        label: inputCol.speedWord(Math.pow(2, speedSlider.value))   // the curve is scaled by 2^value
                        from: -1
                        to: 1
                        onSettled: {
                            Config.options.hyprland.input.sensitivity = Math.round(speedSlider.value * 20) / 20;
                            inputCol.writeSpeeds();
                        }
                        Binding on value {
                            value: Config.options.hyprland.input.sensitivity
                            when: !speedSlider.pressed
                        }
                    }
                }
                // the mouse scrolls like the touchpad does: the same choices, said globally, where the
                // touchpad's own touchpad-scoped keys keep winning for it
                ChoiceRow {
                    label: "Scrolling"
                    description: Config.options.hyprland.input.naturalScroll ? "Natural: the page follows your fingers" : "Traditional: the page moves against your fingers"
                    options: [{ value: true, label: "Natural" }, { value: false, label: "Traditional" }]
                    current: Config.options.hyprland.input.naturalScroll
                    onPicked: value => {
                        Config.options.hyprland.input.naturalScroll = value;
                        HyprlandConfig.set("input:natural_scroll", value ? 1 : 0);
                    }
                }
                SettingRow {
                    clickable: false
                    label: "Scroll speed"
                    stacked: true
                    control: Ruler {
                        fill: true
                        id: mouseScrollSlider
                        implicitWidth: 260
                        label: inputCol.speedWord(mouseScrollSlider.value)   // the pointer's usual scroll is 1
                        from: 0.1
                        to: 3
                        stepSize: 0.1
                        onSettled: {
                            const v = Math.round(mouseScrollSlider.value * 10) / 10;
                            Config.options.hyprland.input.scrollFactor = v;
                            HyprlandConfig.set("input:scroll_factor", v);
                        }
                        Binding on value {
                            value: Config.options.hyprland.input.scrollFactor
                            when: !mouseScrollSlider.pressed
                        }
                    }
                }
                // Hyprland's follow_mouse 0-3, each said by what it does (3 was "Only on click", the
                // opposite of what it is: a click does not move the typing)
                ChoiceRow {
                    label: "Focus follows the pointer"
                    description: ({
                        0: "Click a window to type in it",
                        1: "Moving the pointer onto a window lets you type in it",
                        2: "Scrolling reaches the window under the pointer; click to type in it",
                        3: "Clicking a window does not move your typing to it"
                    })[Config.options.hyprland.input.followMouse] ?? ""
                    options: [
                        { value: 0, label: "Off" },
                        { value: 1, label: "Always" },
                        { value: 2, label: "For scrolling only" },
                        { value: 3, label: "Keyboard stays put" }
                    ]
                    current: Config.options.hyprland.input.followMouse
                    onPicked: value => {
                        Config.options.hyprland.input.followMouse = value;
                        HyprlandConfig.set("input:follow_mouse", value);
                    }
                }
            }

            // Flow reads words.txt at the start of every dictation, so an edit counts from the next.
            Group {
                visible: inputCol.viewing === "" && root.flowInstalled
                title: "Dictation"
                note: "Words Flow always spells exactly as written here: names, products, places."
                ChoiceRow {
                    glyph: "mic"
                    label: "Dictation key"
                    options: root.flowKeyOptions
                    current: root.flowKey
                    onPicked: value => root.setFlowKey(value)
                }
                Repeater {
                    model: root.flowWords
                    SettingRow {
                        required property var modelData
                        required property int index
                        clickable: false
                        label: modelData
                        control: RowMenu {
                            items: [{ label: "Remove", run: () => root.setFlowWords(root.flowWords.filter((w, i) => i !== index)) }]
                        }
                    }
                }
                SettingRow {
                    id: wordRow
                    property string said: ""
                    clickable: false
                    glyph: "add"
                    label: "Add a word"
                    description: wordRow.said
                    control: RowLayout {
                        spacing: 6
                        LineField {
                            id: newWord
                            placeholder: "Word or name"
                            onAccepted: addWord.pressed()
                            onTextChanged: wordRow.said = ""
                        }
                        TextButton {
                            id: addWord
                            label: "Add"
                            // a refused word stays in the box, with the reason under the label
                            onPressed: {
                                const w = newWord.text.trim();
                                if (w.length === 0)
                                    return;
                                if (w.startsWith("#")) {
                                    wordRow.said = "A word can't start with #";
                                    return;
                                }
                                if (root.flowWords.includes(w)) {
                                    wordRow.said = "Already in the list";
                                    return;
                                }
                                root.setFlowWords([...root.flowWords, w]);
                                newWord.text = "";
                            }
                        }
                    }
                }
            }
            Advanced {
                StepperRow {
                    label: "Wait before a held key repeats"
                    value: Config.options.hyprland.input.repeatDelay
                    from: 100
                    to: 1000
                    stepSize: 50
                    suffix: " ms"
                    onMoved: value => {
                        Config.options.hyprland.input.repeatDelay = value;
                        HyprlandConfig.set("input:repeat_delay", value);
                    }
                }
                StepperRow {
                    label: "Repeats per second"
                    value: Config.options.hyprland.input.repeatRate
                    from: 10
                    to: 100
                    stepSize: 5
                    onMoved: value => {
                        Config.options.hyprland.input.repeatRate = value;
                        HyprlandConfig.set("input:repeat_rate", value);
                    }
                }
            }
            BackLine {
                visible: inputCol.viewing !== ""
                text: "Keyboard & touchpad"
                onClicked: inputCol.viewing = ""
            }
            Loader {
                Layout.fillWidth: true
                active: inputCol.viewing === "shortcuts"
                sourceComponent: ShortcutsPage {}
            }
        }
    }

    // ── Apps & services ──────────────────────────────────────────────────────
    Component {
        id: appsPage
        ColumnLayout {
            id: ap
            spacing: 0

            // default apps come from scripts/settings/default_apps.py, which reads the .desktop
            // files and mimeapps.list and writes both
            readonly property string defaultsScript: `${Directories.scriptPath}/settings/default_apps.py`
            property var roles: ({})
            Process {
                id: listDefaults
                running: true
                command: ["python3", ap.defaultsScript, "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            ap.roles = JSON.parse(text);
                        } catch (e) {}
                    }
                }
            }
            // Picks made while one is still applying wait here; running them together would race on the files.
            property var queuedDefaults: []
            Process {
                id: setDefault
                onExited: {
                    if (ap.queuedDefaults.length > 0) {
                        setDefault.command = ap.queuedDefaults[0];
                        ap.queuedDefaults = ap.queuedDefaults.slice(1);
                        setDefault.running = true;
                    } else {
                        listDefaults.running = true;
                    }
                }
            }

            Group {
                title: "Open at login"
                SwitchRow {
                    glyph: "login"
                    label: "Open apps when you log in"
                    checked: Config.options.hyprland.autostartApps.enable
                    onToggled: value => Config.options.hyprland.autostartApps.enable = value
                }
                Repeater {
                    model: Config.options.hyprland.autostartApps.enable ? Config.options.hyprland.autostartApps.apps : []
                    SettingRow {
                        id: sa
                        required property var modelData
                        required property int index
                        clickable: false
                        glyph: "apps"
                        label: root.appName(sa.modelData.cmd)
                        description: `On workspace ${sa.modelData.workspace ?? 1}`
                        control: RowMenu {
                            items: [1, 2, 3, 4, 5].map(w => ({ label: `On workspace ${w}`, checked: (sa.modelData.workspace ?? 1) === w, run: () => root.setStartup(sa.index, w) }))
                                .concat([{ label: "Do not open at login", run: () => root.removeStartup(sa.index) }])
                        }
                    }
                }
                ChoiceRow {
                    visible: Config.options.hyprland.autostartApps.enable
                    glyph: "add"
                    label: "Add an app"
                    // the ones already on the list are left out, as the dock's Pin an app does
                    options: root.appOptions.filter(o => !root.startupList().some(s => s.cmd === root.plainExec(root.appEntries.find(e => e.id === o.value))))
                    current: ""
                    onPicked: value => root.addStartup(value)
                }
            }

            Group {
                title: "Default apps"
                visible: Object.values(ap.roles).some(r => r.options.length > 0)
                Repeater {
                    model: [
                        { role: "browser", label: "Web browser", glyph: "public" },
                        { role: "files", label: "Files", glyph: "folder" },
                        { role: "terminal", label: "Terminal", glyph: "terminal" },
                        { role: "mail", label: "Mail", glyph: "mail" },
                        { role: "images", label: "Pictures", glyph: "image" },
                        { role: "video", label: "Video", glyph: "movie" },
                        { role: "music", label: "Music", glyph: "music_note" },
                        { role: "pdf", label: "PDF documents", glyph: "picture_as_pdf" },
                        { role: "text", label: "Text", glyph: "description" }
                    ]
                    ChoiceRow {
                        id: da
                        required property var modelData
                        readonly property var info: ap.roles[da.modelData.role] ?? { current: "", options: [] }
                        visible: da.info.options.length > 0
                        asList: true
                        glyph: da.modelData.glyph
                        label: da.modelData.label
                        options: da.info.options.map(o => ({ value: o.id, label: o.name }))
                        // the terminal has no MIME type: its current value is the shell's apps.terminal
                        current: da.modelData.role !== "terminal" ? da.info.current
                            : (da.info.options.find(o => o.exec.split(" ")[0] === Config.options.apps.terminal.split(" ")[0])?.id ?? Config.options.apps.terminal)
                        onPicked: value => {
                            if (da.modelData.role === "terminal") {
                                const o = da.info.options.find(x => x.id === value);
                                if (o)
                                    Config.options.apps.terminal = o.exec;
                            }
                            const cmd = ["python3", ap.defaultsScript, "set", da.modelData.role, value];
                            if (setDefault.running) {
                                ap.queuedDefaults = [...ap.queuedDefaults, cmd];
                            } else {
                                setDefault.command = cmd;
                                setDefault.running = true;
                            }
                        }
                    }
                }
            }
            Advanced {
                FieldRow {
                    label: "Screenshots"
                    placeholder: "Only copy them"
                    text: Config.options.screenSnip.savePath
                    onCommitted: value => Config.options.screenSnip.savePath = value
                }
                FieldRow {
                    label: "Screen recordings"
                    text: Config.options.screenRecord.savePath
                    onCommitted: value => Config.options.screenRecord.savePath = value
                }
            }
        }
    }

    // ── About ────────────────────────────────────────────────────────────────
    Component {
        id: aboutPage
        ColumnLayout {
            id: about
            spacing: 0

            property string model: ""
            property int cores: 0
            property real memoryKb: 0
            property real diskSize: 0
            property real diskFree: 0
            // the probes run when About opens (the shell's Settings does the same), not at login
            Component.onCompleted: {
                if (SystemInfo.cpu === "")
                    SystemInfo.refresh();
                about.takeAnchor(root.pageAnchor);
            }
            // about:updates (the notch's What's new): the Updates group, the page's last, at the top, its notes with it.
            // The rows above fill in as the probes answer and push it down, so it is kept there for two seconds, unless
            // the page is scrolled by hand. Spent once taken, as the Notch page's sections are.
            property bool toUpdates: false
            function takeAnchor(anchor) {
                if (anchor === "updates") {
                    about.toUpdates = true;
                    toUpdatesEnd.restart();
                    Qt.callLater(about.showUpdates);
                }
                root.pageAnchor = "";
            }
            function showUpdates() {
                if (!about.toUpdates)
                    return;
                const y = updatesGroup.mapToItem(pageColumn, 0, 0).y + pageColumn.y;
                pageScroll.contentY = Math.max(0, Math.min(pageScroll.contentHeight - pageScroll.height, y - 20));
            }
            onImplicitHeightChanged: Qt.callLater(about.showUpdates)
            Timer { id: toUpdatesEnd; interval: 2000; onTriggered: about.toUpdates = false }
            Connections {
                target: root
                function onAnchorAsked(anchor) { about.takeAnchor(anchor); }
            }
            Connections {
                target: pageScroll
                function onMovementStarted() { about.toUpdates = false; }
            }
            function gb(bytes) {
                return `${Math.round(bytes / 1e9)} GB`;
            }
            // The device tree names an ARM machine properly ("Samsung Galaxy Book4 Edge 15.6");
            // DMI is the x86 source, and some boards fill it with a placeholder.
            Process {
                running: true
                command: ["bash", "-c", `
                    m=$(tr -d '\\0' < /proc/device-tree/model 2>/dev/null)
                    [ -z "$m" ] && m=$(cat /sys/class/dmi/id/product_name 2>/dev/null | grep -vi 'o\\.e\\.m\\|default string')
                    echo "model=$m"
                    c=$(lscpu -p=core,socket 2>/dev/null | grep -v '^#' | sort -u | wc -l)
                    echo "cores=$([ "$c" -gt 0 ] && echo "$c" || nproc)"
                    echo "mem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
                    df -B1 --output=size,avail / | tail -1 | awk '{print "disk=" $1 " " $2}'
                `]
                stdout: SplitParser {
                    onRead: data => {
                        const i = data.indexOf("=");
                        const k = data.slice(0, i), v = data.slice(i + 1).trim();
                        if (k === "model") about.model = v;
                        else if (k === "cores") about.cores = parseInt(v);
                        else if (k === "mem") about.memoryKb = parseFloat(v);
                        else if (k === "disk") {
                            const [size, free] = v.split(" ").map(Number);
                            about.diskSize = size;
                            about.diskFree = free;
                        }
                    }
                }
            }

            // No Tacit mark exists yet, so the name is set in type.
            Group {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 20
                    spacing: 4
                    StyledText {
                        text: Product.name
                        font.pixelSize: 30
                        font.family: Appearance.font.family.display
                        font.weight: Font.Medium
                        color: Appearance.colors.colInkMain
                    }
                    StyledText {
                        text: `Version ${Updates.currentVersion || Product.version}`   // the installed release (/usr/share/tacit/release)
                        font.pixelSize: 15
                        color: Tacit.inkMeta
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        text: "Built on Quickshell and Hyprland, and started from end-4's illogical-impulse."
                        font.pixelSize: 13
                        color: Tacit.inkMeta
                        wrapMode: Text.Wrap
                    }
                }
            }
            Group {
                title: "This machine"
                SettingRow { visible: about.model.length > 0; clickable: false; glyph: "computer"; label: "Model"; control: StyledText { text: about.model; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { visible: SystemInfo.cpu.length > 0; clickable: false; glyph: "memory"; label: "Processor"; control: StyledText { text: about.cores > 0 ? `${SystemInfo.cpu} · ${about.cores} cores` : SystemInfo.cpu; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { visible: SystemInfo.gpu.length > 0; clickable: false; glyph: "developer_board"; label: "Graphics"; control: StyledText { text: SystemInfo.gpu; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { visible: about.memoryKb > 0; clickable: false; glyph: "memory_alt"; label: "Memory"; control: StyledText { text: `${Math.ceil(about.memoryKb / 1048576)} GB`; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { visible: about.diskSize > 0; clickable: false; glyph: "hard_drive"; label: "Storage"; control: StyledText { text: `${about.gb(about.diskFree)} free of ${about.gb(about.diskSize)}`; color: Tacit.inkMeta; font.pixelSize: 15 } }
            }
            Group {
                title: "Software"
                SettingRow { clickable: false; glyph: "badge"; label: "Name"; control: StyledText { text: SystemInfo.hostname; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { clickable: false; glyph: "deployed_code"; label: "System"; control: StyledText { text: SystemInfo.distroName; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { clickable: false; glyph: "terminal"; label: "Kernel"; control: StyledText { text: `Linux ${SystemInfo.kernelVersion.split("-")[0]}`; color: Tacit.inkMeta; font.pixelSize: 15 } }
                SettingRow { clickable: false; glyph: "schedule"; label: "Running for"; control: StyledText { text: DateTime.uptime; color: Tacit.inkMeta; font.pixelSize: 15 } }
            }
            // Tacit downloads its updates by itself and installs them while the computer restarts (session/updates);
            // the shell's Updates.qml writes what is waiting to updates.json. A check shows itself from the press: the
            // list, then the download as it goes, then the answer, with this Tacit's version and what changed
            // (2026-10-20: "Looking now" for minutes, and nobody could tell whether anything had come).
            Group {
                id: updatesGroup
                title: "Updates"
                aside: Updates.currentVersion.length > 0 ? `Tacit ${Updates.currentVersion}` : ""
                property var state: ({})
                // Restart gets the update ready first, then restarts (Updates.restartNow, the notch's too); when a step fails
                // nothing restarts, and the row says which: "" for neither, "prepare" or "reboot"
                readonly property bool tonight: Updates.tonightSet
                // a download for the restart that failed is over once a later look finds it all here (the shell's own
                // download, online again, finished it): the row said "Couldn't finish the download" over Tonight and
                // Restart until one of them was pressed
                readonly property string restartFailed: Updates.restartFailed === "prepare" && updatesGroup.state.ready === true
                    && (updatesGroup.state.checked ?? 0) > Updates.restartFailedAt ? "" : Updates.restartFailed
                readonly property bool restarting: Updates.restarting
                readonly property bool busy: Updates.phase !== ""
                readonly property bool ready: !busy && updatesGroup.state.ready === true
                // what stopped a check or a download, in one line (Updates.failureCause)
                function causeLine(cause) {
                    return ({ "busy": "The package manager is busy, try again once it is done",
                              "conflict": "The waiting updates conflict with what is installed; nothing was changed",
                              "live": "Updates come once Tacit is installed, not on the live USB",
                              "offline": "Check that this computer is online, then try again" })[cause] ?? "Try again later";
                }
                readonly property int waiting: updatesGroup.state.count ?? 0
                // Date.now() is not a binding: this ticks the age of the last check while the page shows
                property real now: Date.now()
                Timer {
                    interval: 60000
                    running: updatesGroup.visible
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: updatesGroup.now = Date.now()
                }
                readonly property string checkedText: {
                    const t = Updates.lastChecked || updatesGroup.state.checked || 0;
                    if (!t)
                        return "";
                    const m = Math.round((updatesGroup.now - t) / 60000);
                    // a check from another day says which: the background one skips a metered link or a low battery
                    // without a word, and a bare time days old read as today
                    const days = Voice.daysAgo(t, updatesGroup.now), at = Qt.formatTime(new Date(t), "hh:mm");
                    return m < 1 ? "Checked just now" : m < 60 ? `Checked ${m} min ago`
                        : days <= 0 ? `Checked at ${at}` : days === 1 ? `Checked yesterday at ${at}`
                        : days < 7 ? `Checked ${Voice.weekdays[new Date(t).getDay()]} at ${at}` : `Checked on ${Voice.when(t, updatesGroup.now)}`;
                }
                // the notes shown: the waiting releases' while they wait, else those this computer got with its last
                // update; "What's new" only over the waiting ones (with only other parts waiting, the installed
                // release's were titled as if they were coming)
                readonly property bool notesWaiting: updatesGroup.ready && Updates.nextNotes.length > 0
                readonly property var shownNotes: updatesGroup.notesWaiting ? Updates.nextNotes : Updates.installedNotes
                FileView {
                    path: `${Directories.userStateDir}/updates.json`
                    watchChanges: true
                    printErrors: false
                    onFileChanged: reload()
                    onLoaded: {
                        try {
                            updatesGroup.state = JSON.parse(text());
                        } catch (e) {
                            updatesGroup.state = ({});
                        }
                    }
                }
                // a download already going in the background shows as it goes
                Component.onCompleted: Updates.follow()
                SettingRow {
                    visible: Updates.available
                    clickable: false
                    glyph: "system_update"
                    label: Updates.phase === "looking" ? "Checking for updates"
                        : Updates.phase === "downloading" ? `Downloading ${Updates.count} ${Updates.count === 1 ? "update" : "updates"}`
                        : Updates.lastCheckFailed ? "Couldn't check for updates"
                        : updatesGroup.waiting === 0 ? "Tacit is up to date"
                        : updatesGroup.ready ? (updatesGroup.state.tacitVersion ? `Tacit ${updatesGroup.state.tacitVersion} is ready` : "Updates are ready")
                        : `${updatesGroup.waiting} ${updatesGroup.waiting === 1 ? "update" : "updates"} to download`
                    description: Updates.phase === "looking" ? "Asking for the newest list"
                        : Updates.phase === "downloading" ? (Updates.totalMB > 0 ? `${Updates.doneMB} of ${Updates.totalMB} MB` : "Starting")
                        : Updates.lastCheckFailed ? updatesGroup.causeLine(Updates.checkCause)
                        : updatesGroup.restarting ? "Getting ready to restart"
                        : Updates.restartWarning.length > 0 ? `${Updates.restartWarning} · restart anyway, or wait`
                        : updatesGroup.restartFailed === "battery" ? `Plug in to restart: the battery is at ${Updates.restartBattery}%`
                        : updatesGroup.restartFailed === "prepare" ? `Couldn't finish the download · ${updatesGroup.causeLine(Updates.restartCause).replace(/^./, c => c.toLowerCase())}`
                        : updatesGroup.restartFailed === "reboot" ? "Couldn't restart · someone else may be signed in on this computer"
                        : Updates.tonightFailed === "set" ? "Couldn't set the update for tonight"
                        : Updates.tonightFailed === "cancel" ? "Couldn't cancel tonight's update"
                        : updatesGroup.tonight ? (Updates.nightSkipped.length > 0 ? `Didn't install last night: ${Updates.nightSkipped}`
                            : "Tonight at 03:00 if it's left on, plugged in and locked, with Caffeine off")
                        : updatesGroup.ready ? `${updatesGroup.waiting} ${updatesGroup.waiting === 1 ? "update" : "updates"} · they install while the computer restarts`
                        : updatesGroup.waiting > 0 ? "Check for updates gets them now"
                        : updatesGroup.checkedText
                    control: Row {
                        visible: (updatesGroup.ready || updatesGroup.tonight) && !Updates.restarting
                        spacing: 4
                        // with Tonight chosen, Restart still installs them now instead (tacit-update now takes
                        // Tonight away), and Cancel takes it back
                        TextButton {
                            visible: !updatesGroup.tonight
                            label: "Tonight"
                            onPressed: Updates.tonight()
                        }
                        TextButton {
                            visible: updatesGroup.tonight
                            label: "Cancel tonight"
                            onPressed: Updates.cancelTonight()
                        }
                        // it closes every app: asked once in place, as the session screen and Apps do; after a
                        // warning, Restart anyway is already the second press
                        TextButton {
                            visible: updatesGroup.ready
                            label: Updates.restartWarning.length > 0 ? "Restart anyway" : "Restart"
                            confirm: Updates.restartWarning.length > 0 ? "" : "Press again to restart"
                            onPressed: Updates.restartNow()
                        }
                    }
                }
                // how far: a sand line on a quiet track, moving while there is nothing yet to measure
                Item {
                    visible: updatesGroup.busy
                    // a layout's row: its width from the layout (a width of its own is ignored there)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: 22
                    Rectangle {
                        id: track
                        x: 52; y: 4
                        width: parent.width - 52 - 20
                        height: 4
                        radius: 2
                        color: Tacit.raised
                        clip: true
                        Rectangle {
                            id: bar
                            height: parent.height
                            radius: 2
                            color: Tacit.accent
                            width: Updates.phase === "downloading" ? Math.max(8, parent.width * Updates.progress) : parent.width * 0.22
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            SequentialAnimation on x {
                                running: Updates.phase === "looking"
                                loops: Animation.Infinite
                                NumberAnimation { from: -track.width * 0.22; to: track.width; duration: 1400; easing.type: Easing.InOutQuad }
                            }
                            onVisibleChanged: x = 0
                            Connections { target: Updates; function onPhaseChanged() { if (Updates.phase !== "looking") bar.x = 0; } }
                        }
                    }
                }
                // what changed: the release waiting, or this one
                Column {
                    visible: updatesGroup.shownNotes.length > 0 && !updatesGroup.busy
                    // the layout's width, not its longest line's: the lines wrap (they ran past the window, VM 2026-10-20)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    topPadding: 10
                    bottomPadding: 12
                    spacing: 6
                    Repeater {
                        model: updatesGroup.shownNotes
                        delegate: Column {
                            required property var modelData
                            x: 52
                            width: parent.width - 52 - 20
                            spacing: 6
                            StyledText {
                                text: updatesGroup.notesWaiting ? `What's new in Tacit ${modelData.version}` : `New in Tacit ${modelData.version}`
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: Tacit.inkMain
                            }
                            Repeater {
                                model: modelData.changes ?? []
                                delegate: Row {
                                    required property string modelData
                                    width: parent.width
                                    spacing: 10
                                    Rectangle { y: 8; width: 4; height: 4; radius: 2; color: Tacit.inkMeta }
                                    StyledText {
                                        width: parent.width - 14
                                        text: modelData
                                        font.pixelSize: 14
                                        color: Tacit.inkSec
                                        wrapMode: Text.Wrap
                                        lineHeight: 1.2
                                    }
                                }
                            }
                        }
                    }
                }
                SettingRow {
                    visible: Updates.available
                    glyph: "refresh"
                    label: "Check for updates"
                    muted: updatesGroup.busy
                    description: updatesGroup.busy ? "Looking now" : Updates.lastCheckFailed ? "The last check didn't work" : "Now, instead of at the next look"
                    onActivated: Updates.checkNow()
                }
                SwitchRow {
                    visible: Updates.available
                    label: "Say when updates are ready"
                    description: "Once, in the notch"
                    checked: Config.options.updates.enableCheck
                    onToggled: value => Config.options.updates.enableCheck = value
                }
            }
        }
    }

    Component {
        id: soonPage
        ColumnLayout {
            spacing: 0
            Group {
                title: "Not moved yet"
                note: "These settings still live in the old window while the shape of this one is decided. Nothing has been lost."
            }
        }
    }

    // a quiet text button, the one the rows use
    // One device nearby, not yet paired. The control panel's flow (BluetoothSection.qml): bond,
    // then trust and connect, because an audio device bonds without bringing a profile up. Nothing
    // reports a failed pair, so a pair that has not landed after a while says so.
    component PairRow: SettingRow {
        id: pr
        required property var modelData
        readonly property bool pending: (pr.modelData?.pairing ?? false) || root.pendingPairs.includes(pr.modelData?.address)
        property string failed: ""
        clickable: false
        label: pr.modelData?.name || "Unknown device"
        glyph: Icons.getBluetoothDeviceMaterialSymbol(pr.modelData?.icon || "")
        description: pr.pending ? "Pairing…" : pr.failed
        control: TextButton {
            label: pr.pending ? "Cancel" : "Pair"
            onPressed: {
                const d = pr.modelData;
                if (!d)
                    return;
                if (pr.pending) {
                    root.pendingPairs = root.pendingPairs.filter(a => a !== d.address);
                    pairWait.stop();
                    d.cancelPair();
                    return;
                }
                pr.failed = "";
                root.pairAsked[d.address] = Date.now();
                root.pendingPairs = [...root.pendingPairs, d.address];
                pairWait.restart();
                d.pair();
            }
        }
        Timer {
            id: pairWait
            interval: 15000
            onTriggered: {
                const d = pr.modelData;
                if (!d || d.paired || !root.pendingPairs.includes(d.address))
                    return;
                root.pendingPairs = root.pendingPairs.filter(a => a !== d.address);
                pr.failed = BluetoothAgent.connected ? "Did not pair. Put it in pairing mode and try again"
                    : "Did not pair. It may need a code confirmed, which needs the pairing helper";
            }
        }
    }

    // A network in range. A click joins it; a secure one without a saved profile first asks for its
    // password on a line under it (Network.connectToWifiNetwork decides that), as does a join whose
    // password was refused. A click while joining stops it. The control panel's WifiRow, in these rows.
    component JoinRow: ColumnLayout {
        id: jr
        required property var modelData
        // a hairline above, as a group's own rows have, unless it is the group's first (Group.firstRow)
        property bool topRule: !!jr.parent && jr.parent.firstRow !== undefined && jr.parent.firstRow !== null && jr.parent.firstRow !== jr
        readonly property bool joining: Network.wifiConnectTarget === jr.modelData
        readonly property bool asking: jr.modelData?.askingPassword ?? false
        readonly property bool enterprise: Network.isEnterprise(jr.modelData)
        readonly property string failure: jr.modelData?.lastError ?? ""
        Layout.fillWidth: true
        spacing: 0
        function relayout() {}   // SettingRow calls this on its parent when it hides
        function submit() {
            if (jr.enterprise)
                Network.joinEnterprise(jr.modelData, identityField.text, passwordField.text, "peap");
            else
                Network.changePassword(jr.modelData, passwordField.text);
            passwordField.text = "";
        }

        SettingRow {
            id: joinLine
            readonly property string ssid: jr.modelData?.ssid ?? ""
            readonly property bool saved: Network.isKnown(joinLine.ssid)
            topRule: jr.topRule
            leading: Signal { strength: jr.modelData?.strength ?? 0 }
            label: joinLine.ssid
            // the lock says secure; the line under the name is for state, and for "Open"
            description: jr.joining ? "Joining… click to stop"
                : jr.failure.length > 0 ? jr.failure
                : joinLine.saved ? ["Saved", Network.isTrusted(joinLine.ssid) ? "Trusted" : ""].filter(x => x).join(" · ")
                : (jr.modelData?.isSecure ?? false) ? "" : "Open"
            // what a click does, said on hover; a saved network's menu beside it
            control: Row {
                spacing: 12
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: joinLine.hovered && !jr.joining && !jr.asking
                    text: "Connect"
                    font.pixelSize: 15
                    color: Appearance.colors.colInkMain
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (jr.modelData?.isSecure ?? false) && !jr.joining
                    text: "lock"
                    iconSize: 16
                    color: Tacit.inkMeta
                }
                RowMenu {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: joinLine.saved
                    items: [
                        { label: "Trusted: home or work", checked: Network.isTrusted(joinLine.ssid),
                          run: () => Network.setTrusted(joinLine.ssid, !Network.isTrusted(joinLine.ssid)) },
                        { label: "Forget this network", run: () => Network.forgetWifiNetwork(joinLine.ssid) }
                    ]
                }
            }
            onActivated: {
                if (jr.joining) {
                    Network.cancelJoin("Stopped joining");
                    return;
                }
                // the password box stays open: a click on the network again goes to it
                if (jr.asking) {
                    (jr.enterprise ? identityField : passwordField).focusInput();
                    return;
                }
                Network.connectToWifiNetwork(jr.modelData);
            }
        }
        SettingRow {
            visible: jr.asking
            topRule: true
            clickable: false
            label: jr.enterprise ? "Sign in" : "Password"
            onVisibleChanged: if (visible) (jr.enterprise ? identityField : passwordField).focusInput()
            control: RowLayout {
                spacing: 6
                LineField { id: identityField; visible: jr.enterprise; placeholder: "User name"; onAccepted: passwordField.focusInput(); onCancelled: jr.modelData.askingPassword = false }
                LineField { id: passwordField; secret: true; placeholder: "Password"; onAccepted: jr.submit(); onCancelled: jr.modelData.askingPassword = false }
                Slab { text: "Cancel"; onPicked: jr.modelData.askingPassword = false }
                Slab { text: "Join"; key: "↵"; tone: "default"; onPicked: jr.submit() }
            }
        }
    }

    // One Claude Code or Codex account on the Accounts page: PairRow's pending form while it signs
    // in (SignInLines under it), and the menu's second lines: its name, the key it signs in with,
    // and the confirms for signing out and removing. `page` is the Accounts page.
    component AccountBlock: ColumnLayout {
        id: ab
        required property string modelData      // the account's id
        property var page: null
        // a hairline above, as a group's own rows have, unless it is the group's first (Group.firstRow)
        property bool topRule: !!ab.parent && ab.parent.firstRow !== undefined && ab.parent.firstRow !== null && ab.parent.firstRow !== ab
        readonly property var acct: ab.page.account(ab.modelData) ?? ({ id: ab.modelData, agent: "", label: "" })
        readonly property string flow: ab.page.flowOf(ab.modelData)
        readonly property string agentName: ab.page.name(ab.acct.agent)
        readonly property string provider: ab.page.keyProvider(ab.acct)
        readonly property var providerKeys: ab.page.keys.filter(k => k.provider === ab.provider)
        Layout.fillWidth: true
        spacing: 0
        function relayout() {}   // SettingRow calls this on its parent when it hides
        onVisibleChanged: if (parent && parent.relayout) Qt.callLater(parent.relayout)
        function rename() {
            const t = renameField.text.trim();
            if (t.length > 0 && t !== ab.acct.label)
                ab.page.am.rename(ab.modelData, t, ab.page.noted(ab.modelData, "rename it"));
            ab.page.open = "";
        }
        // its own key, while it signs in with one
        readonly property var ownKey: ab.acct.use === "key" ? ab.page.keys.find(k => k.id === ab.acct.key) ?? null : null
        // the row's buttons: a sign-in's Cancel, or Try again and Cancel, else what its state needs.
        // A key is replaced only when it is the account's own; without one it picks or adds one.
        readonly property var acts: {
            const a = ab.acct;
            const p = ab.page;
            if (["starting", "waiting", "code", "device", "busy"].includes(ab.flow))
                return [{ label: "Cancel", run: () => p.cancelSignIn(a.id) }];
            if (ab.flow === "failed" || ab.flow === "late")
                return [{ label: "Try again", run: () => p.again(a, "") }, { label: "Cancel", run: () => p.cancelSignIn(a.id) }];
            switch (a.state) {
            case "signedOut":
            case "expired":
                return a.use === "key" ? [] : [{ label: "Sign in", run: () => p.signIn(a.id, a.use === "console" ? "console" : "browser", "") }];
            case "noKey":
            case "keyRefused":
                if (ab.ownKey)
                    return [{ label: "Replace key", run: () => p.goTo(`keys:${ab.provider}:${a.id}`) }];
                if (ab.providerKeys.length > 0)
                    return [{ label: "Choose key", run: () => p.toggle(`useKey:${a.id}`) }];
                return [{ label: "Add key", run: () => p.goTo(`keys:${ab.provider}:${a.id}`) }];
            }
            return [];
        }
        readonly property var menu: {
            const a = ab.acct;
            const p = ab.page;
            return [
                p.accountsOf(a.agent).length > 1
                    ? { label: `Default for ${ab.agentName}`, checked: p.defaultOf(a.agent)?.id === a.id, run: () => p.am.makeDefault(a.id, p.noted(a.id, "make it the default")) } : null,
                { label: "Check again", run: () => p.check(a.id) },
                { label: "Rename…", run: () => p.toggle(`rename:${a.id}`) },
                a.use === "key" ? { label: "Use the plan instead", run: () => p.setUse(a.id, "plan", "") }
                    : { label: "Use a key instead…", run: () => p.toggle(`useKey:${a.id}`) },
                a.use !== "key" && (a.state === "ready" || a.state === "checking") ? { label: "Sign out", run: () => p.toggle(`signOut:${a.id}`) } : null,
                a.personal ? null : { label: "Remove account", run: () => p.toggle(`remove:${a.id}`) }
            ].filter(x => x);
        }

        SettingRow {
            // who you are first (the email), its name and plan under it; "Personal" on every row said nothing
            readonly property bool byEmail: !ab.flow && ab.acct.state === "ready" && (ab.acct.email ?? "").length > 0
            topRule: ab.topRule
            clickable: false
            label: byEmail ? ab.acct.email : (ab.acct.label ?? "")
            description: ab.flow ? ab.page.flowText(ab.flow, ab.modelData)
                : ab.page.accountNotes[ab.modelData] ? ab.page.accountNotes[ab.modelData]
                : byEmail ? [ab.acct.label ?? "", ab.page.planText(ab.acct)].filter(s => s).join(" · ")
                : ab.page.facts(ab.acct)
            control: RowLayout {
                spacing: 4
                TextButton {
                    visible: ab.page.fromHost && ab.acts.length > 0
                    label: ab.acts[0]?.label ?? ""
                    onPressed: ab.acts[0].run()
                }
                TextButton {
                    visible: ab.page.fromHost && ab.acts.length > 1
                    label: ab.acts[1]?.label ?? ""
                    onPressed: ab.acts[1].run()
                }
                RowMenu {
                    visible: ab.page.fromHost && !ab.flow
                    items: ab.menu
                }
            }
        }
        SignInLines {
            page: ab.page
            account: ab.acct
            flow: ab.flow
        }
        SettingRow {
            visible: ab.page.open === `rename:${ab.modelData}`
            topRule: true
            clickable: false
            label: "Name"
            onVisibleChanged: if (visible) {
                renameField.text = ab.acct.label ?? "";
                renameField.focusInput();
            }
            control: RowLayout {
                spacing: 6
                LineField {
                    id: renameField
                    onAccepted: ab.rename()
                    onCancelled: ab.page.open = ""
                }
                TextButton {
                    label: "Rename"
                    onPressed: ab.rename()
                }
            }
        }
        ChoiceRow {
            visible: ab.page.open === `useKey:${ab.modelData}`
            topRule: true
            asList: true
            label: "Sign in with"
            description: ab.providerKeys.length > 0 ? "" : `There is no ${ab.page.providerName(ab.provider)} key yet`
            options: ab.providerKeys.map(k => ({ value: k.id, label: `${ab.page.providerName(k.provider)} key ••••${k.last4}` }))
                .concat([{ value: "add", label: "Add a key in Keys" }])
            current: ""
            onPicked: value => {
                if (value === "add")
                    ab.page.goTo(`keys:${ab.provider}:${ab.modelData}`);
                else
                    ab.page.setUse(ab.modelData, "key", value);
            }
        }
        SettingRow {
            visible: ab.page.open === `signOut:${ab.modelData}`
            topRule: true
            clickable: false
            label: `Sign out of ${ab.acct.email || ab.acct.label}?`
            description: "Sessions stay."
            control: RowLayout {
                spacing: 10
                Slab {
                    text: "Sign out"
                    tone: "risk"
                    onPicked: {
                        ab.page.open = "";
                        ab.page.am.logout(ab.modelData, "", ab.page.noted(ab.modelData, "sign out"));
                    }
                }
                Slab {
                    text: "Keep"
                    tone: "default"
                    onPicked: ab.page.open = ""
                }
            }
        }
        SettingRow {
            visible: ab.page.open === `remove:${ab.modelData}`
            topRule: true
            clickable: false
            label: `Remove ${ab.acct.label}?`
            description: "Its running sessions close, its sign-in is deleted and its folder goes to the Trash."
            control: RowLayout {
                spacing: 10
                Slab {
                    text: "Remove"
                    tone: "risk"
                    onPicked: {
                        ab.page.open = "";
                        ab.page.am.remove(ab.modelData, ab.page.noted(ab.modelData, "remove it"));
                    }
                }
                Slab {
                    text: "Keep"
                    tone: "default"
                    onPicked: ab.page.open = ""
                }
            }
        }
    }

    // One provider pi or opencode reaches: signed in through it, a key from Keys, or a key in the
    // agent's own file (a fact; nothing here moves it). A provider being connected has a row too.
    component ProviderBlock: ColumnLayout {
        id: pb
        required property string modelData      // "<account id>|<provider id>"
        property var page: null
        // a hairline above, as a group's own rows have, unless it is the group's first (Group.firstRow)
        property bool topRule: !!pb.parent && pb.parent.firstRow !== undefined && pb.parent.firstRow !== null && pb.parent.firstRow !== pb
        readonly property string accountId: pb.modelData.split("|")[0]
        readonly property string pid: pb.modelData.split("|").slice(1).join("|")
        readonly property var acct: pb.page.account(pb.accountId) ?? ({ id: pb.accountId, agent: "", label: "", providers: [] })
        readonly property var prov: (pb.acct.providers ?? []).find(p => p.id === pb.pid) ?? null
        readonly property string flow: pb.page.flowOf(pb.accountId, pb.pid)
        readonly property string agentName: pb.page.name(pb.acct.agent)
        readonly property var key: pb.prov?.via === "key"
            ? pb.page.keys.find(k => k.provider === pb.pid && (k.use ?? []).includes(pb.acct.agent)) ?? null : null
        Layout.fillWidth: true
        spacing: 0
        function relayout() {}
        onVisibleChanged: if (parent && parent.relayout) Qt.callLater(parent.relayout)
        readonly property string facts: {
            const p = pb.prov;
            if (!p)
                return "";
            switch (p.state ?? "ready") {
            case "locked": return "The keyring is locked";
            case "refused":
            case "keyRefused": return "The key was refused";
            case "expired":
            case "signedOut": return "Signed out";
            }
            if (p.via === "file")
                return pb.page.keyNotes[`import:${pb.acct.agent}|${pb.pid}`]
                    ?? (pb.importable ? `In ${pb.agentName}'s own file, not connected here` : `In ${pb.agentName}'s own file`);
            if (p.via === "key")
                return "Your key from Keys" + (pb.key ? ` · ••••${pb.key.last4}` : "");
            return "Signed in";
        }
        // a key in pi's own file that Keys can hold (Modal, say, it cannot): pi alone does not count
        // its own file's keys (opencode's work as they are)
        readonly property bool importable: pb.prov?.via === "file" && pb.acct.agent === "pi" && pb.page.fromHost
            && (accountsModel.providers ?? []).some(x => x.id === pb.pid)
        readonly property var acts: {
            if (pb.importable)
                return [{ label: "Use here", run: () => pb.page.importKey(pb.acct.agent, pb.pid) }];
            if (["starting", "waiting", "code", "device", "busy"].includes(pb.flow))
                return [{ label: "Cancel", run: () => pb.page.cancelSignIn(pb.accountId) }];
            if (pb.flow === "failed" || pb.flow === "late")
                return [{ label: "Try again", run: () => pb.page.again(pb.acct, pb.pid) }, { label: "Cancel", run: () => pb.page.cancelSignIn(pb.accountId) }];
            if (pb.prov?.via === "oauth" && (pb.prov.state === "expired" || pb.prov.state === "signedOut"))
                return [{ label: "Sign in", run: () => pb.page.signIn(pb.accountId, "", pb.pid) }];
            return [];
        }
        readonly property var menu: pb.prov?.via === "oauth" ? [{ label: "Sign out", run: () => pb.page.toggle(`signOut:${pb.modelData}`) }]
            : pb.key ? [{ label: `Stop using this key with ${pb.agentName}`, run: () => pb.page.am.useKey(pb.key.id, pb.acct.agent, false, pb.page.noted(pb.accountId, "stop using the key")) }]
            : []

        SettingRow {
            topRule: pb.topRule
            clickable: false
            label: (pb.page.accountsOf(pb.acct.agent).length > 1 ? `${pb.acct.label} · ` : "") + pb.page.providerName(pb.pid, pb.prov?.via ?? "oauth")
            description: pb.flow ? pb.page.flowText(pb.flow, pb.accountId) : pb.page.accountNotes[pb.accountId] ?? pb.facts
            control: RowLayout {
                spacing: 4
                TextButton {
                    visible: pb.page.fromHost && pb.acts.length > 0
                    label: pb.acts[0]?.label ?? ""
                    onPressed: pb.acts[0].run()
                }
                TextButton {
                    visible: pb.page.fromHost && pb.acts.length > 1
                    label: pb.acts[1]?.label ?? ""
                    onPressed: pb.acts[1].run()
                }
                RowMenu {
                    visible: pb.page.fromHost && !pb.flow && pb.menu.length > 0
                    items: pb.menu
                }
            }
        }
        SignInLines {
            page: pb.page
            account: pb.acct
            flow: pb.flow
        }
        SettingRow {
            visible: pb.page.open === `signOut:${pb.modelData}`
            topRule: true
            clickable: false
            label: `Sign out of ${pb.page.providerName(pb.pid, "oauth")} in ${pb.agentName}?`
            description: "Sessions stay."
            control: RowLayout {
                spacing: 10
                Slab {
                    text: "Sign out"
                    tone: "risk"
                    onPicked: {
                        pb.page.open = "";
                        pb.page.am.logout(pb.accountId, pb.pid, pb.page.noted(pb.accountId, "sign out"));
                    }
                }
                Slab {
                    text: "Keep"
                    tone: "default"
                    onPicked: pb.page.open = ""
                }
            }
        }
    }

    // What a sign-in in progress needs under its row: Open it again and I have a code (Claude), the
    // code field, a device code to type elsewhere, or the ways out of a busy port.
    component SignInLines: ColumnLayout {
        id: sl
        property var page: null
        property var account: null
        property string flow: ""
        readonly property var signin: sl.page.am.signin?.account === sl.account?.id ? sl.page.am.signin : null
        readonly property bool coding: sl.flow === "code" || (sl.flow === "waiting" && sl.page.open === `code:${sl.account?.id}`)
        property string codeNote: ""
        property bool copied: false
        Layout.fillWidth: true
        spacing: 0
        function relayout() {}
        // the code goes to the host and the field is emptied in the same step
        function sendCode() {
            const c = codeField.text.trim();
            codeField.text = "";
            if (!c.length)
                return;
            sl.codeNote = "";
            sl.page.am.code(sl.account.id, c, r => {
                if (r.ev === "error")
                    sl.codeNote = `The code didn't go through: ${r.message ?? ""}`;
            });
        }
        readonly property var actions: {
            const p = sl.page;
            const a = sl.account;
            if (!a || !p.fromHost)
                return [];
            if (sl.flow === "waiting" && !sl.coding)
                return [
                    sl.signin?.url ? { label: sl.signin.opened === false ? "Open the page" : "Open it again", run: () => Qt.openUrlExternally(sl.signin.url) } : null,
                    a.agent === "claude" ? { label: "I have a code", run: () => p.open = `code:${a.id}` } : null
                ].filter(x => x);
            if (sl.flow === "busy") {
                const h = p.holder(sl.signin?.holder ?? "");
                return [
                    h.account ? { label: "Cancel it", run: () => { p.am.cancel(h.account.id); p.cancelSignIn(a.id); } }
                        : { label: "Try again", run: () => p.again(a, "") },
                    a.agent === "codex" ? { label: "Use a code instead", run: () => p.signIn(a.id, "device", "") } : null
                ].filter(x => x);
            }
            return [];
        }

        ActionLine {
            visible: sl.actions.length > 0
            items: sl.actions
        }
        SettingRow {
            visible: sl.coding
            topRule: true
            clickable: false
            label: "Code"
            description: sl.codeNote
            onVisibleChanged: if (visible) {
                codeField.text = "";
                codeField.focusInput();
            } else {
                codeField.text = "";
            }
            control: RowLayout {
                spacing: 6
                LineField {
                    id: codeField
                    implicitWidth: 250
                    placeholder: "Paste the code the page shows"
                    onAccepted: sl.sendCode()
                    onCancelled: if (sl.page.open === `code:${sl.account?.id}`) sl.page.open = ""
                }
                Slab {
                    text: "Finish"
                    key: "↵"
                    tone: "default"
                    onPicked: sl.sendCode()
                }
            }
        }
        SettingRow {
            visible: sl.flow === "device"
            topRule: true
            clickable: false
            label: `Enter ${sl.signin?.userCode ?? ""} at ${(sl.signin?.url ?? "").replace(/^https?:\/\//, "")}`
            control: TextButton {
                label: sl.copied ? "Copied" : "Copy"
                onPressed: {
                    Quickshell.clipboardText = sl.signin?.userCode ?? "";
                    sl.copied = true;
                    copiedReset.restart();
                }
            }
        }
        Timer {
            id: copiedReset
            interval: 1500
            onTriggered: sl.copied = false
        }
    }

    // One provider's key on the Accounts page, or the provider with none: its facts, the Add key or
    // Replace line, and the confirm for removing a key an account signs in with. The key is typed
    // into a LineField emptied by the handler that sends it, never a FieldRow, whose text binding
    // would keep the value.
    component KeyBlock: ColumnLayout {
        id: kb
        required property string modelData      // "k:<key id>", or "p:<provider>" for one with no key
        property var page: null
        // a hairline above, as a group's own rows have, unless it is the group's first (Group.firstRow)
        property bool topRule: !!kb.parent && kb.parent.firstRow !== undefined && kb.parent.firstRow !== null && kb.parent.firstRow !== kb
        readonly property var key: kb.modelData.startsWith("k:") ? kb.page.keys.find(k => `k:${k.id}` === kb.modelData) ?? null : null
        readonly property string provider: kb.key?.provider ?? (kb.modelData.startsWith("p:") ? kb.modelData.slice(2) : "")
        readonly property string line: kb.key ? `replace:${kb.key.id}` : `key:${kb.provider}`
        readonly property string note: kb.page.keyNotes[kb.line] ?? ""
        readonly property var env: kb.page.envOf(kb.provider)
        // for the remove confirm: the accounts that sign in with the key, and the others the host
        // named when it refused (back on their plan, still holding the key)
        readonly property var signers: !kb.key ? [] : kb.page.signsInWith(kb.key.id)
        readonly property var holders: !kb.key ? [] : (kb.page.keyUsers[kb.key.id] ?? []).map(id => kb.page.account(id))
            .filter(a => a && !kb.signers.some(s => s.id === a.id))
        // The provider's Add key line sits under its last key, or under its row when it has none.
        readonly property var providerKeys: kb.page.keys.filter(k => k.provider === kb.provider)
        readonly property bool addHere: !kb.key || kb.providerKeys[kb.providerKeys.length - 1]?.id === kb.key.id
        readonly property string addLine: `key:${kb.provider}`
        // the line open under this block: its key's Replace, or the provider's Add key
        readonly property string entry: kb.page.open === kb.line ? kb.line : kb.addHere && kb.page.open === kb.addLine ? kb.addLine : ""
        readonly property var addFor: kb.entry === kb.addLine && kb.page.keyFor ? kb.page.account(kb.page.keyFor) : null
        objectName: kb.key ? `acc-anchor:key:${kb.key.id}` : `acc-anchor:keys:${kb.provider}`
        Layout.fillWidth: true
        spacing: 0
        function relayout() {}
        function focusAdd() { keyField.focusInput(); }
        function who(accts) { return kb.page.list(accts.map(a => `${a.label} (${kb.page.name(a.agent)})`)); }
        function save() {
            const secret = keyField.text.trim();
            keyField.text = "";
            const line = kb.entry;
            if (secret.length > 0 && line.length > 0)
                kb.page.saveKey(line, kb.provider, line === kb.line ? kb.key : null, secret);
        }
        readonly property var menu: !kb.key ? [] : [
            kb.env.pi ? { label: "Use with pi", checked: kb.key.use.includes("pi"), run: () => kb.page.am.useKey(kb.key.id, "pi", !kb.key.use.includes("pi"), kb.page.keyNoted(kb.line)) } : null,
            kb.env.opencode ? { label: "Use with opencode", checked: kb.key.use.includes("opencode"), run: () => kb.page.am.useKey(kb.key.id, "opencode", !kb.key.use.includes("opencode"), kb.page.keyNoted(kb.line)) } : null,
            { label: "Check again", run: () => kb.page.checkKey(kb.key, kb.line) },
            { label: "Replace…", run: () => kb.page.toggle(kb.line) },
            { label: "Remove", run: () => kb.page.removeKey(kb.key, false) }
        ].filter(x => x)

        SettingRow {
            topRule: kb.topRule
            clickable: false
            label: kb.key && kb.page.keys.filter(k => k.provider === kb.provider).length > 1 ? kb.key.label : kb.page.providerName(kb.provider)
            description: kb.note || (kb.key ? kb.page.keyFacts(kb.key) : kb.page.noKeyFacts(kb.provider))
            control: RowLayout {
                spacing: 4
                TextButton {
                    visible: kb.page.fromHost && !kb.key
                    label: kb.page.open === kb.line ? "Cancel" : "Add key"
                    onPressed: kb.page.toggle(kb.line)
                }
                RowMenu {
                    visible: kb.page.fromHost && !!kb.key
                    items: kb.menu
                }
            }
        }
        SettingRow {
            visible: kb.page.fromHost && kb.entry.length > 0
            topRule: true
            clickable: false
            label: kb.entry !== kb.line ? "Another key" : kb.key ? "New key" : "Key"
            // an Add line under a key row keeps its own Checking… and refusal here, not on that key
            description: (kb.entry !== kb.line ? kb.page.keyNotes[kb.entry] ?? "" : "")
                || (kb.addFor ? `${kb.addFor.label} (${kb.page.name(kb.addFor.agent)}) will sign in with it` : "")
            onVisibleChanged: if (visible)
                kb.focusAdd();
            else
                keyField.text = "";
            control: RowLayout {
                spacing: 6
                LineField {
                    id: keyField
                    implicitWidth: 240
                    secret: true
                    placeholder: "Paste the key"
                    onAccepted: kb.save()
                    onCancelled: kb.page.open = ""
                }
                Slab {
                    text: "Save"
                    key: "↵"
                    tone: "default"
                    onPicked: kb.save()
                }
            }
        }
        SettingRow {
            visible: !!kb.key && kb.page.open === `removeKey:${kb.key.id}`
            topRule: true
            clickable: false
            label: [kb.signers.length > 0 ? `${kb.who(kb.signers)} sign${kb.signers.length > 1 ? "" : "s"} in with this key.` : "",
                    kb.holders.length > 0 ? `This key is still set on ${kb.who(kb.holders)}.` : ""]
                .filter(s => s.length > 0).join(" ") || "An account uses this key."
            control: RowLayout {
                spacing: 4
                Slab {
                    text: "Remove"
                    tone: "risk"
                    onPicked: kb.page.removeKey(kb.key, true)
                }
                Slab {
                    text: "Keep"
                    tone: "default"
                    onPicked: kb.page.open = ""
                }
            }
        }
    }

    // Buttons on a line of their own under the row they act for, where the row's label starts.
    component ActionLine: Item {
        id: al
        property var items: []      // [{ label, run }]
        Layout.fillWidth: true
        implicitHeight: 40
        RowLayout {
            x: 12
            spacing: 2
            Repeater {
                model: al.items
                TextButton {
                    required property var modelData
                    label: modelData.label
                    onPressed: modelData.run()
                }
            }
        }
    }

    // A bare text box in the look of FieldRow's, for lines that hold more than one.
    component LineField: Rectangle {
        id: lf
        property alias text: lfInput.text
        property string placeholder: ""
        property bool secret: false
        signal accepted()
        // Esc empties the box and leaves it, and a row with a Cancel closes its line on it: Esc went on to the page,
        // which closed Settings with what was typed
        signal cancelled()
        implicitWidth: 180
        implicitHeight: 32
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.2)
        border.width: 1
        border.color: lfInput.activeFocus ? Appearance.colors.colPrimary
            : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
        function focusInput() { lfInput.forceActiveFocus(); }
        TextInput {
            id: lfInput
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: 15
            font.family: Appearance.font.family.main
            color: Appearance.colors.colInkMain
            selectionColor: Appearance.colors.colPrimary
            echoMode: lf.secret ? TextInput.Password : TextInput.Normal
            clip: true
            activeFocusOnTab: true
            onAccepted: lf.accepted()
            Keys.onEscapePressed: {
                lfInput.text = "";
                lfInput.focus = false;
                lf.cancelled();
            }
        }
        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: lfInput.text.length === 0
            text: lf.placeholder
            font.pixelSize: 15
            color: Tacit.inkMeta
        }
    }

    // An action in quiet words (the photo editor's "Change", "Join"): a word and an optional glyph,
    // a soft wash on hover, the accent ring for keyboard focus; no outline. `confirm` asks in place,
    // as the kit's Slab and WordAction do: the first press shows it in the risk ink after the warning
    // glyph, a second says pressed(); Esc, the keyboard or the pointer leaving, or 4 s untouched put
    // the words back.
    component TextButton: Rectangle {
        id: btn
        property string label: ""
        property string glyph: ""
        property string confirm: ""
        property bool asked: false
        property bool askedByPointer: false
        readonly property bool asking: btn.confirm !== "" && btn.asked
        signal pressed()
        function press(byPointer) {
            if (btn.confirm !== "" && !btn.asked) {
                btn.askedByPointer = byPointer;
                btn.asked = true;
                btn.forceActiveFocus();
                askWait.restart();
                return;
            }
            btn.cancelAsk();
            btn.pressed();
        }
        function cancelAsk() {
            btn.asked = false;
            askWait.stop();
        }
        onConfirmChanged: if (btn.confirm === "") btn.cancelAsk()
        onActiveFocusChanged: if (!btn.activeFocus) btn.cancelAsk()
        Timer {
            id: askWait
            interval: Tacit.motion.confirmWait.ms
            onTriggered: btn.cancelAsk()
        }
        implicitHeight: 32
        implicitWidth: btnRow.implicitWidth + 20
        radius: 8
        color: btn.asking ? ColorUtils.transparentize(Tacit.risk, 0.86)
            : btnArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.95) : "transparent"
        border.width: btn.activeFocus && (btn.focusReason === Qt.TabFocusReason || btn.focusReason === Qt.BacktabFocusReason) ? 2 : 0
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.15)
        activeFocusOnTab: btn.visible && btn.enabled
        Keys.onReturnPressed: btn.press(false)
        Keys.onEnterPressed: btn.press(false)
        Keys.onSpacePressed: btn.press(false)
        // only while asking: otherwise Esc goes on to the page, which closes Settings
        Keys.onEscapePressed: event => {
            if (btn.asked)
                btn.cancelAsk();
            else
                event.accepted = false;
        }
        Behavior on color { ColorAnimation { duration: 80 } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            MaterialSymbol {
                visible: btn.asking || btn.glyph.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: btn.asking ? "warning" : btn.glyph
                iconSize: 17
                color: btn.asking ? Tacit.risk : Tacit.inkSec
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.asking ? btn.confirm : btn.label
                font.pixelSize: 15
                color: !btn.enabled ? Appearance.colors.colInkFaint : btn.asking ? Tacit.risk : Tacit.inkMain
            }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.press(true)
            onExited: if (btn.askedByPointer) btn.cancelAsk()
        }
    }
}
