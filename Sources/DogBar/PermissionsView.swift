import SwiftUI
import DogBarCore

struct PermissionsView: View {
    @ObservedObject var permissions: PermissionsService
    @State private var relaunchError: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your windows, on this desktop").font(.title2.bold())
            Text("DogBar needs both permissions before it can replace the Dock or window switcher.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(!permissions.hasCheckedPermissions ? "Accessibility: Checking..." : permissions.accessibility ? "Accessibility granted" : "Accessibility: Unavailable to this build", systemImage: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle")
                Spacer()
                Button("Open System Settings", action: permissions.openAccessibility)
            }
            HStack {
                Label(!permissions.hasCheckedPermissions ? "Screen Recording: Checking..." : permissions.screenRecording ? "Screen Recording granted" : "Screen Recording: Unavailable to this build", systemImage: permissions.screenRecording ? "checkmark.circle.fill" : "exclamationmark.triangle")
                Spacer()
                Button("Open System Settings", action: permissions.openScreenRecording)
            }
            if permissions.hasCheckedPermissions && !permissions.isGranted {
                Text("A Settings toggle and this running build can disagree when the app signature changes. These rows show the current process checks. Relaunch after a permission change; details are recorded in the system log.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if permissions.usesAdHocSigning {
                Label("This build uses ad-hoc signing. Rebuilding can invalidate grants even when Settings still shows them enabled. The DockWindow Dev certificate keeps the app identity stable across builds.", systemImage: "signature")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button("Relaunch DogBar") {
                do { try AppRelauncher.relaunch() }
                catch { relaunchError = error.localizedDescription }
            }
            Text("Relaunch waits for DogBar to quit and restore the native Dock before starting a fresh process.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        }
        .frame(minWidth: 580, minHeight: 480)
        .onReceive(timer) { _ in permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
        .alert("Could not relaunch DogBar", isPresented: Binding(get: { relaunchError != nil }, set: { if !$0 { relaunchError = nil } })) {
            Button("OK") { relaunchError = nil }
        } message: { Text(relaunchError ?? "") }
    }
}
