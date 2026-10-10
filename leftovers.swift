import Darwin
import Foundation

let VERSION = "dev"
let fm = FileManager.default
let env = ProcessInfo.processInfo.environment
let SUDO = env["SUDO_USER"] != nil
let HOME = env["SUDO_USER"].flatMap { NSHomeDirectoryForUser($0) } ?? NSHomeDirectory()
let LIB = HOME + "/Library"
let TRASH = HOME + "/.Trash"
let TEMPLATE = "/System/Library/Templates/Data"
let IGNORE_FILE = HOME + "/.config/leftovers/ignore"
let RECENT_DAYS = 30.0

let SCAN_DIRS = [
    "Application Support", "Application Scripts", "Caches", "Containers", "Group Containers",
    "Cookies", "HTTPStorages", "LaunchAgents", "Logs", "Preferences", "Preferences/ByHost",
    "Saved Application State", "WebKit",
].map { LIB + "/" + $0 } + [
    "Application Support", "Caches", "LaunchAgents", "LaunchDaemons", "Logs",
    "Preferences", "PrivilegedHelperTools",
].map { "/Library/" + $0 }
let SCAN_SET = Set(SCAN_DIRS)
let SHARED_PRODUCTS = [
    "Google": ["Chrome": "com.google.chrome", "Chrome Beta": "com.google.chrome.beta", "Chrome Canary": "com.google.chrome.canary",
               "Chrome Dev": "com.google.chrome.dev", "Chrome for Testing": "com.google.chrome.for.testing"],
    "Microsoft": ["Teams": "com.microsoft.teams"],
]
let TOP_APP_DIRS = ["/Applications", HOME + "/Applications", "/opt", HOME + "/opt"]
let APP_DIRS = TOP_APP_DIRS + ["/System/Applications", "/System/Library/CoreServices", "/Library/Application Support",
                               LIB + "/Application Support/Steam/steamapps/common"]
let SYSTEM_NAME_DIRS = ["/System/Library/Frameworks", "/System/Library/PrivateFrameworks", "/usr/libexec",
                        "/usr/sbin", "/System/Library/CoreServices", "/opt", HOME + "/opt",
                        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", HOME + "/.local/bin",
                        HOME + "/.cargo/bin", HOME + "/go/bin"]
let LAUNCHD_DIRS = ["/System/Library/LaunchAgents", "/System/Library/LaunchDaemons", "/Library/LaunchAgents",
                    "/Library/LaunchDaemons", LIB + "/LaunchAgents"]
let CASKROOMS = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
let GENERIC_VENDORS: Set = ["com.github", "io.github", "com.electron", "org.chromium", "com.google.code", "com.apple",
                            "com.todesktop", "org.apache", "is.workflow"]
let SHARED_VENDORS: Set = ["com.google", "com.microsoft", "com.adobe"]
let UPDATERS = ["com.google.keystone", "com.google.softwareupdate", "com.microsoft.autoupdate"]
let CCTLD_SLD: Set = ["co", "com", "org", "net", "ac", "ne", "or", "gov", "edu"]
let SDK_DATA = ["comet": "libGalaxy.dylib", "kotlin": "Kotlin", "comandroidemulator": "android",
                "avatarcacheindex": "zPTApp.bundle"]
let IGNORE_PREFIXES = [
    "com.apple.", "apple", "is.workflow.", "tvappservices", "default.store",
    "com.segment.", "com.launchdarkly.", "com.telemetrydeck.", "io.sentry", "io.branch", "com.datadoghq",
    "org.sparkle-project.", "com.crashlytics", "com.qtproject", "com.plausiblelabs.", "com.bugsnag.", "com.hackemist.",
    "com.onevcat.", "com.microsoft.appcenter", "com.breakpad.",
]
let IGNORE: Set = [
    "addressbook", "animoji", "askpermission", "callhistorydb", "callhistorytransactions", "clouddocs",
    "crashreporter", "differentialprivacy", "diskimages", "fileprovider", "intelligenceflow", "knowledge",
    "mobilesync", "cookies", "hsts", "diagnosticreports", "nobackup", "minilauncher", "tokenbucketratelimiter",
    "lkdcsetup", "mcxtools", "hidfwcrashlogs", "desktoppictures", "databases", "localstorage", "btserver",
    "livefsd", "proapps", "auhostingservice", "audioconverterservice", "csexattrcryptoservice", "sandboxhelper",
    "statuskitagent", "mediaanalysisdaccess", "pkinstallsandboxmanager", "pkinstallsandboxmanagersharedtmp",
    "homeenergyd", "studentd", "corefollowup", "catacomb", "thunderboltaccessoryfirmwareupdates", "appstore",
    "syncservices", "icloud", "icdd", "networkserviceproxy", "familycircled", "geoservices", "passkit",
    "sharedimagecache", "mbuseragent", "baseband", "coresimulator", "photoslegacyupgrade", "photosupgrade",
    "siritts", "globalpreferences", "apmanalytics", "apmexperiment", "contextstoreagent", "mobilemeaccounts",
    "intentbuilderc", "loginwindow", "replayd", "sharedfilelistd", "livetranscriptionagent", "betaenrollmentd",
    "contentlinkingd", "diagnosticextensionsd", "gamed", "metrickitd", "mobiletimerd", "proactived",
    "ptpcamerad", "talagent", "watchlistd", "apptranslocation", "amsdatamigratortool", "arfilecache",
    "cloudkit", "gamekit", "pbs", "storeassetd", "storedownloadd", "webpush", "discrecording", "photossearch",
    "scopedbookmarkagent", "privacypreservingmeasurement", "stickersd", "privatecloudcomputed", "tipsd",
    "contactsd", "summaryevents", "identityservicesd", "embeddedbinaryvalidationutility", "aaprofilepicture",
    "locationaccessstored", "backgroundtaskmanagementagent", "osanalytics", "coreanalytics", "segment",
    "sentrycrash", "kscrash", "jna", "cef", "googleheartbeatstorage", "windowserver", "developertools",
    "mau20", "rlz",
]
let UUID_RE = "^([0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}|[0-9a-f]{32})$"
let ID_RE = "^[a-z0-9-]+(\\.[a-z0-9_-]+)+$"

var EXCLUDED: String? = nil, EXCLUDED_ID: String? = nil, EXCLUDED_NAMES = Set<String>()

func sub(_ s: String, _ re: String, _ with: String = "") -> String {
    s.replacingOccurrences(of: re, with: with, options: .regularExpression)
}

func matches(_ s: String, _ re: String) -> Bool { s.range(of: re, options: .regularExpression) != nil }

func ls(_ d: String) -> [String] { (try? fm.contentsOfDirectory(atPath: d)) ?? [] }

func stem(_ n: String) -> String {
    guard let i = n.lastIndex(of: "."), i != n.startIndex, n.index(after: i) != n.endIndex else { return n }
    return String(n[..<i])
}

