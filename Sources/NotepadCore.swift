import AppKit
import UniformTypeIdentifiers

// MARK: - Preferences

enum Pref {
    static let lineEnding = "DefaultLineEnding"        // 0 = LF, 1 = CRLF
    static let wordWrap = "DefaultWordWrap"
    static let appearance = "Appearance"               // 0 = System, 1 = Light, 2 = Dark
    static let restoreSession = "RestoreSession"
    static let confirmClose = "ConfirmClose"
    static let showLineNumbers = "ShowLineNumbers"
    static let showInvisibles = "ShowInvisibles"
    static let saveOnFocusLost = "SaveOnFocusLost"
    static let sessionFiles = "SessionFiles"

    static func registerDefaults() {
        defaults.register(defaults: [
            lineEnding: 0,
            wordWrap: true,
            appearance: 0,
            restoreSession: true,
            confirmClose: true,
            showLineNumbers: true,
            showInvisibles: false,
            saveOnFocusLost: false
        ])
    }
}

let defaults = UserDefaults.standard
let documentController = DocumentController()

func editorFont(size: CGFloat) -> NSFont {
    return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

/// Line numbers and invisible characters: a step fainter than tertiaryLabelColor, in light and dark mode.
let dimmedTextColor = NSColor(name: nil) { appearance in
    return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.18)
}

