pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    // Every active tray item, in the order the apps published them. The split into pinned and
    // overflow items is gone: the bar's tray button opens all of them in one drawer.
    readonly property bool smartTray: Config.options.tray.filterPassive
    readonly property list<var> items: SystemTray.items.values.filter(i => !smartTray || i.status !== Status.Passive)

    function getTooltipForItem(item) {
        var result = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        return result;
    }
}
