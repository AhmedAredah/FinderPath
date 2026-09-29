import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pathBar = PathBarController()
    private var launchedFromURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        SharedSettings.register()
        Self.migrateOldSettings()

        // The Finder extension opens finderpath://show when its toolbar button is clicked.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory apps show no menu bar, but its key equivalents still drive ⌘X/⌘C/⌘V/⌘A.
        NSApp.mainMenu = makeMainMenu()

        // Opened directly (Finder, Launchpad, Spotlight) rather than by the extension: the welcome
        // guide the first time, or while the app still needs moving to Applications; else Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.launchedFromURL else { return }
            if !WelcomeWindowController.hasBeenShown || !Installation.isInApplicationsFolder {
                WelcomeWindowController.shared.show()
            } else {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        launchedFromURL = true
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let components = URLComponents(string: text) else { return }
        let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        switch components.host {
        case "show":
            pathBar.show()
        case "settings":
            SettingsWindowController.shared.show()
        case "terminal":
            if let path { Terminal.open(at: path) }
        case "new-file":
            let template = components.queryItems?.first(where: { $0.name == "template" })?.value
            if let path { NewFile.create(template: template, in: path) }
        default:
            break
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    /// Earlier versions kept some settings in the app's own defaults (set with `defaults write`)
    /// and had a single, renamable text file under New.
    private static func migrateOldSettings() {
        let shared = SharedSettings.defaults
        if shared.object(forKey: SharedSettings.Key.newFileTemplates) == nil,
           let name = shared.string(forKey: SharedSettings.Key.legacyNewFileName), !name.isEmpty {
            var template = NewFileTemplate.textFile
            template.fileName = (name as NSString).pathExtension.isEmpty ? name + ".txt" : name
            SharedSettings.newFileTemplates = [template]
        }
        shared.removeObject(forKey: SharedSettings.Key.legacyNewFileName)

        for key in [SharedSettings.Key.toolbarHeight, SharedSettings.Key.terminalApp] {
            guard let value = UserDefaults.standard.object(forKey: key) else { continue }
            if SharedSettings.defaults.persistentDomain(forName: SharedSettings.suiteName)?[key] == nil {
                SharedSettings.defaults.set(value, forKey: key)
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeMainMenu() -> NSMenu {
        let app = NSMenu(title: "FinderPath")
        app.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit FinderPath", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        for submenu in [app, file, edit] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}
