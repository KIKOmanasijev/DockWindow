import AppKit
import SwiftUI

/// Presentation state the controller owns. Separate from observed session state.
@MainActor final class AgentIslandModel: ObservableObject {
    @Published var geometry: AgentIslandGeometry
    @Published var expanded = false
    @Published var reduceMotion = false
    /// Measured height of the expanded content, so the shell fits it and hit-testing matches.
    @Published var contentHeight: CGFloat = 160
    @Published var dogReaction = AgentDogReaction()
    @Published var shortcutsAvailable = false
    /// Sessions the compact island accounts for: one dog, two dogs, or one dog and "+N".
    @Published var sessionCount = 0
    /// The reply field has keyboard focus: the island stays open when the pointer wanders off.
    @Published var composing = false
    var onCollapse: (() -> Void)?
    var onExpand: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Pointer movement seen inside the panel itself, in case the app's monitors miss it.
    var onPointerActivity: (() -> Void)?
    /// The person clicked into the reply field; the panel must take keyboard focus.
    var onWantsKeyboard: (() -> Void)?
    init(geometry: AgentIslandGeometry) { self.geometry = geometry }

    /// Two positions at most: a second dog, or "+N" for everyone else.
    var compactSlots: Int { sessionCount > 1 ? 2 : 1 }
    var expandedSize: CGSize {
        CGSize(width: geometry.expandedWidth, height: min(geometry.maximumExpandedHeight, max(geometry.collapsedSize.height + 60, contentHeight)))
    }
    var shapeSize: CGSize { expanded ? expandedSize : geometry.collapsedSize(dogs: compactSlots) }

    func react(_ kind: AgentDogReaction.Kind) {
        guard !reduceMotion else { return }
        dogReaction = AgentDogReaction(kind: kind, serial: dogReaction.serial + 1)
    }
}

enum IslandPalette {
    static let shell = Color(hex: 0x070707)
    static let surface = Color(hex: 0x151515)
    static let hairline = Color.white.opacity(0.08)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.44)
    static let working = Color(hex: 0xFF8A3D)
    static let attention = Color(hex: 0xFFC247)
    static let success = Color(hex: 0x5BD08D)
    static let failure = Color(hex: 0xFF6259)
}

/// Motion tokens (hypotheses from the research handoffs, to tune on hardware).
enum IslandMotion {
    static let expand = Animation.spring(duration: 0.34, bounce: 0.08)
    static let collapse = Animation.spring(duration: 0.26, bounce: 0)
    static let resize = Animation.spring(duration: 0.30, bounce: 0)
    static let contentIn = Animation.easeOut(duration: 0.12).delay(0.05)
    static let contentOut = Animation.easeOut(duration: 0.08)
    static let selection = Animation.spring(duration: 0.19, bounce: 0)
    static let crossfade = Animation.easeOut(duration: 0.1)
    static let ringPeriod: TimeInterval = 1.5
}

/// The top-attached silhouette: square shoulders flush with the display edge, a small concave
/// flare into the menu bar, and rounded lower corners. Width, height and radius animate together.
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set { bottomRadius = newValue.first; shoulder = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.width / 4)
        let r = min(bottomRadius, (rect.width - 2 * s) / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// A timeline that ticks once a second only while open; otherwise it renders once and stops.
struct IslandClockSchedule: TimelineSchedule {
    let running: Bool
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard running else { return AnyIterator([startDate].makeIterator()) }
        var next = startDate
        return AnyIterator {
            defer { next = next.addingTimeInterval(1) }
            return next
        }
    }
}


struct AgentIslandView: View {
    @ObservedObject var model: AgentIslandModel
    @ObservedObject var center: AgentActivityCenter

    private var store: AgentActivityStore { center.displayed }
    private var selected: AgentSession? { center.selectedID.flatMap { store.session($0) } }
    private var lead: AgentSession? { store.lead }
    private var isDemo: Bool { center.source == .demo }
    private var showingList: Bool { center.showingList && store.sessions.count > 0 }

