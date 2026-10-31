import AppKit

// MARK: - Main Application Entry Point

Pref.registerDefaults()
let app = NSApplication.shared
_ = documentController   // first instance becomes NSDocumentController.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
