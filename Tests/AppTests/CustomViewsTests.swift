import AppKit

/// Deterministic generator, so a failing randomized test reproduces.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

public enum CustomViewsTests {
    /// Renders a drawing block into a bitmap and returns its raw pixels, for comparing what was drawn.
    static func render(width: Int = 300, height: Int = 100, _ draw: () -> Void) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    static func expectedLineStarts(_ text: String) -> [Int] {
        var starts = [0]
        for (offset, unit) in text.utf16.enumerated() where unit == 10 { starts.append(offset + 1) }
        return starts
    }

    /// A text view in a scroll view with a visible line number ruler, as EditorPane sets it up.
    static func makeRulerSetup(_ text: String) -> (NSTextStorage, LineNumberRuler, NSScrollView, NSTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 1000), textContainer: textContainer)
        textView.font = editorFont(size: 13)
        scrollView.documentView = textView
        let ruler = LineNumberRuler(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        ruler.textFontDidChange()   // builds the line table
        return (storage, ruler, scrollView, textView)
    }

    /// Tab bars stay alive in a window, so mouse event locations convert to view coordinates as in the app.
    static var tabBarWindows: [NSWindow] = []

    static func makeTabBar(_ titles: [String], selected: Int? = 0, width: CGFloat = 600) -> (TabBarView, TabStripView) {
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 28), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tabBar
        tabBarWindows.append(window)
        tabBar.layoutSubtreeIfNeeded()
        tabBar.update(titles: titles, selected: selected)
        let strip = (tabBar.subviews.first as! NSScrollView).documentView as! TabStripView
        strip.subviews.forEach { $0.layoutSubtreeIfNeeded() }   // place each tab's ×, as the window's display pass would
        return (tabBar, strip)
    }

    static func tabFrames(_ strip: TabStripView) -> [NSRect] {
        return strip.subviews.compactMap { ($0 as? TabItemView)?.frame }
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("EditorTextView accepts file drops on top of text drags") {
            let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
            try expect(textView.acceptableDragTypes.contains(.fileURL))
            try expect(textView.acceptableDragTypes.count > 1, "NSTextView's own (text) drag types are kept")
        }

        testRunner("EditorTextView dropping files opens them; failures are reported") {
            let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
            let file = try TestSupport.writeFile("dropped", named: "dropped.txt")
            let missing = file.deletingLastPathComponent().appendingPathComponent("missing.txt")
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            pasteboard.clearContents()
            pasteboard.writeObjects([file as NSURL, missing as NSURL])
            let info = MockDraggingInfo(pasteboard: pasteboard)

            try expectEqual(textView.draggingEntered(info), .copy)
            try expectEqual(textView.draggingUpdated(info), .copy)
            try expect(textView.performDragOperation(info))
            try expect(TestSupport.spin { documentController.documents.contains { $0.fileURL?.path == file.path } }, "the dropped file opens")
            try expect(TestSupport.spin { TestSupport.presentedErrors.count == 1 }, "the missing file is reported")
            try expectEqual(textView.string, "", "a file drop never inserts text")
        }

        testRunner("EditorTextView text drags are left to NSTextView") {
            let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            pasteboard.clearContents()
            pasteboard.setString("Plain text only", forType: .string)
            let info = MockDraggingInfo(pasteboard: pasteboard)
            _ = textView.draggingEntered(info)
            _ = textView.draggingUpdated(info)
            _ = textView.performDragOperation(info)
            try expect(documentController.documents.isEmpty, "no document is opened for a text drag")
            try expect(TestSupport.presentedErrors.isEmpty)
        }

        testRunner("EditorTextView draws find highlights, skipping stale ones past the end") {
            let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            textView.string = "First line\nSecond line"
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let rect = NSRect(x: 0, y: 0, width: 300, height: 100)

            let plain = render { textView.drawBackground(in: rect) }
            textView.findHighlights = [NSRange(location: 0, length: 5), NSRange(location: 11, length: 6)]
            let highlighted = render { textView.drawBackground(in: rect) }
            try expect(plain != highlighted, "highlights are drawn")

            // Matches that no longer fit the text (an edit shortened it before the rescan) are skipped, not drawn or crashed on.
            textView.findHighlights = [NSRange(location: 100, length: 5)]
            let stale = render { textView.drawBackground(in: rect) }
            try expect(stale == plain)

            textView.findHighlights = []
            try expect(render { textView.drawBackground(in: rect) } == plain)
        }

        testRunner("InvisiblesLayoutManager draws symbols only when enabled") {
            let storage = NSTextStorage(string: " \t \n ", attributes: [.font: editorFont(size: 13)])
            let layoutManager = InvisiblesLayoutManager()
            storage.addLayoutManager(layoutManager)
            let container = NSTextContainer(containerSize: NSSize(width: 300, height: 100))
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            let glyphs = layoutManager.glyphRange(for: container)

            layoutManager.showsInvisibles = false
            let hidden = render { layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero) }
            try expect(!hidden.contains { $0 != 0 }, "whitespace alone draws nothing")

            layoutManager.showsInvisibles = true
            let shown = render { layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero) }
            try expect(shown.contains { $0 != 0 }, "spaces, tabs and newlines get symbols")

            // Visible characters only: nothing extra is drawn.
            let letters = NSTextStorage(string: "abc", attributes: [.font: editorFont(size: 13)])
            let lettersManager = InvisiblesLayoutManager()
            letters.addLayoutManager(lettersManager)
            let lettersContainer = NSTextContainer(containerSize: NSSize(width: 300, height: 100))
            lettersManager.addTextContainer(lettersContainer)
            lettersManager.ensureLayout(for: lettersContainer)
            let range = lettersManager.glyphRange(for: lettersContainer)
            lettersManager.showsInvisibles = false
            let off = render { lettersManager.drawGlyphs(forGlyphRange: range, at: .zero) }
            lettersManager.showsInvisibles = true
            try expect(render { lettersManager.drawGlyphs(forGlyphRange: range, at: .zero) } == off)

            // Empty range and detached storage are harmless.
            layoutManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: 0), at: .zero)
            letters.removeLayoutManager(lettersManager)
            lettersManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: 0), at: .zero)
        }

        testRunner("LineNumberRuler builds the line table and widens for more digits") {
            let (storage, ruler, _, _) = makeRulerSetup("a\nb\nc")
            try expectEqual(ruler.lineStarts, [0, 2, 4])
            let narrow = ruler.ruleThickness
            try expect(narrow > 0)

            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: (1...1000).map { "\($0)" }.joined(separator: "\n"))
            TestSupport.drain()   // thickness is updated asynchronously after an edit
            try expectEqual(ruler.lineStarts.count, 1000)
            try expect(ruler.ruleThickness > narrow, "four digits need a wider ruler")

            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
            TestSupport.drain()
            try expectEqual(ruler.lineStarts, [0])
            try expectEqual(ruler.ruleThickness, narrow)
        }

        testRunner("LineNumberRuler incremental line table matches a full rescan after random edits") {
            let (storage, ruler, _, _) = makeRulerSetup("start\n")
            var rng = SeededGenerator(seed: 42)
            let pieces = ["\n", "\n\n", "x", "abc", "a\nb", "\nz\n", "", "ż\n", "😀", "\r\n"]
            for step in 0..<2000 {
                let length = storage.length
                let location = length == 0 ? 0 : Int.random(in: 0...length, using: &rng)
                let deleteLength = Int.random(in: 0...min(6, length - location), using: &rng)
                let insert = pieces.randomElement(using: &rng)!
                if step % 50 == 0 {
                    // Several edits in one editing session are reported as one combined change.
                    storage.beginEditing()
                    storage.replaceCharacters(in: NSRange(location: location, length: deleteLength), with: insert)
                    storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\nq")
                    storage.endEditing()
                } else {
                    storage.replaceCharacters(in: NSRange(location: location, length: deleteLength), with: insert)
                }
                guard ruler.lineStarts == expectedLineStarts(storage.string) else {
                    throw TestFailure(description: "line table diverged at step \(step): \(ruler.lineStarts.prefix(20)) vs \(expectedLineStarts(storage.string).prefix(20))")
                }
            }
            // Attribute-only edits do not touch the table.
            let before = ruler.lineStarts
            storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: storage.length))
            try expectEqual(ruler.lineStarts, before)
        }

        testRunner("LineNumberRuler skips work while hidden and rebuilds when shown") {
            let (storage, ruler, scrollView, _) = makeRulerSetup("a\nb")
            scrollView.rulersVisible = false
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x\ny\nz\n")
            try expectEqual(ruler.lineStarts, [0, 2], "not maintained while hidden")
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "w\n")
            scrollView.rulersVisible = true
            ruler.viewWillDraw()
            try expectEqual(ruler.lineStarts, expectedLineStarts(storage.string))
            // After the rebuild, incremental updates resume.
            storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "\nend")
            try expectEqual(ruler.lineStarts, expectedLineStarts(storage.string))
        }

        testRunner("LineNumberRuler sizes its font from the text font, with a minimum") {
            let (_, ruler, _, textView) = makeRulerSetup("a")
            textView.font = editorFont(size: 40)
            ruler.textFontDidChange()
            let large = ruler.ruleThickness
            textView.font = editorFont(size: 4)
            ruler.textFontDidChange()
            let small = ruler.ruleThickness
            textView.font = editorFont(size: 2)
            ruler.textFontDidChange()
            try expect(large > small)
            try expectEqual(ruler.ruleThickness, small, "below the minimum, the label font stops shrinking")
        }

        testRunner("LineNumberRuler draws visible line labels, including the empty last line") {
            let (storage, ruler, _, textView) = makeRulerSetup((1...50).map { "Line \($0)" }.joined(separator: "\n") + "\n")
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let drawn = render(width: 50, height: 400) { ruler.drawHashMarksAndLabels(in: NSRect(x: 0, y: 0, width: 50, height: 400)) }
            try expect(drawn.contains { $0 != 0 }, "labels are drawn")

            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            _ = render(width: 50, height: 400) { ruler.drawHashMarksAndLabels(in: NSRect(x: 0, y: 0, width: 50, height: 400)) }
        }

        testRunner("TabBarView shares the width equally, down to a minimum, then scrolls") {
            let (tabBar, strip) = makeTabBar(["1", "2", "3"])
            try expectEqual(tabFrames(strip).map { $0.width }, [200, 200, 200])
            try expectEqual(tabFrames(strip).map { $0.minX }, [0, 200, 400])
            try expectEqual(tabBar.accessibilityRole(), .tabGroup)

            tabBar.update(titles: (1...20).map { "Tab \($0)" }, selected: 19)
            try expect(tabFrames(strip).allSatisfy { $0.width == 120 }, "minimum tab width")
            try expectEqual(strip.frame.width, 2400)

            tabBar.update(titles: ["1", "2"], selected: 0)
            try expectEqual(tabFrames(strip).map { $0.width }, [300, 300])
            try expectEqual(strip.subviews.count, 2, "surplus tab views are removed")

            tabBar.update(titles: [], selected: nil)
            try expect(strip.subviews.isEmpty)
        }

        testRunner("TabBarView marks the selected tab and sets titles") {
            let (_, strip) = makeTabBar(["One", "* Two"], selected: 1)
            let tabs = strip.subviews.compactMap { $0 as? TabItemView }
            try expectEqual(tabs.map { $0.isSelected }, [false, true])
            try expectEqual(tabs.map { $0.accessibilityLabel() ?? "" }, ["One", "* Two"])
            try expectEqual(tabs.map { $0.accessibilityRole() }, [.radioButton, .radioButton])
        }

        testRunner("TabBarView click selects, × closes and freezes widths until the pointer leaves") {
            let (tabBar, strip) = makeTabBar(["1", "2", "3"])
            var selected: [Int] = [], closed: [Int] = []
            tabBar.onSelect = { selected.append($0) }
            tabBar.onClose = { closed.append($0) }

            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 300))
            try expectEqual(selected, [1])

            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 212))   // tab 2's ×
            try expectEqual(closed, [1])
            tabBar.update(titles: ["1", "3"], selected: 0)
            try expectEqual(tabFrames(strip).map { $0.width }, [200, 200], "widths stay frozen after closing with ×")

            // The next tab's × is now under the pointer: a second click closes it too.
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 212))
            try expectEqual(closed, [1, 1])
            tabBar.update(titles: ["1"], selected: 0)

            // A click in the empty space the frozen layout leaves is ignored.
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 500))
            try expectEqual(selected, [1])
            try expectEqual(closed, [1, 1])

            tabBar.mouseExited(with: TestSupport.enterExitEvent(.mouseExited))
            try expectEqual(tabFrames(strip).map { $0.width }, [600], "widths recompute when the pointer leaves")
            tabBar.mouseExited(with: TestSupport.enterExitEvent(.mouseExited))   // not frozen: no-op
        }

        testRunner("TabBarView adding a tab unfreezes widths") {
            let (tabBar, strip) = makeTabBar(["1", "2", "3"])
            tabBar.onClose = { _ in }
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 12))
            tabBar.update(titles: ["2", "3"], selected: 0)
            try expectEqual(tabFrames(strip).map { $0.width }, [200, 200])
            tabBar.update(titles: ["2", "3", "4", "5"], selected: 0)
            try expectEqual(tabFrames(strip).map { $0.width }, [150, 150, 150, 150])
        }

        testRunner("TabBarView dragging reorders, and survives tabs vanishing mid-drag") {
            let (tabBar, strip) = makeTabBar(["1", "2", "3"])
            var moves: [[Int]] = []
            tabBar.onSelect = { _ in }
            tabBar.onMove = { moves.append([$0, $1]) }

            // Dragging without a press first does nothing.
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 450))
            try expect(moves.isEmpty)

            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 60))
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 100))
            try expect(moves.isEmpty, "still over the same tab")
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 450))
            try expectEqual(moves, [[0, 2]])
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: -50))
            try expectEqual(moves, [[0, 2], [2, 0]], "positions left of the first tab clamp to it")
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 5000))
            try expectEqual(moves.last, [0, 2], "positions past the last tab clamp to it")

            // A tab closes while dragging the last tab: the stale index must not be used.
            tabBar.update(titles: ["1", "2"], selected: 0)
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 10))
            try expectEqual(moves.count, 3)

            // Pressing a × does not start a drag.
            tabBar.onClose = { _ in }
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 12))
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 450))
            try expectEqual(moves.count, 3)
        }

        testRunner("TabBarView middle-click closes the tab under the pointer on release") {
            let (tabBar, strip) = makeTabBar(["1", "2", "3"])
            var closed: [Int] = [], selected: [Int] = []
            tabBar.onClose = { closed.append($0) }
            tabBar.onSelect = { selected.append($0) }
            func middle(_ type: NSEvent.EventType, _ x: CGFloat, button: Int64 = 2) -> NSEvent {
                return TestSupport.otherMouseEvent(type, button: button, window: strip.window, x: x)
            }
            let probe = middle(.otherMouseDown, 300)
            try expectEqual(probe.buttonNumber, 2)
            try expectEqual(probe.locationInWindow.x, 300, "the test event keeps its position")

            strip.otherMouseDown(with: middle(.otherMouseDown, 300))
            try expect(closed.isEmpty, "nothing closes on press")
            strip.otherMouseUp(with: middle(.otherMouseUp, 350))
            try expectEqual(closed, [1], "released over the same tab: it closes")
            try expect(selected.isEmpty, "middle-click does not select")

            // Like the ×, widths freeze so the next tab slides under the pointer and can be closed the same way.
            tabBar.update(titles: ["1", "3"], selected: 0)
            try expectEqual(tabFrames(strip).map { $0.width }, [200, 200])
            strip.otherMouseDown(with: middle(.otherMouseDown, 300))
            strip.otherMouseUp(with: middle(.otherMouseUp, 300))
            try expectEqual(closed, [1, 1])
            tabBar.update(titles: ["1"], selected: 0)

            // Anywhere on the tab counts, including its ×.
            strip.otherMouseDown(with: middle(.otherMouseDown, 12))
            strip.otherMouseUp(with: middle(.otherMouseUp, 12))
            try expectEqual(closed, [1, 1, 0])
        }

        testRunner("TabBarView middle-click is cancelled by moving off the tab, empty space, other buttons and tab changes") {
            let (tabBar, strip) = makeTabBar(["1", "2", "3"])
            var closed: [Int] = []
            tabBar.onClose = { closed.append($0) }
            func middle(_ type: NSEvent.EventType, _ x: CGFloat, button: Int64 = 2) -> NSEvent {
                return TestSupport.otherMouseEvent(type, button: button, window: strip.window, x: x)
            }

            // Released over another tab.
            strip.otherMouseDown(with: middle(.otherMouseDown, 100))
            strip.otherMouseUp(with: middle(.otherMouseUp, 300))
            try expect(closed.isEmpty)

            // Release without a press, or a second release.
            strip.otherMouseUp(with: middle(.otherMouseUp, 100))
            try expect(closed.isEmpty)

            // Buttons other than the middle one (4th/5th buttons are often Back/Forward).
            strip.otherMouseDown(with: middle(.otherMouseDown, 100, button: 3))
            strip.otherMouseUp(with: middle(.otherMouseUp, 100, button: 3))
            strip.otherMouseDown(with: middle(.otherMouseDown, 100))
            strip.otherMouseUp(with: middle(.otherMouseUp, 100, button: 3))
            try expect(closed.isEmpty)
            strip.otherMouseUp(with: middle(.otherMouseUp, 100))
            try expectEqual(closed, [0], "the middle press is still pending after another button's release")

            // The tab list changes between press and release (a tab closed some other way).
            tabBar.update(titles: ["2", "3"], selected: 0)
            strip.otherMouseDown(with: middle(.otherMouseDown, 100))
            tabBar.update(titles: ["3"], selected: 0)
            strip.otherMouseUp(with: middle(.otherMouseUp, 100))
            try expectEqual(closed, [0])

            // The empty space a frozen layout leaves after the last tab.
            tabBar.mouseExited(with: TestSupport.enterExitEvent(.mouseExited))
            let (frozenBar, frozenStrip) = makeTabBar(["1", "2", "3"])
            var frozenClosed: [Int] = []
            frozenBar.onClose = { frozenClosed.append($0) }
            frozenStrip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: frozenStrip.window, x: 412))
            frozenBar.update(titles: ["1", "2"], selected: 0)
            frozenStrip.otherMouseDown(with: TestSupport.otherMouseEvent(.otherMouseDown, window: frozenStrip.window, x: 500))
            frozenStrip.otherMouseUp(with: TestSupport.otherMouseEvent(.otherMouseUp, window: frozenStrip.window, x: 500))
            try expectEqual(frozenClosed, [2], "only the × click closed a tab")

            // No tabs at all.
            let (emptyBar, emptyStrip) = makeTabBar([])
            emptyBar.onClose = { _ in closed.append(-1) }
            emptyStrip.otherMouseDown(with: TestSupport.otherMouseEvent(.otherMouseDown, window: emptyStrip.window, x: 10))
            emptyStrip.otherMouseUp(with: TestSupport.otherMouseEvent(.otherMouseUp, window: emptyStrip.window, x: 10))
            try expectEqual(closed, [0])
        }

        testRunner("TabBarView middle-click on a tab closes its document in the window") {
            let controller = EditorWindowController()
            let docs = (0..<3).map { _ in TextDocument() }
            docs.forEach(controller.add)
            let tabBar = try unwrap(TestSupport.tabBar(of: controller))
            tabBar.layoutSubtreeIfNeeded()
            let strip = try unwrap((tabBar.subviews.first as? NSScrollView)?.documentView as? TabStripView)
            let window = try unwrap(controller.window)
            let x = tabBar.convert(NSPoint(x: tabFrames(strip)[0].midX, y: 0), to: nil).x
            let y = tabBar.convert(NSPoint(x: 0, y: tabBar.bounds.midY), to: nil).y
            strip.otherMouseDown(with: TestSupport.otherMouseEvent(.otherMouseDown, window: window, x: x, y: y))
            strip.otherMouseUp(with: TestSupport.otherMouseEvent(.otherMouseUp, window: window, x: x, y: y))
            try expect(TestSupport.spin { controller.pane(for: docs[0]) == nil }, "the first tab's document closed")
            try expectEqual(controller.panes.count, 2)
        }

        testRunner("TabBarView with no tabs ignores clicks") {
            let (tabBar, strip) = makeTabBar([])
            var called = false
            tabBar.onSelect = { _ in called = true }
            tabBar.onClose = { _ in called = true }
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, window: strip.window, x: 10))
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, window: strip.window, x: 10))
            try expect(!called)
        }

        testRunner("TabBarView tabs answer accessibility press and their × button") {
            let (tabBar, strip) = makeTabBar(["1", "2"])
            var selected: Int?, closed: Int?
            tabBar.onSelect = { selected = $0 }
            tabBar.onClose = { closed = $0 }
            let tabs = strip.subviews.compactMap { $0 as? TabItemView }
            try expect(tabs[1].accessibilityPerformPress())
            try expectEqual(selected, 1)
            try unwrap(tabs[1].subviews.compactMap { $0 as? TabCloseButton }.first).performClick(nil)
            try expectEqual(closed, 1)
        }

        testRunner("TabBarView tracking areas are replaced, not accumulated") {
            let (tabBar, _) = makeTabBar(["1"])
            tabBar.updateTrackingAreas()
            tabBar.updateTrackingAreas()
            try expectEqual(tabBar.trackingAreas.count, 1)
            let button = TabCloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            button.updateTrackingAreas()
            button.updateTrackingAreas()
            try expectEqual(button.trackingAreas.count, 1)
        }

        testRunner("TabItemView passes clicks to the strip and draws selected and unselected tabs differently") {
            let tab = TabItemView(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
            tab.layoutSubtreeIfNeeded()
            try expect(tab.hitTest(NSPoint(x: 50, y: 14)) == nil)
            try expect(tab.closeButtonContains(NSPoint(x: 10, y: 14)))
            try expect(!tab.closeButtonContains(NSPoint(x: 100, y: 14)))

            tab.configure(title: "T", isSelected: false)
            let unselected = render(width: 150, height: 28) { tab.draw(tab.bounds) }
            tab.configure(title: "T", isSelected: true)
            try expect(tab.isSelected)
            let selectedImage = render(width: 150, height: 28) { tab.draw(tab.bounds) }
            try expect(unselected != selectedImage)
            try expectEqual(tab.accessibilityValue() as? Bool, true)
            tab.configure(title: "T", isSelected: true)   // unchanged selection
            try expect(tab.isSelected)

            let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
            try expect(render(width: 150, height: 28) { bar.draw(bar.bounds) }.contains { $0 != 0 })
        }

        testRunner("TabCloseButton brightens while hovered") {
            let button = TabCloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            try expectEqual(button.contentTintColor, .secondaryLabelColor)
            button.mouseEntered(with: TestSupport.enterExitEvent(.mouseEntered))
            try expectEqual(button.contentTintColor, .labelColor)
            button.mouseExited(with: TestSupport.enterExitEvent(.mouseExited))
            try expectEqual(button.contentTintColor, .secondaryLabelColor)
        }

        testRunner("TabStripView is flipped and forwards mouse events") {
            let strip = TabStripView(frame: NSRect(x: 0, y: 0, width: 100, height: 28))
            try expect(strip.isFlipped)
            var downs = 0, drags = 0, otherDowns = 0, otherUps = 0
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, x: 1))   // no handlers: harmless
            strip.otherMouseDown(with: TestSupport.otherMouseEvent(.otherMouseDown, window: nil, x: 1))
            strip.otherMouseUp(with: TestSupport.otherMouseEvent(.otherMouseUp, window: nil, x: 1))
            strip.onMouseDown = { _ in downs += 1 }
            strip.onMouseDragged = { _ in drags += 1 }
            strip.onOtherMouseDown = { _ in otherDowns += 1 }
            strip.onOtherMouseUp = { _ in otherUps += 1 }
            strip.mouseDown(with: TestSupport.mouseEvent(.leftMouseDown, x: 1))
            strip.mouseDragged(with: TestSupport.mouseEvent(.leftMouseDragged, x: 1))
            strip.otherMouseDown(with: TestSupport.otherMouseEvent(.otherMouseDown, window: nil, x: 1))
            strip.otherMouseUp(with: TestSupport.otherMouseEvent(.otherMouseUp, window: nil, x: 1))
            try expectEqual([downs, drags, otherDowns, otherUps], [1, 1, 1, 1])
        }

        testRunner("SearchBarView controls, buttons and keyboard commands") {
            let searchBar = SearchBarView()
            var calls: [String] = []
            searchBar.onQueryChanged = { calls.append("query") }
            searchBar.onNext = { calls.append("next") }
            searchBar.onPrevious = { calls.append("previous") }
            searchBar.onReplace = { calls.append("replace") }
            searchBar.onReplaceAll = { calls.append("all") }
            searchBar.onClose = { calls.append("close") }

            try expect(searchBar.query.isEmpty && searchBar.replacement.isEmpty && !searchBar.isCaseSensitive && searchBar.status.isEmpty)
            searchBar.status = "Found 5 matches"
            try expectEqual(searchBar.status, "Found 5 matches")
            searchBar.focusFindField()      // not in a window: no-op
            searchBar.focusReplaceField()

            let views = searchBar.arrangedSubviews
            try expectEqual(views.count, 10)
            for index in [1, 2, 3, 5, 6, 9] { (views[index] as? NSButton)?.performClick(nil) }
            try expectEqual(calls, ["previous", "next", "query", "replace", "all", "close"])
            try expect(searchBar.isCaseSensitive, "the checkbox click toggled Match Case")
            try expectEqual(views[1].accessibilityLabel(), "Previous match")
            try expectEqual(views[2].accessibilityLabel(), "Next match")
            try expectEqual(views[6].accessibilityLabel(), "Replace all")

            // Typing in the find field reports a query change.
            let findField = try unwrap(views[0] as? NSSearchField)
            try expect(findField.sendsSearchStringImmediately)
            calls = []
            findField.stringValue = "abc"
            findField.sendAction(findField.action, to: findField.target)
            try expectEqual(calls, ["query"])
            try expectEqual(searchBar.query, "abc")

            let replaceField = try unwrap(views[4] as? NSTextField)
            replaceField.stringValue = "xyz"
            try expectEqual(searchBar.replacement, "xyz")

            // Return in the find field: next; in the replace field: replace; Escape: close; others pass through.
            let textView = NSTextView()
            calls = []
            try expect(searchBar.control(findField, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            try expect(searchBar.control(replaceField, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            try expect(searchBar.control(findField, textView: textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
            try expect(searchBar.control(replaceField, textView: textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
            try expect(!searchBar.control(findField, textView: textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
            try expectEqual(calls, ["next", "replace", "close", "close"])

            _ = render(width: 400, height: 32) { searchBar.draw(NSRect(x: 0, y: 0, width: 400, height: 32)) }
        }
    }
}
