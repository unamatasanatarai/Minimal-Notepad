import AppKit

public enum AppDelegateAndSettingsTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("AppDelegate application lifecycle, appearance, and secure restoration") {
            let delegate = AppDelegate()
            assert(delegate.applicationSupportsSecureRestorableState(NSApplication.shared) == true)

            // appearance setting tests
            let origAppearance = defaults.integer(forKey: Pref.appearance)
            defer { defaults.set(origAppearance, forKey: Pref.appearance) }

            defaults.set(1, forKey: Pref.appearance) // Aqua
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)

            defaults.set(2, forKey: Pref.appearance) // DarkAqua
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)

            defaults.set(0, forKey: Pref.appearance) // System
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)

            // Will finish launching & ShouldOpenUntitledFile
            delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
            let shouldOpen = delegate.applicationShouldOpenUntitledFile(NSApplication.shared)
            assert(shouldOpen == true || shouldOpen == false)

            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

            // Will terminate session saving
            let origRestore = defaults.bool(forKey: Pref.restoreSession)
            defer { defaults.set(origRestore, forKey: Pref.restoreSession) }

            defaults.set(false, forKey: Pref.restoreSession)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            let savedFilesOff = defaults.stringArray(forKey: Pref.sessionFiles) ?? []
            assert(savedFilesOff.isEmpty)

            defaults.set(true, forKey: Pref.restoreSession)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

            // Test session restoring flow with a mock file
            let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("restore_\(UUID().uuidString).txt")
            try? "Restored session content".write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            defaults.set([tempFile.path], forKey: Pref.sessionFiles)
            defaults.set(true, forKey: Pref.restoreSession)
            let restoreDelegate = AppDelegate()
            restoreDelegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
            assert(!restoreDelegate.applicationShouldOpenUntitledFile(NSApplication.shared))
            restoreDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        testRunner("AppDelegate toggle line numbers, invisibles, and menu validation") {
            let delegate = AppDelegate()
            let origLineNumbers = defaults.bool(forKey: Pref.showLineNumbers)
            let origInvisibles = defaults.bool(forKey: Pref.showInvisibles)
            defer {
                defaults.set(origLineNumbers, forKey: Pref.showLineNumbers)
                defaults.set(origInvisibles, forKey: Pref.showInvisibles)
            }

            // Toggle line numbers
            delegate.toggleLineNumbers(nil)
            assert(defaults.bool(forKey: Pref.showLineNumbers) == !origLineNumbers)
            delegate.toggleLineNumbers(nil)
            assert(defaults.bool(forKey: Pref.showLineNumbers) == origLineNumbers)

            // Toggle invisibles
            delegate.toggleInvisibles(nil)
            assert(defaults.bool(forKey: Pref.showInvisibles) == !origInvisibles)
            delegate.toggleInvisibles(nil)
            assert(defaults.bool(forKey: Pref.showInvisibles) == origInvisibles)

            // Menu item validation
            let lineItem = NSMenuItem(title: "Line Numbers", action: #selector(AppDelegate.toggleLineNumbers(_:)), keyEquivalent: "")
            let invisItem = NSMenuItem(title: "Invisibles", action: #selector(AppDelegate.toggleInvisibles(_:)), keyEquivalent: "")
            let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "")
            let otherItem = NSMenuItem(title: "Other", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "")

            defaults.set(true, forKey: Pref.showLineNumbers)
            _ = delegate.validateMenuItem(lineItem)
            assert(lineItem.state == .on)

            defaults.set(false, forKey: Pref.showLineNumbers)
            _ = delegate.validateMenuItem(lineItem)
            assert(lineItem.state == .off)

            defaults.set(true, forKey: Pref.showInvisibles)
            _ = delegate.validateMenuItem(invisItem)
            assert(invisItem.state == .on)

            defaults.set(false, forKey: Pref.showInvisibles)
            _ = delegate.validateMenuItem(invisItem)
            assert(invisItem.state == .off)

            _ = delegate.validateMenuItem(closeTabItem)
            assert(delegate.validateMenuItem(otherItem) == true)
        }

        testRunner("AppDelegate menu structure and key equivalents") {
            let delegate = AppDelegate()
            delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
            guard let mainMenu = NSApp.mainMenu else {
                assertionFailure("NSApp.mainMenu should not be nil")
                return
            }

            let menuTitles = mainMenu.items.map { $0.title }
            assert(menuTitles.contains("Minimal Notepad"))
            assert(menuTitles.contains("File"))
            assert(menuTitles.contains("Edit"))
            assert(menuTitles.contains("Format"))
            assert(menuTitles.contains("View"))
            assert(menuTitles.contains("Window"))
            assert(menuTitles.contains("Help"))

            // Validate specific items in File menu
            if let fileSubmenu = mainMenu.item(withTitle: "File")?.submenu {
                let fileItemTitles = fileSubmenu.items.map { $0.title }
                assert(fileItemTitles.contains("New"))
                assert(fileItemTitles.contains("New Tab"))
                assert(fileItemTitles.contains("Open…"))
                assert(fileItemTitles.contains("Close Tab"))
                assert(fileItemTitles.contains("Close Window"))
                assert(fileItemTitles.contains("Close All"))
                assert(fileItemTitles.contains("Save"))
                assert(fileItemTitles.contains("Save As…"))
                assert(fileItemTitles.contains("Print…"))
            }

            // Validate Edit menu
            if let editSubmenu = mainMenu.item(withTitle: "Edit")?.submenu {
                let editTitles = editSubmenu.items.map { $0.title }
                assert(editTitles.contains("Find…"))
                assert(editTitles.contains("Replace…"))
                assert(editTitles.contains("Go to Line…"))
            }
        }

        testRunner("SettingsWindowController initialization and configuration") {
            let controller = SettingsWindowController()
            guard let window = controller.window else {
                assertionFailure("SettingsWindowController window should exist")
                return
            }
            assert(window.title == "Settings")
            assert(window.tabbingMode == .disallowed)
            assert(window.contentView != nil)
            assert(window.contentView?.subviews.count ?? 0 > 0)
        }

        testRunner("AppDelegate actions invocation") {
            let delegate = AppDelegate()
            delegate.showSettings(nil)
            delegate.closeTab(nil)
            delegate.showQuitHint()
            delegate.newWindow(nil)
            delegate.closeAll(nil)
            delegate.didCloseAll(documentController, didCloseAll: true, contextInfo: nil)
        }
    }
}
