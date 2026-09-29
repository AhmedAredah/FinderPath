import Cocoa

enum NewFile {
    /// Creates a file from the New menu entry with id `templateID` in `folder` (numbered if the
    /// name is taken), selects it in the front Finder window and, like Windows, starts renaming it.
    static func create(template templateID: String?, in folder: String) {
        let templates = SharedSettings.newFileTemplates
        guard let template = templates.first(where: { $0.id == templateID }) ?? templates.first else { return }

        let fileManager = FileManager.default
        let (base, ext) = split(template.fileName)
        var path = (folder as NSString).appendingPathComponent(base + ext)
        var number = 2
        while fileManager.fileExists(atPath: path) {
            path = (folder as NSString).appendingPathComponent("\(base) \(number)\(ext)")
            number += 1
        }

        do {
            if let source = template.templateFile {
                try fileManager.copyItem(atPath: source, toPath: path)
            } else {
                try Data(template.contents.utf8).write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
                // Scripts that start with a shebang are made runnable.
                if template.contents.hasPrefix("#!") {
                    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                }
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not create “\((path as NSString).lastPathComponent)”"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }

        // Give Finder a moment to notice the new file before selecting it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard (try? Finder.select(path)) == true,
                  SharedSettings.defaults.bool(forKey: SharedSettings.Key.renameAfterCreating) else { return }
            startRenaming()
        }
    }

    /// Splits a file name into base and ".ext", making it safe to use as a single path component.
    private static func split(_ fileName: String) -> (base: String, ext: String) {
        var name = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { name = "Untitled" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? (name, "") : ((name as NSString).deletingPathExtension, "." + ext)
    }

    // MARK: Template files

    /// Copies of chosen template files live here, so moving or deleting the original is harmless.
    private static var templatesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinderPath/Templates", isDirectory: true)
    }

    /// Stores a copy of `source` for the entry `id`, replacing any earlier one, and returns its path.
    static func storeTemplateFile(_ source: URL, for id: String) throws -> String {
        removeTemplateFile(for: id)
        let folder = templatesDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy.path
    }

    static func removeTemplateFile(for id: String) {
        try? FileManager.default.removeItem(at: templatesDirectory.appendingPathComponent(id, isDirectory: true))
    }

    /// Presses Return in Finder, which edits the selected item's name. Posting key events needs
    /// Accessibility permission; macOS is asked for it once, and without it the file stays selected.
    private static func startRenaming() {
        let askedKey = "AskedForAccessibility"
        let prompt = !UserDefaults.standard.bool(forKey: askedKey)
        UserDefaults.standard.set(true, forKey: askedKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options),
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return }

        for keyDown in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: keyDown)?.postToPid(finder.processIdentifier)
        }
    }
}
