import Foundation

/// Settings shared by the app and the Finder extension through their app group.
enum SharedSettings {
    static let suiteName = "group.com.aredah.FinderPath"
    static let defaults = UserDefaults(suiteName: suiteName) ?? .standard

    enum Key {
        static let returnOpensFiles = "ReturnOpensFiles"
        static let cmdOpensTerminal = "CmdOpensTerminal"
        static let toolbarHeight = "ToolbarHeight"
        static let showNewMenu = "ShowNewTextFile"
        static let newFileTemplates = "NewFileTemplates"
        static let renameAfterCreating = "RenameAfterCreating"
        static let showOpenTerminal = "ShowOpenTerminal"
        static let showCopyPath = "ShowCopyPath"
        static let terminalApp = "TerminalApp"
        /// Earlier single text-file name; only read to migrate it into `newFileTemplates`.
        static let legacyNewFileName = "NewFileName"
    }

    static let defaultToolbarHeight = 52.0
    static let defaultTerminalApp = "com.apple.Terminal"

    static func register() {
        defaults.register(defaults: [
            Key.returnOpensFiles: true,
            Key.cmdOpensTerminal: true,
            Key.toolbarHeight: defaultToolbarHeight,
            Key.showNewMenu: true,
            Key.renameAfterCreating: true,
            Key.showOpenTerminal: true,
            Key.showCopyPath: true,
            Key.terminalApp: defaultTerminalApp,
        ])
    }

    /// Entries of the right-click New submenu, in menu order.
    static var newFileTemplates: [NewFileTemplate] {
        get {
            guard let data = defaults.data(forKey: Key.newFileTemplates),
                  let templates = try? JSONDecoder().decode([NewFileTemplate].self, from: data)
            else { return [.textFile] }
            return templates
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.newFileTemplates)
        }
    }
}

/// One entry of the right-click New submenu.
struct NewFileTemplate: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    /// Shown in the menu, e.g. "Markdown File".
    var title: String
    /// Name of the created file, numbered if taken, e.g. "New Document.md".
    var fileName: String
    /// Initial text; unused when `templateFile` is set.
    var contents = ""
    /// A file copied to create the new one, for formats that can't start empty (Word, Pages…).
    var templateFile: String?

    /// The built-in default. Its fixed id keeps menu clicks working before anything is saved.
    static let textFile = NewFileTemplate(id: "text-file", title: "Text File", fileName: "New Text File.txt")
}
