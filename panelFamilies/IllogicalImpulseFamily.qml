import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.newbar
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.bluetooth
import qs.modules.ii.island
import qs.modules.ii.keyring
import qs.modules.ii.equalizer
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.settings
import qs.modules.ii.regionSelector
import qs.modules.ii.sharePicker
import qs.modules.ii.openWith
import qs.modules.ii.screenCorners
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarRight
import qs.modules.ii.overlay
import qs.modules.ii.volumePopup
import qs.modules.ii.systemDrawer
import qs.modules.ii.verticalBar
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.desktopMenu
import qs.modules.ii.desktopIcons
import qs.modules.ii.windowMenu
import qs.modules.ii.files
import qs.modules.ii.dropover
import qs.modules.ii.frame

Scope {
    id: family

    // Tacit's experience is fixed (owner, 2026-09-30: no end-4 options). These values are held at
    // the source, so every reader stays as it is; Settings has no switch for them, and the old
    // panel, a preset or a hand edit that changes one is turned back:
    //   the notch on, showing volume and brightness (off, end-4's on-screen meter loaded);
    //   the grid on SUPER+Tab, not end-4's stacked layout; Tacit's lock, not hyprlock
    //   (hyprlock stays the fallback for a crashed shell, keybinds.lua).
    function holdTacit() {
        if (!Config.ready)
            return;
        const o = Config.options;
        if (!o.island.enable)
            o.island.enable = true;
        if (!o.island.states.volume)
            o.island.states.volume = true;
        if (!o.island.states.brightness)
            o.island.states.brightness = true;
        if (o.overview.style !== "default")
            o.overview.style = "default";
        if (o.lock.useHyprlock)
            o.lock.useHyprlock = false;
    }
    Component.onCompleted: family.holdTacit()
    Connections {
        target: Config
        function onReadyChanged() { family.holdTacit(); }
    }
    Connections {
        target: Config.options.island
        function onEnableChanged() { family.holdTacit(); }
    }
    Connections {
        target: Config.options.island.states
        function onVolumeChanged() { family.holdTacit(); }
        function onBrightnessChanged() { family.holdTacit(); }
    }
    Connections {
        target: Config.options.overview
        function onStyleChanged() { family.holdTacit(); }
    }
    Connections {
        target: Config.options.lock
        function onUseHyprlockChanged() { family.holdTacit(); }
    }

    // The bar and the vertical bar have their own switch, bar.enable, off and in no Settings row: the
    // notch replaced them, and turning the notch off used to bring the end-4 bar back.
    PanelLoader { extraCondition: Config.options.bar.enable && !Config.options.bar.vertical && !(Config.options.island.enable && Config.options.island.hideBar); component: Bar {} }
    // Step 1: a full-width strip stands in for the notch. The 3-style demo in modules/demo/
    // is saved but not loaded. The notch itself is back under the strip: it hangs from the
    // bar's underside, in the bar's colour, and only draws while it has something to show.
    // PanelLoader { extraCondition: Config.options.island.enable; component: Island {} }
    // PanelLoader { component: DemoBar {} }
    PanelLoader { extraCondition: Config.options.island.enable; component: Island {} }
    PanelLoader { component: NewBar {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: EqualizerPopup {} }
    PanelLoader { component: FilesPanel {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: Dusk {} }
    // Loaded, but no longer the surface SUPER+M reaches: MediaControls.qml hands the toggle and
    // the `mediaControls` IPC to the notch whenever the island owns media, and opens its own
    // popup only when it does not - or when a kept bar's media widget asks for it. Loading it is
    // what keeps those shortcuts registered at all.
    PanelLoader { component: MediaControls {} }
    // Always loaded: this panel owns the notification centre and the `notifications` IPC as well as
    // the popup, and the shipped defaults (island on, its notification state on) meant a fresh
    // install had no centre at all. The popup itself stands down for the island inside the file.
    PanelLoader { component: NotificationPopup {} }
    // Always loaded: the bar owns the volume popup the bar's volume button opens (GlobalStates.volumeOpen).
    PanelLoader { component: VolumePopup {} }
    // The bar's other drawers share the same shell and the bar's material: each is always
    // loaded so its button works on the first press, and each stays closed until opened.
    PanelLoader { component: NetworkDrawer {} }
    PanelLoader { component: BatteryDrawer {} }
    PanelLoader { component: BrightnessDrawer {} }
    PanelLoader { component: TrayDrawer {} }
    // Always loaded: the notch is suppressed on the lock and session screens, and the volume and
    // brightness keys would give no feedback there. The file mutes its own triggers (meters, gamma,
    // the sink-protection warning) while the notch can answer, so exactly one of them says each.
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    // Pairing questions from BlueZ, in the polkit window's shape. Needs quiet-btagent running;
    // with no agent, the sheet simply never appears and BlueZ refuses the pairing itself.
    PanelLoader { component: BluetoothPairing {} }
    // Keyring unlock / new password / confirm from tacit-keyring-prompter (gcr prompter replacement) through DialogBridge.
    PanelLoader { component: Keyring {} }
    PanelLoader { component: RegionSelector {} }
    // Screen-share picker for xdph's custom_picker_binary (tacit-share-picker); also keeps DialogBridge connected.
    PanelLoader { component: SharePicker {} }
    // "Open with" menu for tacit-portal's AppChooser (DialogBridge kind open.choose).
    PanelLoader { component: OpenWith {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.enable && Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: Settings {} }
    PanelLoader { component: DesktopMenu {} }
    // the Desktop folder's files as tags on the wallpaper
    PanelLoader { component: DesktopTags {} }
    // the window band's menu (a right click on a window's top edge); loading it also starts WindowBand, which
    // listens for the band's events from the moment the shell starts
    PanelLoader { component: WindowMenu {} }
    // The notch is the shelf: IslandContent catches GlobalStates.dropShelfOpen and opens on its
    // shelf view. This floating panel is the pre-notch surface, kept only for a machine running
    // without the notch, where nothing else consumes that flag - two consumers at once meant the
    // notch cleared the flag while this window was also bound to it.
    PanelLoader { extraCondition: !Config.options.island.enable; component: DropShelfPanel {} }
    PanelLoader { component: NiriBackdrop {} }
    PanelLoader { component: ScreenFrame {} }
}
