import AppKit

public enum TextDocumentTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("TextDocument line ending normalization") {
            // Pure LF
            let lf = "Alpha\nBeta\nGamma" as NSString
            assert(TextDocument.normalizeLineEndings(lf) == "Alpha\nBeta\nGamma")

            // CRLF
            let crlf = "Alpha\r\nBeta\r\nGamma" as NSString
            assert(TextDocument.normalizeLineEndings(crlf) == "Alpha\nBeta\nGamma")

            // Classic Mac CR
            let cr = "Alpha\rBeta\rGamma" as NSString
            assert(TextDocument.normalizeLineEndings(cr) == "Alpha\nBeta\nGamma")

            // Mixed CR, CRLF, LF
            let mixed = "Alpha\r\nBeta\rGamma\nDelta\r\n" as NSString
            assert(TextDocument.normalizeLineEndings(mixed) == "Alpha\nBeta\nGamma\nDelta\n")

            // Empty string
            let empty = "" as NSString
            assert(TextDocument.normalizeLineEndings(empty) == "")

            // String without newlines
            let singleLine = "Single line of text without breaks" as NSString
            assert(TextDocument.normalizeLineEndings(singleLine) == "Single line of text without breaks")
        }

        testRunner("TextDocument data decoding encodings and fallbacks") {
            // UTF-8
            let utf8Str = "Hello Swift ⚡️ World!"
            let utf8Data = Data(utf8Str.utf8)
            assert(TextDocument.decode(utf8Data) == utf8Str)

            // UTF-16 LE with BOM (0xFF, 0xFE)
            let utf16LEStr = "UTF16 Little Endian"
            var utf16LEData = Data([0xFF, 0xFE])
            utf16LEData.append(utf16LEStr.data(using: .utf16LittleEndian)!)
            assert(TextDocument.decode(utf16LEData) == utf16LEStr)

            // UTF-16 BE with BOM (0xFE, 0xFF)
            let utf16BEStr = "UTF16 Big Endian"
            var utf16BEData = Data([0xFE, 0xFF])
            utf16BEData.append(utf16BEStr.data(using: .utf16BigEndian)!)
            assert(TextDocument.decode(utf16BEData) == utf16BEStr)

            // Windows CP1252 (e.g. 0x80 is Euro sign '€')
            let cp1252Data = Data([0x80, 0x61, 0x62])
            let decoded1252 = TextDocument.decode(cp1252Data)
            assert(!decoded1252.isEmpty)

            // macOSRoman fallback
            let romanData = Data([0xA5, 0x61, 0x62]) // bullet •
            let decodedRoman = TextDocument.decode(romanData)
            assert(!decodedRoman.isEmpty)

            // Arbitrary raw bytes
            let rawBytes = Data([0xC0, 0xC1, 0xF5, 0xFF])
            let decodedRaw = TextDocument.decode(rawBytes)
            assert(!decodedRaw.isEmpty)
        }

        testRunner("TextDocument read, line ending detection, and data export") {
            let doc = TextDocument()
            assert(TextDocument.autosavesInPlace == false)
            assert(doc.shouldRunSavePanelWithAccessoryView == false)

            // Read CRLF content
            let crlfContent = "Hello\r\nWorld\r\n"
            try doc.read(from: Data(crlfContent.utf8), ofType: "public.plain-text")
            assert(doc.textStorage.string == "Hello\nWorld\n")

            // Export data: should write out CRLF
            let exportedCRLF = try doc.data(ofType: "public.plain-text")
            let exportedStr1 = String(data: exportedCRLF, encoding: .utf8)
            assert(exportedStr1 == "Hello\r\nWorld\r\n")

            // Read LF content
            let lfContent = "First\nSecond\nThird"
            try doc.read(from: Data(lfContent.utf8), ofType: "public.plain-text")
            assert(doc.textStorage.string == "First\nSecond\nThird")

            // Export data: should write out LF
            let exportedLF = try doc.data(ofType: "public.plain-text")
            let exportedStr2 = String(data: exportedLF, encoding: .utf8)
            assert(exportedStr2 == "First\nSecond\nThird")

            // Attributes preservation across reload
            doc.textStorage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 5))
            try doc.read(from: Data("Reloaded text\nLine 2".utf8), ofType: "public.plain-text")
            assert(doc.textStorage.string == "Reloaded text\nLine 2")
            if doc.textStorage.length > 0 {
                let color = doc.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                assert(color == NSColor.red)
            }
        }

        testRunner("TextDocument file reading and error handling") {
            let doc = TextDocument()

            // Reading a directory must throw CocoaError.fileReadUnknown
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            var threwExpected = false
            do {
                try doc.read(from: tempDir, ofType: "public.plain-text")
            } catch let error as CocoaError {
                threwExpected = (error.code == .fileReadUnknown)
                assert(error.localizedDescription.contains("is not a regular file and cannot be opened"))
            } catch {
                threwExpected = false
            }
            assert(threwExpected, "Reading directory must fail with CocoaError.fileReadUnknown")

            // Reading a regular temporary file
            let tempFile = tempDir.appendingPathComponent("test_read_\(UUID().uuidString).txt")
            try "Hello From File\nLine 2".write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            try doc.read(from: tempFile, ofType: "public.plain-text")
            assert(doc.textStorage.string == "Hello From File\nLine 2")
        }

        testRunner("TextDocument tabTitle asterisk indication on edit state") {
            let doc = TextDocument()
            let baseTitle = doc.displayName ?? ""
            assert(doc.tabTitle == baseTitle)
            assert(!doc.tabTitle.hasPrefix("* "))

            doc.updateChangeCount(.changeDone)
            assert(doc.isDocumentEdited)
            assert(doc.tabTitle == "* " + baseTitle)

            doc.updateChangeCount(.changeUndone)
            assert(!doc.isDocumentEdited)
            assert(doc.tabTitle == baseTitle)

            // Token-based change count update
            let token = doc.changeCountToken(for: .saveOperation)
            doc.updateChangeCount(.changeDone)
            assert(doc.tabTitle.hasPrefix("* "))
            doc.updateChangeCount(withToken: token, for: .saveOperation)
        }

        testRunner("TextDocument prepareSavePanel and printOperation") {
            let doc = TextDocument()
            doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Printable content line 1\nLine 2")

            let savePanel = NSSavePanel()
            let allowed = doc.prepareSavePanel(savePanel)
            assert(allowed == true)
            assert(savePanel.allowedContentTypes.isEmpty)
            assert(savePanel.allowsOtherFileTypes == true)

            let printOp = try doc.printOperation(withSettings: [:])
            assert(printOp.view != nil)
            assert(printOp.printInfo.horizontalPagination == .fit)
            assert(printOp.printInfo.isVerticallyCentered == false)
            if let tv = printOp.view as? NSTextView {
                assert(tv.string == "Printable content line 1\nLine 2")
                assert(tv.textColor == .black)
                assert(tv.drawsBackground == false)
            }
        }

        testRunner("TextDocument saveIfWanted branching logic") {
            let doc = TextDocument()
            let originalSaveOnFocus = defaults.bool(forKey: Pref.saveOnFocusLost)
            defer { defaults.set(originalSaveOnFocus, forKey: Pref.saveOnFocusLost) }

            // Branch 1: Pref.saveOnFocusLost is false
            defaults.set(false, forKey: Pref.saveOnFocusLost)
            doc.fileURL = URL(fileURLWithPath: "/tmp/sample.txt")
            doc.updateChangeCount(.changeDone)
            doc.saveIfWanted() // Should early return without saving

            // Branch 2: fileURL is nil
            defaults.set(true, forKey: Pref.saveOnFocusLost)
            doc.fileURL = nil
            doc.updateChangeCount(.changeDone)
            doc.saveIfWanted() // Should early return without saving

            // Branch 3: !isDocumentEdited
            doc.fileURL = URL(fileURLWithPath: "/tmp/sample.txt")
            doc.updateChangeCount(.changeCleared)
            doc.saveIfWanted() // Should early return without saving

            // Branch 4: window attachedSheet != nil
            let windowController = EditorWindowController()
            windowController.add(doc)
            assert(doc.host === windowController)

            // Branch 5: windowForSheet selection
            let sheetWin = doc.windowForSheet
            assert(sheetWin === windowController.window)

            // Document lifecycle showWindows, makeWindowControllers, canClose, close
            doc.makeWindowControllers()
            doc.showWindows()

            var shouldCloseCalled = false
            let closeRequest = CloseRequest { success in
                shouldCloseCalled = true
            }
            doc.canClose(withDelegate: closeRequest, shouldClose: #selector(CloseRequest.document(_:shouldClose:contextInfo:)), contextInfo: nil)
            assert(shouldCloseCalled)

            doc.close()
            assert(windowController.pane(for: doc) == nil)
            assert(windowController.panes.isEmpty)
        }
    }
}
