import AppKit

public enum DocumentControllerTests {
    /// Opens a URL and waits for the completion handler, which AppKit calls on the main run loop
    /// (so it must be awaited by spinning the run loop, never by blocking on a semaphore).
    static func open(_ url: URL, display: Bool = false) throws -> (NSDocument?, Error?) {
        var result: (NSDocument?, Error?)?
        documentController.openDocument(withContentsOf: url, display: display) { document, _, error in
            result = (document, error)
        }
        try expect(TestSupport.spin { result != nil }, "open did not complete")
        return result!
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("DocumentController discardChangesIfNotConfirming") {
            let doc1 = TextDocument()
            let doc2 = TextDocument()
            doc1.updateChangeCount(.changeDone)
            doc2.updateChangeCount(.changeDone)

            defaults.set(true, forKey: Pref.confirmClose)
            documentController.discardChangesIfNotConfirming([doc1, doc2])
            try expect(doc1.isDocumentEdited && doc2.isDocumentEdited, "edits remain when confirmation is on")

            defaults.set(false, forKey: Pref.confirmClose)
            documentController.discardChangesIfNotConfirming([doc1, doc2])
            try expect(!doc1.isDocumentEdited && !doc2.isDocumentEdited, "edits are dropped when confirmation is off")

            documentController.discardChangesIfNotConfirming([])
        }

        testRunner("DocumentController knows the plain text document type") {
            try expect(documentController.defaultType != nil, "the test binary must embed Info.plist (see scripts/test.sh)")
            try expect(documentController.documentClass(forType: documentController.defaultType!) == TextDocument.self)
        }

        testRunner("DocumentController currentDocument follows the main window's selected tab") {
            let doc = TextDocument()
            let controller = EditorWindowController()
            controller.add(doc)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            TestSupport.drain()
            if NSApp.mainWindow === controller.window {
                try expect(documentController.currentDocument === doc)
                let second = TextDocument()
                controller.add(second)
                try expect(documentController.currentDocument === second)
            } else {
                // Without an active app there is no main window, hence no current document.
                try expect(documentController.currentDocument == nil)
            }
        }

        testRunner("DocumentController opens a symlink's target, so saving updates the real file") {
            let original = try TestSupport.writeFile("Symlink test content", named: "orig.txt")
            let link = original.deletingLastPathComponent().appendingPathComponent("link.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

            let (document, error) = try open(link)
            try expect(error == nil, "\(String(describing: error))")
            let doc = try unwrap(document as? TextDocument)
            try expectEqual(doc.fileURL?.path, original.path)
            try expectEqual(doc.textStorage.string, "Symlink test content")

            // Opening the original afterwards finds the same document instead of a second copy.
            let (again, _) = try open(original)
            try expect(again === doc)

            doc.textStorage.mutableString.setString("edited through link")
            var saved = false
            doc.save(to: doc.fileURL!, ofType: doc.fileType!, for: .saveOperation) { _ in saved = true }
            try expect(TestSupport.spin { saved })
            let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
            try expectEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink, "the link must survive saving")
            try expectEqual(try String(contentsOf: original, encoding: .utf8), "edited through link")
        }

        testRunner("DocumentController.open shows a document, or reports why it could not") {
            let file = try TestSupport.writeFile("opened", named: "open.txt")
            documentController.open(file)
            try expect(TestSupport.spin { documentController.documents.contains { $0.fileURL?.path == file.path } })
            let doc = try unwrap(documentController.documents.first { $0.fileURL?.path == file.path } as? TextDocument)
            try expect(doc.host != nil, "opened documents are displayed in a tab")
            try expect(TestSupport.presentedErrors.isEmpty)

            documentController.open(file.deletingLastPathComponent().appendingPathComponent("missing.txt"))
            try expect(TestSupport.spin { TestSupport.presentedErrors.count == 1 }, "a missing file is reported")

            documentController.open(file.deletingLastPathComponent())
            try expect(TestSupport.spin { TestSupport.presentedErrors.count == 2 }, "a directory is reported")
        }

        testRunner("DocumentController warns about files over 200 MB, by default") {
            try expectEqual(DocumentController().largeFileWarningSize, 200_000_000)
            // A sparse file: the real size, without writing 200 MB to disk.
            let url = try TestSupport.writeFile("", named: "huge.txt")
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 200_000_001)
            try handle.close()
            TestSupport.largeFileAnswer = false
            let (document, error) = try open(url)
            try expect(document == nil)
            try expectEqual((error as? CocoaError)?.code, .userCancelled)
            try expectEqual(TestSupport.largeFilePrompts.map { $0.size }, [200_000_001])
            try expectEqual(TestSupport.largeFilePrompts.first?.url.path, url.path)
        }

        testRunner("DocumentController large file warning: decline, accept, threshold and already-open files") {
            documentController.largeFileWarningSize = 10
            let small = try TestSupport.writeFile("0123456789", named: "small.txt")   // exactly at the limit
            let large = try TestSupport.writeFile("0123456789A", named: "large.txt")

            let (smallDoc, _) = try open(small)
            try expect(smallDoc != nil)
            try expect(TestSupport.largeFilePrompts.isEmpty, "a file at the limit opens without a warning")

            // Declining: nothing opens, and open(_:) reports no error for it.
            TestSupport.largeFileAnswer = false
            documentController.open(large)
            TestSupport.drain(0.2)
            try expectEqual(TestSupport.largeFilePrompts.count, 1)
            try expectEqual(TestSupport.largeFilePrompts[0].size, 11)
            try expect(!documentController.documents.contains { $0.fileURL?.path == large.path })
            try expect(TestSupport.presentedErrors.isEmpty, "declining is not an error")

            // Accepting: the file opens normally.
            TestSupport.largeFileAnswer = true
            let (largeDoc, error) = try open(large)
            try expect(error == nil, "\(String(describing: error))")
            try expectEqual((largeDoc as? TextDocument)?.textStorage.string, "0123456789A")
            try expectEqual(TestSupport.largeFilePrompts.count, 2)

            // Already open: brought forward without asking again.
            let (again, _) = try open(large)
            try expect(again === largeDoc)
            try expectEqual(TestSupport.largeFilePrompts.count, 2)

            // Through a symlink: the prompt names the real file, and it is the same open document.
            let link = large.deletingLastPathComponent().appendingPathComponent("link.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: large)
            let (viaLink, _) = try open(link)
            try expect(viaLink === largeDoc)
            try expectEqual(TestSupport.largeFilePrompts.count, 2)

            // Missing files are not sized or warned about; the normal error is reported.
            documentController.open(large.deletingLastPathComponent().appendingPathComponent("missing.txt"))
            try expect(TestSupport.spin { TestSupport.presentedErrors.count == 1 })
            try expectEqual(TestSupport.largeFilePrompts.count, 2)
        }

        testRunner("DocumentController closeAllDocuments and reviewUnsavedDocuments discard edits when not confirming") {
            defaults.set(false, forKey: Pref.confirmClose)
            let doc = TextDocument()
            documentController.addDocument(doc)
            doc.updateChangeCount(.changeDone)
            documentController.reviewUnsavedDocuments(withAlertTitle: "Test", cancellable: true, delegate: nil, didReviewAllSelector: nil, contextInfo: nil)
            try expect(!doc.isDocumentEdited)

            doc.updateChangeCount(.changeDone)
            documentController.closeAllDocuments(withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
            try expect(TestSupport.spin { documentController.documents.isEmpty }, "all documents close without prompting")
        }
    }
}
