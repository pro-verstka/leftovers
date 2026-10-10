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
