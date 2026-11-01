import SwiftUI

/// Asks whether to share anonymous usage data. The two answers carry equal weight and neither is
/// preselected, so sharing is a real choice.
public struct UsageDataChoiceView: View {
    @ObservedObject var settings: AppSettings
    private let onChoice: () -> Void

    public init(settings: AppSettings, onChoice: @escaping () -> Void = {}) {
        self.settings = settings
        self.onChoice = onChoice
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share anonymous usage data?").font(.headline)
            Text("It helps decide what to improve: a random install ID, app and macOS version, whether setup finished, and which features you use each day. Never window titles, app names, files or anything you type. You can change this any time in Settings → General → Privacy.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { choose(false) } label: { Text("Don't Share").frame(maxWidth: .infinity) }
                Button { choose(true) } label: { Text("Share").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func choose(_ share: Bool) {
        settings.chooseUsageData(share: share)
        onChoice()
    }
}
