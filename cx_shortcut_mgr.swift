import Foundation
import AppKit
import CryptoKit

// MARK: - Provenance & Data Models

enum Provenance: String, Codable {
    case crossoverPrefs = "CrossOver BottleDir (Primary)"
    case envVar = "CX_BOTTLE_PATH (Env)"
    case managed = "ManagedBottleDirs (Shared)"
    case userConfig = "Config (~/.cxtool.json)"
    case defaultFallback = "Default Fallback"
}

struct BottleRoot: Hashable {
    let path: String
    let provenance: Provenance
    let exists: Bool
}

struct Config: Codable {
    var bottle_directories: [String]
    var auto_detect_crossover_bottles: Bool
    var crossover_apps_dir: String
    var external_game_roots: [String]
    var default_style: String

    // Optional legacy fields for backwards compatibility with existing ~/.cxtool.json
    var backup_before_write: Bool?
    var offline_roots_are_non_destructive: Bool?

    static let defaultConfig = Config(
        bottle_directories: [],
        auto_detect_crossover_bottles: true,
        crossover_apps_dir: "~/Applications/CrossOver",
        external_game_roots: [],
        default_style: "macos",
        backup_before_write: nil,
        offline_roots_are_non_destructive: nil
    )
}

struct ShortcutInfo: Codable {
    let name: String
    let bottleName: String
    let appPath: String?
    let menuPath: String?
    let commandPath: String?
    let iconTag: String?
    let targetExe: String?
    let externalDependency: String?
    let isOffline: Bool
    let isSquircle: Bool
    let cornerAlpha: CGFloat
    let isCrossoverCog: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case bottleName = "bottle_name"
        case appPath = "app_path"
        case menuPath = "menu_path"
        case commandPath = "command_path"
        case iconTag = "icon_tag"
        case targetExe = "target_exe"
        case externalDependency = "external_dependency"
        case isOffline = "is_offline"
        case isSquircle = "is_squircle"
        case cornerAlpha = "corner_alpha"
        case isCrossoverCog = "is_crossover_cog"
    }
}

struct ListReport: Codable {
    var schema_version: Int = 1
    var command: String = "list"
    let total: Int
    let shortcuts: [ShortcutInfo]
}

struct InspectReport: Codable {
    var schema_version: Int = 1
    var command: String = "inspect"
    let shortcut: ShortcutInfo
    let icns_file: String?
    let icns_sha256: String?
}

struct VerifyChecks: Codable {
    let wrapper_exists: Bool
    let plist_ok: Bool
    let bottle_ok: Bool
    let cxmenu_ok: Bool
    let launcher_ok: Bool
    let windows_shortcut_ok: Bool
    let icon_squircle_ok: Bool
    let launch_chain_valid: Bool
}

struct VerifyReport: Codable {
    var schema_version: Int = 1
    var command: String = "verify"
    let target: String
    let bottle: String
    let healthy: Bool
    let overall_status: String
    let target_executable_status: String
    let checks: VerifyChecks
}

struct HistoryReport: Codable {
    var schema_version: Int = 1
    var command: String = "history"
    let total: Int
    let transactions: [TransactionManifest]
}

struct EnvironmentStatus: Codable {
    let crossover_detected: Bool
    let bottle_roots: [String]
    let applications_dir: String
}

struct InventoryStatus: Codable {
    let bottles_count: Int
    let bottles: [String]
    let shortcuts_count: Int
    let healthy_shortcuts_count: Int
    let icon_compliant_count: Int
    let icon_compliance_percent: Double
}

struct StorageStatus: Codable {
    let external_roots_online: [String]
    let external_roots_offline: [String]
}

struct LastTransactionSummary: Codable {
    let transaction_id: String
    let action: String
    let target: String
    let bottle: String
    let created_at: String
    let status: String
}

struct SafetyStatus: Codable {
    let snapshots_count: Int
    let backup_disk_bytes: Int64
    let backup_disk_human: String
    let undo_available: Bool
    let last_transaction: LastTransactionSummary?
    let mutation_lock: String
}

struct StatusReport: Codable {
    var schema_version: Int = 1
    var command: String = "status"
    let environment: EnvironmentStatus
    let inventory: InventoryStatus
    let storage: StorageStatus
    let safety: SafetyStatus
}

struct BackupSnapshotItem: Codable {
    let transaction_id: String
    let action: String
    let target: String
    let bottle: String
    let created_at: String
    let touched_files_count: Int
    let disk_bytes: Int64
    let disk_human: String
    let status: String
    let is_active_undo: Bool
}

struct BackupsListReport: Codable {
    var schema_version: Int = 1
    var command: String = "backups"
    let total_snapshots: Int
    let total_disk_bytes: Int64
    let total_disk_human: String
    let snapshots: [BackupSnapshotItem]
}

struct PruneReport: Codable {
    var schema_version: Int = 1
    var command: String = "backups_prune"
    let dry_run: Bool
    let pruned_count: Int
    let reclaimed_bytes: Int64
    let reclaimed_human: String
    let preserved_count: Int
    let pruned_snapshots: [String]
}

struct CXErrorDetail: Codable {
    let code: Int
    let type: String
    let message: String
    let matches: [String]?
}

struct CXErrorPayload: Codable {
    var schema_version: Int = 1
    let error: CXErrorDetail
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useAll]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func recursiveDirectorySize(at url: URL) -> Int64 {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
        return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
           resourceValues.isDirectory == false {
            total += Int64(resourceValues.fileSize ?? 0)
        }
    }
    return total
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func exitWithError(code: Int32, type: String, message: String, matches: [String]? = nil, isJSON: Bool) -> Never {
    if isJSON {
        let payload = CXErrorPayload(error: CXErrorDetail(code: Int(code), type: type, message: message, matches: matches))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload), let jsonStr = String(data: data, encoding: .utf8) {
            print(jsonStr)
        }
    } else {
        FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
        if let matches = matches {
            for m in matches {
                FileHandle.standardError.write(Data("  - \(m)\n".utf8))
            }
        }
    }
    exit(code)
}

struct FileHashRecord: Codable {
    let path: String
    let before_sha256: String
    var after_sha256: String
}

struct MovedItemRecord: Codable {
    let from: String
    let to: String
}

struct TransactionManifest: Codable {
    let transaction_id: String
    let action: String
    let target: String
    let bottle: String
    let created_at: String
    var files: [FileHashRecord]
    var verified: Bool
    var undone: Bool?
    var moved_items: [MovedItemRecord]?
    var archived_apps: [MovedItemRecord]?
}

let cxtoolZshCompletionScript = #"""
#compdef cxtool

_cxtool() {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    local -a commands=(
        'status:System & shortcut health dashboard'
        'list:List all CrossOver shortcuts and icon status'
        'inspect:Inspect full configuration for a game shortcut'
        'verify:Audit launch chain and shortcut integrity'
        'set-icon:Update game icon to macOS squircle preset'
        'repair:Convert specific game icon to squircle'
        'repair-all:Scan and safely repair all non-squircle icons'
        'rename:Safely rename shortcut across macOS wrapper and bottle'
        'delete:Safely unregister shortcut (never deletes game data)'
        'history:Display ledger of past transactions'
        'undo:Revert the most recent verified transaction'
        'backup:Create a manual snapshot of CrossOver menus and icons'
        'restore:Rollback to a previously saved snapshot'
        'backups:Inspect and prune transaction snapshots'
        'config:Manage persistent paths and preferences'
        'doctor:Perform environment and path diagnostics'
        'completion:Generate shell completion script'
    )

    _arguments -C \
        '1: :->command' \
        '*:: :->args'

    case $state in
        command)
            _describe -t commands 'cxtool command' commands
            ;;
        args)
            case $words[1] in
                status)
                    _arguments \
                        '--json[Output structured machine-readable JSON]'
                    ;;
                list)
                    _arguments \
                        '--bottle[Filter shortcuts by bottle name]:bottle:->bottles' \
                        '--json[Output structured machine-readable JSON]' \
                        '--verbose[Show internal paths]'
                    ;;
                inspect|verify)
                    _arguments \
                        '1:shortcut:->shortcuts' \
                        '--json[Output structured machine-readable JSON]'
                    ;;
                repair)
                    _arguments \
                        '1:shortcut:->shortcuts' \
                        '--dry-run[Preview changes without modifying disk]'
                    ;;
                repair-all)
                    _arguments \
                        '--dry-run[Preview changes without modifying disk]'
                    ;;
                set-icon)
                    _arguments \
                        '1:shortcut:->shortcuts' \
                        '2:image file:_files -g "*.png *.jpg *.jpeg *.ico *.icns"' \
                        '--style[Icon rendering style]:style:(macos full-bleed emblem raw)' \
                        '--bg[Background fill color]:color:(black white #1a1a1a #000000 #ffffff)' \
                        '--scale[Optical scaling factor]:scale:(0.75 0.80 0.85 0.90 1.0)' \
                        '--dry-run[Preview changes without modifying disk]'
                    ;;
                rename)
                    _arguments \
                        '1:shortcut:->shortcuts' \
                        '2:new name:' \
                        '--dry-run[Preview changes without modifying disk]'
                    ;;
                delete)
                    _arguments \
                        '1:shortcut:->shortcuts' \
                        '--dry-run[Preview changes without modifying disk]' \
                        '--force[Bypass confirmation prompt]'
                    ;;
                backups)
                    local -a backup_subcommands=(
                        'list:List all stored snapshots with disk usage'
                        'prune:Prune old snapshots using retention policy'
                    )
                    if (( CURRENT == 2 )); then
                        _describe -t backup_subcommands 'backups command' backup_subcommands
                    else
                        case $words[2] in
                            prune)
                                _arguments \
                                    '--keep[Number of newest snapshots to retain (default 10)]:(5 10 20)' \
                                    '--days[Age threshold in days for pruning (default 30)]:(7 14 30 60 90)' \
                                    '--dry-run[Preview snapshots to be deleted without modifying disk]' \
                                    '--force[Bypass interactive confirmation prompt]' \
                                    '--json[Output structured machine-readable JSON]'
                                ;;
                            list)
                                _arguments \
                                    '--json[Output structured machine-readable JSON]'
                                ;;
                        esac
                    fi
                    ;;
                restore)
                    _arguments \
                        '1:snapshot id:'
                    ;;
                backup)
                    _arguments \
                        '--note[Optional note describing backup]:note:'
                    ;;
                config)
                    local -a config_subcommands=(
                        'show:Display active configuration'
                        'add-bottle-dir:Add custom bottle root path'
                        'add-library-dir:Add external game library path'
                    )
                    _describe -t config_subcommands 'config command' config_subcommands
                    ;;
                completion)
                    _arguments \
                        '1:shell:(zsh)'
                    ;;
                history)
                    _arguments \
                        '--json[Output structured machine-readable JSON]'
                    ;;
            esac
            ;;
    esac

    case $state in
        shortcuts)
            local -a shortcuts
            shortcuts=("${(@f)$(cxtool __complete-shortcuts 2>/dev/null)}")
            _describe -t shortcuts 'game shortcut' shortcuts
            ;;
        bottles)
            local -a bottles
            bottles=("${(@f)$(cxtool __complete-bottles 2>/dev/null)}")
            _describe -t bottles 'crossover bottle' bottles
            ;;
    esac
}