// MARK: - Main Application Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var restoringSession = false
    private var lastQuitRequest = Date.distantPast
    private lazy var settingsWindowController = SettingsWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false   // tabs are drawn inside the window; this also drops "Show All Tabs"
        NSApp.mainMenu = makeMainMenu()
        applyAppearance()
        NotificationCenter.default.addObserver(self, selector: #selector(applyAppearance), name: UserDefaults.didChangeNotification, object: nil)
        restoringSession = defaults.bool(forKey: Pref.restoreSession) && !sessionFiles.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard restoringSession else { return }
        let group = DispatchGroup()
        for path in sessionFiles {
            group.enter()
            documentController.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in
                group.leave()
            }
        }
        group.notify(queue: .main) { [self] in
            restoringSession = false
            if documentController.documents.isEmpty { documentController.newDocument(nil) }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return !restoringSession
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        let paths = defaults.bool(forKey: Pref.restoreSession) ? EditorWindowController.orderedDocuments.compactMap { $0.fileURL?.path } : []
        defaults.set(paths, forKey: Pref.sessionFiles)
    }

    private var sessionFiles: [String] {
        return defaults.stringArray(forKey: Pref.sessionFiles) ?? []
    }

    @objc private func applyAppearance() {
        let name: NSAppearance.Name? = [1: .aqua, 2: .darkAqua][defaults.integer(forKey: Pref.appearance)]
        if NSApp.appearance?.name != name {
            NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
        }
    }

    // MARK: - Actions

    /// ⌘Q must be pressed twice in quick succession; quitting from the menu with the mouse is immediate.
    /// Holding ⌘Q down is one press: its auto-repeats are ignored, or the key repeat alone would quit.
    @objc func quitRequested(_ sender: Any?) {
        guard let event = NSApp.currentEvent, event.type == .keyDown else {
            NSApp.terminate(sender)
            return
        }
        guard !event.isARepeat else { return }
        guard Date().timeIntervalSince(lastQuitRequest) > 1.5 else {
            NSApp.terminate(sender)
            return
        }
        lastQuitRequest = Date()
        showQuitHint()
    }

    /// A stretchable rounded-rect mask. NSVisualEffectView ignores layer.cornerRadius for its material and for the
    /// window shadow, which leaves a square outline around the rounded shape; a mask image clips both.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    @discardableResult
    func showQuitHint() -> NSPanel {
        let message = "Press ⌘Q again to quit"
        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.maskImage = AppDelegate.roundedMask(radius: 10)
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])

        let size = NSSize(width: 240, height: 50)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = background
        if let frame = NSApp.mainWindow?.frame ?? NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        panel.hasShadow = true
        panel.orderFrontRegardless()
        panel.invalidateShadow()   // recompute the shadow from the masked (rounded) content
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "Press Command Q again to quit",
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { panel.orderOut(nil) }
        return panel
    }

    /// ⌘N opens a new window; ⌘T (newDocument:) opens a new tab in the front window.
    @objc func newWindow(_ sender: Any?) {
        guard let type = documentController.defaultType,
              let document = try? documentController.makeUntitledDocument(ofType: type) as? TextDocument else { return }
        documentController.addDocument(document)
        let windowController = EditorWindowController()
        windowController.add(document)
        windowController.showWindow(nil)
    }

    /// Close All leaves the app as it is at launch: one empty document.
    @objc func closeAll(_ sender: Any?) {
        documentController.closeAllDocuments(withDelegate: self, didCloseAllSelector: #selector(didCloseAll(_:didCloseAll:contextInfo:)), contextInfo: nil)
    }

    @objc func didCloseAll(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if controller.documents.isEmpty { controller.newDocument(nil) }
    }

    /// ⌘W in a window without tabs (Settings) closes that window.
    @objc func closeTab(_ sender: Any?) {
        NSApp.keyWindow?.performClose(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        settingsWindowController.showWindow(sender)
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        defaults.set(!defaults.bool(forKey: Pref.showLineNumbers), forKey: Pref.showLineNumbers)
    }

    @objc func toggleInvisibles(_ sender: Any?) {
        defaults.set(!defaults.bool(forKey: Pref.showInvisibles), forKey: Pref.showInvisibles)
    }

    @objc func openHelp(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/unamatasanatarai/Minimal-Notepad#readme")!)
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        makeKeyboardShortcutsAlert().runModal()
    }

    func makeKeyboardShortcutsAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = """
        ⌘N  New Window          ⌘T  New Tab
        ⌘W  Close Tab           ⇧⌘W  Close Window
        ⇧⌘[  Previous Tab       ⇧⌘]  Next Tab
        ⌘O  Open                ⌥⌘W  Close All
        ⌘S  Save                ⇧⌘S  Save As
        ⌘P  Print               ⌘Q  Quit (press twice)
        ⌘F  Find                ⌥⌘F  Replace
        ⌘G  Find Next           ⇧⌘G  Find Previous
        ⌘L  Go to Line          ⌘Z / ⇧⌘Z  Undo / Redo
        ⌘+  Zoom In             ⌘−  Zoom Out
        ⌘0  Actual Size         ⌃⌘F  Full Screen
        """
        return alert
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = defaults.bool(forKey: Pref.showLineNumbers) ? .on : .off
        case #selector(toggleInvisibles(_:)):
            menuItem.state = defaults.bool(forKey: Pref.showInvisibles) ? .on : .off
        case #selector(closeTab(_:)):
            return NSApp.keyWindow != nil
        default:
            break
        }
        return true
    }

    // MARK: - Menu Setup


    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        menuItem.submenu = submenu
        return menuItem
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let servicesMenu = menu("Services", [])
        NSApp.servicesMenu = servicesMenu.submenu
        mainMenu.addItem(menu("Minimal Notepad", [
            item("About Minimal Notepad", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(showSettings(_:)), ","),
            .separator(),
            servicesMenu,
            .separator(),
            item("Hide Minimal Notepad", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Minimal Notepad", #selector(quitRequested(_:)), "q")
        ]))

        mainMenu.addItem(menu("File", [
            item("New", #selector(newWindow(_:)), "n"),
            item("New Tab", #selector(NSDocumentController.newDocument(_:)), "t"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),   // AppKit inserts Open Recent after this
            .separator(),
            item("Close Tab", #selector(EditorWindowController.closeTab(_:)), "w"),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            item("Close All", #selector(closeAll(_:)), "w", [.command, .option]),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            .separator(),
            item("Print…", #selector(NSDocument.printDocument(_:)), "p")
        ]))

        mainMenu.addItem(menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSTextView.pasteAsPlainText(_:)), "v"),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(EditorPane.showFind(_:)), "f"),
            item("Find Next", #selector(EditorPane.findNext(_:)), "g"),
            item("Find Previous", #selector(EditorPane.findPrevious(_:)), "g", [.command, .shift]),
            item("Replace…", #selector(EditorPane.showReplace(_:)), "f", [.command, .option]),
            .separator(),
            item("Go to Line…", #selector(EditorPane.goToLine(_:)), "l")
        ]))

        // ⌘= is the unshifted ⌘+ key; keep it working without a visible duplicate.
        let zoomInAlias = item("Zoom In", #selector(EditorPane.zoomIn(_:)), "=")
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        mainMenu.addItem(menu("Format", [
            item("Word Wrap", #selector(EditorPane.toggleWordWrap(_:))),
            .separator(),
            item("Zoom In", #selector(EditorPane.zoomIn(_:)), "+"),
            zoomInAlias,
            item("Zoom Out", #selector(EditorPane.zoomOut(_:)), "-"),
            item("Actual Size", #selector(EditorPane.resetZoom(_:)), "0")
        ]))

        let viewMenu = menu("View", [
            item("Line Numbers", #selector(toggleLineNumbers(_:))),
            item("Invisible Characters", #selector(toggleInvisibles(_:))),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        ])
        mainMenu.addItem(viewMenu)

        let windowMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Show Previous Tab", #selector(EditorWindowController.showPreviousTab(_:)), "[", [.command, .shift]),
            item("Show Next Tab", #selector(EditorWindowController.showNextTab(_:)), "]", [.command, .shift]),
            item("Move Tab to New Window", #selector(EditorWindowController.moveTabToNewWindow(_:))),
            item("Merge All Windows", #selector(EditorWindowController.mergeAllWindows(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        ])
        mainMenu.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu

        let helpMenu = menu("Help", [
            item("Minimal Notepad Help", #selector(openHelp(_:)), "?"),
            item("Keyboard Shortcuts", #selector(showKeyboardShortcuts(_:))),
            .separator(),
            item("About Minimal Notepad", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        ])
        mainMenu.addItem(helpMenu)
        NSApp.helpMenu = helpMenu.submenu

        return mainMenu
    }
}

// MARK: - Document Controller

final class DocumentController: NSDocumentController {
    /// Files above this size (in bytes, as Finder counts them) open only after a warning.
    var largeFileWarningSize: Int64 = 200_000_000

    /// Asks whether to open a large file; replaceable so tests are not blocked by an app-modal alert.
    var confirmLargeFile: (URL, Int64) -> Bool = { url, size in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(url.lastPathComponent)” is \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))."
        alert.informativeText = "Large files can take a while to open and use a lot of memory. Open it anyway?"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // Open the symlink target, so saving updates the real file instead of replacing the link with a copy.
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        let target = url.resolvingSymlinksInPath()
        // Warn before opening a large file, unless it is already open (then it is only brought to the front).
        if document(for: target) == nil,
           let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }).map(Int64.init),
           size > largeFileWarningSize,
           !confirmLargeFile(target, size) {
            completionHandler(nil, false, CocoaError(.userCancelled))
            return
        }
        super.openDocument(withContentsOf: target, display: displayDocument, completionHandler: completionHandler)
    }

    override var currentDocument: NSDocument? {
        return (NSApp.mainWindow?.windowController as? EditorWindowController)?.selectedPane?.document
    }

    /// How failures from `open(_:)` are reported; replaceable so tests are not blocked by an app-modal alert.
    var errorPresenter: (Error) -> Void = { NSApp.presentError($0) }

    func open(_ url: URL) {
        openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            // Declining a prompt (such as the large file warning) is not an error to report.
            if let error = error, (error as? CocoaError)?.code != .userCancelled { self?.errorPresenter(error) }
        }
    }

    /// When the user turned off close confirmation, unsaved changes are discarded without asking.
    func discardChangesIfNotConfirming(_ documents: [NSDocument]) {
        guard !defaults.bool(forKey: Pref.confirmClose) else { return }
        documents.forEach { $0.updateChangeCount(.changeCleared) }
    }

    override func reviewUnsavedDocuments(withAlertTitle title: String?, cancellable: Bool, delegate: Any?, didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        discardChangesIfNotConfirming(documents)
        super.reviewUnsavedDocuments(withAlertTitle: title, cancellable: cancellable, delegate: delegate, didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
    }

    override func closeAllDocuments(withDelegate delegate: Any?, didCloseAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        discardChangesIfNotConfirming(documents)
        super.closeAllDocuments(withDelegate: delegate, didCloseAllSelector: didCloseAllSelector, contextInfo: contextInfo)
    }
}

// MARK: - Document

@objc(TextDocument)
final class TextDocument: NSDocument {
    /// Plain text with LF line endings; the original line ending is restored on save.
    let textStorage = NSTextStorage()
    private var usesCRLF = defaults.integer(forKey: Pref.lineEnding) == 1

    override class var autosavesInPlace: Bool {
        return false
    }

    override var shouldRunSavePanelWithAccessoryView: Bool {
        return false
    }

    /// The window showing this document as a tab. Documents have no window controllers of their own.
    weak var host: EditorWindowController?

    var tabTitle: String {
        return (isDocumentEdited ? "* " : "") + displayName
    }

    override var fileURL: URL? {
        didSet { host?.refreshTitles() }
    }

    override func makeWindowControllers() {}

    override func showWindows() {
        if host == nil { EditorWindowController.front.add(self) }
        host?.select(host?.pane(for: self))
        host?.showWindow(nil)
    }

    // Prompts about this document appear on its window, with its tab selected.
    override var windowForSheet: NSWindow? {
        host?.select(host?.pane(for: self), savingLeftTab: false)
        return host?.window
    }

    override func close() {
        host?.remove(self)
        super.close()
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        host?.refreshTitles()
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        host?.refreshTitles()
    }

    /// With "save on focus lost", a document that has a file is saved when its tab or window loses focus.
    /// Skipped while a sheet (save, close or error prompt) is up, so it never races a prompt.
    func saveIfWanted() {
        guard defaults.bool(forKey: Pref.saveOnFocusLost), fileURL != nil, isDocumentEdited,
              host?.window?.attachedSheet == nil else { return }
        save(nil)
    }

    override func read(from url: URL, ofType typeName: String) throws {
        try read(from: TextDocument.readRegularFile(at: url), ofType: typeName)
    }

    /// Reads a regular file. Directories, FIFOs and devices are rejected: they would fail, or block forever, when read.
    /// The type is checked on the opened descriptor itself (opened non-blocking, so a FIFO cannot hang the open),
    /// so the file cannot be swapped for something else between the check and the read.
    static func readRegularFile(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            let cocoaCode: CocoaError.Code = code == ENOENT ? .fileReadNoSuchFile : code == EACCES || code == EPERM ? .fileReadNoPermission : .fileReadUnknown
            throw CocoaError(cocoaCode, userInfo: [NSURLErrorKey: url, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSURLErrorKey: url,
                NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” is not a regular file and cannot be opened."
            ])
        }
        return try handle.readToEnd() ?? Data()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let raw = TextDocument.decode(data) as NSString
        if raw.range(of: "\r\n").location != NSNotFound {
            usesCRLF = true
        } else if raw.rangeOfCharacter(from: .newlines).location != NSNotFound {
            usesCRLF = false
        }
        // Keep the editor's font and color when reloading a file that changed on disk.
        let attributes = textStorage.length > 0 ? textStorage.attributes(at: 0, effectiveRange: nil) : [:]
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: NSAttributedString(string: TextDocument.normalizeLineEndings(raw), attributes: attributes))
        undoManager?.removeAllActions()
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = TextDocument.normalizeLineEndings(textStorage.mutableString)
        return Data((usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text).utf8)
    }

    static func normalizeLineEndings(_ text: NSString) -> String {
        guard text.rangeOfCharacter(from: CharacterSet(charactersIn: "\r")).location != NSNotFound else { return text as String }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        // UTF-16 only when it decodes losslessly: an odd byte count or broken surrogates would otherwise be
        // silently dropped or replaced, and saving would then destroy the file's contents.
        for (bom, encoding) in [([UInt8](arrayLiteral: 0xFF, 0xFE), String.Encoding.utf16LittleEndian), ([0xFE, 0xFF], .utf16BigEndian)]
        where data.starts(with: bom) {
            let payload = data.dropFirst(2)
            if payload.count % 2 == 0, let text = String(data: payload, encoding: encoding), text.data(using: encoding) == payload {
                return text
            }
        }
        // macOSRoman maps every byte, so it is the final fallback.
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .macOSRoman)
            ?? String(decoding: data, as: UTF8.self)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Allow any extension, or none at all.
        savePanel.allowedContentTypes = []
        savePanel.allowsOtherFileTypes = true
        return true
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        documentController.discardChangesIfNotConfirming([self])
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    // Prints black text on white paper at page width, independent of on-screen zoom, wrap and appearance.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        view.string = textStorage.string
        view.font = editorFont(size: 10)
        view.textColor = .black
        view.drawsBackground = false
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }
}

// MARK: - Editor Window

/// One real window holding any number of documents as in-window tabs. Native window tabs are separate
/// windows to the system (and to tiling window managers), so tabs are drawn inside the window instead.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    /// Open editor windows; a window controller is not retained by anything else.
    private static var all: [EditorWindowController] = []

    private let tabBar = TabBarView()
    private let content = NSView()
    private(set) var panes: [EditorPane] = []
    private(set) var selectedPane: EditorPane?
    /// Pending close prompts. NSDocument does not retain its delegate, and several can be pending at once.
    private(set) var closeRequests: [CloseRequest] = []

    /// The window new tabs open in: the frontmost editor window, or a new one.
    static var front: EditorWindowController {
        return NSApp.orderedWindows.lazy.compactMap { $0.windowController as? EditorWindowController }.first ?? EditorWindowController()
    }

    /// Documents in window and tab order, front window first (minimized windows included).
    static var orderedDocuments: [TextDocument] {
        let windows = NSApp.orderedWindows.compactMap { $0.windowController as? EditorWindowController }
        return windows.flatMap { $0.panes.map { $0.document } }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false   // owned by this controller
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = false
        window.center()
        if let previous = EditorWindowController.all.last?.window {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        }

        super.init(window: window)
        window.delegate = self
        EditorWindowController.all.append(self)

        // Indexes come from the tab bar, which mirrors `panes`; they are still checked, as an out-of-range index would crash.
        tabBar.onSelect = { [weak self] index in
            guard let self = self, self.panes.indices.contains(index) else { return }
            self.select(self.panes[index])
        }
        tabBar.onClose = { [weak self] index in
            guard let self = self, self.panes.indices.contains(index) else { return }
            self.close(self.panes[index].document)
        }
        tabBar.onMove = { [weak self] from, to in
            guard let self = self, self.panes.indices.contains(from), self.panes.indices.contains(to) else { return }
            self.panes.insert(self.panes.remove(at: from), at: to)
            self.refreshTitles()
        }

        let stack = NSStackView(views: [tabBar, content])
        stack.orientation = .vertical
        stack.alignment = .width   // stretch the tab bar across the window
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tabs

    func add(_ document: TextDocument) {
        insert(EditorPane(document: document))
    }

    func pane(for document: NSDocument) -> EditorPane? {
        return panes.first { $0.document === document }
    }

    /// Removes a closed document's tab; the window closes with its last tab.
    func remove(_ document: NSDocument) {
        guard let pane = pane(for: document) else { return }
        take(pane)
        pane.detach()
    }

    /// Shows a tab. Leaving a tab counts as losing focus, unless a prompt is switching tabs (savingLeftTab false),
    /// which avoids a save asking for its own prompt window and switching back.
    func select(_ pane: EditorPane?, savingLeftTab: Bool = true) {
        guard let pane = pane, pane !== selectedPane else { return }
        if let previous = selectedPane {
            previous.removeFromSuperview()
            if savingLeftTab { previous.document.saveIfWanted() }
        }
        selectedPane = pane
        pane.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pane.topAnchor.constraint(equalTo: content.topAnchor),
            pane.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        pane.focus()
        refreshTitles()
    }

    private func insert(_ pane: EditorPane, selecting: Bool = true) {
        panes.append(pane)
        pane.document.host = self
        if selecting { select(pane) } else { refreshTitles() }
    }

    private func take(_ pane: EditorPane) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        panes.remove(at: index)
        if pane === selectedPane {
            pane.removeFromSuperview()
            selectedPane = nil
            if !panes.isEmpty { select(panes[min(index, panes.count - 1)]) }
        }
        if panes.isEmpty { window?.close() } else { refreshTitles() }
    }

    /// Unsaved documents get an asterisk in the window and tab title, including untitled ones.
    func refreshTitles() {
        tabBar.isHidden = panes.count < 2
        tabBar.update(titles: panes.map { $0.document.tabTitle }, selected: panes.firstIndex { $0 === selectedPane })
        guard let window = window, let document = selectedPane?.document else { return }
        let title = document.tabTitle
        if window.title != title { window.title = title }
        if window.representedURL != document.fileURL { window.representedURL = document.fileURL }
        if window.isDocumentEdited != document.isDocumentEdited { window.isDocumentEdited = document.isDocumentEdited }
    }

    /// Asks to save if needed, then closes the document (which removes its tab).
    private func close(_ document: NSDocument, then completion: ((Bool) -> Void)? = nil) {
        let request = CloseRequest { shouldClose in
            if shouldClose { document.close() }
            completion?(shouldClose)
        }
        request.onFinish = { [weak self] finished in self?.closeRequests.removeAll { $0 === finished } }
        closeRequests.append(request)
        document.canClose(withDelegate: request, shouldClose: #selector(CloseRequest.document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    private func closeAllTabs() {
        guard let pane = selectedPane ?? panes.last else { return }
        close(pane.document) { [weak self] closed in
            if closed { self?.closeAllTabs() }
        }
    }

    // MARK: - Tab Actions

    @objc func closeTab(_ sender: Any?) {
        if let pane = selectedPane { close(pane.document) }
    }

    @objc func showNextTab(_ sender: Any?) {
        selectTab(offset: 1)
    }

    @objc func showPreviousTab(_ sender: Any?) {
        selectTab(offset: -1)
    }

    private func selectTab(offset: Int) {
        guard let index = panes.firstIndex(where: { $0 === selectedPane }) else { return }
        select(panes[(index + offset + panes.count) % panes.count])
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        guard panes.count > 1, let pane = selectedPane else { return }
        let target = EditorWindowController()
        take(pane)
        target.insert(pane)
        target.showWindow(nil)
    }

    /// Brings every other window's tabs into this one, keeping the current tab selected
    /// (selecting each merged tab in turn would swap views, and save on focus loss, once per tab).
    @objc func mergeAllWindows(_ sender: Any?) {
        for other in EditorWindowController.all where other !== self {
            for pane in other.panes {
                other.take(pane)
                insert(pane, selecting: selectedPane == nil)
            }
        }
    }

    // MARK: - Window Delegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        // Route edits through the document's undo manager so NSDocument tracks unsaved changes.
        return selectedPane?.document.undoManager
    }

    /// The close button closes every tab in the window, asking about each unsaved one.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeAllTabs()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        selectedPane?.document.saveIfWanted()
    }

    func windowWillClose(_ notification: Notification) {
        panes.forEach { $0.detach() }
        // Release this controller only after AppKit has finished closing the window.
        DispatchQueue.main.async { EditorWindowController.all.removeAll { $0 === self } }
    }
}

extension EditorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)), #selector(moveTabToNewWindow(_:)):
            return panes.count > 1
        case #selector(mergeAllWindows(_:)):
            return EditorWindowController.all.count > 1
        default:
            return true
        }
    }
}

/// Bridges NSDocument's selector-based close callback to a closure.
final class CloseRequest: NSObject {
    private let completion: (Bool) -> Void
    /// Called after the completion, so the owner can release this request.
    var onFinish: ((CloseRequest) -> Void)?

    init(_ completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        completion(shouldClose)
        onFinish?(self)
    }
}

// MARK: - Editor Pane

/// The editor for one document in one tab: text view, line numbers and search bar.
/// Its caret, undo history (the document's), zoom, wrap and search state are independent of other tabs.
final class EditorPane: NSView {
    let document: TextDocument
    let textView: EditorTextView
    private let scrollView = NSScrollView()
    private let searchBar = SearchBarView()
    private let lineNumberRuler: LineNumberRuler

    private var fontSize = NSFont.systemFontSize
    private var wrapsLines = defaults.bool(forKey: Pref.wordWrap)
    private var matches: [NSRange] = []
    private var matchesAreStale = false

    init(document: TextDocument) {
        self.document = document
        // Explicit TextKit 1 stack; non-contiguous layout keeps large files responsive.
        let layoutManager = InvisiblesLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        document.textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textView = EditorTextView(frame: .zero, textContainer: textContainer)
        lineNumberRuler = LineNumberRuler(scrollView: scrollView, textView: textView)

        super.init(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        setupViews()
        applyWordWrap()
        applySettings()
        NotificationCenter.default.addObserver(self, selector: #selector(applySettings), name: UserDefaults.didChangeNotification, object: nil)
        // Any change to the text (typing, undo, Revert to Saved, reloading a file changed on disk) makes the
        // search matches stale; edits that bypass the text view would otherwise leave Replace acting on old ranges.
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidChange), name: NSTextStorage.didProcessEditingNotification, object: document.textStorage)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func textStorageDidChange() {
        guard document.textStorage.editedMask.contains(.editedCharacters), !searchBar.isHidden else { return }
        scheduleMatchRefresh()
    }

    private func setupViews() {
        let containerStackView = NSStackView()
        containerStackView.spacing = 0
        containerStackView.orientation = .vertical
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(containerStackView)
        NSLayoutConstraint.activate([
            containerStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerStackView.topAnchor.constraint(equalTo: topAnchor),
            containerStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Search Bar Setup
        searchBar.isHidden = true
        searchBar.onQueryChanged = { [weak self] in self?.searchQueryChanged() }
        searchBar.onNext = { [weak self] in self?.selectMatch(forward: true) }
        searchBar.onPrevious = { [weak self] in self?.selectMatch(forward: false) }
        searchBar.onReplace = { [weak self] in self?.replaceCurrentMatch() }
        searchBar.onReplaceAll = { [weak self] in self?.replaceAllMatches() }
        searchBar.onClose = { [weak self] in self?.hideSearchBar() }
        containerStackView.addArrangedSubview(searchBar)

        // Text View Setup
        scrollView.hasVerticalScroller = true
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.hasVerticalRuler = true

        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textColor = NSColor.textColor
        textView.delegate = self
        applyFont()

        scrollView.documentView = textView
        containerStackView.addArrangedSubview(scrollView)
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }

    /// The pane is going away; detach its layout manager from the document's storage.
    func detach() {
        if let layoutManager = textView.layoutManager {
            layoutManager.textStorage?.removeLayoutManager(layoutManager)
        }
    }

    // Document actions (Save, Print, …) are answered by this tab's document.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        return document.responds(to: action) ? document : super.supplementalTarget(forAction: action, sender: sender)
    }

    // MARK: - Display

    @objc private func applySettings() {
        let showInvisibles = defaults.bool(forKey: Pref.showInvisibles)
        if let layoutManager = textView.layoutManager as? InvisiblesLayoutManager, layoutManager.showsInvisibles != showInvisibles {
            layoutManager.showsInvisibles = showInvisibles
            textView.needsDisplay = true
        }
        let showLineNumbers = defaults.bool(forKey: Pref.showLineNumbers)
        if scrollView.rulersVisible != showLineNumbers {
            scrollView.rulersVisible = showLineNumbers
        }
    }

    private func applyFont() {
        let font = editorFont(size: fontSize)
        textView.font = font
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        (textView.layoutManager as? InvisiblesLayoutManager)?.font = font
        lineNumberRuler.textFontDidChange()
    }

    private func applyWordWrap() {
        guard let textContainer = textView.textContainer else { return }
        scrollView.hasHorizontalScroller = !wrapsLines
        textView.isHorizontallyResizable = !wrapsLines
        textContainer.widthTracksTextView = wrapsLines
        if wrapsLines {
            textView.autoresizingMask = [.width]
            textView.frame.size.width = scrollView.contentSize.width
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.autoresizingMask = []
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    // MARK: - Search Logic

    private var searchOptions: NSString.CompareOptions {
        return searchBar.isCaseSensitive ? [.literal] : [.literal, .caseInsensitive]
    }

    /// Recomputes every match of the current query; the text view draws the highlights.
    @objc private func refreshMatches() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshMatches), object: nil)
        matchesAreStale = false
        matches = []

        let query = searchBar.query
        if !searchBar.isHidden && !query.isEmpty, let text = textView.textStorage?.string as NSString? {
            var searchRange = NSRange(location: 0, length: text.length)
            while true {
                let range = text.range(of: query, options: searchOptions, range: searchRange)
                if range.location == NSNotFound || range.length == 0 { break }
                matches.append(range)
                searchRange = NSRange(location: NSMaxRange(range), length: text.length - NSMaxRange(range))
            }
        }
        textView.findHighlights = matches
        updateMatchStatus()
    }

    /// Edits only schedule a rescan, so typing in a large document stays fast while the search bar is open.
    private func scheduleMatchRefresh() {
        matchesAreStale = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshMatches), object: nil)
        perform(#selector(refreshMatches), with: nil, afterDelay: 0.15)
    }

    private func refreshMatchesIfStale() {
        if matchesAreStale { refreshMatches() }
    }

    private func updateMatchStatus() {
        let selection = textView.selectedRange()
        let index = matches.firstIndex(endingAfter: selection.location)
        if searchBar.query.isEmpty {
            searchBar.status = ""
        } else if matches.isEmpty {
            searchBar.status = "No matches"
        } else if index < matches.count && matches[index] == selection {
            searchBar.status = "\(index + 1) of \(matches.count)"
        } else {
            searchBar.status = matches.count == 1 ? "1 match" : "\(matches.count) matches"
        }
    }

    private func searchQueryChanged() {
        refreshMatches()
        guard !matches.isEmpty else { return }
        let index = matches.firstIndex(endingAfter: textView.selectedRange().location)
        select(index < matches.count ? matches[index] : matches[0])
    }

    private func selectMatch(forward: Bool) {
        guard !searchBar.isHidden, !searchBar.query.isEmpty else {
            showFind(nil)
            return
        }
        refreshMatchesIfStale()
        guard !matches.isEmpty else {
            NSSound.beep()
            return
        }
        let selection = textView.selectedRange()
        let match: NSRange
        if forward {
            let index = matches.firstIndex(endingAfter: NSMaxRange(selection))
            match = index < matches.count ? matches[index] : matches[0]
        } else {
            let index = matches.firstIndex(endingAfter: selection.location) - 1
            match = index >= 0 ? matches[index] : matches[matches.count - 1]
        }
        select(match)
    }

    private func select(_ range: NSRange) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        updateMatchStatus()
    }

    private func replaceCurrentMatch() {
        refreshMatchesIfStale()
        let selection = textView.selectedRange()
        let replacement = searchBar.replacement
        let index = matches.firstIndex(endingAfter: selection.location)
        let text = document.textStorage.mutableString
        if index < matches.count, matches[index] == selection, NSMaxRange(selection) <= text.length,
           text.compare(searchBar.query, options: searchOptions, range: selection) == .orderedSame,
           textView.shouldChangeText(in: selection, replacementString: replacement) {
            textView.replaceCharacters(in: selection, with: replacement)
            textView.didChangeText()
            // Continue after the inserted text so a replacement containing the query is not matched again.
            textView.setSelectedRange(NSRange(location: selection.location + (replacement as NSString).length, length: 0))
        }
        selectMatch(forward: true)
    }

    private func replaceAllMatches() {
        guard let storage = textView.textStorage, !searchBar.query.isEmpty else { return }
        let contents = NSMutableString(string: storage.mutableString)
        let count = contents.replaceOccurrences(of: searchBar.query, with: searchBar.replacement, options: searchOptions, range: NSRange(location: 0, length: contents.length))
        guard count > 0 else { return NSSound.beep() }

        let fullRange = NSRange(location: 0, length: storage.length)
        let caret = textView.selectedRange().location
        if textView.shouldChangeText(in: fullRange, replacementString: contents as String) {
            textView.replaceCharacters(in: fullRange, with: contents as String)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: min(caret, contents.length), length: 0))
        }
        refreshMatches()
        searchBar.status = "Replaced \(count)"
    }

    private func hideSearchBar() {
        searchBar.isHidden = true
        refreshMatches()
        window?.makeFirstResponder(textView)
    }

    // MARK: - Actions

    @objc func showFind(_ sender: Any?) {
        searchBar.isHidden = false
        refreshMatches()
        searchBar.focusFindField()
    }

    @objc func showReplace(_ sender: Any?) {
        showFind(sender)
        searchBar.focusReplaceField()
    }

    @objc func findNext(_ sender: Any?) {
        selectMatch(forward: true)
    }

    @objc func findPrevious(_ sender: Any?) {
        selectMatch(forward: false)
    }

    @objc func goToLine(_ sender: Any?) {
        guard let window = window else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line number"
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn, let line = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), line > 0 else { return }
            moveCaret(toLine: line)
            window.makeFirstResponder(textView)
        }
    }

    /// Places the caret at the start of a 1-based line, or at the end of the text if it has fewer lines.
    func moveCaret(toLine line: Int) {
        guard let text = textView.textStorage?.string as NSString? else { return }
        var location = 0
        var current = 1
        while current < line && location < text.length {
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
            current += 1
        }
        let range = NSRange(location: location, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    @objc func toggleWordWrap(_ sender: Any?) {
        wrapsLines.toggle()
        applyWordWrap()
    }

    @objc func zoomIn(_ sender: Any?) {
        fontSize = min(fontSize + 1, 72)
        applyFont()
    }

    @objc func zoomOut(_ sender: Any?) {
        fontSize = max(fontSize - 1, 6)
        applyFont()
    }

    @objc func resetZoom(_ sender: Any?) {
        fontSize = NSFont.systemFontSize
        applyFont()
    }
}

// MARK: - Menu Validation

extension EditorPane: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleWordWrap(_:)):
            menuItem.state = wrapsLines ? .on : .off
        case #selector(zoomIn(_:)):
            return fontSize < 72
        case #selector(zoomOut(_:)):
            return fontSize > 6
        default:
            break
        }
        return true
    }
}

