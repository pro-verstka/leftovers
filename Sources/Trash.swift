import Foundation

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
