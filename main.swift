import AppKit
import UniformTypeIdentifiers

// MARK: - Main Application Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Main Application Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        
        let controller = MainWindowController()
        controller.showWindow(nil)
        self.windowController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let windowController = windowController, windowController.isDirty {
            windowController.promptForUnsavedChanges { proceed in
                if proceed {
                    NSApp.reply(toApplicationShouldTerminate: true)
                } else {
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        }
        return .terminateNow
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let firstFile = filenames.first else { return }
        let url = URL(fileURLWithPath: firstFile)
        
        if let windowController = windowController {
            windowController.handleFileOpen(url: url)
        }
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    // MARK: - Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Minimal Notepad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New File", action: #selector(MainWindowController.menuNewFile(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open...", action: #selector(MainWindowController.menuOpenFile(_:)), keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(MainWindowController.menuSaveFile(_:)), keyEquivalent: "s"))
        fileMenu.addItem(NSMenuItem(title: "Save As...", action: #selector(MainWindowController.menuSaveAsFile(_:)), keyEquivalent: "S"))
        fileMenuItem.submenu = fileMenu
        
        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSTextView.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSTextView.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSTextView.selectAll(_:)), keyEquivalent: "a"))
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
    
    var textView: NSTextView!
    var searchBar: SearchBarView!
    var containerStackView: NSStackView!
    
    var currentURL: URL?
    var isDirty = false {
        didSet {
            self.window?.isDocumentEdited = isDirty
        }
    }
    
    private var baseFileString: String = ""

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Untitled"
        
        // Force window to use light mode styling appearance explicitly
        window.appearance = NSAppearance(named: .aqua)
        
        self.init(window: window)
        window.delegate = self
        setupViews()
    }

    private func setupViews() {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        containerStackView = NSStackView()
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
        searchBar = SearchBarView()
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
            self?.searchBar.isHidden = true
            self?.window?.makeFirstResponder(self?.textView)
        }
        
        containerStackView.addArrangedSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: containerStackView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: containerStackView.trailingAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: 35)
        ])
        
        // Text View Setup (TextKit 1 Assembly with solid light visibility tracking controls)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        textView = DragDropTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isIncrementalSearchingEnabled = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // Fix visibility rendering by locking background drawing structures to white
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white
        textView.textColor = NSColor.black
        textView.insertionPointColor = NSColor.black
        
        // Block text system attribution fallback leakage dictionary mutations
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = self
        
        if let dragTextView = textView as? DragDropTextView {
            dragTextView.onFileDropped = { [weak self] url in
                self?.handleFileOpen(url: url)
            }
        }
        
        scrollView.documentView = textView
        containerStackView.addArrangedSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerStackView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerStackView.trailingAnchor)
        ])
        
        window.makeFirstResponder(textView)
    }

    // MARK: - Internal Engine Mechanics

    func handleFileOpen(url: URL) {
        verifyAndProcessFileSwap(targetURL: url) { [weak self] in
            self?.loadPathIntoMemory(url: url)
        }
    }

    private func loadPathIntoMemory(url: URL) {
        let resolvedURL = url.resolvingSymlinksInPath()
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir), isDir.boolValue {
            showNativeAlert(title: "Cannot Open Directory", message: "Folders and directories cannot be opened.")
            return
        }
        
        do {
            let fileData = try Data(contentsOf: resolvedURL)
            let loadedString = decodeBytesWithFallback(fileData)
            
            // Clean mutation of underlying text container string contents
            textView.string = loadedString
            
            // Re-apply light mode attributes across the loaded string buffer to fix invisible rendering
            let range = NSRange(location: 0, length: (loadedString as NSString).length)
            textView.textStorage?.addAttributes([
                .foregroundColor: NSColor.black,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ], range: range)
            
            baseFileString = loadedString
            currentURL = resolvedURL
            isDirty = false
            textView.undoManager?.removeAllActions()
            self.window?.title = resolvedURL.lastPathComponent
        } catch {
            showNativeAlert(title: "Open Failure", message: "An error occurred reading the file resource.")
        }
    }

    private func decodeBytesWithFallback(_ data: Data) -> String {
        var convertedString: NSString?
        let encodingHeuristics: [String.Encoding] = [.utf8, .macOSRoman, .windowsCP1252, .utf16]
        
        for encoding in encodingHeuristics {
            if let string = NSString(data: data, encoding: encoding.rawValue) {
                convertedString = string
                break
            }
        }
        
        if let finalizedString = convertedString {
            return finalizedString as String
        }
        
        return String(decoding: data, as: UTF8.self)
    }

    private func commitTextBufferToDisk(url: URL) {
        let textData = textView.string.data(using: .utf8) ?? Data()
        do {
            try textData.write(to: url, options: .atomic)
            currentURL = url
            baseFileString = textView.string
            isDirty = false
            self.window?.title = url.lastPathComponent
        } catch {
            showNativeAlert(title: "Save Failure", message: "The operation could not be completed on the physical filesystem structure.")
        }
    }

    func verifyAndProcessFileSwap(targetURL: URL?, completion: @escaping () -> Void) {
        if isDirty {
            promptForUnsavedChanges { proceed in
                if proceed { completion() }
            }
        } else {
            completion()
        }
    }

    func promptForUnsavedChanges(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to the document?"
        alert.informativeText = "Your modifications will be permanently discarded if you do not preserve them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        
        guard let window = self.window else {
            let result = alert.runModal()
            handlePromptResult(result: result, completion: completion)
            return
        }
        
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.handlePromptResult(result: response, completion: completion)
        }
    }

    private func handlePromptResult(result: NSApplication.ModalResponse, completion: @escaping (Bool) -> Void) {
        switch result {
        case .alertFirstButtonReturn: // Save
            if let targetURL = currentURL {
                commitTextBufferToDisk(url: targetURL)
                completion(true)
            } else {
                presentNativeSavePanel { [weak self] url in
                    self?.commitTextBufferToDisk(url: url)
                    completion(true)
                } fallback: {
                    completion(false)
                }
            }
        case .alertSecondButtonReturn: // Don't Save
            isDirty = false
            completion(true)
        default: // Cancel
            completion(false)
        }
    }

    private func presentNativeSavePanel(success: @escaping (URL) -> Void, fallback: (() -> Void)? = nil) {
        let savePanel = NSSavePanel()
        savePanel.allowsOtherFileTypes = true
        
        guard let window = self.window else {
            if savePanel.runModal() == .OK, let url = savePanel.url {
                success(url)
            } else {
                fallback?()
            }
            return
        }
        
        savePanel.beginSheetModal(for: window) { response in
            if response == .OK, let url = savePanel.url {
                success(url)
            } else {
                fallback?()
            }
        }
    }

    private func showNativeAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchBar.updateMatchLabel(status: "")
            return
        }
        
        let contents = textView.string as NSString
        let options: NSString.CompareOptions = [.literal]
        let range = contents.range(of: query, options: options)
        
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
        
        let contents = textView.string as NSString
        let selectedRange = textView.selectedRange()
        
        if selectedRange.length > 0 {
            let currentSelectionText = contents.substring(with: selectedRange)
            if currentSelectionText == find {
                if textView.shouldChangeText(in: selectedRange, replacementString: replace) {
                    textView.textStorage?.replaceCharacters(in: selectedRange, with: replace)
                    textView.didChangeText()
                }
            }
        }
        
        let trackingContents = textView.string as NSString
        let currentPosition = textView.selectedRange().location
        let remainderRange = NSRange(location: currentPosition, length: trackingContents.length - currentPosition)
        
        var nextRange = trackingContents.range(of: find, options: .literal, range: remainderRange)
        if nextRange.location == NSNotFound {
            nextRange = trackingContents.range(of: find, options: .literal, range: NSRange(location: 0, length: trackingContents.length))
        }
        
        if nextRange.location != NSNotFound {
            textView.setSelectedRange(nextRange)
            textView.scrollRangeToVisible(nextRange)
            searchBar.updateMatchLabel(status: "Match Found")
        } else {
            searchBar.updateMatchLabel(status: "No Matches")
        }
    }

    private func performReplaceAll(find: String, replace: String) {
        guard !find.isEmpty else { return }
        
        var contents = textView.string
        var occurencesCount = 0
        
        while let range = contents.range(of: find, options: .literal) {
            contents.replaceSubrange(range, with: replace)
            occurencesCount += 1
        }
        
        if occurencesCount > 0 {
            let targetFullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: targetFullRange, replacementString: contents) {
                textView.textStorage?.replaceCharacters(in: targetFullRange, with: contents)
                textView.didChangeText()
            }
            searchBar.updateMatchLabel(status: "Replaced \(occurencesCount)")
        } else {
            searchBar.updateMatchLabel(status: "No Matches")
        }
    }

    // MARK: - Actions

    @objc func menuNewFile(_ sender: Any?) {
        verifyAndProcessFileSwap(targetURL: nil) { [weak self] in
            self?.textView.string = ""
            self?.baseFileString = ""
            self?.currentURL = nil
            self?.isDirty = false
            self?.textView.undoManager?.removeAllActions()
            self?.window?.title = "Untitled"
        }
    }

    @objc func menuOpenFile(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        
        guard let window = self.window else {
            if openPanel.runModal() == .OK, let url = openPanel.url {
                handleFileOpen(url: url)
            }
            return
        }
        
        openPanel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.handleFileOpen(url: url)
            }
        }
    }

    @objc func menuSaveFile(_ sender: Any?) {
        if let targetURL = currentURL {
            commitTextBufferToDisk(url: targetURL)
        } else {
            presentNativeSavePanel { [weak self] url in
                self?.commitTextBufferToDisk(url: url)
            }
        }
    }

    @objc func menuSaveAsFile(_ sender: Any?) {
        presentNativeSavePanel { [weak self] url in
            self?.commitTextBufferToDisk(url: url)
        }
    }

    @objc func menuFind(_ sender: Any?) {
        searchBar.isHidden = false
        searchBar.focusSearchField()
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isDirty {
            promptForUnsavedChanges { proceed in
                if proceed {
                    sender.close()
                }
            }
            return false
        }
        return true
    }
}