    var body: some View {
        let size = model.shapeSize
        let shoulder: CGFloat = model.expanded ? 10 : 6
        let shape = IslandShape(bottomRadius: model.expanded ? 26 : min(12, size.height * 0.42), shoulder: shoulder)
        ZStack(alignment: .top) {
            shape
                .fill(IslandPalette.shell)
                .overlay(shape.stroke(Color.white.opacity(model.expanded ? 0.07 : 0), lineWidth: 0.5))
                .shadow(color: .black.opacity(model.expanded ? 0.38 : 0), radius: 18, y: 8)
                .frame(width: size.width, height: size.height)
            ZStack(alignment: .top) {
                expandedContent
                    .frame(width: model.geometry.expandedWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if abs(model.contentHeight - height) > 0.5 { model.contentHeight = height }
                    }
                    .opacity(model.expanded ? 1 : 0)
                    .animation(model.reduceMotion ? nil : (model.expanded ? IslandMotion.contentIn : IslandMotion.contentOut), value: model.expanded)
                    .allowsHitTesting(model.expanded)
                topRow(width: size.width)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { if !model.expanded { model.onExpand?() } }
        }
        .animation(model.reduceMotion ? nil : (model.expanded ? IslandMotion.expand : IslandMotion.collapse), value: model.expanded)
        .animation(model.reduceMotion ? nil : IslandMotion.resize, value: model.contentHeight)
        .animation(model.reduceMotion ? nil : IslandMotion.resize, value: model.compactSlots)
        .onContinuousHover { _ in model.onPointerActivity?() }
        .offset(x: model.geometry.contentOffsetX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isDemo ? "Agent Activity demo" : "Agent Activity")
    }

    // MARK: Top row (visible collapsed and expanded)

    private func topRow(width: CGFloat) -> some View {
        let height = model.geometry.barHeight
        let focus = model.expanded && !showingList ? selected ?? lead : lead
        let dogSize = min(height - 6, 26)
        let others = store.ordered.filter { $0.id != focus?.id }
        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                AgentDogView(coat: focus.map { AgentCoat.palette($0.coat) } ?? AgentCoat.resting, mood: AgentMood(focus),
                             size: dogSize, reaction: model.dogReaction, reduceMotion: model.reduceMotion)
                if !model.expanded {
                    if others.count == 1, let second = others.first {
                        AgentDogView(coat: AgentCoat.palette(second.coat), mood: AgentMood(second), size: dogSize * 0.8, reduceMotion: true)
                            .padding(.top, dogSize * 0.15)
                    } else if others.count > 1 {
                        Text("+\(others.count)")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(IslandPalette.secondary)
                            .padding(.horizontal, 5).frame(height: 17)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .overlay {
                                // Someone else needs you: a quiet persistent ring, not a pulse.
                                if let flag = others.compactMap({ center.attention(for: $0) }).min(by: { AttentionBadge.rank($0) < AttentionBadge.rank($1) }) {
                                    Capsule().strokeBorder(AttentionBadge.color(flag), lineWidth: 1.2)
                                }
                            }
                    }
                }
            }
            Spacer(minLength: 4)
            if !model.geometry.hasNotch && !model.expanded, let focus {
                Text(focus.status.label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(IslandPalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            AgentStatusRing(status: focus?.status, failed: focus?.turnError != nil, demo: isDemo,
                            animate: !model.reduceMotion, size: min(height - 10, 20))
        }
        .padding(.horizontal, model.expanded ? 18 : (model.geometry.hasNotch ? 12 : 9))
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsedAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.expanded ? model.onCollapse?() : model.onExpand?() }
    }

    private var collapsedAccessibilityLabel: String {
        let prefix = isDemo ? "Demo. " : ""
        guard let lead else { return prefix + "No agent sessions" }
        let others = store.sessions.count - 1
        return prefix + "\(lead.displayTitle), \(lead.status.label)" + (others > 0 ? ", and \(others) more" : "")
    }

    // MARK: Expanded

    @ViewBuilder private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: model.geometry.barHeight)
            if store.sessions.isEmpty {
                emptyState
            } else {
                selector.padding(.top, 6)
                Group {
                    if showingList {
                        AgentSessionList(center: center, shortcuts: model.shortcutsAvailable)
                            .transition(.opacity)
                    } else if let session = selected ?? lead {
                        TimelineView(IslandClockSchedule(running: model.expanded)) { context in
                            AgentSessionDetail(session: session, now: context.date, center: center, model: model)
                        }
                        .id(session.id)
                        .transition(.opacity)
                    }
                }
            }
            collapseHandle
        }
        .animation(model.reduceMotion ? nil : IslandMotion.crossfade, value: center.selectedID)
        .animation(model.reduceMotion ? nil : IslandMotion.crossfade, value: center.showingList)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(isDemo ? "Demo is starting…" : "No agent sessions yet")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(IslandPalette.primary)
                if isDemo { DemoBadge() }
            }
            Text(connectionText).font(.system(size: 12)).foregroundStyle(IslandPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Agent Activity Settings…") { model.onOpenSettings?() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandPalette.primary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 18).padding(.top, 10)
    }

    private var connectionText: String {
        switch center.connection {
        case .listening:
            return center.lastEvent == nil
                ? "Listening. Sessions appear when a Claude Code or Codex hook reports one."
                : "Listening. No session is active right now."
        case .off: return "Live observation is off. Turn on Agent Activity in Settings › Beta."
        case .failed(let failure): return failure.message
        }
    }

    /// ‹ [⌘ all sessions] | dots › — the arrows step through the list page and each session.
    private var selector: some View {
        let sessions = store.ordered
        return HStack(spacing: 0) {
            IslandIconButton(symbol: "chevron.left", label: "Previous") { center.selectAdjacent(-1) }
            Spacer(minLength: 6)
            if isDemo { DemoBadge().padding(.trailing, 10) }
            Button { center.showList() } label: {
                Image(systemName: "command").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showingList ? IslandPalette.primary : IslandPalette.tertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(showingList ? 0.12 : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.shortcutsAvailable ? "All sessions. With the pointer here, ⌘1–⌘9 open a session." : "All sessions")
            .accessibilityLabel("All sessions")
            .accessibilityAddTraits(showingList ? .isSelected : [])
            Rectangle().fill(IslandPalette.hairline).frame(width: 1, height: 16).padding(.horizontal, 6)
            SessionDots(sessions: sessions, selectedID: showingList ? nil : (selected ?? lead)?.id, reduceMotion: model.reduceMotion,
                        attention: { center.attention(for: $0) }) { center.select($0) }
            Spacer(minLength: 6)
            IslandIconButton(symbol: "chevron.right", label: "Next") { center.selectAdjacent(1) }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var collapseHandle: some View {
        Button { model.onCollapse?() } label: {
            Image(systemName: "chevron.compact.up").font(.system(size: 15, weight: .medium))
                .foregroundStyle(IslandPalette.tertiary)
                .frame(maxWidth: .infinity).frame(height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6).padding(.bottom, 6)
        .accessibilityLabel("Close")
    }
}

// MARK: - Pieces

struct DemoBadge: View {
    var body: some View {
        Text("DEMO")
            .font(.system(size: 9.5, weight: .bold)).tracking(0.6)
            .foregroundStyle(IslandPalette.attention)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().strokeBorder(IslandPalette.attention.opacity(0.6), lineWidth: 1))
            .accessibilityLabel("Demo: simulated activity")
            .help("Simulated activity, not a real agent")
    }
}

struct IslandIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(hovering ? IslandPalette.primary : IslandPalette.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// Stable session dots in slot order. The halo slides to the selection; dots never reorder.
struct SessionDots: View {
    let sessions: [AgentSession]
    let selectedID: String?
    let reduceMotion: Bool
    var attention: (AgentSession) -> AgentActivityCenter.Attention? = { _ in nil }
    let select: (String) -> Void
    @Namespace private var halo

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sessions.prefix(12)) { session in
                let on = session.id == selectedID
                let flag = attention(session)
                Button { select(session.id) } label: {
                    ZStack {
                        if on {
                            Circle().fill(Color.white.opacity(0.12))
                                .matchedGeometryEffect(id: "halo", in: halo)
                        }
                        Circle().fill(AgentCoat.palette(session.coat).dot)
                            .frame(width: on ? 13 : 10, height: on ? 13 : 10)
                            .opacity(on || flag != nil ? 1 : 0.62)
                            .overlay(alignment: .topTrailing) {
                                // A small, still corner badge: it needs you, failed, or finished since you looked.
                                if let flag {
                                    Circle().fill(AttentionBadge.color(flag))
                                        .frame(width: 7, height: 7)
                                        .overlay(Circle().stroke(IslandPalette.shell, lineWidth: 1.5))
                                        .offset(x: 3.5, y: -3.5)
                                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                                }
                            }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help((session.slot.map { "⌘\($0) · " } ?? "") + session.displayTitle + (flag.map { " · \(AttentionBadge.label($0))" } ?? ""))
                .accessibilityLabel("\(session.displayTitle), \(session.status.label)")
                .accessibilityValue([on ? "Selected" : nil, flag.map(AttentionBadge.label)].compactMap { $0 }.joined(separator: ", "))
                .accessibilityHint(session.slot.map { "Command \($0) while the pointer is over the island" } ?? "")
                .accessibilityAddTraits(on ? .isSelected : [])
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: flag)
            }
            if sessions.count > 12 {
                Text("+\(sessions.count - 12)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(IslandPalette.tertiary)
            }
        }
        .animation(reduceMotion ? nil : IslandMotion.selection, value: selectedID)
    }
}

enum AttentionBadge {
    static func color(_ attention: AgentActivityCenter.Attention) -> Color {
        switch attention {
        case .needsYou: return IslandPalette.attention
        case .failed: return IslandPalette.failure
        case .unseen: return IslandPalette.success
        }
    }
    static func rank(_ attention: AgentActivityCenter.Attention) -> Int {
        switch attention { case .needsYou: return 0; case .failed: return 1; case .unseen: return 2 }
    }
    static func label(_ attention: AgentActivityCenter.Attention) -> String {
        switch attention {
        case .needsYou: return "Needs you"
        case .failed: return "Turn failed"
        case .unseen: return "New reply"
        }
    }
}

/// Trailing ring. A fixed arc rotates only while work is observed and motion is allowed;
/// otherwise every state is a still mark. Never a fraction: there is no real denominator.
struct AgentStatusRing: View {
    let status: AgentStatus?
    let failed: Bool
    let demo: Bool
    let animate: Bool
    let size: CGFloat

    var body: some View {
        let line = max(2, size * 0.13)
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: line)
            switch status {
            case .working?:
                if animate {
                    TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: IslandMotion.ringPeriod) / IslandMotion.ringPeriod
                        arc(line).rotationEffect(.degrees(phase * 360))
                    }
                } else {
                    arc(line)
                }
            case .needsYou?:
                Circle().stroke(IslandPalette.attention, lineWidth: line)
                Image(systemName: "exclamationmark").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(IslandPalette.attention)
            case .finished?:
                Circle().stroke(failed ? IslandPalette.failure : IslandPalette.success, lineWidth: line)
                Image(systemName: failed ? "exclamationmark" : "checkmark").font(.system(size: size * 0.46, weight: .heavy))
                    .foregroundStyle(failed ? IslandPalette.failure : IslandPalette.success)
            case .stale?:
                Circle().stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: line, dash: [2, 3]))
            case .idle?, nil:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func arc(_ line: CGFloat) -> some View {
        Circle().trim(from: 0, to: 0.28)
            .stroke(IslandPalette.working, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}


// MARK: - All sessions

/// Every session in stable slot order: its dog, title, project, status and shortcut.
struct AgentSessionList: View {
    @ObservedObject var center: AgentActivityCenter
    let shortcuts: Bool
    @State private var showAll = false
    static let collapsedCount = 6

    var body: some View {
        let sessions = center.displayed.ordered
        let shown = showAll ? sessions : Array(sessions.prefix(Self.collapsedCount))
        let inactive = sessions.filter { [.finished, .idle, .stale].contains($0.status) }.count
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(sessions.count == 1 ? "1 session" : "\(sessions.count) sessions")
                    .font(.system(size: 12)).foregroundStyle(IslandPalette.secondary)
                Spacer()
                if inactive > 0 {
                    Button("Clear finished") { center.clearInactive() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.secondary)
                        .help("Forget finished and idle sessions. Working sessions stay.")
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
            if showAll {
                ScrollView(.vertical) {
                    VStack(spacing: 2) { ForEach(shown) { session in row(session) } }
                }
                .scrollIndicators(.never)
                .frame(height: min(300, CGFloat(shown.count) * 36))
            } else {
                VStack(spacing: 2) { ForEach(shown) { session in row(session) } }
            }
            if sessions.count > Self.collapsedCount && !showAll {
                Button { showAll = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        Text("Show \(sessions.count - Self.collapsedCount) more")
                    }
                    .font(.system(size: 12)).foregroundStyle(IslandPalette.secondary)
                    .padding(.horizontal, 6).padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func row(_ session: AgentSession) -> some View {
        SessionListRow(session: session, attention: center.attention(for: session), shortcuts: shortcuts,
                       open: { center.select(session.id) }, remove: { center.dismiss(session.id) })
    }
}

/// One session in the list. Its remove button appears only while the row is hovered.
struct SessionListRow: View {
    let session: AgentSession
    let attention: AgentActivityCenter.Attention?
    let shortcuts: Bool
    let open: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 10) {
                    AgentDogView(coat: AgentCoat.palette(session.coat), mood: AgentMood(session), size: 22, reduceMotion: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(session.displayTitle).font(.system(size: 13.5, weight: attention == nil ? .regular : .semibold))
                            .foregroundStyle(IslandPalette.primary).lineLimit(1)
                        if let project = session.project, project != session.displayTitle {
                            Text(project).font(.system(size: 12)).foregroundStyle(IslandPalette.tertiary).lineLimit(1)
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 5) {
                        Circle().fill(attention.map(AttentionBadge.color) ?? statusColor(session)).frame(width: 6, height: 6)
                        Text(attention == .unseen ? "New reply" : session.status.label)
                            .font(.system(size: 11.5)).foregroundStyle(IslandPalette.secondary).lineLimit(1)
                    }
                    .fixedSize()
                }
                .padding(.leading, 8)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ZStack(alignment: .trailing) {
                if hovering {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(IslandPalette.secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove from the island. It comes back when a new turn starts or it needs you.")
                    .accessibilityLabel("Remove \(session.displayTitle) from the island")
                    .transition(.opacity)
                } else if shortcuts, let slot = session.slot {
                    Text("⌘\(slot)").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(IslandPalette.tertiary)
                        .transition(.opacity)
                }
            }
            .frame(width: 30, alignment: .trailing)
            .padding(.trailing, 8)
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.displayTitle), \(attention.map(AttentionBadge.label) ?? session.status.label)")
        .accessibilityAction(named: "Remove from the island", remove)
    }
}

func statusColor(_ session: AgentSession) -> Color {
    switch session.status {
    case .working: return IslandPalette.working
    case .needsYou: return IslandPalette.attention
    case .finished: return session.turnError == nil ? IslandPalette.success : IslandPalette.failure
    case .idle: return Color.white.opacity(0.45)
    case .stale: return Color.white.opacity(0.25)
    }
}

// MARK: - Selected session detail

/// Selector → agent icon, title, project → your prompt → status → live tool feed → last reply →
/// reply or open in the app that hosts the session. No stage strip, no inferred progress.
struct AgentSessionDetail: View {
    let session: AgentSession
    let now: Date
    @ObservedObject var center: AgentActivityCenter
    @ObservedObject var model: AgentIslandModel

    private var host: AgentHostApp? { center.hosts[session.id] }
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                header
                if let prompt = session.lastPrompt {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if session.lastPromptViaDogBar {
                            Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 9.5))
                                .foregroundStyle(IslandPalette.tertiary)
                                .help("You replied from DogBar")
                        }
                        Text(prompt).font(.system(size: 12.5)).foregroundStyle(IslandPalette.secondary)
                            .lineLimit(2).truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(session.lastPromptViaDogBar ? "Your reply from DogBar: \(prompt)" : "Your prompt: \(prompt)")
                }
            }
            if !session.tools.isEmpty && (session.status == .working || session.status == .needsYou || session.lastMessage == nil) { tools }
            if let message = session.lastMessage { lastMessage(message) }
            actions
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Looking at a session clears its "new reply" badge.
        .task(id: "\(session.id)|\(session.statusSince.timeIntervalSince1970)|\(model.expanded)") {
            if model.expanded { center.markSeen(session.id) }
        }
    }

    /// Agent icon, title and project on the left; the status chip and, on hover, a small remove button on the right.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            ClientMark(client: session.client)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.displayTitle)
                    .font(.system(size: 14.5, weight: .medium)).foregroundStyle(IslandPalette.primary)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                if let project = session.project, project != session.displayTitle {
                    Text(project).font(.system(size: 12)).foregroundStyle(IslandPalette.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            statusChip
            if hovering {
                Button { center.dismiss(session.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(IslandPalette.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove from the island. It comes back when a new turn starts or it needs you.")
                .accessibilityLabel("Remove \(session.displayTitle) from the island")
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAction(named: "Remove from the island") { center.dismiss(session.id) }
    }

    /// One compact status: dot, state, an observed qualifier, and when.
    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor(session)).frame(width: 6.5, height: 6.5)
            Text(statusText).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.primary)
            Text(chipTrailing).font(.system(size: 12)).monospacedDigit().foregroundStyle(IslandPalette.tertiary)
        }
        .lineLimit(1)
        .fixedSize()
        .help(statusHelp)
        .accessibilityElement(children: .combine)
    }

    /// Working: elapsed. Needs you: the tool. Otherwise: when it happened.
    private var chipTrailing: String {
        if session.status == .working, let started = session.turnStartedAt { return "· \(IslandFormat.duration(now.timeIntervalSince(started)))" }
        if session.status == .needsYou, let detail = session.detail { return "· \(detail)" }
        return "· \(IslandFormat.relative(session.statusSince, now: now))"
    }

    private var statusHelp: String {
        var parts = [statusText]
        if let detail = session.detail { parts.append(detailText(detail)) }
        if let timing = timingText { parts.append(timing) }
        parts.append("· last event \(IslandFormat.relative(session.lastEventAt, now: now))")
        return parts.joined(separator: " ")
    }

    /// Observed timing only: elapsed while working, the turn's duration once finished.
    private var timingText: String? {
        if session.status == .working, let started = session.turnStartedAt { return IslandFormat.duration(now.timeIntervalSince(started)) }
        if session.status == .finished, session.turnError == nil, let last = session.lastTurnDuration { return "took \(IslandFormat.duration(last))" }
        return nil
    }
    private var statusText: String {
        if session.status == .finished, session.turnError != nil { return "Failed" }
        return session.status.label
    }
    private func detailText(_ detail: String) -> String {
        switch session.status {
        case .needsYou: return "· \(detail) permission"
        case .finished: return "· \(detail.replacingOccurrences(of: "_", with: " "))"
        default: return "· \(detail)"
        }
    }

    /// The live feed: what the agent is running right now and what it just ran, grouped by tool.
    private var tools: some View {
        let recent = Set(session.tools.sorted {
            ($0.running > 0 ? 1 : 0, $0.failures > 0 ? 1 : 0, $0.lastEventAt) > ($1.running > 0 ? 1 : 0, $1.failures > 0 ? 1 : 0, $1.lastEventAt)
        }.prefix(3).map(\.name))
        let shown = session.tools.filter { recent.contains($0.name) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown) { ToolRow(group: $0, now: now) }
        }
    }

    private func lastMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(IslandPalette.hairline).frame(height: 1).padding(.bottom, 5)
            HStack {
                Text(session.lastMessageIsError ? "Error" : isPreviousTurn ? "Previous reply" : "Last reply")
                    .font(.system(size: 12)).foregroundStyle(session.lastMessageIsError ? IslandPalette.failure : IslandPalette.secondary)
                Spacer()
                // The status chip already says when this turn ended; only an earlier turn's reply needs its own time.
                if isPreviousTurn, let at = session.lastMessageAt {
                    Text(IslandFormat.relative(at, now: now)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(IslandPalette.tertiary)
                }
            }
            ScrollableReply(text: message)
        }
    }

    private var isPreviousTurn: Bool {
        guard let started = session.turnStartedAt, let at = session.lastMessageAt else { return false }
        return at < started
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        let isDemo = center.source == .demo
        if session.canReply && !isDemo {
            ReplyComposer(session: session, host: host, center: center, model: model)
        } else if let note = center.replyNotes[session.id], case .sent(let at) = note, now.timeIntervalSince(at) < 120, session.status == .finished {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill").font(.system(size: 11))
                Text("Reply sent. \(session.client.displayName) is picking it up.").font(.system(size: 12))
                Spacer(minLength: 6)
                if let host { OpenHostButton(host: host, compact: true) { center.openHost(of: session.id) } }
            }
            .foregroundStyle(IslandPalette.secondary)
        } else if session.client == .claude, session.status == .finished, !isDemo, center.claudeHooksLackReplies, center.repliesWanted() {
            // Explain the missing reply field instead of leaving it silently absent.
            HStack(spacing: 8) {
                Text("To reply from here, update the Claude Code hooks.").font(.system(size: 12)).foregroundStyle(IslandPalette.secondary)
                Button("Settings…") { model.onOpenSettings?() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.primary)
                Spacer(minLength: 6)
                if let host { OpenHostButton(host: host, compact: true) { center.openHost(of: session.id) } }
            }
        } else if let host {
            HStack(spacing: 8) {
                if case .expired? = center.replyNotes[session.id] {
                    Text("This turn can’t be answered from here any more.").font(.system(size: 12)).foregroundStyle(IslandPalette.tertiary)
                } else if session.status == .needsYou {
                    Text("Waiting for your answer").font(.system(size: 12)).foregroundStyle(IslandPalette.attention)
                }
                Spacer(minLength: 6)
                OpenHostButton(host: host, compact: false) { center.openHost(of: session.id) }
            }
        }
    }
}

