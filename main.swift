import AppKit

// MARK: - Main Application Entry Point

let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Main Application Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    // Lazy so files delivered via openFiles before launch finishes still have a window.
    private lazy var windowController = MainWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        setupMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if windowController.window?.attachedSheet != nil { return .terminateCancel }
        guard windowController.isDirty else { return .terminateNow }
        windowController.resolveUnsavedChanges { proceed in
            NSApp.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let firstFile = filenames.first, windowController.window?.attachedSheet == nil {
            windowController.handleFileOpen(url: URL(fileURLWithPath: firstFile))
            NSApp.reply(toOpenOrPrint: .success)
        } else {
            NSApp.reply(toOpenOrPrint: .failure)
        }
    }

    // MARK: - Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Minimal Notepad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        // File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New File", action: #selector(MainWindowController.menuNewFile(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open...", action: #selector(MainWindowController.menuOpenFile(_:)), keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(MainWindowController.menuSaveFile(_:)), keyEquivalent: "s"))
        fileMenu.addItem(NSMenuItem(title: "Save As...", action: #selector(MainWindowController.menuSaveAsFile(_:)), keyEquivalent: "S"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Print...", action: #selector(MainWindowController.menuPrintFile(_:)), keyEquivalent: "p"))
        fileMenuItem.submenu = fileMenu

        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        // Find Menu
        let findMenuItem = NSMenuItem()
        mainMenu.addItem(findMenuItem)
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(NSMenuItem(title: "Find...", action: #selector(MainWindowController.menuFind(_:)), keyEquivalent: "f"))
        findMenuItem.submenu = findMenu

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Main Window Controller

class MainWindowController: NSWindowController, NSWindowDelegate {

    // Explicit TextKit 1 stack; non-contiguous layout keeps large files responsive.
    private let textView: DragDropTextView = {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        return DragDropTextView(frame: .zero, textContainer: textContainer)
    }()
    private let searchBar = SearchBarView()

    private var currentURL: URL? {
        didSet { updateWindowTitle() }
    }
    private(set) var isDirty = false {
        didSet {
            window?.isDocumentEdited = isDirty
            updateWindowTitle()
        }
    }

    // Snapshot of the text as last loaded/saved, used to detect undo back to a clean state.
    private var savedText: NSString = ""

    // Live backing store; avoids copying the whole document into a Swift String.
    private var buffer: NSMutableString {
        textView.textStorage!.mutableString
    }

    private func updateWindowTitle() {
        window?.title = (isDirty ? "*" : "") + (currentURL?.lastPathComponent ?? "Untitled")
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()

        // Force window to use light mode styling appearance explicitly
        window.appearance = NSAppearance(named: .aqua)

        self.init(window: window)
        window.delegate = self
        setupViews()
        updateWindowTitle()
    }

    private func setupViews() {
        guard let window = self.window, let contentView = window.contentView else { return }

        let containerStackView = NSStackView()
        containerStackView.spacing = 0
        containerStackView.orientation = .vertical
        containerStackView.alignment = .centerX
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(containerStackView)
        NSLayoutConstraint.activate([
            containerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Search Bar Setup
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.isHidden = true
        searchBar.onSearchTextChanged = { [weak self] query in
            self?.performSearch(query: query)
        }
        searchBar.onReplaceRequested = { [weak self] find, replace in
            self?.performReplace(find: find, replace: replace)
        }
        searchBar.onReplaceAllRequested = { [weak self] find, replace in
            self?.performReplaceAll(find: find, replace: replace)
        }
        searchBar.onCloseRequested = { [weak self] in
            guard let self = self else { return }
            self.searchBar.isHidden = true
            self.window?.makeFirstResponder(self.textView)
        }

        containerStackView.addArrangedSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: containerStackView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: containerStackView.trailingAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: 35)
        ])

        // Text View Setup (TextKit 1)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Lock colors so text stays visible regardless of system appearance
        textView.backgroundColor = NSColor.white
        textView.insertionPointColor = NSColor.black
        textView.font = editorFont
        textView.textColor = NSColor.black
        textView.typingAttributes = [.font: editorFont, .foregroundColor: NSColor.black]

        textView.delegate = self
        textView.onFileDropped = { [weak self] url in
            self?.handleFileOpen(url: url)
        }

        scrollView.documentView = textView
        containerStackView.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerStackView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerStackView.trailingAnchor)
        ])

        window.makeFirstResponder(textView)
    }

    // MARK: - File Handling

    func handleFileOpen(url: URL) {
        resolveUnsavedChanges { [self] proceed in
            if proceed { loadFile(url: url) }
        }
    }

    private func loadFile(url: URL) {
        guard url.isFileURL else { return }
        let resolvedURL = url.resolvingSymlinksInPath()

        do {
            // Reject directories, FIFOs and devices, which would fail or block forever when read.
            guard try resolvedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                showAlert(title: "Cannot Open File", message: "Only regular files can be opened.")
                return
            }
            let text = decode(try Data(contentsOf: resolvedURL))
            textView.string = text
            textView.font = editorFont
            textView.textColor = NSColor.black
            textView.undoManager?.removeAllActions()
            markSaved(url: resolvedURL)
        } catch {
            showAlert(title: "Open Failure", message: error.localizedDescription)
        }
    }

    private func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        // macOSRoman maps every byte, so it is the final fallback.
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .macOSRoman)
            ?? String(decoding: data, as: UTF8.self)
    }

    private func write(to url: URL) -> Bool {
        do {
            try Data(textView.string.utf8).write(to: url, options: .atomic)
            markSaved(url: url)
            return true
        } catch {
            showAlert(title: "Save Failure", message: error.localizedDescription)
            return false
        }
    }

    private func markSaved(url: URL?) {
        savedText = NSString(string: buffer)
        currentURL = url
        isDirty = false
    }

    private func save(as forcePanel: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        if !forcePanel, let url = currentURL {
            completion(write(to: url))
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowsOtherFileTypes = true
        savePanel.beginSheetModal(for: window!) { [self] response in
            guard response == .OK, let url = savePanel.url else { return completion(false) }
            completion(write(to: url))
        }
    }

    /// Calls completion(true) when it is safe to discard the current buffer.
    func resolveUnsavedChanges(completion: @escaping (Bool) -> Void) {
        guard isDirty else { return completion(true) }

        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to the document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window!) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
                save(completion: completion)
            case .alertSecondButtonReturn:
                isDirty = false
                completion(true)
            default:
                completion(false)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: window!, completionHandler: nil)
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchBar.updateMatchLabel(status: "")
            return
        }
        selectMatch(query, from: 0)
    }

    /// Selects the first match at or after location, wrapping around to the start.
    private func selectMatch(_ query: String, from location: Int) {
        let contents = buffer
        let start = min(location, contents.length)
        var range = contents.range(of: query, options: .literal, range: NSRange(location: start, length: contents.length - start))
        if range.location == NSNotFound {
            range = contents.range(of: query, options: .literal)
        }

        if range.location != NSNotFound {
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            searchBar.updateMatchLabel(status: "Match Found")
        } else {
            searchBar.updateMatchLabel(status: "No Matches")
        }
    }

    private func performReplace(find: String, replace: String) {
        guard !find.isEmpty else { return }

        let selectedRange = textView.selectedRange()
        var searchStart = selectedRange.location

        if selectedRange.length > 0,
           buffer.range(of: find, options: [.literal, .anchored], range: selectedRange) == selectedRange,
           textView.shouldChangeText(in: selectedRange, replacementString: replace) {
            textView.replaceCharacters(in: selectedRange, with: replace)
            textView.didChangeText()
            // Continue after the inserted text so a replacement containing the query is not matched again.
            searchStart = selectedRange.location + (replace as NSString).length
        }

        selectMatch(find, from: searchStart)
    }

    private func performReplaceAll(find: String, replace: String) {
        guard !find.isEmpty else { return }

        let contents = NSMutableString(string: buffer)
        let occurrencesCount = contents.replaceOccurrences(of: find, with: replace, options: .literal, range: NSRange(location: 0, length: contents.length))

        if occurrencesCount > 0 {
            let fullRange = NSRange(location: 0, length: buffer.length)
            if textView.shouldChangeText(in: fullRange, replacementString: contents as String) {
                textView.replaceCharacters(in: fullRange, with: contents as String)
                textView.didChangeText()
            }
            searchBar.updateMatchLabel(status: "Replaced \(occurrencesCount)")
        } else {
            searchBar.updateMatchLabel(status: "No Matches")
        }
    }

    // MARK: - Actions

    @objc func menuNewFile(_ sender: Any?) {
        resolveUnsavedChanges { [self] proceed in
            guard proceed else { return }
            textView.string = ""
            textView.undoManager?.removeAllActions()
            markSaved(url: nil)
        }
    }

    @objc func menuOpenFile(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        openPanel.beginSheetModal(for: window!) { [self] response in
            if response == .OK, let url = openPanel.url {
                handleFileOpen(url: url)
            }
        }
    }

    @objc func menuSaveFile(_ sender: Any?) {
        save()
    }

    @objc func menuSaveAsFile(_ sender: Any?) {
        save(as: true)
    }

    @objc func menuFind(_ sender: Any?) {
        searchBar.isHidden = false
        searchBar.focusSearchField()
    }

    @objc func menuPrintFile(_ sender: Any?) {
        NSPrintOperation(view: textView).runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty else { return true }
        resolveUnsavedChanges { proceed in
            if proceed { sender.close() }
        }
        return false
    }
}

