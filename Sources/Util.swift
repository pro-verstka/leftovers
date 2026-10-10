import Foundation

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
