import Darwin
import Foundation

let fm = FileManager.default
let env = ProcessInfo.processInfo.environment
let HOME = env["SUDO_USER"].flatMap { NSHomeDirectoryForUser($0) } ?? NSHomeDirectory()
let LIB = HOME + "/Library"
let TRASH = HOME + "/.Trash"
let TEMPLATE = "/System/Library/Templates/Data"

let SCAN_DIRS = [
    "Application Support", "Application Scripts", "Caches", "Containers", "Group Containers",
    "Cookies", "HTTPStorages", "LaunchAgents", "Logs", "Preferences", "Preferences/ByHost",
    "Saved Application State", "WebKit",
].map { LIB + "/" + $0 } + [
    "Application Support", "Caches", "LaunchAgents", "LaunchDaemons", "Logs",
    "Preferences", "PrivilegedHelperTools",
].map { "/Library/" + $0 }
let SCAN_SET = Set(SCAN_DIRS)
let TOP_APP_DIRS = ["/Applications", HOME + "/Applications", "/opt", HOME + "/opt"]
let APP_DIRS = TOP_APP_DIRS + ["/System/Applications", "/System/Library/CoreServices", "/Library/Application Support"]
let SYSTEM_NAME_DIRS = ["/System/Library/Frameworks", "/System/Library/PrivateFrameworks", "/usr/libexec",
                        "/usr/sbin", "/System/Library/CoreServices", "/opt", HOME + "/opt"]
let LAUNCHD_DIRS = ["/System/Library/LaunchAgents", "/System/Library/LaunchDaemons", "/Library/LaunchAgents",
                    "/Library/LaunchDaemons", LIB + "/LaunchAgents"]
let GENERIC_VENDORS: Set = ["com.github", "io.github", "com.electron", "org.chromium", "com.google.code", "com.apple",
                            "com.todesktop", "org.apache", "is.workflow"]
let SHARED_VENDORS: Set = ["com.google", "com.microsoft", "com.adobe"]
let UPDATERS = ["com.google.keystone", "com.google.softwareupdate", "com.microsoft.autoupdate"]
let CCTLD_SLD: Set = ["co", "com", "org", "net", "ac", "ne", "or", "gov", "edu"]
let IGNORE_PREFIXES = [
    "com.apple.", "apple", "is.workflow.", "tvappservices", "default.store",
    "com.segment.", "com.launchdarkly.", "com.telemetrydeck.", "io.sentry", "io.branch", "com.datadoghq",
    "org.sparkle-project.", "com.crashlytics", "com.qtproject", "com.plausiblelabs.", "com.bugsnag.", "com.hackemist.",
    "com.onevcat.", "com.microsoft.appcenter",
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
    "sentrycrash", "kscrash", "jna", "cef", "googleheartbeatstorage", "windowserver",
]
let UUID_RE = "^([0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}|[0-9a-f]{32})$"
let ID_RE = "^[a-z0-9-]+(\\.[a-z0-9_-]+)+$"

func sub(_ s: String, _ re: String, _ with: String = "") -> String {
    s.replacingOccurrences(of: re, with: with, options: .regularExpression)
}

func matches(_ s: String, _ re: String) -> Bool { s.range(of: re, options: .regularExpression) != nil }

func ls(_ d: String) -> [String] { (try? fm.contentsOfDirectory(atPath: d)) ?? [] }

func stem(_ n: String) -> String {
    guard let i = n.lastIndex(of: "."), i != n.startIndex, n.index(after: i) != n.endIndex else { return n }
    return String(n[..<i])
}

func lstatMode(_ p: String) -> mode_t? {
    var st = stat()
    return lstat(p, &st) == 0 ? st.st_mode & S_IFMT : nil
}

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

func hasPrefix(_ sorted: [String], _ prefix: String) -> Bool {
    var lo = 0, hi = sorted.count
    while lo < hi {
        let m = (lo + hi) / 2
        if sorted[m] < prefix { lo = m + 1 } else { hi = m }
    }
    return lo < sorted.count && sorted[lo].hasPrefix(prefix)
}

struct Index {
    let teams, idset, vendors, names, cli, brands: Set<String>
    let ids, appNames: [String]

    init(ids: Set<String>, appNames: Set<String>, sysNames: Set<String> = [], brands: Set<String> = [],
         teams: Set<String> = []) {
        self.teams = teams
        idset = Set(ids.map(key))
        self.ids = idset.sorted()
        vendors = Set(idset.compactMap(vendor)).subtracting(GENERIC_VENDORS)
        self.appNames = Set(appNames.map(norm)).subtracting([""]).sorted()
        names = Set(self.appNames).union(sysNames.filter { $0 != $0.lowercased() || $0 == $0.uppercased() }.map(norm))
        cli = sysNames.filter { $0 == $0.lowercased() && $0 != $0.uppercased() }
        let vendorNames = vendors.map { norm(split($0).last!) }
        self.brands = Set(brands.map(norm) + vendorNames).filter { $0.count >= 4 }
    }

