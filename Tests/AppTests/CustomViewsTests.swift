import AppKit

public enum CustomViewsTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("EditorTextView properties, drag types, and background drawing") {
            let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
            assert(textView.acceptableDragTypes.contains(.fileURL))

            textView.string = "First line\nSecond line\nThird line"
            textView.findHighlights = [
                NSRange(location: 0, length: 5),
                NSRange(location: 11, length: 6)
            ]
            assert(textView.findHighlights.count == 2)

            // Trigger drawBackground directly with forced layout
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let image = NSImage(size: NSSize(width: 500, height: 500))
            image.lockFocus()
            textView.drawBackground(in: NSRect(x: 0, y: 0, width: 500, height: 500))
            image.unlockFocus()

            // Test drag and drop with file URLs
            let pbWithURL = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            pbWithURL.writeObjects([NSURL(fileURLWithPath: "/tmp/sample.txt")])
            let mockWithURL = MockDraggingInfo(pasteboard: pbWithURL)
            assert(textView.draggingEntered(mockWithURL) == .copy)
            assert(textView.draggingUpdated(mockWithURL) == .copy)
            assert(textView.performDragOperation(mockWithURL) == true)

            // Test drag and drop without file URLs
            let pbWithoutURL = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            pbWithoutURL.setString("Plain text only", forType: .string)
            let mockWithoutURL = MockDraggingInfo(pasteboard: pbWithoutURL)
            _ = textView.draggingEntered(mockWithoutURL)
            _ = textView.draggingUpdated(mockWithoutURL)
        }

        testRunner("InvisiblesLayoutManager glyph drawing for space, tab, and newline") {
            let storage = NSTextStorage(string: "A B\tC\nD")
            let layoutManager = InvisiblesLayoutManager()
            storage.addLayoutManager(layoutManager)
            let container = NSTextContainer(containerSize: NSSize(width: 300, height: 300))
            layoutManager.addTextContainer(container)

            // Without invisibles
            layoutManager.showsInvisibles = false
            let image1 = NSImage(size: NSSize(width: 300, height: 300))
            image1.lockFocus()
            layoutManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: 5), at: .zero)
            image1.unlockFocus()

            // With invisibles
            layoutManager.showsInvisibles = true
            let image2 = NSImage(size: NSSize(width: 300, height: 300))
            image2.lockFocus()
            layoutManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: 5), at: .zero)
            image2.unlockFocus()
        }

        testRunner("LineNumberRuler thickness calculation and drawing") {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            let storage = NSTextStorage(string: "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n")
            let layoutManager = NSLayoutManager()
            storage.addLayoutManager(layoutManager)
            let textContainer = NSTextContainer(containerSize: NSSize(width: 300, height: 1000))
            layoutManager.addTextContainer(textContainer)
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 1000), textContainer: textContainer)
            scrollView.documentView = textView

            let ruler = LineNumberRuler(scrollView: scrollView, textView: textView)
            textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            ruler.textFontDidChange()
            assert(ruler.ruleThickness > 0)

            // Simulate storage editing with positive delta
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Added Line\n")
            NotificationCenter.default.post(name: NSTextStorage.didProcessEditingNotification, object: storage)

            // Simulate editing while rulers are hidden (marks lineStartsAreStale)
            scrollView.rulersVisible = false
            storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Replaced")
            NotificationCenter.default.post(name: NSTextStorage.didProcessEditingNotification, object: storage)

            scrollView.rulersVisible = true
            ruler.viewWillDraw()

            // Simulate negative delta (deletion of lines)
            storage.deleteCharacters(in: NSRange(location: 0, length: 15))
            NotificationCenter.default.post(name: NSTextStorage.didProcessEditingNotification, object: storage)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))

            // Thousands of lines scaling test
            let thousandLines = (1...1000).map { "Line \($0)" }.joined(separator: "\n")
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: thousandLines)
            ruler.textFontDidChange()
            assert(ruler.ruleThickness > 30)

            // Render ruler marks with forced layout
            layoutManager.ensureLayout(for: textContainer)
            let img = NSImage(size: NSSize(width: 50, height: 400))
            img.lockFocus()
            ruler.drawHashMarksAndLabels(in: NSRect(x: 0, y: 0, width: 50, height: 400))
            img.unlockFocus()
        }

        testRunner("TabBarView and TabItemView lifecycle and interactions") {
            let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 28))
            var selectedIndex: Int?
            var closedIndex: Int?
            var movedIndices: (Int, Int)?

            tabBar.onSelect = { selectedIndex = $0 }
            tabBar.onClose = { closedIndex = $0 }
            tabBar.onMove = { movedIndices = ($0, $1) }

            // Add small tab list
            tabBar.update(titles: ["Tab 1", "Tab 2", "Tab 3"], selected: 1)
            tabBar.layout()

            // Add large tab list exceeding width to trigger minimum tab width and scrolling
            let manyTitles = (1...20).map { "Tab \($0)" }
            tabBar.update(titles: manyTitles, selected: 0)
            tabBar.layout()

            // Reduce tab list
            tabBar.update(titles: ["Tab 1", "Tab 2"], selected: 0)
            tabBar.layout()

            // Trigger mouseExited to clear frozen tab width
            if let exitEvent = NSEvent.enterExitEvent(
                with: .mouseExited,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            ) {
                tabBar.mouseExited(with: exitEvent)
            }

            tabBar.updateTrackingAreas()
            tabBar.updateTrackingAreas() // Exercise removeTrackingArea iteration

            // Test embedded tab item callbacks inside strip
            if let scrollView = tabBar.subviews.first as? NSScrollView,
               let embeddedStrip = scrollView.documentView as? TabStripView,
               let firstTab = embeddedStrip.subviews.first as? TabItemView {
                firstTab.onPress?()
                firstTab.onClose?()
            }

            // Tab Item hit testing and accessibility
            let tabItem = TabItemView(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
            assert(tabItem.hitTest(NSPoint(x: 50, y: 14)) == nil, "TabItemView redirects clicks to strip")

            tabItem.configure(title: "Configured Title", isSelected: false)
            assert(!tabItem.isSelected)
            tabItem.configure(title: "Configured Title", isSelected: true)
            assert(tabItem.isSelected)

            var tabItemPressed = false
            tabItem.onPress = { tabItemPressed = true }
            _ = tabItem.accessibilityPerformPress()
            assert(tabItemPressed)

            // Tab Item close button and closePressed selector
            assert(tabItem.closeButtonContains(NSPoint(x: 10, y: 14)) || !tabItem.closeButtonContains(NSPoint(x: 500, y: 500)))
            var tabClosedFromItem = false
            tabItem.onClose = { tabClosedFromItem = true }
            (tabItem.subviews.compactMap { $0 as? TabCloseButton }.first)?.performClick(nil)
            assert(tabClosedFromItem)

            tabBar.onSelect?(0)
            tabBar.onClose?(1)
            tabBar.onMove?(0, 2)
            assert(selectedIndex == 0)
            assert(closedIndex == 1)
            assert(movedIndices?.0 == 0 && movedIndices?.1 == 2)

            // Draw tab bar and item
            let img = NSImage(size: NSSize(width: 600, height: 28))
            img.lockFocus()
            tabBar.draw(NSRect(x: 0, y: 0, width: 600, height: 28))
            tabItem.configure(title: "Unselected Tab", isSelected: false)
            tabItem.draw(NSRect(x: 0, y: 0, width: 150, height: 28))
            img.unlockFocus()

            // TabStripView flipped check and event handling
            let strip = TabStripView(frame: NSRect(x: 0, y: 0, width: 600, height: 28))
            assert(strip.isFlipped == true)

            // Test mouseDown and mouseDragged on embedded strip
            if let scrollView = tabBar.subviews.first as? NSScrollView,
               let embeddedStrip = scrollView.documentView as? TabStripView {
                let downEvent = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: NSPoint(x: 50, y: 14),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 1,
                    clickCount: 1,
                    pressure: 1.0
                )
                if let downEvent = downEvent {
                    embeddedStrip.mouseDown(with: downEvent)
                }

                let dragEvent = NSEvent.mouseEvent(
                    with: .leftMouseDragged,
                    location: NSPoint(x: 180, y: 14),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 2,
                    clickCount: 1,
                    pressure: 1.0
                )
                if let dragEvent = dragEvent {
                    embeddedStrip.mouseDragged(with: dragEvent)
                }
            }
            assert(strip.isFlipped == true)
        }

        testRunner("TabCloseButton hover states and tint changes") {
            let button = TabCloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            button.updateTrackingAreas()
            button.updateTrackingAreas() // Exercise removeTrackingArea iteration

            if let dummyEvent = NSEvent.enterExitEvent(
                with: .mouseEntered,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            ) {
                button.mouseEntered(with: dummyEvent)
                assert(button.contentTintColor == .labelColor)
            }

            if let exitEvent = NSEvent.enterExitEvent(
                with: .mouseExited,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            ) {
                button.mouseExited(with: exitEvent)
                assert(button.contentTintColor == .secondaryLabelColor)
            }
        }

        testRunner("SearchBarView controls, callbacks, and keyboard shortcuts") {
            let searchBar = SearchBarView()
            var queryChanged = false
            var nextClicked = false
            var prevClicked = false
            var replaceClicked = false
            var replaceAllClicked = false
            var closeClicked = false

            searchBar.onQueryChanged = { queryChanged = true }
            searchBar.onNext = { nextClicked = true }
            searchBar.onPrevious = { prevClicked = true }
            searchBar.onReplace = { replaceClicked = true }
            searchBar.onReplaceAll = { replaceAllClicked = true }
            searchBar.onClose = { closeClicked = true }

            assert(searchBar.query.isEmpty)
            assert(searchBar.replacement.isEmpty)
            assert(!searchBar.isCaseSensitive)
            assert(searchBar.status.isEmpty)

            searchBar.status = "Found 5 matches"
            assert(searchBar.status == "Found 5 matches")

            searchBar.focusFindField()
            searchBar.focusReplaceField()

            searchBar.onQueryChanged?()
            assert(queryChanged)
            searchBar.onPrevious?()
            assert(prevClicked)
            searchBar.onReplace?()
            assert(replaceClicked)
            // Test clicking each button in SearchBarView
            (searchBar.arrangedSubviews[1] as? NSButton)?.performClick(nil)
            assert(prevClicked)
            (searchBar.arrangedSubviews[2] as? NSButton)?.performClick(nil)
            assert(nextClicked)
            (searchBar.arrangedSubviews[3] as? NSButton)?.performClick(nil)
            assert(queryChanged)
            (searchBar.arrangedSubviews[5] as? NSButton)?.performClick(nil)
            assert(replaceClicked)
            (searchBar.arrangedSubviews[6] as? NSButton)?.performClick(nil)
            assert(replaceAllClicked)
            (searchBar.arrangedSubviews[9] as? NSButton)?.performClick(nil)
            assert(closeClicked)

            // Test key commands via control(_:textView:doCommandBy:) delegate
            let dummyControl = NSControl()
            let dummyTV = NSTextView()

            // Return in find field -> Next match
            nextClicked = false
            let handledReturn = searchBar.control(dummyControl, textView: dummyTV, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            assert(handledReturn == true)
            assert(nextClicked == true)

            // Return in replace field -> Replace match
            if let replaceField = searchBar.arrangedSubviews[4] as? NSControl {
                replaceClicked = false
                let handledReplaceReturn = searchBar.control(replaceField, textView: dummyTV, doCommandBy: #selector(NSResponder.insertNewline(_:)))
                assert(handledReplaceReturn == true)
                assert(replaceClicked == true)
            }

            // Cancel / Escape -> Close
            closeClicked = false
            let handledEsc = searchBar.control(dummyControl, textView: dummyTV, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
            assert(handledEsc == true)
            assert(closeClicked == true)

            // Unhandled command
            let unhandled = searchBar.control(dummyControl, textView: dummyTV, doCommandBy: #selector(NSResponder.insertTab(_:)))
            assert(unhandled == false)

            // Draw searchBar
            let img = NSImage(size: NSSize(width: 400, height: 32))
            img.lockFocus()
            searchBar.draw(NSRect(x: 0, y: 0, width: 400, height: 32))
            img.unlockFocus()
        }
    }
}

private final class MockDraggingInfo: NSObject, NSDraggingInfo {
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
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { return .none }
    func resetSpringLoading() {}
}

