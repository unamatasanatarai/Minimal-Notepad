import Cocoa

/// Kills the run when one test blocks (typically on an app-modal alert), naming the test, instead of hanging forever.
private final class Watchdog {
    private let lock = NSLock()
    private var current: (name: String, start: Date)?
    private let timer: DispatchSourceTimer

    init(limit: TimeInterval) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "test.watchdog"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [unowned self] in
            self.lock.lock()
            let running = self.current
            self.lock.unlock()
            if let running = running, Date().timeIntervalSince(running.start) > limit {
                print("  ⏱  TIMEOUT: \(running.name) blocked for more than \(Int(limit))s (modal alert?)")
                exit(3)
            }
        }
        timer.resume()
    }

    func begin(_ name: String) {
        lock.lock(); current = (name, Date()); lock.unlock()
    }

    func end() {
        lock.lock(); current = nil; lock.unlock()
    }
}

/// Set once the summary is printed. If anything (such as NSApp.terminate) exits the process before that,
/// the atexit handler turns the run into a failure instead of a silent "success".
private var suiteFinished = false

@main
struct TestMain {
    static func main() {
        atexit {
            if !suiteFinished {
                print("\n  ❌ The test process exited before the suite finished.")
                _exit(4)
            }
        }
        _ = NSApplication.shared
        _ = documentController   // first instance becomes NSDocumentController.shared
        Pref.registerDefaults()
        TestSupport.reset()

        // Optional filter: only tests whose name contains the first argument.
        let filter = CommandLine.arguments.dropFirst().first

        print("==================================================")
        print("         Running Swift Native Test Suite          ")
        print("==================================================")

        var passed = 0
        var failed = 0
        var failures: [String] = []
        let totalStart = CFAbsoluteTimeGetCurrent()
        let watchdog = Watchdog(limit: 30)

        let runTest: (String, () throws -> Void) -> Void = { name, block in
            if let filter = filter, !name.localizedCaseInsensitiveContains(filter) { return }
            let start = CFAbsoluteTimeGetCurrent()
            watchdog.begin(name)
            defer {
                watchdog.end()
                TestSupport.reset()
            }
            do {
                try block()
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                print(String(format: "  ✔ PASS: %@ (%.2fms)", name, elapsedMs))
                passed += 1
            } catch {
                print("  ❌ FAIL: \(name) - \(error)")
                failures.append("\(name) - \(error)")
                failed += 1
            }
        }

        print("\n--- Application Configuration & State Suite ---")
        AppTests.run(testRunner: runTest)

        print("\n--- Preferences, Fonts & Helper Utilities Suite ---")
        PrefAndHelpersTests.run(testRunner: runTest)

        print("\n--- TextDocument Model, Encoding & I/O Suite ---")
        TextDocumentTests.run(testRunner: runTest)

        print("\n--- DocumentController & Document Management Suite ---")
        DocumentControllerTests.run(testRunner: runTest)

        print("\n--- EditorWindowController & Tabs Coordination Suite ---")
        EditorWindowControllerTests.run(testRunner: runTest)

        print("\n--- EditorPane, Search, Replace & Zoom Suite ---")
        EditorPaneTests.run(testRunner: runTest)

        print("\n--- Custom Views, TabBar, Ruler & Layout Suite ---")
        CustomViewsTests.run(testRunner: runTest)

        print("\n--- AppDelegate, Menus & Settings Window Suite ---")
        AppDelegateAndSettingsTests.run(testRunner: runTest)

        let totalElapsedMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0

        print("\n==================================================")
        print(String(format: "  Summary: %d Passed | %d Failed (Total: %.2fms)", passed, failed, totalElapsedMs))
        failures.forEach { print("  ❌ \($0)") }
        print("==================================================")

        if let domain = ProcessInfo.processInfo.environment["TEST_BUNDLE_ID"] {
            defaults.removePersistentDomain(forName: domain)
        }
        suiteFinished = true
        exit(failed > 0 ? 1 : 0)
    }
}
