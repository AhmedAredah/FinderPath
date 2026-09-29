import Cocoa
import FinderSync
import SwiftUI
import UniformTypeIdentifiers

/// Owns the Settings window.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "FinderPath Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 640))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }()

    func show() {
        AppPresence.windowWillShow()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppPresence.windowWillClose(window)
    }
}

private typealias Key = SharedSettings.Key

struct SettingsView: View {
    @AppStorage(Key.returnOpensFiles, store: SharedSettings.defaults) private var returnOpensFiles = true
    @AppStorage(Key.cmdOpensTerminal, store: SharedSettings.defaults) private var cmdOpensTerminal = true
    @AppStorage(Key.toolbarHeight, store: SharedSettings.defaults)
    private var toolbarHeight = SharedSettings.defaultToolbarHeight
    @AppStorage(Key.showNewMenu, store: SharedSettings.defaults) private var showNewMenu = true
    @AppStorage(Key.renameAfterCreating, store: SharedSettings.defaults) private var renameAfterCreating = true
    @AppStorage(Key.showOpenTerminal, store: SharedSettings.defaults) private var showOpenTerminal = true
    @AppStorage(Key.showCopyPath, store: SharedSettings.defaults) private var showCopyPath = true
    @AppStorage(Key.terminalApp, store: SharedSettings.defaults)
    private var terminalApp = SharedSettings.defaultTerminalApp

    @State private var permissions = Permissions.current()
    @State private var templates = SharedSettings.newFileTemplates

