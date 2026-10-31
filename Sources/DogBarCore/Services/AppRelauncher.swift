import AppKit

/// Starts a fresh installed application after the old process finishes restoring the Dock.
@MainActor public enum AppRelauncher {
    public static func relaunch() throws {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else { throw CocoaError(.executableNotLoadable) }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Arguments carry the path and PID literally. Never interpolate a bundle path into shell code.
        // Do not launch a second instance if termination is cancelled or restoration times out.
        helper.arguments = ["-c", """
        attempts=0
        while /bin/kill -0 "$1" 2>/dev/null; do
            attempts=$((attempts + 1))
            [ "$attempts" -lt 300 ] || exit 1
            /bin/sleep 0.1
        done
        exec /usr/bin/open -n "$2"
        """, "DogBar-relaunch", String(ProcessInfo.processInfo.processIdentifier), appURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        NSApp.terminate(nil)
    }
}
