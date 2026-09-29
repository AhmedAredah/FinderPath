import Cocoa

// Set the delegate explicitly: there is no main nib to do it for us.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