    var body: some View {
        Form {
            Section {
                statusRow("Finder extension", granted: permissions.extensionEnabled,
                          detail: "Adds the toolbar button and right-click items.", action: "Manage…") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
                statusRow("Control of Finder", granted: permissions.automation,
                          detail: "Needed to read and change the folder a Finder window shows.", action: "Open…") {
                    Permissions.openPrivacyPane("Privacy_Automation")
                }
                statusRow("Accessibility", granted: permissions.accessibility,
                          detail: "Optional. Starts renaming a newly created file.", action: "Open…") {
                    Permissions.openPrivacyPane("Privacy_Accessibility")
                }
                HStack {
                    Spacer()
                    Button("Show Welcome Guide…") { WelcomeWindowController.shared.show() }
                }
            } header: {
                Text("General")
            }

            Section {
                Picker("Return on a file or app", selection: $returnOpensFiles) {
                    Text("Opens it").tag(true)
                    Text("Shows it in its folder").tag(false)
                }
                Toggle("Typing “cmd” opens Terminal here", isOn: $cmdOpensTerminal)
                LabeledContent("Distance from window top") {
                    Stepper(value: $toolbarHeight, in: 20...200, step: 2) {
                        Text("\(Int(toolbarHeight)) pt").monospacedDigit()
                    }
                }
            } header: {
                Text("Path Bar")
            } footer: {
                Text("⌘Return does the opposite. Folders always open in the same window. Raise the distance if the bar covers your toolbar or tab bar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show New submenu", isOn: $showNewMenu)
                Toggle("Start renaming new files", isOn: $renameAfterCreating)
                    .disabled(!showNewMenu)
                Toggle("Show Open Terminal Here", isOn: $showOpenTerminal)
                Toggle("Show Copy Path on files and folders", isOn: $showCopyPath)
            } header: {
                Text("Right-Click Menu")
            } footer: {
                Text("New and Open Terminal Here appear when you right-click an empty area of a folder.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($templates) { $template in
                    TemplateRow(template: $template,
                                canMoveUp: template.id != templates.first?.id,
                                canMoveDown: template.id != templates.last?.id,
                                move: { offset in move(template, by: offset) },
                                remove: { remove(template) })
                }
                HStack {
                    Spacer()
                    Menu("Add File Type") {
                        ForEach(NewFilePreset.all, id: \.title) { preset in
                            Button(preset.title) { templates.append(preset.template()) }
                        }
                        Divider()
                        Button("From a Template File…") { addFromTemplateFile() }
                    }
                    .fixedSize()
                }
            } header: {
                Text("New Menu")
            } footer: {
                Text("Shown when you right-click an empty area of a folder. For Word, Excel, Pages or Numbers, save a blank document once and add it with “From a Template File…”; each new file is a copy of it.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!showNewMenu)

            Section {
                Picker("Open folders in", selection: $terminalApp) {
                    ForEach(TerminalApp.choices(including: terminalApp)) { app in
                        Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                            .tag(app.bundleID)
                    }
                }
                HStack {
                    Spacer()
                    Button("Choose Another App…") {
                        if let bundleID = TerminalApp.chooseApp() { terminalApp = bundleID }
                    }
                }
            } header: {
                Text("Terminal")
            } footer: {
                Text("Used by Open Terminal Here and by typing “cmd” in the path bar.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions = Permissions.current()
        }
        .onChange(of: templates) { SharedSettings.newFileTemplates = templates }
    }

    private func move(_ template: NewFileTemplate, by offset: Int) {
        guard let index = templates.firstIndex(of: template), templates.indices.contains(index + offset) else { return }
        templates.swapAt(index, index + offset)
    }

    private func remove(_ template: NewFileTemplate) {
        templates.removeAll { $0.id == template.id }
        NewFile.removeTemplateFile(for: template.id)
    }

    private func addFromTemplateFile() {
        guard let source = TemplateRow.chooseTemplateFile() else { return }
        var template = NewFileTemplate(title: "", fileName: "")
        guard let stored = TemplateRow.store(source, for: template.id) else { return }
        // Name it after the file's kind, as Windows does: "Microsoft Word Document", …
        let ext = source.pathExtension
        let kind = UTType(filenameExtension: ext)?.localizedDescription ?? "\(ext.uppercased()) File"
        template.title = kind.prefix(1).uppercased() + kind.dropFirst()
        template.fileName = "New \(template.title)" + (ext.isEmpty ? "" : ".\(ext)")
        template.templateFile = stored
        templates.append(template)
    }

    private func statusRow(_ title: String, granted: Bool?, detail: String, action: String,
                           perform: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack {
                switch granted {
                case true?: Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case false?: Label("Off", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                case nil: Label("Not asked yet", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                }
                Button(action, action: perform)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// One editable entry of the New submenu.
private struct TemplateRow: View {
    @Binding var template: NewFileTemplate
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(for: fileType))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Menu title", text: $template.title, prompt: Text("Menu title"))
                TextField("File name", text: $template.fileName, prompt: Text("File name, e.g. Notes.md"))
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            Menu {
                Button("Move Up") { move(-1) }.disabled(!canMoveUp)
                Button("Move Down") { move(1) }.disabled(!canMoveDown)
                Divider()
                Button("Use a Template File…") { useTemplateFile() }
                if template.templateFile != nil {
                    Button("Start Empty Instead") {
                        NewFile.removeTemplateFile(for: template.id)
                        template.templateFile = nil
                    }
                }
                Divider()
                Button("Remove", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    private var fileType: UTType {
        UTType(filenameExtension: (template.fileName as NSString).pathExtension) ?? .data
    }

    private var source: String {
        if let file = template.templateFile { return "Copy of “\((file as NSString).lastPathComponent)”" }
        return template.contents.isEmpty ? "Empty file" : "Starts with sample content"
    }

    private func useTemplateFile() {
        guard let source = Self.chooseTemplateFile(), let stored = Self.store(source, for: template.id) else { return }
        template.templateFile = stored
        // Keep the extension in step with the template so the copy opens in the right app.
        let ext = source.pathExtension
        if !ext.isEmpty {
            template.fileName = ((template.fileName as NSString).deletingPathExtension as NSString)
                .appendingPathExtension(ext) ?? template.fileName
        }
    }

    static func chooseTemplateFile() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose a blank document to copy each time"
        panel.prompt = "Use as Template"
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func store(_ source: URL, for id: String) -> String? {
        do {
            return try NewFile.storeTemplateFile(source, for: id)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }
}

/// Ready-made entries offered by "Add File Type".
private struct NewFilePreset {
    let title: String
    let fileName: String
    var contents = ""

    func template() -> NewFileTemplate {
        NewFileTemplate(title: title, fileName: fileName, contents: contents)
    }

    static let all = [
        NewFilePreset(title: "Text File", fileName: "New Text File.txt"),
        NewFilePreset(title: "Markdown File", fileName: "New Document.md"),
        NewFilePreset(title: "Rich Text Document", fileName: "New Rich Text Document.rtf",
                      contents: "{\\rtf1\\ansi\\deff0\n}\n"),
        NewFilePreset(title: "HTML File", fileName: "index.html", contents: """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <title>Untitled</title>
            </head>
            <body>

            </body>
            </html>

            """),
        NewFilePreset(title: "JSON File", fileName: "data.json", contents: "{}\n"),
        NewFilePreset(title: "CSV File", fileName: "data.csv"),
        NewFilePreset(title: "Python Script", fileName: "script.py", contents: "#!/usr/bin/env python3\n\n"),
        NewFilePreset(title: "Shell Script", fileName: "script.sh", contents: "#!/bin/zsh\n\n"),
    ]
}

private struct Permissions {
    var extensionEnabled: Bool
    /// nil while macOS has not asked yet (or Finder isn't running).
    var automation: Bool?
    var accessibility: Bool

    static func current() -> Permissions {
        Permissions(extensionEnabled: FIFinderSyncController.isExtensionEnabled,
                    automation: finderAutomation(),
                    accessibility: AXIsProcessTrusted())
    }

    private static func finderAutomation() -> Bool? {
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let status = withExtendedLifetime(finder) {
            AEDeterminePermissionToAutomateTarget(finder.aeDesc, typeWildCard, typeWildCard, false)
        }
        switch status {
        case noErr: return true
        case OSStatus(errAEEventNotPermitted): return false
        default: return nil
        }
    }

    static func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

private struct TerminalApp: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage
    var id: String { bundleID }

    private static let known = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty", "co.zeit.hyper",
    ]

    /// Installed terminals, plus the current choice if it's some other app.
    static func choices(including selected: String) -> [TerminalApp] {
        var ids = known
        if !ids.contains(selected) { ids.append(selected) }
        return ids.compactMap(installed)
    }

    private static func installed(_ bundleID: String) -> TerminalApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        let name = FileManager.default.displayName(atPath: url.path)
        return TerminalApp(bundleID: bundleID, name: (name as NSString).deletingPathExtension, icon: icon)
    }

    static func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