// MARK: - TextView Delegate Operations

extension EditorPane: NSTextViewDelegate {
    // Keep the buffer LF-only (the document's model): pasted or dropped CR/CRLF is converted on the way in.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text = text as NSString?, text.rangeOfCharacter(from: CharacterSet(charactersIn: "\r")).location != NSNotFound else { return true }
        textView.insertText(TextDocument.normalizeLineEndings(text), replacementRange: range)
        return false
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !searchBar.isHidden { updateMatchStatus() }
    }
}

// MARK: - Custom Views

extension Array where Element == NSRange {
    /// Index of the first range ending after location, for sorted, non-overlapping ranges.
    func firstIndex(endingAfter location: Int) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(self[mid]) > location { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

final class EditorTextView: NSTextView {
    private static let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    /// Sorted search matches. Only the ones in the dirty rect are drawn, so huge match counts stay cheap.
    var findHighlights: [NSRange] = [] {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard !findHighlights.isEmpty, let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let origin = textContainerOrigin
        let length = textStorage?.length ?? 0
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let visible = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        NSColor.systemYellow.withAlphaComponent(0.4).setFill()
        var index = findHighlights.firstIndex(endingAfter: visible.location)
        // Matches may briefly lag behind edits until the next rescan; skip any that no longer fit.
        while index < findHighlights.count, findHighlights[index].location < NSMaxRange(visible), NSMaxRange(findHighlights[index]) <= length {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: findHighlights[index], actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { highlight, _ in
                highlight.offsetBy(dx: origin.x, dy: origin.y).fill()
            }
            index += 1
        }
    }

    // NSTextView re-registers drag types itself, so extend its list instead of registering once.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        return super.acceptableDragTypes + [.fileURL]
    }

    private func carriesFiles(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: EditorTextView.fileURLOptions)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return carriesFiles(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return carriesFiles(sender) ? .copy : super.draggingUpdated(sender)
    }

    // Dropped files open as documents; dragged text is handled by NSTextView.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: EditorTextView.fileURLOptions) as? [URL],
              !urls.isEmpty else {
            return super.performDragOperation(sender)
        }
        urls.forEach(documentController.open)
        return true
    }
}

