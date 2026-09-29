import Cocoa
import FinderSync
import UniformTypeIdentifiers

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        SharedSettings.register()
        // Watch the whole filesystem so the toolbar button works in every location.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String { "Go to Path" }
    override var toolbarItemToolTip: String { "Type or paste a path to open in this window" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Go to Path")
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .toolbarItemMenu:
            // Open the path bar straight from the click instead of showing a one-item menu.
            // The host app is not sandboxed, so it can script Finder and see the real home folder.
            NSWorkspace.shared.open(URL(string: "finderpath://show")!)
            return NSMenu()
        case .contextualMenuForContainer:
            return emptyAreaMenu()
        case .contextualMenuForItems:
            return itemsMenu()
        default:
            return nil
        }
    }

    /// The menu for right-clicking a folder's empty area, like Windows' background menu. Items are
    /// shown or hidden in FinderPath's Settings.
    private func emptyAreaMenu() -> NSMenu? {
        let settings = SharedSettings.defaults
        let menu = NSMenu(title: "")

        let templates = SharedSettings.newFileTemplates
        if settings.bool(forKey: SharedSettings.Key.showNewMenu) && !templates.isEmpty {
            let newMenu = NSMenu(title: "New")
            for (index, template) in templates.enumerated() {
                // Finder keeps a menu item's tag but not its representedObject, so tag with the index.
                let item = NSMenuItem(title: template.title, action: #selector(newFile(_:)), keyEquivalent: "")
                item.image = Self.icon(forFileNamed: template.fileName)
                item.tag = index
                newMenu.addItem(item)
            }
            let newItem = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
            newItem.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: nil)
            newItem.submenu = newMenu
            menu.addItem(newItem)
        }

        if settings.bool(forKey: SharedSettings.Key.showOpenTerminal) {
            let item = NSMenuItem(title: "Open Terminal Here", action: #selector(openTerminal(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            menu.addItem(item)
        }

        return menu.items.isEmpty ? nil : menu
    }

    /// The menu for right-clicking files and folders. Open Terminal Here is left out: macOS already
    /// offers "New Terminal at Folder" there.
    private func itemsMenu() -> NSMenu? {
        guard SharedSettings.defaults.bool(forKey: SharedSettings.Key.showCopyPath) else { return nil }
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "Copy Path", action: #selector(copyPath(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(item)
        return menu
    }

    /// Copies the full path of each selected item, one per line.
    @objc private func copyPath(_ sender: NSMenuItem) {
        let controller = FIFinderSyncController.default()
        let urls = controller.selectedItemURLs() ?? controller.targetedURL().map { [$0] } ?? []
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let folder = FIFinderSyncController.default().targetedURL()?.path else { return }
        openHostApp("terminal", path: folder)
    }

    @objc private func newFile(_ sender: NSMenuItem) {
        let templates = SharedSettings.newFileTemplates
        guard templates.indices.contains(sender.tag),
              let folder = FIFinderSyncController.default().targetedURL()?.path else { return }
        // The sandboxed extension cannot write to the folder; the host app creates the file.
        openHostApp("new-file", path: folder, extra: [URLQueryItem(name: "template", value: templates[sender.tag].id)])
    }

    private func openHostApp(_ action: String, path: String, extra: [URLQueryItem] = []) {
        var components = URLComponents()
        components.scheme = "finderpath"
        components.host = action
        components.queryItems = [URLQueryItem(name: "path", value: path)] + extra
        if let link = components.url { NSWorkspace.shared.open(link) }
    }

    private static func icon(forFileNamed name: String) -> NSImage {
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
