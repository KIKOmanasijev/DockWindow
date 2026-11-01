import AppKit
import SwiftUI

/// The onboarding wizard: one idea per step, one dominant action, a mascot that reacts to what
/// the user does. Steps never advance by themselves.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var permissions: PermissionsService
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var hopToken = 0
    @State private var installedCopy: URL?
    @State private var actionError: String?

    static let size = CGSize(width: 860, height: 600)
    private var reduceMotion: Bool { systemReduceMotion || settings.reduceAnimations }
    private var step: OnboardingStep { model.step }
    private var onHero: Bool { step == .welcome || step == .ready }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header.frame(height: 52)
                ZStack {
                    content
                        .id(step)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: model.forward ? 36 : -36)),
                            removal: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.9), value: step)
                footer.frame(height: 80)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onChange(of: step) { _, _ in
            // Move VoiceOver to the new step's title; keyboard focus stays on the footer buttons.
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); titleFocused = true }
        }
        .onChange(of: permissions.accessibility) { old, new in reactToGrant(old, new, step: .accessibility, name: "Accessibility") }
        .onChange(of: permissions.screenRecording) { old, new in reactToGrant(old, new, step: .screenRecording, name: "Screen Recording") }
        .alert("DogBar could not do that", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func reactToGrant(_ old: Bool, _ new: Bool, step target: OnboardingStep, name: String) {
        guard !old, new, step == target else { return }
        hopToken += 1
        AccessibilityNotification.Announcement("\(name) is on for DogBar").post()
    }

    // MARK: Frame

    @ViewBuilder private var background: some View {
        if onHero {
            ZStack {
                OnboardingPalette.hero
                RadialGradient(colors: [Color(hex: 0x8A4DFF, opacity: 0.45), .clear], center: .init(x: 0.22, y: 0.7), startRadius: 10, endRadius: 420)
            }
            .ignoresSafeArea()
        } else {
            OnboardingPalette.paper.ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            if model.steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(model.steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == model.index ? (onHero ? OnboardingPalette.yellow : OnboardingPalette.purple)
                                  : index < model.index ? (onHero ? Color.white.opacity(0.7) : OnboardingPalette.accent.opacity(0.45))
                                  : (onHero ? Color.white.opacity(0.25) : OnboardingPalette.line))
                            .frame(width: index == model.index ? 22 : 7, height: 7)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: model.index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(model.index + 1) of \(model.steps.count)")
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isFirst {
                if step == .welcome, model.mode == .firstRun || model.mode == .tour, model.setupIndex != nil {
                    Button("Skip to Setup") { model.skipToSetup() }
                        .buttonStyle(OnboardingQuietButtonStyle(tint: onHero ? .white : OnboardingPalette.accent))
                        .help("Skip the feature tour and go straight to setup")
                }
            } else {
                Button { model.back() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(OnboardingQuietButtonStyle(tint: onHero ? .white : OnboardingPalette.accent))
                    .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            if let secondary {
                Button(secondary.title, action: secondary.action)
                    .buttonStyle(OnboardingQuietButtonStyle(tint: onHero ? .white : OnboardingPalette.accent))
            }
            if let primary {
                Button(action: primary.action) {
                    HStack(spacing: 8) {
                        if primary.busy { ProgressView().controlSize(.small).tint(OnboardingPalette.ink) }
                        Text(primary.title)
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(primary.busy || !primary.enabled)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    // MARK: Actions per step

    private struct Action {
        var title: String
        var enabled = true
        var busy = false
        var action: () -> Void
    }

    private var primary: Action? {
        switch step {
        case .welcome: return Action(title: model.mode == .tour ? "Start the Tour" : "Show Me Around") { model.next() }
        case .desktops, .previews, .switcher: return Action(title: "Continue") { model.next() }
        case .install:
            if permissions.installLocation.isInstalled { return Action(title: "Continue") { model.next() } }
            if let installedCopy { return Action(title: "Open DogBar from Applications") { openInstalled(installedCopy) } }
            return Action(title: "Show DogBar in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
        case .accessibility: return permissionAction(permissions.accessibilityAccess, request: permissions.openAccessibility)
        case .screenRecording: return permissionAction(permissions.screenRecordingAccess, request: permissions.openScreenRecording)
        case .privacy:
            return settings.telemetryAsked ? Action(title: model.isLast ? "Done" : "Continue") { model.next() } : nil
        case .ready: return Action(title: permissions.isGranted ? "Start DogBar" : "Done") { model.finish() }
        }
    }

    private var secondary: Action? {
        switch step {
        case .install:
            if permissions.installLocation.isInstalled { return nil }
            return installedCopy == nil
                ? Action(title: "Open Applications Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
                : Action(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([installedCopy!]) }
        case .accessibility where !permissions.accessibility && permissions.installLocation.isInstalled,
             .screenRecording where !permissions.screenRecording && permissions.installLocation.isInstalled:
            // Never a trap: every permission can be left for later.
            return Action(title: "Not Now") { model.next() }
        default: return nil
        }
    }

    private func permissionAction(_ access: PermissionAccess, request: @escaping () -> Void) -> Action {
        if !permissions.installLocation.isInstalled {
            // Grants made from the disk image belong to a copy that is about to disappear.
            if model.steps.contains(.install) { return Action(title: "Move DogBar First") { model.go(to: .install) } }
            return Action(title: "Not Now") { model.next() }
        }
        switch access {
        case .granted: return Action(title: "Continue") { model.next() }
        case .checking: return Action(title: "Checking…", busy: true) {}
        case .requesting: return Action(title: "Asking macOS…", busy: true) {}
        case .notRequested: return Action(title: "Allow Access…", action: request)
        case .waitingForUser: return Action(title: "Open System Settings", action: request)
        }
    }

    private func openInstalled(_ url: URL) {
        do { try InstalledCopy.openAndQuit(url) } catch { actionError = error.localizedDescription }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .desktops:
            feature(kicker: "A Dock per desktop", title: "Each desktop gets a Dock with just its apps.",
                    text: "Keep work on one desktop and personal stuff on another. Swipe between them and the Dock changes too.",
                    aside: "DogBar's Dock is our own rebuild of the Mac Dock. While it's on, it stands in for Apple's Dock. Pause DogBar or Restore Native Dock in the paw menu brings Apple's Dock back.") {
                DesktopsScene(reduceMotion: reduceMotion)
            }
        case .previews:
            feature(kicker: "Previews from the Dock", title: "Hover an app to see every window.",
                    text: "Click the window you want and only that one comes forward. Close or minimize it right from the preview.",
                    aside: nil) {
                PreviewsScene(reduceMotion: reduceMotion)
            }
        case .switcher:
            feature(kicker: "Window switching", title: "Switch to any window, not just any app.",
                    text: "Hold \(shortcutText.modifierWords) and tap \(shortcutText.key). Every window gets its own tile, so two Safari windows are two choices.",
                    aside: "Change the shortcut, or turn the switcher off, in Settings → Switcher.") {
                SwitcherScene(reduceMotion: reduceMotion, shortcut: RecorderButton.label(settings.switcherShortcut))
            }
        case .install: install
        case .accessibility:
            permissionStep(kicker: model.mode == .recovery ? "Permission needed" : "Permission 1 of 2", title: "Allow Accessibility",
                           text: "This lets DogBar work with single windows: bring one forward, close or minimize it, and notice your switcher shortcut.",
                           access: permissions.accessibilityAccess, granted: permissions.accessibility,
                           pane: "Accessibility",
                           uses: ["Bring the exact window you chose forward", "Close, minimize and hide windows from previews", "Open the switcher with \(RecorderButton.label(settings.switcherShortcut))"],
                           never: "It only reacts to its own shortcut. It never records or sends what you type.")
        case .screenRecording:
            permissionStep(kicker: model.mode == .recovery ? "Permission needed" : "Permission 2 of 2", title: "Allow Screen Recording",
                           text: "This lets DogBar show what's inside each window, so previews and switcher tiles are real thumbnails, not just icons.",
                           access: permissions.screenRecordingAccess, granted: permissions.screenRecording,
                           pane: "Screen & System Audio Recording",
                           uses: ["Show live window thumbnails in Dock previews", "Show a picture of each window in the switcher"],
                           never: "No video or audio is recorded. Thumbnails stay in memory on your Mac and are never saved or sent.")
        case .privacy: privacy
        case .ready: ready
        }
    }

    private var welcome: some View {
        HStack(spacing: 36) {
            MascotView(pose: .welcome, size: 300, reactionToken: 1, reaction: .greet, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 28, height: 28)
                    Text("DogBar").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                }
                .accessibilityElement(children: .combine)
                Text(model.mode == .tour ? "Here's what DogBar does." : "Hi! Let's set up your new Dock.")
                    .font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                Text("A separate Dock for every desktop, previews of every window, and a switcher that picks windows, not just apps.")
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.82)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.mode == .tour ? "Takes about a minute. Nothing here changes your settings." : "Three quick looks, then two permissions. About a minute.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            }
            .frame(width: 380, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }

    private func feature<Scene: View>(kicker: String, title: String, text: String, aside: String?, @ViewBuilder scene: () -> Scene) -> some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                copy(kicker: kicker, title: title, text: text)
                if let aside {
                    Text(aside).font(.system(size: 12.5, weight: .medium)).foregroundStyle(OnboardingPalette.accent)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
                Spacer(minLength: 0)
                // The guide pose presents toward the scene on its right.
                MascotView(pose: .guide, size: 150, reduceMotion: reduceMotion).offset(x: -8, y: 6)
            }
            .frame(width: 262)
            scene()
        }
        .padding(.horizontal, 36).padding(.top, 4)
    }

    private func copy(kicker: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker.uppercased()).font(.system(size: 11.5, weight: .bold)).tracking(0.8).foregroundStyle(OnboardingPalette.accent)
            Text(title).font(.system(size: 27, weight: .bold)).foregroundStyle(OnboardingPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
            Text(text).font(.system(size: 14.5)).foregroundStyle(OnboardingPalette.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var install: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                copy(kicker: "Before permissions", title: permissions.installLocation.isInstalled ? "DogBar is installed." : "Move DogBar to Applications first.",
                     text: permissions.installLocation.isInstalled
                        ? "It's running from your Applications folder, so the permissions you give it will stick."
                        : "DogBar is running from the downloaded disk image. Permissions belong to the copy you keep, so install it first, then grant them there.")
                Spacer(minLength: 0)
                MascotView(pose: .permissions, size: 150, reduceMotion: reduceMotion).offset(x: -8, y: 6)
            }
            .frame(width: 262)
            VStack(alignment: .leading, spacing: 14) {
                installRow(1, "Drag DogBar into Applications", detail: "Your Applications folder or the one in your home folder both work.", done: installedCopy != nil || permissions.installLocation.isInstalled)
                installRow(2, "Open DogBar from Applications", detail: installedCopy == nil ? "Use the button below once it's copied. This copy quits." : "Found it. The button below opens it and quits this copy.", done: permissions.installLocation.isInstalled)
                installRow(3, "Eject the DogBar disk", detail: "In Finder's sidebar, or drag it to the Trash. You can delete the download afterwards.", done: false)
                if permissions.installLocation == .translocated {
                    Text("macOS is running this copy from a temporary location because it hasn't been moved yet.")
                        .font(.system(size: 12.5)).foregroundStyle(OnboardingPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .frame(width: 440, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OnboardingPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(OnboardingPalette.line))
        }
        .padding(.horizontal, 36).padding(.top, 4)
        .task(id: step) {
            // Notice the copy appearing in Applications while this step is open. Stops with the step.
            while !Task.isCancelled && !permissions.installLocation.isInstalled {
                let found = InstalledCopy.find()
                if found != installedCopy { withAnimation(reduceMotion ? nil : .default) { installedCopy = found } }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func installRow(_ number: Int, _ title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? OnboardingPalette.success : OnboardingPalette.accent.opacity(0.12)).frame(width: 28, height: 28)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(OnboardingPalette.accent) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(OnboardingPalette.text)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(OnboardingPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "")
    }

    private func permissionStep(kicker: String, title: String, text: String, access: PermissionAccess, granted: Bool,
                                pane: String, uses: [String], never: String) -> some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                copy(kicker: kicker, title: title, text: text)
                statusRow(access).padding(.top, 16)
                hint(for: access).padding(.top, 10)
                Spacer(minLength: 0)
                MascotView(pose: granted ? .celebrate : .permissions, size: 140, reactionToken: hopToken, reaction: .hop, reduceMotion: reduceMotion)
                    .offset(x: -8, y: 6)
            }
            .frame(width: 290)
            PermissionPanel(pane: pane, granted: granted, uses: uses, never: never)
                .padding(.top, 8)
        }
        .padding(.horizontal, 36).padding(.top, 4)
    }

    private func statusRow(_ access: PermissionAccess) -> some View {
        let (symbol, label, color): (String, String, Color) = {
            if !permissions.installLocation.isInstalled { return ("shippingbox", "Install DogBar before allowing this", OnboardingPalette.caution) }
            switch access {
            case .checking: return ("ellipsis.circle", "Checking…", OnboardingPalette.muted)
            case .granted: return ("checkmark.circle.fill", "Allowed", OnboardingPalette.success)
            case .notRequested: return ("circle.dashed", "Not allowed yet", OnboardingPalette.muted)
            case .requesting: return ("hourglass", "Asking macOS…", OnboardingPalette.muted)
            case .waitingForUser: return ("arrow.right.circle", "Turn on DogBar in System Settings", OnboardingPalette.caution)
            }
        }()
        return Label { Text(label) } icon: { Image(systemName: symbol) }
            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(0.1)))
            .accessibilityLabel("Status: \(label)")
    }

    @ViewBuilder private func hint(for access: PermissionAccess) -> some View {
        if !permissions.installLocation.isInstalled {
            hintText("Grants made now would belong to the copy on the disk image. Move DogBar to Applications first.")
        } else if step == .screenRecording && access != .granted && (permissions.screenRecordingNeedsRelaunchAfterGrant || access == .waitingForUser) {
            VStack(alignment: .leading, spacing: 6) {
                hintText("Switched it on already? macOS applies Screen Recording after DogBar restarts. Choose Quit & Reopen when macOS offers it, or use this button. DogBar comes back to this step.")
                Button("Quit & Reopen DogBar") {
                    do { try AppRelauncher.relaunch() } catch { actionError = error.localizedDescription }
                }
                .buttonStyle(OnboardingQuietButtonStyle()).padding(.leading, -14)
            }
        } else if step == .accessibility && access == .waitingForUser {
            hintText("Find DogBar in the list and switch it on. This page updates by itself.")
        } else if access == .granted {
            hintText("Thanks! You can change this any time in System Settings → Privacy & Security.")
        }
        if permissions.usesAdHocSigning && access != .granted {
            hintText("This development build has no stable signature, so rebuilding it can make macOS forget this permission.")
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(OnboardingPalette.muted).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var privacy: some View {
        HStack(alignment: .center, spacing: 40) {
            MascotView(pose: .guide, size: 200, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 16) {
                copy(kicker: "Your choice", title: "Share anonymous usage data?",
                     text: "It helps decide what to improve next. DogBar works exactly the same either way.")
                VStack(alignment: .leading, spacing: 8) {
                    Label("A random install ID, app and macOS version, whether setup finished, and which features you use each day.", systemImage: "chart.bar")
                    Label("Never window titles, app names, files or anything you type.", systemImage: "hand.raised")
                }
                .font(.system(size: 13)).foregroundStyle(OnboardingPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Don't Share") { choose(false) }
                        .buttonStyle(OnboardingChoiceButtonStyle(selected: settings.telemetryAsked && !settings.telemetryEnabled))
                    Button("Share") { choose(true) }
                        .buttonStyle(OnboardingChoiceButtonStyle(selected: settings.telemetryAsked && settings.telemetryEnabled))
                }
                .padding(.top, 4)
                Text("Change it any time in Settings → General → Privacy.")
                    .font(.system(size: 12)).foregroundStyle(OnboardingPalette.muted)
            }
            .frame(width: 430, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }

    private func choose(_ share: Bool) {
        let firstAnswer = !settings.telemetryAsked
        settings.chooseUsageData(share: share)
        // Answering is the step's action. A changed answer on a replay stays put.
        if firstAnswer { model.next() }
    }

    private var ready: some View {
        HStack(spacing: 30) {
            MascotView(pose: permissions.isGranted ? .celebrate : .permissions, size: 270, reactionToken: permissions.isGranted ? 1 : 0,
                       reaction: .hop, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 16) {
                Text(permissions.isGranted ? "You're all set!" : "Almost there.")
                    .font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                Text(permissions.isGranted
                     ? (model.mode == .firstRun ? "DogBar's Dock, previews and switcher start when you click Start DogBar." : "Everything DogBar needs is on.")
                     : "DogBar's Dock, previews and switcher start once Accessibility and Screen Recording are on. Pick up where you left off from the paw menu → Finish Setup.")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.82)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    tip(symbol: "rectangle.on.rectangle", title: "Switch windows", detail: "Hold \(shortcutText.modifierWords) and tap \(shortcutText.key).")
                    tip(symbol: "dock.rectangle", title: "Preview from the Dock", detail: "Hover an app to see its windows.")
                    tip(symbol: "pawprint.fill", title: "Want Apple's Dock back?", detail: "Click the paw in the menu bar: Pause DogBar or Restore Native Dock.")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
            }
            .frame(width: 420, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }

    private func tip(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(OnboardingPalette.yellow).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Option" and "Tab" for the default shortcut, in words for the sentence copy.
    private var shortcutText: (modifierWords: String, key: String) {
        let shortcut = settings.switcherShortcut
        var words: [String] = []
        if shortcut.modifiers.contains(.control) { words.append("Control") }
        if shortcut.modifiers.contains(.option) { words.append("Option") }
        if shortcut.modifiers.contains(.shift) { words.append("Shift") }
        if shortcut.modifiers.contains(.command) { words.append("Command") }
        let label = RecorderButton.label(shortcut)
        let key = String(label.drop { "⌃⌥⇧⌘".contains($0) })
        return (words.isEmpty ? "the shortcut" : words.joined(separator: "+"), key)
    }
}
