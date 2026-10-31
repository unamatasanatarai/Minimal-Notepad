import AppKit

public enum PrefAndHelpersTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Pref constants and registerDefaults") {
            Pref.registerDefaults()
            try expect(Pref.lineEnding == "DefaultLineEnding")
            try expect(Pref.wordWrap == "DefaultWordWrap")
            try expect(Pref.appearance == "Appearance")
            try expect(Pref.restoreSession == "RestoreSession")
            try expect(Pref.confirmClose == "ConfirmClose")
            try expect(Pref.showLineNumbers == "ShowLineNumbers")
            try expect(Pref.showInvisibles == "ShowInvisibles")
            try expect(Pref.saveOnFocusLost == "SaveOnFocusLost")
            try expect(Pref.sessionFiles == "SessionFiles")

            try expect(defaults.integer(forKey: Pref.lineEnding) == 0 || defaults.integer(forKey: Pref.lineEnding) == 1)
            try expect(defaults.object(forKey: Pref.wordWrap) != nil)
            try expect(defaults.object(forKey: Pref.appearance) != nil)
            try expect(defaults.object(forKey: Pref.restoreSession) != nil)
            try expect(defaults.object(forKey: Pref.confirmClose) != nil)
            try expect(defaults.object(forKey: Pref.showLineNumbers) != nil)
            try expect(defaults.object(forKey: Pref.showInvisibles) != nil)
            try expect(defaults.object(forKey: Pref.saveOnFocusLost) != nil)
        }

        testRunner("editorFont sizing bounds and properties") {
            let fontDefault = editorFont(size: 13)
            try expect(fontDefault.pointSize == 13)
            try expect(fontDefault.isFixedPitch || fontDefault.fontDescriptor.symbolicTraits.contains(.monoSpace))

            let fontLarge = editorFont(size: 72)
            try expect(fontLarge.pointSize == 72)

            let fontSmall = editorFont(size: 6)
            try expect(fontSmall.pointSize == 6)
        }

        testRunner("dimmedTextColor appearance adaptation") {
            if let lightAppearance = NSAppearance(named: .aqua) {
                var resolvedLight: NSColor?
                lightAppearance.performAsCurrentDrawingAppearance {
                    resolvedLight = dimmedTextColor.usingColorSpace(.genericRGB)
                }
                try expect(resolvedLight != nil, "Light appearance should resolve color")
                if let light = resolvedLight {
                    try expect(abs(light.alphaComponent - 0.18) < 0.05, "Alpha should be ~0.18")
                    try expect(light.redComponent < 0.1, "White 0 should have low red value")
                }
            }

            if let darkAppearance = NSAppearance(named: .darkAqua) {
                var resolvedDark: NSColor?
                darkAppearance.performAsCurrentDrawingAppearance {
                    resolvedDark = dimmedTextColor.usingColorSpace(.genericRGB)
                }
                try expect(resolvedDark != nil, "Dark appearance should resolve color")
                if let dark = resolvedDark {
                    try expect(abs(dark.alphaComponent - 0.18) < 0.05, "Alpha should be ~0.18")
                    try expect(dark.redComponent > 0.9, "White 1 should have high red value")
                }
            }
        }

        testRunner("NSRange array firstIndex(endingAfter:) binary search edge cases") {
            let empty: [NSRange] = []
            try expect(empty.firstIndex(endingAfter: 0) == 0)
            try expect(empty.firstIndex(endingAfter: 100) == 0)
            try expect(empty.firstIndex(endingAfter: -5) == 0)

            let single = [NSRange(location: 5, length: 5)] // 5..<10
            try expect(single.firstIndex(endingAfter: -1) == 0)
            try expect(single.firstIndex(endingAfter: 4) == 0)
            try expect(single.firstIndex(endingAfter: 5) == 0)
            try expect(single.firstIndex(endingAfter: 9) == 0)
            try expect(single.firstIndex(endingAfter: 10) == 1)
            try expect(single.firstIndex(endingAfter: 15) == 1)

            // Multiple disjoint ranges: [0..<5, 10..<15, 20..<25]
            let multiple = [
                NSRange(location: 0, length: 5),
                NSRange(location: 10, length: 5),
                NSRange(location: 20, length: 5)
            ]
            try expect(multiple.firstIndex(endingAfter: -1) == 0)
            try expect(multiple.firstIndex(endingAfter: 0) == 0)
            try expect(multiple.firstIndex(endingAfter: 4) == 0)
            try expect(multiple.firstIndex(endingAfter: 5) == 1)
            try expect(multiple.firstIndex(endingAfter: 9) == 1)
            try expect(multiple.firstIndex(endingAfter: 10) == 1)
            try expect(multiple.firstIndex(endingAfter: 14) == 1)
            try expect(multiple.firstIndex(endingAfter: 15) == 2)
            try expect(multiple.firstIndex(endingAfter: 19) == 2)
            try expect(multiple.firstIndex(endingAfter: 20) == 2)
            try expect(multiple.firstIndex(endingAfter: 24) == 2)
            try expect(multiple.firstIndex(endingAfter: 25) == 3)
            try expect(multiple.firstIndex(endingAfter: 999) == 3)

            // Contiguous / adjacent ranges: [0..<5, 5..<10]
            let adjacent = [
                NSRange(location: 0, length: 5),
                NSRange(location: 5, length: 5)
            ]
            try expect(adjacent.firstIndex(endingAfter: 0) == 0)
            try expect(adjacent.firstIndex(endingAfter: 4) == 0)
            try expect(adjacent.firstIndex(endingAfter: 5) == 1)
            try expect(adjacent.firstIndex(endingAfter: 9) == 1)
            try expect(adjacent.firstIndex(endingAfter: 10) == 2)

            // Zero-length ranges: [5..<5, 10..<10]
            let zeroLength = [
                NSRange(location: 5, length: 0),
                NSRange(location: 10, length: 0)
            ]
            try expect(zeroLength.firstIndex(endingAfter: 4) == 0)
            try expect(zeroLength.firstIndex(endingAfter: 5) == 1)
            try expect(zeroLength.firstIndex(endingAfter: 9) == 1)
            try expect(zeroLength.firstIndex(endingAfter: 10) == 2)
        }
    }
}