/// In-window tab bar: tabs share the full width equally down to a minimum width, then the bar scrolls.
/// Click to select, × or middle-click to close, drag to reorder.
final class TabBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onMove: ((Int, Int) -> Void)?
    private static let minimumTabWidth: CGFloat = 120
    private let scrollView = NSScrollView()
    private let strip = TabStripView()
    private var tabs: [TabItemView] = []
    private var draggedIndex: Int?
    /// The tab a middle button press started on; releasing over the same tab closes it.
    private var middlePressedIndex: Int?
    /// After closing a tab with its ×, tabs keep their width until the pointer leaves the bar,
    /// so a neighbouring tab's × slides under the pointer and repeated clicks keep closing tabs.
    private var frozenTabWidth: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = strip
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
        strip.onMouseDown = { [weak self] event in self?.startDrag(event) }
        strip.onMouseDragged = { [weak self] event in self?.continueDrag(event) }
        strip.onOtherMouseDown = { [weak self] event in self?.middlePress(event) }
        strip.onOtherMouseUp = { [weak self] event in self?.middleRelease(event) }
        setAccessibilityRole(.tabGroup)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Updates tabs in place (only adding or removing views when the count changes), so a drag survives reordering.
    func update(titles: [String], selected: Int?) {
        if titles.count != tabs.count {   // a drag or middle-click cannot survive tabs appearing or vanishing
            draggedIndex = nil
            middlePressedIndex = nil
        }
        while tabs.count > titles.count {
            tabs.removeLast().removeFromSuperview()
        }
        if titles.count > tabs.count { frozenTabWidth = nil }
        while tabs.count < titles.count {
            let tab = TabItemView()
            tab.onPress = { [weak self, weak tab] in self?.indexAction(tab, self?.onSelect) }
            tab.onClose = { [weak self, weak tab] in
                if let self = self, let tab = tab, let index = self.tabs.firstIndex(of: tab) { self.closeTab(at: index) }
            }
            tabs.append(tab)
            strip.addSubview(tab)
        }
        for (index, tab) in tabs.enumerated() {
            tab.configure(title: titles[index], isSelected: index == selected)
        }
        layoutTabs()
        scrollSelectedTabToVisible()
    }

    private func scrollSelectedTabToVisible() {
        guard frozenTabWidth == nil, let selected = tabs.firstIndex(where: { $0.isSelected }) else { return }
        strip.scrollToVisible(tabs[selected].frame)
    }

    override func layout() {
        super.layout()
        layoutTabs()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseExited(with event: NSEvent) {
        guard frozenTabWidth != nil else { return }
        frozenTabWidth = nil
        layoutTabs()
        scrollSelectedTabToVisible()
    }

    private var tabWidth: CGFloat {
        if let frozen = frozenTabWidth { return frozen }
        let width = scrollView.contentSize.width
        return tabs.isEmpty ? width : max(TabBarView.minimumTabWidth, width / CGFloat(tabs.count))
    }

    private func layoutTabs() {
        let width = tabWidth, height = scrollView.contentSize.height
        let stripWidth = width * CGFloat(tabs.count)
        strip.frame = NSRect(x: 0, y: 0, width: stripWidth, height: height)
        // Never leave empty space on the right while tabs are scrolled out on the left:
        // the rightmost tab stays at the right edge and hidden tabs slide in from the left.
        let clipView = scrollView.contentView
        let maxOffset = max(0, stripWidth - clipView.bounds.width)
        if clipView.bounds.origin.x > maxOffset {
            clipView.scroll(to: NSPoint(x: maxOffset, y: 0))
            scrollView.reflectScrolledClipView(clipView)
        }
        for (index, tab) in tabs.enumerated() {
            tab.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }
    }

    private func indexAction(_ tab: TabItemView?, _ action: ((Int) -> Void)?) {
        if let tab = tab, let index = tabs.firstIndex(of: tab) { action?(index) }
    }

    private func tabIndex(at event: NSEvent) -> Int {
        let x = strip.convert(event.locationInWindow, from: nil).x
        return max(0, min(tabs.count - 1, Int(x / tabWidth)))
    }

    /// The tab under the event, or nil over the empty space a frozen layout leaves after the last tab.
    private func tabUnder(_ event: NSEvent) -> Int? {
        let x = strip.convert(event.locationInWindow, from: nil).x
        guard !tabs.isEmpty, x < tabWidth * CGFloat(tabs.count) else { return nil }
        return tabIndex(at: event)
    }

    /// Middle-click closes a tab, like in browsers: on release, if the pointer is still over the pressed tab.
    private func middlePress(_ event: NSEvent) {
        middlePressedIndex = event.buttonNumber == 2 ? tabUnder(event) : nil
    }

    private func middleRelease(_ event: NSEvent) {
        guard event.buttonNumber == 2, let pressed = middlePressedIndex else { return }
        middlePressedIndex = nil
        if tabUnder(event) == pressed { closeTab(at: pressed) }
    }

    private func closeTab(at index: Int) {
        frozenTabWidth = tabWidth
        onClose?(index)
    }

    /// Every click lands on the strip and is resolved by position. A double-click's second click is then
    /// still handled when, after the first click closed a tab, a different tab's × has moved under the pointer.
    private func startDrag(_ event: NSEvent) {
        let point = strip.convert(event.locationInWindow, from: nil)
        // Ignore clicks on the empty space a frozen layout leaves after the last tab.
        guard !tabs.isEmpty, point.x < tabWidth * CGFloat(tabs.count) else { return }
        let index = tabIndex(at: event)
        if tabs[index].closeButtonContains(strip.convert(point, to: tabs[index])) {
            draggedIndex = nil
            closeTab(at: index)
        } else {
            draggedIndex = index
            onSelect?(index)
        }
    }

    private func continueDrag(_ event: NSEvent) {
        guard let from = draggedIndex, from < tabs.count else { return }
        strip.autoscroll(with: event)
        let to = tabIndex(at: event)
        if to != from {
            onMove?(from, to)
            draggedIndex = to
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

/// The scrolling content of the tab bar; it receives clicks on tabs (outside their close buttons).
final class TabStripView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onOtherMouseDown: ((NSEvent) -> Void)?
    var onOtherMouseUp: ((NSEvent) -> Void)?

    override var isFlipped: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onOtherMouseDown?(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        onOtherMouseUp?(event)
    }
}

final class TabItemView: NSView {
    var onPress: (() -> Void)?
    var onClose: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let closeButton = TabCloseButton()
    private(set) var isSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingMiddle
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.setAccessibilityLabel("Close Tab")
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 1),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Called for every tab whenever any tab's title or the selection changes, so unchanged values are left alone.
    func configure(title: String, isSelected: Bool) {
        if label.stringValue != title {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
        if self.isSelected != isSelected || accessibilityValue() == nil {
            self.isSelected = isSelected
            label.textColor = isSelected ? .labelColor : .secondaryLabelColor
            setAccessibilityValue(isSelected)
            needsDisplay = true
        }
    }

    // All clicks go to the tab strip, which handles closing, selection and dragging by position.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func closeButtonContains(_ point: NSPoint) -> Bool {
        return closeButton.frame.contains(point)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    @objc private func closePressed() {
        onClose?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isSelected {
            NSColor.black.withAlphaComponent(0.07).setFill()
            dirtyRect.fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

/// The tab's × button: dimmed, and drawn in full text color while the pointer is over it.
final class TabCloseButton: NSButton {
    private var isHovered = false {
        didSet { contentTintColor = isHovered ? .labelColor : .secondaryLabelColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentTintColor = .secondaryLabelColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}

/// Draws spaces, tabs and line breaks as dimmed symbols, only for the glyphs being drawn.
final class InvisiblesLayoutManager: NSLayoutManager {
    var showsInvisibles = false
    var font = editorFont(size: NSFont.systemFontSize)
    private static let symbols: [unichar: String] = [0x20: "·", 0x09: "→", 0x0A: "↵"]

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showsInvisibles, let text = textStorage?.mutableString else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dimmedTextColor]
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for index in characters.location..<NSMaxRange(characters) {
            guard let symbol = InvisiblesLayoutManager.symbols[text.character(at: index)] else { continue }
            let glyph = glyphIndexForCharacter(at: index)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
            let location = self.location(forGlyphAt: glyph)
            symbol.draw(at: NSPoint(x: origin.x + line.minX + location.x, y: origin.y + line.minY + location.y - font.ascender), withAttributes: attributes)
        }
    }
}

final class LineNumberRuler: NSRulerView {
    /// Character offset of the start of each line. The buffer is LF-only, so only "\n" starts a line.
    private(set) var lineStarts = [0]
    private var lineStartsAreStale = true
    private var font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        setAccessibilityLabel("Line numbers")
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageEdited(_:)), name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var textView: NSTextView? {
        return clientView as? NSTextView
    }

    func textFontDidChange() {
        let size = max((textView?.font?.pointSize ?? NSFont.systemFontSize) * 0.85, 8)
        font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        updateThickness()
    }

    /// Patches the line table from the edited range instead of rescanning the whole document on every keystroke.
    /// While hidden, the table is just marked stale and rebuilt once when shown again.
    @objc private func textStorageEdited(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        guard !lineStartsAreStale, scrollView?.rulersVisible == true else {
            lineStartsAreStale = true
            return
        }

        let edited = storage.editedRange
        let delta = storage.changeInLength
        let first = firstLine(startingAfter: edited.location)
        let last = firstLine(startingAfter: NSMaxRange(edited) - delta)
        let inserted = newlineOffsets(in: storage.string as NSString, range: edited)
        lineStarts.replaceSubrange(first..<last, with: inserted)
        if delta != 0 {
            lineStarts.withUnsafeMutableBufferPointer { starts in
                for index in (first + inserted.count)..<starts.count { starts[index] += delta }
            }
        }
        if !inserted.isEmpty || first != last {
            DispatchQueue.main.async { [weak self] in self?.updateThickness() }
        }
        needsDisplay = true
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        if lineStartsAreStale { updateThickness() }
    }

    /// Index of the first line that starts after location.
    private func firstLine(startingAfter location: Int) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] > location { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// Offsets just past each "\n" in range, i.e. where the following lines start.
    private func newlineOffsets(in text: NSString, range: NSRange) -> [Int] {
        var starts: [Int] = []
        var buffer = [unichar](repeating: 0, count: Swift.min(range.length, 65_536))
        var offset = range.location
        while offset < NSMaxRange(range) {
            let count = min(buffer.count, NSMaxRange(range) - offset)
            text.getCharacters(&buffer, range: NSRange(location: offset, length: count))
            for index in 0..<count where buffer[index] == 10 {
                starts.append(offset + index + 1)
            }
            offset += count
        }
        return starts
    }

    @objc private func redraw() {
        needsDisplay = true
    }

    private func updateThickness() {
        refreshLineStarts()
        let digits = CGFloat(String(lineStarts.count).count)
        let width = ceil(digits * ("8" as NSString).size(withAttributes: [.font: font]).width + 16)
        if ruleThickness != width { ruleThickness = width }
    }

    private func refreshLineStarts() {
        guard lineStartsAreStale, let text = textView?.textStorage?.string as NSString? else { return }
        lineStartsAreStale = false
        lineStarts = [0] + newlineOffsets(in: text, range: NSRange(location: 0, length: text.length))
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer, let scrollView = scrollView else { return }
        refreshLineStarts()

        let length = textView.textStorage?.length ?? 0
        let origin = textView.textContainerOrigin
        let visibleRect = scrollView.contentView.bounds.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dimmedTextColor]

        // Binary search for the first line starting at or before the top of the visible text.
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= visibleChars.location { low = mid } else { high = mid - 1 }
        }

        for line in low..<lineStarts.count {
            let start = lineStarts[line]
            if start > NSMaxRange(visibleChars) { break }
            let fragment = start < length
                ? layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
                : layoutManager.extraLineFragmentRect
            if fragment.isEmpty { continue }
            let y = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: textView).y
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (fragment.height - size.height) / 2), withAttributes: attributes)
        }
    }
}

