# Architecture & Design

This document details the internal architecture of `cxtool` (CrossOver Mac Bottle Shortcut & Icon Manager), explaining how its discovery, transaction, icon rendering, and lifecycle subsystems interact.

---

## The Frozen Core Lifecycle (V1.1.1)

All modifying operations in `cxtool` adhere to a strictly sequential, fail-safe lifecycle:

```text
Discover  ──▶  Validate  ──▶  Plan  ──▶  Backup (Manifest)  ──▶  Apply  ──▶  Verify  ──▶  Rollback (on failure)
```

1. **Discover**: Resolves CrossOver bottles, custom directories, macOS application wrappers, and shortcut mappings.
2. **Validate**: Verifies that the target shortcut and all associated files exist and are not in an ambiguous or corrupted state.
3. **Plan**: Calculates the exact modifications required (file moves, configuration sections, icon compilations). Displayed during `--dry-run`.
4. **Backup**: Creates a timestamped snapshot in `~/.cxtool/backups/<id>/` capturing every file scheduled for modification along with its pre-change SHA-256 hash.
5. **Apply**: Performs atomic file system operations in a safe order.
6. **Verify**: Confirms that post-change files exist, SHA-256 hashes differ as expected, and internal references remain valid.
7. **Rollback**: If any failure occurs during application or verification, previous state is immediately restored from the snapshot.

---

## Subsystems

### 1. Discovery Engine
CrossOver Mac supports multiple locations for bottles and launcher menus. `cxtool` uses a 5-tier discovery hierarchy to locate bottles:
1. **CrossOver Preferences**: Queries `com.codeweavers.CrossOver` defaults for the `BottleDir` key.
2. **Environment Variable**: Inspects `$CX_BOTTLE_PATH` (as documented in `CrossOver.conf`).
3. **Managed Bottles**: Discovers `ManagedBottleDirs` for shared or published bottles.
4. **Persistent User Configuration**: Reads `~/.cxtool.json` for custom user-registered paths.
5. **Default Fallback**: Inspects standard `~/Library/Application Support/CrossOver/Bottles`.

To locate the macOS application wrappers, `cxtool` resolves CrossOver's `ProgramsFolderBookmark` safely to identify the menu wrapper directory (typically `~/Applications/CrossOver/`).

### 2. Shortcut Matching & Disambiguation
- Matches query strings against macOS bundle names and CrossOver menu items.
- If a query ambiguously matches multiple shortcuts (e.g., `Spider-Man` matching both *Miles Morales* and *Spider-Man Remastered*), execution halts immediately with exit code 0 and presents a formatted list of candidates.
- Silent partial matching is strictly prohibited for modifying commands.

### 3. Icon Rendering & Apple `.iconset` Engine
macOS Big Sur and later mandate a 22.37% squircle corner radius with transparent insets for application icons.
- **Image Processing**: Utilizes Apple's native `CoreGraphics` and `AppKit` APIs.
- **Styles**:
  - `macos`: Proportional squircle mask with optical margin inset (standard Apple HIG aesthetic).
  - `full-bleed`: Squircle mask extending to the canvas bounds.
  - `emblem`: Scaled artwork placed over a colored or dark squircle tile.
  - `raw`: Direct pass-through without squircle masking.
- **Resolution Matrix**: Generates all 10 required Apple icon representations:
  - 16×16 (`icon_16x16.png`), 16×16@2x (`icon_16x16@2x.png`)
  - 32×32 (`icon_32x32.png`), 32×32@2x (`icon_32x32@2x.png`)
  - 128×128 (`icon_128x128.png`), 128×128@2x (`icon_128x128@2x.png`)
  - 256×256 (`icon_256x256.png`), 256×256@2x (`icon_256x256@2x.png`)
  - 512×512 (`icon_512x512.png`), 512×512@2x (`icon_512x512@2x.png` [1024×1024])
- **ICNS Compilation**: Compiles `.iconset` directories directly into native `.icns` binaries using macOS `/usr/bin/iconutil`.
- **Bottle Synchronization**: Simultaneously updates the bottle's internal `desktopdata/cxmenu` hicolor PNG hierarchy (16x16, 32x32, 48x48, 64x64, 128x128, 256x256) to maintain full consistency.

### 4. Transaction Engine & Cryptographic Manifests
- Every modification creates a directory: `~/.cxtool/backups/<timestamp>_<action>_<target>/`.
- Pre-modification and post-modification SHA-256 hashes are recorded in `manifest.json`.
- Modified files are saved with a content-hash prefix (e.g., `<hash8>_Info.plist`).
- Operations track file moves (`moved_items`) and wrapper unregistrations (`archived_apps`).
- Rollback cleanly restores moved items in reverse order, resurrects archived bundles, and overwrites modified files with original bytes.

### 5. Windows Shell Link (`.lnk`) Safety Policy
- Windows `.lnk` files are binary structures (MS-SHLLINK).
- `cxtool` **never** modifies or parses binary bytes inside `.lnk` files.
- For rename operations, the `.lnk` file is renamed on the file system, and CrossOver's `desktopdata/cxmenu` launcher script argument (`--start`) is updated. Wine resolves the destination target internally.

### 6. Non-Destructive Lifecycle Management
- **Rename**: Renames the macOS `.app` bundle, updates `CFBundleName` and helper keys in `Info.plist`, renames the section in `cxmenu.conf`, updates and renames the `desktopdata` script, and renames the Start Menu / Desktop `.lnk`.
- **Delete**: Unregisters the shortcut from `cxmenu.conf`, removes the launcher script and `.lnk` shortcuts, and moves the macOS `.app` bundle into the transaction backup archive.
- **Safety Guarantee**: Game binaries, Wine prefixes, drive_c program files, and save games are **never** removed or modified.

### 7. Process Locking
- Utilizes non-blocking POSIX `flock` on `~/.cxtool/cxtool.lock`.
- Prevents concurrent executions, automated script collisions, or simultaneous terminal invocations from corrupting CrossOver configuration files.

### 8. External Storage & Offline Safety
- Inspects target executable paths.
- If a shortcut points to an unmounted external volume (e.g., `/Volumes/ExternalDrive/...`), `cxtool` flags the target as `OFFLINE (protected) ⚠️`.
- Offline targets are protected from pruning, cache purges, or automated cleanups.
