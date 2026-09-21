# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