func base(_ p: String) -> String { (p as NSString).lastPathComponent }

func lstatMode(_ p: String) -> mode_t? {
    var st = stat()
    return lstat(p, &st) == 0 ? st.st_mode & S_IFMT : nil
}

func expand(_ p: String) -> String { p.hasPrefix("~/") ? HOME + p.dropFirst() : p }

func tilde(_ p: String) -> String { p.hasPrefix(HOME + "/") ? "~" + p.dropFirst(HOME.count) : p }

func norm(_ s: String) -> String { sub(s.lowercased(), "[\\W_]") }

func key(_ name: String) -> String {
    var k = sub(name, "^[A-Z0-9]{10}\\.").lowercased()
    k = sub(k, "-(wal|shm|journal)$")
    k = sub(k, "\\.(plist|savedstate|binarycookies|log)$")
    k = sub(k, "-nodejs$", ".nodejs")
    return sub(k, "^(system)?groups?\\.")
}

func split(_ s: String) -> [String] { s.split(separator: ".", omittingEmptySubsequences: false).map(String.init) }

func vendor(_ bundleID: String) -> String? {
    let p = split(bundleID)
    let n = p[0].count == 2 && p.count > 1 && CCTLD_SLD.contains(p[1]) ? 3 : 2
    return p.count > n ? p[..<n].joined(separator: ".") : nil
}

func appKey(_ path: String) -> String {
    let k = key(base(path))
    if matches(k, ID_RE) {
        let p = split(k)
        return p.count > 2 ? p[1] : p[0]
    }
    return norm(k.split(separator: " ").first.map(String.init) ?? k)
}

func hasPrefix(_ sorted: [String], _ prefix: String) -> Bool {
    var lo = 0, hi = sorted.count
    while lo < hi {
        let m = (lo + hi) / 2
        if sorted[m] < prefix { lo = m + 1 } else { hi = m }
    }
    return lo < sorted.count && sorted[lo].hasPrefix(prefix)
}

struct Index {
    let teams, idset, vendors, names, cli, brands, bundled: Set<String>
    let ids, appNames, zaps, appPaths: [String]

    init(ids: Set<String>, appNames: Set<String>, sysNames: Set<String> = [], brands: Set<String> = [],
         teams: Set<String> = [], bundled: Set<String> = [], zaps: [String] = [], apps: Set<String> = []) {
        appPaths = apps.map { $0 + "/" }.sorted()
        self.teams = teams
        self.bundled = bundled
        self.zaps = zaps
        idset = Set(ids.map(key))
        self.ids = idset.sorted()
        vendors = Set(idset.compactMap(vendor)).subtracting(GENERIC_VENDORS)
        self.appNames = Set(appNames.map(norm)).subtracting([""]).sorted()
        names = Set(self.appNames).union(sysNames.filter { $0 != $0.lowercased() || $0 == $0.uppercased() }.map(norm))
        cli = sysNames.filter { $0 == $0.lowercased() && $0 != $0.uppercased() }
        let vendorNames = vendors.map { norm(split($0).last!) }
        self.brands = Set(brands.map(norm) + vendorNames).filter { $0.count >= 4 }
    }

    func zapped(_ path: String) -> Bool { zaps.contains { fnmatch($0, path, 0) == 0 } }

    func known(_ name: String) -> Bool {
        let k = key(name)
        if let x = EXCLUDED_ID, k == x || k.hasPrefix(x + "."),
           !idset.contains(where: { $0.hasPrefix(x + ".") && (k == $0 || k.hasPrefix($0 + ".")) }) { return false }
        if teams.contains(String(name.prefix(10))) && name.dropFirst(10).first == "." && !matches(k, ID_RE) {
            return true
        }
        let n = norm(k)
        if n.isEmpty || IGNORE_PREFIXES.contains(where: k.hasPrefix) || k.hasSuffix(".nodejs")
            || matches(k, UUID_RE) || IGNORE.contains(n) {
            return true
        }
        if EXCLUDED_NAMES.contains(n) { return false }
        if let file = SDK_DATA[n], bundled.contains(file) { return true }
        if UPDATERS.contains(where: k.hasPrefix) { return vendor(k).map(vendors.contains) ?? false }
        if names.contains(n) || cli.contains(sub(name, "\\.(plist|log)$")) { return true }
        if matches(k, ID_RE) {
            let parts = split(k)
            let v = vendor(k)
            if (2...parts.count).contains(where: { idset.contains(parts[..<$0].joined(separator: ".")) })
                || hasPrefix(ids, k + ".") || (v.map { vendors.contains($0) && !SHARED_VENDORS.contains($0) } ?? false) {
                return true
            }
            if parts.count > 2 { return false }
        }
        let c = Array(n)
        if c.count >= 4 && (hasPrefix(appNames, n) || brands.contains(String(c[..<4]))) { return true }
        for i in 0..<c.count where i + 5 <= c.count {
            for j in (i + 5)...c.count where brands.contains(String(c[i..<j])) { return true }
        }
        return false
    }
}

func loadPlist(_ path: String) -> [String: Any] {
    var st = stat()
    guard stat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size <= 1 << 20,
          let data = fm.contents(atPath: path) else { return [:] }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
}

func run(_ args: [String]) -> (out: Data, err: Data) {
    let p = Process(), out = Pipe(), err = Pipe()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardOutput = out
    p.standardError = err
    guard (try? p.run()) != nil else { return (Data(), Data()) }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (o, e)
}

func bundleRoot(_ app: String) -> String {
    lstatMode(app + "/Contents") == nil && lstatMode(app + "/WrappedBundle") != nil ? app + "/WrappedBundle" : app
}

func signature(_ app: String) -> (team: String?, groups: [String]) {
    let r = run(["/usr/bin/codesign", "-dv", "--entitlements", "-", "--xml", bundleRoot(app)])
    let team = String(decoding: r.err, as: UTF8.self).split(separator: "\n")
        .first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst(15)) }
    let ent = (try? PropertyListSerialization.propertyList(from: r.out, format: nil)) as? [String: Any]
    let groups = (ent?["com.apple.security.application-groups"] as? [Any])?.compactMap { $0 as? String } ?? []
    return (team.flatMap { matches($0, "^[A-Z0-9]{10}$") ? $0 : nil }, groups)
}

func launchdTarget(_ path: String) -> String? {
    let p = loadPlist(path)
    let raw = p["Program"]
    let prog = raw == nil || raw as? String == "" ? (p["ProgramArguments"] as? [Any])?.first as? String : raw as? String
    return prog?.hasPrefix("/") == true ? prog : nil
}

func excluded(_ path: String) -> Bool { EXCLUDED.map { path == $0 || path.hasPrefix($0 + "/") } ?? false }

func missing(_ path: String) -> Bool {
    if excluded(path) { return true }
    var st = stat()
    return stat(path, &st) != 0 && (errno == ENOENT || errno == ENOTDIR)
}