    func known(_ name: String) -> Bool {
        let k = key(name)
        if teams.contains(String(name.prefix(10))) && name.dropFirst(10).first == "." && !matches(k, ID_RE) {
            return true
        }
        let n = norm(k)
        if n.isEmpty || IGNORE_PREFIXES.contains(where: k.hasPrefix) || k.hasSuffix(".nodejs")
            || matches(k, UUID_RE) || IGNORE.contains(n) {
            return true
        }
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

func signature(_ app: String) -> (team: String?, groups: [String]) {
    let r = run(["/usr/bin/codesign", "-dv", "--entitlements", "-", "--xml", app])
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

func missing(_ path: String) -> Bool {
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
    var r = [app + "/Contents/Info.plist"]
    for a in ls(app + "/Contents") {
        for b in ls(app + "/Contents/" + a) {
            let pb = app + "/Contents/" + a + "/" + b
            r += ([pb] + ls(pb).map { pb + "/" + $0 }).map { $0 + "/Contents/Info.plist" }.filter { fm.fileExists(atPath: $0) }
        }
    }
    return r
}

func buildIndex() -> Index {
    var ids = Set<String>(), appNames = Set<String>(), sysNames = Set<String>(), brands = Set<String>(),
        teams = Set<String>()
    let found = String(decoding: run(["/usr/bin/mdfind", "kMDItemContentType == 'com.apple.application-bundle'"]).out,
                       as: UTF8.self).split(separator: "\n").map(String.init)
    let top = globbedApps(TOP_APP_DIRS)
    let apps = Set(found.filter { !$0.contains("/CoreSimulator/") }).union(top).union(globbedApps(APP_DIRS))
    let inLib = apps.filter { $0.hasPrefix(LIB + "/") }

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
            for (i, plist) in nestedPlists(app).enumerated() {
                let info = loadPlist(plist)
                let bid = info["CFBundleIdentifier"] as? String
                if let bid = bid, !bid.hasSuffix(".resources") { ids.insert(bid) }
                guard i == 0 else { continue }
                let names = Set([stem((app as NSString).lastPathComponent)]
                    + ["CFBundleName", "CFBundleDisplayName"].compactMap { info[$0] as? String })
                if app.hasPrefix("/System/") { sysNames.formUnion(names) } else { appNames.formUnion(names) }
                if top.contains(app) && !(bid ?? "").hasPrefix("com.apple.") { brands.formUnion(names) }
            }
        }
    }

    addApps(apps.subtracting(inLib))
    for d in (env["PATH"] ?? "").split(separator: ":").map(String.init) + SYSTEM_NAME_DIRS {
        sysNames.formUnion(ls(d).filter { fm.fileExists(atPath: d + "/" + $0) }.map(stem))
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
                if let t = target { sysNames.insert((t as NSString).lastPathComponent) }
            }
        }
    }
    let idx = Index(ids: ids, appNames: appNames, sysNames: sysNames, brands: brands, teams: teams)
    addApps(inLib.filter { app in
        let parts = String(app.dropFirst(LIB.count + 1)).split(separator: "/").map(String.init)
        return idx.known(parts.count > 1 ? parts[1] : "")
    })
    return Index(ids: ids, appNames: appNames, sysNames: sysNames, brands: brands, teams: teams)
}

