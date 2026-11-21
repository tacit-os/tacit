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

This repo has no QML test harness. Verification is manual/live using config toggles and `qs log`.

1. **RED**: Reproduce with bar off→on→open panel; observe background taller than content.
   **GREEN**: Restore Loader `height: item?.implicitHeight`, revert all added clamps and content-root height pin; restore the original direct-child `DockedRect`/`Rectangle` in the sidebar background so no extra layout layer is introduced.
   **verify**: `qs -p <shell>` loads with `Configuration Loaded`; toggle bar off/on several times, open panel, background matches content height.

2. **RED**: Confirm no regression in bar-on floating/attached drawer styles.
   **GREEN**: no further change.
   **verify**: visual check of control panel with `drawerStyle: floating` and `attached`.

**REFACTOR**: If the shared `BarDrawerBackground` component is wanted back in the sidebar, reintroduce it only after confirming the extra Item layer does not reintroduce the stretch; keep Loader height bound to `item.implicitHeight` at all times.

## Acceptance Criteria

- [ ] Bar off→on→open panel shows background at content height (not screen height)
- [ ] No ReferenceError / binding-loop warnings in `qs log`
- [ ] Control panel works in floating and attached drawer styles
- [ ] Shell loads cleanly (`Configuration Loaded`)

## Resolution

Fix applied by reverting the sidebar geometry changes to the last-known-good state (pre-refactor) while keeping unrelated bar feature work.