func foreignTarget(_ t: String) -> Bool { t.hasPrefix("/Library/PrivilegedHelperTools/") || t.hasPrefix(LIB + "/") }

func globbedApps(_ dirs: [String]) -> Set<String> {
    var r = Set<String>()
    for d in dirs {
        for a in ls(d) {
            if a.hasSuffix(".app") { r.insert(d + "/" + a); continue }
            for b in ls(d + "/" + a) where b.hasSuffix(".app") { r.insert(d + "/" + a + "/" + b) }
        }
    }
    return r
}

func nestedPlists(_ app: String) -> [String] {
    let root = bundleRoot(app)
    if root != app {
        return [root + "/Info.plist"] + ls(root + "/PlugIns").map { root + "/PlugIns/" + $0 + "/Info.plist" }
            .filter { fm.fileExists(atPath: $0) }
    }
    var r = [app + "/Contents/Info.plist"]
    for a in ls(app + "/Contents") {
        for b in ls(app + "/Contents/" + a) {
            let pb = app + "/Contents/" + a + "/" + b
            r += ([pb] + ls(pb).map { pb + "/" + $0 }).map { $0 + "/Contents/Info.plist" }.filter { fm.fileExists(atPath: $0) }
        }
    }
    return r
}

func zapPatterns() -> [String] {
    var r = [String]()
    for root in CASKROOMS {
        for cask in ls(root) {
            guard let data = fm.contents(atPath: "\(root)/\(cask)/.metadata/INSTALL_RECEIPT.json"),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let artifacts = json["uninstall_artifacts"] as? [[String: Any]] else { continue }
            let apps = artifacts.compactMap { $0["app"] as? [Any] }.joined().compactMap { $0 as? String }
            if !apps.isEmpty && apps.allSatisfy({ a in ["/Applications", HOME + "/Applications"].allSatisfy { missing($0 + "/" + a) } }) {
                continue
            }
            for zap in artifacts.compactMap({ $0["zap"] as? [[String: Any]] }).joined() {
                for value in zap.values {
                    r += ((value as? [Any]) ?? [value]).compactMap { $0 as? String }.map(expand)
                }
            }
        }
    }
    return r
}

func buildIndex() -> (index: Index, spotlightOK: Bool) {
    var ids = Set<String>(), appNames = Set<String>(), sysNames = Set<String>(), brands = Set<String>(),
        teams = Set<String>(), bundled = Set<String>()
    let found = Set(String(decoding: run(["/usr/bin/mdfind", "kMDItemContentType == 'com.apple.application-bundle'"]).out,
                           as: UTF8.self).split(separator: "\n").map(String.init))
    let top = globbedApps(TOP_APP_DIRS)
    let apps = found.filter { !$0.contains("/CoreSimulator/") }.union(globbedApps(APP_DIRS))
        .filter { !excluded($0) && (lstatMode($0 + "/Contents") != nil || lstatMode($0 + "/WrappedBundle") != nil) }
    let inLib = apps.filter { $0.hasPrefix(LIB + "/") }
    let visible = globbedApps(["/Applications", HOME + "/Applications"]).filter { lstatMode($0) == S_IFDIR }
    let spotlightOK = visible.filter(found.contains).count * 5 >= visible.count * 4

    func addApps(_ apps: Set<String>) {
        let list = Array(apps)
        var sigs = [(team: String?, groups: [String])](repeating: (nil, []), count: list.count)
        sigs.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: list.count) { buf[$0] = signature(list[$0]) }
        }
        for s in sigs {
            if let t = s.team { teams.insert(t) }
            ids.formUnion(s.groups)
        }
        for app in list {
            for d in ls(app + "/Contents/Library") where d.hasPrefix("Launch") {
                ids.formUnion(ls(app + "/Contents/Library/" + d).map { sub($0, "\\.plist$") })
            }
            for d in ["Frameworks", "PlugIns", "plugins"] { bundled.formUnion(ls(app + "/Contents/" + d)) }
            for (i, plist) in nestedPlists(app).enumerated() {
                let info = loadPlist(plist)
                let bid = info["CFBundleIdentifier"] as? String
                if let bid = bid, !bid.hasSuffix(".resources") { ids.insert(bid) }
                guard i == 0 else { continue }
                let names = Set([stem(base(app))] + ["CFBundleName", "CFBundleDisplayName"].compactMap { info[$0] as? String })
                if app.hasPrefix("/System/") { sysNames.formUnion(names) } else { appNames.formUnion(names) }
                if top.contains(app) && !(bid ?? "").hasPrefix("com.apple.") { brands.formUnion(names) }
            }
        }
    }

    addApps(apps.subtracting(inLib))
    for d in (env["PATH"] ?? "").split(separator: ":").map(String.init) + SYSTEM_NAME_DIRS {
        sysNames.formUnion(ls(d).filter { n in
            EXCLUDED == nil ? fm.fileExists(atPath: d + "/" + n)
                            : !missing(URL(fileURLWithPath: d + "/" + n).resolvingSymlinksInPath().path)
        }.map(stem))
    }
    brands.formUnion(ls("/opt") + ls(HOME + "/opt"))
    for fw in ls("/System/Library") where fw.hasSuffix("Frameworks") {
        for f in ls("/System/Library/" + fw) where f.hasSuffix(".framework") {
            for x in ["/XPCServices", "/Versions/A/XPCServices"] {
                sysNames.formUnion(ls("/System/Library/" + fw + "/" + f + x).filter { $0.hasSuffix(".xpc") }.map(stem))
            }
        }
    }
    for d in LAUNCHD_DIRS {
        for f in ls(d) where f.hasSuffix(".plist") {
            let p = d + "/" + f
            let target = launchdTarget(p)
            if d.hasPrefix("/System/") || (target.map { !missing($0) && !foreignTarget($0) } ?? false) {
                ids.insert(loadPlist(p)["Label"] as? String ?? stem(f))
                if let t = target { sysNames.insert(base(t)) }
            }
        }
    }
    let zaps = zapPatterns()
    let first = Index(ids: ids, appNames: appNames, sysNames: sysNames, brands: brands, teams: teams,
                      bundled: bundled, zaps: zaps)
    addApps(inLib.filter { app in
        let parts = String(app.dropFirst(LIB.count + 1)).split(separator: "/").map(String.init)
        return first.known(parts.count > 1 ? parts[1] : "")
    })
    let index = Index(ids: ids, appNames: appNames, sysNames: sysNames, brands: brands, teams: teams,
                      bundled: bundled, zaps: zaps, apps: apps)
    return (index, spotlightOK)
}

