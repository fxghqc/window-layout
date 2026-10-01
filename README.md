# Window Layout for macOS

Window Layout is a small native macOS utility that saves and restores multi-display window layouts. It includes a command-line tool and a menu bar app, and it does not depend on Moom during normal use.

## Features

- Save the current display topology and standard application windows.
- Restore display arrangement before moving and resizing windows.
- Identify displays by UUID, with vendor, model, and serial fallbacks.
- Adapt a saved layout to replacement displays with the same screen count, keeping the current arrangement.
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

On the first install, the script asks to create and trust a self-signed **Window Layout Local Code Signing** root certificate and private key in your login keychain. This identity stays on your Mac and gives application updates a stable code identity, allowing macOS to remember Accessibility permission. The private key is never added to the repository or transmitted anywhere.

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
window-layout apply "Office" --current-displays
window-layout diagnose-app com.google.Chrome
```

Layouts are stored in:

```text
~/Library/Application Support/window-layout/layouts.json
```

Set `WINDOW_LAYOUT_CONFIG` to use another configuration file.

## Replacement Displays

Choose **Apply to Current Displays** in a layout's menu bar submenu, or run:

```sh
window-layout apply "Office" --current-displays --dry-run
window-layout apply "Office" --current-displays
```

This mode requires the same number of connected displays as the saved layout. Known display identities take priority; replacement displays are mapped by resolution and position. Window positions and sizes scale proportionally to the mapped current displays. The current display arrangement and the original saved configuration are not modified. With several indistinguishable replacement displays, review the dry-run mapping first.

Regular **Apply** still matches the saved display identities and restores the saved arrangement. To remember the replacement setup permanently, save it under a new layout name or explicitly update the existing layout after arranging its windows.

Run `bash Tests/CurrentDisplaysLive.sh /path/to/window-layout` to test replacement identities against the connected displays. It uses a private temporary configuration and dry-run apply, without moving windows or changing the display arrangement.

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

## Accessibility Permission Keeps Resetting

macOS stores privacy permissions against an application's code-signing designated requirement. Ad-hoc signatures use the exact executable hash, so rebuilding an ad-hoc-signed app makes it a different application to macOS even when its name and path are unchanged.

The installer avoids this by creating and reusing a trusted local Code Signing identity, then registering the installed app with Launch Services. Verify an installed build with:

```sh
codesign -d -r- "$HOME/Applications/Window Layout.app"
```

The result should contain the bundle identifier and a certificate hash. It must not be only `designated => cdhash ...`.

To deliberately use ad-hoc signing instead, set `WINDOW_LAYOUT_SIGNING_IDENTITY=-` while installing. Accessibility permission may need to be granted again after every update.

## Chrome Window Matching

Saved windows now include a window ID scoped to the application's PID and launch time. While Chrome stays running, switching tabs, changing window order, and reconnecting displays do not change the assignment. IDs from a previous Chrome process are not reused after restart.

For old layouts and restarted Chrome sessions, only unique normalized titles are accepted. Chrome's changing English memory-usage decoration is ignored; profile names are preserved. Ambiguous, duplicate, or unrelated titles are skipped instead of assigned arbitrarily. Successfully restored Chrome windows refresh their identity and title without changing saved positions.

For existing layouts, put the windows in their intended positions and update each layout once to record identities. If windows must remain recognizable across Chrome restarts and tab changes, give them distinct names using Chrome's **Name window** command before saving. Window IDs cannot recover the intent of an old layout whose tab titles have all changed.

The ID collector uses public Core Graphics window metadata and Accessibility frames. It accepts a unique bounds match within the owning process; if metadata is unavailable or identical windows overlap, it leaves the identity unset and uses conservative title matching.

Run `bash Tests/ChromeMatchingLive.sh /path/to/window-layout` with multiple Chrome windows open to exercise save and dry-run apply using changed titles and reversed order in a private temporary configuration. It does not move windows or modify your layouts.

## Privacy

Window titles can contain private project names, document names, or URLs. The repository does not include user layout files. `Resources/layouts.example.json` contains only synthetic data.

## Development

```sh
swift build
swift test
```

The local-signing installer path has a separate macOS integration test. It creates and removes a temporary keychain and installs only into a temporary home directory:

```sh
make test-signing
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

The local signing identity is retained so reinstalling the app keeps the same identity. Remove it separately in Keychain Access only when you no longer plan to use Window Layout.

## License

MIT
