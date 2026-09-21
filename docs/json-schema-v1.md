# JSON Schema Specification (v1)

This document specifies the machine-readable JSON contracts emitted by `cxtool` when invoked with the `--json` flag.

---

## Specification Guarantees

1. **Schema Versioning**:
   Every JSON response contains a top-level `"schema_version": 1`. Any non-backward-compatible change (key rename, key deletion, type alteration) will strictly increment this version number. Additions of new optional fields may occur within version 1.
2. **Stream Separation**:
   - **`stdout`**: Reserved exclusively for valid JSON payloads. No progress bars, diagnostic logs, or banner text are printed to `stdout` in `--json` mode.
   - **`stderr`**: Diagnostics, debug info, warnings, and error messages are written to `stderr`.
3. **Key Naming Convention**:
   All JSON keys strictly adhere to `snake_case`.
4. **Structured Error Handling**:
   Non-zero exit codes (such as `2`, `3`, `4`, `5`, `6`) output a standardized structured error JSON object before terminating.

---

## 1. Status Report (`cxtool status --json`)

Provides a unified health and inventory overview across the host environment, bottles, storage, and recovery subsystem.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "status",
  "environment": {
    "crossover_detected": true,
    "bottle_roots": [
      "/Users/username/Library/Application Support/CrossOver/Bottles"
    ],
    "applications_dir": "/Users/username/Applications/CrossOver"
  },
  "inventory": {
    "bottles": [
      "Steam",
      "Epic Games"
    ],
    "bottles_count": 2,
    "shortcuts_count": 20,
    "healthy_shortcuts_count": 20,
    "icon_compliant_count": 20,
    "icon_compliance_percent": 100.0
  },
  "storage": {
    "external_roots_online": [],
    "external_roots_offline": [
      "/Volumes/ExternalDrive"
    ]
  },
  "safety": {
    "snapshots_count": 5,
    "backup_disk_bytes": 12307503,
    "backup_disk_human": "12.3 MB",
    "undo_available": true,
    "last_transaction": {
      "transaction_id": "20260921_184206_rename_Game",
      "action": "rename",
      "target": "OldName_to_NewName",
      "bottle": "Steam",
      "created_at": "2026-09-21T15:42:06Z",
      "status": "undone"
    },
    "mutation_lock": "IDLE"
  }
}
```

### Field Definitions

| Field | Type | Description |
|---|---|---|
| `schema_version` | Integer | Always `1`. |
| `command` | String | Fixed string: `"status"`. |
| `environment.crossover_detected` | Boolean | Whether CrossOver installation or preferences were found. |
| `environment.bottle_roots` | Array of Strings | Discovered bottle root directories across all discovery tiers. |
| `environment.applications_dir` | String | Resolved CrossOver wrapper applications directory. |
| `inventory.bottles` | Array of Strings | Names of all detected bottles. |
| `inventory.bottles_count` | Integer | Total count of detected bottles. |
| `inventory.shortcuts_count` | Integer | Total count of registered game shortcuts. |
| `inventory.healthy_shortcuts_count` | Integer | Count of shortcuts passing all integrity checks. |
| `inventory.icon_compliant_count` | Integer | Count of shortcuts using macOS squircle compliant icons. |
| `inventory.icon_compliance_percent` | Number (Float) | Percentage of shortcuts conforming to squircle geometry (0.0 to 100.0). |
| `storage.external_roots_online` | Array of Strings | Configured external game library directories currently mounted. |
| `storage.external_roots_offline` | Array of Strings | Configured external roots currently unmounted (`OFFLINE (protected) ⚠️`). |
| `safety.snapshots_count` | Integer | Total count of transaction backup snapshots stored in `~/.cxtool/backups/`. |
| `safety.backup_disk_bytes` | Integer (64-bit) | Cumulative disk usage in bytes for all backup snapshots. |
| `safety.backup_disk_human` | String | Formatted disk usage (e.g. `"12.3 MB"`). |
| `safety.undo_available` | Boolean | Whether a reversible verified transaction is currently available for `cxtool undo`. |
| `safety.last_transaction` | Object or Null | Summary of the most recent transaction recorded in `last_action.json`. |
| `safety.mutation_lock` | String | Process lock status (`"IDLE"` or `"HELD"`). |

---

## 2. Shortcut List (`cxtool list [--bottle <name>] --json`)

Returns an inventory of discovered shortcuts. Can be filtered by bottle name using `--bottle`.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "list",
  "total": 1,
  "shortcuts": [
    {
      "name": "Game Title",
      "bottle_name": "Steam",
      "app_path": "/Users/username/Applications/CrossOver/Game Title.app",
      "menu_path": "StartMenu.C^3A_users_crossover_AppData_Roaming_Microsoft_Windows_Start+Menu/Game Title.lnk",
      "command_path": "\"/Users/username/Bottles/Steam/desktopdata/cxmenu/.../Game+Title.lnk\"",
      "icon_tag": "icon_GameTitle",
      "target_exe": "game.exe",
      "external_dependency": null,
      "is_offline": false,
      "is_squircle": true,
      "corner_alpha": 0.0,
      "is_crossover_cog": false
    }
  ]
}
```

