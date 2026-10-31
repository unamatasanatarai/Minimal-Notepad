import AppKit

public enum DocumentControllerTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("DocumentController discardChangesIfNotConfirming behavior") {
            let controller = documentController
            let doc1 = TextDocument()
            let doc2 = TextDocument()
            doc1.updateChangeCount(.changeDone)
            doc2.updateChangeCount(.changeDone)
            assert(doc1.isDocumentEdited)
            assert(doc2.isDocumentEdited)

            let originalConfirm = defaults.bool(forKey: Pref.confirmClose)
            defer { defaults.set(originalConfirm, forKey: Pref.confirmClose) }

            // When confirmClose is true, edits should NOT be cleared
            defaults.set(true, forKey: Pref.confirmClose)
            controller.discardChangesIfNotConfirming([doc1, doc2])
            assert(doc1.isDocumentEdited, "Edits should remain when confirmClose is true")
            assert(doc2.isDocumentEdited, "Edits should remain when confirmClose is true")

            // When confirmClose is false, edits SHOULD be cleared without asking
            defaults.set(false, forKey: Pref.confirmClose)
            controller.discardChangesIfNotConfirming([doc1, doc2])
            assert(!doc1.isDocumentEdited, "Edits should be cleared when confirmClose is false")
            assert(!doc2.isDocumentEdited, "Edits should be cleared when confirmClose is false")
        }

        testRunner("DocumentController currentDocument resolution") {
            let controller = documentController
            // Test accessing currentDocument property
            _ = controller.currentDocument

            let doc = TextDocument()
            let windowController = EditorWindowController()
            windowController.add(doc)
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)

            if NSApp.mainWindow === windowController.window {
                assert(controller.currentDocument === doc)
            }
            windowController.close()
        }

        testRunner("DocumentController open with symlink resolution") {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let originalFile = tempDir.appendingPathComponent("orig_\(UUID().uuidString).txt")
            let symlinkFile = tempDir.appendingPathComponent("link_\(UUID().uuidString).txt")

            try "Symlink test content".write(to: originalFile, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: originalFile)

            defer {
                try? FileManager.default.removeItem(at: originalFile)
                try? FileManager.default.removeItem(at: symlinkFile)
            }

            let controller = documentController
            var openedDoc: NSDocument?
            let exp = DispatchSemaphore(value: 0)

            controller.openDocument(withContentsOf: symlinkFile, display: false) { doc, _, error in
                openedDoc = doc
                exp.signal()
            }
            _ = exp.wait(timeout: .now() + 2.0)

            if let doc = openedDoc as? TextDocument {
                // Verify symlink was resolved to the original file path
                assert(doc.fileURL?.standardizedFileURL.path == originalFile.standardizedFileURL.path)
                doc.close()
            }

            // Test open(_:) fire-and-forget helper
            controller.open(originalFile)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        testRunner("DocumentController reviewUnsavedDocuments and closeAllDocuments delegation") {
            let controller = documentController
            let origConfirm = defaults.bool(forKey: Pref.confirmClose)
            defer { defaults.set(origConfirm, forKey: Pref.confirmClose) }

            defaults.set(false, forKey: Pref.confirmClose)
            // Verify reviewUnsavedDocuments and closeAllDocuments execute without error
            controller.reviewUnsavedDocuments(withAlertTitle: "Test", cancellable: true, delegate: nil, didReviewAllSelector: nil, contextInfo: nil)
            controller.closeAllDocuments(withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
        }
    }
}
