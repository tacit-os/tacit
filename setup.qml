//@ pragma UseQApplication
//@ pragma AppId tacit-setup
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// Tacit's setup: from the USB stick to the first desktop. Design: ~/Pictures/Martida/tacit-setup-mocks-2026-10-08
// (v8, after five reviews and a final round). Every screen keeps the same lines - headline top 200, controls top
// 360, the main action's top 720 and centred - so a step changes in place; the horizon (a render from the
// trailer's renderer) is the progress, one step brighter per screen.
//
// PRACTICE ONLY for now (scripts/setup/setupd.py): the computer is read - Wi-Fi, disks, power, keyboards - and the
// install is played, but nothing is written to a disk, no network is joined and no account is made. The real install
// needs a Tacit system image to copy (release plan steps 1-2).
//
//   qs -p setup.qml                          full screen, as on the stick
//   TACIT_SETUP_WINDOWED=1 qs -p setup.qml   in a window, to look at it on the desktop
//   TACIT_SETUP_SCENARIO=windows|bitlocker|asleep|check|nouefi|full|empty|linux, TACIT_SETUP_FAIL=1   cases this computer does not have

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.setup

ApplicationWindow {
    id: root
    visible: true
    title: "Tacit setup"
    color: "black"
    readonly property bool windowed: (Quickshell.env("TACIT_SETUP_WINDOWED") ?? "") === "1"
    width: windowed ? 1440 : (screen?.width ?? 1920)
    height: windowed ? 810 : (screen?.height ?? 1080)
    visibility: windowed ? Window.Windowed : Window.FullScreen
    // a window opened over it on the stick (a key that starts the terminal) takes the full screen away (Hyprland's
    // on_focus_under_fullscreen), and the practice run's rule then made Setup a card: it takes it back when in front again
    onActiveChanged: if (active && !windowed && visibility !== Window.FullScreen) visibility = Window.FullScreen
    // closing the window (Super+Q, Alt+F4) mid-install would stop the helper while the installer, as root, goes on to a disk
    // already erased or shrunk with nobody to give it the account: refused while a real install runs
    onClosing: close => { if (!backend.practice && setup.installState === "running") close.accepted = false; }
    Binding { target: Quickshell; property: "watchFiles"; value: false }
    Binding { target: Look; property: "u"; value: Math.min(root.width / 1920, root.height / 1080) }
    Component.onCompleted: MaterialThemeLoader.reapplyTheme()
    // ask until it answers: a request written before the service has started is lost
    Timer { interval: 300; repeat: true; running: !backend.ready; triggeredOnStart: true; onTriggered: if (proc.running) backend.send({ op: "hello" }) }

    // ── what the computer says (scripts/setup/setupd.py)
    QtObject {
        id: backend
        property var languages: []
        property var layouts: []
        property var nonLatin: []       // layouts that cannot type Latin letters
        property bool wired: false      // a cable connects this computer (no Wi-Fi needed)
        property var wifi: []
        property var disk: ({})
        property var plan: null
        property var disks: []          // every disk inside, when there is more than one to choose from
        property var power: ({ ac: true })
        property string scenario: ""
        property bool ready: false
        property bool disksRead: false      // the disks come in their own answer, once read (it can take a minute)
        property var parts: []              // every partition inside, for "Choose partitions myself"
        property bool editing: false        // the partition editor is open
        property bool practice: true        // false on Tacit's live system: the install is real
        function send(o) { proc.write(JSON.stringify(o) + "\n"); }
    }
    Process {
        id: proc
        running: true
        command: ["python3", "-I", Quickshell.shellPath("scripts/setup/setupd.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root.receive(line) }
        // the helper going away mid-install would leave "Installing" on the page for good (Back and Esc are blocked)
        onExited: {
            setup.joining = false;
            if (setup.installState !== "running") return;
            setup.installUntouched = false; setup.installReason = "Setup's helper stopped"; setup.installState = "failed"; setup.go("failed");
        }
    }
    function receive(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        if (m.ev === "hello") {
            backend.languages = m.languages; backend.layouts = m.layouts; backend.nonLatin = m.nonLatin ?? []; backend.wifi = m.wifi; backend.wired = m.wired === true;
            backend.power = m.power; backend.scenario = m.scenario;
            backend.practice = m.practice !== false;
            backend.ready = true;
            if (setup.language === "") { setup.language = m.languages[0].code; setup.layout = m.keyboard || m.languages[0].layout; }
            const here = m.wifi.find(w => w.inUse);
            if (here) setup.network = here.ssid;
        } else if (m.ev === "disks") { backend.disk = m.disk; backend.plan = m.plan; backend.disks = m.disks ?? []; backend.parts = m.parts ?? []; backend.disksRead = true; root.keepParts(); }
        else if (m.ev === "editorClosed") backend.editing = false;
        else if (m.ev === "wifi") { backend.wifi = m.wifi; backend.wired = m.wired === true; }
        else if (m.ev === "disk") { backend.disk = m.disk; backend.plan = m.plan; }
        else if (m.ev === "power") backend.power = m.power;
        else if (m.ev === "join") {
            setup.joining = false;
            if (m.ok) { setup.joined = m.ssid; setup.joinError = ""; if (setup.page === "wifi") setup.go("where"); }
            else setup.joinError = m.why === "password" ? "That password didn't work. Check it and try again." : `Could not connect to ${m.ssid}. Try again, or connect later.`;
        } else if (m.ev === "install") {
            setup.installDone = m.done; setup.installLeft = m.left ?? -1; setup.installState = m.state;
            if (m.other) setup.otherSystem = m.other;
            if (m.state === "failed") setup.installUntouched = m.untouched !== false;
            if (m.state === "failed") setup.installReason = m.reason ?? "";
            if (m.state === "failed") setup.go("failed");
            else if (m.state === "done" && setup.page === "almost") setup.go("ready");
        }
    }
    Timer { interval: 10000; repeat: true; running: setup.page === "wifi"; triggeredOnStart: true; onTriggered: backend.send({ op: "wifi" }) }

    // ── where we are, and what has been chosen
    QtObject {
        id: setup
        property string page: "welcome"
        property var trail: []
        property string language: ""
        property string layout: ""
        property bool layoutPicked: false       // a keyboard chosen from the list: a language chosen after it leaves it be
        // a layout that cannot type Latin letters (Russian, Arabic ...) comes second to US, so a Wi-Fi name or password
        // can still be typed; Alt + Shift switches (tacit-install writes the same pair for the installed system)
        readonly property bool paired: backend.nonLatin.includes(layout)
        readonly property string kbLayout: paired ? `us,${layout}` : layout
        readonly property string kbTag: kbLayout.replace(",", " / ")      // on the password fields
        // the live system types in the layout chosen, so a password made here is typed the same at the installed
        // system's lock (which reads the layout tacit-install writes); not in the practice run, which runs on this desktop
        onKbLayoutChanged: if (!backend.practice && /^[a-z]{2,8}(,[a-z]{2,8})?$/.test(kbLayout))
            Quickshell.execDetached(["hyprctl", "eval", `hl.config({ input = { kb_layout = "${kbLayout}", kb_options = "${paired ? "grp:alt_shift_toggle" : ""}" } })`])
        property string installReason: ""   // what stopped an install, in the installer's words
        property string network: ""
        property string joined: ""
        property bool joining: false
        property string joinName: ""            // the network being joined
        property bool otherNet: false           // "Other network…": its name and password typed in
        property string joinError: ""
        property string place: "next"          // next | instead | manual
        // "Choose partitions myself": Tacit's partition (erased), the EFI partition (kept), a boot partition (erased) or ""
        property string partRoot: ""
        property string partEfi: ""
        property string partBoot: ""
        property string otherSystem: ""        // Windows on another disk, still chosen with Space (tacit-install)
        property string picture: "dune"
        property real installDone: 0
        property int installLeft: -1
        property bool installUntouched: true
        property string installState: ""
        readonly property bool installing: installState === "running" || installState === "done"
        function go(p) { trail = trail.concat([page]); page = p; }
        function back() {
            // the failed page's way out is Try again: Back would land on a page of an install that is not running
            if (installing || page === "failed" || trail.length === 0) return;
            const t = trail.slice(); page = t.pop(); trail = t;
        }
        function startInstall() {
            if (installing) return;
            backend.send({ op: "install", place: place }); installState = "running"; trail = []; go("you");
        }
        function startManual() {
            if (installing) return;
            place = "manual";
            backend.send({ op: "install", place: "manual", root: partRoot, efi: partEfi, boot: partBoot || null });
            installState = "running"; trail = []; go("you");
        }
        readonly property var lang: backend.languages.find(l => l.code === language) ?? null
        readonly property var layoutName: (backend.layouts.find(l => l.code === layout) ?? { name: layout }).name
    }
    readonly property int step: ({ welcome: 1, languages: 1, keyboards: 1, wifi: 2, where: 3, disks: 3, erase: 3, parts: 3, eraseparts: 3, you: 4, almost: 6, ready: 7, failed: 3 })[setup.page] ?? 1

    // a page switch: the new words come in where the old ones were, rising a little
    property string shownPage: "welcome"
    Connections {
        target: setup
        function onPageChanged() {
            swapOut.restart();
            // no disk was found when the disks were read: one that came up since (a slow drive) is looked for again
            if (setup.page === "where" && backend.disksRead && (backend.disk.case ?? "none") === "none") backend.send({ op: "disks" });
        }
    }
    SequentialAnimation {
        id: swapOut
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: Look.lessMotion ? 80 : 140; easing.type: Easing.InCubic }
        ScriptAction { script: { root.shownPage = setup.page; content.y = Look.lessMotion ? 0 : Look.px(10); root.focusFirst(); } }
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: Look.lessMotion ? 120 : 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: content; property: "y"; to: 0; duration: Look.lessMotion ? 0 : 420; easing.type: Easing.OutCubic }
        }
    }
    function focusFirst() {
        Qt.callLater(() => {
            if (root.shownPage === "you") nameField.focusIn();
            else if (root.shownPage === "wifi" && root.pwFieldRef) root.pwFieldRef.focusIn();
            // Erase can't be undone: the page opens on Back, so a doubled Enter from the page before goes back, and
            // erasing takes a choice (Tab or a click) after "This can't be undone" has been seen
            else if (root.shownPage === "erase" || root.shownPage === "eraseparts") otherWay.forceActiveFocus();
            else primary.forceActiveFocus();
        });
    }

    Item {
        id: shot
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { if (a11y.open) a11y.open = false; else setup.back(); }

        Ground { anchors.fill: parent; step: root.step; lessMotion: Look.lessMotion }

        // the design is 1920 x 1080; everything inside scales with Look.u, centred on any screen
        Item {
            id: stage
            width: Look.px(1920); height: Look.px(1080)
            anchors.centerIn: parent

            // practice: said where a tester sees it, never in the way
            T { visible: backend.practice; x: Look.px(48); y: Look.px(58); text: "Practice run · nothing is installed"; font.pixelSize: Look.fs(14); color: Look.meta }

            // while it installs: one quiet line at the top, on the dark sky
            T {
                visible: setup.installing && ["you", "almost"].includes(root.shownPage)
                x: (stage.width - width) / 2; y: Look.px(62)
                text: setup.installLeft < 0 ? "Installing" : `Installing · about ${Math.max(1, Math.round(setup.installLeft / 60))} ${Math.round(setup.installLeft / 60) <= 1 ? "minute" : "minutes"} left`
                font.pixelSize: Look.fs(17); color: Look.sec
            }

            Item {
                id: content
                width: stage.width; height: stage.height

                // ── welcome
                Item {
                    visible: root.shownPage === "welcome"
                    anchors.fill: parent
                    T { x: (parent.width - width) / 2 + Look.px(14); y: Look.px(196); text: "TACIT"; font.family: Look.display; font.pixelSize: Look.fs(60); font.weight: Font.Light; font.variableAxes: { "wght": 300 }; font.letterSpacing: Look.px(28) }
                    // a language Tacit has no words in (Setup itself is in English for all): said once chosen, not left to be found out
                    Sentence { visible: setup.lang?.translated === false; text: root.notTranslated }
                    Column {
                        x: (parent.width - width) / 2; y: Look.px(330); width: Look.px(600)
                        Repeater {
                            model: backend.languages.slice(0, 5)
                            Item {
                                id: langRow
                                required property var modelData
                                readonly property bool on: modelData.code === setup.language
                                width: Look.px(600); height: Look.px(50)
                                activeFocusOnTab: true
                                Keys.onReturnPressed: root.pickLanguage(modelData)
                                Keys.onSpacePressed: root.pickLanguage(modelData)
                                T {
                                    anchors.centerIn: parent
                                    text: langRow.modelData.name
                                    font.pixelSize: langRow.on ? Look.fs(30) : Look.fs(24)
                                    font.weight: langRow.on || langRow.activeFocus ? Font.Medium : Font.Normal
                                    color: langRow.on || langRow.activeFocus || lma.containsMouse ? Look.main : Look.meta
                                }
                                MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickLanguage(langRow.modelData) }
                            }
                        }
                        Item { width: 1; height: Look.px(10) }
                        Link { anchors.horizontalCenter: parent.horizontalCenter; glyph: "language"; text: "More languages ›"; onClicked: setup.go("languages") }
                    }
                    Link { x: (parent.width - width) / 2; y: Look.px(646); text: `Keyboard: ${setup.layoutName}  ›`; bright: true; onClicked: setup.go("keyboards") }
                    T { visible: setup.paired; x: (parent.width - width) / 2; y: Look.px(684); text: "Press Alt + Shift to switch to the US keyboard."; font.pixelSize: Look.fs(16); color: Look.meta }
                }

                // ── a long list to pick from: every language, or every keyboard
                Item {
                    visible: root.shownPage === "languages" || root.shownPage === "keyboards"
                    anchors.fill: parent
                    readonly property bool langs: root.shownPage === "languages"
                    Headline { text: parent.langs ? "Choose a language." : "Choose a keyboard." }
                    Sentence { text: !parent.langs ? "Type a few letters to find yours."
                                   : setup.lang?.translated === false ? root.notTranslated : "Tacit starts in it. Setup stays in English." }
                    Rectangle {
                        visible: !parent.langs
                        x: (parent.width - width) / 2; y: Look.px(340); width: Look.px(600); height: Look.px(56); radius: Look.px(18)
                        color: Qt.rgba(1, 1, 1, filter.activeFocus ? 0.10 : 0.06)
                        TextInput { id: filter; x: Look.px(26); anchors.verticalCenter: parent.verticalCenter; width: parent.width - Look.px(52)
                            color: Look.main; font.family: Appearance.font.family.main; font.pixelSize: Look.fs(21); activeFocusOnTab: true
                            cursorDelegate: Rectangle { width: 2; color: Look.light; visible: filter.activeFocus }
                            // the page says "Type a few letters": the keys go here as it opens (they went nowhere)
                            Connections { target: root; function onShownPageChanged() { if (root.shownPage === "keyboards") filter.forceActiveFocus() } } }
                        T { visible: filter.text === ""; x: Look.px(26); anchors.verticalCenter: parent.verticalCenter; text: "Search"; font.pixelSize: Look.fs(20); color: Look.meta }
                    }
                    ListView {
                        id: pick
                        x: (parent.width - width) / 2; y: parent.langs ? Look.px(352) : Look.px(410)
                        width: Look.px(600); height: Look.px(680) - y
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: parent.langs ? backend.languages
                             : backend.layouts.filter(l => filter.text === "" || l.name.toLowerCase().includes(filter.text.toLowerCase()) || l.code.startsWith(filter.text.toLowerCase()))
                        delegate: Item {
                            id: pr
                            required property var modelData
                            readonly property bool on: root.shownPage === "languages" ? modelData.code === setup.language : modelData.code === setup.layout
                            width: pick.width; height: Look.px(48)
                            activeFocusOnTab: true
                            Keys.onReturnPressed: root.pickFrom(modelData)
                            T { x: Look.px(44); anchors.verticalCenter: parent.verticalCenter; text: pr.modelData.name; font.pixelSize: Look.fs(21)
                                font.weight: pr.on || pr.activeFocus ? Font.Medium : Font.Normal; color: pr.on || pr.activeFocus || pma.containsMouse ? Look.main : Look.meta }
                            Rectangle { visible: pr.on; anchors.verticalCenter: parent.verticalCenter; x: Look.px(6); width: Look.px(10); height: width; radius: width / 2; color: Look.light }
                            MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickFrom(pr.modelData) }
                        }
                    }
                }

                // ── the internet
                Item {
                    visible: root.shownPage === "wifi"
                    anchors.fill: parent
                    Headline { text: "Connect to the internet." }
                    Sentence { text: "Tacit uses it to set the clock and look for updates. You can connect later." }
                    // a list longer than its window scrolls (the wheel, a drag, Tab); the window is where four rows and an open
                    // password field fitted above the buttons
                    Flickable {
                        id: netList
                        x: (parent.width - width) / 2; y: Look.px(360); width: Look.px(600); height: Look.px(300)
                        contentWidth: width; contentHeight: netCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: netCol
                            width: Look.px(600)
                            Repeater {
                                // kept by name, so a rescan every 10 s keeps the row (and the password being typed in it)
                                model: ScriptModel { values: backend.wifi; objectProp: "ssid" }
                                Column {
                                    id: net
                                    required property var modelData
                                    readonly property bool on: modelData.ssid === setup.network
                                    width: Look.px(600)
                                    onOnChanged: if (on) root.reveal(net)
                                    onHeightChanged: if (on) root.reveal(net)
                                    Item {
                                        id: nrow
                                        width: Look.px(600); height: Look.px(52)
                                        activeFocusOnTab: true
                                        Keys.onReturnPressed: root.pickNetwork(net.modelData)
                                        onActiveFocusChanged: if (activeFocus) root.reveal(nrow)
                                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; iconSize: Look.fs(24)
                                            text: net.modelData.signal > 66 ? "wifi" : net.modelData.signal > 33 ? "wifi_2_bar" : "wifi_1_bar"; color: net.on ? Look.main : Look.meta }
                                        T { x: Look.px(44); anchors.verticalCenter: parent.verticalCenter; text: net.modelData.ssid; font.pixelSize: Look.fs(22)
                                            font.weight: net.on || parent.activeFocus ? Font.DemiBold : Font.Normal; color: net.on || parent.activeFocus || nma.containsMouse ? Look.main : Look.meta }
                                        T { visible: net.modelData.inUse; anchors.right: parent.right; anchors.rightMargin: Look.px(20); anchors.verticalCenter: parent.verticalCenter
                                            text: "Connected"; font.pixelSize: Look.fs(16); color: Look.sec }
                                        MaterialSymbol { visible: net.modelData.secure && !net.modelData.inUse; anchors.right: parent.right; anchors.rightMargin: Look.px(20); anchors.verticalCenter: parent.verticalCenter
                                            text: "lock"; iconSize: Look.fs(18); color: Look.meta }
                                        MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickNetwork(net.modelData) }
                                    }
                                    Loader {
                                        active: net.on && net.modelData.secure && !net.modelData.inUse
                                        visible: active
                                        sourceComponent: Column {
                                            width: Look.px(600)
                                            Field {
                                                id: pwField
                                                width: Look.px(600)
                                                label: `Password for ${net.modelData.ssid}`
                                                secret: true
                                                layout: setup.kbTag
                                                error: setup.joinError
                                                onAccepted: root.forward()
                                                Component.onCompleted: { root.pwFieldRef = pwField; pwField.focusIn(); }
                                            }
                                            Item { width: 1; height: Look.px(14) }
                                        }
                                    }
                                }
                            }
                            T { visible: backend.wired || backend.wifi.length === 0; text: backend.wired ? "Connected by cable." : "No networks found. You can connect later."; font.pixelSize: Look.fs(19); color: Look.sec }
                            // a network that is not in the list (a hidden one, or one out of the scan's reach): its name and password
                            Item {
                                id: orow
                                width: Look.px(600); height: Look.px(52)
                                activeFocusOnTab: true
                                Keys.onReturnPressed: root.pickOther()
                                onActiveFocusChanged: if (activeFocus) root.reveal(orow)
                                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; iconSize: Look.fs(24); text: "add"; color: setup.otherNet ? Look.main : Look.meta }
                                T { x: Look.px(44); anchors.verticalCenter: parent.verticalCenter; text: "Other network…"; font.pixelSize: Look.fs(22)
                                    font.weight: setup.otherNet || orow.activeFocus ? Font.DemiBold : Font.Normal; color: setup.otherNet || orow.activeFocus || oma2.containsMouse ? Look.main : Look.meta }
                                MouseArea { id: oma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickOther() }
                            }
                            Column {
                                id: otherForm
                                visible: setup.otherNet
                                width: Look.px(600)
                                onHeightChanged: if (visible) root.reveal(otherForm)
                                Field { id: otherName; width: Look.px(600); label: "Network name"; onAccepted: otherPass.focusIn() }
                                Item { width: 1; height: Look.px(8) }
                                Field { id: otherPass; width: Look.px(600); label: "Password (if it has one)"; secret: true; layout: setup.kbTag
                                    error: setup.joinError; onAccepted: root.forward() }
                                Item { width: 1; height: Look.px(14) }
                            }
                        }
                    }
                    // while it joins (up to 45 s the button is grey and nothing else moved), and why it did not: the
                    // error is drawn in the password field, which an open network has none of
                    T { visible: setup.joining || (setup.joinError !== "" && !root.pwFieldShown)
                        x: netList.x + Look.px(44); y: netList.y + netList.height + Look.px(8); width: Look.px(556); wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: setup.joining ? `Connecting to ${setup.joinName}…` : setup.joinError; font.pixelSize: Look.fs(19); color: setup.joining ? Look.sec : Look.light }
                }

                // ── where Tacit goes
                Item {
                    id: wherePage
                    visible: root.shownPage === "where"
                    anchors.fill: parent
                    // where the page ends, for the buttons below it to keep clear of (they move down for Larger text); not
                    // "bottom", which Item has as a FINAL property and Setup would not load
                    readonly property real endY: Math.max(whereCol.y + whereCol.height, diskLinks.visible ? diskLinks.y + diskLinks.height : 0)
                    // "looking" until the disks have been read: it said "no disk" while they were still being read
                    readonly property string c: backend.disksRead ? (backend.disk.case ?? "none") : "looking"
                    readonly property bool room: backend.plan?.room ?? false
                    readonly property bool locked: c === "bitlocker" || c === "asleep"
                    readonly property string size: `${Math.round((backend.disk.size ?? 0) / 1e9)} GB`
                    // why "next to" is not offered, where the sentence does not already say (setupd's words)
                    readonly property string noNext: (backend.disk.noNext ?? "") === "" ? ""
                        : ` ${root.other === "it" ? "Next to what is on it" : `Next to ${root.other}`} is not possible: ${backend.disk.noNext}.`
                    Headline {
                        text: parent.c === "looking" ? "Looking at the disks…"
                            : parent.c === "choose" ? "Which disk should Tacit go on?"
                            : parent.c === "nouefi" ? "Tacit needs UEFI."
                            : parent.c === "bitlocker" ? "Windows is locked."
                            : parent.c === "asleep" && backend.disk.why === "check" ? "Windows has a disk check waiting."
                            : parent.c === "asleep" && backend.disk.why === "other" ? "Tacit can't read the Windows disk yet."
                            : parent.c === "asleep" ? "Windows didn't shut down fully."
                            : parent.c === "windows" && !parent.room && backend.plan ? "There is no room next to Windows."
                            : parent.c === "none" ? "There is no disk to install on."
                            : parent.c === "empty" ? "Tacit will use the whole disk."
                            : "Where should Tacit go?"
                    }
                    Sentence {
                        id: whereSentence
                        text: parent.c === "looking" ? "Tacit is reading what is on each disk inside this computer. With several drives this can take a minute. Nothing on them is changed."
                            : parent.c === "choose" ? "This computer has more than one disk with files on it. Choose the one for Tacit. The others stay as they are."
                            : parent.c === "nouefi" ? "This computer started the USB stick in the older BIOS mode, so Tacit can't be installed. Restart, and start the stick from the UEFI entry in the boot menu."
                            : parent.c === "bitlocker" ? "This disk is locked with BitLocker, so Tacit can't make room next to Windows. Start Windows, turn BitLocker off in Settings, then start from this USB stick again."
                            : parent.c === "asleep" && backend.disk.why === "check" ? "Windows marked its disk to be checked, so Tacit can't make room next to it yet. Start Windows and restart it twice so the check runs, then shut it down and start from this USB stick again."
                            : parent.c === "asleep" && backend.disk.why === "other" ? `Tacit can't make room next to Windows until it can read the disk safely. Start Windows, restart it, shut it down, then start from this USB stick again. The disk said: “${backend.disk.says}”`
                            : parent.c === "asleep" ? "Windows is paused rather than shut down, so Tacit can't make room next to it yet. Start Windows, hold Shift while you choose Shut down, then start from this USB stick again."
                            : parent.c === "windows" && backend.plan && !parent.room && backend.disk.used == null ? `Setup could not read how much of the ${parent.size} disk Windows uses, so it can't make room next to it. You can install instead of Windows.`
                            : parent.c === "windows" && backend.plan && !parent.room ? `Windows and your files use ${Math.round(backend.disk.used / 1e9)} GB of the ${parent.size} disk. Free up space in Windows, or install instead of Windows.`
                            : parent.c === "windows" && backend.plan && backend.disk.used != null ? `This computer has Windows on its ${parent.size} disk, with ${Math.round(backend.disk.used / 1e9)} GB in use.`
                            : parent.c === "windows" ? `This computer has Windows on its ${parent.size} disk.${parent.noNext}`
                            : parent.c === "linux" ? `This computer has Linux on its ${parent.size} disk.${parent.noNext}`
                            : parent.c === "empty" && root.windowsElsewhere ? `This ${parent.size} disk is empty. Windows, on the other disk, stays as it is.`
                            : parent.c === "empty" ? `This computer's ${parent.size} disk is empty.`
                            : parent.c === "none" ? "Tacit found no disk inside this computer. The USB stick it runs from can't be used."
                            : `This computer's disk is ${parent.size}.${parent.noNext}`
                    }
                    Column {
                        id: whereCol
                        // under the sentence when Larger text makes it run past the usual line
                        x: (parent.width - width) / 2; y: Math.max(Look.px(360), whereSentence.y + whereSentence.height + Look.px(32)); width: Look.px(600)
                        spacing: Look.px(30)
                        Choice {
                            visible: parent.parent.room
                            width: Look.px(600)
                            name: root.other === "it" ? "Next to what is on it" : `Next to ${root.other}`; on: setup.place === "next"
                            detail: (root.other === "Windows" ? "Your Windows files stay as they are. " : "Everything on this disk stays as it is. ")
                                    + (backend.plan?.windowsKeeps ? `Windows keeps ${Math.round(backend.plan.windowsKeeps / 1e9)} GB, Tacit gets ${Math.round(backend.plan.tacitGets / 1e9)} GB.`
                                                                  : `Tacit uses the ${Math.round((backend.plan?.tacitGets ?? 0) / 1e9)} GB of free space.`)
                                    + (root.other === "it" ? "" : ` To use ${root.other}, hold the Space bar while the computer starts.`)
                            onPicked: setup.place = "next"
                        }
                        // a Windows that has to be started first (locked, paused, due a check): the safe way, and the one chosen
                        Choice {
                            visible: parent.parent.locked
                            width: Look.px(600)
                            name: "Start Windows first"; on: setup.place !== "instead"
                            detail: "Your Windows files stay as they are. When the screen goes dark, take out the USB stick."
                            onPicked: setup.place = "next"
                        }
                        // one way only (an empty disk) is no choice: the headline says it. A locked Windows can be erased too,
                        // which needs nothing read from it (the erase page asks once more)
                        Choice {
                            visible: !["none", "looking", "choose", "nouefi", "empty"].includes(parent.parent.c)
                            width: Look.px(600)
                            name: root.isWindows(backend.disk) ? "Instead of Windows" : "Instead of what is on it"
                            on: setup.place === "instead" || (!parent.parent.room && !parent.parent.locked)
                            detail: root.isWindows(backend.disk) ? "Windows and every file on this disk will be erased." : "Everything on this disk will be erased."
                            onPicked: setup.place = "instead"
                        }
                        T {
                            visible: !(backend.power.ac ?? true) && !["none", "looking", "choose", "nouefi"].includes(parent.parent.c) && (!parent.parent.locked || setup.place === "instead")
                            width: Look.px(600); wrapMode: Text.Wrap
                            horizontalAlignment: parent.parent.c === "empty" ? Text.AlignHCenter : Text.AlignLeft
                            text: "Plug in the charger. Installing takes about 10 minutes."
                            font.pixelSize: Look.fs(17); color: Look.sec
                        }
                    }

                    // with more than one disk inside: which one, as the first page names the keyboard; and for people who set up
                    // their own partitions, their own way
                    Row {
                        id: diskLinks
                        x: (parent.width - width) / 2; y: Math.max(Look.px(646), whereCol.y + whereCol.height + Look.px(20))
                        spacing: Look.px(40)
                        visible: backend.disksRead && parent.c !== "nouefi"
                        Link { visible: backend.disks.length > 1 && parent.parent.c !== "choose"; bright: true
                            text: `Disk: ${root.diskName(backend.disk)}  ›`; onClicked: setup.go("disks") }
                        Link { visible: backend.parts.length > 0; text: "Choose partitions myself  ›"; onClicked: setup.go("parts") }
                    }
                }

                // ── the disks inside, to choose from (Setup took the biggest until 2026-10-18)
                Item {
                    visible: root.shownPage === "disks"
                    anchors.fill: parent
                    Headline { text: "Choose a disk." }
                    Sentence { text: "Tacit goes on the one you choose. Nothing changes until you install." }
                    Column {
                        x: (parent.width - width) / 2; y: Look.px(352); width: Look.px(600)
                        Repeater {
                            model: backend.disks
                            delegate: Item {
                                id: dr
                                required property var modelData
                                readonly property bool on: modelData.name === backend.disk.name
                                width: Look.px(600); height: Look.px(56)
                                activeFocusOnTab: true
                                Keys.onReturnPressed: root.pickDisk(modelData)
                                T { x: Look.px(44); anchors.verticalCenter: parent.verticalCenter; text: root.diskName(dr.modelData); font.pixelSize: Look.fs(21)
                                    font.weight: dr.on || dr.activeFocus ? Font.Medium : Font.Normal; color: dr.on || dr.activeFocus || dma.containsMouse ? Look.main : Look.meta }
                                T { anchors.right: parent.right; anchors.rightMargin: Look.px(20); anchors.verticalCenter: parent.verticalCenter
                                    text: root.diskHolds(dr.modelData); font.pixelSize: Look.fs(16); color: Look.sec }
                                Rectangle { visible: dr.on; anchors.verticalCenter: parent.verticalCenter; x: Look.px(6); width: Look.px(10); height: width; radius: width / 2; color: Look.light }
                                MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickDisk(dr.modelData) }
                            }
                        }
                    }
                }

                // ── "Choose partitions myself": for people who set up their own. Tacit's partition is erased, the EFI one is shared,
                // a boot partition (when the EFI one is small) is erased; the installer checks each again before anything changes
                Item {
                    visible: root.shownPage === "parts"
                    anchors.fill: parent
                    Headline { text: "Choose partitions." }
                    Sentence { text: "Tacit is copied onto the partition you choose for it, and that partition is erased. The others stay as they are." }
                    Flickable {
                        id: partFlick
                        x: (parent.width - width) / 2; y: Look.px(345); width: Look.px(720)
                        height: Math.min(contentHeight, Look.px(328))
                        contentHeight: partCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        // more partitions than fit: the bar says there is more below
                        ScrollBar.vertical: ScrollBar { policy: partFlick.contentHeight > partFlick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                        Column {
                            id: partCol
                            width: parent.width
                            spacing: Look.px(4)
                            PartHead { text: "Tacit goes on (erased)" }
                            Repeater {
                                model: backend.parts.filter(p => !p.esp && p.size >= 32e9 && p.name !== setup.partBoot)
                                delegate: PartRow { required property var modelData; part: modelData; on: setup.partRoot === modelData.name; onPicked: root.pickRoot(modelData) }
                            }
                            PartNone { visible: !backend.parts.some(p => !p.esp && p.size >= 32e9); text: "No partition of 32 GB or more. Make one with the partition editor below." }
                            PartHead { text: "EFI partition (kept)" }
                            Repeater {
                                model: backend.parts.filter(p => p.esp)
                                delegate: PartRow { required property var modelData; part: modelData; on: setup.partEfi === modelData.name; onPicked: setup.partEfi = modelData.name }
                            }
                            PartNone { visible: !backend.parts.some(p => p.esp); text: "No EFI partition. Make one of 300 MB or more (FAT32, the esp flag) with the partition editor." }
                            // Tacit's start-up files need about 250 MB on the EFI partition: a smaller one needs a boot partition too
                            PartHead { visible: root.efiSmall; text: "Boot partition (erased)" }
                            PartNone { visible: root.efiSmall; text: "This EFI partition is small, so Tacit's start-up files need a partition of their own, 500 MB or more, on the same disk."
                                + (root.bootChoices.length ? "" : " Make one with the partition editor below.") }
                            Repeater {
                                model: root.efiSmall ? root.bootChoices : []
                                delegate: PartRow { required property var modelData; part: modelData; on: setup.partBoot === modelData.name; onPicked: setup.partBoot = modelData.name }
                            }
                        }
                    }
                    Link { x: (parent.width - width) / 2; y: Look.px(680); bright: true
                        text: backend.editing ? "The partition editor is open…" : "Make or resize partitions  ›"
                        onClicked: if (!backend.editing) { backend.editing = true; backend.send({ op: "editor" }); } }
                }

                // ── the partitions, said once more
                Item {
                    visible: root.shownPage === "eraseparts"
                    anchors.fill: parent
                    readonly property var rootPart: backend.parts.find(p => p.name === setup.partRoot) ?? ({})
                    readonly property var bootPart: backend.parts.find(p => p.name === setup.partBoot) ?? null
                    Headline { text: parent.bootPart ? "Erase these partitions?" : "Erase this partition?" }
                    Sentence { text: `Everything on ${root.partName(parent.rootPart)}${parent.bootPart ? " and " + root.partName(parent.bootPart) : ""} will be erased. This can't be undone. The other partitions stay as they are.` }
                    Column {
                        x: (parent.width - width) / 2; y: Look.px(360); width: Look.px(640); spacing: Look.px(10)
                        T { width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Look.fs(19); color: Look.main
                            text: `Tacit: ${root.partName(parent.parent.rootPart)}, ${root.partHolds(parent.parent.rootPart)}` }
                        T { width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Look.fs(17); color: Look.sec
                            text: `Start-up: ${setup.partEfi.replace("/dev/", "")}, kept` + (parent.parent.bootPart ? ` · boot files: ${root.partName(parent.parent.bootPart)}, erased` : "") }
                    }
                }

                // ── erase, said once more
                Item {
                    visible: root.shownPage === "erase"
                    anchors.fill: parent
                    Headline { text: "Erase this disk?" }
                    Sentence { text: (root.isWindows(backend.disk) ? "Windows and every file" : "Everything") + " on this disk will be erased. This can't be undone." }
                    Column {
                        x: (parent.width - width) / 2; y: Look.px(360); width: Look.px(600); spacing: Look.px(10)
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: `${backend.disk.model ?? "This disk"} · ${Math.round((backend.disk.size ?? 0) / 1e9)} GB`; font.pixelSize: Look.fs(22) }
                        T { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; font.pixelSize: Look.fs(18); color: Look.sec
                            text: root.isWindows(backend.disk) ? "To keep any files, restart into Windows and copy them to a USB drive first." : "To keep any files, copy them somewhere else first." }
                    }
                }

                // ── you
                Item {
                    visible: root.shownPage === "you"
                    anchors.fill: parent
                    Headline { text: "Who will use this computer?" }
                    Sentence { text: "You can add other people later." }
                    Column {
                        x: (parent.width - width) / 2; y: Look.px(360); width: Look.px(600)
                        Row {
                            spacing: (Look.px(600) - 6 * Look.px(58)) / 5
                            Repeater {
                                model: ["dune", "terracotta", "moss", "copper", "basalt", "marble"]
                                Planet { required property string modelData; name: modelData; on: setup.picture === modelData; onPicked: setup.picture = modelData }
                            }
                        }
                        Item { width: 1; height: Look.px(12) }
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: "Your picture, shown when the computer starts"; font.pixelSize: Look.fs(16); color: Look.meta }
                        Item { width: 1; height: Look.px(22) }
                        Field { id: nameField; width: Look.px(600); label: "Your name"; onAccepted: passField.focusIn() }
                        Item { width: 1; height: Look.px(8) }
                        Field { id: passField; width: Look.px(600); label: "Password for this computer"; secret: true; layout: setup.kbTag; onAccepted: againField.focusIn() }
                        Item { width: 1; height: Look.px(8) }
                        Field {
                            id: againField; width: Look.px(600); label: "Type it again"; secret: true; layout: setup.kbTag
                            error: text !== "" && passField.text !== "" && text !== passField.text && text.length >= passField.text.length ? "The two passwords are different." : ""
                            onAccepted: root.forward()
                        }
                    }
                }

                // "Send a report when something breaks?" is not asked while nothing reads the answer (no reporter yet):
                // once one exists, its page comes back here, after "you", with tacit-install writing the answer again

                // ── almost, ready, stopped
                Item {
                    visible: ["almost", "ready", "failed"].includes(root.shownPage)
                    anchors.fill: parent
                    Headline { text: root.shownPage === "almost" ? "Almost done." : root.shownPage === "ready" ? "Tacit is ready." : "Tacit didn't finish installing." }
                    // what stopped it, in the installer's words (a tool's failure as its last line), and where all of it is
                    Column {
                        visible: root.shownPage === "failed"
                        x: (parent.width - width) / 2; y: Look.px(430); width: Look.px(780); spacing: Look.px(8)
                        T {
                            visible: setup.installReason !== ""
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            text: `What stopped it: ${setup.installReason}.`
                            font.pixelSize: Look.fs(16); color: Look.meta
                        }
                        T {
                            visible: !backend.practice
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: "The full record is in /tmp/tacit-install.log."
                            font.pixelSize: Look.fs(16); color: Look.meta
                        }
                    }
                    Sentence {
                        text: root.shownPage === "almost" ? "Tacit is finishing on its own. Keep the computer on and the USB stick in."
                            : root.shownPage === "ready" ? ("Restart now. When the screen goes dark, take out the USB stick." + (setup.place === "next" && root.other !== "it" ? ` To use ${root.other}, hold the Space bar while the computer starts.`
                                                                                                                                : setup.otherSystem !== "" ? ` To use ${setup.otherSystem}, hold the Space bar while the computer starts.` : "")
                                + (setup.place === "next" || setup.place === "manual" ? " If it starts the old system instead, open the boot menu (often F12 or Esc) and choose Tacit." : "") + root.a11yNote)
                            : setup.installUntouched ? "Nothing on the disk was changed, so the computer starts as before. You can try again."
                            : setup.place === "next" ? `Tacit stopped partway. ${root.other === "it" ? "What was on the disk" : root.other} should start as before${root.other === "Windows" ? ", after it checks its disk" : ""}. You can try again.`
                            : "Tacit stopped partway, after the disk was erased. You can try again."
                    }
                }
            }

            // ── the way forward: the main action's top at 720; the other way to its left, the two centred as a pair (the
            // main action alone at the centre left the pair off it, 2026-10-17)
            Act {
                id: primary
                visible: root.shownPage !== "almost" && root.shownPage !== "languages" && root.shownPage !== "keyboards" && root.shownPage !== "disks"
                x: (stage.width - width + (otherWay.visible ? otherWay.width + Look.px(18) : 0)) / 2; y: Math.max(Look.px(720), root.flowBottom + Look.px(40))
                text: root.primaryText
                later: root.primaryLater
                onClicked: root.forward()
            }
            Quiet {
                id: otherWay
                // on the stick's first screen: Tacit as it is, without installing it (Discord 2026-10-24: people did not
                // know they could, and Setup covered the desktop)
                readonly property bool tryFirst: root.shownPage === "welcome" && !backend.practice && !root.windowed
                visible: tryFirst || ["wifi", "where", "erase", "parts", "eraseparts"].includes(root.shownPage)
                x: primary.x - width - Look.px(18); y: primary.y + Look.px(4)
                text: tryFirst ? "Try Tacit first" : root.shownPage === "wifi" ? "Not now" : "Back"
                onClicked: tryFirst ? root.tryTacitFirst() : root.shownPage === "wifi" ? setup.go("where") : setup.back()
            }
            Quiet {
                visible: root.shownPage === "languages" || root.shownPage === "keyboards" || root.shownPage === "disks"
                x: (stage.width - width) / 2; y: Look.px(724)
                text: "Back"
                onClicked: setup.back()
            }

            // accessibility, before any language is chosen
            Item {
                id: a11y
                property bool open: false
                x: stage.width - Look.px(100); y: Look.px(48); width: Look.px(52); height: width
                activeFocusOnTab: true
                Keys.onReturnPressed: open = !open
                Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(1, 1, 1, a11y.activeFocus || a11y.open ? 0.09 : ama.containsMouse ? 0.05 : 0); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.42) }
                Text { anchors.centerIn: parent; text: "accessibility_new"; font.family: "Material Symbols Rounded"; font.pixelSize: Look.fs(28); color: Look.sec }
                MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: a11y.open = !a11y.open }
            }
            Column {
                visible: a11y.open
                x: stage.width - Look.px(48) - width; y: Look.px(116); width: Look.px(300)
                spacing: Look.px(4)
                Repeater {
                    model: [{ t: "Larger text", on: Look.text > 1, f: () => Look.text = Look.text > 1 ? 1 : 1.25 },
                            { t: "Less motion", on: Look.lessMotion, f: () => Look.lessMotion = !Look.lessMotion }]
                    Item {
                        id: opt
                        required property var modelData
                        width: Look.px(300); height: Look.px(48)
                        activeFocusOnTab: true
                        Keys.onReturnPressed: modelData.f()
                        T { anchors.verticalCenter: parent.verticalCenter; text: opt.modelData.t; font.pixelSize: Look.fs(19); color: opt.activeFocus || oma.containsMouse ? Look.main : Look.sec }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: Look.px(44); height: Look.px(26); radius: height / 2; color: "transparent"; border.width: 1
                            border.color: opt.modelData.on ? Qt.rgba(0.95, 0.77, 0.60, 0.85) : Qt.rgba(1, 1, 1, 0.42)
                            Rectangle { x: opt.modelData.on ? parent.width - width - Look.px(4) : Look.px(4); anchors.verticalCenter: parent.verticalCenter
                                width: Look.px(18); height: width; radius: width / 2; color: opt.modelData.on ? Look.light : Look.meta
                                Behavior on x { Anim { type: Anim.FastSpatial } } }
                        }
                        MouseArea { id: oma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: opt.modelData.f() }
                    }
                }
            }
        }
    }

    // ── small parts used by the pages above
    component Headline: T {
        x: (parent.width - width) / 2; y: Look.px(200)
        font.family: Look.display; font.pixelSize: Look.fs(52); font.weight: Font.Light; font.variableAxes: { "wght": 300 }; font.letterSpacing: 0.5
    }
    component Sentence: T {
        x: (parent.width - width) / 2; y: Look.px(282); width: Look.px(780)
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; lineHeight: 1.3
        color: Look.sec
    }
    function partName(p) {
        if (!p || !p.name) return "";
        const sz = (p.size ?? 0) >= 1e9 ? `${Math.round(p.size / 1e9)} GB` : `${Math.round((p.size ?? 0) / 1e6)} MB`;
        return `${p.name.replace("/dev/", "")} · ${sz}`;
    }
    readonly property bool efiSmall: (backend.parts.find(p => p.name === setup.partEfi)?.size ?? 1e12) < 3e8
    function partHolds(p) {
        if (!p || !p.name) return "";
        const f = ({ ntfs: "NTFS", vfat: "FAT", ext4: "ext4", btrfs: "Btrfs", xfs: "XFS", BitLocker: "BitLocker", swap: "swap" })[p.fstype] ?? (p.fstype || "empty");
        return p.label ? `${f}, ${p.label}` : f;
    }
    function pickRoot(p) {
        setup.partRoot = p.name;
        // the EFI partition on the same disk, when there is one and none was chosen on that disk
        const same = backend.parts.find(e => e.esp && e.disk === p.disk);
        if (same && (setup.partEfi === "" || backend.parts.find(e => e.name === setup.partEfi)?.disk !== p.disk)) setup.partEfi = same.name;
    }
    // what was chosen goes when the editor took it away
    function keepParts() {
        const has = n => backend.parts.some(p => p.name === n);
        if (setup.partRoot && !has(setup.partRoot)) setup.partRoot = "";
        if (setup.partEfi && !has(setup.partEfi)) setup.partEfi = "";
        if (setup.partBoot && !has(setup.partBoot)) setup.partBoot = "";
        if (setup.partEfi === "") setup.partEfi = backend.parts.find(p => p.esp)?.name ?? "";
    }
    onEfiSmallChanged: if (!efiSmall) setup.partBoot = ""
    // the partition editor has the screen while it is open (over it, Setup left full screen and sat on top of it as a
    // card); Setup comes back when it closes
    Connections {
        target: backend
        function onEditingChanged() { if (root.windowed) return; if (backend.editing) root.hide(); else root.showFullScreen(); }
    }
    // the start-up loader finds a boot partition only on the disk it started from, the EFI partition's
    readonly property string efiDisk: backend.parts.find(p => p.name === setup.partEfi)?.disk ?? ""
    readonly property var bootChoices: backend.parts.filter(p => !p.esp && p.disk === efiDisk && p.size >= 5e8 && p.size < 32e9 && p.name !== setup.partRoot)
    onEfiDiskChanged: if (setup.partBoot && backend.parts.find(p => p.name === setup.partBoot)?.disk !== efiDisk) setup.partBoot = ""
    component PartHead: T { width: Look.px(720); topPadding: Look.px(10); bottomPadding: Look.px(2); font.pixelSize: Look.fs(15); color: Look.meta }
    component PartNone: T { width: Look.px(720); leftPadding: Look.px(44); wrapMode: Text.Wrap; font.pixelSize: Look.fs(16); color: Look.sec }
    component PartRow: Item {
        id: pr
        property var part
        property bool on: false
        signal picked()
        width: Look.px(720); height: Look.px(40)
        activeFocusOnTab: true
        Keys.onReturnPressed: pr.picked()
        Rectangle { visible: pr.on; anchors.verticalCenter: parent.verticalCenter; x: Look.px(6); width: Look.px(10); height: width; radius: width / 2; color: Look.light }
        T { x: Look.px(44); anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Look.fs(19)
            text: pr.part.name ? `${pr.part.model ?? ""}  ${root.partName(pr.part)}` : (pr.part.label ?? "")
            font.weight: pr.on || pr.activeFocus ? Font.Medium : Font.Normal; color: pr.on || pr.activeFocus || pma.containsMouse ? Look.main : Look.meta }
        T { anchors.right: parent.right; anchors.rightMargin: Look.px(20); anchors.verticalCenter: parent.verticalCenter
            text: pr.part.name ? root.partHolds(pr.part) : "The EFI partition holds the start-up files"; font.pixelSize: Look.fs(16); color: Look.sec }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pr.picked() }
    }
    component Link: Item {
        id: lk
        property string text
        property string glyph: ""
        property bool bright: false
        signal clicked()
        width: lrow.width; height: Look.px(32)
        activeFocusOnTab: true
        Keys.onReturnPressed: clicked()
        Row {
            id: lrow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Look.px(8)
            MaterialSymbol { visible: lk.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; text: lk.glyph; iconSize: Look.fs(20); color: lt.color }
            T { id: lt; anchors.verticalCenter: parent.verticalCenter; text: lk.text; font.pixelSize: Look.fs(17)
                font.weight: lk.activeFocus ? Font.Medium : Font.Normal; color: lk.activeFocus || lkma.containsMouse ? Look.main : lk.bright ? Look.sec : Look.meta }
        }
        MouseArea { id: lkma; anchors.fill: parent; anchors.margins: -Look.px(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lk.clicked() }
    }

    // ── what the buttons do
    readonly property string notTranslated: "Tacit isn't in this language yet, so it starts in English."
    property Item pwFieldRef: null
    // the bottom of what the page above the buttons holds, 0 where it is short; only the disk page can grow past them
    readonly property real flowBottom: shownPage === "where" ? wherePage.endY : 0
    // the accessibility button's choices are Setup's own: the installed desktop starts at normal size and motion
    readonly property string a11yNote: {
        const on = [Look.text > 1 ? "Text size" : "", Look.lessMotion ? "Reduce motion" : ""].filter(t => t !== "");
        return on.length === 0 ? "" : ` What you chose with the accessibility button is not kept: Settings, under Accessibility, has ${on.join(" and ")}.`;
    }
    // a password field is on the page: the chosen network asks for one, or its name is being typed in
    readonly property bool pwFieldShown: { const n = backend.wifi.find(w => w.ssid === setup.network); return setup.otherNet || (n !== undefined && n.secure && !n.inUse); }
    // the system Tacit goes next to
    readonly property string other: backend.disk.case === "windows" ? "Windows" : backend.disk.case === "linux" ? "Linux" : "it"
    readonly property string primaryText: ({
        welcome: "Continue", wifi: "Continue", erase: "Erase and install", parts: "Continue", eraseparts: "Erase and install", you: "Continue", ready: "Restart", failed: "Try again"
    })[shownPage] ?? (shownPage === "where" ? (!backend.disksRead ? "Continue"
                                                : backend.disk.case === "choose" ? "Choose a disk"
                                                : ["bitlocker", "asleep"].includes(backend.disk.case) ? (setup.place === "instead" ? "Continue" : "Restart into Windows")
                                                : backend.disk.case === "none" ? "Turn off"
                                                : backend.disk.case === "nouefi" ? "Restart"
                                                : (backend.plan?.room ?? false) && setup.place === "next" ? (root.other === "it" ? "Install" : `Install next to ${root.other}`)
                                                : backend.disk.case === "empty" ? "Install" : "Continue") : "Continue")
    readonly property bool primaryLater: shownPage === "you" ? (nameField.text.trim() === "" || passField.text === "" || againField.text !== passField.text)
                                       : shownPage === "wifi" ? setup.joining : shownPage === "where" ? !backend.disksRead
                                       : shownPage === "parts" ? (setup.partRoot === "" || setup.partEfi === "" || backend.editing || (root.efiSmall && setup.partBoot === ""))
                                       : shownPage === "welcome" ? !backend.ready : false
    // a language sets the keyboard only when it is a different one: tapping the language already shown (English, first
    // on the page) left the keyboard of the computer for the UK's
    function pickLanguage(l) { const same = l.code === setup.language; setup.language = l.code; if (!setup.layoutPicked && !same) setup.layout = l.layout; }
    function pickFrom(item) {
        if (shownPage === "languages") { const same = item.code === setup.language; setup.language = item.code; if (!setup.layoutPicked && !same) setup.layout = item.layout; }
        else { setup.layout = item.code; setup.layoutPicked = true; }
        setup.back();
    }
    function pickNetwork(n) { setup.otherNet = false; setup.network = n.ssid; setup.joinError = ""; }
    function pickOther() { setup.otherNet = true; setup.network = ""; setup.joinError = ""; Qt.callLater(() => otherName.focusIn()); }
    // scroll the Wi-Fi list so that an item in it shows (Tab moves down a list longer than its window); a taller one shows its top
    function reveal(item) {
        const top = item.mapToItem(netList.contentItem, 0, 0).y;
        if (top < netList.contentY) netList.contentY = top;
        else if (top + item.height > netList.contentY + netList.height) netList.contentY = Math.max(0, Math.min(top, top + item.height - netList.height));
    }
    // Windows is on the disk, whether Setup can make room next to it or not
    function isWindows(d) { return ["windows", "asleep", "bitlocker"].includes(d.case); }
    // a disk in words: its name and size, and what is on it
    function diskName(d) { return `${d.model ?? "Disk"} · ${Math.round((d.size ?? 0) / 1e9)} GB`; }
    function diskHolds(d) {
        return ({ windows: "Windows", asleep: "Windows", bitlocker: "Windows, with BitLocker", linux: "Linux", empty: "Empty" })[d.case] ?? "Other files";
    }
    readonly property bool windowsElsewhere: backend.disks.some(d => d.name !== backend.disk.name && root.isWindows(d))
    function pickDisk(d) {
        backend.disk = d; backend.plan = d.plan; setup.place = "next";
        backend.send({ op: "disk", name: d.name });
        setup.back();
    }
    function forward() {
        switch (shownPage) {
        case "welcome": setup.go("wifi"); break;
        case "wifi": {
            if (setup.joining) break;
            if (setup.otherNet) {
                const ssid = otherName.text.trim();
                if (ssid === "" || setup.joined === ssid) { setup.go("where"); break; }
                setup.joining = true; setup.joinName = ssid; setup.joinError = "";
                backend.send({ op: "join", ssid: ssid, secure: otherPass.text !== "", hidden: true, password: otherPass.text });
                break;
            }
            const n = backend.wifi.find(w => w.ssid === setup.network);
            if (!n || n.inUse || setup.joined === n.ssid) { setup.go("where"); break; }
            setup.joining = true; setup.joinName = n.ssid; setup.joinError = "";
            backend.send({ op: "join", ssid: n.ssid, secure: n.secure, password: root.pwFieldRef?.text ?? "" });
            break;
        }
        case "where": {
            if (!backend.disksRead) break;      // the disks are still being read
            const c = backend.disk.case ?? "none";
            if (c === "choose") { setup.go("disks"); break; }
            // "Restart into Windows" and "Turn off" do that on the stick (they only closed Setup there)
            if (c === "bitlocker" || c === "asleep" || c === "nouefi" || c === "none") {
                if (c !== "none" && setup.place === "instead") { setup.go("erase"); break; }
                if (backend.practice) root.endPractice();
                else backend.send({ op: c === "none" ? "off" : "restart", windows: c !== "none" && c !== "nouefi" });
                break;
            }
            if ((backend.plan?.room ?? false) && setup.place === "next") setup.startInstall();
            else if (c === "empty") { setup.place = "instead"; setup.startInstall(); }
            else { setup.place = "instead"; setup.go("erase"); }
            break;
        }
        case "erase": setup.startInstall(); break;
        case "parts": if (!root.primaryLater) setup.go("eraseparts"); break;
        case "eraseparts": setup.startManual(); break;
        case "you": if (!root.primaryLater) root.afterQuestions(); break;
        case "ready": if (backend.practice) root.endPractice(); else backend.send({ op: "restart" }); break;
        // the disks are read again (a failed install may have changed them), and Back and Esc lead on from the page it shows
        case "failed": setup.installState = ""; setup.trail = ["welcome", "wifi"]; setup.page = "where"; backend.send({ op: "disks" }); break;
        }
    }
    function afterQuestions() {
        backend.send({ op: "answers", language: setup.language, layout: setup.kbLayout, network: setup.joined || setup.network,
                       place: setup.place, name: nameField.text.trim(), password: passField.text, picture: setup.picture });
        setup.go(setup.installState === "done" ? "ready" : "almost");
    }
    // Setup steps aside on the stick and says once how to come back: the launcher's Install Tacit (the ISO's
    // tacit-setup.desktop) opens it again
    function tryTacitFirst() {
        Quickshell.execDetached(["notify-send", "-a", "Tacit", "Trying Tacit",
                                 "Nothing is installed. To install it, press Super and open Install Tacit."]);
        Qt.quit();
    }
    function endPractice() { if (root.walk) console.info("WALK end"); Qt.quit(); }

    // ── a scripted walk through the flow (TACIT_SETUP_WALK=1): each step's page, printed, for a quick check
    readonly property bool walk: (Quickshell.env("TACIT_SETUP_WALK") ?? "") === "1"
    property int wi: 0
    Timer {
        interval: 700
        repeat: true
        running: root.walk && backend.ready && backend.disksRead
        onTriggered: {
            const steps = [
                () => root.forward(),                                                        // welcome -> wifi
                () => { setup.network = (backend.wifi.find(w => w.inUse) ?? backend.wifi[0] ?? {}).ssid ?? ""; root.forward(); },
                () => { setup.place = "instead"; root.forward(); },                         // where -> erase
                () => setup.back(),                                                         // erase -> where (back works)
                () => { setup.place = "next"; root.forward(); },                            // where -> you (install starts)
                () => { setup.back(); },                                                    // no way back once installing
                () => { nameField.text = "Abdul"; passField.text = "abc12345"; againField.text = "abc1234"; console.info("WALK later", root.primaryLater); againField.text = "abc12345"; root.forward(); },    // you -> almost
            ];
            console.info("WALK page", setup.page, "install", setup.installState, Math.round(setup.installDone * 100) + "%");
            if (root.wi < steps.length) { steps[root.wi](); root.wi++; }
            else if (setup.page === "ready") { console.info("WALK page ready"); root.forward(); }
        }
    }

    // ── render harness: TACIT_SETUP_RENDER=<dir> draws each page once and saves it
    readonly property string renderDir: Quickshell.env("TACIT_SETUP_RENDER") ?? ""
    property var shots: [["1-welcome", "welcome"], ["1b-languages", "languages"], ["1c-keyboards", "keyboards"], ["2-internet", "wifi"],
                         ["3-where", "where"], ["3c-disks", "disks"], ["3b-erase", "erase"], ["4-you", "you"], ["6-almost", "almost"],
                         ["7-ready", "ready"], ["8-failed", "failed"]]
    property int si: -1
    Timer { id: quitLater; interval: 1500; onTriggered: Qt.quit() }
    Timer {
        id: renderStep
        interval: 2200
        running: root.renderDir !== ""
        onTriggered: {
            if (root.si >= 0) {
                const name = root.shots[root.si][0];     // the grab finishes after si has moved on
                shot.grabToImage(g => g.saveToFile(`${root.renderDir}/setup-${name}.png`));
            }
            root.si++;
            if (root.si >= root.shots.length) { quitLater.start(); return; }
            const pg = root.shots[root.si][1];
            if (pg === "wifi" && backend.wifi.length > 0) { setup.network = backend.wifi.find(w => w.secure && !w.inUse)?.ssid ?? setup.network; }
            if (["you", "almost"].includes(pg)) { setup.installState = "running"; setup.installLeft = 360; }
            if (pg === "you") { nameField.text = "Abdul"; passField.text = "correct horse"; againField.text = "correct hors"; }
            setup.page = pg;
            renderStep.restart();
        }
    }
}
