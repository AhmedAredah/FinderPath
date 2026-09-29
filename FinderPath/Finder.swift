import Cocoa

/// A Finder browser window (or tab) as reported by AppleScript.
struct FinderWindow {
    let id: Int
    /// Window frame in global coordinates with a top-left origin (AppleScript's convention).
    let bounds: CGRect
    /// POSIX path of the folder shown; nil for places like Recents or Network.
    let path: String?
    /// Width of the sidebar on the window's left; 0 when it's hidden.
    let sidebarWidth: CGFloat
}

enum FinderError: Error {
    case notAuthorized
    case script(String)

    var message: String {
        switch self {
        case .notAuthorized:
            return "Allow control of Finder in System Settings › Privacy & Security › Automation"
        case .script(let text):
            return text
        }
    }
}

/// Talks to Finder over Apple Events.
enum Finder {
    static func frontWindow() throws -> FinderWindow? {
        let result = try run("""
        tell application "Finder"
            if (count of Finder windows) is 0 then return {}
            set w to front Finder window
            set p to ""
            try
                set p to POSIX path of (target of w as alias)
            end try
            set sw to 0
            try
                set sw to sidebar width of w
            end try
            return {id of w, bounds of w, p, sw}
        end tell
        """)
        guard result.numberOfItems == 4,
              let id = result.atIndex(1)?.int32Value,
              let bounds = result.atIndex(2), bounds.numberOfItems == 4 else { return nil }
        let edge = { (i: Int) in CGFloat(bounds.atIndex(i)?.int32Value ?? 0) }
        let path = result.atIndex(3)?.stringValue ?? ""
        return FinderWindow(
            id: Int(id),
            bounds: CGRect(x: edge(1), y: edge(2), width: edge(3) - edge(1), height: edge(4) - edge(2)),
            path: path.isEmpty ? nil : path,
            sidebarWidth: CGFloat(result.atIndex(4)?.int32Value ?? 0)
        )
    }

    /// Shows `folder` in the window/tab with `windowID` (falling back to the front window, or a new
    /// one), then selects `item` in it if given.
    static func open(folder: String, selecting item: String?, inWindow windowID: Int?) throws {
        let window = windowID.map { "Finder window id \($0)" } ?? "front Finder window"
        let select = item.map { "select (POSIX file \(quoted($0)) as alias)" } ?? ""
        try run("""
        tell application "Finder"
            if exists \(window) then
                set w to \(window)
            else
                set w to make new Finder window
            end if
            set target of w to (POSIX file \(quoted(folder)) as alias)
            set index of w to 1
            activate
            \(select)
        end tell
        """)
    }

    /// Selects the item at `path` if the front Finder window shows its folder. Returns whether it did.
    static func select(_ path: String) throws -> Bool {
        try run("""
        tell application "Finder"
            if (count of Finder windows) is 0 then return false
            set f to (POSIX file \(quoted(path)) as alias)
            set shown to POSIX path of (target of front Finder window as alias)
            if shown is not POSIX path of (container of f as alias) then return false
            activate
            select f
            return true
        end tell
        """).booleanValue
    }

    static func activate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    }

    @discardableResult
    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            if error?[NSAppleScript.errorNumber] as? Int == -1743 { throw FinderError.notAuthorized }
            throw FinderError.script(error?[NSAppleScript.errorMessage] as? String ?? "Finder did not respond")
        }
        return result
    }

    private static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