@discardableResult
func walk(_ dir: String, _ visit: (String) -> Bool) -> Bool {
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
            if !walk(path, visit) { return false }
        } else if !(type == DT_LNK && stat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR), !visit(path) {
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
    let onlyHosts = walk(p) { f in
        if (f as NSString).lastPathComponent.hasPrefix(".") { return true }
        any = true
        return f.contains("/NativeMessagingHosts/")
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
    walk(p) { f in
        var s = stat()
        if lstat(f, &s) == 0 {
            size += Int64(s.st_blocks) * 512
            mtime = max(mtime, Double(s.st_mtimespec.tv_sec))
        }
        return true
    }
    return (size, mtime)
}

func isLeftover(_ idx: Index, _ d: String, _ name: String) -> Bool {
    let p = d + "/" + name
    if name.hasPrefix(".") || SCAN_SET.contains(p) || lstatMode(TEMPLATE + p) != nil { return false }
    let target = d.hasSuffix("/LaunchAgents") || d.hasSuffix("/LaunchDaemons") ? launchdTarget(p) : nil
    if let t = target, missing(t) { return true }
    if let t = target, !foreignTarget(t) { return false }
    return !idx.known(name) && !foreignOnly(p)
}

struct Item { let path: String; let size: Int64?; let mtime: Double? }

func scan() -> [Item] {
    let idx = buildIndex()
    var found = [Item]()
    for d in SCAN_DIRS where lstatMode(d) == S_IFDIR {
        for n in ls(d) where isLeftover(idx, d, n) {
            let s = treeStats(d + "/" + n)
            found.append(Item(path: d + "/" + n, size: s.size, mtime: s.mtime))
        }
    }
    return found.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
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
    let s = path.hasPrefix(HOME + "/") ? "~" + path.dropFirst(HOME.count) : path
    return String(String.UnicodeScalarView(s.unicodeScalars.map { $0.value < 32 || (0x7f...0x9f).contains($0.value) ? "?" : $0 }))
}

struct Failure: Error { let message: String }

func trash(_ path: String) throws {
    guard lstatMode(TRASH) == S_IFDIR else { throw Failure(message: "\(short(TRASH)) is not a Trash folder") }
    let name = (path as NSString).lastPathComponent
    var dest = TRASH + "/" + name, n = 1
    while lstatMode(dest) != nil {
        dest = TRASH + "/\(name) \(n)"
        n += 1
    }
    if renamex_np(path, dest, UInt32(RENAME_EXCL)) != 0 { throw Failure(message: String(cString: strerror(errno))) }
}

let ESC = "\u{1b}["
let RESET = ESC + "0m", BOLD = ESC + "1m", DIM = ESC + "2m", GREEN = ESC + "32m"
let BAR = ESC + "44;97m", BAR_OK = ESC + "42;30m", BAR_ERR = ESC + "41;97m", BAR_ASK = ESC + "43;30m"
let HINTS = [("space", "select"), ("a", "all"), ("o", "reveal"), ("d", "trash"), ("q", "quit")]
let SHORT_HINTS = [("space", "select"), ("d", "trash"), ("q", "quit")]

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
    return n >= 1 << 30 ? ESC + "1;31m" : n >= 100 << 20 ? ESC + "33m" : n >= 1 << 20 ? "" : DIM
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
        let check = selected ? "[x] " : "[ ] ", path = fit(short(it.path), pathW, tail: true)
        let size = showSize ? "  " + String(repeating: " ", count: max(0, 8 - width(human(it.size)))) + human(it.size) : ""
        let day = showDate ? "  " + fit(date(it.mtime), 10) : ""
        if current { return ESC + "1;7m" + fit(check + path + size + day + " ", w) + RESET }
        let cut = path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex
        return (selected ? GREEN : DIM) + check + RESET + DIM + path[..<cut] + RESET + (selected ? GREEN : "")
            + path[cut...] + RESET + sizeColor(it.size) + size + RESET + DIM + day + " " + RESET
    }
}

var gotSignal: Int32 = 0
var savedTermios = termios()

func out(_ s: String) { FileHandle.standardOutput.write(s.data(using: .utf8)!) }

func termSize() -> (h: Int, w: Int) {
    var ws = winsize()
    return ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0 ? (Int(ws.ws_row), Int(ws.ws_col)) : (24, 80)
}

func enterScreen() {
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
    let text = "Scanning ~/Library and /Library…"
    out(ESC + "?1049h" + ESC + "?25l" + ESC + "?7l" + ESC + "2J" + ESC + "\(h / 2);\(max(1, (w - width(text)) / 2))H" + DIM + text + RESET)
}

func leaveScreen() {
    out(RESET + ESC + "?7h" + ESC + "?25h" + ESC + "?1049l")
    tcsetattr(0, TCSAFLUSH, &savedTermios)
}

