import Foundation

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
