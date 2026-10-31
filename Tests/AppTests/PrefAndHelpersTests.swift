import AppKit

public enum PrefAndHelpersTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Pref constants and registerDefaults") {
            Pref.registerDefaults()
            assert(Pref.lineEnding == "DefaultLineEnding")
            assert(Pref.wordWrap == "DefaultWordWrap")
            assert(Pref.appearance == "Appearance")
            assert(Pref.restoreSession == "RestoreSession")
            assert(Pref.confirmClose == "ConfirmClose")
            assert(Pref.showLineNumbers == "ShowLineNumbers")
            assert(Pref.showInvisibles == "ShowInvisibles")
            assert(Pref.saveOnFocusLost == "SaveOnFocusLost")
            assert(Pref.sessionFiles == "SessionFiles")

            assert(defaults.integer(forKey: Pref.lineEnding) == 0 || defaults.integer(forKey: Pref.lineEnding) == 1)
            assert(defaults.object(forKey: Pref.wordWrap) != nil)
            assert(defaults.object(forKey: Pref.appearance) != nil)
            assert(defaults.object(forKey: Pref.restoreSession) != nil)
            assert(defaults.object(forKey: Pref.confirmClose) != nil)
            assert(defaults.object(forKey: Pref.showLineNumbers) != nil)
            assert(defaults.object(forKey: Pref.showInvisibles) != nil)
            assert(defaults.object(forKey: Pref.saveOnFocusLost) != nil)
        }

        testRunner("editorFont sizing bounds and properties") {
            let fontDefault = editorFont(size: 13)
            assert(fontDefault.pointSize == 13)
            assert(fontDefault.isFixedPitch || fontDefault.fontDescriptor.symbolicTraits.contains(.monoSpace))

            let fontLarge = editorFont(size: 72)
            assert(fontLarge.pointSize == 72)

            let fontSmall = editorFont(size: 6)
            assert(fontSmall.pointSize == 6)
        }

        testRunner("dimmedTextColor appearance adaptation") {
            if let lightAppearance = NSAppearance(named: .aqua) {
                var resolvedLight: NSColor?
                lightAppearance.performAsCurrentDrawingAppearance {
                    resolvedLight = dimmedTextColor.usingColorSpace(.genericRGB)
                }
                assert(resolvedLight != nil, "Light appearance should resolve color")
                if let light = resolvedLight {
                    assert(abs(light.alphaComponent - 0.18) < 0.05, "Alpha should be ~0.18")
                    assert(light.redComponent < 0.1, "White 0 should have low red value")
                }
            }

            if let darkAppearance = NSAppearance(named: .darkAqua) {
                var resolvedDark: NSColor?
                darkAppearance.performAsCurrentDrawingAppearance {
                    resolvedDark = dimmedTextColor.usingColorSpace(.genericRGB)
                }
                assert(resolvedDark != nil, "Dark appearance should resolve color")
                if let dark = resolvedDark {
                    assert(abs(dark.alphaComponent - 0.18) < 0.05, "Alpha should be ~0.18")
                    assert(dark.redComponent > 0.9, "White 1 should have high red value")
                }
            }
        }

        testRunner("NSRange array firstIndex(endingAfter:) binary search edge cases") {
            let empty: [NSRange] = []
            assert(empty.firstIndex(endingAfter: 0) == 0)
            assert(empty.firstIndex(endingAfter: 100) == 0)
            assert(empty.firstIndex(endingAfter: -5) == 0)

            let single = [NSRange(location: 5, length: 5)] // 5..<10
            assert(single.firstIndex(endingAfter: -1) == 0)
            assert(single.firstIndex(endingAfter: 4) == 0)
            assert(single.firstIndex(endingAfter: 5) == 0)
            assert(single.firstIndex(endingAfter: 9) == 0)
            assert(single.firstIndex(endingAfter: 10) == 1)
            assert(single.firstIndex(endingAfter: 15) == 1)

            // Multiple disjoint ranges: [0..<5, 10..<15, 20..<25]
            let multiple = [
                NSRange(location: 0, length: 5),
                NSRange(location: 10, length: 5),
                NSRange(location: 20, length: 5)
            ]
            assert(multiple.firstIndex(endingAfter: -1) == 0)
            assert(multiple.firstIndex(endingAfter: 0) == 0)
            assert(multiple.firstIndex(endingAfter: 4) == 0)
            assert(multiple.firstIndex(endingAfter: 5) == 1)
            assert(multiple.firstIndex(endingAfter: 9) == 1)
            assert(multiple.firstIndex(endingAfter: 10) == 1)
            assert(multiple.firstIndex(endingAfter: 14) == 1)
            assert(multiple.firstIndex(endingAfter: 15) == 2)
            assert(multiple.firstIndex(endingAfter: 19) == 2)
            assert(multiple.firstIndex(endingAfter: 20) == 2)
            assert(multiple.firstIndex(endingAfter: 24) == 2)
            assert(multiple.firstIndex(endingAfter: 25) == 3)
            assert(multiple.firstIndex(endingAfter: 999) == 3)

            // Contiguous / adjacent ranges: [0..<5, 5..<10]
            let adjacent = [
                NSRange(location: 0, length: 5),
                NSRange(location: 5, length: 5)
            ]
            assert(adjacent.firstIndex(endingAfter: 0) == 0)
            assert(adjacent.firstIndex(endingAfter: 4) == 0)
            assert(adjacent.firstIndex(endingAfter: 5) == 1)
            assert(adjacent.firstIndex(endingAfter: 9) == 1)
            assert(adjacent.firstIndex(endingAfter: 10) == 2)

            // Zero-length ranges: [5..<5, 10..<10]
            let zeroLength = [
                NSRange(location: 5, length: 0),
                NSRange(location: 10, length: 0)
            ]
            assert(zeroLength.firstIndex(endingAfter: 4) == 0)
            assert(zeroLength.firstIndex(endingAfter: 5) == 1)
            assert(zeroLength.firstIndex(endingAfter: 9) == 1)
            assert(zeroLength.firstIndex(endingAfter: 10) == 2)
        }
    }
}