_cxtool "$@"
"""#

func currentUserHomeDirectory() -> URL {
    if let envHome = ProcessInfo.processInfo.environment["HOME"], !envHome.isEmpty {
        return URL(fileURLWithPath: envHome)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

// MARK: - Process Lock

class ProcessLock {
    static let shared = ProcessLock()
    private var lockFd: Int32 = -1
    private let lockPath: String

    init() {
        let home = currentUserHomeDirectory().path
        let dir = "\(home)/.cxtool"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        lockPath = "\(dir)/cxtool.lock"
    }

    func acquire() -> Bool {
        lockFd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard lockFd >= 0 else { return false }
        let rc = flock(lockFd, LOCK_EX | LOCK_NB)
        if rc != 0 {
            close(lockFd)
            lockFd = -1
            return false
        }
        return true
    }

    func release() {
        if lockFd >= 0 {
            flock(lockFd, LOCK_UN)
            close(lockFd)
            lockFd = -1
        }
    }

    func isLocked() -> Bool {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }
        let rc = flock(fd, LOCK_EX | LOCK_NB)
        if rc != 0 {
            close(fd)
            return true
        }
        flock(fd, LOCK_UN)
        close(fd)
        return false
    }
}

// MARK: - Configuration Manager

class ConfigManager {
    static let shared = ConfigManager()
    let configURL: URL

    init() {
        let home = currentUserHomeDirectory()
        configURL = home.appendingPathComponent(".cxtool.json")
    }

    func load() -> Config {
        let fm = FileManager.default
        if fm.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let def = Config.defaultConfig
        save(def)
        return def
    }

    func save(_ cfg: Config) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cfg) {
            try? data.write(to: configURL)
        }
    }
}

// MARK: - SHA256 Helper

func computeSHA256(for filePath: String) -> String {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
        return "none"
    }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Discovery Engine

class DiscoveryEngine {
    let config: Config

    init(config: Config) {
        self.config = config
    }

    func discoverBottleRoots() -> [BottleRoot] {
        var rawRoots: [(String, Provenance)] = []

        // 1. CrossOver Preferences (BottleDir)
        let prefDomain = "com.codeweavers.CrossOver"
        let defaults = UserDefaults.standard.persistentDomain(forName: prefDomain) ?? [:]
        if config.auto_detect_crossover_bottles,
           let bottleDir = defaults["BottleDir"] as? String, !bottleDir.isEmpty {
            rawRoots.append((bottleDir, .crossoverPrefs))
        }

        // 2. CX_BOTTLE_PATH
        if let envPath = ProcessInfo.processInfo.environment["CX_BOTTLE_PATH"], !envPath.isEmpty {
            rawRoots.append((envPath, .envVar))
        }

        // 3. ManagedBottleDirs
        if let managed = defaults["ManagedBottleDirs"] as? [String] {
            for m in managed where !m.isEmpty {
                rawRoots.append((m, .managed))
            }
        } else if let managedStr = defaults["ManagedBottleDirs"] as? String, !managedStr.isEmpty {
            rawRoots.append((managedStr, .managed))
        }

        // 4. Configured directories
        for userDir in config.bottle_directories {
            rawRoots.append((userDir, .userConfig))
        }

        // 5. Default Fallback
        let fallback = NSString(string: "~/Library/Application Support/CrossOver/Bottles").expandingTildeInPath
        rawRoots.append((fallback, .defaultFallback))

        // Canonicalize & Deduplicate
        var seenCanonical = Set<String>()
        var result: [BottleRoot] = []
        let fm = FileManager.default

        for (path, prov) in rawRoots {
            let expanded = NSString(string: path).expandingTildeInPath
            let canonical = URL(fileURLWithPath: expanded).standardized.path
            if !seenCanonical.contains(canonical) {
                seenCanonical.insert(canonical)
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: canonical, isDirectory: &isDir) && isDir.boolValue
                result.append(BottleRoot(path: canonical, provenance: prov, exists: exists))
            }
        }
        return result
    }

    func discoverProgramsFolder() -> (path: String, verified: Bool) {
        if config.auto_detect_crossover_bottles {
            let prefDomain = "com.codeweavers.CrossOver"
            let defaults = UserDefaults.standard.persistentDomain(forName: prefDomain) ?? [:]

            if let bookmarkData = defaults["ProgramsFolderBookmark"] as? Data {
                var isStale = false
                let savedStderr = dup(STDERR_FILENO)
                let devNull = open("/dev/null", O_WRONLY)
                dup2(devNull, STDERR_FILENO)
                close(devNull)

                let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)

                fflush(stderr)
                dup2(savedStderr, STDERR_FILENO)
                close(savedStderr)

                if let resolved = url {
                    return (resolved.path, true)
                }
            }
        }
        let fallback = NSString(string: config.crossover_apps_dir).expandingTildeInPath
        let exists = FileManager.default.fileExists(atPath: fallback)
        return (fallback, exists)
    }

    func discoverBottles() -> [(name: String, path: String, root: BottleRoot)] {
        let fm = FileManager.default
        let roots = discoverBottleRoots().filter { $0.exists }
        var bottles: [(name: String, path: String, root: BottleRoot)] = []
        var seenNames = Set<String>()

        for root in roots {
            let subitems = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            for sub in subitems.sorted() {
                let bottlePath = "\(root.path)/\(sub)"
                if fm.fileExists(atPath: "\(bottlePath)/cxbottle.conf") {
                    if !seenNames.contains(sub) {
                        seenNames.insert(sub)
                        bottles.append((sub, bottlePath, root))
                    }
                }
            }
        }
        return bottles
    }

    func parseCxMenuConf(at path: String) -> [String: [String: String]] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var sections: [String: [String: String]] = [:]
        var currentSection = ""

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let secName = String(trimmed.dropFirst().dropLast())
                currentSection = secName
                if sections[secName] == nil {
                    sections[secName] = [:]
                }
            } else if let eqIdx = trimmed.firstIndex(of: "="), !currentSection.isEmpty {
                let key = trimmed[..<eqIdx].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let val = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                sections[currentSection]?[key] = val
            }
        }
        return sections
    }

    func scanAllShortcuts() -> [ShortcutInfo] {
        let fm = FileManager.default
        let programsFolder = discoverProgramsFolder().path
        let bottles = discoverBottles()
        var results: [ShortcutInfo] = []

        var bottleMenus: [String: [String: [String: String]]] = [:]
        for b in bottles {
            let confPath = "\(b.path)/cxmenu.conf"
            bottleMenus[b.name] = parseCxMenuConf(at: confPath)
        }

        func scanAppsIn(dir: String) -> [String] {
            var apps: [String] = []
            let items = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for item in items {
                let itemPath = "\(dir)/\(item)"
                if item.hasSuffix(".app") {
                    apps.append(itemPath)
                } else {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: itemPath, isDirectory: &isDir) && isDir.boolValue && !item.hasPrefix(".") {
                        apps.append(contentsOf: scanAppsIn(dir: itemPath))
                    }
                }
            }
            return apps
        }

        let appPaths = scanAppsIn(dir: programsFolder)

        for appPath in appPaths.sorted() {
            let plistPath = "\(appPath)/Contents/Info.plist"
            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
                  let plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any] else {
                continue
            }

            let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let bottleName = plist["CXHelperAppBottleName"] as? String ?? "Unknown"
            let menuPath = plist["CrossOverHelperMenuPath"] as? String
            let commandPath = plist["CrossOverHelperCommand"] as? String

            var iconTag: String? = nil
            var targetExe: String? = nil

            if let bMenu = bottleMenus[bottleName], let mPath = menuPath {
                if let sec = bMenu[mPath] {
                    iconTag = sec["Icon"]
                    targetExe = sec["StartupWMClass"] ?? sec["Shortcut"]
                }
            }

            var isOffline = false
            var extDep: String? = nil
            if let cmd = commandPath, let content = try? String(contentsOfFile: cmd, encoding: .utf8) {
                for extRoot in config.external_game_roots {
                    if content.contains(extRoot) {
                        extDep = extRoot
                        if !fm.fileExists(atPath: extRoot) {
                            isOffline = true
                        }
                    }
                }
            }

            let icnsPath = "\(appPath)/Contents/Resources/CrossOverHelper.icns"
            let (isSquircle, cornerAlpha, isCog) = checkIconStyle(icnsPath: icnsPath)

            results.append(ShortcutInfo(
                name: appName,
                bottleName: bottleName,
                appPath: appPath,
                menuPath: menuPath,
                commandPath: commandPath,
                iconTag: iconTag,
                targetExe: targetExe,
                externalDependency: extDep,
                isOffline: isOffline,
                isSquircle: isSquircle,
                cornerAlpha: cornerAlpha,
                isCrossoverCog: isCog
            ))
        }

        return results
    }

    func checkIconStyle(icnsPath: String) -> (isSquircle: Bool, cornerAlpha: CGFloat, isCog: Bool) {
        guard let img = NSImage(contentsOfFile: icnsPath) else {
            return (false, 1.0, false)
        }
        let rep512 = (img.representations.first(where: { $0.pixelsWide == 512 }) ?? img.representations.first) as? NSBitmapImageRep
        guard let rep = rep512 else {
            return (false, 1.0, false)
        }

        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0 && h > 0 else { return (false, 1.0, false) }

        let c1 = rep.colorAt(x: 8, y: 8)?.alphaComponent ?? 0
        let c2 = rep.colorAt(x: w - 9, y: 8)?.alphaComponent ?? 0
        let c3 = rep.colorAt(x: 8, y: h - 9)?.alphaComponent ?? 0
        let c4 = rep.colorAt(x: w - 9, y: h - 9)?.alphaComponent ?? 0
        let maxCornerAlpha = max(c1, max(c2, max(c3, c4)))

        var isCog = false
        if let cornerC = rep.colorAt(x: w / 4, y: h / 4) {
            if cornerC.redComponent > 0.8 && cornerC.greenComponent > 0.8 && cornerC.blueComponent < 0.2 {
                isCog = true
            }
        }

        let isSquircle = (maxCornerAlpha < 0.05) && !isCog
        return (isSquircle, maxCornerAlpha, isCog)
    }

    // MARK: - Disambiguation Helper

    enum ResolveResult {
        case success(ShortcutInfo)
        case ambiguous([ShortcutInfo])
        case notFound
    }

    func resolveShortcut(query: String, in shortcuts: [ShortcutInfo]) -> ShortcutInfo? {
        switch resolveShortcutDetailed(query: query, in: shortcuts) {
        case .success(let s): return s
        default: return nil
        }
    }

    func resolveShortcutDetailed(query: String, in shortcuts: [ShortcutInfo]) -> ResolveResult {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // 1. Exact case-insensitive match
        if let exact = shortcuts.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .success(exact)
        }

        // 2. Partial contains match
        let matches = shortcuts.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        if matches.count == 1 {
            return .success(matches.first!)
        } else if matches.count > 1 {
            return .ambiguous(matches)
        } else {
            return .notFound
        }
    }
}

// MARK: - Apple .iconset & Squircle Renderer

enum IconStyle: String {
    case macos = "macos"
    case fullBleed = "full-bleed"
    case emblem = "emblem"
    case raw = "raw"
}

class SquircleRenderer {
    static let canvasSize = 512
    static let bodyRect = NSRect(x: 52, y: 52, width: 408, height: 408)
    static let cornerRadius: CGFloat = 91

    static func parseColor(from string: String?) -> NSColor? {
        guard let s = string?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        if s == "black" { return .black }
        if s == "white" { return .white }
        if s == "clear" || s == "transparent" { return .clear }
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            if hex.count == 6, let num = UInt64(hex, radix: 16) {
                let r = CGFloat((num >> 16) & 0xFF) / 255.0
                let g = CGFloat((num >> 8) & 0xFF) / 255.0
                let b = CGFloat(num & 0xFF) / 255.0
                return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
            }
        }
        return nil
    }

    static func renderMaster(sourcePath: String, style: IconStyle, bgColor: NSColor?, scale: CGFloat) -> NSBitmapImageRep? {
        guard let rawImg = NSImage(contentsOfFile: sourcePath) else { return nil }

        let w = canvasSize
        let h = canvasSize

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: w,
                                         pixelsHigh: h,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .calibratedRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        ctx.imageInterpolation = .high
        NSGraphicsContext.current = ctx

        // Find highest resolution representation (critical for multi-res .ico files)
        guard let firstRep = rawImg.representations.first else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        var bestRep: NSImageRep = firstRep
        var maxPixels = 0
        for r in rawImg.representations {
            let px = r.pixelsWide * r.pixelsHigh
            if px > maxPixels {
                maxPixels = px
                bestRep = r
            }
        }

        if style == .raw {
            bestRep.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }

        // 1. Drop Shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.26)
        shadow.shadowOffset = NSSize(width: 0, height: -7)
        shadow.shadowBlurRadius = 11
        shadow.set()

        let path = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.setFill()
        path.fill()

        let noShadow = NSShadow()
        noShadow.set()

        // 2. Squircle Clip & Background Fill
        let clipPath = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()

        if let bg = bgColor {
            bg.setFill()
            clipPath.fill()
        }

        let effScale = (style == .fullBleed) ? 1.0 : scale
        let targetRect: NSRect
        if effScale == 1.0 {
            targetRect = bodyRect
        } else {
            let artW = bodyRect.width * effScale
            let artH = bodyRect.height * effScale
            let artX = bodyRect.midX - artW / 2
            let artY = bodyRect.midY - artH / 2
            targetRect = NSRect(x: artX, y: artY, width: artW, height: artH)
        }

        bestRep.draw(in: targetRect)

        // 3. Subtle Inner Rim
        let borderPath = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        borderPath.lineWidth = 1.0
        if let bg = bgColor, bg == NSColor.white {
            NSColor(calibratedWhite: 0.0, alpha: 0.08).setStroke()
        } else {
            NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
        }
        borderPath.stroke()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func buildAppleIconset(from master: NSBitmapImageRep, iconsetDir: String) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(atPath: iconsetDir)
        try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

        let spec: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (filename, px) in spec {
            guard let rep = resize(master: master, toSize: px),
                  let png = rep.representation(using: .png, properties: [:]) else {
                return false
            }
            let outPath = "\(iconsetDir)/\(filename)"
            do {
                try png.write(to: URL(fileURLWithPath: outPath))
            } catch {
                return false
            }
        }
        return true
    }

    static func resize(master: NSBitmapImageRep, toSize: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: toSize,
                                         pixelsHigh: toSize,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .calibratedRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        ctx.imageInterpolation = .high
        NSGraphicsContext.current = ctx
        master.draw(in: NSRect(x: 0, y: 0, width: toSize, height: toSize))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

// MARK: - Transaction & Rollback Engine

class TransactionManager {
    static let shared = TransactionManager()
    let backupBaseURL: URL

    init() {
        let home = currentUserHomeDirectory()
        backupBaseURL = home.appendingPathComponent(".cxtool/backups")
        try? FileManager.default.createDirectory(at: backupBaseURL, withIntermediateDirectories: true)
    }

    func createSnapshot(action: String, target: String, bottle: String, touchedFiles: [String]) -> (id: String, manifest: TransactionManifest)? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = fmt.string(from: Date())
        let cleanTarget = target.replacingOccurrences(of: " ", with: "_").prefix(20)
        let txId = "\(timestamp)_\(action)_\(cleanTarget)"

        let snapshotDir = backupBaseURL.appendingPathComponent(txId)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var records: [FileHashRecord] = []
        for file in touchedFiles {
            let beforeHash = computeSHA256(for: file)
            records.append(FileHashRecord(path: file, before_sha256: beforeHash, after_sha256: ""))

            if fm.fileExists(atPath: file) {
                let hash = computeSHA256(for: file).prefix(8)
                let backupFileName = "\(hash)_\((file as NSString).lastPathComponent)"
                let dest = snapshotDir.appendingPathComponent(backupFileName)
                try? fm.copyItem(at: URL(fileURLWithPath: file), to: dest)
            }
        }

        let isoFmt = ISO8601DateFormatter()
        let manifest = TransactionManifest(
            transaction_id: txId,
            action: action,
            target: target,
            bottle: bottle,
            created_at: isoFmt.string(from: Date()),
            files: records,
            verified: false
        )

        saveManifest(manifest, in: snapshotDir)
        return (txId, manifest)
    }

    func saveManifest(_ manifest: TransactionManifest, in dir: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            let mURL = dir.appendingPathComponent("manifest.json")
            try? data.write(to: mURL)
        }
    }

    func completeSnapshot(id: String, verified: Bool, movedItems: [MovedItemRecord]? = nil, archivedApps: [MovedItemRecord]? = nil) {
        let snapshotDir = backupBaseURL.appendingPathComponent(id)
        let mURL = snapshotDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: mURL),
              var manifest = try? JSONDecoder().decode(TransactionManifest.self, from: data) else {
            return
        }

        for i in 0..<manifest.files.count {
            manifest.files[i].after_sha256 = computeSHA256(for: manifest.files[i].path)
        }
        manifest.verified = verified
        if let moved = movedItems { manifest.moved_items = moved }
        if let archived = archivedApps { manifest.archived_apps = archived }
        saveManifest(manifest, in: snapshotDir)
    }

    func markUndone(id: String) {
        let snapshotDir = backupBaseURL.appendingPathComponent(id)
        let mURL = snapshotDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: mURL),
              var manifest = try? JSONDecoder().decode(TransactionManifest.self, from: data) else {
            return
        }
        manifest.undone = true
        saveManifest(manifest, in: snapshotDir)
    }

    func rollback(id: String) -> Bool {
        let snapshotDir = backupBaseURL.appendingPathComponent(id)
        let mURL = snapshotDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: mURL),
              let manifest = try? JSONDecoder().decode(TransactionManifest.self, from: data) else {
            print("❌ Cannot load manifest for snapshot: \(id)")
            return false
        }

        let fm = FileManager.default
        var allRestored = true

        // 1. Move back any moved/renamed items in reverse order
        if let moved = manifest.moved_items {
            for item in moved.reversed() {
                if fm.fileExists(atPath: item.to) {
                    try? fm.removeItem(atPath: item.from)
                    do {
                        try fm.moveItem(atPath: item.to, toPath: item.from)
                        print("  [Moved Back] \(item.to) -> \(item.from)")
                    } catch {
                        print("  [Failed Move Back] \(item.to) -> \(item.from): \(error.localizedDescription)")
                        allRestored = false
                    }
                }
            }
        }

        // 2. Restore any archived apps (from delete operations)
        if let archived = manifest.archived_apps {
            for item in archived {
                if fm.fileExists(atPath: item.to) {
                    try? fm.removeItem(atPath: item.from)
                    do {
                        try fm.moveItem(atPath: item.to, toPath: item.from)
                        print("  [Restored App] \(item.from)")
                    } catch {
                        print("  [Failed Restoring App] \(item.from): \(error.localizedDescription)")
                        allRestored = false
                    }
                }
            }
        }

        // 3. Restore backed up files
        for record in manifest.files {
            let backupPrefix = record.before_sha256.prefix(8)
            let backupFileName = "\(backupPrefix)_\((record.path as NSString).lastPathComponent)"
            let backupFile = snapshotDir.appendingPathComponent(backupFileName)

            if fm.fileExists(atPath: backupFile.path) {
                let targetURL = URL(fileURLWithPath: record.path)
                try? fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(atPath: record.path)
                do {
                    try fm.copyItem(at: backupFile, to: targetURL)
                    print("  [Restored] \(record.path)")
                } catch {
                    print("  [Failed] Could not restore \(record.path): \(error.localizedDescription)")
                    allRestored = false
                }
            } else if record.before_sha256 == "none" {
                try? fm.removeItem(atPath: record.path)
                print("  [Cleaned] Removed newly created file \(record.path)")
            }
        }

        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])
        return allRestored
    }

    func listSnapshots() -> [TransactionManifest] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: backupBaseURL.path)) ?? []
        var manifests: [TransactionManifest] = []

        for item in items.sorted().reversed() {
            let mURL = backupBaseURL.appendingPathComponent(item).appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: mURL),
               let m = try? JSONDecoder().decode(TransactionManifest.self, from: data) {
                manifests.append(m)
            }
        }
        return manifests
    }
}

// MARK: - CLI Commands Implementation

class CXToolCLI {
    let config = ConfigManager.shared.load()
    let discovery: DiscoveryEngine
    var isJSON: Bool = false

    init() {
        self.discovery = DiscoveryEngine(config: config)
    }

    func resolveOrExit(query: String, in shortcuts: [ShortcutInfo]) -> ShortcutInfo {
        switch discovery.resolveShortcutDetailed(query: query, in: shortcuts) {
        case .success(let item):
            return item
        case .ambiguous(let matches):
            let matchDescriptions = matches.map { "\($0.name) (Bottle: \($0.bottleName))" }
            exitWithError(
                code: 4,
                type: "ambiguous_target",
                message: "Ambiguous query \"\(query)\". Matches multiple shortcuts.",
                matches: matchDescriptions,
                isJSON: isJSON
            )
        case .notFound:
            exitWithError(
                code: 3,
                type: "target_not_found",
                message: "No shortcut found matching \"\(query)\".",
                matches: nil,
                isJSON: isJSON
            )
        }
    }

    func run(args: [String]) {
        self.isJSON = args.contains("--json")

        guard args.count > 1 else {
            if isJSON {
                exitWithError(code: 2, type: "missing_command", message: "No command specified. Run 'cxtool --help' for usage.", isJSON: true)
            }
            printUsage()
            exit(2)
        }

        let command = args[1]
        let remaining = Array(args.dropFirst(2))

        // Fast completion helpers - 100% read-only, zero lock, zero banners, fast exit
        if command == "__complete-shortcuts" {
            cmdCompleteShortcuts()
            return
        }
        if command == "__complete-bottles" {
            cmdCompleteBottles()
            return
        }

        // Determine if command mutates state
        let mutatingCommands: Set<String> = [
            "set-icon", "repair", "repair-all", "rename", "delete", "undo", "restore", "backup"
        ]
        var needsLock = mutatingCommands.contains(command)
        if command == "backups" && remaining.first == "prune" {
            needsLock = true
        }
        if command == "config" && remaining.count >= 1 && (remaining[0] == "add-bottle-dir" || remaining[0] == "add-library-dir") {
            needsLock = true
        }

        if needsLock {
            guard ProcessLock.shared.acquire() else {
                exitWithError(code: 6, type: "lock_collision", message: "Another cxtool process is currently running (~/.cxtool/cxtool.lock held).", isJSON: isJSON)
            }
        }
        defer {
            if needsLock {
                ProcessLock.shared.release()
            }
        }

        switch command {
        case "status":
            cmdStatus(args: remaining)
        case "list":
            cmdList(args: remaining)
        case "doctor":
            cmdDoctor()
        case "inspect":
            cmdInspect(args: remaining)
        case "verify":
            cmdVerify(args: remaining)
        case "set-icon":
            cmdSetIcon(args: remaining)
        case "repair":
            cmdRepair(args: remaining)
        case "repair-all":
            cmdRepairAll(args: remaining)
        case "rename":
            cmdRename(args: remaining)
        case "delete":
            cmdDelete(args: remaining)
        case "history":
            cmdHistory(args: remaining)
        case "undo":
            cmdUndo()
        case "backup":
            cmdBackup(args: remaining)
        case "restore":
            cmdRestore(args: remaining)
        case "backups":
            cmdBackups(args: remaining)
        case "config":
            cmdConfig(args: remaining)
        case "completion":
            cmdCompletion(args: remaining)
        case "version", "--version", "-v":
            print("cxtool 1.2.0")
        case "help", "--help", "-h":
            printUsage()
        default:
            exitWithError(code: 2, type: "unknown_command", message: "Unknown command '\(command)'. Run 'cxtool --help' for usage.", isJSON: isJSON)
        }
    }

    func printUsage() {
        print("""
        cxtool - CrossOver Mac Bottle Shortcut & Icon Manager (V1.2.0 Stable)

        USAGE:
          cxtool <command> [options]

        INSPECTION & DIAGNOSTICS:
          status                       System, inventory, storage, and safety health dashboard
          list                         List all game shortcuts, bottles, and icon status
          doctor                       Perform comprehensive CrossOver environment health check
          inspect <Game Name>          Display complete CrossOver state for a specific game
          verify <Game Name>           Audit entire launch chain & shortcut integrity

        ICON MANAGEMENT:
          set-icon <Name> <image>      Update icon to macOS squircle (--style, --bg, --scale)
          repair <Game Name>           Convert game icon to macOS squircle if needed
          repair-all                   Scan and safely repair all non-squircle icons (idempotent)

        LIFECYCLE MANAGEMENT:
          rename <Old Name> <New Name> Safely rename shortcut across macOS wrapper & bottle
          delete <Game Name>           Safely unregister shortcut (NEVER deletes game data)

        SAFETY, HISTORY & BACKUPS:
          history                      Display log of past transactions
          undo                         Revert the most recent verified transaction
          backup [--note <text>]       Create a manual snapshot of CrossOver menus and icons
          restore <backup-id>          Rollback to a previously saved snapshot
          backups [list|prune]         Inspect and prune snapshot backups (--keep, --days)
          config [show|add-bottle-dir|add-library-dir] Manage persistent paths

        SHELL COMPLETION:
          completion zsh               Generate native Zsh shell completion script

        OPTIONS:
          --json                       Output structured machine-readable JSON (schema_version: 1)
          --dry-run                    Preview changes without writing to disk
          --force                      Bypass confirmation prompts
          --bottle <name>              Filter or target a specific bottle
          --style <macos|full-bleed|emblem|raw> Icon rendering style preset
          --bg <black|white|#hex>      Background fill color for emblem styles
          --scale <float>              Optical scaling factor for art (default 1.0 or 0.85)
          --keep <N>                   Number of newest snapshots to retain in prune (default: 10)
          --days <N>                   Age threshold in days for pruning (default: 30)
          --verbose                    Show internal paths and diagnostic details
        """)
    }

    // MARK: - cmdList

    func cmdList(args: [String]) {
        let shortcuts = discovery.scanAllShortcuts()
        let bottleFilter = getFlagValue("--bottle", from: args)

        let filtered = shortcuts.filter { s in
            if let b = bottleFilter {
                return s.bottleName.localizedCaseInsensitiveContains(b)
            }
            return true
        }

        if self.isJSON {
            let report = ListReport(total: filtered.count, shortcuts: filtered)
            printJSON(report)
            return
        }

        print(String(format: "%-35@ | %-12@ | %-16@ | %-12@", "Game / Shortcut Name", "Bottle", "Icon Style", "Drive Status"))
        print(String(repeating: "-", count: 85))

        for s in filtered {
            let iconStr: String
            if s.isSquircle {
                iconStr = "Squircle ✅"
            } else if s.isCrossoverCog {
                iconStr = "CrossOver Cog ⚙️"
            } else {
                iconStr = "Square ❌"
            }

            let driveStr: String
            if s.isOffline {
                driveStr = "OFFLINE ⚠️"
            } else {
                driveStr = "ONLINE ✅"
            }

            print(String(format: "%-35@ | %-12@ | %-16@ | %-12@",
                         s.name.prefix(35) as NSString,
                         s.bottleName.prefix(12) as NSString,
                         iconStr as NSString,
                         driveStr as NSString))
        }
        print(String(repeating: "=", count: 85))
        print("Total: \(filtered.count) items found across active bottles.")
    }

    // MARK: - cmdDoctor

    func cmdDoctor() {
        print("=== CrossOver Environment Doctor ===")

        let roots = discovery.discoverBottleRoots()
        let (progPath, progVerified) = discovery.discoverProgramsFolder()
        let bottles = discovery.discoverBottles()
        let shortcuts = discovery.scanAllShortcuts()

        print("\n[CrossOver Preferences]")
        for r in roots {
            let stat = r.exists ? "OK" : "NOT FOUND"
            print(String(format: "  %-32@ : %@ (%@)", r.provenance.rawValue as NSString, r.path as NSString, stat as NSString))
        }
        print(String(format: "  %-32@ : %@ (%@)", "Programs Folder" as NSString, progPath as NSString, progVerified ? "OK" : "NOT FOUND" as NSString))

        print("\n[Bottles]")
        for b in bottles {
            let bShortcuts = shortcuts.filter { $0.bottleName == b.name }
            print("  Bottle: [\(b.name)]")
            print("    Path: \(b.path)")
            print("    Shortcuts mapped: \(bShortcuts.count)")
            let squareCount = bShortcuts.filter { !$0.isSquircle }.count
            print("    Icon compliance: \(bShortcuts.count - squareCount)/\(bShortcuts.count) Squircles (Issues: \(squareCount))")
        }

        print("\n[External Storage]")
        for ext in config.external_game_roots {
            let isOnline = FileManager.default.fileExists(atPath: ext)
            let status = isOnline ? "ONLINE ✅" : "OFFLINE (protected) ⚠️"
            print("  \(ext) -> \(status)")
        }

        print("\n[Safety & Policy]")
        print("  Safety backups ................... MANDATORY (always enabled) ✅")
        print("  Offline pruning protection ....... ENFORCED (always protected) ✅")
        print("  Process locking .................. ENABLED (~/.cxtool/cxtool.lock) ✅")
        print("  Default Icon Style ............... \(config.default_style)")
        print("\nDoctor Check Complete.")
    }

    // MARK: - cmdInspect

    func cmdInspect(args: [String]) {
        let nonFlagArgs = args.filter { !$0.hasPrefix("--") }
        guard let name = nonFlagArgs.first else {
            exitWithError(code: 2, type: "invalid_usage", message: "Usage: cxtool inspect \"Game Name\" [--json]", isJSON: self.isJSON)
        }

        let shortcuts = discovery.scanAllShortcuts()
        let item = resolveOrExit(query: name, in: shortcuts)

        var icnsPath: String? = nil
        var icnsSHA: String? = nil
        if let app = item.appPath {
            let icns = "\(app)/Contents/Resources/CrossOverHelper.icns"
            icnsPath = icns
            icnsSHA = computeSHA256(for: icns)
        }

        if self.isJSON {
            let report = InspectReport(shortcut: item, icns_file: icnsPath, icns_sha256: icnsSHA)
            printJSON(report)
            return
        }

        print("=== State Inspection: \(item.name) ===")
        print("Bottle:                  \(item.bottleName)")
        print("macOS App Wrapper:       \(item.appPath ?? "<None>")")
        print("Start Menu MenuPath:     \(item.menuPath ?? "<None>")")
        print("Command Script:          \(item.commandPath ?? "<None>")")
        print("Icon Tag:                \(item.iconTag ?? "<None>")")
        print("Target Executable:       \(item.targetExe ?? "<None>")")
        print("External Dependency:     \(item.externalDependency ?? "<None>")")
        print("External Drive Status:   \(item.isOffline ? "OFFLINE ⚠️" : "ONLINE ✅")")
        print("Squircle Style:          \(item.isSquircle ? "YES (macOS Squircle) ✅" : "NO (Needs Repair) ❌")")
        print("Corner Alpha:            \(item.cornerAlpha)")
        print("Is CrossOver Gear Icon:  \(item.isCrossoverCog ? "YES ⚙️" : "NO")")

        if let icns = icnsPath, let sha = icnsSHA {
            print("ICNS File:               \(icns) (SHA256: \(sha.prefix(12))...)")
        }
    }

    // MARK: - cmdVerify (V1.1.1)

    func cmdVerify(args: [String]) {
        let nonFlagArgs = args.filter { !$0.hasPrefix("--") }
        guard let name = nonFlagArgs.first else {
            exitWithError(code: 2, type: "invalid_usage", message: "Usage: cxtool verify \"Game Name\" [--json]", isJSON: self.isJSON)
        }

        let shortcuts = discovery.scanAllShortcuts()
        let item = resolveOrExit(query: name, in: shortcuts)

        let fm = FileManager.default

        // 1. Wrapper exists
        let wrapperExists = item.appPath.map { fm.fileExists(atPath: $0) } ?? false

        // 2. Info.plist
        var plistOK = false
        if let app = item.appPath {
            let pPath = "\(app)/Contents/Info.plist"
            if let pData = try? Data(contentsOf: URL(fileURLWithPath: pPath)),
               let _ = try? PropertyListSerialization.propertyList(from: pData, options: [], format: nil) as? [String: Any] {
                plistOK = true
            }
        }

        // 3. Bottle association
        let bottles = discovery.discoverBottles()
        let bottle = bottles.first(where: { $0.name == item.bottleName })

        // 4. cxmenu entry
        var cxmenuOK = false
        if let b = bottle, let mPath = item.menuPath {
            let bMenu = discovery.parseCxMenuConf(at: "\(b.path)/cxmenu.conf")
            cxmenuOK = bMenu[mPath] != nil
        }

        // 5. desktopdata launcher
        var launcherOK = false
        if let cmd = item.commandPath?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
            launcherOK = fm.fileExists(atPath: cmd) && fm.isExecutableFile(atPath: cmd)
        }

        // 6. Windows shortcut
        var lnkOK = false
        if let b = bottle {
            let startLnk = "\(b.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(item.name).lnk"
            let startUrl = "\(b.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(item.name).url"
            let deskLnk = "\(b.path)/drive_c/users/crossover/Desktop/\(item.name).lnk"
            let deskUrl = "\(b.path)/drive_c/users/crossover/Desktop/\(item.name).url"
            lnkOK = fm.fileExists(atPath: startLnk) || fm.fileExists(atPath: startUrl) || fm.fileExists(atPath: deskLnk) || fm.fileExists(atPath: deskUrl)
        }

        // 7. Icon resources
        var iconsOK = false
        if let app = item.appPath {
            let icns = "\(app)/Contents/Resources/CrossOverHelper.icns"
            iconsOK = fm.fileExists(atPath: icns) && item.isSquircle
        }

        // 8. Executable target & Launch Chain
        var launchChainValid = false
        var targetStatus = "OK ✅"

        if item.isOffline {
            targetStatus = "OFFLINE (protected) ⚠️"
        }

        if let cmd = item.commandPath?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
           let script = try? String(contentsOfFile: cmd, encoding: .utf8) {
            // Check wine path in script
            if script.contains("/wine") {
                launchChainValid = true
            }
        }

        let isHealthy = wrapperExists && plistOK && bottle != nil && cxmenuOK && launcherOK && iconsOK && launchChainValid
        let overallStatus = isHealthy ? (item.isOffline ? "healthy_offline" : "healthy") : "degraded"

        if self.isJSON {
            let checks = VerifyChecks(
                wrapper_exists: wrapperExists,
                plist_ok: plistOK,
                bottle_ok: bottle != nil,
                cxmenu_ok: cxmenuOK,
                launcher_ok: launcherOK,
                windows_shortcut_ok: lnkOK,
                icon_squircle_ok: iconsOK,
                launch_chain_valid: launchChainValid
            )
            let report = VerifyReport(
                target: item.name,
                bottle: item.bottleName,
                healthy: isHealthy,
                overall_status: overallStatus,
                target_executable_status: targetStatus,
                checks: checks
            )
            printJSON(report)
            exit(isHealthy ? 0 : 5)
        }

        print("=== Launch Chain & Integrity Audit: [\(item.name)] ===")
        print(String(format: "  %-30@ : %@", "Wrapper exists", wrapperExists ? "OK ✅" : "MISSING ❌"))
        print(String(format: "  %-30@ : %@", "Info.plist", plistOK ? "OK ✅" : "INVALID ❌"))
        print(String(format: "  %-30@ : %@", "Bottle association [\(item.bottleName)]", bottle != nil ? "OK ✅" : "UNKNOWN ❌"))
        print(String(format: "  %-30@ : %@", "cxmenu entry", cxmenuOK ? "OK ✅" : "MISSING ❌"))
        print(String(format: "  %-30@ : %@", "desktopdata launcher", launcherOK ? "OK ✅" : "MISSING ❌"))
        print(String(format: "  %-30@ : %@", "Windows shortcut", lnkOK ? "OK (Binary Untouched) ✅" : "NOT FOUND ⚠️"))
        print(String(format: "  %-30@ : %@", "Icon resources (Squircle)", iconsOK ? "OK ✅" : "NEEDS REPAIR ❌"))
        print(String(format: "  %-30@ : %@", "Executable target", targetStatus))
        print(String(format: "  %-30@ : %@", "Launch chain", launchChainValid ? "VALID ✅" : "INVALID ❌"))

        print(String(repeating: "-", count: 55))
        if isHealthy {
            if item.isOffline {
                print("Overall ..................... HEALTHY (External Storage Offline) ⚠️")
            } else {
                print("Overall ..................... HEALTHY ✅")
            }
            exit(0)
        } else {
            print("Overall ..................... DEGRADED ❌")
            exit(5)
        }
    }

    // MARK: - cmdHistory & cmdUndo (V1.1.1)

    func cmdHistory(args: [String] = []) {
        let snapshots = TransactionManager.shared.listSnapshots()

        if self.isJSON {
            let report = HistoryReport(total: snapshots.count, transactions: snapshots)
            printJSON(report)
            return
        }

        if snapshots.isEmpty {
            print("No transaction history found in ~/.cxtool/backups/.")
            return
        }

        print(String(format: "%-17@ | %-10@ | %-32@ | %-10@", "Timestamp", "Action", "Target", "Status"))
        print(String(repeating: "-", count: 78))

        for s in snapshots.prefix(20) {
            let stat: String
            if s.undone == true {
                stat = "UNDONE ↩️"
            } else if s.verified {
                stat = "VERIFIED ✅"
            } else {
                stat = "UNVERIFIED ⚠️"
            }
            print(String(format: "%-17@ | %-10@ | %-32@ | %-10@",
                         s.transaction_id.prefix(17) as NSString,
                         s.action as NSString,
                         s.target.prefix(32) as NSString,
                         stat as NSString))
        }
    }

    func cmdUndo() {
        let snapshots = TransactionManager.shared.listSnapshots()
        guard let latest = snapshots.first(where: { $0.undone != true }) else {
            print("❌ No active transactions found to undo.")
            exit(1)
        }

        print("Undoing most recent transaction [\(latest.transaction_id)]:")
        print("  Action: \(latest.action)")
        print("  Target: \(latest.target)")
        print("  Bottle: \(latest.bottle)")

        if TransactionManager.shared.rollback(id: latest.transaction_id) {
            TransactionManager.shared.markUndone(id: latest.transaction_id)
            print("\n🎉 Undo completed successfully! Files restored to previous state.")
        } else {
            print("❌ Undo encountered errors during rollback.")
            exit(1)
        }
    }

    // MARK: - cmdSetIcon

    func cmdSetIcon(args: [String]) {
        guard args.count >= 2, !args[0].hasPrefix("--"), !args[1].hasPrefix("--") else {
            print("Usage: cxtool set-icon \"Game Name\" /path/to/image.png [--style macos|full-bleed|emblem|raw] [--bg black|white|#hex] [--scale <float>]")
            exit(2)
        }

        let targetName = args[0]
        let imagePath = args[1]
        let dryRun = args.contains("--dry-run")
        let styleStr = getFlagValue("--style", from: args) ?? config.default_style
        let style = IconStyle(rawValue: styleStr) ?? .macos
        let bgStr = getFlagValue("--bg", from: args)
        let bgColor = SquircleRenderer.parseColor(from: bgStr)
        let scaleStr = getFlagValue("--scale", from: args)
        let scale = scaleStr.flatMap { Double($0) }.map { CGFloat($0) } ?? (style == .emblem ? 0.85 : 1.0)

        let shortcuts = discovery.scanAllShortcuts()
        let item = resolveOrExit(query: targetName, in: shortcuts)
        guard let appPath = item.appPath else {
            print("❌ Shortcut has no associated macOS app wrapper.")
            exit(1)
        }

        guard FileManager.default.fileExists(atPath: imagePath) else {
            print("❌ Source image does not exist: \(imagePath)")
            exit(2)
        }

        print("Planning icon update for [\(item.name)]:")
        print("  Source image: \(imagePath)")
        print("  Style preset: \(style.rawValue)")
        print("  Background:   \(bgStr ?? "automatic")")
        print("  Scale:        \(scale)")
        print("  Target app:   \(appPath)")

        if dryRun {
            print("ℹ️  [Dry-Run] No changes written to disk.")
            return
        }

        guard let masterRep = SquircleRenderer.renderMaster(sourcePath: imagePath, style: style, bgColor: bgColor, scale: scale) else {
            print("❌ Failed to render squircle image representation.")
            return
        }

        let icnsDest = "\(appPath)/Contents/Resources/CrossOverHelper.icns"
        var touchedFiles = [icnsDest]

        let bottles = discovery.discoverBottles()
        let bottle = bottles.first(where: { $0.name == item.bottleName })
        if let b = bottle, let tag = item.iconTag {
            for px in [16, 20, 24, 32, 40, 48, 64, 128, 256] {
                touchedFiles.append("\(b.path)/windata/cxmenu/icons/hicolor/\(px)x\(px)/apps/\(tag).png")
            }
        }

        guard let (txId, _) = TransactionManager.shared.createSnapshot(action: "set-icon", target: item.name, bottle: item.bottleName, touchedFiles: touchedFiles) else {
            print("❌ Failed to initialize backup transaction.")
            return
        }
        print("📦 Transaction snapshot created: \(txId)")

        let tempIconset = "/tmp/\(txId).iconset"
        let tempIcns = "/tmp/\(txId).icns"
        defer {
            try? FileManager.default.removeItem(atPath: tempIconset)
            try? FileManager.default.removeItem(atPath: tempIcns)
        }

        guard SquircleRenderer.buildAppleIconset(from: masterRep, iconsetDir: tempIconset) else {
            print("❌ Failed to generate Apple iconset.")
            _ = TransactionManager.shared.rollback(id: txId)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "icns", tempIconset, "-o", tempIcns]
        try? proc.run()
        proc.waitUntilExit()

        guard FileManager.default.fileExists(atPath: tempIcns) else {
            print("❌ iconutil failed to compile .icns.")
            _ = TransactionManager.shared.rollback(id: txId)
            return
        }

        let fm = FileManager.default
        try? fm.removeItem(atPath: icnsDest)
        do {
            try fm.copyItem(atPath: tempIcns, toPath: icnsDest)
            print("✅ Updated: \(icnsDest)")
        } catch {
            print("❌ Failed to install .icns: \(error.localizedDescription)")
            _ = TransactionManager.shared.rollback(id: txId)
            return
        }

        if let b = bottle, let tag = item.iconTag {
            for px in [16, 20, 24, 32, 40, 48, 64, 128, 256] {
                let dir = "\(b.path)/windata/cxmenu/icons/hicolor/\(px)x\(px)/apps"
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let dest = "\(dir)/\(tag).png"
                if let rep = SquircleRenderer.resize(master: masterRep, toSize: px),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dest))
                }
            }
            print("✅ Updated bottle icons across all resolutions in [\(b.name)]")
        }

        TransactionManager.shared.completeSnapshot(id: txId, verified: true)
        let procTouch = Process()
        procTouch.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        procTouch.arguments = [appPath]
        try? procTouch.run()

        print("🎉 Successfully applied macOS squircle icon to \(item.name)!")
    }

    // MARK: - cmdRepair

    func cmdRepair(args: [String]) {
        guard let targetName = args.first, !targetName.hasPrefix("--") else {
            print("Usage: cxtool repair \"Game Name\" [--dry-run]")
            exit(2)
        }

        let shortcuts = discovery.scanAllShortcuts()
        let item = resolveOrExit(query: targetName, in: shortcuts)
        guard let appPath = item.appPath else {
            print("❌ Shortcut has no associated macOS app wrapper.")
            exit(1)
        }

        if item.isSquircle {
            print("✅ [\(item.name)] already conforms to macOS squircle standards. No repair needed.")
            return
        }

        let icnsPath = "\(appPath)/Contents/Resources/CrossOverHelper.icns"
        var passArgs = [item.name, icnsPath]
        if args.contains("--dry-run") { passArgs.append("--dry-run") }
        cmdSetIcon(args: passArgs)
    }

    // MARK: - cmdRepairAll

    func cmdRepairAll(args: [String]) {
        let dryRun = args.contains("--dry-run")
        let shortcuts = discovery.scanAllShortcuts()

        let needsRepair = shortcuts.filter { !$0.isSquircle }
        if needsRepair.isEmpty {
            print("🎉 All \(shortcuts.count) shortcuts already conform to macOS squircle standards! Nothing to repair.")
            return
        }

        print("Found \(needsRepair.count) shortcuts needing repair:")
        for item in needsRepair {
            print("  - \(item.name) (Bottle: \(item.bottleName), Corner Alpha: \(item.cornerAlpha))")
        }

        if dryRun {
            print("\nℹ️  [Dry-Run] Would repair \(needsRepair.count) shortcuts. No changes made.")
            return
        }

        for item in needsRepair {
            guard let appPath = item.appPath else { continue }
            let icnsPath = "\(appPath)/Contents/Resources/CrossOverHelper.icns"
            print("\n--- Repairing: \(item.name) ---")
            cmdSetIcon(args: [item.name, icnsPath])
        }

        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])
        print("\n🎉 Batch repair complete! Cache flushed.")
    }

    // MARK: - cmdRename

    func cmdRename(args: [String]) {
        guard args.count >= 2, !args[0].hasPrefix("--"), !args[1].hasPrefix("--") else {
            print("Usage: cxtool rename \"Current Name\" \"New Display Name\" [--dry-run]")
            exit(2)
        }

        let oldName = args[0]
        let newName = args[1]
        let dryRun = args.contains("--dry-run")

        let shortcuts = discovery.scanAllShortcuts()
        let item = resolveOrExit(query: oldName, in: shortcuts)
        guard let oldAppPath = item.appPath else {
            print("❌ Shortcut has no associated macOS app wrapper.")
            exit(1)
        }

        if shortcuts.contains(where: { $0.name.localizedCaseInsensitiveCompare(newName) == .orderedSame }) {
            print("❌ A shortcut named \"\(newName)\" already exists!")
            exit(1)
        }

        let fm = FileManager.default
        let appDir = (oldAppPath as NSString).deletingLastPathComponent
        let newAppPath = "\(appDir)/\(newName).app"
        let oldPlistPath = "\(oldAppPath)/Contents/Info.plist"

        let bottles = discovery.discoverBottles()
        guard let bottle = bottles.first(where: { $0.name == item.bottleName }) else {
            print("❌ Cannot find associated bottle [\(item.bottleName)]")
            exit(1)
        }

        let confPath = "\(bottle.path)/cxmenu.conf"
        let oldCmdPath = item.commandPath?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let oldStartMenuLnk = "\(bottle.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(item.name).lnk"
        let newStartMenuLnk = "\(bottle.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(newName).lnk"

        print("Planning rename operation:")
        print("  Target:           \(item.name) -> \(newName)")
        print("  macOS App:        \(oldAppPath) -> \(newAppPath)")
        print("  Bottle Config:    \(confPath)")
        if let cmd = oldCmdPath { print("  Launcher Script:  \(cmd)") }
        if fm.fileExists(atPath: oldStartMenuLnk) { print("  Windows Lnk:      \(oldStartMenuLnk) -> \(newStartMenuLnk)") }

        if dryRun {
            print("\nℹ️  [Dry-Run] Planned rename displayed above. No files were modified.")
            return
        }

        var touchedFiles = [oldPlistPath, confPath]
        if let cmd = oldCmdPath { touchedFiles.append(cmd) }
        if fm.fileExists(atPath: oldStartMenuLnk) { touchedFiles.append(oldStartMenuLnk) }

        guard let (txId, _) = TransactionManager.shared.createSnapshot(action: "rename", target: "\(item.name)_to_\(newName)", bottle: item.bottleName, touchedFiles: touchedFiles) else {
            print("❌ Failed to initialize transaction snapshot.")
            exit(1)
        }
        print("📦 Transaction snapshot created: \(txId)")

        var movedItems: [MovedItemRecord] = []

        // 1. Rename .app wrapper
        do {
            try fm.moveItem(atPath: oldAppPath, toPath: newAppPath)
            movedItems.append(MovedItemRecord(from: oldAppPath, to: newAppPath))
        } catch {
            print("❌ Failed to rename app wrapper: \(error.localizedDescription)")
            _ = TransactionManager.shared.rollback(id: txId)
            exit(1)
        }

        // 2. Update Info.plist inside new wrapper
        let newPlistPath = "\(newAppPath)/Contents/Info.plist"
        if let pData = try? Data(contentsOf: URL(fileURLWithPath: newPlistPath)),
           var plist = (try? PropertyListSerialization.propertyList(from: pData, options: .mutableContainersAndLeaves, format: nil)) as? [String: Any] {
            plist["CFBundleName"] = newName
            if let oldMPath = item.menuPath {
                let newMPath = oldMPath.replacingOccurrences(of: item.name, with: newName)
                plist["CrossOverHelperMenuPath"] = newMPath
            }
            if let oldCPath = item.commandPath {
                let newCPath = oldCPath.replacingOccurrences(of: item.name.replacingOccurrences(of: " ", with: "+"), with: newName.replacingOccurrences(of: " ", with: "+"))
                plist["CrossOverHelperCommand"] = newCPath
            }
            if let serialized = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? serialized.write(to: URL(fileURLWithPath: newPlistPath))
            }
        }

        // 3. Update cxmenu.conf section header
        if let confContent = try? String(contentsOfFile: confPath, encoding: .utf8),
           let oldMPath = item.menuPath {
            let newMPath = oldMPath.replacingOccurrences(of: item.name, with: newName)
            let updatedConf = confContent.replacingOccurrences(of: "[\(oldMPath)]", with: "[\(newMPath)]")
            try? updatedConf.write(toFile: confPath, atomically: true, encoding: .utf8)
        }

        // 4. Update Launcher script in desktopdata/cxmenu
        if let cmd = oldCmdPath, fm.fileExists(atPath: cmd) {
            let escapedOld = item.name.replacingOccurrences(of: " ", with: "+")
            let escapedNew = newName.replacingOccurrences(of: " ", with: "+")
            let newCmdPath = cmd.replacingOccurrences(of: escapedOld, with: escapedNew)
            if let scriptContent = try? String(contentsOfFile: cmd, encoding: .utf8) {
                let updatedScript = scriptContent.replacingOccurrences(of: "\(item.name).lnk", with: "\(newName).lnk")
                try? updatedScript.write(toFile: cmd, atomically: true, encoding: .utf8)
            }
            try? fm.moveItem(atPath: cmd, toPath: newCmdPath)
            movedItems.append(MovedItemRecord(from: cmd, to: newCmdPath))
        }

        // 5. Rename Windows Start Menu .lnk if present
        if fm.fileExists(atPath: oldStartMenuLnk) {
            try? fm.moveItem(atPath: oldStartMenuLnk, toPath: newStartMenuLnk)
            movedItems.append(MovedItemRecord(from: oldStartMenuLnk, to: newStartMenuLnk))
        }

        TransactionManager.shared.completeSnapshot(id: txId, verified: true, movedItems: movedItems)
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/touch"), arguments: [newAppPath])

        print("🎉 Successfully renamed [\(item.name)] to [\(newName)]!")
    }

    // MARK: - cmdDelete

    func cmdDelete(args: [String]) {
        guard let targetName = args.first, !targetName.hasPrefix("--") else {
            print("Usage: cxtool delete \"Game Name\" [--dry-run] [--force]")
            exit(2)
        }

        let dryRun = args.contains("--dry-run")
        let force = args.contains("--force")

        let shortcuts = discovery.scanAllShortcuts()
        let item = resolveOrExit(query: targetName, in: shortcuts)
        guard let appPath = item.appPath else {
            print("❌ Shortcut has no associated macOS app wrapper.")
            exit(1)
        }

        let bottles = discovery.discoverBottles()
        guard let bottle = bottles.first(where: { $0.name == item.bottleName }) else {
            print("❌ Cannot find associated bottle [\(item.bottleName)]")
            exit(1)
        }

        let fm = FileManager.default
        let confPath = "\(bottle.path)/cxmenu.conf"
        let cmdPath = item.commandPath?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let startMenuLnk = "\(bottle.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(item.name).lnk"
        let desktopLnk = "\(bottle.path)/drive_c/users/crossover/Desktop/\(item.name).lnk"

        print("⚠️  PLANNING SAFE SHORTCUT REMOVAL:")
        print("  Game:               \(item.name)")
        print("  Bottle:             \(item.bottleName)")
        print("  macOS Wrapper:      \(appPath)")
        if let cmd = cmdPath { print("  Launcher Script:    \(cmd)") }
        if fm.fileExists(atPath: startMenuLnk) { print("  Start Menu Shortcut:\(startMenuLnk)") }
        if fm.fileExists(atPath: desktopLnk) { print("  Desktop Shortcut:   \(desktopLnk)") }
        print("  Bottle Config:      \(confPath)")
        print("\n🔒 CRITICAL SAFETY GUARANTEE:")
        print("  • Game files & executable will NOT be touched.")
        print("  • Save files & user data will NOT be touched.")
        print("  • Only CrossOver integration wrappers & menu registrations will be removed.")

        if dryRun {
            print("\nℹ️  [Dry-Run] Displayed planned deletions above. No files were removed.")
            return
        }

        if !force {
            print("\nType 'yes' to confirm shortcut unregistration: ", terminator: "")
            fflush(stdout)
            guard let line = readLine(), line.lowercased().trimmingCharacters(in: .whitespaces) == "yes" else {
                print("Operation aborted by user.")
                return
            }
        }

        var touchedFiles = [confPath]
        if let cmd = cmdPath, fm.fileExists(atPath: cmd) { touchedFiles.append(cmd) }
        if fm.fileExists(atPath: startMenuLnk) { touchedFiles.append(startMenuLnk) }
        if fm.fileExists(atPath: desktopLnk) { touchedFiles.append(desktopLnk) }

        let icns = "\(appPath)/Contents/Resources/CrossOverHelper.icns"
        let plist = "\(appPath)/Contents/Info.plist"
        if fm.fileExists(atPath: icns) { touchedFiles.append(icns) }
        if fm.fileExists(atPath: plist) { touchedFiles.append(plist) }

        guard let (txId, _) = TransactionManager.shared.createSnapshot(action: "delete", target: item.name, bottle: item.bottleName, touchedFiles: touchedFiles) else {
            print("❌ Failed to initialize backup snapshot.")
            exit(1)
        }
        print("📦 Transaction snapshot created: \(txId)")

        // 1. Remove from cxmenu.conf
        if let confContent = try? String(contentsOfFile: confPath, encoding: .utf8),
           let mPath = item.menuPath {
            let lines = confContent.components(separatedBy: .newlines)
            var newLines: [String] = []
            var skipping = false
            for l in lines {
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                if trimmed == "[\(mPath)]" {
                    skipping = true
                    continue
                } else if skipping && trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    skipping = false
                }
                if !skipping {
                    newLines.append(l)
                }
            }
            try? newLines.joined(separator: "\n").write(toFile: confPath, atomically: true, encoding: .utf8)
            print("✅ Removed section [\(mPath)] from cxmenu.conf")
        }

        // 2. Remove launcher script
        if let cmd = cmdPath, fm.fileExists(atPath: cmd) {
            try? fm.removeItem(atPath: cmd)
            print("✅ Removed launcher script: \(cmd)")
        }

        // 3. Remove Start Menu & Desktop shortcuts
        if fm.fileExists(atPath: startMenuLnk) {
            try? fm.removeItem(atPath: startMenuLnk)
            print("✅ Removed Windows Start Menu shortcut: \(startMenuLnk)")
        }
        if fm.fileExists(atPath: desktopLnk) {
            try? fm.removeItem(atPath: desktopLnk)
            print("✅ Removed Windows Desktop shortcut: \(desktopLnk)")
        }

        // 4. Move .app wrapper to backup trash
        var archivedApps: [MovedItemRecord] = []
        let trashDir = TransactionManager.shared.backupBaseURL.appendingPathComponent(txId).appendingPathComponent("removed_apps")
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trashDest = trashDir.appendingPathComponent((appPath as NSString).lastPathComponent)
        do {
            try fm.moveItem(at: URL(fileURLWithPath: appPath), to: trashDest)
            archivedApps.append(MovedItemRecord(from: appPath, to: trashDest.path))
            print("✅ Archived macOS app wrapper to: \(trashDest.path)")
        } catch {
            print("❌ Failed to archive app wrapper: \(error.localizedDescription)")
            _ = TransactionManager.shared.rollback(id: txId)
            exit(1)
        }

        TransactionManager.shared.completeSnapshot(id: txId, verified: true, archivedApps: archivedApps)
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])

        print("🎉 Successfully unregistered [\(item.name)] from CrossOver!")
    }

    // MARK: - cmdBackup & cmdRestore

    func cmdBackup(args: [String]) {
        let note = getFlagValue("--note", from: args) ?? "manual_backup"
        let shortcuts = discovery.scanAllShortcuts()
        var touched: [String] = []

        for s in shortcuts {
            if let app = s.appPath {
                touched.append("\(app)/Contents/Resources/CrossOverHelper.icns")
            }
        }

        for b in discovery.discoverBottles() {
            touched.append("\(b.path)/cxmenu.conf")
        }

        if let (txId, _) = TransactionManager.shared.createSnapshot(action: "backup", target: note, bottle: "All", touchedFiles: touched) {
            TransactionManager.shared.completeSnapshot(id: txId, verified: true)
            print("✅ Created backup snapshot: \(txId)")
        } else {
            print("❌ Failed to create backup snapshot.")
            exit(1)
        }
    }

    func cmdRestore(args: [String]) {
        guard let backupId = args.first, !backupId.hasPrefix("--") else {
            print("Available Snapshots:")
            let snapshots = TransactionManager.shared.listSnapshots()
            for s in snapshots.prefix(10) {
                print("  \(s.transaction_id) | Target: \(s.target) | Action: \(s.action) | Files: \(s.files.count)")
            }
            print("\nUsage: cxtool restore <backup-id>")
            exit(2)
        }

        print("Restoring snapshot: \(backupId)...")
        if TransactionManager.shared.rollback(id: backupId) {
            print("✅ Rollback successful! Cache refreshed.")
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])
        } else {
            print("❌ Rollback encountered errors.")
            exit(1)
        }
    }

    // MARK: - cmdConfig

    func cmdConfig(args: [String]) {
        guard let sub = args.first else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(config), let s = String(data: data, encoding: .utf8) {
                print("Current Configuration (~/.cxtool.json):")
                print(s)
            }
            return
        }

        var cfg = config
        switch sub {
        case "show":
            cmdConfig(args: [])
        case "add-bottle-dir":
            guard args.count > 1 else { print("Usage: cxtool config add-bottle-dir <path>"); exit(2) }
            let dir = args[1]
            if !cfg.bottle_directories.contains(dir) {
                cfg.bottle_directories.append(dir)
                ConfigManager.shared.save(cfg)
                print("✅ Added bottle directory: \(dir)")
            }
        case "add-library-dir":
            guard args.count > 1 else { print("Usage: cxtool config add-library-dir <path>"); exit(2) }
            let dir = args[1]
            if !cfg.external_game_roots.contains(dir) {
                cfg.external_game_roots.append(dir)
                ConfigManager.shared.save(cfg)
                print("✅ Added external game library root: \(dir)")
            }
        default:
            print("Unknown config command: \(sub)")
            exit(2)
        }
    }

    // MARK: - cmdStatus (V1.2.0)

    func cmdStatus(args: [String]) {
        let bottles = discovery.discoverBottles()
        let bottleRoots = discovery.discoverBottleRoots()
        let appsDir = discovery.discoverProgramsFolder().path
        let shortcuts = discovery.scanAllShortcuts()
        let snapshots = TransactionManager.shared.listSnapshots()

        let crossoverDetected = !bottles.isEmpty || FileManager.default.fileExists(atPath: "/Applications/CrossOver.app")
        let healthyShortcuts = shortcuts.filter { $0.isSquircle && !$0.isOffline }.count
        let iconCompliant = shortcuts.filter { $0.isSquircle }.count
        let iconPercent = shortcuts.isEmpty ? 100.0 : (Double(iconCompliant * 1000 / shortcuts.count) / 10.0)

        var offlineRoots: [String] = []
        var onlineRoots: [String] = []
        for r in config.external_game_roots {
            if FileManager.default.fileExists(atPath: r) {
                onlineRoots.append(r)
            } else {
                offlineRoots.append(r)
            }
        }
        for s in shortcuts where s.isOffline {
            if let exe = s.targetExe {
                let prefix = (exe as NSString).pathComponents.prefix(3).joined(separator: "/")
                if !offlineRoots.contains(prefix) && !onlineRoots.contains(prefix) {
                    offlineRoots.append(prefix)
                }
            }
        }

        let totalBackupBytes = recursiveDirectorySize(at: TransactionManager.shared.backupBaseURL)
        let activeUndoSnapshot = snapshots.first(where: { $0.undone != true })
        let undoAvailable = activeUndoSnapshot != nil

        var lastTxSummary: LastTransactionSummary? = nil
        if let first = snapshots.first {
            let stat = first.undone == true ? "undone" : (first.verified ? "verified" : "unverified")
            lastTxSummary = LastTransactionSummary(
                transaction_id: first.transaction_id,
                action: first.action,
                target: first.target,
                bottle: first.bottle,
                created_at: first.created_at,
                status: stat
            )
        }

        let isLocked = ProcessLock.shared.isLocked()
        let lockStatus = isLocked ? "ACTIVE" : "IDLE"

        if self.isJSON {
            let report = StatusReport(
                environment: EnvironmentStatus(
                    crossover_detected: crossoverDetected,
                    bottle_roots: bottleRoots.map { $0.path },
                    applications_dir: appsDir
                ),
                inventory: InventoryStatus(
                    bottles_count: bottles.count,
                    bottles: bottles.map { $0.name },
                    shortcuts_count: shortcuts.count,
                    healthy_shortcuts_count: healthyShortcuts,
                    icon_compliant_count: iconCompliant,
                    icon_compliance_percent: iconPercent
                ),
                storage: StorageStatus(
                    external_roots_online: onlineRoots,
                    external_roots_offline: offlineRoots
                ),
                safety: SafetyStatus(
                    snapshots_count: snapshots.count,
                    backup_disk_bytes: totalBackupBytes,
                    backup_disk_human: formatBytes(totalBackupBytes),
                    undo_available: undoAvailable,
                    last_transaction: lastTxSummary,
                    mutation_lock: lockStatus
                )
            )
            printJSON(report)
            return
        }

        print("=== cxtool System Status ===")
        print("\n[Environment]")
        print("  CrossOver Detected ......... \(crossoverDetected ? "YES ✅" : "NO ⚠️")")
        print("  Applications Directory ..... \(appsDir)")
        print("  Bottle Roots (\(bottleRoots.count)) ........... \(bottleRoots.map { $0.path }.joined(separator: ", "))")

        print("\n[Inventory]")
        let bottleNames = bottles.map { $0.name }.joined(separator: ", ")
        print("  Active Bottles (\(bottles.count)) ......... \(bottleNames.isEmpty ? "<None>" : bottleNames)")
        print("  Total Shortcuts ............ \(shortcuts.count)")
        print("  Healthy Shortcuts .......... \(healthyShortcuts)")
        print("  Icon Compliance ............ \(iconCompliant)/\(shortcuts.count) (\(iconPercent)%) macOS Squircles \(iconPercent >= 100.0 ? "✅" : "⚠️")")

        print("\n[Storage]")
        print("  Online Roots (\(onlineRoots.count)) .......... \(onlineRoots.isEmpty ? "<None>" : onlineRoots.joined(separator: ", "))")
        print("  Offline Roots (\(offlineRoots.count)) ......... \(offlineRoots.isEmpty ? "<None>" : offlineRoots.joined(separator: ", ") + " ⚠️ (Protected)")")

        print("\n[Safety & Recovery]")
        print("  Snapshots Stored ........... \(snapshots.count)")
        print("  Backup Disk Usage .......... \(formatBytes(totalBackupBytes))")
        if let undoTarget = activeUndoSnapshot {
            print("  Undo Available ............. YES ✅ (Target: \(undoTarget.target), ID: \(undoTarget.transaction_id))")
        } else {
            print("  Undo Available ............. NONE")
        }
        if let tx = lastTxSummary {
            print("  Last Transaction ........... \(tx.transaction_id) [\(tx.action) -> \(tx.target)] (\(tx.status))")
        } else {
            print("  Last Transaction ........... <None>")
        }
        print("  Mutation Lock .............. \(lockStatus == "IDLE" ? "IDLE ✅" : "ACTIVE ⚠️")")
        print("")
    }

    // MARK: - cmdBackups (V1.2.0)

    func cmdBackups(args: [String]) {
        let sub = args.first(where: { !$0.hasPrefix("--") }) ?? "list"

        switch sub {
        case "list":
            cmdBackupsList()
        case "prune":
            cmdBackupsPrune(args: args)
        default:
            exitWithError(code: 2, type: "invalid_subcommand", message: "Unknown backups subcommand '\(sub)'. Usage: cxtool backups [list|prune] [options]", isJSON: self.isJSON)
        }
    }

    func cmdBackupsList() {
        let snapshots = TransactionManager.shared.listSnapshots()
        let activeUndoId = snapshots.first(where: { $0.undone != true })?.transaction_id
        var items: [BackupSnapshotItem] = []
        var totalBytes: Int64 = 0

        for s in snapshots {
            let sDir = TransactionManager.shared.backupBaseURL.appendingPathComponent(s.transaction_id)
            let bytes = recursiveDirectorySize(at: sDir)
            totalBytes += bytes

            let stat = s.undone == true ? "undone" : (s.verified ? "verified" : "unverified")
            let isUndo = s.transaction_id == activeUndoId

            items.append(BackupSnapshotItem(
                transaction_id: s.transaction_id,
                action: s.action,
                target: s.target,
                bottle: s.bottle,
                created_at: s.created_at,
                touched_files_count: s.files.count,
                disk_bytes: bytes,
                disk_human: formatBytes(bytes),
                status: stat,
                is_active_undo: isUndo
            ))
        }

        if self.isJSON {
            let report = BackupsListReport(
                total_snapshots: items.count,
                total_disk_bytes: totalBytes,
                total_disk_human: formatBytes(totalBytes),
                snapshots: items
            )
            printJSON(report)
            return
        }

        if items.isEmpty {
            print("No snapshot backups found in ~/.cxtool/backups/.")
            return
        }

        print("=== Stored Transaction Snapshots ===")
        print(String(format: "%-20@ | %-8@ | %-24@ | %-6@ | %-10@ | %-6@ | %-10@",
                     "Snapshot ID", "Action", "Target", "Files", "Disk Size", "Undo", "Status"))
        print(String(repeating: "-", count: 96))

        for item in items {
            print(String(format: "%-20@ | %-8@ | %-24@ | %-6@ | %-10@ | %-6@ | %-10@",
                         item.transaction_id.prefix(20) as NSString,
                         item.action as NSString,
                         item.target.prefix(24) as NSString,
                         "\(item.touched_files_count)" as NSString,
                         item.disk_human as NSString,
                         item.is_active_undo ? "YES ⭐" : "NO",
                         item.status as NSString))
        }
        print(String(repeating: "=", count: 96))
        print("Total: \(items.count) snapshot(s), consuming \(formatBytes(totalBytes)) on disk.")
        if let undoId = activeUndoId {
            print("Active undo target: \(undoId)")
        }
    }

    func cmdBackupsPrune(args: [String]) {
        let keep = nonNegativeIntegerFlag("--keep", in: args, defaultValue: 10)
        let days = nonNegativeIntegerFlag("--days", in: args, defaultValue: 30)
        let dryRun = args.contains("--dry-run")
        let force = args.contains("--force")

        let snapshots = TransactionManager.shared.listSnapshots()
        let activeUndoId = snapshots.first(where: { $0.undone != true })?.transaction_id

        var eligibleToPrune: [(manifest: TransactionManifest, dirURL: URL, size: Int64, ageDays: Int)] = []
        var preservedCount = 0

        let now = Date()
        let calendar = Calendar.current
        let isoFmt = ISO8601DateFormatter()

        for (index, s) in snapshots.enumerated() {
            let snapshotDir = TransactionManager.shared.backupBaseURL.appendingPathComponent(s.transaction_id)
            let dirSize = recursiveDirectorySize(at: snapshotDir)

            // Guard 1: Never prune the active undo snapshot
            if let undoId = activeUndoId, s.transaction_id == undoId {
                preservedCount += 1
                continue
            }

            // Guard 2: Only prune terminal snapshots (verified: true OR undone: true)
            let isTerminal = (s.verified == true) || (s.undone == true)
            guard isTerminal else {
                preservedCount += 1
                continue
            }

            // Guard 3: Dual retention condition (index >= keep AND age >= days)
            let createdDate = isoFmt.date(from: s.created_at) ?? now
            let ageDays = calendar.dateComponents([.day], from: createdDate, to: now).day ?? 0

            if index >= keep && ageDays >= days {
                eligibleToPrune.append((manifest: s, dirURL: snapshotDir, size: dirSize, ageDays: ageDays))
            } else {
                preservedCount += 1
            }
        }

        let totalReclaimableBytes = eligibleToPrune.reduce(0) { $0 + $1.size }

        if eligibleToPrune.isEmpty {
            if self.isJSON {
                let report = PruneReport(
                    dry_run: dryRun,
                    pruned_count: 0,
                    reclaimed_bytes: 0,
                    reclaimed_human: "0 B",
                    preserved_count: snapshots.count,
                    pruned_snapshots: []
                )
                printJSON(report)
                return
            }
            print("✅ No snapshots eligible for pruning. All \(snapshots.count) snapshot(s) retained.")
            print("   Criteria: outside newest \(keep) AND older than \(days) days, with terminal status and not active undo.")
            return
        }

        if !self.isJSON {
            print("=== Backups Retention Prune Plan ===")
            print("Criteria: outside newest \(keep) AND older than \(days) days.")
            print("Eligible snapshots for deletion (\(eligibleToPrune.count)):")
            for item in eligibleToPrune {
                print("  • \(item.manifest.transaction_id) (\(item.ageDays) days old, \(formatBytes(item.size))) [\(item.manifest.action) -> \(item.manifest.target)]")
            }
            print("Total disk space to reclaim: \(formatBytes(totalReclaimableBytes))")
        }

        if dryRun {
            if self.isJSON {
                let report = PruneReport(
                    dry_run: true,
                    pruned_count: eligibleToPrune.count,
                    reclaimed_bytes: totalReclaimableBytes,
                    reclaimed_human: formatBytes(totalReclaimableBytes),
                    preserved_count: preservedCount,
                    pruned_snapshots: eligibleToPrune.map { $0.manifest.transaction_id }
                )
                printJSON(report)
                return
            }
            print("\nℹ️  [Dry-Run] Retention prune preview displayed above. No files were deleted.")
            return
        }

        if !force && !self.isJSON {
            print("\nAre you sure you want to permanently delete these \(eligibleToPrune.count) snapshot(s)? [y/N]: ", terminator: "")
            fflush(stdout)
            let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "n"
            guard response == "y" || response == "yes" else {
                print("Prune aborted by user.")
                return
            }
        }

        var prunedIds: [String] = []
        var actuallyReclaimedBytes: Int64 = 0
        for item in eligibleToPrune {
            do {
                try FileManager.default.removeItem(at: item.dirURL)
                prunedIds.append(item.manifest.transaction_id)
                actuallyReclaimedBytes += item.size
            } catch {
                FileHandle.standardError.write(Data("❌ Failed to remove \(item.manifest.transaction_id): \(error.localizedDescription)\n".utf8))
            }
        }

        if self.isJSON {
            let report = PruneReport(
                dry_run: false,
                pruned_count: prunedIds.count,
                reclaimed_bytes: actuallyReclaimedBytes,
                reclaimed_human: formatBytes(actuallyReclaimedBytes),
                preserved_count: preservedCount,
                pruned_snapshots: prunedIds
            )
            printJSON(report)
            return
        }

        print("\n🎉 Prune complete! Deleted \(prunedIds.count) snapshot(s), reclaimed \(formatBytes(actuallyReclaimedBytes)).")
    }

    // MARK: - cmdCompletion (V1.2.0)

    func cmdCompletion(args: [String]) {
        let nonFlagArgs = args.filter { !$0.hasPrefix("--") }
        guard let shell = nonFlagArgs.first, shell.lowercased() == "zsh" else {
            exitWithError(code: 2, type: "invalid_usage", message: "Usage: cxtool completion zsh", isJSON: self.isJSON)
        }

        print(cxtoolZshCompletionScript)
    }

    // MARK: - Fast Read-Only Shell Helpers

    func cmdCompleteShortcuts() {
        let shortcuts = discovery.scanAllShortcuts()
        for s in shortcuts {
            print(s.name)
        }
    }

    func cmdCompleteBottles() {
        let bottles = discovery.discoverBottles()
        for b in bottles {
            print(b.name)
        }
    }

    // MARK: - Helper

    func getFlagValue(_ flag: String, from args: [String]) -> String? {
        if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }

    func nonNegativeIntegerFlag(_ flag: String, in args: [String], defaultValue: Int) -> Int {
        guard let index = args.firstIndex(of: flag) else { return defaultValue }
        guard index + 1 < args.count,
              let value = Int(args[index + 1]),
              value >= 0 else {
            exitWithError(code: 2, type: "invalid_usage", message: "\(flag) requires a non-negative integer.", isJSON: isJSON)
        }
        return value
    }
}

// MARK: - Main Entry Point

let cli = CXToolCLI()
cli.run(args: CommandLine.arguments)
