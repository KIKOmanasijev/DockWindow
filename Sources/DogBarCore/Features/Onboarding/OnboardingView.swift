import AppKit
import SwiftUI

/// The onboarding wizard: a welcome, three feature scenes, then one setup screen. One dominant
/// action per screen. Steps never advance by themselves.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var hopToken = 0
    @State private var installedCopy: URL?
    @State private var actionError: String?

    static let size = CGSize(width: 860, height: 600)
    private var reduceMotion: Bool { systemReduceMotion || settings.reduceAnimations }
    private var step: OnboardingStep { model.step }
    private var isFeature: Bool { [.desktops, .previews, .switcher].contains(step) }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header.frame(height: 52)
                ZStack {
                    content
                        .id(step)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: model.forward ? 40 : -40)),
                            removal: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.9), value: step)
                if step != .welcome { footer.frame(height: 76) }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onChange(of: step) { _, _ in
            // VoiceOver moves to the new step's title. Keyboard focus stays where it was.
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); titleFocused = true }
        }
        .onChange(of: permissions.accessibility) { old, new in reactToGrant(old, new, name: "Accessibility") }
        .onChange(of: permissions.screenRecording) { old, new in reactToGrant(old, new, name: "Screen Recording") }
        .alert("DogBar could not do that", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func reactToGrant(_ old: Bool, _ new: Bool, name: String) {
        guard !old, new, step == .setup else { return }
        hopToken += 1
        AccessibilityNotification.Announcement("\(name) is on for DogBar").post()
    }

    // MARK: Frame

    @ViewBuilder private var background: some View {
        if step == .welcome {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x7B3FF2), Color(hex: 0x5A1FD0), Color(hex: 0x3A0F99)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.08), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(hex: 0xFF8FD1, opacity: 0.16), .clear], center: .init(x: 0.95, y: 0.95), startRadius: 0, endRadius: 380)
            }
            .ignoresSafeArea()
        } else {
            ZStack {
                OnboardingPalette.paper
                RadialGradient(colors: [Color(hex: colorScheme == .dark ? 0x3A1F7A : 0xE6DAFF, opacity: colorScheme == .dark ? 0.35 : 0.8), .clear],
                               center: .init(x: 0.85, y: 0.1), startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Color(hex: colorScheme == .dark ? 0x4A1636 : 0xFFE6EE, opacity: colorScheme == .dark ? 0.25 : 0.7), .clear],
                               center: .init(x: 0.1, y: 1), startRadius: 0, endRadius: 420)
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        ZStack {
            if model.steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(model.steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == model.index ? (step == .welcome ? OnboardingPalette.yellow : OnboardingPalette.purple)
                                  : index < model.index ? OnboardingPalette.accent.opacity(0.45)
                                  : (step == .welcome ? Color.white.opacity(0.3) : OnboardingPalette.line))
                            .frame(width: index == model.index ? 22 : 7, height: 7)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: model.index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(model.index + 1) of \(model.steps.count)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !model.isFirst {
                Button { model.back() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(OnboardingQuietButtonStyle())
                    .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            if isFeature {
                Button("Skip") { model.skipToSetup() }
                    .buttonStyle(OnboardingQuietButtonStyle(tint: OnboardingPalette.muted))
                    .help("Skip the tour and go to setup")
                Button("Continue") { model.next() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else if step == .setup {
                if permissions.isGranted || model.mode == .privacyOnly {
                    Button(model.mode == .firstRun ? "Start DogBar" : "Done") { model.finish() }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    // Never a trap: setup can be finished later from the paw menu.
                    Button("Finish Later") { model.finish() }
                        .buttonStyle(OnboardingQuietButtonStyle())
                        .help("DogBar starts once both permissions are on. Finish from the paw menu → Finish Setup.")
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 10)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .desktops:
            feature(number: 1, kicker: "A Dock per desktop", title: "Each desktop gets a Dock with just its apps.",
                    text: "Keep work on one desktop and personal stuff on another. Swipe between them and the Dock follows.",
                    aside: "DogBar's Dock is its own rebuild of the Mac Dock and stands in for Apple's while it's on. The paw menu's Pause DogBar or Restore Native Dock brings Apple's back.") {
                DesktopsScene(reduceMotion: reduceMotion)
            }
        case .previews:
            feature(number: 2, kicker: "Previews from the Dock", title: "Hover an app to see every window.",
                    text: "Pick the window you want and only that one comes forward. Close or minimize it right from the preview.", aside: nil) {
                PreviewsScene(reduceMotion: reduceMotion)
            }
        case .switcher:
            feature(number: 3, kicker: "Window switching", title: "Switch to any window, not just any app.",
                    text: "Hold \(shortcutWords.modifiers) and tap \(shortcutWords.key). Every window gets its own tile, so two Safari windows are two choices.",
                    aside: "Change the shortcut in Settings → Switcher.") {
                SwitcherScene(reduceMotion: reduceMotion, shortcut: settings.switcherShortcut)
            }
        case .setup: setup
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)], center: .center, startRadius: 10, endRadius: 150))
                    .frame(width: 300, height: 300)
                MascotView(pose: .welcome, size: 220, reactionToken: 1, reaction: .greet, reduceMotion: reduceMotion)
            }
            .frame(height: 230)
            .padding(.bottom, 10)
            Text(model.mode == .tour ? "Here's DogBar." : "Meet DogBar.")
                .font(.system(size: 46, weight: .bold)).tracking(-1.2)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
            Text("A Dock for every desktop, previews of every window, and a switcher that picks windows, not just apps.")
                .font(.system(size: 16.5)).foregroundStyle(.white.opacity(0.82)).lineSpacing(3)
                .multilineTextAlignment(.center).frame(width: 500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            HStack(spacing: 26) {
                Button { model.next() } label: {
                    HStack(spacing: 8) { Text(model.mode == .tour ? "Start the Tour" : "Show Me Around"); Image(systemName: "arrow.right") }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .shadow(color: OnboardingPalette.yellow.opacity(0.35), radius: 18, y: 8)
                .keyboardShortcut(.defaultAction)
                Button { model.skipToSetup() } label: { Text("Skip to setup").underline() }
                    .buttonStyle(OnboardingQuietButtonStyle(tint: .white))
            }
            .padding(.top, 30)
            Text("Three quick looks, then two permissions.")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                .padding(.top, 18)
        }
        .padding(.bottom, 40)
    }

    private func feature<Scene: View>(number: Int, kicker: String, title: String, text: String, aside: String?, @ViewBuilder scene: () -> Scene) -> some View {
        HStack(alignment: .center, spacing: 34) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(number) of 3 · \(kicker)".uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(OnboardingPalette.accent)
                Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.5).foregroundStyle(OnboardingPalette.text)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                Text(text).font(.system(size: 14.5)).foregroundStyle(OnboardingPalette.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                if let aside {
                    Text(aside).font(.system(size: 12, weight: .medium)).foregroundStyle(OnboardingPalette.accent).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
                // The guide pose presents toward the scene on its right.
                MascotView(pose: .guide, size: 112, reduceMotion: reduceMotion).offset(x: -10).padding(.top, 14)
            }
            .frame(width: 232, alignment: .leading)
            scene()
        }
        .padding(.horizontal, 36)
    }

    // MARK: Setup

    private var setup: some View {
        HStack(alignment: .center, spacing: 22) {
            MascotView(pose: permissions.isGranted && permissions.installLocation.isInstalled ? .celebrate : .permissions,
                       size: 190, reactionToken: hopToken, reaction: .hop, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(setupTitle).font(.system(size: 28, weight: .bold)).tracking(-0.5).foregroundStyle(OnboardingPalette.text)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                    Text(setupSubtitle).font(.system(size: 13.5)).foregroundStyle(OnboardingPalette.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
                if !permissions.installLocation.isInstalled { installBanner }
                permissionCard(title: "Accessibility", symbol: "accessibility", colors: [0x3B8BFF, 0x1A56DB],
                               why: "Brings the exact window forward, closes or minimizes it, and hears your switcher shortcut. Never records what you type.",
                               access: permissions.accessibilityAccess, granted: permissions.accessibility,
                               isNext: !permissions.accessibility, request: permissions.openAccessibility)
                permissionCard(title: "Screen Recording", symbol: "macwindow.on.rectangle", colors: [0xB76DFF, 0x6E24E6],
                               why: "Shows real window thumbnails in previews and the switcher. Images stay in memory, never saved or sent.",
                               access: permissions.screenRecordingAccess, granted: permissions.screenRecording,
                               isNext: permissions.accessibility && !permissions.screenRecording, request: permissions.openScreenRecording)
                privacyRow.padding(.top, 2)
                if permissions.usesAdHocSigning && !permissions.isGranted {
                    Text("Development build without a stable signature: rebuilding it can make macOS forget these permissions.")
                        .font(.system(size: 11.5)).foregroundStyle(OnboardingPalette.muted)
                }
            }
            .frame(width: 540)
        }
        .padding(.horizontal, 36)
        .task(id: permissions.installLocation.isInstalled) {
            // Notice a copy appearing in Applications while setup is open. Stops with the step.
            while !Task.isCancelled && !permissions.installLocation.isInstalled {
                let found = InstalledCopy.find()
                if found != installedCopy { withAnimation(reduceMotion ? nil : .default) { installedCopy = found } }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var setupTitle: String {
        if !permissions.installLocation.isInstalled { return "First, move DogBar to Applications." }
        return permissions.isGranted ? "You're all set." : "Two permissions, and you're in."
    }
    private var setupSubtitle: String {
        if !permissions.installLocation.isInstalled { return "Permissions belong to the copy you keep, so grant them from the installed app." }
        if permissions.isGranted { return "Want Apple's Dock back at any point? Click the paw in the menu bar and choose Pause DogBar or Restore Native Dock." }
        return "macOS asks only when you click Allow. You can change either one later in System Settings → Privacy & Security."
    }

    private var installBanner: some View {
        HStack(spacing: 14) {
            iconTile(symbol: "externaldrive.fill", colors: [0xFFC93C, 0xF09A1A])
            VStack(alignment: .leading, spacing: 3) {
                Text(permissions.installLocation == .translocated ? "Running from a temporary copy" : "Running from the disk image")
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(OnboardingPalette.text)
                Text(installedCopy == nil
                     ? "Drag DogBar into Applications (yours or your home folder's), then open it from there and eject the disk."
                     : "Found DogBar in Applications. Open it there; this copy quits. Then eject the disk.")
                    .font(.system(size: 12)).foregroundStyle(OnboardingPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let installedCopy {
                Button("Open It") {
                    do { try InstalledCopy.openAndQuit(installedCopy) } catch { actionError = error.localizedDescription }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle(compact: true))
            } else {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    .buttonStyle(OnboardingPrimaryButtonStyle(compact: true))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OnboardingPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OnboardingPalette.caution.opacity(0.45)))
    }

    private func iconTile(symbol: String, colors: [UInt32]) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75))
            .overlay(Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white))
            .frame(width: 42, height: 42)
            .shadow(color: Color(hex: colors[1]).opacity(0.35), radius: 6, y: 3)
            .accessibilityHidden(true)
    }

    private func permissionCard(title: String, symbol: String, colors: [UInt32], why: String, access: PermissionAccess,
                                granted: Bool, isNext: Bool, request: @escaping () -> Void) -> some View {
        let installed = permissions.installLocation.isInstalled
        return HStack(alignment: .center, spacing: 14) {
            iconTile(symbol: symbol, colors: colors)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(OnboardingPalette.text)
                Text(why).font(.system(size: 12)).foregroundStyle(OnboardingPalette.muted).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                if installed { cardHint(title: title, access: access) }
            }
            Spacer(minLength: 8)
            Group {
                if !installed {
                    Text("Install first").font(.system(size: 12.5, weight: .medium)).foregroundStyle(OnboardingPalette.muted)
                } else {
                    switch access {
                    case .granted:
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(OnboardingPalette.success)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(OnboardingPalette.success.opacity(0.12)))
                    case .checking, .requesting:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(access == .checking ? "Checking…" : "Asking macOS…").font(.system(size: 12.5)).foregroundStyle(OnboardingPalette.muted)
                        }
                    case .notRequested, .waitingForUser:
                        let label = access == .notRequested ? "Allow…" : "Open Settings"
                        if isNext {
                            Button(label, action: request).buttonStyle(OnboardingPrimaryButtonStyle(compact: true))
                        } else {
                            Button(label, action: request).buttonStyle(OnboardingBorderedButtonStyle())
                        }
                    }
                }
            }
            .fixedSize()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OnboardingPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(granted ? OnboardingPalette.success.opacity(0.45) : OnboardingPalette.line))
        .shadow(color: Color(hex: 0x2B0A74).opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(statusWords(access, installed: installed))")
    }

    @ViewBuilder private func cardHint(title: String, access: PermissionAccess) -> some View {
        if title == "Screen Recording" && access != .granted && (permissions.screenRecordingNeedsRelaunchAfterGrant || access == .waitingForUser) {
            HStack(spacing: 4) {
                Text("Switched it on? macOS applies it after a restart.").font(.system(size: 11.5, weight: .medium)).foregroundStyle(OnboardingPalette.caution)
                Button("Quit & Reopen") {
                    do { try AppRelauncher.relaunch() } catch { actionError = error.localizedDescription }
                }
                .buttonStyle(.link).font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.top, 2)
        } else if access == .waitingForUser {
            Text("Switch DogBar on in the list. This updates by itself.")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(OnboardingPalette.caution).padding(.top, 2)
        }
    }

    private func statusWords(_ access: PermissionAccess, installed: Bool) -> String {
        guard installed else { return "install DogBar first" }
        switch access {
        case .checking: return "checking"
        case .granted: return "allowed"
        case .notRequested: return "not allowed yet"
        case .requesting: return "asking macOS"
        case .waitingForUser: return "turn on DogBar in System Settings"
        }
    }

    private var privacyRow: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share anonymous usage data?").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(OnboardingPalette.text)
                Text("A random install ID, versions and which features get used. Never titles, app names, files or typing.")
                    .font(.system(size: 11.5)).foregroundStyle(OnboardingPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("Don't Share") { settings.chooseUsageData(share: false) }
                    .buttonStyle(OnboardingChoiceButtonStyle(selected: settings.telemetryAsked && !settings.telemetryEnabled))
                Button("Share") { settings.chooseUsageData(share: true) }
                    .buttonStyle(OnboardingChoiceButtonStyle(selected: settings.telemetryAsked && settings.telemetryEnabled))
            }
            .frame(width: 210)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OnboardingPalette.surface.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OnboardingPalette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .contain)
    }

    /// "Option" and "Tab" for the default shortcut, in words for sentences.
    private var shortcutWords: (modifiers: String, key: String) {
        let shortcut = settings.switcherShortcut
        var words: [String] = []
        if shortcut.modifiers.contains(.control) { words.append("Control") }
        if shortcut.modifiers.contains(.option) { words.append("Option") }
        if shortcut.modifiers.contains(.shift) { words.append("Shift") }
        if shortcut.modifiers.contains(.command) { words.append("Command") }
        let key = String(RecorderButton.label(shortcut).drop { "⌃⌥⇧⌘".contains($0) })
        return (words.isEmpty ? "the shortcut" : words.joined(separator: "+"), key)
    }
}
