import AppKit

public enum EditorPaneTests {
    static func makePane(_ text: String) -> (EditorPane, TextDocument) {
        let doc = TextDocument()
        doc.textStorage.mutableString.setString(text)
        return (EditorPane(document: doc), doc)
    }

    /// A pane in a window, so edits are undoable through the document's undo manager (the window delegate supplies it).
    static func makeHostedPane(_ text: String) throws -> (EditorPane, TextDocument) {
        let doc = TextDocument()
        doc.textStorage.mutableString.setString(text)
        let controller = EditorWindowController()
        controller.add(doc)
        return (try unwrap(controller.selectedPane), doc)
    }

    /// Opens the search bar with a query, the way typing into the find field does.
    static func search(_ pane: EditorPane, _ query: String, replace: String? = nil, matchCase: Bool = false) throws -> TestSupport.SearchControls {
        let controls = try TestSupport.searchControls(of: pane)
        if controls.bar.isHidden { pane.showFind(nil) }
        controls.matchCase.state = matchCase ? .on : .off
        if let replace = replace { controls.replace.stringValue = replace }
        controls.find.stringValue = query
        controls.bar.onQueryChanged?()
        return controls
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("EditorPane shares the document's storage and detaches from it") {
            let (pane, doc) = makePane("Hello")
            try expect(pane.textView.textStorage === doc.textStorage)
            try expectEqual(doc.textStorage.layoutManagers.count, 1)
            try expect(pane.textView.layoutManager is InvisiblesLayoutManager)
            try expect(pane.textView.layoutManager?.allowsNonContiguousLayout == true)
            try expect(!pane.textView.isRichText)
            try expect(pane.textView.allowsUndo)
            try expect(!pane.textView.isAutomaticQuoteSubstitutionEnabled)
            try expect(!pane.textView.isAutomaticDashSubstitutionEnabled)
            try expect(!pane.textView.isAutomaticTextReplacementEnabled)
            try expect(!pane.textView.isAutomaticSpellingCorrectionEnabled)
            pane.detach()
            try expectEqual(doc.textStorage.layoutManagers.count, 0)
            pane.detach()   // twice is harmless
        }

        testRunner("EditorPane forwards document actions to its document only") {
            let (pane, doc) = makePane("")
            try expect(pane.supplementalTarget(forAction: #selector(NSDocument.save(_:)), sender: nil) as AnyObject? === doc)
            try expect(pane.supplementalTarget(forAction: #selector(NSDocument.printDocument(_:)), sender: nil) as AnyObject? === doc)
            try expect(pane.supplementalTarget(forAction: #selector(NSText.selectAll(_:)), sender: nil) as AnyObject? !== doc)
        }

        testRunner("EditorPane applies the line number and invisibles preferences live") {
            let (pane, _) = makePane("a b")
            let layoutManager = try unwrap(pane.textView.layoutManager as? InvisiblesLayoutManager)
            let scrollView = try unwrap(pane.textView.enclosingScrollView)
            try expect(scrollView.rulersVisible, "line numbers are on by default")
            try expect(!layoutManager.showsInvisibles)

            defaults.set(false, forKey: Pref.showLineNumbers)
            defaults.set(true, forKey: Pref.showInvisibles)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            try expect(!scrollView.rulersVisible)
            try expect(layoutManager.showsInvisibles)

            // Posting again with nothing changed must leave things alone.
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            try expect(!scrollView.rulersVisible)
            try expect(layoutManager.showsInvisibles)
        }

        testRunner("EditorPane word wrap follows the preference and toggles") {
            defaults.set(false, forKey: Pref.wordWrap)
            let (noWrap, _) = makePane("")
            try expect(noWrap.textView.isHorizontallyResizable, "not wrapping: the text view grows sideways")
            try expect(noWrap.textView.textContainer?.widthTracksTextView == false)
            try expect(noWrap.textView.enclosingScrollView?.hasHorizontalScroller == true)

            defaults.set(true, forKey: Pref.wordWrap)
            let (pane, _) = makePane("")
            let item = NSMenuItem(title: "Wrap", action: #selector(EditorPane.toggleWordWrap(_:)), keyEquivalent: "")
            try expect(pane.validateMenuItem(item))
            try expectEqual(item.state, .on)
            try expect(!pane.textView.isHorizontallyResizable)
            try expect(pane.textView.textContainer?.widthTracksTextView == true)

            pane.toggleWordWrap(nil)
            _ = pane.validateMenuItem(item)
            try expectEqual(item.state, .off)
            try expect(pane.textView.isHorizontallyResizable)
            try expectEqual(pane.textView.textContainer?.containerSize.width, CGFloat.greatestFiniteMagnitude)

            pane.toggleWordWrap(nil)
            _ = pane.validateMenuItem(item)
            try expectEqual(item.state, .on)
        }

        testRunner("EditorPane zoom changes font size between 6 and 72 points") {
            let (pane, _) = makePane("text")
            let base = NSFont.systemFontSize
            try expectEqual(pane.textView.font?.pointSize, base)
            let zoomIn = NSMenuItem(title: "", action: #selector(EditorPane.zoomIn(_:)), keyEquivalent: "")
            let zoomOut = NSMenuItem(title: "", action: #selector(EditorPane.zoomOut(_:)), keyEquivalent: "")
            let other = NSMenuItem(title: "", action: #selector(NSObject.description), keyEquivalent: "")

            pane.zoomIn(nil)
            try expectEqual(pane.textView.font?.pointSize, base + 1)
            try expectEqual((pane.textView.typingAttributes[.font] as? NSFont)?.pointSize, base + 1)
            try expectEqual((pane.textView.layoutManager as? InvisiblesLayoutManager)?.font.pointSize, base + 1)

            for _ in 0..<100 { pane.zoomIn(nil) }
            try expectEqual(pane.textView.font?.pointSize, 72)
            try expect(!pane.validateMenuItem(zoomIn))
            try expect(pane.validateMenuItem(zoomOut))

            for _ in 0..<100 { pane.zoomOut(nil) }
            try expectEqual(pane.textView.font?.pointSize, 6)
            try expect(!pane.validateMenuItem(zoomOut))
            try expect(pane.validateMenuItem(zoomIn))

            pane.resetZoom(nil)
            try expectEqual(pane.textView.font?.pointSize, base)
            try expect(pane.validateMenuItem(zoomIn) && pane.validateMenuItem(zoomOut) && pane.validateMenuItem(other))
        }

        testRunner("EditorPane converts pasted or typed CR and CRLF to LF") {
            let (pane, doc) = makePane("")
            let textView = pane.textView
            try expect(pane.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "plain"))
            try expect(pane.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: nil), "attribute-only changes pass")

            textView.insertText("a\r\nb\rc", replacementRange: NSRange(location: 0, length: 0))
            try expectEqual(doc.textStorage.string, "a\nb\nc")
            textView.insertText("X\r\n", replacementRange: NSRange(location: 1, length: 1))
            try expectEqual(doc.textStorage.string, "aX\nb\nc")
        }

        testRunner("EditorPane search: statuses for match counts and current match") {
            let (pane, _) = makePane("apple banana apple cherry apple")
            var controls = try search(pane, "apple")
            try expectEqual(controls.bar.status, "1 of 3")
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 0, length: 5))
            try expectEqual(pane.textView.findHighlights.count, 3)

            // Caret away from a match: count only, singular and plural.
            pane.textView.setSelectedRange(NSRange(location: 7, length: 0))
            try expectEqual(controls.bar.status, "3 matches")
            controls = try search(pane, "cherry")
            try expectEqual(controls.bar.status, "1 of 1")
            pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
            try expectEqual(controls.bar.status, "1 match")

            controls = try search(pane, "watermelon")
            try expectEqual(controls.bar.status, "No matches")
            try expect(pane.textView.findHighlights.isEmpty)

            controls = try search(pane, "")
            try expectEqual(controls.bar.status, "")
        }

        testRunner("EditorPane search starts at the caret and wraps both ways") {
            let (pane, _) = makePane("apple banana apple cherry apple")
            pane.textView.setSelectedRange(NSRange(location: 8, length: 0))
            let controls = try search(pane, "apple")
            try expectEqual(controls.bar.status, "2 of 3", "the first match after the caret is selected")

            pane.findNext(nil)
            try expectEqual(controls.bar.status, "3 of 3")
            pane.findNext(nil)
            try expectEqual(controls.bar.status, "1 of 3")
            pane.findPrevious(nil)
            try expectEqual(controls.bar.status, "3 of 3")
            pane.findPrevious(nil)
            try expectEqual(controls.bar.status, "2 of 3")

            // Caret after the last match: the query wraps to the first.
            pane.textView.setSelectedRange(NSRange(location: 31, length: 0))
            _ = try search(pane, "apple")
            try expectEqual(controls.bar.status, "1 of 3")

            // The buttons do the same as the menu items.
            controls.next.performClick(nil)
            try expectEqual(controls.bar.status, "2 of 3")
            controls.previous.performClick(nil)
            try expectEqual(controls.bar.status, "1 of 3")
        }

        testRunner("EditorPane search is case-insensitive unless Match Case is on, and literal") {
            let (pane, _) = makePane("Apple apple APPLE a.c abc")
            try expectEqual(try search(pane, "apple").bar.status, "1 of 3")
            try expectEqual(try search(pane, "apple", matchCase: true).bar.status, "1 of 1")
            try expectEqual(try search(pane, "Orange", matchCase: true).bar.status, "No matches")
            try expectEqual(try search(pane, "a.c").bar.status, "1 of 1", "no regex or wildcard meaning")
            // The Match Case checkbox re-runs the search.
            let controls = try search(pane, "APPLE")
            try expectEqual(pane.textView.findHighlights.count, 3)
            controls.matchCase.performClick(nil)
            try expectEqual(pane.textView.findHighlights.count, 1)
        }

        testRunner("EditorPane find next with a hidden or empty search bar opens it instead") {
            let (pane, _) = makePane("abc")
            let controls = try TestSupport.searchControls(of: pane)
            try expect(controls.bar.isHidden)
            pane.findNext(nil)
            try expect(!controls.bar.isHidden, "find next opens the search bar")
            pane.findPrevious(nil)
            try expect(!controls.bar.isHidden)
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 0, length: 0), "nothing selected")

            // No matches: the selection is kept.
            _ = try search(pane, "zzz")
            pane.findNext(nil)
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 0, length: 0))
        }

        testRunner("EditorPane hiding the search bar clears highlights, and reopening restores them") {
            let (pane, _) = makePane("a a a")
            let controls = try search(pane, "a")
            try expectEqual(pane.textView.findHighlights.count, 3)
            controls.done.performClick(nil)
            try expect(controls.bar.isHidden)
            try expect(pane.textView.findHighlights.isEmpty)
            pane.showReplace(nil)
            try expect(!controls.bar.isHidden)
            try expectEqual(pane.textView.findHighlights.count, 3, "the old query is searched again")
        }

        testRunner("EditorPane edits rescan matches after a delay, or at once when navigating") {
            let (pane, doc) = makePane("one two")
            let controls = try search(pane, "o")
            try expectEqual(pane.textView.findHighlights.count, 2)

            pane.textView.setSelectedRange(NSRange(location: 7, length: 0))
            pane.textView.insertText(" four", replacementRange: pane.textView.selectedRange())
            try expectEqual(doc.textStorage.string, "one two four")
            try expectEqual(pane.textView.findHighlights.count, 2, "typing does not rescan immediately")
            try expect(TestSupport.spin(timeout: 1) { pane.textView.findHighlights.count == 3 }, "rescanned after the delay")

            pane.textView.insertText(" go", replacementRange: NSRange(location: 12, length: 0))
            pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
            pane.findPrevious(nil)
            try expectEqual(controls.bar.status, "4 of 4", "stale matches are refreshed before navigating")

            // Edits while the bar is hidden schedule nothing.
            controls.bar.onClose?()
            pane.textView.insertText("o", replacementRange: NSRange(location: 0, length: 0))
            TestSupport.drain(0.3)
            try expect(pane.textView.findHighlights.isEmpty)
        }

        testRunner("EditorPane replace replaces the selected match and moves to the next") {
            let (pane, doc) = try makeHostedPane("apple banana apple cherry apple")
            let controls = try search(pane, "apple", replace: "orange")
            controls.replaceButton.performClick(nil)
            try expectEqual(doc.textStorage.string, "orange banana apple cherry apple")
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 14, length: 5), "the next match is selected")
            try expectEqual(controls.bar.status, "1 of 2")

            // With the caret not on a match, Replace only selects the next match.
            pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
            controls.bar.onReplace?()
            try expectEqual(doc.textStorage.string, "orange banana apple cherry apple")
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 14, length: 5))

