import AppKit

/// Stands in as NSApp's delegate while testing quitting: records the request and refuses it, so the suite keeps running.
private final class TerminationRecorder: NSObject, NSApplicationDelegate {
    var requests = 0
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requests += 1
        return .terminateCancel
    }
}

public enum AppDelegateAndSettingsTests {
    static func launchedDelegate() -> AppDelegate {
        let delegate = AppDelegate()
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        return delegate
    }

    static func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        return menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }

    /// Makes `event` NSApp.currentEvent, the way the run loop does while dispatching it.
    static func makeCurrent(_ event: NSEvent) {
        NSApp.postEvent(event, atStart: true)
        _ = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(1), inMode: .default, dequeue: true)
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("AppDelegate supports secure restorable state and disables system window tabbing") {
            let delegate = launchedDelegate()
            try expect(delegate.applicationSupportsSecureRestorableState(NSApp))
            try expect(!NSWindow.allowsAutomaticWindowTabbing)
        }

        testRunner("AppDelegate applies the appearance preference live") {
            let delegate = launchedDelegate()
            defaults.set(2, forKey: Pref.appearance)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            try expectEqual(NSApp.appearance?.name, .darkAqua)
            defaults.set(1, forKey: Pref.appearance)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            try expectEqual(NSApp.appearance?.name, .aqua)
            defaults.set(0, forKey: Pref.appearance)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            try expect(NSApp.appearance == nil, "System follows the OS")
            defaults.set(99, forKey: Pref.appearance)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            try expect(NSApp.appearance == nil, "unknown values fall back to System")
            withExtendedLifetime(delegate) {}
        }

        testRunner("AppDelegate opens an untitled document unless a session is being restored") {
            defaults.removeObject(forKey: Pref.sessionFiles)
            try expect(launchedDelegate().applicationShouldOpenUntitledFile(NSApp), "no saved session")

            defaults.set(["/nonexistent/file.txt"], forKey: Pref.sessionFiles)
            defaults.set(false, forKey: Pref.restoreSession)
            try expect(launchedDelegate().applicationShouldOpenUntitledFile(NSApp), "restoring is turned off")

            defaults.set(true, forKey: Pref.restoreSession)
            try expect(!launchedDelegate().applicationShouldOpenUntitledFile(NSApp), "a session will be restored")

            // Not restoring: finishing launch opens nothing by itself.
            defaults.removeObject(forKey: Pref.sessionFiles)
            launchedDelegate().applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            TestSupport.drain(0.1)
            try expect(documentController.documents.isEmpty)
        }

        testRunner("AppDelegate restores the previous session's files, skipping missing ones") {
            let dir = try TestSupport.temporaryDirectory()
            let a = try TestSupport.writeFile("A", named: "a.txt", in: dir)
            let b = try TestSupport.writeFile("B", named: "b.txt", in: dir)
            defaults.set([a.path, dir.appendingPathComponent("gone.txt").path, b.path], forKey: Pref.sessionFiles)
            let delegate = launchedDelegate()
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try expect(TestSupport.spin { delegate.applicationShouldOpenUntitledFile(NSApp) }, "restoring finishes")
            let paths = Set(documentController.documents.compactMap { $0.fileURL?.path })
            try expectEqual(paths, [a.path, b.path])
            try expect(documentController.documents.allSatisfy { ($0 as? TextDocument)?.host != nil }, "restored documents are shown")
            try expect(TestSupport.presentedErrors.isEmpty, "a missing session file is skipped silently")
        }

        testRunner("AppDelegate opens an empty document when no session file could be restored") {
            defaults.set(["/nonexistent/one.txt", "/nonexistent/two.txt"], forKey: Pref.sessionFiles)
            let delegate = launchedDelegate()
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try expect(TestSupport.spin { documentController.documents.count == 1 })
            try expect(documentController.documents[0].fileURL == nil, "an untitled document")
        }

        testRunner("AppDelegate saves open files, in window and tab order, as the session on quit") {
            let delegate = launchedDelegate()
            let first = try makeFileDocument("1", named: "first.txt")
            let second = try makeFileDocument("2", named: "second.txt")
            let controller = EditorWindowController()
            controller.add(first)
            controller.add(TextDocument())   // untitled: not part of the session
            controller.add(second)
            controller.showWindow(nil)
            TestSupport.drain()

            defaults.set(true, forKey: Pref.restoreSession)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            if NSApp.orderedWindows.contains(where: { $0 === controller.window }) {
                try expectEqual(defaults.stringArray(forKey: Pref.sessionFiles), [first.fileURL!.path, second.fileURL!.path])
            }

            defaults.set(false, forKey: Pref.restoreSession)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            try expectEqual(defaults.stringArray(forKey: Pref.sessionFiles), [], "turning restore off forgets the session")
        }

        testRunner("AppDelegate session keeps documents in minimized windows") {
            let delegate = launchedDelegate()
            let shown = try makeFileDocument("1", named: "shown.txt")
            let hidden = try makeFileDocument("2", named: "hidden.txt")
            let front = EditorWindowController()
            front.add(shown)
            front.showWindow(nil)
            let offScreen = EditorWindowController()
            offScreen.add(hidden)
            offScreen.showWindow(nil)
            offScreen.window?.miniaturize(nil)
            TestSupport.spin(timeout: 3) { offScreen.window?.isMiniaturized == true }

            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            let session = defaults.stringArray(forKey: Pref.sessionFiles) ?? []
            try expect(session.contains(hidden.fileURL!.path), "minimized window's file is kept: \(session)")
            try expect(session.contains(shown.fileURL!.path))
            try expectEqual(session.count, 2, "no duplicates")
        }

        testRunner("AppDelegate New Window makes a window with one untitled document") {
            let delegate = launchedDelegate()
            let before = TestSupport.editorWindows.count
            delegate.newWindow(nil)
            try expectEqual(documentController.documents.count, 1)
            let doc = try unwrap(documentController.documents.first as? TextDocument)
            try expect(doc.fileURL == nil)
            let host = try unwrap(doc.host)
            try expectEqual(host.panes.count, 1)
            try expectEqual(TestSupport.editorWindows.count, before + 1)
            try expect(host.window?.isVisible == true)
        }

        testRunner("AppDelegate Close All closes everything and leaves one empty document") {
            let delegate = launchedDelegate()
            delegate.newWindow(nil)
            delegate.newWindow(nil)
            try expectEqual(documentController.documents.count, 2)
            let originals = documentController.documents
            delegate.closeAll(nil)
            try expect(TestSupport.spin { documentController.documents.count == 1 && !originals.contains { $0 === documentController.documents[0] } })

            // didCloseAll only adds a document when none are left (for instance, when a close was cancelled).
            delegate.didCloseAll(documentController, didCloseAll: false, contextInfo: nil)
            try expectEqual(documentController.documents.count, 1)
        }

        testRunner("AppDelegate toggles line numbers and invisibles and shows their state in the menu") {
            let delegate = launchedDelegate()
            let lines = NSMenuItem(title: "", action: #selector(AppDelegate.toggleLineNumbers(_:)), keyEquivalent: "")
            let invisibles = NSMenuItem(title: "", action: #selector(AppDelegate.toggleInvisibles(_:)), keyEquivalent: "")

            try expect(delegate.validateMenuItem(lines))
            try expectEqual(lines.state, .on, "line numbers default on")
            delegate.toggleLineNumbers(nil)
            try expect(!defaults.bool(forKey: Pref.showLineNumbers))
            _ = delegate.validateMenuItem(lines)
            try expectEqual(lines.state, .off)

            _ = delegate.validateMenuItem(invisibles)
            try expectEqual(invisibles.state, .off, "invisibles default off")
            delegate.toggleInvisibles(nil)
            try expect(defaults.bool(forKey: Pref.showInvisibles))
            _ = delegate.validateMenuItem(invisibles)
            try expectEqual(invisibles.state, .on)
        }

        testRunner("AppDelegate Close Tab is enabled only with a key window") {
            let delegate = launchedDelegate()
            let closeTab = NSMenuItem(title: "", action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "")
            try expectEqual(delegate.validateMenuItem(closeTab), NSApp.keyWindow != nil)
            try expect(delegate.validateMenuItem(NSMenuItem(title: "", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "")))

            delegate.showSettings(nil)
            let settings = try unwrap(NSApp.windows.first { $0.title == "Settings" })
            settings.makeKey()
            if NSApp.keyWindow === settings {
                delegate.closeTab(nil)
                try expect(!settings.isVisible, "⌘W closes the Settings window")
            } else {
                delegate.closeTab(nil)   // no key window: nothing to close
            }
        }

        testRunner("AppDelegate Settings opens one reusable window") {
            let delegate = launchedDelegate()
            delegate.showSettings(nil)
            let settings = NSApp.windows.filter { $0.title == "Settings" && $0.isVisible }
            try expectEqual(settings.count, 1)
            delegate.showSettings(nil)
            try expectEqual(NSApp.windows.filter { $0.title == "Settings" && $0.isVisible }.count, 1)
            try expect(NSApp.windows.first { $0.title == "Settings" && $0.isVisible } === settings[0])
        }

        testRunner("AppDelegate keyboard shortcuts list matches the menu") {
            let alert = launchedDelegate().makeKeyboardShortcutsAlert()
            try expectEqual(alert.messageText, "Keyboard Shortcuts")
            for shortcut in ["⌘N  New Window", "⌘T  New Tab", "⌘L  Go to Line", "⌥⌘W  Close All", "⌘Q  Quit (press twice)"] {
                try expect(alert.informativeText.contains(shortcut), shortcut)
            }
        }

        testRunner("AppDelegate rounded mask is transparent in the corners and opaque inside") {
            let mask = AppDelegate.roundedMask(radius: 10)
            try expectEqual(mask.size, NSSize(width: 21, height: 21))
            try expect(NSEdgeInsetsEqual(mask.capInsets, NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)))
            try expectEqual(mask.resizingMode, .stretch)

            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            mask.draw(in: NSRect(x: 0, y: 0, width: 240, height: 50))
            NSGraphicsContext.restoreGraphicsState()
            for corner in [(0, 0), (239, 0), (0, 49), (239, 49)] {
                try expectEqual(rep.colorAt(x: corner.0, y: corner.1)?.alphaComponent, 0, "corner \(corner) must be clear, or a square edge shows")
            }
            try expectEqual(rep.colorAt(x: 120, y: 25)?.alphaComponent, 1, "center")
            try expectEqual(rep.colorAt(x: 120, y: 0)?.alphaComponent, 1, "middle of the straight top edge")
            try expectEqual(rep.colorAt(x: 0, y: 25)?.alphaComponent, 1, "middle of the straight left edge")
        }

        testRunner("AppDelegate quit hint is a rounded, transparent, floating panel that hides itself") {
            let panel = launchedDelegate().showQuitHint()
            try expect(!panel.isOpaque)
            try expectEqual(panel.backgroundColor, .clear)
            try expect(panel.hasShadow)
            try expectEqual(panel.level, .floating)
            try expect(panel.styleMask.contains(.borderless) && panel.styleMask.contains(.nonactivatingPanel))
            let effect = try unwrap(panel.contentView as? NSVisualEffectView)
            try expect(effect.maskImage != nil, "the material and the shadow are clipped to a rounded shape")
            try expectEqual(effect.material, .hudWindow)
            try expect(TestSupport.findSubview(NSTextField.self, in: effect) { $0.stringValue == "Press ⌘Q again to quit" } != nil)
            try expect(panel.isVisible)
            try expect(TestSupport.spin(timeout: 3) { !panel.isVisible }, "the hint disappears after 1.5 s")
        }

        testRunner("AppDelegate ⌘Q needs a second press; menu quit and slow presses behave correctly") {
            let recorder = TerminationRecorder()
            let previousDelegate = NSApp.delegate
            NSApp.delegate = recorder
            defer { NSApp.delegate = previousDelegate }
            let delegate = launchedDelegate()
            let keyDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                           context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!

            // Not a key press (menu chosen with the mouse): quit at once.
            makeCurrent(TestSupport.mouseEvent(.leftMouseDown, x: 0))
            delegate.quitRequested(nil)
            try expectEqual(recorder.requests, 1)

            // First ⌘Q: only the hint.
            makeCurrent(keyDown)
            try expectEqual(NSApp.currentEvent?.type, .keyDown)
            delegate.quitRequested(nil)
            try expectEqual(recorder.requests, 1, "the first ⌘Q only shows the hint")
            try expect(NSApp.windows.contains { $0 is NSPanel && $0.isVisible }, "hint is visible")

            // Holding ⌘Q down (key repeat) is not a second press.
            let repeatKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                             context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: true, keyCode: 12)!
            makeCurrent(repeatKey)
            try expect(NSApp.currentEvent?.isARepeat == true)
            delegate.quitRequested(nil)
            delegate.quitRequested(nil)
            try expectEqual(recorder.requests, 1, "auto-repeat must not quit")

            // Second ⌘Q within 1.5 s: quit.
            makeCurrent(keyDown)
            delegate.quitRequested(nil)
            try expectEqual(recorder.requests, 2)
        }

        testRunner("AppDelegate main menu: structure, shortcuts and wiring") {
            _ = launchedDelegate()
            let mainMenu = try unwrap(NSApp.mainMenu)
            try expectEqual(mainMenu.items.map { $0.title }, ["Minimal Notepad", "File", "Edit", "Format", "View", "Window", "Help"])
            try expect(NSApp.windowsMenu === mainMenu.item(withTitle: "Window")?.submenu)
            try expect(NSApp.helpMenu === mainMenu.item(withTitle: "Help")?.submenu)
            try expect(NSApp.servicesMenu != nil)

            let items = allItems(mainMenu)
            func item(_ title: String, in menu: String) throws -> NSMenuItem {
                return try unwrap(mainMenu.item(withTitle: menu)?.submenu?.item(withTitle: title), "\(menu) > \(title)")
            }
            func shortcut(_ item: NSMenuItem) -> String {
                let m = item.keyEquivalentModifierMask
                return (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "") + item.keyEquivalent
            }
            let expected: [(String, String, String)] = [
                ("File", "New", "⌘n"), ("File", "New Tab", "⌘t"), ("File", "Open…", "⌘o"), ("File", "Close Tab", "⌘w"),
                ("File", "Close Window", "⇧⌘w"), ("File", "Close All", "⌥⌘w"), ("File", "Save", "⌘s"), ("File", "Save As…", "⇧⌘s"),
                ("File", "Print…", "⌘p"), ("Edit", "Undo", "⌘z"), ("Edit", "Redo", "⇧⌘z"), ("Edit", "Paste", "⌘v"),
                ("Edit", "Find…", "⌘f"), ("Edit", "Find Next", "⌘g"), ("Edit", "Find Previous", "⇧⌘g"), ("Edit", "Replace…", "⌥⌘f"),
                ("Edit", "Go to Line…", "⌘l"), ("Format", "Zoom In", "⌘+"), ("Format", "Zoom Out", "⌘-"), ("Format", "Actual Size", "⌘0"),
                ("View", "Enter Full Screen", "⌃⌘f"), ("Window", "Show Previous Tab", "⇧⌘["), ("Window", "Show Next Tab", "⇧⌘]"),
                ("Minimal Notepad", "Quit Minimal Notepad", "⌘q"), ("Minimal Notepad", "Settings…", "⌘,"), ("Help", "Minimal Notepad Help", "⌘?")
            ]
            for (menu, title, keys) in expected {
                try expectEqual(shortcut(try item(title, in: menu)), keys, "\(menu) > \(title)")
            }
            try expectEqual(try item("Paste", in: "Edit").action, #selector(NSTextView.pasteAsPlainText(_:)), "paste never brings in formatting")
            try expectEqual(try item("Quit Minimal Notepad", in: "Minimal Notepad").action, #selector(AppDelegate.quitRequested(_:)))

            let alias = try unwrap(items.first { $0.keyEquivalent == "=" })
            try expect(alias.isHidden && alias.allowsKeyEquivalentWhenHidden, "⌘= zooms in without a visible duplicate")

            // No duplicate shortcuts.
            let shortcuts = items.filter { !$0.keyEquivalent.isEmpty }.map(shortcut)
            try expectEqual(shortcuts.count, Set(shortcuts).count, "duplicate key equivalents: \(shortcuts)")

            // Every action is implemented by something in the responder chain, so no item is dead because of a typo.
            let implementers: [AnyClass] = [AppDelegate.self, EditorWindowController.self, EditorPane.self, EditorTextView.self,
                                            TextDocument.self, DocumentController.self, NSApplication.self, NSWindow.self]
            for menuItem in items {
                guard let action = menuItem.action, menuItem.submenu == nil else { continue }
                try expect(implementers.contains { $0.instancesRespond(to: action) }, "nothing implements \(action) for “\(menuItem.title)”")
            }
        }

        testRunner("SettingsWindowController binds every control to its preference") {
            let controller = SettingsWindowController()
            let window = try unwrap(controller.window)
            try expectEqual(window.title, "Settings")
            try expectEqual(window.tabbingMode, .disallowed)
            let content = try unwrap(window.contentView)
            try expect(content.fittingSize.width > 0 && window.frame.width > 0)

            var popUps: [NSPopUpButton] = []
            var checkboxes: [NSButton] = []
            func collect(_ view: NSView) {
                if let popUp = view as? NSPopUpButton { popUps.append(popUp) }
                else if let button = view as? NSButton { checkboxes.append(button) }
                view.subviews.forEach(collect)
            }
            collect(content)
            try expectEqual(popUps.count, 2)
            try expectEqual(checkboxes.count, 4)
            try expectEqual(popUps[0].itemTitles, ["System", "Light", "Dark"])
            try expectEqual(popUps[1].itemTitles, ["LF (macOS, Unix)", "CRLF (Windows)"])

            defaults.set(2, forKey: Pref.appearance)
            try expectEqual(popUps[0].indexOfSelectedItem, 2)
            defaults.set(1, forKey: Pref.lineEnding)
            try expectEqual(popUps[1].indexOfSelectedItem, 1)

            let keys = [Pref.wordWrap, Pref.restoreSession, Pref.confirmClose, Pref.saveOnFocusLost]
            for (checkbox, key) in zip(checkboxes, keys) {
                let before = defaults.bool(forKey: key)
                try expectEqual(checkbox.state == .on, before, key)
                checkbox.performClick(nil)
                try expectEqual(defaults.bool(forKey: key), !before, "clicking changes \(key)")
            }
        }
    }
}
