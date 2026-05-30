# simple-opds.koplugin

A clean, cover-first OPDS browser for [KOReader](https://github.com/koreader/koreader).

Adding a server opens directly into a grid of book covers — no intermediate "OPDS catalogs" list. A persistent bottom bar swaps between four configurable tabs (Home / Recent / Genre / Search by default). Covers and metadata are cached on device, downloaded in the background, and refresh in place when they land. Long feeds are paginated by swipe; alphabetical index feeds (Calibre's "By Author", "By Title", etc.) are auto-detected and get an iPhone-style A–Z scrubber on the right edge.

![Home screen](./images/home_screen.png)

## Features

- **Cover grid by default.** Tap a server → straight into a grid of covers. No multi-step navigation, no list-of-catalogs page.
- **Persistent bottom bar with four tabs.** Each tab's label, target feed, and view mode (grid or list) are configurable **per server** via a dropdown of feeds the server actually exposes — no URL typing required.
- **Auto-detected A–Z scrubber.** When the plugin sees a feed whose entries are single letters with sub-feeds (Calibre's "By Title", "By Author", "By Series", …), it swaps in an iPhone-style vertical letter strip on the right. Tap a letter to jump to that section. Letters with no entries are dimmed.
- **List view for navigation feeds.** Pick "List" instead of "Grid" for a tab and you get compact 14-rows-per-page entries with a small thumbnail, title, and author — much better for browsing category lists than 6 fat tiles.
- **Background cover downloads.** Each cover fetches in a forked subprocess so the UI never blocks on HTTP. A poller refreshes individual tiles in place as covers land, so you can swipe, tap, or search while covers are still arriving.
- **Disk cache.** Covers live under `<koreader-data>/cache/simple-opds-covers/` as `md5(url).jpg` with a 50 MB LRU cap. Atomic `.tmp` → rename writes guarantee a reader never opens a half-downloaded file.
- **Swipe pagination.** Swipe left for the next page, right for the previous. A small `1 / 7` indicator sits between the content area and the tab bar.
- **OpenSearch resolution.** Relative templates and `{startIndex?}`/`{count?}`/etc. optional placeholders are handled; multi-format `<Url>` blocks pick the Atom/OPDS one.
- **Per-server auth.** HTTP basic auth via username + password fields on the server form. Credentials persist in plain `LuaSettings` (KOReader doesn't have a keyring).

## Install

### General (any KOReader device)

1. Grab the latest `simple-opds.koplugin-<version>.zip` from the [Releases page](https://github.com/broemp/simple-opds/releases).
2. Unzip it — you'll get a folder named `simple-opds.koplugin/`.
3. Copy that folder (the whole thing, name and all) into your device's `koreader/plugins/` directory.
4. Restart KOReader (or use **⚙️ → More tools → Plugin management** to enable it without a restart).
5. **Simple OPDS** shows up in the FileManager top menu, in the same group as the built-in OPDS browser.

The plugins directory location depends on the device. Two views are useful — the path you'll see when the device is plugged in via USB ("as seen on your computer") and the absolute path KOReader itself sees ("on-device"):

| Device         | As seen on your computer (USB)                | On-device absolute path                        |
| -------------- | --------------------------------------------- | ---------------------------------------------- |
| Kindle         | `<Kindle drive>/koreader/plugins/`            | `/mnt/us/koreader/plugins/`                    |
| Kobo           | `<Kobo drive>/.adds/koreader/plugins/`        | `/mnt/onboard/.adds/koreader/plugins/`         |
| PocketBook     | `<PB drive>/applications/koreader/plugins/`   | `/mnt/ext1/applications/koreader/plugins/`     |
| reMarkable     | n/a — copy over SSH/SCP                       | `/home/root/koreader/plugins/`                 |
| Android        | The app's storage `koreader/plugins/`         | varies; check KOReader's "About → Paths"       |
| Linux desktop  | `~/.config/koreader/plugins/`                 | `$KO_HOME/plugins/` (= `~/.config/koreader/plugins/`) |

If you've ever installed another koplugin manually, the same folder you used then is the right one. On Kobo, `.adds/` is hidden by default — your file manager may need "show hidden files" turned on to see it.

### Kindle (step-by-step)

Assuming you already have [KOReader installed on your Kindle](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices):

1. **Download** the latest `simple-opds.koplugin-<version>.zip` from [Releases](https://github.com/broemp/simple-opds/releases) and unzip it on your computer. You'll get a `simple-opds.koplugin/` folder.
2. **Connect** the Kindle to your computer with a USB cable. It mounts as a USB drive named `Kindle` (or similar).
3. **Open the Kindle drive** in your file manager. At the top level you'll see folders like `documents/`, `audible/`, `system/` … and a `koreader/` folder (this is where KOReader lives). Open `koreader/plugins/`.
4. **Copy** the entire `simple-opds.koplugin/` folder into `koreader/plugins/`. After the copy, the path on your computer should look like `<Kindle drive>/koreader/plugins/simple-opds.koplugin/_meta.lua` (i.e. the `.koplugin` folder is *directly* inside `plugins/`, not nested inside another folder).
5. **Eject** the Kindle from your computer safely and unplug.
6. On the Kindle, **open KOReader**. If it was already running while you copied the folder, exit and reopen it (or restart via the gear menu).
7. The plugin should auto-enable. Open the file manager view in KOReader, tap the menu icon at the top, and look for **Simple OPDS**. Tap it to add your first server.

If the menu entry doesn't appear:
- Open **⚙️ (top bar) → More tools → Plugin management** and verify *Simple OPDS* is listed and toggled on.
- Double-check the folder layout: on the Kindle KOReader sees `/mnt/us/koreader/plugins/simple-opds.koplugin/_meta.lua`. From the computer's side that's `<Kindle drive>/koreader/plugins/simple-opds.koplugin/_meta.lua`. If you accidentally unzipped to a nested `simple-opds.koplugin/simple-opds.koplugin/…`, KOReader won't see it — move the inner folder up one level.

### From source (developers)

```sh
git clone https://github.com/broemp/simple-opds.git
ln -s "$(pwd)/simple-opds/simple-opds.koplugin" /path/to/koreader/plugins/simple-opds.koplugin
```

Useful when iterating on the code — every restart of KOReader picks up the latest edits. See **Contributing** below for the dev loop.

### Versioning

Each push to `main` runs `.github/workflows/release.yml`, which:

1. Computes a CalVer tag — `v<YYYY>.<M>.<D>` (e.g. `v2026.5.31`), incrementing a `.N` suffix for same-day rebuilds (`v2026.5.31.1`, `v2026.5.31.2`, …).
2. Rewrites the `version` field in `_meta.lua` from `"dev"` to that version in the build artifact.
3. Builds `simple-opds.koplugin-<version>.zip` and creates a GitHub release with auto-generated notes plus the zip attached.

Local checkouts always read `version = "dev"`. The injected version only lives in the release zip, so installing from git you'll see `dev`; installing from the release artifact you'll see the date-based version.

## Usage

1. **First open:** the picker prompts for a name, URL, optional username/password. Save → the shell opens straight into the server's Home tab.
2. **Configure tabs (≡ menu → Configure tabs):**
   - Tap a row to pick what feed that tab loads — the dropdown lists every navigation entry from the catalog root plus `Search` and the current feed.
   - Tap the **Grid / List** button on the same row to toggle the view mode for that tab.
3. **Navigation:**
   - Tap a category → drill in.
   - Tap a book → download flow (picks the first format your KOReader can open).
   - Swipe left / right → paginate.
   - Tap a letter in the scrubber → jump to that section.
4. **Re-bind home on the fly:** the ≡ menu also has `Edit server credentials` and `Switch server`.

Tested catalogs: Project Gutenberg, Calibre Web, Standard Ebooks (paywalled — the "New Releases" sub-feed works without auth).

## Configuration

Settings live in `<koreader-data>/settings/simple-opds.lua`. Hand-editable if you want; the in-app picker covers everything except batch operations.

| Field                    | Where it lives                       | Notes                                  |
| ------------------------ | ------------------------------------ | -------------------------------------- |
| Server list              | `servers`                            | Name, URL, optional auth, per-server tab config |
| Last used server         | `last_used`                          | Skips the picker on next open          |
| Per-server tabs          | `servers[i].tabs[1..4]`              | Each: `{ label, href, view }`          |
| Tab view mode            | `tabs[i].view`                       | `"grid"` or `"list"`                   |
| Special search href      | `tabs[i].href = "@search"`           | Opens the search prompt on tap         |

## How invalidation works

- **No TTL.** Covers stay on disk forever until evicted.
- **LRU eviction at 50 MB.** After every successful download, `cache.lua`'s `prune()` totals the directory and deletes oldest files (by `mtime`) until the total drops below the cap.
- **No server-side change detection.** No `If-Modified-Since` or `ETag` round-trips — if a server replaces a cover at the same URL, the stale one keeps showing.
- **Hash key.** `md5(cover_url)`. A URL change is effectively an invalidation; the old file sits dead until LRU sweeps it.

If you want a fresh state, `rm -rf <koreader-data>/cache/simple-opds-covers/`.

## Architecture

```
simple-opds.koplugin/
├── _meta.lua                  Plugin metadata (KOReader requires this)
├── main.lua                   Lifecycle: FileManager menu hook, server open, post-download hand-off
└── simple_opds/
    ├── settings.lua           LuaSettings CRUD for servers + tab normalisation
    ├── feed.lua               HTTP + OPDS parsing (lazy-requires OPDSParser from the bundled plugin)
    ├── cache.lua              On-disk cover store, atomic writes, LRU
    └── ui/
        ├── shell.lua          Top-level container: title bar, content, page indicator, bottom bar
        ├── bottom_bar.lua     Four custom Tab widgets (plain InputContainer + GestureRange)
        ├── grid.lua           Cover grid; exposes items_per_page() for pagination
        ├── list.lua           Compact list rows; books vs. category styled differently
        ├── tile.lua           Single grid tile; TextWidget truncation, in-place cover swap
        ├── scrubber.lua       A–Z letter strip
        └── picker.lua         Add / edit server dialog
```

The plugin is namespaced under `simple_opds/` to avoid `require()` collisions with other plugins (KOReader's plugin loader puts every plugin's root on `package.path`).

## Limitations & known issues

- **OPDS 1.x only** — the OPDS 2.0 JSON catalogs aren't parsed.
- **Passwords stored in plain text** in `simple-opds.lua`. KOReader has no keyring; the input dialog also can't mask the field reliably (upstream `MultiInputDialog` has a known issue with `text_type = "password"`).
- **No batch concurrency cap on cover fetches.** A page renders six covers → six forks. Fine in practice; could be tuned if you're on a very slow device.
- **Pagination is per-feed, not virtual scrolling.** Page state resets when you change tabs or drill into a sub-feed.

## Contributing

Bug reports and PRs welcome. The code is small (~1,500 LOC of Lua) and tries to stay readable. A new feature usually touches: feed.lua (parsing), one widget under `ui/`, and shell.lua (wiring).

To iterate locally:

```sh
# Wire the repo into a local KOReader install
ln -sfn "$(pwd)/simple-opds.koplugin" /path/to/koreader/plugins/simple-opds.koplugin

# Run KOReader with debug logging
KO_HOME=/path/to/ko-home KO_MULTIUSER=1 /path/to/koreader/reader.lua -d
```

KOReader rebuilds its Lua state on each launch (no hot reload), so changes need a restart.

## License

MIT.

---

> 🤖 **Built with heavy AI assistance.** The bulk of this plugin's code was written with [Claude Code](https://claude.com/claude-code). A human reviewed each iteration and drove the feature direction, but most line-level decisions came from the model. Treat the codebase accordingly — works in practice, but the usual caveats about AI-generated code (subtle logic errors, occasional over-abstracted bits, inconsistent style) apply.
