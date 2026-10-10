import Foundation

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
