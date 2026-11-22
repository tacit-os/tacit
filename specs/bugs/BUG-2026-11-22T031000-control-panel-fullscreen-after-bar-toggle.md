# BUG-2026-11-22T031000: Control panel background fills screen after bar off→on toggle

## Problem

Actual: After turning the top bar off and back on, opening the control panel renders the panel's floating background at (or beyond) full screen height, while the panel contents stay at normal height. Goes away after a full shell restart.

Expected: The control panel background always matches the panel content height, regardless of bar toggle sequence.

Reproduce: (1) bar on, (2) toggle bar off via Settings, (3) toggle bar back on, (4) open control panel.

Security impact: NONE — pure UI geometry, no exploit path identified.

## Root Cause Analysis

Verified via QML runtime instrumentation (`onContentHeightChanged` logging item.implicitHeight vs item.height vs window height) while toggling `Config.options.bar.show` in a live shell.

The regression was introduced by a refactor of the sidebar geometry (commit 5886609 / d86a620 / 5500abc):

1. The Loader that hosts `SidebarRightContent` had its `height` binding changed from `item?.implicitHeight` to `item?.height`. This creates a self-referential dependency: Loader height → item.height → Loader height. During a bar toggle, a transient stretched item.height (~window height, e.g. 1164px while implicitHeight was 445px) was captured and then self-sustained by the loop. The panel background, which anchors to the content root, inherited this stretched height and filled the screen.

2. Compounding changes (content root `height: implicitHeight`, entrance-wrapper and mask clamps against `windowContent.height`) attempted to paper over the loop but used the full-screen window as the clamp ceiling, so a stale large implicitHeight resolved to full window height rather than the panel's own max.

Risk level: Medium — user-visible geometry regression, no data/security impact.

## TDD Fix Plan

Verification uses the repo's qmltestrunner harness (`tests/lib/qtscene.mjs`) plus live config toggles and `qs log`.

1. **RED**: Reproduce with bar off→on→open panel; observe background taller than content.
   **GREEN**: Replace the Loader's conditional top/bottom anchors with an explicit `y` binding (so it can never be stretched to the screen-sized wrapper), and derive the content's `maxHeight` live inside `SidebarRightContent` instead of passing it through the inline `sourceComponent`.
   **verify**: `node tests/control-panel-bar-toggle-height.test.mjs` passes; `qs log -p <path>` shows the background height stays ~405 (content height), not 1164 (window height), across an off→on→off→on sequence.

2. **RED**: Confirm no regression in bar-on floating/attached drawer styles and no state loss.
   **GREEN**: Keep `BarDrawerBackground` as the single source of floating/attached material logic; do NOT recreate the Loader on toggles (an earlier attempt did and caused flicker + state loss).
   **verify**: visual check with `drawerStyle: floating` and `attached`; toggle bar while panel states (submenu, drawer) are open and confirm they survive.

**REFACTOR**: Removed the now-unnecessary Loader-recreation `Connections` block after verifying the explicit-`y` + live-`maxHeight` changes alone fix the staleness.

## Acceptance Criteria

- [x] Bar off→on→open panel shows background at content height (not screen height) — verified via runtime instrumentation: `bgH=405` after toggle
- [x] No ReferenceError / binding-loop warnings in `qs log`
- [x] Control panel works in floating and attached drawer styles (single `BarDrawerBackground` source)
- [x] Shell loads cleanly (`Configuration Loaded`)
- [x] Panel state (submenu, drawer, focus) survives a bar toggle (no Loader recreation)

## Resolution

Fixed by positioning the sidebar content Loader with an explicit `y` instead of conditional top/bottom anchors (removing the vector that stretched it to window height), deriving `maxHeight` live inside `SidebarRightContent` instead of through a severed `sourceComponent` binding, and keeping `BarDrawerBackground` as the single floating/attached material source. An earlier attempt that recreated the Loader item on every toggle was removed after review — the two geometry changes alone fix the bug without flicker or state loss.

