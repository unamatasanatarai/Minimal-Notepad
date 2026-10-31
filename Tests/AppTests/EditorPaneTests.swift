import AppKit

public enum EditorPaneTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("EditorPane initialization, views hierarchy, and detach") {
            let doc = TextDocument()
            doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Hello World\nLine 2\nLine 3")
            let pane = EditorPane(document: doc)
            assert(pane.document === doc)
            assert(pane.subviews.count > 0)

            // Test supplemental target for document actions
            let targetForSave = pane.supplementalTarget(forAction: #selector(NSDocument.save(_:)), sender: nil)
            assert(targetForSave as? NSDocument === doc)

            let targetForOther = pane.supplementalTarget(forAction: #selector(NSObject.copy), sender: nil)
            _ = targetForOther

            // Focus and detach
            pane.focus()
            pane.detach()
        }

        testRunner("EditorPane word wrap toggling and zoom bounds") {
            let doc = TextDocument()
            let pane = EditorPane(document: doc)

            let wrapItem = NSMenuItem(title: "Wrap", action: #selector(EditorPane.toggleWordWrap(_:)), keyEquivalent: "")
            let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(EditorPane.zoomIn(_:)), keyEquivalent: "")
            let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(EditorPane.zoomOut(_:)), keyEquivalent: "")
            let otherItem = NSMenuItem(title: "Other", action: #selector(NSObject.description), keyEquivalent: "")

            // Toggle word wrap
            let initialWrapState = pane.validateMenuItem(wrapItem)
            assert(initialWrapState == true)
            let stateBefore = wrapItem.state
            pane.toggleWordWrap(nil)
            _ = pane.validateMenuItem(wrapItem)
            assert(wrapItem.state != stateBefore)
            pane.toggleWordWrap(nil)
            _ = pane.validateMenuItem(wrapItem)
            assert(wrapItem.state == stateBefore)

            // Zoom In repeatedly up to max (72)
            for _ in 0..<100 {
                pane.zoomIn(nil)
            }
            assert(!pane.validateMenuItem(zoomInItem), "Zoom In should disable at max size 72")
            assert(pane.validateMenuItem(zoomOutItem), "Zoom Out should be enabled at max size 72")

            // Zoom Out repeatedly down to min (6)
            for _ in 0..<100 {
                pane.zoomOut(nil)
            }
            assert(!pane.validateMenuItem(zoomOutItem), "Zoom Out should disable at min size 6")
            assert(pane.validateMenuItem(zoomInItem), "Zoom In should be enabled at min size 6")

            // Reset zoom
            pane.resetZoom(nil)
            assert(pane.validateMenuItem(zoomInItem))
            assert(pane.validateMenuItem(zoomOutItem))
            assert(pane.validateMenuItem(otherItem))
        }

        testRunner("EditorPane search, navigation, replace, and replace all") {
            let doc = TextDocument()
            doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "apple banana apple cherry apple")
            let pane = EditorPane(document: doc)

            // Reveal search bar
            pane.showFind(nil)
            pane.showReplace(nil)

            // Find next / previous with no search query or hidden bar
            pane.findNext(nil)
            pane.findPrevious(nil)

            // Hide search bar
            pane.showFind(nil)

            // Delegate change text notifications
            let dummyTV = NSTextView()
            pane.textDidChange(Notification(name: NSText.didChangeNotification, object: dummyTV))
            pane.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: dummyTV))

            // Text change with Carriage Return '\r' normalization
            let allowedPlain = pane.textView(dummyTV, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "Clean text")
            assert(allowedPlain == true, "Normal text without carriage returns should be allowed as-is")

            let allowedCR = pane.textView(dummyTV, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "Carriage\r\nReturn")
            assert(allowedCR == false, "Text with carriage returns should be intercepted and normalized")
        }

        testRunner("EditorPane active search, replace, and replace all execution") {
            let doc = TextDocument()
            doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "apple banana apple cherry apple")
            let pane = EditorPane(document: doc)
            pane.showFind(nil)

            // Locate SearchBarView inside pane hierarchy
            func searchBarIn(_ view: NSView) -> SearchBarView? {
                if let sb = view as? SearchBarView { return sb }
                for sub in view.subviews {
                    if let found = searchBarIn(sub) { return found }
                }
                return nil
            }

            guard let searchBar = searchBarIn(pane),
                  let findField = searchBar.arrangedSubviews[0] as? NSSearchField,
                  let caseCheckbox = searchBar.arrangedSubviews[3] as? NSButton,
                  let replaceField = searchBar.arrangedSubviews[4] as? NSTextField else {
                assertionFailure("Failed to resolve SearchBarView subcomponents")
                return
            }

            // Test query with 3 matches
            findField.stringValue = "apple"
            searchBar.onQueryChanged?()
            assert(searchBar.status == "1 of 3", "Status was: \(searchBar.status)")

            // Navigate forward: 1 of 3 -> 2 of 3 -> 3 of 3 -> 1 of 3 (wrap)
            searchBar.onNext?()
            assert(searchBar.status == "2 of 3", "Status was: \(searchBar.status)")
            searchBar.onNext?()
            assert(searchBar.status == "3 of 3", "Status was: \(searchBar.status)")
            searchBar.onNext?()
            assert(searchBar.status == "1 of 3", "Status was: \(searchBar.status)")

            // Navigate backward: 1 of 3 -> 3 of 3 -> 2 of 3
            searchBar.onPrevious?()
            assert(searchBar.status == "3 of 3", "Status was: \(searchBar.status)")
            searchBar.onPrevious?()
            assert(searchBar.status == "2 of 3", "Status was: \(searchBar.status)")

            // Replace current match ('apple' -> 'orange')
            replaceField.stringValue = "orange"
            searchBar.onReplace?()
            assert(doc.textStorage.string.contains("orange"))

            // Replace all matches
            searchBar.onReplaceAll?()
            assert(searchBar.status.hasPrefix("Replaced"))
            assert(!doc.textStorage.string.contains("apple"))
            assert(doc.textStorage.string == "orange banana orange cherry orange")

            // Test query with 0 matches
            findField.stringValue = "watermelon"
            searchBar.onQueryChanged?()
            assert(searchBar.status == "No matches")
            searchBar.onNext?()
            searchBar.onReplaceAll?()

            // Test case sensitivity toggle
            caseCheckbox.state = .on
            assert(searchBar.isCaseSensitive == true)
            findField.stringValue = "Orange"
            searchBar.onQueryChanged?()
            assert(searchBar.status == "No matches") // all were lower-case 'orange'

            caseCheckbox.state = .off
            assert(searchBar.isCaseSensitive == false)
            searchBar.onQueryChanged?()
            assert(searchBar.status.contains("of 3") || searchBar.status == "3 matches")

            // Close search bar
            searchBar.onClose?()
            assert(searchBar.isHidden == true)
        }

        testRunner("EditorPane goToLine with window and nil window") {
            let doc = TextDocument()
            doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Line 1\nLine 2\nLine 3\nLine 4\nLine 5")
            let pane = EditorPane(document: doc)

            // Calling goToLine when not hosted in window is safe guard
            pane.goToLine(nil)

            // Direct moveCaret testing: line 1, intermediate line 3, beyond EOF line 100
            pane.moveCaret(toLine: 1)
            assert(pane.textView.selectedRange.location == 0)

            pane.moveCaret(toLine: 3)
            let line3Loc = (doc.textStorage.string as NSString).range(of: "Line 3").location
            assert(pane.textView.selectedRange.location == line3Loc)

            pane.moveCaret(toLine: 100)
            assert(pane.textView.selectedRange.location == doc.textStorage.length)

            // Hosting in a window
            let winCtrl = EditorWindowController()
            winCtrl.add(doc)
            pane.goToLine(nil)
            winCtrl.close()
        }
    }
}