// MARK: - Menu Validation

extension MainWindowController: NSMenuItemValidation {
    // Disable file actions while a sheet is up so prompts and panels cannot stack.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return window?.attachedSheet == nil
    }
}

// MARK: - TextView Delegate Operations

extension MainWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        // Length check first keeps typing O(1); full compare only when lengths match.
        let current = buffer
        isDirty = current.length != savedText.length || !current.isEqual(to: savedText as String)
    }
}

// MARK: - Custom Views

class DragDropTextView: NSTextView {
    var onFileDropped: ((URL) -> Void)?

    private static let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    // NSTextView re-registers drag types itself, so extend its list instead of registering once.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        return super.acceptableDragTypes + [.fileURL]
    }

    private func carriesFile(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: Self.fileURLOptions)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return carriesFile(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return carriesFile(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: Self.fileURLOptions)?.first as? URL else {
            return super.performDragOperation(sender)
        }
        onFileDropped?(url)
        return true
    }
}

class SearchBarView: NSView {

    var onSearchTextChanged: ((String) -> Void)?
    var onReplaceRequested: ((String, String) -> Void)?
    var onReplaceAllRequested: ((String, String) -> Void)?
    var onCloseRequested: (() -> Void)?

    private let searchField = NSTextField(string: "")
    private let replaceField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let borderLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupInterface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInterface()
    }

    override func layout() {
        super.layout()
        // Keep the bottom border spanning the full width on resize
        borderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    private func setupInterface() {
        wantsLayer = true
        appearance = NSAppearance(named: .aqua)
        layer?.backgroundColor = NSColor.white.cgColor

        borderLayer.backgroundColor = NSColor.separatorColor.cgColor
        layer?.addSublayer(borderLayer)

        searchField.placeholderString = "Find"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self

        replaceField.placeholderString = "Replace with"
        replaceField.translatesAutoresizingMaskIntoConstraints = false

        let replaceBtn = NSButton(title: "Replace", target: self, action: #selector(btnReplacePressed))
        replaceBtn.translatesAutoresizingMaskIntoConstraints = false

        let replaceAllBtn = NSButton(title: "All", target: self, action: #selector(btnReplaceAllPressed))
        replaceAllBtn.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor

        let closeBtn = NSButton(title: "✕", target: self, action: #selector(btnClosePressed))
        closeBtn.isBordered = false
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(replaceField)
        addSubview(replaceBtn)
        addSubview(replaceAllBtn)
        addSubview(statusLabel)
        addSubview(closeBtn)

        NSLayoutConstraint.activate([
            closeBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),

            searchField.leadingAnchor.constraint(equalTo: closeBtn.trailingAnchor, constant: 4),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 160),

            replaceField.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            replaceField.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceField.widthAnchor.constraint(equalToConstant: 140),

            replaceBtn.leadingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: 4),
            replaceBtn.centerYAnchor.constraint(equalTo: centerYAnchor),

            replaceAllBtn.leadingAnchor.constraint(equalTo: replaceBtn.trailingAnchor, constant: 2),
            replaceAllBtn.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: replaceAllBtn.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    func updateMatchLabel(status: String) {
        statusLabel.stringValue = status
    }

    @objc private func btnReplacePressed() {
        onReplaceRequested?(searchField.stringValue, replaceField.stringValue)
    }

    @objc private func btnReplaceAllPressed() {
        onReplaceAllRequested?(searchField.stringValue, replaceField.stringValue)
    }

    @objc private func btnClosePressed() {
        onCloseRequested?()
    }
}

extension SearchBarView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onSearchTextChanged?(searchField.stringValue)
    }
}
