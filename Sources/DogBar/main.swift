import AppKit
import DogBarCore

// Hook relay mode (`DogBar --agent-hook claude|codex`): forward one event and exit before any UI starts.
if let status = AgentHookRelay.runIfRequested() { exit(status) }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(delegate.settings.showDogBarInDock ? .regular : .accessory)
    withExtendedLifetime(delegate) { application.run() }
}
