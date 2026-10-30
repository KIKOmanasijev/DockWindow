import SwiftUI
import DockWindowCore

struct PermissionsView: View {
    @ObservedObject var permissions: PermissionsService
    @State private var relaunchError: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your windows, on this desktop").font(.title2.bold())
            Text("DockWindow needs both permissions before it can replace the Dock or window switcher.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(permissions.accessibility ? "Accessibility granted" : "Accessibility not active", systemImage: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle")
                Spacer()
                Button("Open System Settings", action: permissions.openAccessibility)
            }
            HStack {
                Label(permissions.screenRecording ? "Screen Recording granted" : "Screen Recording not active", systemImage: permissions.screenRecording ? "checkmark.circle.fill" : "exclamationmark.triangle")
                Spacer()
                Button("Open System Settings", action: permissions.openScreenRecording)
            }
            if !permissions.isGranted {
                Text("Already enabled in System Settings? Relaunch first. If access is still inactive, remove DockWindow from the affected permission list, then add ~/Applications/DockWindow.app again. Screen Recording has its own permission list.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if permissions.usesAdHocSigning {
                Label("This build uses ad-hoc signing. Rebuilding can invalidate grants even when Settings still shows them enabled. The DockWindow Dev certificate keeps the app identity stable across builds.", systemImage: "signature")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button("Relaunch DockWindow") {
                do { try AppRelauncher.relaunch() }
                catch { relaunchError = error.localizedDescription }
            }
            Text("Relaunch waits for DockWindow to quit and restore the native Dock before starting a fresh process.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .onReceive(timer) { _ in permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
        .alert("Could not relaunch DockWindow", isPresented: Binding(get: { relaunchError != nil }, set: { if !$0 { relaunchError = nil } })) {
            Button("OK") { relaunchError = nil }
        } message: { Text(relaunchError ?? "") }
    }
}
