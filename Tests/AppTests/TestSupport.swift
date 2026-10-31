import AppKit

/// A failed expectation. Thrown (instead of `assert`, which traps and is compiled out with -O)
/// so the runner reports it and continues with the next test.
struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
            file: StaticString = #fileID, line: UInt = #line) throws {
    guard try condition() else {
        throw TestFailure(description: "\(file):\(line) expectation failed. \(message())")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String = "",
                               file: StaticString = #fileID, line: UInt = #line) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(file):\(line) expected \(String(reflecting: expected)), got \(String(reflecting: actual)). \(message())")
    }
}

func expectThrows(_ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line,
                  _ block: () throws -> Void) throws -> Error {
    do {
        try block()
    } catch {
        return error
    }
    throw TestFailure(description: "\(file):\(line) expected an error to be thrown. \(message())")
}

func unwrap<T>(_ value: T?, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value = value else {
        throw TestFailure(description: "\(file):\(line) unexpected nil. \(message())")
    }
    return value
}

enum TestSupport {
    /// Errors that DocumentController.open(_:) would have shown in an (app-modal, suite-blocking) alert.
    static var presentedErrors: [Error] = []
    /// Large file warnings that would have been shown, and the answer the stand-in prompt gives.
    static var largeFilePrompts: [(url: URL, size: Int64)] = []
    static var largeFileAnswer = true

    /// Runs the main run loop until the condition holds or the timeout passes. Returns the condition.
    @discardableResult
    static func spin(timeout: TimeInterval = 2, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// Keeps the run loop turning for the whole interval (a single run(until:) can return at once when no
    /// timers are scheduled, leaving deferred main-queue work, such as window cleanup, not yet done).
    static func drain(_ seconds: TimeInterval = 0.02) {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        } while Date() < deadline
    }

    static var editorWindows: [EditorWindowController] {
        return NSApp.windows.compactMap { $0.windowController as? EditorWindowController }
    }

    static let prefKeys = [Pref.lineEnding, Pref.wordWrap, Pref.appearance, Pref.restoreSession, Pref.confirmClose,
                           Pref.showLineNumbers, Pref.showInvisibles, Pref.saveOnFocusLost, Pref.sessionFiles]

    /// Puts the app back in its pristine state: no documents, no windows, registered default preferences.
    static func reset() {
        presentedErrors = []
        documentController.errorPresenter = { TestSupport.presentedErrors.append($0) }
        largeFilePrompts = []
        documentController.largeFileWarningSize = 200_000_000
        documentController.confirmLargeFile = { url, size in
            TestSupport.largeFilePrompts.append((url, size))
            return TestSupport.largeFileAnswer
        }
        largeFileAnswer = true
        for window in NSApp.windows {
            while let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        }
        for document in documentController.documents {
            document.updateChangeCount(.changeCleared)
            document.close()
        }
        for controller in editorWindows {
            for pane in controller.panes {
                pane.document.updateChangeCount(.changeCleared)
                pane.document.close()
            }
            controller.window?.close()
        }
        for window in NSApp.windows where window.isVisible { window.orderOut(nil) }
        prefKeys.forEach(defaults.removeObject(forKey:))
        Pref.registerDefaults()
        NSApp.appearance = nil
        drain()
    }

    // MARK: - Temporary files

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MinimalNotepadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    static func writeFile(_ contents: Data, named name: String = "file.txt", in directory: URL? = nil) throws -> URL {
        let dir = try directory ?? temporaryDirectory()
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    static func writeFile(_ contents: String, named name: String = "file.txt", in directory: URL? = nil) throws -> URL {
        return try writeFile(Data(contents.utf8), named: name, in: directory)
    }

    // MARK: - View lookup

    static func findSubview<T: NSView>(_ type: T.Type, in view: NSView, where predicate: (T) -> Bool = { _ in true }) -> T? {
        if let match = view as? T, predicate(match) { return match }
        for subview in view.subviews {
            if let found = findSubview(type, in: subview, where: predicate) { return found }
        }
        return nil
    }

    static func tabBar(of controller: EditorWindowController) -> TabBarView? {
        return controller.window?.contentView.flatMap { findSubview(TabBarView.self, in: $0) }
    }

    static func searchBar(of pane: EditorPane) -> SearchBarView? {
        return findSubview(SearchBarView.self, in: pane)
    }

    /// Search bar parts, by their position in the bar.
    struct SearchControls {
        let bar: SearchBarView
        let find: NSSearchField
        let previous: NSButton
        let next: NSButton
        let matchCase: NSButton
        let replace: NSTextField
        let replaceButton: NSButton
        let replaceAll: NSButton
        let done: NSButton
    }

    static func searchControls(of pane: EditorPane) throws -> SearchControls {
        let bar = try unwrap(searchBar(of: pane), "search bar")
        let views = bar.arrangedSubviews
        return SearchControls(
            bar: bar,
            find: try unwrap(views[0] as? NSSearchField),
            previous: try unwrap(views[1] as? NSButton),
            next: try unwrap(views[2] as? NSButton),
            matchCase: try unwrap(views[3] as? NSButton),
            replace: try unwrap(views[4] as? NSTextField),
            replaceButton: try unwrap(views[5] as? NSButton),
            replaceAll: try unwrap(views[6] as? NSButton),
            done: try unwrap(views[9] as? NSButton)
        )
    }

    // MARK: - Events

    static func mouseEvent(_ type: NSEvent.EventType, window: NSWindow? = nil, x: CGFloat, y: CGFloat = 14) -> NSEvent {
        return NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// A mouse event for another button (2 = middle). NSEvent's factory cannot set the button number,
    /// so it is set on the underlying CGEvent.
    static func otherMouseEvent(_ type: NSEvent.EventType, button: Int64 = 2, window: NSWindow?, x: CGFloat, y: CGFloat = 14) -> NSEvent {
        let base = mouseEvent(type, window: window, x: x, y: y)
        let cgEvent = base.cgEvent!
        cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return NSEvent(cgEvent: cgEvent)!
    }

    static func enterExitEvent(_ type: NSEvent.EventType) -> NSEvent {
        return NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                      context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }
}

/// Makes a document the way the app does when opening a file (proper file type, URL and contents).
func makeFileDocument(_ contents: String, named name: String = "file.txt") throws -> TextDocument {
    let url = try TestSupport.writeFile(contents, named: name)
    let type = try documentController.typeForContents(of: url)
    return try unwrap(try documentController.makeDocument(withContentsOf: url, ofType: type) as? TextDocument)
}

final class MockDraggingInfo: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        super.init()
    }

    var draggingPasteboard: NSPasteboard { return pasteboard }
    var draggingLocation: NSPoint { return .zero }
    var draggingSourceOperationMask: NSDragOperation { return .copy }
    var draggingDestinationWindow: NSWindow? { return nil }
    var draggingSource: Any? { return nil }
    var draggingSequenceNumber: Int { return 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggedImage: NSImage? { return nil }
    var draggedImageLocation: NSPoint { return .zero }
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { return nil }
    var numberOfValidItemsForDrop: Int = 1
    var animatesToDestination: Bool = false
    var draggingFormation: NSDraggingFormation = .default
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { return .none }
    func resetSpringLoading() {}
}
