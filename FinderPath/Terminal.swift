import Cocoa

enum Terminal {
    /// Opens a terminal window in `path`, or in its enclosing folder when `path` is a file.
    /// Uses the terminal chosen in Settings, falling back to Terminal if it's no longer installed.
    @discardableResult
    static func open(at path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        let folder = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent

        let workspace = NSWorkspace.shared
        let preferred = SharedSettings.defaults.string(forKey: SharedSettings.Key.terminalApp) ?? ""
        guard let terminal = workspace.urlForApplication(withBundleIdentifier: preferred)
                ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return false }
        // Terminal (and iTerm2) open a new window at a folder handed to them this way.
        workspace.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: terminal,
                       configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}