            // Undo restores the replaced text.
            doc.undoManager?.undo()
            try expectEqual(doc.textStorage.string, "apple banana apple cherry apple")
        }

        testRunner("EditorPane replace never touches text that stopped matching after a revert or reload") {
            let (pane, doc) = try makeHostedPane("apple pie")
            let controls = try search(pane, "apple", replace: "pear")
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 0, length: 5))
            // Revert to Saved / reload from disk replaces the storage directly, not through the text view.
            try doc.read(from: Data("zzzzz pie".utf8), ofType: "public.plain-text")
            pane.textView.setSelectedRange(NSRange(location: 0, length: 5))
            controls.bar.onReplace?()
            try expectEqual(doc.textStorage.string, "zzzzz pie", "only real matches may be replaced")
            try expectEqual(controls.bar.status, "No matches")
            try expect(pane.textView.findHighlights.isEmpty, "highlights follow the reloaded text")
        }

        testRunner("EditorPane highlights follow undo and external edits while the search bar is open") {
            let (pane, doc) = try makeHostedPane("one")
            _ = try search(pane, "o")
            try expectEqual(pane.textView.findHighlights.count, 1)
            doc.textStorage.mutableString.append(" two")   // an edit that bypasses the text view
            try expect(TestSupport.spin(timeout: 1) { pane.textView.findHighlights.count == 2 })
            // Attribute-only changes (zooming) do not rescan.
            pane.zoomIn(nil)
            try expectEqual(pane.textView.findHighlights.count, 2)
        }

        testRunner("EditorPane replace with text containing the query does not loop on its own output") {
            let (pane, doc) = makePane("a b a")
            let controls = try search(pane, "a", replace: "aa")
            controls.bar.onReplace?()
            try expectEqual(doc.textStorage.string, "aa b a")
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 5, length: 1), "skips past the inserted text")
            controls.bar.onReplace?()
            try expectEqual(doc.textStorage.string, "aa b aa")
        }

        testRunner("EditorPane replace with an empty replacement deletes the match") {
            let (pane, doc) = makePane("x-y-z")
            let controls = try search(pane, "-", replace: "")
            controls.bar.onReplace?()
            try expectEqual(doc.textStorage.string, "xy-z")
        }

        testRunner("EditorPane replace all: count, caret, undo and no-op cases") {
            let (pane, doc) = try makeHostedPane("Apple banana apple cherry APPLE")
            let controls = try search(pane, "apple", replace: "kiwi")
            pane.textView.setSelectedRange(NSRange(location: 30, length: 0))
            controls.replaceAll.performClick(nil)
            try expectEqual(doc.textStorage.string, "kiwi banana kiwi cherry kiwi")
            try expectEqual(controls.bar.status, "Replaced 3")
            try expectEqual(pane.textView.selectedRange().location, 28, "the caret is clamped to the shorter text")
            try expect(pane.textView.findHighlights.isEmpty)

            doc.undoManager?.undo()
            try expectEqual(doc.textStorage.string, "Apple banana apple cherry APPLE", "replace all is one undo step")

            // Case-sensitive replace all only touches exact matches.
            _ = try search(pane, "apple", replace: "pear", matchCase: true)
            controls.bar.onReplaceAll?()
            try expectEqual(doc.textStorage.string, "Apple banana pear cherry APPLE")

            // No matches: the text and status are unchanged.
            _ = try search(pane, "watermelon")
            controls.bar.onReplaceAll?()
            try expectEqual(doc.textStorage.string, "Apple banana pear cherry APPLE")
            try expectEqual(controls.bar.status, "No matches")

            // Empty query: nothing happens.
            _ = try search(pane, "")
            controls.bar.onReplaceAll?()
            try expectEqual(doc.textStorage.string, "Apple banana pear cherry APPLE")
        }

        testRunner("EditorPane moveCaret goes to the start of a 1-based line, clamped to the text") {
            let (pane, doc) = makePane("Line 1\nLine 2\nLine 3\n")
            pane.moveCaret(toLine: 1)
            try expectEqual(pane.textView.selectedRange(), NSRange(location: 0, length: 0))
            pane.moveCaret(toLine: 3)
            try expectEqual(pane.textView.selectedRange().location, 14)
            pane.moveCaret(toLine: 4)
            try expectEqual(pane.textView.selectedRange().location, 21, "the empty line after the final newline")
            pane.moveCaret(toLine: 100)
            try expectEqual(pane.textView.selectedRange().location, doc.textStorage.length)
            pane.moveCaret(toLine: Int.max)
            try expectEqual(pane.textView.selectedRange().location, doc.textStorage.length)
            pane.moveCaret(toLine: 0)
            try expectEqual(pane.textView.selectedRange().location, 0)
            pane.moveCaret(toLine: -5)
            try expectEqual(pane.textView.selectedRange().location, 0)

            let (empty, _) = makePane("")
            empty.moveCaret(toLine: 5)
            try expectEqual(empty.textView.selectedRange().location, 0)
        }

        testRunner("EditorPane goToLine asks for a line in a sheet") {
            let (orphan, _) = makePane("x")
            orphan.goToLine(nil)   // not in a window: nothing to attach a sheet to

            let doc = TextDocument()
            doc.textStorage.mutableString.setString("Line 1\nLine 2\nLine 3")
            let controller = EditorWindowController()
            controller.add(doc)
            controller.showWindow(nil)
            let window = try unwrap(controller.window)
            let pane = try unwrap(controller.selectedPane)

            func answer(_ text: String, button: String) throws {
                pane.goToLine(nil)
                guard TestSupport.spin(until: { window.attachedSheet != nil }), let sheet = window.attachedSheet,
                      let content = sheet.contentView else {
                    throw TestFailure(description: "the Go to Line sheet did not appear")
                }
                let field = try unwrap(TestSupport.findSubview(NSTextField.self, in: content) { $0.placeholderString == "Line number" })
                field.stringValue = text
                try unwrap(TestSupport.findSubview(NSButton.self, in: content) { $0.title == button }).performClick(nil)
                try expect(TestSupport.spin { window.attachedSheet == nil })
            }

            pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
            try answer(" 2 ", button: "Go")
            try expectEqual(pane.textView.selectedRange().location, 7)
            try answer("3", button: "Cancel")
            try expectEqual(pane.textView.selectedRange().location, 7, "cancel does not move")
            try answer("abc", button: "Go")
            try expectEqual(pane.textView.selectedRange().location, 7, "not a number")
            try answer("0", button: "Go")
            try expectEqual(pane.textView.selectedRange().location, 7, "lines start at 1")
            try answer("3", button: "Go")
            try expectEqual(pane.textView.selectedRange().location, 14)
        }
    }
}
