# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-09-21

### Added
- **Status Dashboard (`cxtool status`)**: System overview reporting CrossOver environment paths, active bottle inventory, shortcut counts, squircle icon compliance percentage, offline/online external roots, total snapshot disk consumption, active undo availability, last transaction status, and process lock health.
- **Machine-Readable JSON Mode (`--json`)**: Uniform `snake_case` JSON output with `"schema_version": 1` across `status`, `list`, `inspect`, `verify`, and `history`.
- **Structured JSON Errors**: Standardized JSON error schema emitted on exit codes 2 (invalid usage), 3 (not found), 4 (ambiguous target), 5 (verification degraded), and 6 (lock busy) when `--json` is active.
- **Dedicated Backup Inspection & Pruning (`cxtool backups [list|prune]`)**:
  - `list`: Inspect stored snapshots with recursive folder sizes, file counts, and active undo target identification.
  - `prune`: Safe retention cleanup with dual-guard protection (`--keep <N>` and `--days <N>`).
  - **Invariants**: Active undo snapshot is permanently guarded from deletion; only terminal snapshots (`verified` or `undone`) are eligible for pruning. Supports interactive confirmation, `--dry-run`, `--force`, and `--json`.
- **Native Zsh Shell Completion (`cxtool completion zsh`)**: Embedded completion generator and checked-in `completions/_cxtool` providing autocompletion for all subcommands, options, and dynamic resolution of game shortcut and bottle names.
- **Fast Read-Only Completion Helpers (`cxtool __complete-shortcuts`, `cxtool __complete-bottles`)**: Lightweight, lock-free discovery routines designed for shell completions.

### Changed
- **Selective Process Locking**: Granular lock policy ensuring read-only commands (`status`, `list`, `inspect`, `verify`, `history`, `backups list`, `completion`) never acquire the mutation lock. Mutation commands (`set-icon`, `repair`, `rename`, `delete`, `undo`, `restore`, `backup`, `backups prune`, `config add-*`) acquire exclusive non-blocking `flock`.

## [1.1.3] - 2026-09-21

### Added
- **Standardized POSIX Exit Codes**: Deterministic exit code mapping (`0` success, `1` operation error, `2` invalid usage, `3` target not found, `4` ambiguous query, `5` integrity degraded, `6` lock collision) across all commands and disambiguation flows.
- **CI Portability & Exit Code Test Suite**: GitHub Actions workflow verifying clean-user default config generation under isolated `$HOME` and automated exit code assertions.

### Fixed
- **Clean-User Default Configuration Portability**: Eliminated hardcoded developer-specific local paths from default configuration initialization. Default config now uses generic paths (`crossover_apps_dir: "~/Applications/CrossOver"`, empty initial bottle and external game lists) and respects `$HOME` environment overrides.

### Changed
- **Policy Invariants Clarification**: Clarified in documentation that pre-execution transaction snapshots and offline storage protection are mandatory core invariants that cannot be disabled.
- **Icon Geometry & HIG Claims**: Refined wording from strict "Apple HIG 22.37% mandate" to "macOS-style squircle preset inspired by Apple icon conventions" with accurate optical margin specifications.
- **CrossOver Compatibility Statement**: Relaxed version compatibility claims to specify verified testing against the current installation rather than unverified range assertions.
- **CLI Documentation**: Documented `cxtool config add-library-dir <path>` in the README command reference.

## [1.1.2] - 2026-09-21

### Changed
- Aligned the public GitHub release tag with the complete repository documentation.
- Included README, MIT License, changelog, architecture documentation, and hardened `.gitignore` in the tagged release source.
- No changes to the frozen transaction, shortcut, icon, rollback, or CrossOver management core.

## [1.1.1] - 2026-09-21

### Added
- **Deep Integrity Audit (`cxtool verify`)**: 9-point verification auditing macOS wrapper bundles, `Info.plist` metadata, bottle associations, `cxmenu.conf` sections, launcher scripts, `.lnk` shortcuts, icon squircle compliance, target executables, and wine launch chains.
- **Transaction History (`cxtool history`)**: Human-readable ledger of previous operations displaying timestamps, actions, targets, and verified status.
- **One-Shot Undo (`cxtool undo`)**: Rollback mechanism that reverts the most recent transaction, restoring moved `.app` bundles, launcher scripts, Windows shortcuts, and modified configuration files.
- **Process Locking**: Added non-blocking POSIX `flock` locking at `~/.cxtool/cxtool.lock` to prevent concurrent writes and race conditions.
- **Version Flag**: Added `--version`, `-v`, and `version` commands reporting `cxtool 1.1.1`.

### Improved
- **Ambiguous-Name Protection**: Partial search queries matching multiple games (e.g., matching multiple editions of a game) halt and output clear candidate lists without mutating any files.
- **Multi-Resolution ICO Extraction**: Automatically detects and extracts the highest-resolution bitmap representation from multi-size Windows `.ico` files for sharp downsampling.
- **Strict Idempotency**: `repair` and `repair-all` commands evaluate corner alpha and inset radii conservatively, modifying zero files if icons already comply with Apple squircle standards.
- **Offline Storage Protection**: External drive paths that are unmounted or disconnected are flagged as `OFFLINE (protected) ⚠️`, preventing false cache purges or accidental wrapper deletion.

### Safety
- **`.lnk` Binary Policy**: Windows Shell Link (`.lnk`) binary files are never edited internally; only file locations and CrossOver launcher references are updated, preserving binary link integrity.
- **Cryptographic Snapshots**: Every modifying action captures SHA-256 pre-modification hashes and backs up files to `~/.cxtool/backups/<id>/`.
- **Non-Destructive Shortcut Removal**: `cxtool delete` removes only CrossOver integration files (`cxmenu.conf`, desktopdata launcher, shortcuts) and archives the macOS `.app` bundle, never touching game installation directories, executables, or save data.

> **Validation**: Validated through an end-to-end live lifecycle test (`verify` -> `rename --dry-run` -> `rename` -> `verify` -> `undo` -> `verify`) confirming zero regression and full rollback capability.
