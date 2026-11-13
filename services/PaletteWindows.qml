pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * The "Windows" section of the command palette.
 *
 * The client list already exists: HyprlandData polls `hyprctl clients -j` and
 * HyprlandBackend normalises it into WM.windowList, which is what the dock, the
 * overview and NiriOverview read. Nothing new is polled or dispatched here - focus
 * and move go through WM.focusWindow() / WM.moveWindowToWorkspace(), the same
 * helpers modules/ii/overview/OverviewWidget.qml uses.
 *
 * Rows are plain-substring matched on title, class and workspace name, like
 * PaletteSystemActions: this is a short, live list, not a corpus.
 */
Singleton {
    id: root

    readonly property string sectionTitle: Translation.tr("Windows")
    // Shared with SearchWidget's Shift+Enter handler, so the two never disagree on
    // the label the way a re-translated literal could.
    readonly property string focusLabel: Translation.tr("Focus window")
    readonly property string moveHereLabel: Translation.tr("Move here")

    /**
     * WM.windowList entries are {id, address, title, appId, workspaceId, focused}
     * (services/HyprlandBackend.qml normalizeWindow, services/NiriBackend.qml).
     * Workspace names come from WM.workspaceById, which on Hyprland only holds ids
     * 1..100 - another numbered one falls back to its id, a special one (below 1) has none.
     *
     * The window you are sitting in sorts last: Enter on it focuses what is already focused,
     * so it must not be the row an untyped palette opens on.
     *
     * A window the window band holds is as the dock has it: one about to be closed is not
     * listed, and a hidden one (on the band's own special workspace, so no "workspace -98")
     * comes back through the band. Focusing it by address showed that workspace while the
     * band still had it hidden.
     */
    readonly property var windows: {
        // Only while the palette is on screen. AppSearch.guessIcon below is the most
        // expensive call in the shell and this list otherwise rebuilt on every Hyprland
        // event - a browser switching tabs, a terminal changing directory - all session.
        if (!GlobalStates.overviewOpen && !GlobalStates.searchOpen)
            return [];
        const raw = WM.windowList ?? [];
        const byId = WM.workspaceById ?? ({});
        return raw.filter(win => ((win?.title ?? "").length > 0) || ((win?.appId ?? "").length > 0)).map(win => {
            const workspaceId = win.workspaceId ?? -1;
            const workspace = byId[workspaceId];
            const title = (win.title ?? "").length > 0 ? win.title : win.appId;
            const address = win.address ?? win.id ?? "";
            return {
                address: address,
                title: title,
                appId: win.appId ?? "",
                workspaceId: workspaceId,
                workspaceName: workspace?.name !== undefined ? `${workspace.name}` : workspaceId >= 1 ? `${workspaceId}` : "",
                held: WindowBand.held[WindowBand.norm(address)] ?? "",
                focused: win.focused === true,
                // AppSearch.guessIcon is the most expensive call in this shell: on a miss it
                // does five icon-theme lookups and two full fuzzy passes over every desktop
                // entry. Resolving it here means it runs when the window list changes, not
                // once per window on every keystroke.
                iconName: AppSearch.guessIcon(win.appId ?? "")
            };
        }).filter(win => win.held !== "closed").sort((a, b) => (a.focused - b.focused) || ((a.held !== "") - (b.held !== "")) || (a.workspaceId - b.workspaceId) || a.appId.localeCompare(b.appId) || a.title.localeCompare(b.title));
    }

    readonly property int count: root.windows.length

    function focusWindow(address) {
        if (!address || address.length === 0)
            return;
        WM.focusWindow(address);
    }

    /**
     * Shift+Enter: pull the window onto the workspace being looked at instead of
     * jumping away to it. follow=false in the backend means the move alone would
     * leave focus where it was, so focus it afterwards - it is on screen now.
     */
    function moveWindowHere(address) {
        if (!address || address.length === 0)
            return;
        const workspace = WM.activeWorkspace;
        if (!workspace || workspace.id === undefined || workspace.id === null)
            return;
        WM.moveWindowToWorkspace(address, workspace.id);
        WM.focusWindow(address);
    }

    function matches(win, needle) {
        if (needle.length === 0)
            return true;
        return win.title.toLowerCase().includes(needle) || win.appId.toLowerCase().includes(needle) || win.workspaceName.toLowerCase().includes(needle);
    }

    /**
     * Same shape as PaletteSystemActions.fuzzyQuery: returns ready-made
     * LauncherSearchResults. An empty query returns every open window, which is what
     * the untyped palette leads with.
     */
    function fuzzyQuery(search: string): var {
        const needle = (search ?? "").trim().toLowerCase();
        // Slice BEFORE building: every discarded row otherwise allocated three
        // parentless QObjects that nothing ever destroys.
        const limit = Config.options.commandPalette?.resultLimit ?? 40;
        return root.windows.filter(win => root.matches(win, needle)).slice(0, limit).map(win => {
            const address = win.address;
            const held = win.held;
            return resultComp.createObject(null, {
                name: win.title,
                comment: win.workspaceName.length > 0 ? Translation.tr("workspace %1").arg(win.workspaceName) : "",
                type: root.sectionTitle,
                verb: Translation.tr("Focus"),
                iconName: win.iconName,
                iconType: LauncherSearchResult.IconType.System,
                genericName: win.appId,
                keywords: [win.appId, win.workspaceName],
                execute: () => {
                    if (held === "hidden")
                        WindowBand.reopenAll([address]);
                    else if (held === "folding")
                        WindowBand.reopenWhenHidden(address);
                    else
                        root.focusWindow(address);
                },
                // Focus is the row's own verb; listing it again here showed it twice on the row. A held window comes
                // back to its own place, so it has no Move here.
                actions: held !== "" ? [] : [resultComp.createObject(null, {
                        name: root.moveHereLabel,
                        iconName: "move_item",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            root.moveWindowHere(address);
                        }
                    })]
            });
        });
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