// MARK: - TextView Delegate Operations

extension MainWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        isDirty = (textView.string != baseFileString)
        
        // Enforce solid black text attribute mapping across incoming runtime typing sequences
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.addAttributes([
            .foregroundColor: NSColor.black,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        ], range: fullRange)
    }
}

// MARK: - Custom Views

class DragDropTextView: NSTextView {
    var onFileDropped: ((URL) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.availableType(from: [NSPasteboard.PasteboardType.fileURL]) != nil {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let classes = [NSURL.self] as [AnyClass]
        guard let urls = pasteboard.readObjects(forClasses: classes, options: nil) as? [URL],
              let absoluteFirstFile = urls.first else {
            return false
        }
        
        onFileDropped?(absoluteFirstFile)
        return true
    }
}

class SearchBarView: NSView {
    
    var onSearchTextChanged: ((String) -> Void)?
    var onReplaceRequested: ((String, String) -> Void)?
    var onReplaceAllRequested: ((String, String) -> Void)?
    var onCloseRequested: (() -> Void)?
    
    private var searchField: NSTextField!
    private var replaceField: NSTextField!
    private var statusLabel: NSTextField!
    private var borderLayer: CALayer?
    
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
        // Update solid bottom border path frame on window resize layout loops
        borderLayer?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }
    