### Field Definitions (`ShortcutInfo`)

| Field | Type | Description |
|---|---|---|
| `name` | String | Shortcut display name. |
| `bottle_name` | String | Name of the CrossOver bottle owning this shortcut. |
| `app_path` | String or Null | Absolute path to the macOS `.app` bundle wrapper. |
| `menu_path` | String or Null | Internal CrossOver `cxmenu.conf` relative section path. |
| `command_path` | String or Null | Path to the `desktopdata` helper launcher script. |
| `icon_tag` | String or Null | CrossOver icon identifier tag from `cxmenu.conf`. |
| `target_exe` | String or Null | Windows target executable filename. |
| `external_dependency` | String or Null | External storage volume dependency path if located on external media. |
| `is_offline` | Boolean | Whether the target executable resides on an unmounted external volume. |
| `is_squircle` | Boolean | Whether the primary icon conforms to macOS squircle transparency guidelines. |
| `corner_alpha` | Number (Float) | Measured corner transparency alpha value (0.0 = fully transparent/squircle). |
| `is_crossover_cog` | Boolean | Whether the shortcut uses CrossOver's default fallback cogwheel icon. |

---

## 3. Shortcut Inspection (`cxtool inspect "<name>" --json`)

Dumps the complete configuration, filesystem paths, and `.icns` checksum for a specific shortcut.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "inspect",
  "shortcut": {
    "name": "Game Title",
    "bottle_name": "Steam",
    "app_path": "/Users/username/Applications/CrossOver/Game Title.app",
    "menu_path": "StartMenu.C^3A_users_crossover_AppData_Roaming_Microsoft_Windows_Start+Menu/Game Title.lnk",
    "command_path": "\"/Users/username/Bottles/Steam/desktopdata/cxmenu/.../Game+Title.lnk\"",
    "icon_tag": "icon_GameTitle",
    "target_exe": "game.exe",
    "external_dependency": null,
    "is_offline": false,
    "is_squircle": true,
    "corner_alpha": 0.0,
    "is_crossover_cog": false
  },
  "icns_file": "/Users/username/Applications/CrossOver/Game Title.app/Contents/Resources/CrossOverHelper.icns",
  "icns_sha256": "9bf01617b6dead3467cceb1d830eebac3e2c5cf1a2123789d26a8000d614ed2a"
}
```

---

## 4. Integrity Verification (`cxtool verify "<name>" --json`)

Performs a 9-point deep integrity audit across macOS wrapper bundles, plist keys, bottle configurations, launchers, and `.lnk` files.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "verify",
  "target": "Game Title",
  "bottle": "Steam",
  "healthy": true,
  "overall_status": "healthy",
  "target_executable_status": "OK ✅",
  "checks": {
    "wrapper_exists": true,
    "plist_ok": true,
    "bottle_ok": true,
    "cxmenu_ok": true,
    "launcher_ok": true,
    "windows_shortcut_ok": true,
    "icon_squircle_ok": true,
    "launch_chain_valid": true
  }
}
```

### Exit Codes & Health States
- If all checks pass: `healthy: true`, `overall_status: "healthy"`, exit code `0`.
- If any check fails: `healthy: false`, `overall_status: "degraded"`, exit code `5`.

---

## 5. Transaction History (`cxtool history --json`)

