import Foundation

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