@discardableResult
func walk(_ dir: String, _ visit: (String, Bool) -> Bool) -> Bool {
    guard let dp = opendir(dir) else { return true }
    defer { closedir(dp) }
    while let e = readdir(dp) {
        let name = withUnsafeBytes(of: e.pointee.d_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        if name == "." || name == ".." { continue }
        let path = dir + "/" + name
        var type = Int32(e.pointee.d_type)
        if type == DT_UNKNOWN { type = lstatMode(path) == S_IFDIR ? DT_DIR : DT_REG }
        var st = stat()
        if type == DT_DIR {
            if !visit(path, true) || !walk(path, visit) { return false }
        } else if !(type == DT_LNK && stat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR), !visit(path, false) {
            return false
        }
    }
    return true
}

func foreignOnly(_ p: String) -> Bool {
    guard lstatMode(p) == S_IFDIR, let kids = try? fm.contentsOfDirectory(atPath: p) else { return false }
    let visible = kids.filter { !$0.hasPrefix(".") }
    if !visible.isEmpty && visible.allSatisfy({ $0.hasPrefix("com.apple.") }) { return true }
    var any = false
    let onlyHosts = walk(p) { f, isDir in
        if isDir || base(f).hasPrefix(".") { return true }
        any = true
        return f.contains("/NativeMessagingHosts/") || f.contains("/External Extensions/")
    }
    return onlyHosts && any
}

func treeStats(_ p: String) -> (size: Int64?, mtime: Double?) {
    var st = stat()
    guard lstat(p, &st) == 0 else { return (nil, nil) }
    var size = Int64(st.st_blocks) * 512, mtime = Double(st.st_mtimespec.tv_sec)
    guard st.st_mode & S_IFMT == S_IFDIR else { return (size, mtime) }
    guard let dp = opendir(p) else { return (nil, nil) }
    closedir(dp)
    size = 0
    walk(p) { f, _ in
        var s = stat()
        if lstat(f, &s) == 0 {
            size += Int64(s.st_blocks) * 512
            mtime = max(mtime, Double(s.st_mtimespec.tv_sec))
        }
        return true
    }
    return (size, mtime)
}

func leftoverReason(_ idx: Index, _ d: String, _ name: String) -> String? {
    let p = d + "/" + name
    if name.hasPrefix(".") || SCAN_SET.contains(p) || lstatMode(TEMPLATE + p) != nil || idx.zapped(p)
        || hasPrefix(idx.appPaths, p + "/") { return nil }
    let target = d.hasSuffix("/LaunchAgents") || d.hasSuffix("/LaunchDaemons") ? launchdTarget(p) : nil
    if let t = target, missing(t), !t.hasPrefix("/Volumes/") { return "launchd job runs \(tilde(t)), which no longer exists" }
    if let t = target, !foreignTarget(t) { return nil }
    return idx.known(name) || foreignOnly(p) ? nil : "no installed app matches this name"
}

struct Item {
    let path: String, size: Int64?, mtime: Double?, reason: String
    var error: String? = nil

    var recent: Bool { mtime.map { Date().timeIntervalSince1970 - $0 < RECENT_DAYS * 86400 } ?? false }
}

func loadIgnored() -> Set<String> {
    let text = (try? String(contentsOfFile: IGNORE_FILE, encoding: .utf8)) ?? ""
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    return Set((lines + lines.map { $0.trimmingCharacters(in: .whitespaces) })
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }.map(expand))
}

func candidates(_ idx: Index, _ ignored: Set<String>, unreadable: inout Int) -> [(path: String, reason: String)] {
    var r = [(path: String, reason: String)]()
    func check(_ d: String) {
        guard let names = try? fm.contentsOfDirectory(atPath: d) else {
            unreadable += 1
            return
        }
        for n in names {
            let p = d + "/" + n
            if ignored.contains(p) { continue }
            if SCAN_SET.contains(d), let products = SHARED_PRODUCTS[n], lstatMode(p) == S_IFDIR {
                if !idx.known(n) {
                    check(p)
                    continue
                }
                for (c, id) in products where lstatMode(p + "/" + c) != nil && !idx.idset.contains(id)
                    && !ignored.contains(p + "/" + c) && !foreignOnly(p + "/" + c) {
                    r.append((p + "/" + c, "\(c) is not installed"))
                }
            } else if let why = leftoverReason(idx, d, n) {
                r.append((p, why))
            }
        }
    }
    for d in SCAN_DIRS where lstatMode(d) == S_IFDIR { check(d) }
    return r
}

func item(_ path: String, _ reason: String) -> Item {
    let s = treeStats(path)
    return Item(path: path, size: s.size, mtime: s.mtime, reason: reason)
}

func warnings(_ items: [Item], spotlightOK: Bool, unreadable: Int) -> [String] {
    var w = [String]()
    if !spotlightOK { w.append("Spotlight index looks incomplete — installed apps may show up") }
    let n = unreadable + items.filter { $0.size == nil }.count
    if n > 0 { w.append("\(n) folder\(n == 1 ? "" : "s") unreadable — give your terminal Full Disk Access") }
    return w
}

func scan() -> (items: [Item], warnings: [String]) {
    let (idx, spotlightOK) = buildIndex()
    var unreadable = 0
    let items = candidates(idx, loadIgnored(), unreadable: &unreadable).map { item($0.path, $0.reason) }
    return (items, warnings(items, spotlightOK: spotlightOK, unreadable: unreadable))
}

func findApp(_ query: String) -> String? {
    let found: String?
    if query.contains("/") {
        let p = realpath(expand(query), nil).map { r in defer { free(r) }; return String(cString: r) } ?? ""
        found = p.hasSuffix(".app") && lstatMode(p) == S_IFDIR && !p.dropLast(4).contains(".app/") ? p : nil
    } else {
        let q = sub(query.lowercased(), "\\.app$")
        let apps = globbedApps(TOP_APP_DIRS).sorted()
        let prefixed = apps.filter { stem(base($0)).lowercased().hasPrefix(q) }
        found = apps.first { stem(base($0)).lowercased() == q } ?? apps.first { app in
            let info = loadPlist(app + "/Contents/Info.plist")
            return ["CFBundleName", "CFBundleDisplayName"].contains { (info[$0] as? String)?.lowercased() == q }
        } ?? (prefixed.count == 1 ? prefixed[0] : nil)
    }
    let id = found.flatMap { loadPlist($0 + "/Contents/Info.plist")["CFBundleIdentifier"] as? String } ?? ""
    return id.hasPrefix("com.apple.") ? nil : found
}

