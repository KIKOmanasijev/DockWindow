import AppKit
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(delegate.settings.showDogBarInDock ? .regular : .accessory)
    withExtendedLifetime(delegate) { application.run() }
}