/// The reply in a bounded, scrollable area. A soft fade at the bottom shows there is more,
/// and disappears once the end is reached. Short replies take only the room they need.
struct ScrollableReply: View {
    let text: String
    static let maximumHeight: CGFloat = 150
    @State private var contentHeight: CGFloat = 0
    @State private var atEnd = true

    var body: some View {
        let overflows = contentHeight > Self.maximumHeight
        ScrollView(.vertical) {
            Text(IslandFormat.markdown(text))
                .font(.system(size: 13)).foregroundStyle(IslandPalette.primary.opacity(0.88))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.bottom, overflows ? 12 : 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 4
        } action: { _, value in atEnd = value }
        .frame(height: min(max(contentHeight, 18), Self.maximumHeight))
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [IslandPalette.shell.opacity(0), IslandPalette.shell], startPoint: .top, endPoint: .bottom)
                .frame(height: 36)
                .allowsHitTesting(false)
                .opacity(overflows && !atEnd ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: atEnd)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The agent's mark: its installed app icon, or a neutral glyph.
struct ClientMark: View {
    let client: AgentClient
    var body: some View {
        Group {
            if let image = AgentClientIcon.image(client) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: AgentClientIcon.symbol(client)).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(client == .claude ? IslandPalette.working : IslandPalette.primary)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.1)))
            }
        }
        .frame(width: 18, height: 18)
        .help(client.displayName)
        .accessibilityLabel(client.displayName)
    }
}

