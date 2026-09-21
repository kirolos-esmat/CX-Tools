# CX-Tools

> **A transaction-safe CrossOver Mac bottle shortcut and icon manager.**

`cxtool` is a native, zero-dependency Swift CLI utility designed to manage, inspect, repair, rename, and safely unregister CrossOver Mac game shortcuts and application icons with cryptographic transaction snapshots and instant rollback.

---

## Features

- **Automatic Bottle Discovery**: Automatically locates CrossOver bottles using CrossOver's `BottleDir` user preference, `$CX_BOTTLE_PATH` environment settings, `ManagedBottleDirs`, user configuration (`~/.cxtool.json`), and default system paths.
- **macOS Squircle Icon Engine**: Automatically converts sharp or square Windows icons into native macOS Big Sur+ squircles adhering to Apple Human Interface Guidelines.
  - Supports `macos` (default HIG squircle with optical margin), `full-bleed`, `emblem` (custom background fill), and `raw` styles.
  - Extracts the highest-resolution bitmap from multi-resolution `.ico` binaries.
  - Generates the complete 10-representation Apple `.iconset` specification and compiles `.icns` binaries via `/usr/bin/iconutil`.
  - Concurrently synchronizes the bottle's internal `desktopdata/cxmenu` hicolor PNG tree.
- **Non-Destructive Shortcut Lifecycle**:
  - **Safe Rename**: Renames macOS `.app` bundles, updates internal `Info.plist` metadata, updates `cxmenu.conf`, renames `desktopdata` launcher scripts, and renames Windows `.lnk` shortcuts.
  - **Safe Deletion**: Unregisters shortcuts from CrossOver menus and safely archives the `.app` bundle into a snapshot directory. **Game installations, Wine prefixes, and save games are never touched.**
  - **`.lnk` Binary Guarantee**: Windows Shell Link (`.lnk`) binary internals are **never modified or parsed**; only file paths and launcher arguments are updated.
- **Deep 9-Point Verification (`cxtool verify`)**: Audits wrapper existence, `Info.plist` keys, bottle associations, `cxmenu.conf` sections, launcher scripts, `.lnk` integrity, icon squircle compliance, target executables, and wine launch chains.
- **Cryptographic Safety & Rollback**:
  - Every modification takes a pre-execution snapshot with SHA-256 manifests in `~/.cxtool/backups/`.
  - **One-Shot Undo (`cxtool undo`)**: Automatically reverses the most recent operation, restoring moved files and archived apps.
  - **Transaction History (`cxtool history`)**: Displays an audit log of past actions with verification statuses.
- **Concurrency Protection**: Non-blocking POSIX process locking (`flock`) on `~/.cxtool/cxtool.lock` prevents race conditions.
- **External Storage Safety**: Detects shortcuts located on unmounted external volumes (e.g. `/Volumes/...`) and marks them as `OFFLINE (protected) ⚠️` to prevent accidental pruning or broken state.

---

## Safety Model

`cxtool` guarantees that all modifying actions follow a fail-safe, transactional execution flow:

```text
Discover  ──▶  Validate  ──▶  Plan  ──▶  Backup (Manifest)  ──▶  Apply  ──▶  Verify  ──▶  Rollback (on failure)
```

- **Non-Destructive Guarantee**: `cxtool delete` only removes CrossOver integration wrappers and launcher registrations. Game directories, executables, and save files are strictly preserved.
- **Binary Link Safety**: `.lnk` shortcuts are treated as opaque binaries. They are relocated or renamed as whole files without altering internal bytes.
- **Idempotency**: Running `cxtool repair-all` multiple times inspects corner transparency and padding; if an icon already conforms to Apple guidelines, zero files are modified.

---

## Supported Commands

```bash
# Inspection & Diagnostics
cxtool doctor                         # Comprehensive environment and path audit
cxtool list [--bottle <name>]         # Tabular overview of all shortcuts and icon status
cxtool inspect "Game Name"            # Full CrossOver configuration dump for a game
cxtool verify "Game Name"             # 9-point deep audit of launch chain & shortcut integrity

# Icon Management
cxtool set-icon "Game Name" /path/to/art.png [--style macos|full-bleed|emblem|raw] [--bg black|white|#hex] [--scale <float>]
cxtool repair "Game Name"             # Convert a specific game's icon to a macOS squircle
cxtool repair-all [--dry-run]         # Scan and safely repair all non-squircle icons (idempotent)

# Lifecycle Operations
cxtool rename "Old Name" "New Name" [--dry-run]
cxtool delete "Game Name" [--dry-run] [--force]

# Safety, History & Backups
cxtool history                        # View ledger of transactions
cxtool undo                           # Revert the most recent verified transaction
cxtool backup [--note "text"]         # Create a manual snapshot of CrossOver menus and icons
cxtool restore <backup-id>            # Rollback to a specific snapshot ID
cxtool config [show|add-bottle-dir]   # Manage persistent bottle and search paths

# Version
cxtool --version                      # Print version (1.1.1)
```

---

## Requirements

- **macOS**: macOS 11 (Big Sur) or newer.
- **CrossOver Mac**: CrossOver 21, 22, 23, or 24.
- **Build Tools**: Apple Swift compiler (`swiftc`) and `/usr/bin/iconutil` (both standard with Xcode Command Line Tools).
- **Runtime Dependencies**: **Zero**. `cxtool` compiles to a single native binary using macOS system frameworks (`Foundation`, `AppKit`, `CoreGraphics`, `CryptoKit`).

---

## Build & Install

### 1. Compile
Clone the repository and compile with optimizations:

```bash
swiftc -O cx_shortcut_mgr.swift -o cxtool
chmod +x cxtool
```

### 2. Install (User-Local)
Copy the binary to a directory in your `$PATH` (e.g. `~/.local/bin`):

```bash
mkdir -p ~/.local/bin
cp cxtool ~/.local/bin/cxtool
chmod +x ~/.local/bin/cxtool
```

Alternatively, create a symbolic link during development:

```bash
ln -sf "$(pwd)/cxtool" ~/.local/bin/cxtool
```

---

## First Run & Dry-Run Mode

### Recommended First Steps
Before making any modifications, run the environment check and shortcut inventory:

```bash
cxtool doctor
cxtool list
```

### Safe Preview with `--dry-run`
Any command that modifies files (`repair-all`, `rename`, `delete`) supports the `--dry-run` flag to display the exact planned changes without writing anything to disk:

```bash
cxtool rename "Current Title" "New Title" --dry-run
cxtool delete "Obsolete Game" --dry-run
cxtool repair-all --dry-run
```

---

## Version

Current stable release: **`1.1.1 Stable`**

For architectural details, refer to [Architecture Documentation](docs/architecture.md).  
For release history, see [CHANGELOG.md](CHANGELOG.md).

---

## Roadmap (Planned V1.2 — Usability Focus)

The core lifecycle (`discover → validate → backup → apply → verify → rollback`) is locked and stable. Planned enhancements for **V1.2** focus strictly on usability and CLI integrations:

- **`cxtool status`**: Quick terminal dashboard summarizing total shortcuts, squircle compliance percentage, active bottles, and storage health.
- **`--json` Output**: Machine-readable JSON output for `list`, `inspect`, `verify`, and `history` to support scripting and Raycast / Shortcuts extensions.
- **`cxtool backups`**: Dedicated snapshot manager to list, inspect, and safely prune backups.
- **Rolling Retention Policy**: Automatic retention limit (e.g. retaining the 20 most recent snapshots in `~/.cxtool/backups/`) to prevent indefinite storage growth.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