func appScan(_ app: String) -> (items: [Item], warnings: [String]) {
    let ignored = loadIgnored()
    var unreadable = 0
    let before = Set(candidates(buildIndex().index, ignored, unreadable: &unreadable).map(\.path))
    let info = loadPlist(nestedPlists(app)[0]), name = stem(base(app))
    EXCLUDED = app
    EXCLUDED_ID = (info["CFBundleIdentifier"] as? String).map(key)
    let (idx, spotlightOK) = buildIndex()
    EXCLUDED_NAMES = Set(([name] + ["CFBundleName", "CFBundleDisplayName"].compactMap { info[$0] as? String }).map(norm))
        .subtracting(idx.names)
    let own = candidates(idx, ignored, unreadable: &unreadable).filter { !before.contains($0.path) }
    (EXCLUDED, EXCLUDED_ID, EXCLUDED_NAMES) = (nil, nil, [])
    let items = [item(app, "the app itself")] + own.map { item($0.path, "belongs to \(name)") }
    var w = warnings(items, spotlightOK: spotlightOK, unreadable: unreadable / 2)
    if !run(["/usr/bin/pgrep", "-f", NSRegularExpression.escapedPattern(for: app + "/")]).out.isEmpty {
        w.insert("\(name) is running — quit it before moving it to Trash", at: 0)
    }
    return (items, w)
}

func groups(_ items: [Item]) -> [String: String] {
    let plain = Set(items.filter { !matches(key(base($0.path)), ID_RE) }.map { appKey($0.path) })
    return Dictionary(uniqueKeysWithValues: items.map { it -> (String, String) in
        let k = key(base(it.path)), last = norm(split(k).last ?? "")
        return (it.path, matches(k, ID_RE) && plain.contains(last) ? last : appKey(it.path))
    })
}

func sorted(_ items: [Item], byApp: Bool) -> [Item] {
    let bySize = { (a: Item, b: Item) in (a.size ?? 0, b.path) > (b.size ?? 0, a.path) }
    guard byApp else { return items.sorted(by: bySize) }
    let g = groups(items)
    let totals = Dictionary(grouping: items, by: { g[$0.path]! }).mapValues { $0.reduce(Int64(0)) { $0 + ($1.size ?? 0) } }
    return items.sorted { a, b in
        let ka = g[a.path]!, kb = g[b.path]!
        return ka == kb ? bySize(a, b) : (totals[ka]!, kb) > (totals[kb]!, ka)
    }
}

func human(_ n: Int64?) -> String {
    guard var v = n.map(Double.init) else { return "?" }
    for u in ["B", "K", "M", "G", "T"] {
        if v < 1024 || u == "T" { return u == "B" ? String(format: "%.0fB", v) : String(format: "%.1f", v) + u }
        v /= 1024
    }
    return "?"
}

let dateFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

func date(_ mtime: Double?) -> String { mtime.map { dateFormat.string(from: Date(timeIntervalSince1970: $0)) } ?? "?" }

func short(_ path: String) -> String {
    String(String.UnicodeScalarView(tilde(path).unicodeScalars.map { $0.value < 32 || (0x7f...0x9f).contains($0.value) ? "?" : $0 }))
}

struct Failure: Error { let message: String }

func explain(_ code: Int32) -> String {
    let s = String(cString: strerror(code))
    return code == EACCES || code == EPERM ? s + " (try sudo or Full Disk Access)" : s
}

func trash(_ path: String) throws {
    if !SUDO {
        do {
            try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            let e = error as NSError, inner = e.userInfo[NSUnderlyingErrorKey] as? NSError
            if let posix = [inner, e].compactMap({ $0 }).first(where: { $0.domain == NSPOSIXErrorDomain }) {
                throw Failure(message: explain(Int32(posix.code)))
            }
            throw Failure(message: e.code == NSFileWriteNoPermissionError ? explain(EACCES) : e.localizedDescription)
        }
        return
    }
    guard lstatMode(TRASH) == S_IFDIR else { throw Failure(message: "\(short(TRASH)) is not a Trash folder") }
    let name = base(path)
    var dest = TRASH + "/" + name, n = 1
    while lstatMode(dest) != nil {
        dest = TRASH + "/\(name) \(n)"
        n += 1
    }
    if renamex_np(path, dest, UInt32(RENAME_EXCL)) != 0 { throw Failure(message: explain(errno)) }
}

func asUser<T>(_ body: () throws -> T) rethrows -> T {
    guard SUDO, let uid = env["SUDO_UID"].flatMap(uid_t.init), let gid = env["SUDO_GID"].flatMap(gid_t.init),
          setegid(gid) == 0, seteuid(uid) == 0 else { return try body() }
    defer {
        seteuid(0)
        setegid(0)
    }
    return try body()
}