/// Brings the hosting app forward: its icon, and its name when there is room.
struct OpenHostButton: View {
    let host: AgentHostApp
    let compact: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = host.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 18, height: 18) }
                if !compact { Text("Open \(host.name)").font(.system(size: 12, weight: .medium)).lineLimit(1) }
            }
            .foregroundStyle(IslandPalette.primary)
            .padding(.horizontal, compact ? 6 : 10).frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(host.name)")
        .accessibilityLabel("Open \(host.name)")
    }
}

/// Answer a finished Claude Code turn without leaving what you are doing. Return sends.
struct ReplyComposer: View {
    let session: AgentSession
    let host: AgentHostApp?
    @ObservedObject var center: AgentActivityCenter
    @ObservedObject var model: AgentIslandModel
    @FocusState private var focused: Bool

    private var draft: Binding<String> {
        Binding(get: { center.drafts[session.id] ?? "" },
                set: { center.drafts[session.id] = String($0.prefix(AgentReplyChannel.maximumReply)) })
    }
    private var canSend: Bool { !(center.drafts[session.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            if let host { OpenHostButton(host: host, compact: true) { center.openHost(of: session.id) } }
            TextField("Reply to \(session.client.displayName)…", text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(IslandPalette.primary)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(send)
                .onExitCommand { focused = false; model.onCollapse?() }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.28 : 0.1), lineWidth: 1))
                .simultaneousGesture(TapGesture().onEnded { model.onWantsKeyboard?(); focused = true })
                .accessibilityLabel("Reply to \(session.client.displayName)")
                .accessibilityHint("Sends your reply to this session. Press Return to send.")
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(canSend ? Color.black : IslandPalette.tertiary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(canSend ? IslandPalette.primary : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send reply")
        }
        .onChange(of: focused) { _, value in model.composing = value }
        .onDisappear { model.composing = false }
    }

    private func send() {
        guard canSend else { return }
        center.sendReply(to: session.id, text: center.drafts[session.id] ?? "")
        focused = false
    }
}

struct ToolRow: View {
    let group: AgentToolGroup
    let now: Date
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: IslandFormat.symbol(forTool: group.name))
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(IslandPalette.secondary)
                .frame(width: 16)
            Text(IslandFormat.toolName(group.name)).font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(IslandPalette.primary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if group.failures > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    Text("\(group.failures) failed")
                }
                .font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(IslandPalette.failure)
            }
            Text("×\(group.attempts)").font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(IslandPalette.working)
                .frame(minWidth: 34, alignment: .trailing)
            Text(group.running > 0 ? "running" : IslandFormat.relative(group.lastEventAt, now: now))
                .font(.system(size: 11.5)).monospacedDigit()
                .foregroundStyle(group.running > 0 ? IslandPalette.working.opacity(0.9) : IslandPalette.tertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IslandPalette.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name), \(group.attempts) \(group.attempts == 1 ? "call" : "calls")"
            + (group.failures > 0 ? ", \(group.failures) failed" : "") + (group.running > 0 ? ", running" : ""))
    }
}


