import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions
import qs.services
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject icon
    property QtObject spacing
    property QtObject sizes
    property string syntaxHighlightingTheme

    // Agents' marks (dots, run bars, the shine, the ring) move for a few seconds after an agent does something,
    // then rest: marks that moved for as long as an agent worked redrew the screen every frame. agent-host's
    // events call agentMoved() (Host.receive).
    property bool agentsMoving: false
    function agentMoved() {
        agentsMoving = true;
        agentRest.restart();
    }
    Timer {
        id: agentRest
        interval: 3000
        onTriggered: root.agentsMoving = false
    }

    // Transparency. The quadratic functions were derived from analysis of hand-picked transparency values.
    ColorQuantizer {
        id: wallColorQuant
        property string wallpaperPath: Config.options.background.wallpaperPath
        property bool wallpaperIsVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(wallpaperPath)
        // a file URL with each part encoded: Qt.resolvedUrl would read a '#' or '?' in the name as a fragment or query
        property string samplePath: FileUtils.trimFileProtocol(wallpaperIsVideo ? Config.options.background.thumbnailPath : wallpaperPath)
        source: samplePath.length > 0 ? "file://" + samplePath.split("/").map(encodeURIComponent).join("/") : ""
        depth: 0 // 2^0 = 1 color
        rescaleSize: 10
    }
    // a middling vibrancy until the sample has loaded (or when it cannot: no wallpaper, an unreadable file), so the
    // transparency below is a number rather than NaN
    property real wallpaperVibrancy: {
        const c = wallColorQuant.colors[0]
        return c ? (c.hslSaturation + c.hslLightness) / 2 : 0.5
    }
    property real autoBackgroundTransparency: { // y = 0.5768x^2 - 0.759x + 0.2896
        let x = wallpaperVibrancy
        let y = 0.5768 * (x * x) - 0.759 * (x) + 0.2896
        return Math.max(0, Math.min(0.22, y)) - 0.12 * (m3colors.darkmode ? 0 : 1)
    }
    property real autoContentTransparency: 0.9
    property real backgroundTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoBackgroundTransparency : Config?.options.appearance.transparency.backgroundTransparency : 0
    property real contentTransparency: Config?.options.appearance.transparency.automatic ? autoContentTransparency : Config?.options.appearance.transparency.contentTransparency
    // How much of this wallpaper the glass lets through (scripts/colors/seethrough.py, at every wallpaper change): one
    // scale on every designed see-through amount, 1 on dark wallpapers and less on bright ones, so the grounds under the
    // text stay as dark as on dusk. Tacit.windowSeeThrough and the frost take it; Hyprland's rules and foot read the file.
    property real seeThroughScale: 1
    // after scripts/colors/measure-glass.sh made the file: a watch on a file that was not there sees nothing
    function seeThroughMeasured() { seeThroughFile.reload() }
    FileView {
        id: seeThroughFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/seethrough.json`)
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text()).scale;
                root.seeThroughScale = s >= 0 && s <= 1 ? s : 1;
            } catch (e) {
                root.seeThroughScale = 1;
            }
        }
        onLoadFailed: root.seeThroughScale = 1
    }
    // Whether Hyprland blurs what is behind a see-through surface (decoration:blur:enabled) as it is now, asked again
    // at every config reload: Settings > Appearance, Game mode or a line in the person's own files can turn the blur
    // off, and a see-through ground with nothing blurred behind it shows the wallpaper sharp under the text. Without it
    // Tacit.windowSeeThrough, the frost and Files are solid. Hyprland 0.56 answers with a bool, older ones with an int;
    // until it answers, and off Hyprland, the blur counts as on, so nothing flashes solid at start. Asked here, not with
    // a HyprlandConfigOption: its WM would start HyprlandData's hyprctl refreshes in every app that draws a ground.
    property var blurAnswer
    readonly property bool blurBehind: root.blurAnswer !== false && root.blurAnswer !== 0
    Process {
        id: blurQuery
        command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const answer = JSON.parse(text);
                    root.blurAnswer = answer.bool ?? answer.int;
                } catch (e) {}
            }
        }
    }
    Connections {
        target: HyprlandConfig
        function onReloaded() { blurQuery.running = true }
    }
    Component.onCompleted: blurQuery.running = true
    
    // An ink at a given APCA Lc on a ground (surfaceContainerLow unless given): the point on the line from
    // that ground through onBackground on to white (dark grounds) or black (light ones) that first reaches
    // it, so the ink keeps the palette's hue. Halving the line 18 times is finer than 8-bit colour.
    function inkFor(lc, ground = root.m3colors.m3surfaceContainerLow) {
        const ink = root.m3colors.m3onBackground;
        const far = ground.hslLightness < 0.5 ? "#ffffff" : "#000000";
        const at = t => t <= 1 ? ColorUtils.mix(ink, ground, t) : ColorUtils.mix(far, ink, t - 1);
        let lo = 0, hi = 2;
        for (let i = 0; i < 18; i++) {
            const mid = (lo + hi) / 2;
            if (Math.abs(ColorUtils.apcaLc(at(mid), ground)) < lc)
                lo = mid;
            else
                hi = mid;
        }
        return at(hi);
    }

    function getColorFromName(name) {
        switch (name) {
            case "primary":            return colors.colPrimary
            case "secondary":          return colors.colSecondary
            case "tertiary":           return colors.colTertiary
            case "primaryContainer":   return colors.colPrimaryContainer
            case "secondaryContainer": return colors.colSecondaryContainer
            case "tertiaryContainer":  return colors.colTertiaryContainer
            case "layer0":             return colors.colLayer0
            case "layer1":             return colors.colLayer1
            case "layer0Border":       return colors.colLayer0Border
            case "black":              return "black"
            default:                   return colors.colPrimaryContainer
        }
    }

    m3colors: QtObject {
        property bool darkmode: true
        property bool transparent: false
        property color m3background: "#141313"
        property color m3onBackground: "#e6e1e1"
        property color m3surface: "#141313"
        property color m3surfaceDim: "#141313"
        property color m3surfaceBright: "#3a3939"
        property color m3surfaceContainerLowest: "#0f0e0e"
        property color m3surfaceContainerLow: "#1c1b1c"
        property color m3surfaceContainer: "#201f20"
        property color m3surfaceContainerHigh: "#2b2a2a"
        property color m3surfaceContainerHighest: "#363435"
        property color m3onSurface: "#e6e1e1"
        property color m3surfaceVariant: "#49464a"
        property color m3onSurfaceVariant: "#cbc5ca"
        property color m3inverseSurface: "#e6e1e1"
        property color m3inverseOnSurface: "#313030"
        property color m3outline: "#948f94"
        property color m3outlineVariant: "#49464a"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#cbc4cb"
        property color m3primary: "#cbc4cb"
        property color m3onPrimary: "#322f34"
        property color m3primaryContainer: "#2d2a2f"
        property color m3onPrimaryContainer: "#bcb6bc"
        property color m3inversePrimary: "#615d63"
        property color m3secondary: "#cac5c8"
        property color m3onSecondary: "#323032"
        property color m3secondaryContainer: "#4d4b4d"
        property color m3onSecondaryContainer: "#ece6e9"
        property color m3tertiary: "#d1c3c6"
        property color m3onTertiary: "#372e30"
        property color m3tertiaryContainer: "#31292b"
        property color m3onTertiaryContainer: "#c1b4b7"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3primaryFixed: "#e7e0e7"
        property color m3primaryFixedDim: "#cbc4cb"
        property color m3onPrimaryFixed: "#1d1b1f"
        property color m3onPrimaryFixedVariant: "#49454b"
        property color m3secondaryFixed: "#e6e1e4"
        property color m3secondaryFixedDim: "#cac5c8"
        property color m3onSecondaryFixed: "#1d1b1d"
        property color m3onSecondaryFixedVariant: "#484648"
        property color m3tertiaryFixed: "#eddfe1"
        property color m3tertiaryFixedDim: "#d1c3c6"
        property color m3onTertiaryFixed: "#211a1c"
        property color m3onTertiaryFixedVariant: "#4e4447"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color term0: "#EDE4E4"
        property color term1: "#B52755"
        property color term2: "#A97363"
        property color term3: "#AF535D"
        property color term4: "#A67F7C"
        property color term5: "#B2416B"
        property color term6: "#8D76AD"
        property color term7: "#272022"
        property color term8: "#0E0D0D"
        property color term9: "#B52755"
        property color term10: "#A97363"
        property color term11: "#AF535D"
        property color term12: "#A67F7C"
        property color term13: "#B2416B"
        property color term14: "#8D76AD"
        property color term15: "#221A1A"
    }

    colors: QtObject {
        // Secondary TEXT is onSurfaceVariant (about 7:1 on the frost). outline is a border
        // colour (under 3:1 as text) and was making every second line hard to read.
        property color colSubtext: m3colors.m3onSurfaceVariant
        // Text in four levels by measured contrast (APCA Lc on surfaceContainerLow, the panels'
        // ground): main 92 (preferred body), secondary 85, meta 75 (times, counts, labels), faint 60
        // (placeholders, folds), and a divider at 16. APCA's floor for 13-15 px text is 75: meta at 60
        // and secondary at 75 kept small text at or under it ("text grey", 2026-10-11). Each is solved for its Lc
        // (root.inkFor), so the levels hold in light mode and on any wallpaper's palette; the fixed
        // mixes they replace only fitted the dark dusk palette and in light mode made the main ink
        // paler than the secondary one. Used in place of colSubtext plus opacity (Lc 35-51).
        property color colInkMain: root.inkFor(92)
        property color colInkSecondary: root.inkFor(85)
        property color colInkMeta: root.inkFor(75)
        property color colInkFaint: root.inkFor(60)
        property color colInkDivider: root.inkFor(16)
        // a failure, said without alarm: the palette's error pulled halfway to its accent
        property color colClay: ColorUtils.mix(m3colors.m3error, m3colors.m3primary, 0.5)
        // Layer 0
        property color colLayer0Base: ColorUtils.mix(m3colors.m3background, m3colors.m3primary, Config.options.appearance.extraBackgroundTint ? 0.99 : 1)
        property color colLayer0: ColorUtils.transparentize(colLayer0Base, root.backgroundTransparency)
        property color colOnLayer0: m3colors.m3onBackground
        property color colLayer0Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.9, root.contentTransparency))
        property color colLayer0Active: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.8, root.contentTransparency))
        property color colLayer0Border: ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0, 0.4)
        // Layer 1
        property color colLayer1Base: m3colors.m3surfaceContainerLow
        property color colLayer1: ColorUtils.solveOverlayColor(colLayer0Base, colLayer1Base, 1 - root.contentTransparency);
        property color colOnLayer1: m3colors.m3onSurfaceVariant;
        property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45);
        property color colLayer1Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.92), root.contentTransparency)
        property color colLayer1Active: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.85), root.contentTransparency);
        // Layer 2
        property color colLayer2Base: m3colors.m3surfaceContainer
        property color colLayer2: ColorUtils.solveOverlayColor(colLayer1Base, colLayer2Base, 1 - root.contentTransparency)
        property color colLayer2Hover: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.90), 1 - root.contentTransparency)
        property color colLayer2Active: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.80), 1 - root.contentTransparency);
        property color colLayer2Disabled: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, m3colors.m3background, 0.8), 1 - root.contentTransparency);
        property color colOnLayer2: m3colors.m3onSurface;
        property color colOnLayer2Disabled: ColorUtils.mix(colOnLayer2, m3colors.m3background, 0.4);
        // Layer 3
        property color colLayer3Base: m3colors.m3surfaceContainerHigh
        property color colLayer3: ColorUtils.solveOverlayColor(colLayer2Base, colLayer3Base, 1 - root.contentTransparency)
        property color colLayer3Hover: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.90), 1 - root.contentTransparency)
        property color colLayer3Active: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.80), 1 - root.contentTransparency);
        property color colOnLayer3: m3colors.m3onSurface;
        // Layer 4
        property color colLayer4Base: m3colors.m3surfaceContainerHighest
        property color colLayer4: ColorUtils.solveOverlayColor(colLayer3Base, colLayer4Base, 1 - root.contentTransparency)
        property color colLayer4Hover: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.90), 1 - root.contentTransparency)
        property color colLayer4Active: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.80), 1 - root.contentTransparency);
        property color colOnLayer4: m3colors.m3onSurface;
        // Primary
        property color colPrimary: m3colors.m3primary
        property color colOnPrimary: m3colors.m3onPrimary
        property color colPrimaryHover: ColorUtils.mix(colors.colPrimary, colLayer1Hover, 0.87)
        property color colPrimaryActive: ColorUtils.mix(colors.colPrimary, colLayer1Active, 0.7)
        property color colPrimaryContainer: m3colors.m3primaryContainer
        property color colPrimaryContainerHover: ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.9)
        property color colPrimaryContainerActive: ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.8)
        property color colOnPrimaryContainer: m3colors.m3onPrimaryContainer
        // Secondary
        property color colSecondary: m3colors.m3secondary
        property color colSecondaryHover: ColorUtils.mix(m3colors.m3secondary, colLayer1Hover, 0.85)
        property color colSecondaryActive: ColorUtils.mix(m3colors.m3secondary, colLayer1Active, 0.4)
        property color colOnSecondary: m3colors.m3onSecondary
        property color colSecondaryContainer: m3colors.m3secondaryContainer
        property color colSecondaryContainerHover: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.90)
        property color colSecondaryContainerActive: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.54)
        property color colOnSecondaryContainer: m3colors.m3onSecondaryContainer
        // Tertiary
        property color colTertiary: m3colors.m3tertiary
        property color colTertiaryHover: ColorUtils.mix(m3colors.m3tertiary, colLayer1Hover, 0.85)
        property color colTertiaryActive: ColorUtils.mix(m3colors.m3tertiary, colLayer1Active, 0.4)
        property color colTertiaryContainer: m3colors.m3tertiaryContainer
        property color colTertiaryContainerHover: ColorUtils.mix(m3colors.m3tertiaryContainer, m3colors.m3onTertiaryContainer, 0.90)
        property color colTertiaryContainerActive: ColorUtils.mix(m3colors.m3tertiaryContainer, colLayer1Active, 0.54)
        property color colOnTertiary: m3colors.m3onTertiary
        property color colOnTertiaryContainer: m3colors.m3onTertiaryContainer
        // Surface
        property color colBackgroundSurfaceContainer: ColorUtils.transparentize(m3colors.m3surfaceContainer, root.backgroundTransparency)
        // The one surface every edge panel wears (palette, both sidebars, notification
        // popups): M3 frost over the compositor blur at AOSP's 170/255 = 0.667 opacity.
        // Was the palette's private formula; hoisted so the panels stop disagreeing.
        // One step above surfaceContainer: over a page of the same dark tone the frost was
        // invisible and the controls floated. Alpha 0.72 stays above the blur threshold (0.64).
        property color colPanelFrost: ColorUtils.transparentize(m3colors.m3surfaceContainerHigh, root.blurBehind ? 0.24 * root.seeThroughScale : 0)
        property color colSurfaceContainerLow: ColorUtils.solveOverlayColor(m3colors.m3background, m3colors.m3surfaceContainerLow, 1 - root.contentTransparency)
        property color colSurfaceContainer: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerLow, m3colors.m3surfaceContainer, 1 - root.contentTransparency)
        property color colSurfaceContainerHigh: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainer, m3colors.m3surfaceContainerHigh, 1 - root.contentTransparency)
        property color colSurfaceContainerHighest: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerHigh, m3colors.m3surfaceContainerHighest, 1 - root.contentTransparency)
        property color colSurfaceContainerHighestHover: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.95)
        property color colSurfaceContainerHighestActive: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.85)
        property color colOnSurface: m3colors.m3onSurface
        property color colOnSurfaceVariant: m3colors.m3onSurfaceVariant
        // Misc
        property color colTooltip: m3colors.m3inverseSurface
        property color colOnTooltip: m3colors.m3inverseOnSurface
        property color colScrim: ColorUtils.transparentize(m3colors.m3scrim, 0.5)
        property color colShadow: ColorUtils.transparentize(m3colors.m3shadow, 0.7)
        // The focus edge: the faint primary ring MaterialTextField already draws, named so the
        // fields that draw their own stop each picking a different alpha.
        property color colFocusEdge: ColorUtils.transparentize(colPrimary, 0.4)
        property color colOutline: m3colors.m3outline
        property color colOutlineVariant: m3colors.m3outlineVariant
        property color colError: m3colors.m3error
        property color colErrorHover: ColorUtils.mix(m3colors.m3error, colLayer1Hover, 0.85)
        property color colErrorActive: ColorUtils.mix(m3colors.m3error, colLayer1Active, 0.7)
        property color colOnError: m3colors.m3onError
        property color colErrorContainer: m3colors.m3errorContainer
        property color colErrorContainerHover: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.90)
        property color colErrorContainerActive: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.70)
        property color colOnErrorContainer: m3colors.m3onErrorContainer
    }

    rounding: QtObject {
        property int unsharpen: 2
        property int unsharpenmore: 6
        property int verysmall: 8
        // The two radii the surfaces draw with no name for them: 10 is the small tile (10 sites),
        // 14 the card and the 28-high pill (17 sites, including the notch's resting corner).
        property int chip: 10
        property int small: 12
        property int card: 14
        property int normal: 17
        property int large: 23
        property int verylarge: 30
        property int full: 9999
        property int screenRounding: large
        property int windowRounding: 18
    }

    font: QtObject {
        property QtObject family: QtObject {
            property string main: Config.options.appearance.fonts.main
            property string numbers: Config.options.appearance.fonts.numbers
            property string title: Config.options.appearance.fonts.title
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: Config.options.appearance.fonts.iconNerd
            property string monospace: Config.options.appearance.fonts.monospace
            property string reading: Config.options.appearance.fonts.reading
            property string expressive: Config.options.appearance.fonts.expressive
            // Tacit Sans cut for its cases (~/dev/tacit-font, 2026-10-01): titles, lists and rows, tight places
            property string display: "Tacit Sans Display"
            property string compact: "Tacit Sans Compact"
            property string condensed: "Tacit Sans Condensed"
        }
        property QtObject variableAxes: QtObject {
            property var main: ({
                "wght": 450,
                "wdth": 100,
            })
            property var numbers: ({
                "wght": 450,
            })
            property var title: ({ // Slightly bold weight for title
                "wght": 550, // Weight (Lowered to compensate for increased grade)
            })
        }
        // Text sizes one step up from the first scale (2026-10-01): 11-15 px became 12-16 for this 142 PPI panel.
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            // 11 and 14 were missing from the scale while being typed by hand 10 and 54 times.
            property int tiny: 12
            property int smaller: 13
            property int smallie: 14
            property int smallish: 15
            property int small: 16
            property int normal: 16
            property int large: 17
            property int larger: 19
            property int huge: 22
            property int hugeass: 23
            property int title: huge
        }
    }

    icon: QtObject {
        // The glyph sizes the shell already draws. 18 and 20 are the two most common and neither is
        // a step on the font scale, which jumps 17 -> 19; that is why they were typed by hand.
        // MaterialSymbol's own default is font.pixelSize.small (15), which is not on this ladder.
        property int tiny: 13
        property int small: 16
        property int normal: 18
        property int large: 20
        property int verylarge: 24
    }

    spacing: QtObject {
        // The gaps the shell already draws. `panel` is a frosted panel's content inset, which the
        // control panel sets to 14 and the notification centre to 8; naming it does not reconcile
        // them.
        property int tiny: 4
        property int verysmall: 6
        property int small: 8
        property int smallish: 10
        property int normal: 12
        property int panel: 14
        property int large: 16
        property int verylarge: 20
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
        readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1] // Default, 650ms
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1] // Default, 200ms
        // Fast/slow effects pair, from caelestia plugin/src/Caelestia/Config/tokens.hpp:25,27.
        // expressiveEffects above is their expressiveDefaultEffects; aliased below.
        readonly property list<real> expressiveFastEffects: [0.31, 0.94, 0.34, 1.00, 1, 1] // 150ms
        readonly property list<real> expressiveDefaultEffects: expressiveEffects
        readonly property list<real> expressiveSlowEffects: [0.34, 0.88, 0.34, 1.00, 1, 1] // 300ms
        readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property real expressiveFastSpatialDuration: 350
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveSlowSpatialDuration: 650
        readonly property real expressiveEffectsDuration: 200
        // Duration tokens that were missing, from caelestia tokens.hpp:80-93. The 140
        // hardcoded `duration: 150/200/300/400/1000` literals across modules are these
        // values typed by hand because there was nothing to reference.
        readonly property real smallDuration: 200
        readonly property real normalDuration: 400
        readonly property real largeDuration: 600
        readonly property real extraLargeDuration: 1000
        readonly property real expressiveFastEffectsDuration: 150
        readonly property real expressiveDefaultEffectsDuration: expressiveEffectsDuration
        readonly property real expressiveSlowEffectsDuration: 300
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveSmall: QtObject {
            property int duration: animationCurves.expressiveFastSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveFastSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveSmall.duration
                    easing.type: root.animation.elementMoveSmall.type
                    easing.bezierCurve: root.animation.elementMoveSmall.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveExit: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: 850
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
        }

        property QtObject elementResize: QtObject {
            property int duration: 300
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }

        property QtObject clickBounce: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 850
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.clickBounce.duration
                easing.type: root.animation.clickBounce.type
                easing.bezierCurve: root.animation.clickBounce.bezierCurve
            }}
        }
        
        property QtObject scroll: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: root.animationCurves.standardDecel
        }

        property QtObject menuDecel: QtObject {
            property int duration: 350
            property int type: Easing.OutExpo
        }

        property QtObject sidebarSlideEnter: QtObject {
            property int duration: 300
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.standardDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.sidebarSlideEnter.duration
                    easing.type: root.animation.sidebarSlideEnter.type
                    easing.bezierCurve: root.animation.sidebarSlideEnter.bezierCurve
                }
            }
        }

        property QtObject sidebarSlideExit: QtObject {
            property int duration: 250
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.standardAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.sidebarSlideExit.duration
                    easing.type: root.animation.sidebarSlideExit.type
                    easing.bezierCurve: root.animation.sidebarSlideExit.bezierCurve
                }
            }
        }
    }

    

    sizes: QtObject {
        property real baseBarHeight: 40
        property real barHeight: Config.options.bar.cornerStyle === 1 ? 
            (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: 10
        property real fabShadowRadius: 5
        property real fabHoveredShadowRadius: 7
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real mediaControlsHeight: 160
        property real notificationPopupWidth: 410
        property real osdWidth: 180
        property real searchWidthCollapsed: 210
        property real searchWidth: 360
        property real sidebarWidth: 460
        property real sidebarWidthExtended: 750
        property real baseVerticalBarWidth: 46
        property real verticalBarWidth: Config.options.bar.cornerStyle === 1 ? 
            (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
        property real wallpaperSelectorWidth: 1200
        property real wallpaperSelectorHeight: 690
        property real wallpaperSelectorItemMargins: 8
        property real wallpaperSelectorItemPadding: 6
    }

    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