func addIgnore(_ path: String) throws {
    try asUser {
        try fm.createDirectory(atPath: (IGNORE_FILE as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let old = fm.contents(atPath: IGNORE_FILE) ?? Data()
        let line = (old.isEmpty || old.last == 10 ? "" : "\n") + tilde(path) + "\n"
        guard let h = FileHandle(forWritingAtPath: IGNORE_FILE) else {
            return try Data(line.utf8).write(to: URL(fileURLWithPath: IGNORE_FILE))
        }
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(line.utf8))
    }
}

let ESC = "\u{1b}["
let RESET = ESC + "0m", BOLD = ESC + "1m", DIM = ESC + "2m", GREEN = ESC + "32m", RED = ESC + "31m", YELLOW = ESC + "33m"
let BAR = ESC + "7m", BAR_OK = ESC + "42;30m", BAR_ERR = ESC + "41;97m", BAR_ASK = ESC + "43;30m"
let HINTS = [("space", "select"), ("a", "all"), ("d", "trash"), ("?", "help"), ("q", "quit")]
let SHORT_HINTS = [("?", "help"), ("q", "quit")]
let HELP = [
    ("↑ ↓  j k", "move"),
    ("PgUp PgDn  g G", "page, top, bottom"),
    ("space", "select item"),
    ("a", "select all except recently modified, or clear selection"),
    ("A", "select everything from the same app"),
    ("s", "sort by size or group by app"),
    ("i", "hide item for good (~/.config/leftovers/ignore)"),
    ("o", "reveal in Finder"),
    ("d  Enter", "move selected items, or the current one, to Trash"),
    ("q", "quit"),
]

func width(_ s: String) -> Int {
    s.unicodeScalars.reduce(0) { n, u in
        let w = wcwidth(wchar_t(u.value))
        return n + (w < 0 ? 1 : Int(w))
    }
}

func fit(_ s: String, _ w: Int, tail: Bool = false) -> String {
    guard w > 0 else { return "" }
    let sw = width(s)
    if sw <= w { return s + String(repeating: " ", count: w - sw) }
    var kept = [Character](), kw = 0
    for ch in tail ? Array(s.reversed()) : Array(s) {
        let cw = width(String(ch))
        if kw + cw > w - 1 { break }
        kept.append(ch)
        kw += cw
    }
    let body = String(tail ? kept.reversed() : kept), padding = String(repeating: " ", count: w - 1 - kw)
    return tail ? "…" + body + padding : body + "…" + padding
}

func sizeColor(_ n: Int64?) -> String {
    guard let n = n else { return DIM }
    return n >= 1 << 30 ? ESC + "1;31m" : n >= 100 << 20 ? YELLOW : n >= 1 << 20 ? "" : DIM
}

func bar(_ text: String, _ hints: [[(String, String)]], _ style: String, _ w: Int) -> String {
    let left = " " + text + "  "
    for h in hints {
        let plain = h.map { "\($0.0) \($0.1)" }.joined(separator: "  ") + " "
        guard width(left) + width(plain) <= w else { continue }
        let styled = h.map { BOLD + $0.0 + ESC + "22m " + $0.1 }.joined(separator: "  ") + " "
        return style + left + String(repeating: " ", count: w - width(left) - width(plain)) + styled + RESET
    }
    return style + fit(left, w) + RESET
}

struct Layout {
    let w: Int, showSize: Bool, showDate: Bool, pathW: Int
    init(_ w: Int) {
        self.w = w
        showSize = w >= 30
        showDate = w >= 50
        pathW = max(0, w - 5 - (showSize ? 10 : 0) - (showDate ? 12 : 0))
    }

    var header: String {
        BOLD + "    " + fit("PATH", pathW) + (showSize ? "      SIZE" : "") + (showDate ? "  MODIFIED  " : "") + " " + RESET
    }

    func row(_ it: Item, selected: Bool, current: Bool) -> String {
        let check = selected ? "[x] " : it.error != nil ? "[!] " : "[ ] ", path = fit(short(it.path), pathW, tail: true)
        let size = showSize ? "  " + String(repeating: " ", count: max(0, 8 - width(human(it.size)))) + human(it.size) : ""
        let day = showDate ? "  " + fit(date(it.mtime), 10) : ""
        if current { return ESC + "1;7m" + fit(check + path + size + day + " ", w) + RESET }
        let cut = path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex
        let mark: String = it.error != nil ? RED : selected ? GREEN : DIM
        let folder = String(path[..<cut]), name = String(path[cut...])
        let left: String = mark + check + RESET + DIM + folder + RESET + (selected ? GREEN : "") + name + RESET
        let right: String = sizeColor(it.size) + size + RESET + (it.recent ? YELLOW : DIM) + day + " " + RESET
        return left + right
    }

    func details(_ it: Item) -> String {
        let days = it.mtime.map { max(0, Int((Date().timeIntervalSince1970 - $0) / 86400)) } ?? 0
        let (color, text) = it.error.map { (RED, "✗ " + short($0)) } ?? (it.recent
            ? (YELLOW, "modified \(days == 0 ? "today" : "\(days)d ago"), may still be in use · " + it.reason)
            : (DIM, it.reason))
        let shown = width(text) < w - 1 ? text : fit(text, max(0, w - 1))
        return color + shown + RESET + DIM + fit("  " + short(it.path), max(0, w - 1 - width(shown))) + RESET
    }
}

var gotSignal: Int32 = 0
var savedTermios = termios()

func out(_ s: String) { FileHandle.standardOutput.write(s.data(using: .utf8)!) }

func termSize() -> (h: Int, w: Int) {
    var ws = winsize()
    return ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0 ? (Int(ws.ws_row), Int(ws.ws_col)) : (24, 80)
}

func enterScreen(_ text: String) {
    tcgetattr(0, &savedTermios)
    var raw = savedTermios
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG | IEXTEN)
    raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
    withUnsafeMutableBytes(of: &raw.c_cc) { cc in
        cc[Int(VMIN)] = 1
        cc[Int(VTIME)] = 0
    }
    tcsetattr(0, TCSAFLUSH, &raw)
    for s in [SIGTERM, SIGHUP, SIGINT, SIGQUIT] { signal(s) { gotSignal = $0 } }
    let (h, w) = termSize()
    out(ESC + "?1049h" + ESC + "?25l" + ESC + "?7l" + ESC + "2J" + ESC + "\(h / 2);\(max(1, (w - width(text)) / 2))H" + DIM + text + RESET)
}

func leaveScreen() {
    out(RESET + ESC + "?7h" + ESC + "?25h" + ESC + "?1049l")
    tcsetattr(0, TCSAFLUSH, &savedTermios)
}

