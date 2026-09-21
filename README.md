# CX-Tools

[![CI](https://github.com/kirolos-esmat/CX-Tools/actions/workflows/ci.yml/badge.svg)](https://github.com/kirolos-esmat/CX-Tools/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/kirolos-esmat/CX-Tools)](https://github.com/kirolos-esmat/CX-Tools/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **A transaction-safe CrossOver Mac bottle shortcut and icon manager.**

`cxtool` is a native, zero-dependency Swift CLI utility designed to manage, inspect, repair, rename, and safely unregister CrossOver Mac game shortcuts and application icons with cryptographic transaction snapshots and instant rollback.

---

## Features

- **Automatic Bottle Discovery**: Automatically locates CrossOver bottles using CrossOver's `BottleDir` user preference, `$CX_BOTTLE_PATH` environment settings, `ManagedBottleDirs`, user configuration (`~/.cxtool.json`), and default system paths.
- **macOS Squircle Icon Engine**: Automatically converts sharp or square Windows icons into native macOS-style squircle presets inspired by Apple icon conventions.
  - Supports `macos` (default squircle with optical margin), `full-bleed`, `emblem` (custom background fill), and `raw` styles.
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
  - **Mandatory Policy**: Transaction snapshots and offline storage protection are core invariants and cannot be disabled.
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
- **Idempotency**: Running `cxtool repair-all` multiple times inspects corner transparency and padding; if an icon already conforms to macOS squircle standards, zero files are modified.

---

## Supported Commands

```bash
# Inspection & Diagnostics
cxtool status [--json]                              # High-level system, inventory, storage & safety dashboard
cxtool doctor                                       # Comprehensive environment and path audit
cxtool list [--bottle <name>] [--json]              # Tabular overview of all shortcuts and icon status
cxtool inspect "Game Name" [--json]                 # Full CrossOver configuration dump for a game
cxtool verify "Game Name" [--json]                  # 9-point deep audit of launch chain & shortcut integrity

# Icon Management
cxtool set-icon "Game Name" /path/to/art.png [--style macos|full-bleed|emblem|raw] [--bg black|white|#hex] [--scale <float>]
cxtool repair "Game Name"                           # Convert a specific game's icon to a macOS squircle
cxtool repair-all [--dry-run]                       # Scan and safely repair all non-squircle icons (idempotent)

# Lifecycle Operations
cxtool rename "Old Name" "New Name" [--dry-run]
cxtool delete "Game Name" [--dry-run] [--force]

# Safety, History & Backups
cxtool history [--json]                             # View ledger of transactions
cxtool undo                                         # Revert the most recent verified transaction
cxtool backup [--note "text"]                       # Create a manual snapshot of CrossOver menus and icons
cxtool restore <backup-id>                          # Rollback to a specific snapshot ID
cxtool backups [list] [--json]                      # Inspect snapshots with disk usage and undo target
cxtool backups prune [--keep <N>] [--days <N>] [--dry-run] [--force] [--json] # Prune old snapshots safely
cxtool config [show|add-bottle-dir|add-library-dir] # Manage persistent bottle and search paths

# Shell Completion
cxtool completion zsh                               # Output native Zsh completion function

# Version
cxtool --version                                    # Print version (1.2.0)
```

---

## Requirements

- **macOS**: macOS 11 (Big Sur) or newer.
- **CrossOver Mac**: Tested against the author's current CrossOver installation. Other recent versions using the same bottle/menu structure may also work.
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

## Shell Completion (Zsh)

Generate and install native Zsh completion for `cxtool`:

```bash
# Option 1: Load directly in current session
source <(cxtool completion zsh)

# Option 2: Install to your user Zsh completions directory
mkdir -p ~/.zfunc
cxtool completion zsh > ~/.zfunc/_cxtool

# Add to ~/.zshrc (before compinit):
#   fpath=(~/.zfunc $fpath)
#   autoload -Uz compinit && compinit
```

---

## Version

Current stable release: **`1.2.0 Stable`**

For architectural details, refer to [Architecture Documentation](docs/architecture.md).  
For release history, see [CHANGELOG.md](CHANGELOG.md).

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
