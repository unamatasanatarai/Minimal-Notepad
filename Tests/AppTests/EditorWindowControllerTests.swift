import AppKit

public enum EditorWindowControllerTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("EditorWindowController initialization, front, and orderedDocuments") {
            let winCtrl = EditorWindowController()
            assert(winCtrl.window != nil)
            assert(winCtrl.window?.tabbingMode == .disallowed)
            assert(winCtrl.window?.isReleasedWhenClosed == false)
            assert(winCtrl.panes.isEmpty)
            assert(winCtrl.selectedPane == nil)

            let front = EditorWindowController.front
            assert(front.window != nil)

            let doc1 = TextDocument()
            winCtrl.add(doc1)
            assert(winCtrl.panes.count == 1)
            assert(winCtrl.selectedPane?.document === doc1)
            assert(doc1.host === winCtrl)

            let ordered = EditorWindowController.orderedDocuments
            assert(ordered.contains(where: { $0 === doc1 }))
            winCtrl.close()
        }

        testRunner("EditorWindowController tab addition, selection, and removal") {
            let winCtrl = EditorWindowController()
            let doc1 = TextDocument()
            let doc2 = TextDocument()
            let doc3 = TextDocument()

            winCtrl.add(doc1)
            assert(winCtrl.panes.count == 1)
            assert(winCtrl.pane(for: doc1) != nil)

            winCtrl.add(doc2)
            assert(winCtrl.panes.count == 2)
            assert(winCtrl.selectedPane?.document === doc2)

            winCtrl.add(doc3)
            assert(winCtrl.panes.count == 3)
            assert(winCtrl.selectedPane?.document === doc3)

            // Select tab with savingLeftTab = true and false
            let pane1 = winCtrl.pane(for: doc1)
            winCtrl.select(pane1, savingLeftTab: true)
            assert(winCtrl.selectedPane === pane1)

            let pane2 = winCtrl.pane(for: doc2)
            winCtrl.select(pane2, savingLeftTab: false)
            assert(winCtrl.selectedPane === pane2)

            // Select nil or same pane should be safe no-op
            winCtrl.select(nil)
            assert(winCtrl.selectedPane === pane2)
            winCtrl.select(pane2)
            assert(winCtrl.selectedPane === pane2)

            // Remove tab
            winCtrl.remove(doc2)
            assert(winCtrl.panes.count == 2)
            assert(winCtrl.pane(for: doc2) == nil)

            // Removing non-existent doc is safe no-op
            let foreignDoc = TextDocument()
            winCtrl.remove(foreignDoc)
            assert(winCtrl.panes.count == 2)

            // Test tabBar callbacks (onMove, onSelect, onClose)
            if let stack = winCtrl.window?.contentView?.subviews.first as? NSStackView,
               let tabBar = stack.arrangedSubviews.first as? TabBarView {
                tabBar.onMove?(0, 1)
                tabBar.onSelect?(0)
                tabBar.onClose?(0)
            }

            winCtrl.close()
        }

        testRunner("EditorWindowController next and previous tab navigation with wrap-around") {
            let winCtrl = EditorWindowController()
            let doc1 = TextDocument()
            let doc2 = TextDocument()
            let doc3 = TextDocument()
            winCtrl.add(doc1)
            winCtrl.add(doc2)
            winCtrl.add(doc3)

            winCtrl.select(winCtrl.pane(for: doc1))
            assert(winCtrl.selectedPane?.document === doc1)

            // Next tab: 1 -> 2
            winCtrl.showNextTab(nil)
            assert(winCtrl.selectedPane?.document === doc2)

            // Next tab: 2 -> 3
            winCtrl.showNextTab(nil)
            assert(winCtrl.selectedPane?.document === doc3)

            // Next tab: 3 -> 1 (wrap around)
            winCtrl.showNextTab(nil)
            assert(winCtrl.selectedPane?.document === doc1)

            // Previous tab: 1 -> 3 (wrap around backwards)
            winCtrl.showPreviousTab(nil)
            assert(winCtrl.selectedPane?.document === doc3)

            // Previous tab: 3 -> 2
            winCtrl.showPreviousTab(nil)
            assert(winCtrl.selectedPane?.document === doc2)

            winCtrl.close()
        }

        testRunner("EditorWindowController moveTabToNewWindow and mergeAllWindows") {
            let winCtrl1 = EditorWindowController()
            let docA = TextDocument()
            let docB = TextDocument()
            winCtrl1.add(docA)
            winCtrl1.add(docB)
            winCtrl1.select(winCtrl1.pane(for: docB))

            // Move tab B to new window
            winCtrl1.moveTabToNewWindow(nil)
            assert(winCtrl1.panes.count == 1)
            assert(winCtrl1.panes.first?.document === docA)

            // Calling moveTabToNewWindow with only 1 tab is a no-op
            winCtrl1.moveTabToNewWindow(nil)
            assert(winCtrl1.panes.count == 1)

            // Merge all windows back into winCtrl1
            winCtrl1.mergeAllWindows(nil)
            assert(winCtrl1.panes.contains(where: { $0.document === docA }))
            assert(winCtrl1.panes.contains(where: { $0.document === docB }))

            winCtrl1.close()
        }

        testRunner("EditorWindowController delegate and menu validation methods") {
            let winCtrl = EditorWindowController()
            let doc = TextDocument()
            winCtrl.add(doc)

            // Menu validation with 1 tab
            let nextTabItem = NSMenuItem(title: "Next", action: #selector(EditorWindowController.showNextTab(_:)), keyEquivalent: "")
            let prevTabItem = NSMenuItem(title: "Prev", action: #selector(EditorWindowController.showPreviousTab(_:)), keyEquivalent: "")
            let moveTabItem = NSMenuItem(title: "Move", action: #selector(EditorWindowController.moveTabToNewWindow(_:)), keyEquivalent: "")
            let mergeItem = NSMenuItem(title: "Merge", action: #selector(EditorWindowController.mergeAllWindows(_:)), keyEquivalent: "")
            let otherItem = NSMenuItem(title: "Other", action: #selector(NSDocument.save(_:)), keyEquivalent: "")

            assert(!winCtrl.validateMenuItem(nextTabItem), "Next tab disabled with 1 tab")
            assert(!winCtrl.validateMenuItem(prevTabItem), "Prev tab disabled with 1 tab")
            assert(!winCtrl.validateMenuItem(moveTabItem), "Move tab disabled with 1 tab")
            assert(winCtrl.validateMenuItem(otherItem), "Other item should validate true")

            // Add second tab
            let doc2 = TextDocument()
            winCtrl.add(doc2)
            assert(winCtrl.panes.count == 2)
            assert(winCtrl.validateMenuItem(nextTabItem), "Next tab enabled with 2 tabs")
            assert(winCtrl.validateMenuItem(prevTabItem), "Prev tab enabled with 2 tabs")
            assert(winCtrl.validateMenuItem(moveTabItem), "Move tab enabled with 2 tabs")
            _ = winCtrl.validateMenuItem(mergeItem)

            // Undo manager routing
            if let window = winCtrl.window {
                let undoMgr = winCtrl.windowWillReturnUndoManager(window)
                assert(undoMgr === doc2.undoManager)

                winCtrl.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
                winCtrl.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))

                // Window close delegates
                let shouldClose = winCtrl.windowShouldClose(window)
                assert(shouldClose == false, "windowShouldClose handles tabs internally")
            }

            // CloseTab action
            winCtrl.closeTab(nil)
            winCtrl.close()
        }

        testRunner("CloseRequest callback mechanism") {
            var callbackInvokedWith: Bool?
            let request = CloseRequest { shouldClose in
                callbackInvokedWith = shouldClose
            }

            let dummyDoc = TextDocument()
            request.document(dummyDoc, shouldClose: true, contextInfo: nil)
            assert(callbackInvokedWith == true)

            request.document(dummyDoc, shouldClose: false, contextInfo: nil)
            assert(callbackInvokedWith == false)
        }
    }
}