func ui(_ initial: [Item], notes: [String], preselect: Bool) {
    var byApp = false, items = sorted(initial, byApp: false), cur = 0, top = 0
    var sel = preselect ? Set(items.map(\.path)) : []
    var notes = notes
    var msg: (text: String, style: String)? = notes.isEmpty ? nil : (notes.removeFirst(), BAR_ASK)
    var pending = [UInt8]()
    func partial() -> Bool {
        guard pending.first == 27 else { return pending.isEmpty }
        return pending.count < 3 || (pending[1] == 91 || pending[1] == 79) && !pending[2...].contains { (64...126).contains($0) }
    }
    func readKey() -> [UInt8] {
        while partial() {
            var p = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, pending.isEmpty ? 100 : 10) > 0 else { break }
            var buf = [UInt8](repeating: 0, count: 64)
            let n = read(0, &buf, 64)
            guard n > 0 else {
                gotSignal = SIGHUP
                return []
            }
            pending += buf[..<n]
        }
        if pending.isEmpty { return [] }
        var len = 1
        if pending[0] == 27, pending.count > 2, pending[1] == 91 || pending[1] == 79 {
            len = 2
            while len < pending.count && !(64...126).contains(pending[len]) { len += 1 }
            len = min(len + 1, pending.count)
        }
        defer { pending.removeFirst(len) }
        return Array(pending[..<len])
    }
    func waitKey(_ draw: (Int, Int) -> String) -> [UInt8] {
        pending = []
        var shown = (h: 0, w: 0)
        while gotSignal == 0 {
            let sz = termSize()
            if sz != shown {
                out(draw(sz.h, sz.w))
                shown = sz
            }
            let k = readKey()
            if !k.isEmpty { return k }
        }
        return []
    }
    func help(_ h: Int, _ w: Int) -> String {
        let legend = [(YELLOW, "2026-01-01", "date modified in the last \(Int(RECENT_DAYS)) days, may still be in use"),
                      (RED, "red", "could not be moved, the line above the status bar says why")]
        var lines = [BOLD + "Keys" + RESET] + HELP.map { BOLD + fit($0.0, 16) + RESET + fit($0.1, max(0, w - 20)) }
            + [""] + legend.map { $0.0 + fit($0.1, 16) + RESET + fit($0.2, max(0, w - 20)) }
        if lines.count > h - 1 { lines = Array(lines.dropFirst().filter { !$0.isEmpty }.prefix(max(0, h - 1))) }
        let s = lines.enumerated().map { ESC + "\($0.offset + 1);3H" + $0.element }.joined()
        return ESC + "2J" + s + ESC + "\(h);1H" + bar("Press any key", [[]], BAR, w)
    }
    var last = (h: 0, w: 0), dirty = true
    while true {
        let (h, w) = termSize()
        let rows = max(1, h - (h > 3 ? 3 : 2)), layout = Layout(w)
        cur = max(0, min(cur, items.count - 1))
        top = max(0, min(max(top, cur - rows + 1), cur, items.count - rows))
        let chosen = items.filter { sel.contains($0.path) }
        let total = chosen.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        if dirty || last != (h, w) {
            var s = ESC + "1;1H" + ESC + "K" + layout.header
            for y in 0..<rows {
                let i = top + y
                s += ESC + "\(y + 2);1H" + ESC + "K"
                if i < items.count {
                    s += layout.row(items[i], selected: sel.contains(items[i].path), current: i == cur)
                } else if items.isEmpty && y == 0 {
                    s += DIM + "    All clean. Press q to quit." + RESET
                }
            }
            if h > 3 { s += ESC + "\(h - 1);1H" + ESC + "K" + (items.isEmpty ? "" : layout.details(items[cur])) }
            let status = (sel.isEmpty
                ? "\(items.count) leftovers · \(human(items.reduce(Int64(0)) { $0 + ($1.size ?? 0) }))"
                : "\(sel.count) of \(items.count) selected · \(human(total))") + (byApp ? " · by app" : "")
            s += ESC + "\(h);1H" + (msg.map { bar($0.text, [HINTS, SHORT_HINTS, []], $0.style, w) }
                                     ?? bar(status, [HINTS, SHORT_HINTS, []], BAR, w))
            out(s)
            last = (h, w)
            dirty = false
        }
        let k = readKey()
        if gotSignal != 0 { return }
        if k.isEmpty { continue }
        dirty = true
        msg = notes.isEmpty ? nil : (notes.removeFirst(), BAR_ASK)
        if k == [113] || k == [3] { return }
        if k == [63] {
            _ = waitKey(help)
            out(ESC + "2J")
            continue
        }
        if items.isEmpty { continue }
        let path = items[cur].path
        switch k {
        case [27, 91, 65], [27, 79, 65], [107]: cur -= 1
        case [27, 91, 66], [27, 79, 66], [106]: cur += 1
        case [27, 91, 53, 126]: cur -= rows
        case [27, 91, 54, 126]: cur += rows
        case [27, 91, 72], [27, 79, 72], [27, 91, 49, 126], [103]: cur = 0
        case [27, 91, 70], [27, 79, 70], [27, 91, 52, 126], [71]: cur = items.count - 1
        case [32]:
            if sel.contains(path) { sel.remove(path) } else { sel.insert(path) }
            cur += 1
        case [97]:
            let safe = Set(items.filter { !$0.recent && $0.mtime != nil }.map(\.path))
            sel = sel.isEmpty ? safe : []
            if sel.isEmpty && safe.isEmpty { msg = ("All items are recent or unreadable — select them one by one", BAR_ASK) }
        case [65]:
            let g = groups(items)
            let group = Set(items.filter { g[$0.path] == g[path] }.map(\.path))
            if group.isSubset(of: sel) { sel.subtract(group) } else { sel.formUnion(group) }
        case [115]:
            byApp.toggle()
            items = sorted(items, byApp: byApp)
            cur = items.firstIndex { $0.path == path } ?? 0
        case [105]:
            do {
                try addIgnore(path)
                items.remove(at: cur)
                sel.remove(path)
                msg = ("Hidden for good: \(short(path)) — undo in \(tilde(IGNORE_FILE))", BAR_OK)
            } catch {
                msg = ("✗ Could not write \(tilde(IGNORE_FILE)): \(error.localizedDescription)", BAR_ERR)
            }
        case [111]: _ = run(["/usr/bin/open", "-R", path])
        case [100], [13], [10]:
            let targets = sel.isEmpty ? [path] : items.map(\.path).filter(sel.contains)
            let picked = items.filter { targets.contains($0.path) }
            let size = picked.contains { $0.size == nil } ? "?" : human(picked.reduce(Int64(0)) { $0 + ($1.size ?? 0) })
            func prompt(_ w: Int) -> String {
                let name = short(base(targets[0]))
                let room = w - 34 - width(size)
                return targets.count == 1 ? "Move \(width(name) > room ? fit(name, max(4, room)) : name) (\(size)) to Trash?"
                                          : "Move \(targets.count) items (\(size)) to Trash?"
            }
            guard waitKey({ h, w in ESC + "\(h);1H" + bar(prompt(w), [[("y", "yes"), ("n", "no")], []], BAR_ASK, w) }) == [121]
            else { break }
            var moved = Set<String>(), failed = 0
            for p in targets {
                guard let i = items.firstIndex(where: { $0.path == p }) else { continue }
                do {
                    try trash(p)
                    moved.insert(p)
                } catch {
                    items[i].error = (error as? Failure)?.message ?? "\(error)"
                    failed += 1
                }
            }
            let anchor = items[cur...].first { !moved.contains($0.path) } ?? items[..<cur].last { !moved.contains($0.path) }
            items.removeAll { moved.contains($0.path) }
            cur = anchor.flatMap { a in items.firstIndex { $0.path == a.path } } ?? 0
            sel.subtract(moved)
            msg = failed == 0
                ? ("✓ Moved \(moved.count) \(moved.count == 1 ? "item" : "items") to Trash", BAR_OK)
                : ("✗ Moved \(moved.count), failed \(failed) — see red items", BAR_ERR)
        default: break
        }
    }
}

#if SELFTEST
let idx = Index(
    ids: ["com.foo.bar", "dev.kdrag0n.MacVirt", "2BUA8C4S2C.com.agilebits", "uk.co.revolution.BS1R",
          "ru.kontur.updater", "com.raycast.macos", "com.google.android.studio", "EQHXZ8M8AV.group.com.google.x",
          "com.foo.bar.beta"],
    appNames: ["CleanShot X", "Microsoft Edge", "Code", "Telegram"],
    sysNames: ["codesign", "cupsd", "dash", "CloudDocs"],
    brands: ["Telegram"],
    teams: ["BJ4HAAB9B3", "EQHXZ8M8AV"],
    bundled: ["libGalaxy.dylib", "zPTApp.bundle"],
    zaps: [HOME + "/Library/Preferences/com.zapped.app.plist", HOME + "/Library/Caches/com.zapped.*"],
    apps: [LIB + "/Application Support/Steam/common/Game.app"])
precondition(key("243LU875E5.groups.com.apple.podcasts") == "com.apple.podcasts")
precondition(key("com.foo.bar.savedState") == "com.foo.bar")
precondition(key("default.store-wal") == "default.store")
precondition(vendor("uk.co.revolution.BS1R") == "uk.co.revolution")
precondition(vendor("kontur.plugin") == nil)
precondition(appKey("/x/com.docker.vmnetd.plist") == "docker" && appKey("/x/zoom.us") == "zoom")
precondition(appKey("/x/Microsoft Edge") == "microsoft" && appKey("/x/notion.id") == "notion")
precondition(idx.zapped(HOME + "/Library/Caches/com.zapped.helper") && !idx.zapped(HOME + "/Library/Caches/com.other"))
precondition(stem("Foo 1.2 beta") == "Foo 1" && stem(".hidden") == ".hidden")
EXCLUDED_ID = "com.foo.bar"
EXCLUDED_NAMES = ["cleanshotx"]
precondition(!idx.known("com.foo.bar.plist") && !idx.known("com.foo.bar.helper") && !idx.known("CleanShot X"))
precondition(idx.known("com.foo.other") && idx.known("com.foo.bar.beta.plist"))
(EXCLUDED_ID, EXCLUDED_NAMES) = (nil, [])
let g = groups([Item(path: "/x/Telegram", size: 1, mtime: nil, reason: ""),
                Item(path: "/x/ru.keepcoder.Telegram.plist", size: 1, mtime: nil, reason: ""),
                Item(path: "/x/com.docker.vmnetd", size: 1, mtime: nil, reason: "")])