enum IslandFormat {
    /// Inline Markdown (bold, italics, `code`, links) for an agent reply. Headings and list markers
    /// are tidied rather than shown raw; anything unparsable falls back to plain text.
    static func markdown(_ text: String) -> AttributedString {
        let tidied = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var line = String(line)
            if let range = line.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) { line.removeSubrange(range) }
            if let range = line.range(of: #"^\s*[-*]\s+"#, options: .regularExpression) { line.replaceSubrange(range, with: "• ") }
            return line
        }.joined(separator: "\n")
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var attributed = try? AttributedString(markdown: tidied, options: options) else { return AttributedString(text) }
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = .system(size: 12, design: .monospaced)
            attributed[run.range].backgroundColor = Color.white.opacity(0.08)
        }
        return attributed
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return String(format: "%dm %02ds", total / 60, total % 60) }
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }
    /// MCP tools arrive as mcp__server__tool; show the readable tail.
    static func toolName(_ name: String) -> String {
        guard name.hasPrefix("mcp__") else { return name }
        let parts = name.split(separator: "_", omittingEmptySubsequences: true)
        return parts.count >= 3 ? "\(parts[1]) · \(parts[2...].joined(separator: "_"))" : name
    }
    static func symbol(forTool name: String) -> String {
        let lower = name.lowercased()
        if lower.hasPrefix("mcp__") { return "puzzlepiece.extension" }
        if ["bash", "shell", "exec_command", "local_shell", "powershell"].contains(lower) { return "terminal" }
        if lower == "read" || lower == "notebookread" { return "doc.text" }
        if ["edit", "write", "multiedit", "apply_patch", "notebookedit"].contains(lower) { return "pencil" }
        if ["grep", "glob", "search", "toolsearch"].contains(lower) { return "magnifyingglass" }
        if lower.hasPrefix("web") { return "globe" }
        if ["task", "agent"].contains(lower) { return "person.2" }
        return "chevron.left.forwardslash.chevron.right"
    }
}
