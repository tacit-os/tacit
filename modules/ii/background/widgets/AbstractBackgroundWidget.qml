import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale

    property Item wallpaperItem: null

    property bool visibleWhenLocked: Config.options.lock.showWidgets
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free" && !Config.options.background.widgetsLocked
    function restoreXYBinding() {
        root.x = Qt.binding(() => root.targetX);
        root.y = Qt.binding(() => root.targetY);
    }

    // the saved position; a placement script's answer replaces this binding until it is put back
    function bindTargetToConfig() {
        root.targetX = Qt.binding(() => Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width)));
        root.targetY = Qt.binding(() => Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height)));
    }

    function commitPosition() {
        configEntry.x = root.x;
        configEntry.y = root.y;
        root.bindTargetToConfig();
        root.restoreXYBinding();
    }

    onReleased: root.commitPosition()

    // Switched on while the desktop runs (Background.qml's switchedOn), a widget whose saved spot lies under one
    // already shown takes the next free spot: every widget's saved spot starts at 400,100, so a second one switched on
    // sat exactly over the first. The spots tried are beside those shown, to the right of each and below it, in reading
    // order; the first that is on the screen and clear of them all is saved. With none, it stays where it was.
    function takeFreeSpot() {
        const canvas = root.registeredCanvas;
        if (!canvas || root.placementStrategy !== "free") return;
        const shown = canvas.registeredWidgets.filter(w => w !== root && w.visible && w.enabled);
        const clear = (x, y) => x >= 0 && y >= 0
            && x + root.width <= root.scaledScreenWidth && y + root.height <= root.scaledScreenHeight
            && !shown.some(w => canvas.rectsIntersect(Qt.rect(x, y, root.width, root.height),
                Qt.rect(w.x, w.y, w.width, w.height)));
        if (clear(root.targetX, root.targetY)) return;
        const gap = 24;
        const spots = [];
        for (const w of shown) spots.push(Qt.point(w.x + w.width + gap, w.y), Qt.point(w.x, w.y + w.height + gap));
        const spot = spots.sort((a, b) => a.y - b.y || a.x - b.x).find(p => clear(p.x, p.y));
        if (!spot) return;
        root.configEntry.x = spot.x;
        root.configEntry.y = spot.y;
    }
    Component.onCompleted: {
        const canvas = root.findCanvas(root.parent);
        if (!canvas?.switchedOn?.[root.configEntryName]) return;
        canvas.switchedOn[root.configEntryName] = false;
        // once its content has given it a size
        Qt.callLater(root.takeFreeSpot);
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.options.background.wallpaperPath)
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free") root.bindTargetToConfig();
        if (root.placementStrategy === "free" && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh")
            , "--screen-width", Math.round(root.scaledScreenWidth)
            , "--screen-height", Math.round(root.scaledScreenHeight)
            , "--width", contentWidth
            , "--height", contentHeight
            , "--horizontal-padding", horizontalPadding
            , "--vertical-padding", verticalPadding
            , wallpaperPath
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }
}