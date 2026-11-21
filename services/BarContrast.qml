pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // CIE L* from the top wallpaper band, split into left/center/right thirds.
    property real leftL: 0
    property real centerL: 0
    property real rightL: 0

    readonly property real lightThreshold: 65
    readonly property bool leftIsLight: leftL >= lightThreshold
    readonly property bool centerIsLight: centerL >= lightThreshold
    readonly property bool rightIsLight: rightL >= lightThreshold

    function isLight(zone) {
        if (zone === "left") return leftIsLight
        if (zone === "center") return centerIsLight
        if (zone === "right") return rightIsLight
        return false
    }

    function luminance(zone) {
        if (zone === "left") return leftL
        if (zone === "center") return centerL
        if (zone === "right") return rightL
        return 0
    }

    // Ink colors for a zone when the bar background is transparent. On light wallpaper
    // regions we use dark ink; on dark regions we keep the normal Tacit ink.
    function inkMain(zone) {
        if (Config.options.bar.showBackground) return Tacit.inkMain
        return isLight(zone) ? Appearance.inkFor(92, Appearance.m3colors.m3inverseSurface) : Tacit.inkMain
    }
    function inkSec(zone) {
        if (Config.options.bar.showBackground) return Tacit.inkSec
        return isLight(zone) ? Appearance.inkFor(85, Appearance.m3colors.m3inverseSurface) : Tacit.inkSec
    }
    function inkMeta(zone) {
        if (Config.options.bar.showBackground) return Tacit.inkMeta
        return isLight(zone) ? Appearance.inkFor(75, Appearance.m3colors.m3inverseSurface) : Tacit.inkMeta
    }
    function inkFaint(zone) {
        if (Config.options.bar.showBackground) return Tacit.inkFaint
        return isLight(zone) ? Appearance.inkFor(60, Appearance.m3colors.m3inverseSurface) : Tacit.inkFaint
    }

    function onInkMain(zone) {
        if (Config.options.bar.showBackground) return Tacit.ground
        return isLight(zone) ? Appearance.colors.colOnLayer0 : Tacit.ground
    }

    function seeThroughMeasured() { luminanceFile.reload() }

    FileView {
        id: luminanceFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/bar_luminance.json`)
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text())
                root.leftL = Number(j.left) || 0
                root.centerL = Number(j.center) || 0
                root.rightL = Number(j.right) || 0
            } catch (e) {
                root.leftL = 0; root.centerL = 0; root.rightL = 0
            }
        }
        onLoadFailed: {
            root.leftL = 0; root.centerL = 0; root.rightL = 0
        }
    }

    // Re-measure when wallpaper changes. The script is run by switchwall; this is a
    // fallback to keep values fresh in the current session.
    Connections {
        target: Config.options.background
        function onWallpaperPathChanged() { luminanceFile.reload() }
    }
}
