# Window Layout for macOS

Window Layout is a small native macOS utility that saves and restores multi-display window layouts. It includes a command-line tool and a menu bar app, and it does not depend on Moom during normal use.

## Features

- Save the current display topology and standard application windows.
- Restore display arrangement before moving and resizing windows.
- Identify displays by UUID, with vendor, model, and serial fallbacks.
- Match windows by application bundle identifier and window-title similarity.
- Use layouts from a menu bar icon or the `window-layout` CLI.
- Update an existing layout from the current desktop.
- Import Moom snapshots once, then operate independently.
- Report Accessibility failures separately from applications that are not running.

## Requirements

- macOS 13 or later.
- Xcode Command Line Tools or Xcode with Swift 5.10 or later.
- Accessibility permission for Window Layout when macOS requests it.

## Install

```sh
git clone https://github.com/fxghqc/window-layout.git
cd window-layout
./scripts/install.sh
```

The installer builds both executables, installs the CLI at `~/.local/bin/window-layout`, creates `~/Applications/Window Layout.app`, and preserves an existing layout configuration.

Open the menu bar app later with:

```sh
open "$HOME/Applications/Window Layout.app"
```

To launch it automatically, add `Window Layout.app` under **System Settings > General > Login Items**.

## CLI

```sh
window-layout list
window-layout save "Home"
window-layout inspect "Home"
window-layout check "Home"
window-layout arrange "Home" --dry-run
window-layout apply "Home" --dry-run
window-layout apply "Home"
window-layout diagnose-app com.google.Chrome
```

Layouts are stored in:

```text
~/Library/Application Support/window-layout/layouts.json
```

Set `WINDOW_LAYOUT_CONFIG` to use another configuration file.

## Moom Migration

Moom is only required while importing its saved snapshots:

```sh
window-layout import-moom "Office" "Home"
```

Review the imported layout with `window-layout inspect`, then use `save` to refresh display identities on the current Mac.

## How Matching Works

When applying a layout, Window Layout first matches connected displays to the saved identities and restores their origins. It then finds running application windows by bundle identifier. When one application has several windows, saved and live titles are scored to select the closest unused window.

Only standard, non-minimized Accessibility windows are saved. Missing applications or windows are skipped without aborting the rest of the layout.

## Chrome Troubleshooting

Chrome may occasionally keep running after an internal restart while its macOS Accessibility endpoint is unavailable. Diagnose it with:

```sh
window-layout diagnose-app com.google.Chrome
```

If every normal Chrome process reports `axError=-25211`, quit and reopen Chrome. Window Layout reports this state as `accessibility unavailable` rather than incorrectly saying Chrome is not running.

## Privacy

Window titles can contain private project names, document names, or URLs. The repository does not include user layout files. `Resources/layouts.example.json` contains only synthetic data.

## Development

```sh
swift build
swift test
```

The project contains three Swift targets:

- `WindowLayoutCore`: configuration models and pure matching/coordinate logic.
- `WindowLayoutCLI`: display discovery, Accessibility integration, save/apply commands, and Moom import.
- `WindowLayoutMenu`: the menu bar interface.

## Uninstall

```sh
./scripts/uninstall.sh
```

Saved layouts are retained by default. Use `./scripts/uninstall.sh --purge` to remove them as well.

## License

MIT
