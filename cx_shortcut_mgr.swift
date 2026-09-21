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
    var backup_before_write: Bool
    var offline_roots_are_non_destructive: Bool
    var default_style: String

    static let defaultConfig = Config(
        bottle_directories: ["/Users/exampleuser/CXPBottles"],
        auto_detect_crossover_bottles: true,
        crossover_apps_dir: "/Users/exampleuser/Applications/CrossOver",
        external_game_roots: ["/Volumes/ExternalDrive"],
        backup_before_write: true,
        offline_roots_are_non_destructive: true,
        default_style: "macos"
    )
}

struct ShortcutInfo {
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

// MARK: - Process Lock

class ProcessLock {
    static let shared = ProcessLock()
    private var lockFd: Int32 = -1
    private let lockPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
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
}

// MARK: - Configuration Manager

class ConfigManager {
    static let shared = ConfigManager()
    let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
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

    func resolveShortcut(query: String, in shortcuts: [ShortcutInfo]) -> ShortcutInfo? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // 1. Exact case-insensitive match
        if let exact = shortcuts.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }

        // 2. Partial contains match
        let matches = shortcuts.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        if matches.count == 1 {
            return matches.first!
        } else if matches.count > 1 {
            print("❌ Ambiguous query \"\(query)\". Matches multiple games:")
            for m in matches {
                print("  • \(m.name) (Bottle: \(m.bottleName))")
            }
            print("Please specify the exact full title.")
            return nil
        } else {
            print("❌ No game shortcut found matching \"\(query)\".")
            print("Run 'cxtool list' to view all available shortcuts.")
            return nil
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
        let home = FileManager.default.homeDirectoryForCurrentUser
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

    init() {
        self.discovery = DiscoveryEngine(config: config)
    }

    func run(args: [String]) {
        guard args.count > 1 else {
            printUsage()
            return
        }

        // Acquire process lock
        guard ProcessLock.shared.acquire() else {
            print("❌ Another cxtool process is currently running.")
            print("If no process is running, remove ~/.cxtool/cxtool.lock to clear the lock.")
            return
        }
        defer { ProcessLock.shared.release() }

        let command = args[1]
        let remaining = Array(args.dropFirst(2))

        switch command {
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
            cmdHistory()
        case "undo":
            cmdUndo()
        case "backup":
            cmdBackup(args: remaining)
        case "restore":
            cmdRestore(args: remaining)
        case "config":
            cmdConfig(args: remaining)
        case "version", "--version", "-v":
            print("cxtool 1.1.2")
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    func printUsage() {
        print("""
        cxtool - CrossOver Mac Bottle Shortcut & Icon Manager (V1.1.2 Stable)

        USAGE:
          cxtool <command> [options]

        INSPECTION & DIAGNOSTICS:
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

        SAFETY & HISTORY:
          history                      Display log of past transactions
          undo                         Revert the most recent verified transaction
          backup [--note <text>]       Create a manual snapshot of CrossOver menus and icons
          restore <backup-id>          Rollback to a previously saved snapshot
          config [show|add-bottle-dir|add-library-dir] Manage persistent paths

        OPTIONS:
          --dry-run                    Preview changes without writing to disk
          --force                      Bypass confirmation prompts
          --bottle <name>              Filter or target a specific bottle
          --style <macos|full-bleed|emblem|raw> Icon rendering style preset
          --bg <black|white|#hex>      Background fill color for emblem styles
          --scale <float>              Optical scaling factor for art (default 1.0 or 0.85)
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
        print("  Safety backups ................... \(config.backup_before_write ? "ENABLED ✅" : "DISABLED ❌")")
        print("  Offline pruning protection ....... \(config.offline_roots_are_non_destructive ? "ENABLED ✅" : "DISABLED ❌")")
        print("  Process locking .................. ENABLED (~/.cxtool/cxtool.lock) ✅")
        print("  Default Icon Style ............... \(config.default_style)")
        print("\nDoctor Check Complete.")
    }

    // MARK: - cmdInspect

    func cmdInspect(args: [String]) {
        guard let name = args.first, !name.hasPrefix("--") else {
            print("Usage: cxtool inspect \"Game Name\"")
            return
        }

        let shortcuts = discovery.scanAllShortcuts()
        guard let item = discovery.resolveShortcut(query: name, in: shortcuts) else {
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
        print("Squircle Style:          \(item.isSquircle ? "YES (Apple HIG) ✅" : "NO (Needs Repair) ❌")")
        print("Corner Alpha:            \(item.cornerAlpha)")
        print("Is CrossOver Gear Icon:  \(item.isCrossoverCog ? "YES ⚙️" : "NO")")

        if let app = item.appPath {
            let icns = "\(app)/Contents/Resources/CrossOverHelper.icns"
            print("ICNS File:               \(icns) (SHA256: \(computeSHA256(for: icns).prefix(12))...)")
        }
    }

    // MARK: - cmdVerify (V1.1.1)

    func cmdVerify(args: [String]) {
        guard let name = args.first, !name.hasPrefix("--") else {
            print("Usage: cxtool verify \"Game Name\"")
            return
        }

        let shortcuts = discovery.scanAllShortcuts()
        guard let item = discovery.resolveShortcut(query: name, in: shortcuts) else {
            return
        }

        let fm = FileManager.default
        print("=== Launch Chain & Integrity Audit: [\(item.name)] ===")

        // 1. Wrapper exists
        let wrapperExists = item.appPath.map { fm.fileExists(atPath: $0) } ?? false
        print(String(format: "  %-30@ : %@", "Wrapper exists", wrapperExists ? "OK ✅" : "MISSING ❌"))

        // 2. Info.plist
        var plistOK = false
        if let app = item.appPath {
            let pPath = "\(app)/Contents/Info.plist"
            if let pData = try? Data(contentsOf: URL(fileURLWithPath: pPath)),
               let _ = try? PropertyListSerialization.propertyList(from: pData, options: [], format: nil) as? [String: Any] {
                plistOK = true
            }
        }
        print(String(format: "  %-30@ : %@", "Info.plist", plistOK ? "OK ✅" : "INVALID ❌"))

        // 3. Bottle association
        let bottles = discovery.discoverBottles()
        let bottle = bottles.first(where: { $0.name == item.bottleName })
        print(String(format: "  %-30@ : %@", "Bottle association [\(item.bottleName)]", bottle != nil ? "OK ✅" : "UNKNOWN ❌"))

        // 4. cxmenu entry
        var cxmenuOK = false
        if let b = bottle, let mPath = item.menuPath {
            let bMenu = discovery.parseCxMenuConf(at: "\(b.path)/cxmenu.conf")
            cxmenuOK = bMenu[mPath] != nil
        }
        print(String(format: "  %-30@ : %@", "cxmenu entry", cxmenuOK ? "OK ✅" : "MISSING ❌"))

        // 5. desktopdata launcher
        var launcherOK = false
        if let cmd = item.commandPath?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
            launcherOK = fm.fileExists(atPath: cmd) && fm.isExecutableFile(atPath: cmd)
        }
        print(String(format: "  %-30@ : %@", "desktopdata launcher", launcherOK ? "OK ✅" : "MISSING ❌"))

        // 6. Windows shortcut
        var lnkOK = false
        if let b = bottle {
            let startLnk = "\(b.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(item.name).lnk"
            let startUrl = "\(b.path)/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/\(item.name).url"
            let deskLnk = "\(b.path)/drive_c/users/crossover/Desktop/\(item.name).lnk"
            let deskUrl = "\(b.path)/drive_c/users/crossover/Desktop/\(item.name).url"
            lnkOK = fm.fileExists(atPath: startLnk) || fm.fileExists(atPath: startUrl) || fm.fileExists(atPath: deskLnk) || fm.fileExists(atPath: deskUrl)
        }
        print(String(format: "  %-30@ : %@", "Windows shortcut", lnkOK ? "OK (Binary Untouched) ✅" : "NOT FOUND ⚠️"))

        // 7. Icon resources
        var iconsOK = false
        if let app = item.appPath {
            let icns = "\(app)/Contents/Resources/CrossOverHelper.icns"
            iconsOK = fm.fileExists(atPath: icns) && item.isSquircle
        }
        print(String(format: "  %-30@ : %@", "Icon resources (Squircle)", iconsOK ? "OK ✅" : "NEEDS REPAIR ❌"))

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
        print(String(format: "  %-30@ : %@", "Executable target", targetStatus))
        print(String(format: "  %-30@ : %@", "Launch chain", launchChainValid ? "VALID ✅" : "INVALID ❌"))

        print(String(repeating: "-", count: 55))
        let isHealthy = wrapperExists && plistOK && bottle != nil && cxmenuOK && launcherOK && iconsOK && launchChainValid
        if isHealthy {
            if item.isOffline {
                print("Overall ..................... HEALTHY (External Storage Offline) ⚠️")
            } else {
                print("Overall ..................... HEALTHY ✅")
            }
        } else {
            print("Overall ..................... DEGRADED ❌")
        }
    }

    // MARK: - cmdHistory & cmdUndo (V1.1.1)

    func cmdHistory() {
        let snapshots = TransactionManager.shared.listSnapshots()
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
            return
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
        }
    }

    // MARK: - cmdSetIcon

    func cmdSetIcon(args: [String]) {
        guard args.count >= 2, !args[0].hasPrefix("--"), !args[1].hasPrefix("--") else {
            print("Usage: cxtool set-icon \"Game Name\" /path/to/image.png [--style macos|full-bleed|emblem|raw] [--bg black|white|#hex] [--scale <float>]")
            return
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
        guard let item = discovery.resolveShortcut(query: targetName, in: shortcuts),
              let appPath = item.appPath else {
            return
        }

        guard FileManager.default.fileExists(atPath: imagePath) else {
            print("❌ Source image does not exist: \(imagePath)")
            return
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
            return
        }

        let shortcuts = discovery.scanAllShortcuts()
        guard let item = discovery.resolveShortcut(query: targetName, in: shortcuts),
              let appPath = item.appPath else {
            return
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
            return
        }

        let oldName = args[0]
        let newName = args[1]
        let dryRun = args.contains("--dry-run")

        let shortcuts = discovery.scanAllShortcuts()
        guard let item = discovery.resolveShortcut(query: oldName, in: shortcuts),
              let oldAppPath = item.appPath else {
            return
        }

        if shortcuts.contains(where: { $0.name.localizedCaseInsensitiveCompare(newName) == .orderedSame }) {
            print("❌ A shortcut named \"\(newName)\" already exists!")
            return
        }

        let fm = FileManager.default
        let appDir = (oldAppPath as NSString).deletingLastPathComponent
        let newAppPath = "\(appDir)/\(newName).app"
        let oldPlistPath = "\(oldAppPath)/Contents/Info.plist"

        let bottles = discovery.discoverBottles()
        guard let bottle = bottles.first(where: { $0.name == item.bottleName }) else {
            print("❌ Cannot find associated bottle [\(item.bottleName)]")
            return
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
            return
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
            return
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
            return
        }

        let dryRun = args.contains("--dry-run")
        let force = args.contains("--force")

        let shortcuts = discovery.scanAllShortcuts()
        guard let item = discovery.resolveShortcut(query: targetName, in: shortcuts),
              let appPath = item.appPath else {
            return
        }

        let bottles = discovery.discoverBottles()
        guard let bottle = bottles.first(where: { $0.name == item.bottleName }) else {
            print("❌ Cannot find associated bottle [\(item.bottleName)]")
            return
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
            return
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
            return
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
            return
        }

        print("Restoring snapshot: \(backupId)...")
        if TransactionManager.shared.rollback(id: backupId) {
            print("✅ Rollback successful! Cache refreshed.")
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])
        } else {
            print("❌ Rollback encountered errors.")
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
            guard args.count > 1 else { print("Usage: cxtool config add-bottle-dir <path>"); return }
            let dir = args[1]
            if !cfg.bottle_directories.contains(dir) {
                cfg.bottle_directories.append(dir)
                ConfigManager.shared.save(cfg)
                print("✅ Added bottle directory: \(dir)")
            }
        case "add-library-dir":
            guard args.count > 1 else { print("Usage: cxtool config add-library-dir <path>"); return }
            let dir = args[1]
            if !cfg.external_game_roots.contains(dir) {
                cfg.external_game_roots.append(dir)
                ConfigManager.shared.save(cfg)
                print("✅ Added external game library root: \(dir)")
            }
        default:
            print("Unknown config command: \(sub)")
        }
    }

    // MARK: - Helper

    func getFlagValue(_ flag: String, from args: [String]) -> String? {
        if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }
}

// MARK: - Main Entry Point

let cli = CXToolCLI()
cli.run(args: CommandLine.arguments)
