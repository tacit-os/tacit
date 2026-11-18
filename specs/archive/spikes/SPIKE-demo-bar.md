# Spike: demo bar in place of the notch

## Question

Can we show three bar styles at once in a top-centre frost sheet that replaces the notch, using the
existing bar widgets for live clock / workspaces / media, with all changes isolated to a local demo
folder so the shipping shell can be restored by one line?

## Result

Answered — implemented and running locally. Not shipped.

## Findings

- `panelFamilies/IllogicalImpulseFamily.qml` is the single switch point: the notch is one
  `PanelLoader { component: Island {} }`, and the bar is already built in `modules/ii/bar/`.
- `Workspaces.qml` and `Media.qml` are self-contained (they read `WorkspaceModel` / `MprisController`
  directly), so they can be instanced in a new surface without touching bar config or popups.
- `ClockWidget.qml` is tied to `BarWidgetSwitcher` and `colOnLayer1`; a small `DemoClock.qml` reads the
  same `DateTime` service but ranks text with `Tacit.inkMain` / `Tacit.inkMeta`, matching the shell rule.
- The notch's surface recipe is reusable as-is: fixed-size `PanelWindow`, top-anchored, `WlrLayer.Top`,
  `mask: Region`, and one `DockedRect` silhouette (`edge: "top"`, frost `colPanelFrost`, `borderWidth: 0`).
- `Tacit.quiet` gives the segment style a wash of ink, so its tiles are not hand-picked colours or
  hairline-bordered cards.

## Evidence

- `modules/demo/DemoBar.qml` — the sheet and the three styles.
- `modules/demo/DemoClock.qml` — the clock adapted from `ClockWidget.qml`.
- `panelFamilies/IllogicalImpulseFamily.qml` — one loader swapped; the old loader is left commented.
- `qs log -p /home/yugaaank/Projects/tacit` — no QML errors after the shell restarts from this folder.

## Implications for the plan

- Reverting is one line: restore the `Island` `PanelLoader`, remove `DemoBar`, delete `modules/demo/`.
- If a style is kept, `plan-work` should account for extracting it out of the comparison sheet into a
  standalone surface, adding a pointer/key way out if it ever opens, and checking the bottom/top-edge
  rule with the owner (only the notch docks to the top edge today).

## What was NOT explored

- Multi-monitor behaviour beyond one `PanelWindow` per screen.
- Lock/session screens (this sheet has no reserve and is not suppressed there).
- Any change to `Config.options.*`; the demo reads defaults only.

## Recommendation

Keep as a demo. Do not merge into the shipped shell without agreement on the look (CONTRIBUTING.md,
"Ask first").
