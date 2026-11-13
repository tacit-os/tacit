pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The screen-share picker (DialogBridge kind "share.pick"), drawn over one monitor. No state of its own
 * beyond the choice: it emits done(result) or cancelled() and the window around it talks to the bridge.
 *
 * Look (dialogs v2, approved 2026-10-04): a plain slab centred over the window of the app that asked, only that
 * window dimmed, one list with live thumbnails, 2 px accent ring on the choice. "Draw a region" is its own step:
 * the screen is the picker, a small bar holds the size, Back and Share.
 *
 * request: { app, monitor, screen: {name,x,y,w,h}, screens: [{name,w,h}], windows: [{id,class,title,address}],
 *            asker: {x,y,w,h} | null  (global layout coordinates), allowToken }
 * result:  { kind: "screen", name } | { kind: "window", id } | { kind: "region", output, x,y,w,h } + token
 */
Item {
    id: root

    property var request: ({})
    // false until the window is mapped; the screen thumbnail is taken before anything is drawn over it
    property bool entered: false
    // a harness can draw its own thumbnails (a Component with `kind` and `row` properties); the real ones are copies
    property Component thumbOverride: null
    property string startStep: "list"

    signal done(var result)
    signal cancelled()

    readonly property var screenInfo: request.screen ?? { name: "", x: 0, y: 0, w: width, h: height }
    readonly property string appName: (request.app ?? "") || prettyApp(request.appClass ?? "")
    readonly property bool allowToken: request.allowToken ?? false
    // the asker's window in this monitor's own coordinates, or null: then the slab is centred on the monitor
    readonly property var askRect: {
        const a = request.asker;
        if (!a) return null;
        return Qt.rect(a.x - screenInfo.x, a.y - screenInfo.y, a.w, a.h);
    }

    // rows of the list: screens, windows; the region row is separate
    readonly property var rows: {
        const out = [];
        const sc = request.screens ?? [];
        sc.forEach((s, i) => {
            const nice = root.screenName(s.name, i);
            out.push({ kind: "screen", key: `screen:${s.name}`, label: sc.length > 1 ? nice : Translation.tr("Whole screen"), meta: sc.length > 1 ? Translation.tr("Whole screen") : "", name: s.name, cls: "" });
        });
        for (const w of (request.windows ?? [])) {
            const app = root.prettyApp(w.class);
            const label = w.title.length > 0 ? w.title : app;
            out.push({ kind: "window", key: `window:${w.id}`, label: label, meta: app.toLowerCase() === label.toLowerCase() ? "" : app, id: w.id, address: w.address ?? "", cls: w.class });
        }
        return out;
    }
    property int index: 0
    // a second ask in the same sheet starts from the top again
    property bool ready: false
    Component.onCompleted: root.ready = true
    onRequestChanged: {
        if (!root.ready) return;
        root.index = 0; root.token = false; root.step = "list"; root.region = Qt.rect(0, 0, 0, 0);
    }
    property bool token: false
    property string step: startStep   // "list" | "region"

    // the region being drawn, in monitor coordinates
    property rect region: Qt.rect(0, 0, 0, 0)
    readonly property bool hasRegion: region.width >= 16 && region.height >= 16

    // The app's own name; with no desktop entry, the last dotted part of its class with a capital
    // ("org.gnome.Nautilus" -> "Nautilus", "opsis" -> "Opsis").
    function prettyApp(cls: string): string {
        if (!cls) return "";
        const n = DesktopEntries.heuristicLookup(cls)?.name;
        if (n) return n;
        const last = cls.split(".").filter(x => x.length > 0).pop() ?? cls;
        return last.charAt(0).toUpperCase() + last.slice(1);
    }
    // "Built-in screen" for a laptop panel, else the monitor's model when it reads as a name, else "Screen N"
    function screenName(connector: string, i: int): string {
        if (/^(eDP|LVDS|DSI)/i.test(connector)) return Translation.tr("Built-in screen");
        const model = Quickshell.screens.find(q => q.name === connector)?.model ?? "";
        if (model.length > 2 && !/^(0x)?[0-9a-f]+$/i.test(model)) return model;
        return Translation.tr("Screen %1").arg(i + 1);
    }
    function appIcon(cls: string): string {
        return cls ? (DesktopEntries.heuristicLookup(cls)?.icon ?? "") : "";
    }
    function share(): void {
        if (root.step === "region") {
            if (!root.hasRegion) return;
            root.done({ kind: "region", output: root.screenInfo.name, x: Math.round(root.region.x), y: Math.round(root.region.y),
                        w: Math.round(root.region.width), h: Math.round(root.region.height), token: root.token });
            return;
        }
        const r = root.rows[root.index];
        if (!r) return;
        root.done(r.kind === "screen" ? { kind: "screen", name: r.name, token: root.token } : { kind: "window", id: r.id, token: root.token });
    }
    function back(): void {
        if (root.step === "region") root.step = "list";
        else root.cancelled();
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.share(); event.accepted = true; }
        else if (root.step === "list" && event.key === Qt.Key_Down) { root.index = Math.min(root.rows.length - 1, root.index + 1); event.accepted = true; }
        else if (root.step === "list" && event.key === Qt.Key_Up) { root.index = Math.max(0, root.index - 1); event.accepted = true; }
    }

    readonly property color slab: Appearance.m3colors.m3surfaceContainerLow
    readonly property color ink: Appearance.colors.colInkMain
    readonly property color ink2: Appearance.colors.colInkSecondary
    readonly property color hair: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
    // primary actions: colPrimary 30 % toward white, dark text on it (Lc 82)
    readonly property color accentFill: ColorUtils.mix(Appearance.colors.colPrimary, root.ink, 0.7)
    readonly property color onAccent: Appearance.m3colors.m3surfaceContainerLowest

    // ------------------------------------------------------------------ list step
    Item {
        anchors.fill: parent
        visible: root.step === "list"
        opacity: root.entered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // a click anywhere off the slab backs out: the window covers the whole monitor and holds the keyboard, so a
        // click on the desktop or another window lands here
        MouseArea { anchors.fill: parent; onClicked: root.cancelled() }

        // only the asking window is dimmed
        Rectangle {
            visible: root.askRect !== null
            x: root.askRect?.x ?? 0; y: root.askRect?.y ?? 0; width: root.askRect?.width ?? 0; height: root.askRect?.height ?? 0
            radius: 20
            color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.45)
        }

        Rectangle {
            id: pick
            readonly property real areaX: root.askRect?.x ?? 0
            readonly property real areaY: root.askRect?.y ?? 0
            readonly property real areaW: root.askRect?.width ?? root.width
            readonly property real areaH: root.askRect?.height ?? root.height
            width: 520
            // the list scrolls when the slab would outgrow the window it sits on
            height: Math.min(chrome.wantH + 40, Math.max(300, Math.min(areaH, root.height) - 24))
            x: areaX + (areaW - width) / 2
            y: areaY + (areaH - height) / 2
            color: root.slab; radius: 20
            border.width: 1; border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.72)

            // a press on the slab's own padding is not a click away
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: chrome
                x: 20; y: 20; width: parent.width - 40; height: parent.height - 40
                spacing: 12
                // the slab's natural inner height: title, list, buttons and the gaps between
                readonly property real wantH: 24 + list.contentHeight + tail.implicitHeight + 36 + 12 * 3

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    MaterialSymbol { text: "screen_share"; iconSize: 24; color: Appearance.colors.colPrimary }
                    StyledText {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: root.appName.length > 0 ? Translation.tr("Share with %1").arg(root.appName) : Translation.tr("Share your screen")
                        font.pixelSize: 17; font.weight: Font.Medium; color: root.ink
                    }
                }

                Flickable {
                    id: list
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentWidth: width; contentHeight: col.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    // keep the chosen row in view when the arrows move it
                    Connections {
                        target: root
                        function onIndexChanged() {
                            const top = root.index * 78, bottom = top + 76;
                            if (top < list.contentY) list.contentY = top;
                            else if (bottom > list.contentY + list.height) list.contentY = bottom - list.height;
                        }
                    }

                    ColumnLayout {
                        id: col
                        width: list.width; spacing: 2
                        Repeater {
                            model: root.rows
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool on: root.index === index
                                Layout.fillWidth: true; implicitHeight: 76; radius: 14
                                color: hover.containsMouse && !on ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.94) : "transparent"
                                border.width: on ? 2 : 0; border.color: Appearance.colors.colPrimary
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 14; spacing: 14
                                    Thumb { row: row.modelData; Layout.alignment: Qt.AlignVCenter }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        StyledText {
                                            Layout.fillWidth: true; elide: Text.ElideRight; text: row.modelData.label
                                            font.pixelSize: 15; font.weight: row.on ? Font.DemiBold : Font.Normal; color: root.ink
                                        }
                                        StyledText {
                                            Layout.fillWidth: true; elide: Text.ElideRight; visible: text.length > 0; text: row.modelData.meta
                                            font.pixelSize: 14; color: root.ink2
                                        }
                                    }
                                }
                                MouseArea {
                                    id: hover
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.index = row.index
                                    onDoubleClicked: { root.index = row.index; root.share(); }
                                }
                            }
                        }
                    }
                }

                // pinned under the list so it stays reachable when the list scrolls
                ColumnLayout {
                    id: tail
                    Layout.fillWidth: true; spacing: 2
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4; implicitHeight: 1; color: root.hair }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 52; radius: 14
                        color: regionHover.containsMouse ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.94) : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; spacing: 14
                            Item {
                                implicitWidth: 112; implicitHeight: 24
                                MaterialSymbol { anchors.centerIn: parent; text: "crop"; iconSize: 24; color: root.ink2 }
                            }
                            StyledText { Layout.fillWidth: true; text: Translation.tr("Draw a region"); font.pixelSize: 15; color: root.ink }
                        }
                        MouseArea { id: regionHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.step = "region" }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Item {
                        visible: root.allowToken
                        implicitWidth: tokRow.implicitWidth; implicitHeight: 28
                        MouseArea { anchors.fill: parent; onClicked: root.token = !root.token }
                        Row {
                            id: tokRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Rectangle {
                                width: 20; height: 20; radius: 6; anchors.verticalCenter: parent.verticalCenter
                                color: root.token ? Appearance.colors.colPrimary : "transparent"
                                border.width: 2; border.color: root.token ? Appearance.colors.colPrimary : root.ink2
                                MaterialSymbol { anchors.centerIn: parent; visible: root.token; text: "check"; iconSize: 16; color: root.onAccent }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.appName.length > 0 ? Translation.tr("Allow %1 next time").arg(root.appName) : Translation.tr("Allow next time")
                                font.pixelSize: 14; color: root.ink2
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    TextAction { label: Translation.tr("Cancel"); onClicked: root.cancelled() }
                    Primary { label: Translation.tr("Share"); onClicked: root.share() }
                }
            }
        }
    }

    // ------------------------------------------------------------------ region step
    Item {
        id: reg
        anchors.fill: parent
        visible: root.step === "region"

        readonly property color scrim: Appearance.colors.colScrim
        // 0: none, 1: new, 2: move, 3: resize (with the edges in `grab`)
        property int mode: 0
        property var grab: ({ l: false, r: false, t: false, b: false })
        property point anchorPt: Qt.point(0, 0)
        property rect startRect: Qt.rect(0, 0, 0, 0)

        function clampPt(x, y) { return Qt.point(Math.max(0, Math.min(root.width, x)), Math.max(0, Math.min(root.height, y))); }
        function hit(x, y) {
            const r = root.region, m = 14;
            if (!root.hasRegion) return null;
            const nl = Math.abs(x - r.x) < m, nr = Math.abs(x - (r.x + r.width)) < m;
            const nt = Math.abs(y - r.y) < m, nb = Math.abs(y - (r.y + r.height)) < m;
            const inX = x > r.x - m && x < r.x + r.width + m, inY = y > r.y - m && y < r.y + r.height + m;
            const g = { l: nl && inY, r: nr && inY, t: nt && inX, b: nb && inX };
            return (g.l || g.r || g.t || g.b) ? g : null;
        }

        // dim around the region (all of it until one is drawn)
        Rectangle { x: 0; y: 0; width: reg.width; height: root.hasRegion ? root.region.y : reg.height; color: reg.scrim }
        Rectangle { visible: root.hasRegion; x: 0; y: root.region.y + root.region.height; width: reg.width; height: reg.height - y; color: reg.scrim }
        Rectangle { visible: root.hasRegion; x: 0; y: root.region.y; width: root.region.x; height: root.region.height; color: reg.scrim }
        Rectangle { visible: root.hasRegion; x: root.region.x + root.region.width; y: root.region.y; width: reg.width - x; height: root.region.height; color: reg.scrim }
        Rectangle {
            visible: root.hasRegion
            x: root.region.x; y: root.region.y; width: root.region.width; height: root.region.height
            color: "transparent"; border.width: 2; border.color: Appearance.colors.colPrimary; radius: 4
        }
        Repeater {
            model: root.hasRegion ? [[0, 0], [1, 0], [0, 1], [1, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]] : []
            Rectangle {
                required property var modelData
                width: 12; height: 12; radius: 6; color: Appearance.colors.colPrimary
                x: root.region.x + modelData[0] * root.region.width - 6
                y: root.region.y + modelData[1] * root.region.height - 6
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            onPressed: mouse => {
                const g = reg.hit(mouse.x, mouse.y);
                reg.startRect = root.region;
                reg.anchorPt = Qt.point(mouse.x, mouse.y);
                if (g) { reg.mode = 3; reg.grab = g; }
                else if (root.hasRegion && mouse.x > root.region.x && mouse.x < root.region.x + root.region.width
                         && mouse.y > root.region.y && mouse.y < root.region.y + root.region.height) reg.mode = 2;
                else { reg.mode = 1; root.region = Qt.rect(mouse.x, mouse.y, 0, 0); }
            }
            onPositionChanged: mouse => {
                if (reg.mode === 0) return;
                const p = reg.clampPt(mouse.x, mouse.y), a = reg.anchorPt, s = reg.startRect;
                if (reg.mode === 1) {
                    root.region = Qt.rect(Math.min(a.x, p.x), Math.min(a.y, p.y), Math.abs(p.x - a.x), Math.abs(p.y - a.y));
                } else if (reg.mode === 2) {
                    const dx = Math.max(-s.x, Math.min(root.width - s.x - s.width, p.x - a.x));
                    const dy = Math.max(-s.y, Math.min(root.height - s.y - s.height, p.y - a.y));
                    root.region = Qt.rect(s.x + dx, s.y + dy, s.width, s.height);
                } else {
                    let l = s.x, r = s.x + s.width, t = s.y, b = s.y + s.height;
                    if (reg.grab.l) l = p.x;
                    if (reg.grab.r) r = p.x;
                    if (reg.grab.t) t = p.y;
                    if (reg.grab.b) b = p.y;
                    root.region = Qt.rect(Math.min(l, r), Math.min(t, b), Math.abs(r - l), Math.abs(b - t));
                    // a grabbed edge that crossed over is now the opposite one
                    if (l > r) reg.grab = { l: reg.grab.r, r: reg.grab.l, t: reg.grab.t, b: reg.grab.b };
                    if (t > b) reg.grab = { l: reg.grab.l, r: reg.grab.r, t: reg.grab.b, b: reg.grab.t };
                    reg.startRect = root.region; reg.anchorPt = p;
                }
            }
            onReleased: reg.mode = 0
        }

        Rectangle {
            id: bar
            readonly property real wantY: root.hasRegion ? root.region.y + root.region.height + 20 : reg.height - height - 48
            x: Math.max(12, Math.min(reg.width - width - 12, root.hasRegion ? root.region.x + root.region.width / 2 - width / 2 : (reg.width - width) / 2))
            y: wantY + height + 12 > reg.height ? Math.max(12, (root.hasRegion ? root.region.y : reg.height) - height - 20) : wantY
            width: barRow.implicitWidth + 20; height: barRow.implicitHeight + 20; radius: 24
            color: root.slab
            border.width: 1; border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.72)
            RowLayout {
                id: barRow
                x: 10; y: 10; spacing: 12
                StyledText {
                    Layout.leftMargin: 12
                    text: root.hasRegion ? `${Math.round(root.region.width)} × ${Math.round(root.region.height)}` : Translation.tr("Drag to draw a region")
                    font.family: root.hasRegion ? Appearance.font.family.numbers : Appearance.font.family.main
                    font.pixelSize: 15; color: root.ink
                }
                TextAction { label: Translation.tr("Back"); onClicked: root.back() }
                Primary { label: Translation.tr("Share"); dim: !root.hasRegion; onClicked: root.share() }
            }
        }
    }

    // ------------------------------------------------------------------ parts
    component TextAction: Rectangle {
        id: ta
        property string label: ""
        signal clicked()
        implicitWidth: tl.implicitWidth + 24; implicitHeight: 36; radius: 18
        color: tm.containsMouse ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.92) : "transparent"
        StyledText { id: tl; anchors.centerIn: parent; text: ta.label; font.pixelSize: 14; color: root.ink }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; onClicked: ta.clicked() }
    }
    component Primary: Rectangle {
        id: pr
        property string label: ""
        property bool dim: false
        signal clicked()
        implicitWidth: pl.implicitWidth + 32; implicitHeight: 36; radius: 18
        // inert: a quiet tint with secondary ink (a faded accent fill left the label unreadable)
        color: dim ? ColorUtils.transparentize(root.ink, 0.88) : root.accentFill
        StyledText { id: pl; anchors.centerIn: parent; text: pr.label; font.pixelSize: 14; font.weight: Font.Medium; color: pr.dim ? root.ink2 : root.onAccent }
        MouseArea { anchors.fill: parent; enabled: !pr.dim; onClicked: pr.clicked() }
    }

    // A live copy of a window (or the screen) fitted into 112 x 68.
    component Thumb: Item {
        id: th
        property var row: ({})
        implicitWidth: 112; implicitHeight: 68
        readonly property var toplevel: {
            if (th.row.kind !== "window" || !th.row.address) return null;
            return ToplevelManager.toplevels.values.find(t => `0x${t.HyprlandToplevel?.address}` === th.row.address) ?? null;
        }
        readonly property string iconName: th.row.kind === "window" ? root.appIcon(th.row.cls ?? "") : ""
        readonly property var source: th.row.kind === "screen" ? (Quickshell.screens.find(s => s.name === th.row.name) ?? null) : th.toplevel
        Rectangle { anchors.fill: parent; color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.94) }
        Loader {
            id: over
            anchors.fill: parent
            sourceComponent: root.thumbOverride
            active: root.thumbOverride !== null
        }
        Binding { target: over.item; property: "row"; value: th.row; when: over.item !== null }
        ScreencopyView {
            // fitted to its own aspect inside the box
            readonly property real fit: sourceSize.width > 0 && sourceSize.height > 0 ? Math.min(th.width / sourceSize.width, th.height / sourceSize.height) : 1
            anchors.centerIn: parent
            width: sourceSize.width > 0 ? sourceSize.width * fit : th.width
            height: sourceSize.height > 0 ? sourceSize.height * fit : th.height
            visible: root.thumbOverride === null && hasContent
            // the screen is copied once, before the picker is drawn over it; windows follow
            live: th.row.kind !== "screen" && root.step === "list"
            captureSource: th.source
        }
        // a window with nothing to copy (another workspace) shows its app's icon
        IconImage {
            anchors.centerIn: parent
            visible: root.thumbOverride === null && th.source === null && th.iconName.length > 0
            implicitSize: 32
            source: th.iconName.length > 0 ? Quickshell.iconPath(th.iconName, true) : ""
        }
        MaterialSymbol {
            anchors.centerIn: parent; visible: root.thumbOverride === null && th.source === null && th.iconName.length === 0
            text: th.row.kind === "screen" ? "desktop_windows" : "web_asset"; iconSize: 24; color: root.ink2
        }
        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: root.hair }
    }
}
