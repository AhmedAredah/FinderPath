import Cocoa
import FinderSync
import SwiftUI

/// The first-launch guide. A downloaded copy of FinderPath can't turn on its own extension or add
/// its toolbar button, so this walks the user through doing it.
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private static let shownKey = "HasShownWelcome"
    static var hasBeenShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(done: { [weak self] in
            self?.window.close()
        })))
        window.title = "Welcome to FinderPath"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }()

    func show() {
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        AppPresence.windowWillShow()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppPresence.windowWillClose(window)
    }
}

/// FinderPath runs in the background, but shows in the Dock and ⌘Tab while one of its windows is
/// open so the window can't get lost behind others.
enum AppPresence {
    static func windowWillShow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowWillClose(_ closing: NSWindow) {
        let othersOpen = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct WelcomeView: View {
    let done: () -> Void

    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var accessibility = AXIsProcessTrusted()
    private let inApplications = Installation.isInApplicationsFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to FinderPath").font(.title).bold()
                    Text("A Windows-style path bar and right-click menu for Finder.")
                        .foregroundStyle(.secondary)
                }
            }

            if !inApplications {
                GroupBox {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Move FinderPath to Applications first").bold()
                            Text("It's running from outside the Applications folder, so Finder won't load its extension reliably.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Move to Applications and Reopen", action: Installation.moveToApplications)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                step(1, "Turn on the Finder extension", done: extensionEnabled,
                     detail: "Switch on FinderPath in the list of Finder extensions.") {
                    Button("Open Extension Settings") { FIFinderSyncController.showExtensionManagementInterface() }
                }
                step(2, "Add the Go to Path button to Finder", done: nil,
                     detail: "In a Finder window, choose View ▸ Customize Toolbar…, then drag Go to Path into the toolbar.") {
                    Button("Open a Finder Window") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
                    }
                }
                step(3, "Allow FinderPath to control Finder", done: nil,
                     detail: "macOS asks the first time you use the path bar. Click Allow so it can change the folder a window shows.") {
                    EmptyView()
                }
                step(4, "Optional: allow Accessibility", done: accessibility,
                     detail: "Lets new files from the New menu start with their name ready to edit.") {
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            .disabled(!inApplications)

            GroupBox("What you get") {
                VStack(alignment: .leading, spacing: 6) {
                    feature("text.cursor", "Click **Go to Path**, type or paste a path, and press Return.")
                    feature("plus.square", "Right-click an empty area: **New** files and **Open Terminal Here**.")
                    feature("doc.on.clipboard", "Right-click files or folders: **Copy Path**.")
                    feature("gearshape", "Adjust everything in Settings, or type **settings** in the path bar.")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Open Settings") {
                    done()
                    SettingsWindowController.shared.show()
                }
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
            accessibility = AXIsProcessTrusted()
        }
    }

    private func step<Actions: View>(_ number: Int, _ title: String, done: Bool?, detail: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done == true ? Color.green : Color.accentColor)
                if done == true {
                    Image(systemName: "checkmark").font(.caption.bold())
                } else {
                    Text("\(number)").font(.callout.bold())
                }
            }
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold()
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
        }
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(Color.accentColor) }
    }
}

enum Installation {
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    /// Copies this app into /Applications (replacing an older copy, which goes to the Trash),
    /// opens the copy and quits.
    static func moveToApplications() {
        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: Bundle.main.bundleURL, to: destination)
            // The user already chose to open this download; without this the copy would be run
            // from a read-only random location again (App Translocation).
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try xattr.run()
            xattr.waitUntilExit()

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
