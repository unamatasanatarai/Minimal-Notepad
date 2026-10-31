import AppKit

public enum EditorWindowControllerTests {
    static func makeWindow(_ count: Int) -> (EditorWindowController, [TextDocument]) {
        let controller = EditorWindowController()
        let documents = (0..<count).map { _ in TextDocument() }
        documents.forEach(controller.add)
        return (controller, documents)
    }

    static func order(_ controller: EditorWindowController) -> [ObjectIdentifier] {
        return controller.panes.map { ObjectIdentifier($0.document) }
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("EditorWindowController window configuration") {
            let controller = EditorWindowController()
            let window = try unwrap(controller.window)
            try expectEqual(window.tabbingMode, .disallowed)
            try expect(!window.isReleasedWhenClosed)
            try expect(!window.isRestorable)
            try expect(window.collectionBehavior.contains(.fullScreenPrimary))
            try expect(window.delegate === controller)
            try expect(controller.panes.isEmpty)
            try expect(controller.selectedPane == nil)
        }

        testRunner("EditorWindowController cascades new windows from the previous one") {
            let first = EditorWindowController()
            let second = EditorWindowController()
            let a = try unwrap(first.window).frame, b = try unwrap(second.window).frame
            try expect(a.origin != b.origin, "windows must not stack exactly on top of each other")
        }

        testRunner("EditorWindowController.front reuses the front window or makes one") {
            let made = EditorWindowController.front
            try expect(made.window != nil)

            let (controller, docs) = makeWindow(1)
            controller.showWindow(nil)
            TestSupport.drain()
            if NSApp.orderedWindows.contains(where: { $0 === controller.window }) {
                try expect(EditorWindowController.front === controller)
                try expect(EditorWindowController.orderedDocuments.contains { $0 === docs[0] })
            }
        }

        testRunner("EditorWindowController add, select and remove tabs") {
            let (controller, docs) = makeWindow(3)
            try expectEqual(controller.panes.count, 3)
            try expect(controller.selectedPane?.document === docs[2], "a new tab is selected")
            try expect(docs.allSatisfy { $0.host === controller })

            let pane0 = controller.pane(for: docs[0])
            controller.select(pane0, savingLeftTab: true)
            try expect(controller.selectedPane === pane0)
            try expect(pane0?.superview != nil, "the selected pane is shown")
            try expect(controller.pane(for: docs[2])?.superview == nil, "other panes are not in the view hierarchy")

            controller.select(controller.pane(for: docs[1]), savingLeftTab: false)
            try expect(controller.selectedPane?.document === docs[1])

            controller.select(nil)
            try expect(controller.selectedPane?.document === docs[1], "selecting nil is a no-op")
            controller.select(controller.selectedPane)
            try expect(controller.selectedPane?.document === docs[1], "reselecting is a no-op")

            // Removing a background tab keeps the selection.
            controller.remove(docs[0])
            try expectEqual(controller.panes.count, 2)
            try expect(controller.selectedPane?.document === docs[1])

            // Removing a document that is not in this window does nothing.
            controller.remove(TextDocument())
            try expectEqual(controller.panes.count, 2)
            try expect(controller.pane(for: TextDocument()) == nil)
        }

        testRunner("EditorWindowController removing the selected tab selects its right neighbour, else the last") {
            let (controller, docs) = makeWindow(4)
            controller.select(controller.pane(for: docs[1]))
            controller.remove(docs[1])
            try expect(controller.selectedPane?.document === docs[2], "right neighbour takes over")

            controller.select(controller.pane(for: docs[3]))
            controller.remove(docs[3])
            try expect(controller.selectedPane?.document === docs[2], "the last tab falls back to its left neighbour")
        }

        testRunner("EditorWindowController closes its window with the last tab") {
            let (controller, docs) = makeWindow(1)
            controller.showWindow(nil)
            try expect(controller.window?.isVisible == true)
            controller.remove(docs[0])
            try expect(controller.panes.isEmpty)
            try expect(controller.window?.isVisible == false)
        }

        testRunner("EditorWindowController title, edited state and tab bar visibility") {
            let (controller, docs) = makeWindow(1)
            let window = try unwrap(controller.window)
            let tabBar = try unwrap(TestSupport.tabBar(of: controller))
            try expect(tabBar.isHidden, "a single tab shows no tab bar")
            try expectEqual(window.title, docs[0].tabTitle)

            let second = try makeFileDocument("x", named: "second.txt")
            controller.add(second)
            try expect(!tabBar.isHidden)
            try expectEqual(window.title, "second.txt")
            try expectEqual(window.representedURL, second.fileURL)

            docs[0].updateChangeCount(.changeDone)
            try expect(!window.isDocumentEdited, "only the selected tab sets the window's edited state")
            controller.select(controller.pane(for: docs[0]))
            try expect(window.isDocumentEdited)
            try expect(window.title.hasPrefix("* "))
            try expect(window.representedURL == nil)
        }

        testRunner("EditorWindowController tab bar callbacks select, close and reorder") {
            let (controller, docs) = makeWindow(3)
            let tabBar = try unwrap(TestSupport.tabBar(of: controller))

            tabBar.onSelect?(0)
            try expect(controller.selectedPane?.document === docs[0])

            tabBar.onMove?(0, 2)
            try expectEqual(order(controller), [docs[1], docs[2], docs[0]].map(ObjectIdentifier.init))
            try expect(controller.selectedPane?.document === docs[0], "moving keeps the selection")

            tabBar.onClose?(0)
            try expect(TestSupport.spin { controller.pane(for: docs[1]) == nil }, "the clean document closes")
            try expectEqual(controller.panes.count, 2)
            try expect(controller.closeRequests.isEmpty, "finished close requests are released")
        }

        testRunner("EditorWindowController next and previous tab wrap around") {
            let (controller, docs) = makeWindow(3)
            controller.select(controller.pane(for: docs[0]))
            controller.showNextTab(nil)
            try expect(controller.selectedPane?.document === docs[1])
            controller.showNextTab(nil)
            try expect(controller.selectedPane?.document === docs[2])
            controller.showNextTab(nil)
            try expect(controller.selectedPane?.document === docs[0])
            controller.showPreviousTab(nil)
            try expect(controller.selectedPane?.document === docs[2])
            controller.showPreviousTab(nil)
            try expect(controller.selectedPane?.document === docs[1])

            // No tabs: nothing to do.
            let empty = EditorWindowController()
            empty.showNextTab(nil)
            empty.showPreviousTab(nil)
            empty.closeTab(nil)
            try expect(empty.selectedPane == nil)
        }

        testRunner("EditorWindowController moveTabToNewWindow and mergeAllWindows") {
            let (first, docs) = makeWindow(2)
            first.select(first.pane(for: docs[1]))

            first.moveTabToNewWindow(nil)
            try expectEqual(first.panes.count, 1)
            try expect(first.panes.first?.document === docs[0])
            let second = try unwrap(docs[1].host)
            try expect(second !== first)
            try expect(second.selectedPane?.document === docs[1])

            first.moveTabToNewWindow(nil)
            try expectEqual(first.panes.count, 1, "the only tab cannot be moved out")

            let (third, thirdDocs) = makeWindow(2)
            first.mergeAllWindows(nil)
            try expectEqual(first.panes.count, 4, "every tab from every window is merged")
            for doc in [docs[1]] + thirdDocs {
                try expect(doc.host === first)
            }
            try expect(second.panes.isEmpty && third.panes.isEmpty)
            try expect(second.window?.isVisible != true && third.window?.isVisible != true)
        }

        testRunner("EditorWindowController merging keeps the current tab selected and appends the others in order") {
            let (first, docs) = makeWindow(2)
            first.select(first.pane(for: docs[0]))
            let (_, otherDocs) = makeWindow(3)
            first.mergeAllWindows(nil)
            try expect(first.selectedPane?.document === docs[0], "the tab you were on stays selected")
            try expectEqual(order(first), (docs + otherDocs).map(ObjectIdentifier.init))
            try expect(first.panes.filter { $0.superview != nil }.count == 1, "only the selected pane is shown")
            try expect(TestSupport.tabBar(of: first)?.isHidden == false)
        }

        testRunner("EditorWindowController ignores out-of-range indexes from the tab bar") {
            let (controller, docs) = makeWindow(2)
            let tabBar = try unwrap(TestSupport.tabBar(of: controller))
            tabBar.onSelect?(5)
            tabBar.onSelect?(-1)
            tabBar.onClose?(2)
            tabBar.onMove?(0, 9)
            tabBar.onMove?(-1, 0)
            TestSupport.drain()
            try expectEqual(order(controller), docs.map(ObjectIdentifier.init))
            try expect(controller.selectedPane?.document === docs[1])
        }

        testRunner("EditorWindowController menu validation") {
            let (controller, _) = makeWindow(1)
            let item = { (action: Selector) in NSMenuItem(title: "", action: action, keyEquivalent: "") }
            let next = item(#selector(EditorWindowController.showNextTab(_:)))
            let previous = item(#selector(EditorWindowController.showPreviousTab(_:)))
            let move = item(#selector(EditorWindowController.moveTabToNewWindow(_:)))
            let merge = item(#selector(EditorWindowController.mergeAllWindows(_:)))
            let other = item(#selector(NSDocument.save(_:)))

            try expect(!controller.validateMenuItem(next))
            try expect(!controller.validateMenuItem(previous))
            try expect(!controller.validateMenuItem(move))
            try expect(controller.validateMenuItem(other))

            controller.add(TextDocument())
            try expect(controller.validateMenuItem(next))
            try expect(controller.validateMenuItem(previous))
            try expect(controller.validateMenuItem(move))

            // Merging needs at least two windows. Closed windows leave the list on the next run loop pass.
            try expect(TestSupport.spin { !controller.validateMenuItem(merge) }, "one window: nothing to merge")
            let (other2, _) = makeWindow(1)
            try expect(controller.validateMenuItem(merge))
            other2.remove(other2.panes[0].document)
            try expect(TestSupport.spin { !controller.validateMenuItem(merge) }, "a closed window leaves the list")
        }

        testRunner("EditorWindowController routes undo to the selected document") {
            let (controller, docs) = makeWindow(2)
            let window = try unwrap(controller.window)
            try expect(controller.windowWillReturnUndoManager(window) === docs[1].undoManager)
            controller.select(controller.pane(for: docs[0]))
            try expect(controller.windowWillReturnUndoManager(window) === docs[0].undoManager)
            try expect(EditorWindowController().windowWillReturnUndoManager(window) == nil)
        }

        testRunner("EditorWindowController close button closes every tab, and the window with them") {
            let (controller, docs) = makeWindow(3)
            controller.showWindow(nil)
            let window = try unwrap(controller.window)
            try expect(controller.windowShouldClose(window) == false, "closing is done tab by tab")
            try expect(TestSupport.spin { controller.panes.isEmpty })
            try expect(docs.allSatisfy { $0.host == nil || $0.host?.pane(for: $0) == nil })
            try expect(!window.isVisible)
            try expect(controller.closeRequests.isEmpty)
        }

        testRunner("EditorWindowController closeTab closes only the selected tab") {
            let (controller, docs) = makeWindow(2)
            controller.closeTab(nil)
            try expect(TestSupport.spin { controller.panes.count == 1 })
            try expect(controller.panes[0].document === docs[0])
        }

        testRunner("EditorWindowController saves on focus loss: resigning key and leaving a tab") {
            defaults.set(true, forKey: Pref.saveOnFocusLost)
            let doc = try makeFileDocument("v1", named: "focus.txt")
            let url = try unwrap(doc.fileURL)
            let controller = EditorWindowController()
            controller.add(doc)
            let window = try unwrap(controller.window)

            doc.textStorage.mutableString.setString("v2")
            doc.updateChangeCount(.changeDone)
            controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
            try expect(TestSupport.spin { (try? String(contentsOf: url, encoding: .utf8)) == "v2" }, "saved on resign key")

            // Leaving the tab saves it; a prompt switching tabs (savingLeftTab false) does not.
            controller.add(TextDocument())
            controller.select(controller.pane(for: doc))
            doc.textStorage.mutableString.setString("v3")
            doc.updateChangeCount(.changeDone)
            controller.select(controller.panes[1], savingLeftTab: false)
            TestSupport.drain(0.2)
            try expectEqual(try String(contentsOf: url, encoding: .utf8), "v2")
            controller.select(controller.pane(for: doc))
            controller.select(controller.panes[1])
            try expect(TestSupport.spin { (try? String(contentsOf: url, encoding: .utf8)) == "v3" }, "saved when leaving the tab")
            TestSupport.drain(0.2)
            try expect(controller.selectedPane === controller.panes[1], "saving the tab you left must not switch back to it")
        }

        testRunner("EditorWindowController windowWillClose detaches panes from document storage") {
            let (controller, docs) = makeWindow(1)
            let window = try unwrap(controller.window)
            try expectEqual(docs[0].textStorage.layoutManagers.count, 1)
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            try expectEqual(docs[0].textStorage.layoutManagers.count, 0)
        }

        testRunner("CloseRequest forwards the answer, then reports it finished") {
            var answers: [Bool] = []
            var finished: [CloseRequest] = []
            let request = CloseRequest { answers.append($0) }
            request.onFinish = { finished.append($0) }
            request.document(TextDocument(), shouldClose: true, contextInfo: nil)
            request.document(TextDocument(), shouldClose: false, contextInfo: nil)
            try expectEqual(answers, [true, false])
            try expect(finished.count == 2 && finished.allSatisfy { $0 === request })
        }
    }
}
