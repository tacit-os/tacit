import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.models.hyprland
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    // Hyprland's own answer decides, not the click: assigning toggled here would drop this binding for good,
    // and until the first answer value is undefined, which must not read as animations off. Hyprland 0.56 answers
    // animations:enabled with a bool ({"bool": false}), older ones with an int
    toggled: confOpt.value === false || confOpt.value === 0
    icon: "gamepad"

    mainAction: () => {
        if (!root.toggled) {
            HyprlandConfig.setMany({
                "animations:enabled": 0,
                "decoration:shadow:enabled": 0,
                "decoration:blur:enabled": 0,
                "general:gaps_in": 0,
                "general:gaps_out": 0,
                "general:border_size": 1,
                "decoration:rounding": 0,
                "general:allow_tearing": 1
            });
        } else {
            // A reset DELETES the lines from shellOverrides/main.lua, which Hyprland loads last,
            // so these keys fell back to custom/general.lua and the configured look was gone until
            // each control on the Hyprland page was touched again. Write the stored values back.
            HyprlandConfig.setMany({
                "animations:enabled": Config.options.hyprland.animations.enable ? 1 : 0,
                "decoration:shadow:enabled": Config.options.hyprland.decoration.shadow.enabled ? 1 : 0,
                "decoration:blur:enabled": Config.options.hyprland.decoration.blur.enabled ? 1 : 0,
                "general:gaps_in": Config.options.hyprland.general.gapsIn,
                "general:gaps_out": Config.options.hyprland.general.gapsOut,
                "general:border_size": Config.options.hyprland.general.borderSize,
                "decoration:rounding": Config.options.hyprland.decoration.rounding
            });
            // Tearing has no setting of its own, so this one key does go back to hyprland/general.lua.
            HyprlandConfig.reset("general:allow_tearing");
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "animations:enabled"
    }

    tooltipText: Translation.tr("Game mode")
}
