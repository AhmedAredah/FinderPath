import Cocoa

/// The editable path bar that drops down just below a Finder window's toolbar.
final class PathBarController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let panel = PathBarPanel(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: PathBarController.height),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private let field = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private var finderWindow: FinderWindow?

    private static let height: CGFloat = 34
    private static let inset: CGFloat = 10

    private var settings: UserDefaults { SharedSettings.defaults }

    /// Whether plain Return opens files and apps (⌘Return then reveals them), or the reverse.
    private var returnOpensFiles: Bool { settings.bool(forKey: SharedSettings.Key.returnOpensFiles) }

    private var hint: String {
        returnOpensFiles ? "⇥ complete   ↩ open   ⌘↩ show in folder   esc"
                         : "⇥ complete   ↩ go   ⌘↩ open file   esc"
    }

    /// Height of Finder's title bar plus toolbar; set in Settings.
    private var toolbarHeight: CGFloat {
        let value = settings.double(forKey: SharedSettings.Key.toolbarHeight)
        return value > 0 ? value : SharedSettings.defaultToolbarHeight
    }

    override init() {
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "Type or paste a path"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        status.setContentHuggingPriority(.required, for: .horizontal)

        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") ?? NSImage(),
                            target: self, action: #selector(openSettings(_:)))
        gear.isBordered = false
        gear.contentTintColor = .tertiaryLabelColor
        gear.toolTip = "FinderPath Settings"

        let row = NSStackView(views: [icon, field, status, gear])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            row.topAnchor.constraint(equalTo: background.topAnchor),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    func show() {
        do {
            finderWindow = try Finder.frontWindow()
            setStatus(nil)
        } catch {
            finderWindow = nil
            setStatus((error as? FinderError)?.message ?? error.localizedDescription, isError: true)
        }
        field.stringValue = finderWindow?.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
        field.textColor = .labelColor

        panel.setFrame(barFrame(), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Spans the Finder window's content area (right of the sidebar) just under its toolbar, or
    /// sits near the top of the screen when there is no Finder window.
    private func barFrame() -> NSRect {
        guard let window = finderWindow, let primary = NSScreen.screens.first else {
            let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let width = min(720, visible.width - 40)
            return NSRect(x: visible.midX - width / 2, y: visible.maxY - visible.height / 4,
                          width: width, height: Self.height)
        }
        // Keep the sidebar clear unless that would leave the bar too narrow to use.
        let bounds = window.bounds
        let sidebar = bounds.width - window.sidebarWidth >= 320 ? window.sidebarWidth : 0
        // AppleScript measures from the top of the primary screen; Cocoa from its bottom.
        let top = primary.frame.height - (bounds.minY + toolbarHeight + 6)
        return NSRect(x: bounds.minX + sidebar + Self.inset, y: top - Self.height,
                      width: max(bounds.width - sidebar - 2 * Self.inset, 240), height: Self.height)
    }

    /// Like the Windows address bar: folders open in this window; files and apps open in their
    /// default app. With `reveal`, files and apps are shown selected in their folder instead.
    private func go(reveal: Bool) {
        // Keywords win over same-named items here; type `./cmd` to reach a folder of that name.
        let command = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if command == "settings" {
            openSettings(nil)
            return
        }
        // As on Windows, `cmd` opens a terminal in the current folder.
        if (command == "cmd" || command == "terminal") && settings.bool(forKey: SharedSettings.Key.cmdOpensTerminal) {
            if Terminal.open(at: finderWindow?.path ?? NSHomeDirectory()) {
                panel.orderOut(nil)
            } else {
                fail("Could not open Terminal")
            }
            return
        }

        guard let target = PathResolver.resolve(field.stringValue, relativeTo: finderWindow?.path) else {
            fail("No such file or folder")
            return
        }
        let isFile = !target.isDirectory || NSWorkspace.shared.isFilePackage(atPath: target.path)

        if isFile && !reveal {
            if NSWorkspace.shared.open(URL(fileURLWithPath: target.path)) {
                panel.orderOut(nil)
            } else {
                fail("No app can open this file")
            }
            return
        }

        let folder = isFile ? (target.path as NSString).deletingLastPathComponent : target.path
        do {
            try Finder.open(folder: folder, selecting: isFile ? target.path : nil, inWindow: finderWindow?.id)
            panel.orderOut(nil)
        } catch {
            fail((error as? FinderError)?.message ?? error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        NSSound.beep()
        field.textColor = .systemRed
        setStatus(message, isError: true)
    }

    private func setStatus(_ message: String?, isError: Bool = false) {
        status.stringValue = message ?? hint
        status.textColor = isError ? .systemRed : .tertiaryLabelColor
        status.toolTip = message
    }

    @objc private func openSettings(_ sender: Any?) {
        panel.orderOut(nil)
        SettingsWindowController.shared.show()
    }

    private func dismiss() {
        panel.orderOut(nil)
        Finder.activate()
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // ⌘Return arrives as insertNewline: or, having no key binding, as noop:.
        if let event = NSApp.currentEvent, event.type == .keyDown, [36, 76].contains(event.keyCode),
           selector == #selector(NSResponder.insertNewline(_:)) || selector == Selector(("noop:")) {
            // ⌘ flips whatever plain Return does.
            go(reveal: event.modifierFlags.contains(.command) == returnOpensFiles)
            return true
        }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            go(reveal: !returnOpensFiles)
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
        case #selector(NSResponder.insertTab(_:)):
            if let completed = PathResolver.complete(textView.string, relativeTo: finderWindow?.path) {
                textView.string = completed
                textView.setSelectedRange(NSRange(location: (completed as NSString).length, length: 0))
            } else {
                NSSound.beep()
            }
        default:
            return false
        }
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        field.textColor = .labelColor
        setStatus(nil)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }
}

/// Borderless panels refuse key status by default, which would block typing.
private final class PathBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