func ui(_ initial: [Item]) {
    var items = initial, sel = Set<String>(), cur = 0, top = 0
    var msg: (text: String, style: String)? = nil
    var pending = [UInt8]()
    func readKey() -> [UInt8] {
        if pending.isEmpty {
            var p = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 100) > 0 else { return [] }
            var buf = [UInt8](repeating: 0, count: 64)
            let n = read(0, &buf, 64)
            guard n > 0 else {
                gotSignal = SIGHUP
                return []
            }
            pending = Array(buf[..<n])
        }
        var len = 1
        if pending[0] == 27, pending.count > 2, pending[1] == 91 || pending[1] == 79 {
            len = 2
            while len < pending.count && !(64...126).contains(pending[len]) { len += 1 }
            len = min(len + 1, pending.count)
        }
        defer { pending.removeFirst(len) }
        return Array(pending[..<len])
    }
    func confirm(_ prompt: String) -> Bool {
        pending = []
        var shown = (h: 0, w: 0)
        while gotSignal == 0 {
            let sz = termSize()
            if sz != shown {
                out(ESC + "\(sz.h);1H" + bar(prompt, [[("y", "yes"), ("n", "no")], []], BAR_ASK, sz.w))
                shown = sz
            }
            let k = readKey()
            if !k.isEmpty { return k == [121] }
        }
        return false
    }
    var last = (h: 0, w: 0), dirty = true
    while true {
        let (h, w) = termSize()
        let rows = max(1, h - 2), layout = Layout(w)
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
            let status = sel.isEmpty
                ? "\(items.count) leftovers · \(human(items.reduce(Int64(0)) { $0 + ($1.size ?? 0) }))"
                : "\(sel.count) of \(items.count) selected · \(human(total))"
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
        msg = nil
        if k == [113] || k == [3] { return }
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
        case [97]: sel = sel.count == items.count ? [] : Set(items.map(\.path))
        case [111]: _ = run(["/usr/bin/open", "-R", path])
        case [100], [13], [10]:
            guard !sel.isEmpty else { break }
            let noun = sel.count == 1 ? "item" : "items"
            guard confirm("Move \(sel.count) \(noun) (\(human(total))) to Trash?") else { break }
            var ok = Set<String>(), errors = [String]()
            for p in sel.sorted() {
                do {
                    try trash(p)
                    ok.insert(p)
                } catch {
                    errors.append("\((error as? Failure)?.message ?? "\(error)") — \(short(p))")
                }
            }
            items.removeAll { ok.contains($0.path) }
            sel.subtract(ok)
            msg = errors.isEmpty
                ? ("✓ Moved \(ok.count) \(ok.count == 1 ? "item" : "items") to Trash", BAR_OK)
                : ("✗ Moved \(ok.count), failed \(errors.count): \(errors[0])", BAR_ERR)
        default: break
        }
    }
}

#if SELFTEST
let idx = Index(
    ids: ["com.foo.bar", "dev.kdrag0n.MacVirt", "2BUA8C4S2C.com.agilebits", "uk.co.revolution.BS1R",
          "ru.kontur.updater", "com.raycast.macos", "com.google.android.studio", "EQHXZ8M8AV.group.com.google.x"],
    appNames: ["CleanShot X", "Microsoft Edge", "Code", "Telegram"],
    sysNames: ["codesign", "cupsd", "dash", "CloudDocs"],
    brands: ["Telegram"],
    teams: ["BJ4HAAB9B3", "EQHXZ8M8AV"])
precondition(key("243LU875E5.groups.com.apple.podcasts") == "com.apple.podcasts")
precondition(key("com.foo.bar.savedState") == "com.foo.bar")
precondition(key("default.store-wal") == "default.store")
precondition(vendor("uk.co.revolution.BS1R") == "uk.co.revolution")
precondition(vendor("kontur.plugin") == nil)
for name in ["com.foo.bar.plist", "com.foo.bar.helper", "com.foo", "com.foo.other",
             "2BUA8C4S2C.com.agilebits", "BJ4HAAB9B3.ZoomClient3rd", "CleanShot", "Microsoft Edge",
             "com.apple.anything", "1494A21C-7586-4A65-9BD9-1D18F9BB5A84", "Telegram Desktop",
             "Revolution Software", "Kontur.Assistant", "Kontur.Updater Admin", "claude-cli-nodejs",
             "default.store-shm", "com.segment.storage.abc.plist", "Code", "dash", "clouddocs",
             "com.google.keystone.agent.plist"] {
    precondition(idx.known(name), name)
}
for name in ["com.other.app", "Microsoft Edge Beta", "shadPS4", "XXXXXXXXXX.com.gone",
             "uk.co.othervendor.x", "com.raycast-x.macos", "Visual Studio Code", "Яндекс.Диск",
             "com.google.Chrome", "EQHXZ8M8AV.group.com.google.drivefs", "Dash", "com.microsoft.autoupdate2"] {
    precondition(!idx.known(name), name)
}
print("ok")
#else
setlocale(LC_CTYPE, "")
if CommandLine.arguments.contains("--list") || isatty(0) == 0 || isatty(1) == 0 {
    FileHandle.standardError.write("Scanning…\n".data(using: .utf8)!)
    for it in scan() { print("\(it.path)\t\(human(it.size))\t\(date(it.mtime))") }
} else {
    enterScreen()
    let items = scan()
    if !items.isEmpty && gotSignal == 0 { ui(items) }
    leaveScreen()
    if gotSignal != 0 {
        signal(gotSignal, SIG_DFL)
        raise(gotSignal)
    }
    if items.isEmpty { print("No leftovers found.") }
}
#endif