    override func viewWillDraw() {
        super.viewWillDraw()
        // Enforce solid explicit white background color structure across rendering operations
        layer?.backgroundColor = NSColor.white.cgColor
    }
    
    private func setupInterface() {
        wantsLayer = true
        
        // Enforce explicit white background and aqua appearance for the container layout
        self.appearance = NSAppearance(named: .aqua)
        layer?.backgroundColor = NSColor.white.cgColor
        
        // Add solid dark line border on the bottom of the pane panel view surface
        let bottomBorder = CALayer()
        bottomBorder.backgroundColor = NSColor.separatorColor.cgColor
        layer?.addSublayer(bottomBorder)
        self.borderLayer = bottomBorder
        
        searchField = NSTextField(string: "")
        searchField.placeholderString = "Find"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.textColor = NSColor.black
        searchField.backgroundColor = NSColor.white
        
        replaceField = NSTextField(string: "")
        replaceField.placeholderString = "Replace with"
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.textColor = NSColor.black
        replaceField.backgroundColor = NSColor.white
        
        let replaceBtn = NSButton(title: "Replace", target: self, action: #selector(btnReplacePressed))
        replaceBtn.bezelStyle = .rounded
        replaceBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let replaceAllBtn = NSButton(title: "All", target: self, action: #selector(btnReplaceAllPressed))
        replaceAllBtn.bezelStyle = .rounded
        replaceAllBtn.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.separatorColor
        
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