final class SearchBarView: NSStackView {

    var onQueryChanged: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let caseSensitiveCheckbox = NSButton(checkboxWithTitle: "Match Case", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    var query: String { return findField.stringValue }
    var replacement: String { return replaceField.stringValue }
    var isCaseSensitive: Bool { return caseSensitiveCheckbox.state == .on }
    var status: String {
        get { return statusLabel.stringValue }
        set { statusLabel.stringValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        setupInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func button(_ title: String, _ action: Selector, image: NSImage? = nil, label: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if let image = image {
            button.image = image
            button.imagePosition = .imageOnly
        }
        button.bezelStyle = .rounded
        if let label = label { button.setAccessibilityLabel(label) }
        return button
    }

    private func setupInterface() {
        orientation = .horizontal
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        findField.placeholderString = "Find"
        findField.setAccessibilityLabel("Find")
        findField.sendsSearchStringImmediately = true
        findField.target = self
        findField.action = #selector(queryChanged)
        findField.delegate = self
        findField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        replaceField.placeholderString = "Replace with"
        replaceField.setAccessibilityLabel("Replace with")
        replaceField.delegate = self
        replaceField.widthAnchor.constraint(equalToConstant: 140).isActive = true

        caseSensitiveCheckbox.target = self
        caseSensitiveCheckbox.action = #selector(queryChanged)

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let closeButton = button("Done", #selector(closePressed))

        [findField,
         button("", #selector(previousPressed), image: NSImage(named: NSImage.goLeftTemplateName), label: "Previous match"),
         button("", #selector(nextPressed), image: NSImage(named: NSImage.goRightTemplateName), label: "Next match"),
         caseSensitiveCheckbox,
         replaceField,
         button("Replace", #selector(replacePressed)),
         button("All", #selector(replaceAllPressed), label: "Replace all"),
         statusLabel,
         NSView(),
         closeButton].forEach(addArrangedSubview)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    func focusFindField() {
        window?.makeFirstResponder(findField)
    }

    func focusReplaceField() {
        window?.makeFirstResponder(replaceField)
    }

    @objc private func queryChanged() { onQueryChanged?() }
    @objc private func previousPressed() { onPrevious?() }
    @objc private func nextPressed() { onNext?() }
    @objc private func replacePressed() { onReplace?() }
    @objc private func replaceAllPressed() { onReplaceAll?() }
    @objc private func closePressed() { onClose?() }
}

extension SearchBarView: NSSearchFieldDelegate {
    // Return = next match, Shift-Return = previous match (Return in the replace field replaces), Escape closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField {
                onReplace?()
            } else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}

// MARK: - Settings Window

final class SettingsWindowController: NSWindowController {
    convenience init() {
        func bound<Control: NSControl>(_ control: Control, _ binding: NSBindingName, _ key: String) -> Control {
            control.bind(binding, to: NSUserDefaultsController.shared, withKeyPath: "values.\(key)", options: nil)
            return control
        }
        func popUp(_ titles: [String]) -> NSPopUpButton {
            let popUp = NSPopUpButton()
            popUp.addItems(withTitles: titles)
            return popUp
        }
        func checkbox(_ title: String) -> NSButton {
            return NSButton(checkboxWithTitle: title, target: nil, action: nil)
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Appearance:"), bound(popUp(["System", "Light", "Dark"]), .selectedIndex, Pref.appearance)],
            [NSTextField(labelWithString: "Line endings for new documents:"), bound(popUp(["LF (macOS, Unix)", "CRLF (Windows)"]), .selectedIndex, Pref.lineEnding)],
            [NSGridCell.emptyContentView, bound(checkbox("Wrap lines in new windows"), .value, Pref.wordWrap)],
            [NSGridCell.emptyContentView, bound(checkbox("Restore previous session"), .value, Pref.restoreSession)],
            [NSGridCell.emptyContentView, bound(checkbox("Confirm before closing unsaved documents"), .value, Pref.confirmClose)],
            [NSGridCell.emptyContentView, bound(checkbox("Save documents when their window loses focus"), .value, Pref.saveOnFocusLost)]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.tabbingMode = .disallowed
        window.contentView = contentView
        window.setContentSize(contentView.fittingSize)
        window.center()
        self.init(window: window)
    }
}
