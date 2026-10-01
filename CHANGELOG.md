# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Add `apply --current-displays` and an **Apply to Current Displays** menu action for replacement monitors with the same screen count. Preserve known display matches, proportionally adapt windows, and leave the current arrangement and saved configuration unchanged.
- Return a failure status when regular apply cannot match or restore displays, rather than showing a misleading success alert.
- Refuse save/apply when no active displays are available, preventing empty layouts from replacing saved configurations while the desktop is asleep or unavailable.

- Verify actual window frames after resize/move, retry boundedly on the same window, and recheck the full batch before reporting success.
- Wait for consecutive matching display topology samples and prevent overlapping menu bar operations.
- Report windows that remain constrained or unresponsive as failures instead of claiming the layout was applied.

- Preserve Chrome window assignments through tab changes using process-scoped window IDs.
- Plan matches before moving windows; reserve unique titles and skip ambiguous Chrome matches instead of guessing.
- Ignore Chrome's changing memory-usage title decoration and retain profile suffixes.

- Sign local installations with a persistent self-signed Code Signing identity so macOS Accessibility permission survives application updates.
- Refuse stable-identity installs when the resulting designated requirement is still tied to a single executable `cdhash`.
- Register the installed app with Launch Services so it can be added in Accessibility settings.

## 0.1.0 - 2026-09-01

- Save and restore multi-display window layouts.
- Match displays by UUID with vendor, model, and serial fallbacks.
- Restore display topology before moving windows.
- Match windows by bundle identifier and title similarity.
- Provide CLI and menu bar interfaces.
- Import existing Moom snapshots.
- Diagnose per-process macOS Accessibility failures.