precondition(g["/x/ru.keepcoder.Telegram.plist"] == "telegram" && g["/x/com.docker.vmnetd"] == "docker")
for name in ["com.foo.bar.plist", "com.foo.bar.helper", "com.foo", "com.foo.other",
             "2BUA8C4S2C.com.agilebits", "BJ4HAAB9B3.ZoomClient3rd", "CleanShot", "Microsoft Edge",
             "com.apple.anything", "1494A21C-7586-4A65-9BD9-1D18F9BB5A84", "Telegram Desktop",
             "Revolution Software", "Kontur.Assistant", "Kontur.Updater Admin", "claude-cli-nodejs",
             "default.store-shm", "com.segment.storage.abc.plist", "Code", "dash", "clouddocs",
             "com.google.keystone.agent.plist", "comet", "Avatar Cache Index.plist", "com.Breakpad.crash"] {
    precondition(idx.known(name), name)
}
for name in ["com.other.app", "Microsoft Edge Beta", "shadPS4", "XXXXXXXXXX.com.gone",
             "uk.co.othervendor.x", "com.raycast-x.macos", "Visual Studio Code", "Яндекс.Диск",
             "com.google.Chrome", "EQHXZ8M8AV.group.com.google.drivefs", "Dash", "com.microsoft.autoupdate2",
             "kotlin", "com.android.Emulator.plist"] {
    precondition(!idx.known(name), name)
}

precondition(env["CFFIXED_USER_HOME"] != nil, "run via make test: it needs a temporary home")
func file(_ p: String, _ plist: [String: Any] = [:]) {
    try! fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: URL(fileURLWithPath: p))
}
let AS = LIB + "/Application Support"
file(LIB + "/LaunchAgents/com.t.gone.plist", ["Program": "/nonexistent/agent"])
file(LIB + "/LaunchAgents/com.t.live.plist", ["Program": "/bin/ls"])
file(LIB + "/LaunchAgents/com.t.disk.plist", ["Program": "/Volumes/NoSuchDisk/agent"])
file(AS + "/Steam/common/Game.app/Contents/Info.plist")
file(AS + "/Google/Chrome/Default/Preferences")
file(AS + "/Google/DriveFS/state")
for n in ["com.gone.app", "com.hidden.app", "com.foo.bar"] { file(LIB + "/Caches/" + n + "/data") }
try! addIgnore(LIB + "/Caches/com.hidden.app")
var unreadable = 0
let found = Dictionary(candidates(idx, loadIgnored(), unreadable: &unreadable).map { ($0.path, $0.reason) }) { a, _ in a }
precondition(found[LIB + "/LaunchAgents/com.t.gone.plist"]?.hasPrefix("launchd job runs") == true)
precondition(found[AS + "/Google/Chrome"] == "Chrome is not installed")
precondition(found[LIB + "/Caches/com.gone.app"] != nil)
for p in ["/LaunchAgents/com.t.live.plist", "/LaunchAgents/com.t.disk.plist", "/Application Support/Steam",
          "/Application Support/Google/DriveFS", "/Caches/com.hidden.app", "/Caches/com.foo.bar"] {
    precondition(found[LIB + p] == nil, p)
}
print("ok")
#else
let USAGE = """
Usage: leftovers [--app NAME|PATH] [--list]

Find files left behind by uninstalled apps and move them to the Trash.

Options:
  --app NAME|PATH   uninstall an app: list the app together with its files
  --list            print path, size, date and reason instead of the interactive UI
                    (used automatically when stdin or stdout is not a terminal)
  -v, --version     print version
  -h, --help        show this help

Keys: ↑↓/jk move · space select · a all · A same app · s group by app · i ignore
      o reveal · d move to Trash · ? help · q quit

Ignored paths are kept in ~/.config/leftovers/ignore, one per line.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("leftovers: \(message)\nTry 'leftovers --help'.\n".utf8))
    exit(2)
}

if setlocale(LC_CTYPE, "") == nil || String(cString: nl_langinfo(CODESET)) != "UTF-8" { setlocale(LC_CTYPE, "en_US.UTF-8") }
var listMode = false, appQuery: String? = nil
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "-h", "--help": print(USAGE); exit(0)
    case "-v", "--version": print("leftovers \(VERSION)"); exit(0)
    case "--list": listMode = true
    case "--app":
        guard let q = args.popFirst() else { fail("--app needs an app name or path") }
        appQuery = q
    default: fail("unknown option '\(a)'")
    }
}
var app: String? = nil
if let q = appQuery {
    guard let p = findApp(q) else { fail("app '\(q)' not found in /Applications, ~/Applications or /opt") }
    app = p
}
let what = app.map { "Looking for files of \(stem(base($0)))…" } ?? "Scanning ~/Library and /Library…"
if listMode || isatty(0) == 0 || isatty(1) == 0 {
    FileHandle.standardError.write(Data((what + "\n").utf8))
    let result = app.map(appScan) ?? scan()
    for w in result.warnings { FileHandle.standardError.write(Data("warning: \(w)\n".utf8)) }
    for it in sorted(result.items, byApp: false) {
        print("\(it.path)\t\(human(it.size))\t\(date(it.mtime))\t\(it.reason)")
    }
} else {
    enterScreen(what)
    var scanned: (items: [Item], warnings: [String])? = nil
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        scanned = app.map(appScan) ?? scan()
        done.signal()
    }
    while gotSignal == 0 && done.wait(timeout: .now() + 0.1) == .timedOut {
        var byte: UInt8 = 0, p = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
        if poll(&p, 1, 0) > 0 && read(0, &byte, 1) == 1 && (byte == 3 || byte == 113) { gotSignal = SIGINT }
    }
    if gotSignal == 0, let r = scanned, !r.items.isEmpty { ui(r.items, notes: r.warnings, preselect: app != nil) }
    leaveScreen()
    if gotSignal != 0 {
        signal(gotSignal, SIG_DFL)
        raise(gotSignal)
    }
    if let r = scanned, r.items.isEmpty {
        print("No leftovers found.")
        for w in r.warnings { print("warning: \(w)") }
    }
}
#endif
