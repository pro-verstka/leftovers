import Foundation

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
