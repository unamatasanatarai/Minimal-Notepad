import AppKit

public enum TextDocumentTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("TextDocument line ending normalization") {
            try expectEqual(TextDocument.normalizeLineEndings("Alpha\nBeta\nGamma"), "Alpha\nBeta\nGamma")
            try expectEqual(TextDocument.normalizeLineEndings("Alpha\r\nBeta\r\nGamma"), "Alpha\nBeta\nGamma")
            try expectEqual(TextDocument.normalizeLineEndings("Alpha\rBeta\rGamma"), "Alpha\nBeta\nGamma")
            try expectEqual(TextDocument.normalizeLineEndings("Alpha\r\nBeta\rGamma\nDelta\r\n"), "Alpha\nBeta\nGamma\nDelta\n")
            try expectEqual(TextDocument.normalizeLineEndings(""), "")
            try expectEqual(TextDocument.normalizeLineEndings("No breaks"), "No breaks")
            // A CR immediately before a CRLF is its own line break; a trailing lone CR becomes LF.
            try expectEqual(TextDocument.normalizeLineEndings("a\r\r\nb\r"), "a\n\nb\n")
            // LF followed by CR is two breaks, not one.
            try expectEqual(TextDocument.normalizeLineEndings("a\n\rb"), "a\n\nb")
        }

        testRunner("TextDocument.decode picks the right encoding for each input") {
            try expectEqual(TextDocument.decode(Data("Hello ⚡️ World".utf8)), "Hello ⚡️ World")
            try expectEqual(TextDocument.decode(Data()), "")

            var utf16LE = Data([0xFF, 0xFE])
            utf16LE.append("UTF16 LE ż".data(using: .utf16LittleEndian)!)
            try expectEqual(TextDocument.decode(utf16LE), "UTF16 LE ż")

            var utf16BE = Data([0xFE, 0xFF])
            utf16BE.append("UTF16 BE ż".data(using: .utf16BigEndian)!)
            try expectEqual(TextDocument.decode(utf16BE), "UTF16 BE ż")

            // Invalid UTF-8 that is valid Windows-1252: 0x80 is the euro sign.
            try expectEqual(TextDocument.decode(Data([0x80, 0x61, 0x62])), "€ab")
            // 0x81 is undefined in Windows-1252, so Mac Roman (which maps every byte) is used.
            try expectEqual(TextDocument.decode(Data([0x81, 0x61])), "Åa")
            // Never empty for non-empty input, whatever the bytes.
            try expect(!TextDocument.decode(Data([0xC0, 0xC1, 0xF5, 0xFF])).isEmpty)
            // A UTF-8 BOM is kept as U+FEFF, so saving writes it back unchanged.
            try expectEqual(TextDocument.decode(Data([0xEF, 0xBB, 0xBF, 0x61])).unicodeScalars.first?.value, 0xFEFF)
            // BOM bytes that are not followed by valid UTF-16 must not lose data (this used to decode to "",
            // or drop the last byte, so saving destroyed the file). They fall back to a byte-preserving encoding.
            try expectEqual(TextDocument.decode(Data([0xFF, 0xFE, 0x41])), "ÿþA")
            try expectEqual(TextDocument.decode(Data([0xFF, 0xFE, 0x41, 0x00, 0x42])).count, 5, "odd length keeps every byte")
            try expect(!TextDocument.decode(Data([0xFF, 0xFE, 0x00, 0xD8])).contains("\u{FFFD}"), "a lone surrogate is not replaced")
            try expectEqual(TextDocument.decode(Data([0xFF, 0xFE])), "", "BOM only: an empty UTF-16 file")
        }

        testRunner("TextDocument detects and restores CRLF, LF and the preference default") {
            let doc = TextDocument()
            try expect(TextDocument.autosavesInPlace == false)
            try expect(doc.shouldRunSavePanelWithAccessoryView == false)

            try doc.read(from: Data("Hello\r\nWorld\r\n".utf8), ofType: "public.plain-text")
            try expectEqual(doc.textStorage.string, "Hello\nWorld\n", "the buffer is LF-only")
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "Hello\r\nWorld\r\n")

            // A file without any line break keeps the current line ending (CRLF from the previous read).
            try doc.read(from: Data("single line".utf8), ofType: "public.plain-text")
            doc.textStorage.mutableString.append("\nadded")
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "single line\r\nadded")

            try doc.read(from: Data("First\nSecond".utf8), ofType: "public.plain-text")
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "First\nSecond")

            // Mixed line endings: the most common one wins (ties go to CRLF, then LF), and every line gets it on save.
            try doc.read(from: Data("a\nb\r\nc".utf8), ofType: "public.plain-text")
            try expect(doc.hasMixedLineEndings)
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "a\r\nb\r\nc")
            try doc.read(from: Data("a\nb\nc\r\nd".utf8), ofType: "public.plain-text")
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "a\nb\nc\nd")
            try doc.read(from: Data("a\rb\rc\nd".utf8), ofType: "public.plain-text")
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "a\rb\rc\rd")

            // Classic Mac (CR-only) files are read with LF and saved with CR again.
            try doc.read(from: Data("a\rb".utf8), ofType: "public.plain-text")
            try expect(!doc.hasMixedLineEndings)
            try expectEqual(doc.textStorage.string, "a\nb")
            try expectEqual(String(data: try doc.data(ofType: "public.plain-text"), encoding: .utf8), "a\rb")

            // A CRLF split across the byte-scanning buffer and a CR right before a CRLF are handled.
            try doc.read(from: Data("a\r\r\nb".utf8), ofType: "public.plain-text")
            try expectEqual(doc.textStorage.string, "a\n\nb")

            // New documents follow the line ending preference.
            defaults.set(1, forKey: Pref.lineEnding)
            let crlfDoc = TextDocument()
            crlfDoc.textStorage.mutableString.setString("x\ny")
            try expectEqual(String(data: try crlfDoc.data(ofType: "public.plain-text"), encoding: .utf8), "x\r\ny")
            defaults.set(0, forKey: Pref.lineEnding)
            let lfDoc = TextDocument()
            lfDoc.textStorage.mutableString.setString("x\ny")
            try expectEqual(String(data: try lfDoc.data(ofType: "public.plain-text"), encoding: .utf8), "x\ny")
        }

        testRunner("TextDocument data(ofType:) normalizes stray CRs; new documents are UTF-8") {
            let doc = TextDocument()
            doc.textStorage.mutableString.setString("a\rb\r\nc ż")
            try expectEqual(try doc.data(ofType: "public.plain-text"), Data("a\nb\nc ż".utf8))
            try expectEqual(doc.encoding, .utf8)
        }

        testRunner("TextDocument writes back exactly what it read: encoding, BOM and line endings") {
            var utf16LE = Data([0xFF, 0xFE]); utf16LE.append("ż\r\nb".data(using: .utf16LittleEndian)!)
            var utf16BE = Data([0xFE, 0xFF]); utf16BE.append("ż\nb".data(using: .utf16BigEndian)!)
            let samples: [(String, Data, String.Encoding)] = [
                ("UTF-8", Data("héllo\nwörld\n".utf8), .utf8),
                ("UTF-8 with BOM", Data([0xEF, 0xBB, 0xBF]) + Data("hi\r\n".utf8), .utf8),
                ("UTF-16 LE", utf16LE, .utf16LittleEndian),
                ("UTF-16 BE", utf16BE, .utf16BigEndian),
                ("Windows-1252", Data([0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A, 0x80]), .windowsCP1252),
                ("Mac Roman", Data([0x81, 0x61, 0x0D, 0x62]), .macOSRoman),
                ("CR only", Data("a\rb\r".utf8), .utf8),
                ("no line break", Data("x".utf8), .utf8),
                ("empty", Data(), .utf8)
            ]
            for (name, bytes, encoding) in samples {
                let doc = TextDocument()
                try doc.read(from: bytes, ofType: "public.plain-text")
                try expectEqual(doc.encoding, encoding, name)
                try expect(doc.saveWarnings.isEmpty, "\(name): \(doc.saveWarnings)")
                try expectEqual(try doc.data(ofType: "public.plain-text"), bytes, name)
            }
        }

        testRunner("TextDocument edits are saved in the file's own encoding") {
            let latin = TextDocument()
            try latin.read(from: Data([0x63, 0x61, 0x66, 0xE9]), ofType: "public.plain-text")   // "café" in Windows-1252
            latin.textStorage.mutableString.append(" €")
            try expectEqual(try latin.data(ofType: "public.plain-text"), Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x80]))

            let wide = TextDocument()
            var bytes = Data([0xFF, 0xFE]); bytes.append("a".data(using: .utf16LittleEndian)!)
            try wide.read(from: bytes, ofType: "public.plain-text")
            wide.textStorage.mutableString.append("\nż")
            var expected = Data([0xFF, 0xFE]); expected.append("a\nż".data(using: .utf16LittleEndian)!)
            try expectEqual(try wide.data(ofType: "public.plain-text"), expected)

            // A character the encoding cannot hold is never dropped or replaced: writing fails instead.
            latin.textStorage.mutableString.append(" ż")
            try expect(!latin.saveWarnings.isEmpty)
            let error = try expectThrows { _ = try latin.data(ofType: "public.plain-text") }
            try expectEqual((error as? CocoaError)?.code, .fileWriteInapplicableStringEncoding)
        }

        testRunner("TextDocument opens files with NUL bytes read-only and saves their bytes unchanged") {
            let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x81, 0xFF, 0x0D])
            let doc = TextDocument()
            try doc.read(from: bytes, ofType: "public.data")
            try expect(doc.isBinary)
            try expect(doc.saveWarnings.isEmpty)
            try expectEqual(try doc.data(ofType: "public.data"), bytes)
            try expect(doc.tabTitle.hasSuffix(" (read-only)"), doc.tabTitle)

            let pane = EditorPane(document: doc)
            try expect(!pane.textView.isEditable, "binary content cannot be edited")

            // Reloading as text makes the same pane editable again.
            let controller = EditorWindowController()
            controller.add(doc)
            let hosted = try unwrap(controller.selectedPane)
            try expect(!hosted.textView.isEditable)
            try doc.read(from: Data("text".utf8), ofType: "public.plain-text")
            try expect(!doc.isBinary)
            try expect(hosted.textView.isEditable)
            try expect(!doc.tabTitle.contains("read-only"))

            // UTF-16 text contains NUL bytes but is not binary.
            var utf16 = Data([0xFF, 0xFE]); utf16.append("ok".data(using: .utf16LittleEndian)!)
            try doc.read(from: utf16, ofType: "public.plain-text")
            try expect(!doc.isBinary)
        }

        testRunner("TextDocument asks before a save would change more than the user's edits") {
            let dir = try TestSupport.temporaryDirectory()
            let latinURL = try TestSupport.writeFile(Data([0x63, 0x61, 0x66, 0xE9]), named: "latin.txt", in: dir)
            let type = try documentController.typeForContents(of: latinURL)
            let latin = try unwrap(try documentController.makeDocument(withContentsOf: latinURL, ofType: type) as? TextDocument)

            func save(_ doc: TextDocument) throws -> Error? {
                var result: Error??
                doc.save(to: try unwrap(doc.fileURL), ofType: type, for: .saveOperation) { result = .some($0) }
                try expect(TestSupport.spin { result != nil }, "save did not complete")
                return result!
            }

            // Representable edits: saved silently, in Windows-1252.
            latin.textStorage.mutableString.append("!")
            try expect(try save(latin) == nil)
            try expect(TestSupport.lossySavePrompts.isEmpty)
            try expectEqual(try Data(contentsOf: latinURL), Data([0x63, 0x61, 0x66, 0xE9, 0x21]))

            // A character Windows-1252 cannot hold: declining leaves the file alone.
            latin.textStorage.mutableString.append("ż")
            TestSupport.lossySaveAnswer = false
            let declined = try save(latin)
            try expectEqual((declined as? CocoaError)?.code, .userCancelled)
            try expectEqual(TestSupport.lossySavePrompts.count, 1)
            try expect(TestSupport.lossySavePrompts[0].contains { $0.contains("UTF-8") }, "\(TestSupport.lossySavePrompts)")
            try expectEqual(try Data(contentsOf: latinURL), Data([0x63, 0x61, 0x66, 0xE9, 0x21]))
            try expectEqual(latin.encoding, .windowsCP1252)

            // Accepting converts to UTF-8, once.
            TestSupport.lossySaveAnswer = true
            try expect(try save(latin) == nil)
            try expectEqual(try String(contentsOf: latinURL, encoding: .utf8), "café!ż")
            try expectEqual(latin.encoding, .utf8)
            try expect(try save(latin) == nil)
            try expectEqual(TestSupport.lossySavePrompts.count, 2, "no prompt once converted")

            // Mixed line endings: one prompt, then the file is uniform.
            let mixedURL = try TestSupport.writeFile("a\r\nb\nc\r\n", named: "mixed.txt", in: dir)
            let mixed = try unwrap(try documentController.makeDocument(withContentsOf: mixedURL, ofType: type) as? TextDocument)
            try expect(try save(mixed) == nil)
            try expectEqual(TestSupport.lossySavePrompts.count, 3)
            try expect(TestSupport.lossySavePrompts[2].contains { $0.contains("mixed line endings") }, "\(TestSupport.lossySavePrompts)")
            try expectEqual(try String(contentsOf: mixedURL, encoding: .utf8), "a\r\nb\r\nc\r\n")
            try expect(!mixed.hasMixedLineEndings)

            // The Save menu command goes through the same check.
            let menuURL = try TestSupport.writeFile("x\ny\r\n", named: "menu.txt", in: dir)
            let viaMenu = try unwrap(try documentController.makeDocument(withContentsOf: menuURL, ofType: type) as? TextDocument)
            TestSupport.lossySaveAnswer = false
            viaMenu.updateChangeCount(.changeDone)
            viaMenu.save(nil)
            try expect(TestSupport.spin { TestSupport.lossySavePrompts.count == 4 }, "File > Save asks too")
            TestSupport.drain(0.2)
            try expectEqual(try String(contentsOf: menuURL, encoding: .utf8), "x\ny\r\n")
        }

        testRunner("TextDocument save on focus lost never prompts about a lossy save") {
            defaults.set(true, forKey: Pref.saveOnFocusLost)
            let doc = try makeFileDocument("a\r\nb\n")
            let url = try unwrap(doc.fileURL)
            doc.textStorage.mutableString.append("c")
            doc.updateChangeCount(.changeDone)
            doc.saveIfWanted()
            TestSupport.drain(0.2)
            try expect(TestSupport.lossySavePrompts.isEmpty, "the user is in another window")
            try expectEqual(try String(contentsOf: url, encoding: .utf8), "a\r\nb\n")
            try expect(doc.isDocumentEdited)
        }

        testRunner("TextDocument revert warns before loading a file that grew too large") {
            let doc = try makeFileDocument("small")
            let url = try unwrap(doc.fileURL)
            documentController.largeFileWarningSize = 10
            try "now much larger than ten bytes".write(to: url, atomically: false, encoding: .utf8)
            TestSupport.largeFileAnswer = false
            let error = try expectThrows { try doc.revert(toContentsOf: url, ofType: doc.fileType ?? "") }
            try expectEqual((error as? CocoaError)?.code, .userCancelled)
            try expectEqual(TestSupport.largeFilePrompts.count, 1)
            try expectEqual(doc.textStorage.string, "small")

            TestSupport.largeFileAnswer = true
            try doc.revert(toContentsOf: url, ofType: doc.fileType ?? "")
            try expectEqual(doc.textStorage.string, "now much larger than ten bytes")
        }

        testRunner("TextDocument reload keeps attributes and clears undo history") {
            let doc = TextDocument()
            try doc.read(from: Data("first".utf8), ofType: "public.plain-text")
            doc.textStorage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 5))
            doc.undoManager?.registerUndo(withTarget: doc) { _ in }
            try expect(doc.undoManager?.canUndo == true)

            try doc.read(from: Data("Reloaded text\nLine 2".utf8), ofType: "public.plain-text")
            try expectEqual(doc.textStorage.string, "Reloaded text\nLine 2")
            try expectEqual(doc.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.red)
            try expect(doc.undoManager?.canUndo == false, "reloading from disk is not undoable")

            // Reading into an empty document uses no attributes, and reading empty data empties it.
            let empty = TextDocument()
            try empty.read(from: Data("x".utf8), ofType: "public.plain-text")
            try expectEqual(empty.textStorage.string, "x")
            try empty.read(from: Data(), ofType: "public.plain-text")
            try expectEqual(empty.textStorage.length, 0)
        }

        testRunner("TextDocument read(from: URL) accepts regular files and symlinks to them") {
            let doc = TextDocument()
            let file = try TestSupport.writeFile("Hello From File\nLine 2")
            try doc.read(from: file, ofType: "public.plain-text")
            try expectEqual(doc.textStorage.string, "Hello From File\nLine 2")

            let link = file.deletingLastPathComponent().appendingPathComponent("link.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            try doc.read(from: link, ofType: "public.plain-text")
            try expectEqual(doc.textStorage.string, "Hello From File\nLine 2")
        }

        testRunner("TextDocument read(from: URL) rejects directories, FIFOs, devices and missing files") {
            let doc = TextDocument()
            try doc.read(from: Data("unchanged".utf8), ofType: "public.plain-text")
            let dir = try TestSupport.temporaryDirectory()

            func expectNotRegular(_ url: URL) throws {
                let error = try expectThrows("\(url.path) must be rejected") { try doc.read(from: url, ofType: "public.plain-text") }
                try expectEqual((error as? CocoaError)?.code, .fileReadUnknown, "\(error)")
                try expect(error.localizedDescription.contains("is not a regular file"), error.localizedDescription)
            }

            try expectNotRegular(dir)

            // A FIFO would block the main thread forever if it were read.
            let fifo = dir.appendingPathComponent("pipe")
            try expectEqual(mkfifo(fifo.path, 0o600), 0)
            try expectNotRegular(fifo)

            // A symlink to a directory is resolved before checking.
            let dirLink = dir.appendingPathComponent("dirlink")
            try FileManager.default.createSymbolicLink(at: dirLink, withDestinationURL: dir)
            try expectNotRegular(dirLink)

            try expectNotRegular(URL(fileURLWithPath: "/dev/null"))

            _ = try expectThrows { try doc.read(from: dir.appendingPathComponent("missing.txt"), ofType: "public.plain-text") }
            try expectEqual(doc.textStorage.string, "unchanged", "a failed read leaves the buffer alone")
        }

        testRunner("TextDocument.readRegularFile reports why a file cannot be read") {
            let dir = try TestSupport.temporaryDirectory()
            let missing = try expectThrows { _ = try TextDocument.readRegularFile(at: dir.appendingPathComponent("nope.txt")) }
            try expectEqual((missing as? CocoaError)?.code, .fileReadNoSuchFile)

            let locked = try TestSupport.writeFile("secret", named: "locked.txt", in: dir)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path) }
            if getuid() != 0 {   // root can read anything
                let denied = try expectThrows { _ = try TextDocument.readRegularFile(at: locked) }
                try expectEqual((denied as? CocoaError)?.code, .fileReadNoPermission)
            }

            // Empty and binary files read exactly.
            try expectEqual(try TextDocument.readRegularFile(at: try TestSupport.writeFile(Data(), named: "empty", in: dir)), Data())
            let bytes = Data((0...255).map { UInt8($0) })
            try expectEqual(try TextDocument.readRegularFile(at: try TestSupport.writeFile(bytes, named: "bin", in: dir)), bytes)

            // Opening a FIFO returns immediately (non-blocking open) and is rejected.
            let fifo = dir.appendingPathComponent("fifo")
            try expectEqual(mkfifo(fifo.path, 0o600), 0)
            let start = Date()
            _ = try expectThrows { _ = try TextDocument.readRegularFile(at: fifo) }
            try expect(Date().timeIntervalSince(start) < 1, "must not wait for a writer")
        }

        testRunner("TextDocument tabTitle marks unsaved changes") {
            let doc = TextDocument()
            let baseTitle = doc.displayName ?? ""
            try expectEqual(doc.tabTitle, baseTitle)

            doc.updateChangeCount(.changeDone)
            try expect(doc.isDocumentEdited)
            try expectEqual(doc.tabTitle, "* " + baseTitle)

            doc.updateChangeCount(.changeUndone)
            try expectEqual(doc.tabTitle, baseTitle)

            // A save that started before the latest edit leaves the document edited; one that included it clears it.
            let staleToken = doc.changeCountToken(for: .saveOperation)
            doc.updateChangeCount(.changeDone)
            try expect(doc.tabTitle.hasPrefix("* "))
            doc.updateChangeCount(withToken: staleToken, for: .saveOperation)
            try expect(doc.isDocumentEdited, "edits made after the save started are still unsaved")
            let token = doc.changeCountToken(for: .saveOperation)
            doc.updateChangeCount(withToken: token, for: .saveOperation)
            try expect(!doc.isDocumentEdited)
            try expectEqual(doc.tabTitle, baseTitle)
        }

        testRunner("TextDocument change count and fileURL changes refresh the host window title") {
            let controller = EditorWindowController()
            let doc = TextDocument()
            controller.add(doc)
            let window = try unwrap(controller.window)
            try expect(!window.isDocumentEdited)

            doc.updateChangeCount(.changeDone)
            try expect(window.isDocumentEdited)
            try expect(window.title.hasPrefix("* "))

            let token = doc.changeCountToken(for: .saveOperation)
            doc.updateChangeCount(withToken: token, for: .saveOperation)
            try expect(!window.isDocumentEdited)

            let url = try TestSupport.writeFile("x", named: "renamed.txt")
            doc.fileURL = url
            try expectEqual(window.representedURL, url)
            try expectEqual(window.title, "renamed.txt")
        }

        testRunner("TextDocument prepareSavePanel allows any extension") {
            let doc = TextDocument()
            let savePanel = NSSavePanel()
            try expect(doc.prepareSavePanel(savePanel))
            try expect(savePanel.allowedContentTypes.isEmpty)
            try expect(savePanel.allowsOtherFileTypes)
        }

        testRunner("TextDocument printOperation prints black text at page width, independent of the editor") {
            let doc = TextDocument()
            doc.textStorage.mutableString.setString("Printable content line 1\nLine 2")
            let operation = try doc.printOperation(withSettings: [:])
            try expectEqual(operation.printInfo.horizontalPagination, .fit)
            try expect(!operation.printInfo.isVerticallyCentered)
            let view = try unwrap(operation.view as? NSTextView)
            try expectEqual(view.string, "Printable content line 1\nLine 2")
            try expectEqual(view.textColor, .black)
            try expect(!view.drawsBackground)
            try expectEqual(view.font?.pointSize, 10)
            let info = operation.printInfo
            try expectEqual(view.frame.width, info.paperSize.width - info.leftMargin - info.rightMargin)
            try expect(view.frame.height > 0, "sized to fit its text")
        }

        testRunner("TextDocument typing after a save marks the document edited again") {
            let doc = try makeFileDocument("")
            let url = try unwrap(doc.fileURL)
            let controller = EditorWindowController()
            controller.add(doc)
            controller.showWindow(nil)
            let pane = try unwrap(controller.selectedPane)
            let window = try unwrap(controller.window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(pane.textView)

            // Type the way the keyboard does: one insertText per key, with the run loop turning in between.
            func type(_ text: String) {
                for character in text {
                    pane.textView.insertText(String(character), replacementRange: pane.textView.selectedRange())
                    TestSupport.drain(0.01)
                }
            }

            type("abc")
            try expect(doc.isDocumentEdited)
            for operation in ["File > Save", "save on focus lost"] {
                if operation == "File > Save" {
                    doc.save(nil)
                } else {
                    defaults.set(true, forKey: Pref.saveOnFocusLost)
                    doc.saveIfWanted()
                }
                try expect(TestSupport.spin { !doc.isDocumentEdited }, "\(operation): saved")
                type("d")
                try expect(TestSupport.spin { doc.isDocumentEdited }, "\(operation): typing after the save must mark the document edited")
                try expect(window.isDocumentEdited && window.title.hasPrefix("* "), "\(operation): \(window.title)")
            }
            doc.save(nil)
            try expect(TestSupport.spin { (try? String(contentsOf: url, encoding: .utf8)) == "abcdd" })

            // Undo after a save goes back past it, and marks the document edited.
            doc.undoManager?.undo()
            try expectEqual(doc.textStorage.string, "abcd", "the typing after the last save is its own undo step")
            try expect(doc.isDocumentEdited)
        }

        testRunner("TextDocument saveIfWanted saves only an edited, file-backed document with no sheet up") {
            let doc = try makeFileDocument("original")
            let url = try unwrap(doc.fileURL)
            let controller = EditorWindowController()
            controller.add(doc)
            let window = try unwrap(controller.window)

            func edit(_ text: String) {
                doc.textStorage.mutableString.setString(text)
                doc.updateChangeCount(.changeDone)
            }
            func fileContents() throws -> String { return try String(contentsOf: url, encoding: .utf8) }

            // Preference off: nothing is saved.
            defaults.set(false, forKey: Pref.saveOnFocusLost)
            edit("pref off")
            doc.saveIfWanted()
            TestSupport.drain(0.2)
            try expectEqual(try fileContents(), "original")

            // A sheet is up: nothing is saved (the save must not race a prompt).
            defaults.set(true, forKey: Pref.saveOnFocusLost)
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            window.beginSheet(sheet)
            if window.attachedSheet != nil {
                doc.saveIfWanted()
                TestSupport.drain(0.2)
                try expectEqual(try fileContents(), "original")
                window.endSheet(sheet)
            }

            // Not edited: nothing to save.
            doc.updateChangeCount(.changeCleared)
            doc.saveIfWanted()
            TestSupport.drain(0.2)
            try expectEqual(try fileContents(), "original")

            // All conditions met: the document is written to its file.
            edit("saved on focus lost")
            doc.saveIfWanted()
            try expect(TestSupport.spin { (try? fileContents()) == "saved on focus lost" }, "file was not saved")
            try expect(TestSupport.spin { !doc.isDocumentEdited })

            // Untitled document: never saved (that would need a save panel).
            let untitled = TextDocument()
            untitled.updateChangeCount(.changeDone)
            untitled.saveIfWanted()
            try expect(untitled.fileURL == nil)
        }

        testRunner("TextDocument window lifecycle: showWindows, windowForSheet, canClose and close") {
            let doc = TextDocument()
            try expect(doc.windowForSheet == nil, "a document without a tab has no sheet window")
            doc.makeWindowControllers()
            try expect(doc.windowControllers.isEmpty, "documents never own window controllers")

            // showWindows puts a hostless document into a window.
            doc.showWindows()
            let host = try unwrap(doc.host)
            try expect(host.pane(for: doc) != nil)

            // windowForSheet selects the document's tab, without saving the tab it leaves.
            let other = TextDocument()
            host.add(other)
            try expect(host.selectedPane?.document === other)
            try expect(doc.windowForSheet === host.window)
            try expect(host.selectedPane?.document === doc)

            // showWindows on a hosted document selects its tab in the same window.
            other.showWindows()
            try expect(other.host === host)
            try expect(host.selectedPane?.document === other)

            var shouldClose: Bool?
            let request = CloseRequest { shouldClose = $0 }
            doc.canClose(withDelegate: request, shouldClose: #selector(CloseRequest.document(_:shouldClose:contextInfo:)), contextInfo: nil)
            try expect(TestSupport.spin { shouldClose != nil })
            try expectEqual(shouldClose, true, "a clean document can close")

            doc.close()
            try expect(host.pane(for: doc) == nil)
            try expectEqual(host.panes.count, 1)
        }

        testRunner("TextDocument canClose discards changes without asking when confirmation is off") {
            defaults.set(false, forKey: Pref.confirmClose)
            let doc = TextDocument()
            doc.updateChangeCount(.changeDone)
            var shouldClose: Bool?
            let request = CloseRequest { shouldClose = $0 }
            doc.canClose(withDelegate: request, shouldClose: #selector(CloseRequest.document(_:shouldClose:contextInfo:)), contextInfo: nil)
            try expect(TestSupport.spin { shouldClose != nil })
            try expectEqual(shouldClose, true)
            try expect(!doc.isDocumentEdited)
        }
    }
}