Returns the ledger of transaction manifests recorded in `~/.cxtool/backups/`.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "history",
  "total": 1,
  "transactions": [
    {
      "transaction_id": "20260921_184206_rename_Game",
      "action": "rename",
      "target": "OldName_to_NewName",
      "bottle": "Steam",
      "created_at": "2026-09-21T15:42:06Z",
      "files": [
        {
          "path": "/Users/username/Applications/CrossOver/Game.app/Contents/Info.plist",
          "sha256_before": "b9c3392c1ab3fc2752b85ceca17018fab47a920f6a1a5afa91de3da124e4777a",
          "sha256_after": "none",
          "backup_name": "b9c3392c_Info.plist"
        }
      ],
      "verified": true,
      "undone": false,
      "moved_items": [
        {
          "from": "/path/to/old",
          "to": "/path/to/new"
        }
      ],
      "archived_apps": []
    }
  ]
}
```

---

## 6. Backups Snapshot Inventory (`cxtool backups [list] --json`)

Lists all backup snapshots stored on disk with size breakdowns and active undo target identification.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "backups",
  "total_snapshots": 1,
  "total_disk_bytes": 10306,
  "total_disk_human": "10 KB",
  "snapshots": [
    {
      "transaction_id": "20260921_184206_rename_Game",
      "action": "rename",
      "target": "OldName_to_NewName",
      "bottle": "Steam",
      "created_at": "2026-09-21T15:42:06Z",
      "touched_files_count": 4,
      "disk_bytes": 10306,
      "disk_human": "10 KB",
      "status": "verified",
      "is_active_undo": true
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `snapshots[].is_active_undo` | Boolean | `true` if this snapshot is the target of the next `cxtool undo` operation. **Permanently guarded against pruning.** |
| `snapshots[].status` | String | `"verified"`, `"undone"`, or `"unverified"`. |

---

## 7. Backups Pruning (`cxtool backups prune --json`)

Reports snapshots pruned or scheduled for pruning under the dual-retention policy.

### Payload Schema

```json
{
  "schema_version": 1,
  "command": "backups_prune",
  "dry_run": true,
  "pruned_count": 2,
  "reclaimed_bytes": 204800,
  "reclaimed_human": "200 KB",
  "preserved_count": 5,
  "pruned_snapshots": [
    "20260910_120000_set_icon_OldGame",
    "20260911_150000_repair_OldGame"
  ]
}
```

### Retention Policy Invariants
1. `is_active_undo == true` is never pruned.
2. Incomplete or unverified snapshots (`verified != true && undone != true`) are never pruned.
3. Candidate snapshots must satisfy **both** `index >= keep` and `age_days >= days`.
4. `--keep` and `--days` accept only non-negative integers; invalid values return exit code `2`.

---

## 8. Structured Error Payload (`error`)

When `--json` is supplied, non-zero exits (POSIX exit codes 2, 3, 4, 5, 6) emit a structured error object to `stdout` before exiting.

### Standard Error Schema

```json
{
  "schema_version": 1,
  "error": {
    "code": 3,
    "type": "target_not_found",
    "message": "No shortcut found matching \"NonExistentGame\"."
  }
}
```

### Ambiguous Query Error Schema (Exit Code 4)

When a query matches multiple candidate shortcuts, `matches` contains the candidate strings:

```json
{
  "schema_version": 1,
  "error": {
    "code": 4,
    "type": "ambiguous_target",
    "message": "Ambiguous query \"Spider\". Matches multiple shortcuts.",
    "matches": [
      "Marvel's Spider-Man - Miles Morales (Bottle: Steam)",
      "Marvel's Spider-Man Remastered (Bottle: Steam)"
    ]
  }
}
```

### Error Types & Exit Codes

| Exit Code | `error.type` | Trigger |
|:---:|---|---|
| `2` | `"invalid_usage"` / `"unknown_command"` | Missing required arguments, bad options, unknown subcommand. |
| `3` | `"target_not_found"` | Requested shortcut or bottle was not found. |
| `4` | `"ambiguous_target"` | Search query matches more than one candidate. |
| `5` | `"integrity_degraded"` | `verify` detected one or more failed integrity checks. |
| `6` | `"lock_collision"` | An exclusive mutation lock is currently held by another process. |
| `1` | `"operation_error"` | Unexpected filesystem or transaction failure. |

---

## Integration Guidelines

- **jq Validation**: Scripts can reliably assert `.schema_version == 1` to ensure API compatibility.
- **Silent Pipelines**: Pipe `stdout` directly to downstream parsers (e.g. `cxtool status --json | jq .inventory.shortcuts_count`).
- **Error Checking**: Check the shell exit code (`$?`) first or parse `.error.code` directly from the payload.
