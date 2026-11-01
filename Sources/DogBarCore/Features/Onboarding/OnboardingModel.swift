import AppKit
import Combine

/// Navigation state for one presentation of the wizard. Moves only when the user acts:
/// permission changes update a step's content but never advance it.
@MainActor public final class OnboardingModel: ObservableObject {
    @Published public private(set) var mode: OnboardingMode = .firstRun
    @Published public private(set) var steps: [OnboardingStep] = [.welcome]
    @Published public private(set) var index = 0
    @Published private(set) var forward = true
    private let store: OnboardingStore
    var onFinish: (() -> Void)?

    init(store: OnboardingStore) { self.store = store }

    public var step: OnboardingStep { steps[min(index, steps.count - 1)] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }
    /// The setup step, for Skip on the welcome and feature screens.
    var setupIndex: Int? { steps.firstIndex(of: .setup) }

    func configure(mode: OnboardingMode, steps: [OnboardingStep], start: Int) {
        self.mode = mode; self.steps = steps.isEmpty ? [.setup] : steps
        forward = true
        index = min(max(0, start), self.steps.count - 1)
        persist()
    }
    func next() {
        guard !isLast else { finish(); return }
        forward = true; index += 1; persist()
    }
    func back() {
        guard index > 0 else { return }
        forward = false; index -= 1; persist()
    }
    func go(to step: OnboardingStep) {
        guard let target = steps.firstIndex(of: step), target != index else { return }
        forward = target > index; index = target; persist()
    }
    func skipToSetup() {
        guard let target = setupIndex else { return }
        forward = true; index = target; persist()
    }
    func finish() { onFinish?() }
    /// Only the first-run tour remembers its place, so a relaunch (for example Quit & Reopen
    /// after Screen Recording) returns to the exact step.
    private func persist() { if mode == .firstRun { store.resumeStep = step } }
}

/// A DogBar copy installed in an Applications folder, other than the running one.
enum InstalledCopy {
    static func find(bundle: Bundle = .main) -> URL? {
        let fileManager = FileManager.default
        let candidates = [URL(fileURLWithPath: "/Applications/DogBar.app"),
                          fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/DogBar.app")]
        let running = bundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        return candidates.first { url in
            guard url.resolvingSymlinksInPath().standardizedFileURL != running,
                  let candidate = Bundle(url: url) else { return false }
            return candidate.bundleIdentifier == bundle.bundleIdentifier
        }
    }

    /// Quits this copy, letting the normal quit path restore the native Dock first, then opens
    /// the installed copy. Nothing is copied or deleted.
    static func openAndQuit(_ url: URL) throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Arguments carry the path and PID literally. Never interpolate a bundle path into shell code.
        helper.arguments = ["-c", """
        attempts=0
        while /bin/kill -0 "$1" 2>/dev/null; do
            attempts=$((attempts + 1))
            [ "$attempts" -lt 300 ] || exit 1
            /bin/sleep 0.1
        done
        exec /usr/bin/open "$2"
        """, "DogBar-open-installed", String(ProcessInfo.processInfo.processIdentifier), url.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        NSApp.terminate(nil)
    }
}
