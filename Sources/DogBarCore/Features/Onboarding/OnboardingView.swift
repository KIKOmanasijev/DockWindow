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
    @StateObject private var heroDog = MascotDirector(MascotState(frame: .celebrate))
    @StateObject private var setupDog = MascotDirector(MascotState(frame: .think))
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
        AccessibilityNotification.Announcement("\(name) is on for DogBar").post()
        Task { @MainActor in await cheer() }
    }

    /// A permission turned on: the dog cheers, then goes back to wondering if one is still missing.
    private func cheer() async {
        await setupDog.perform {
            await setupDog.pose(.celebrate)
            await setupDog.hop(18)
            await setupDog.wag(3)
            await setupDog.blink()
            guard await setupDog.beat(0.9), !setupComplete else { return }
            await setupDog.pose(.think)
        }
    }
    private var setupComplete: Bool { permissions.isGranted && permissions.installLocation.isInstalled }

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
            feature(number: 1, kicker: "A Dock per desktop", title: "A Dock for every desktop.",
                    text: "Each one shows only the apps open there.", aside: nil) {
                DesktopsScene(reduceMotion: reduceMotion)
            }
        case .previews:
            feature(number: 2, kicker: "Dock previews", title: "Hover to see every window.",
                    text: "Click one and only that window comes forward.", aside: nil) {
                PreviewsScene(reduceMotion: reduceMotion)
            }
        case .switcher:
            feature(number: 3, kicker: "Window switcher", title: "Switch windows, not apps.",
                    text: "Hold \(shortcutWords.modifiers) and tap \(shortcutWords.key).", aside: nil) {
                SwitcherScene(reduceMotion: reduceMotion, shortcut: settings.switcherShortcut)
            }
        case .setup: setup
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            heroPeek.padding(.bottom, 26)
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
                Button { model.skipToSetup() } label: { Text("Skip to setup").underline() }
                    .buttonStyle(OnboardingQuietButtonStyle(tint: .white))
                Button { model.next() } label: {
                    HStack(spacing: 8) { Text(model.mode == .tour ? "Start the Tour" : "Show Me Around"); Image(systemName: "arrow.right") }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .shadow(color: OnboardingPalette.yellow.opacity(0.35), radius: 18, y: 8)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 28)
            Text("Three quick looks, then setup.")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                .padding(.top, 16)
        }
        .padding(.bottom, 30)
        .task {
            heroDog.reduceMotion = reduceMotion
            heroDog.set(nil) { $0 = MascotState(frame: reduceMotion ? .wave : .celebrate, lift: reduceMotion ? 0 : -heroDogSize * 0.56) }
            guard !reduceMotion else { return }
            await heroDog.perform {
                guard await heroDog.beat(0.45) else { return }
                // Slowly rises from behind the Dock and grips it with both paws.
                heroDog.set(.spring(response: 1.1, dampingFraction: 0.82)) { $0.lift = 0 }
                guard await heroDog.beat(1.0) else { return }
                await heroDog.blink()
                guard await heroDog.beat(0.25) else { return }
                // Lets go with one paw to say hi.
                await heroDog.pose(.wave)
                await heroDog.wave(2)
                guard await heroDog.beat(0.4) else { return }
                await heroDog.blink()
            }
        }
    }

    private let heroDogSize: CGFloat = 230

    /// The dog peeking over a glass DogBar Dock: icons on both sides, the dog's paws on its edge.
    private var heroPeek: some View {
        let edge = heroDogSize * MascotRig.peekEdge
        let left = ["finder", "safari", "slack"], right = ["music", "photos"]
        return ZStack(alignment: .top) {
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.28), .clear], center: .center, startRadius: 6, endRadius: 140))
                .frame(width: 280, height: 280).offset(y: -40)
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(left, id: \.self) { AppIconImage(name: $0, size: 44).shadow(color: .black.opacity(0.25), radius: 2, y: 1) }
                }
                .frame(width: 166, alignment: .trailing)
                // The dog's place in the middle of the Dock.
                Spacer().frame(width: heroDogSize * 0.7)
                HStack(spacing: 8) {
                    ForEach(right, id: \.self) { AppIconImage(name: $0, size: 44).shadow(color: .black.opacity(0.25), radius: 2, y: 1) }
                    Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 34)
                    AppIconImage(name: "trash", size: 46)
                }
                .frame(width: 166, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 13)
            .background {
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.1), .white.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.inset(by: 1.5).stroke(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center), lineWidth: 2).blur(radius: 1.2))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.18), .white.opacity(0.5)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
                    .shadow(color: Color(hex: 0x1A0550).opacity(0.35), radius: 22, y: 12)
            }
            .padding(.top, edge)
            MascotRigView(dog: heroDog, size: heroDogSize, peek: true)
                .frame(height: edge + 70, alignment: .top)
        }
        .frame(height: edge + 70, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The DogBar dog peeks over a Dock and waves.")
    }

    private func feature<Scene: View>(number: Int, kicker: String, title: String, text: String, aside: String?, @ViewBuilder scene: () -> Scene) -> some View {
        HStack(alignment: .center, spacing: 34) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(number) of 3".uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(OnboardingPalette.accent)
                Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(OnboardingPalette.text)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                Text(text).font(.system(size: 15)).foregroundStyle(OnboardingPalette.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                if let aside {
                    Text(aside).font(.system(size: 12, weight: .medium)).foregroundStyle(OnboardingPalette.accent).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
            }
            .frame(width: 236, alignment: .leading)
            scene()
        }
        .padding(.horizontal, 36)
    }

    // MARK: Setup

    private var setup: some View {
        HStack(alignment: .center, spacing: 22) {
            MascotRigView(dog: setupDog, size: 196)
                .task {
                    setupDog.reduceMotion = reduceMotion
                    setupDog.set(nil) { $0 = MascotState(frame: setupComplete ? .celebrate : .think, lift: reduceMotion ? 0 : -24, opacity: reduceMotion ? 1 : 0) }
                    guard !reduceMotion else { return }
                    await setupDog.perform {
                        setupDog.set(.spring(response: 0.6, dampingFraction: 0.75)) { $0.lift = 0; $0.opacity = 1 }
                        guard await setupDog.beat(0.6) else { return }
                        await setupDog.blink()
                        if setupComplete { await setupDog.hop(14); await setupDog.wag(3); return }
                        // Asking for something: a puzzled scratch behind the ear.
                        await setupDog.scratch(4)
                        await setupDog.wag(2)
                        guard await setupDog.beat(0.8) else { return }
                        await setupDog.blink()
                    }
                }
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
                               why: "Focus, close and minimize single windows. Never reads what you type.",
                               access: permissions.accessibilityAccess, granted: permissions.accessibility,
                               isNext: !permissions.accessibility, request: permissions.openAccessibility)
                permissionCard(title: "Screen Recording", symbol: "macwindow.on.rectangle", colors: [0xB76DFF, 0x6E24E6],
                               why: "Real window thumbnails. Images never leave your Mac.",
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
        if !permissions.installLocation.isInstalled { return "Permissions stay with the copy you keep." }
        if permissions.isGranted { return "DogBar's Dock replaces Apple's while it runs. The paw in the menu bar brings Apple's back." }
        return "macOS asks only when you click Allow."
    }

    private var installBanner: some View {
        HStack(spacing: 14) {
            iconTile(symbol: "externaldrive.fill", colors: [0xFFC93C, 0xF09A1A])
            VStack(alignment: .leading, spacing: 3) {
                Text(permissions.installLocation == .translocated ? "Running from a temporary copy" : "Running from the disk image")
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(OnboardingPalette.text)
                Text(installedCopy == nil
                     ? "Drag it to Applications, open it there, then eject the disk."
                     : "Found it in Applications. Open that copy; this one quits.")
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
                Text("Anonymous feature counts. Never titles, files or typing.")
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
