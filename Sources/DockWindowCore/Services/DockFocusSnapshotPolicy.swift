import AppKit

/// Merges event state over slow inventory results. Owned by WindowTracker's main actor.
/// Inventory can replace window details, but cannot roll back an already observed activation,
/// focus timestamp, or desktop result. No Accessibility calls occur in this reducer.
internal struct DockFocusSnapshotPolicy {
    private(set) var snapshot = WindowSnapshot()
    private var activation: (app: TrackedApp, date: Date, include: Bool)?
    private var focus: (id: CGWindowID, pid: pid_t, date: Date)?
    private var focusDates: [CGWindowID: (pid: pid_t, date: Date)] = [:]
    private var spaceDate = Date.distantPast
    private var activeSpaces: [String: UInt64]?
    private var membership: [CGWindowID: [UInt64]] = [:]
    private(set) var inventoryRevision: UInt64 = 0
    private(set) var activationRevision: UInt64 = 0

    mutating func inventory(_ value: WindowSnapshot, revision: UInt64, activationRevision acknowledged: UInt64 = 0) {
        guard revision >= inventoryRevision else { return }
        inventoryRevision = revision
        snapshot = value
        // Only a collection requested after this activation can retire a superseded app.
        if let activation, acknowledged >= activationRevision,
           !value.apps.contains(where: { $0.pid == activation.app.pid && $0.isFrontmost }) { self.activation = nil }
        focusDates = focusDates.filter { id, _ in id == focus?.id || value.windows.contains { $0.id == id } }
        membership = membership.filter { id, _ in value.windows.contains { $0.id == id } }
        merge()
    }
    mutating func activate(_ app: TrackedApp, at date: Date, includeInInventory: Bool = true) {
        activationRevision &+= 1
        activation = (app, date, includeInInventory)
        merge()
    }
    @discardableResult mutating func focused(id: CGWindowID, pid: pid_t, at date: Date) -> Bool {
        guard let app = snapshot.apps.first(where: { $0.isFrontmost }), app.pid == pid,
              date >= (activation?.date ?? .distantPast), date >= (focus?.date ?? .distantPast) else { return false }
        focus = (id, pid, date)
        focusDates[id] = (pid, date)
        merge()
        return true
    }
    mutating func spaces(_ active: [String: UInt64], membership values: [CGWindowID: [UInt64]] = [:], revision: UInt64? = nil, at date: Date = Date()) {
        guard date >= spaceDate else { return }
        spaceDate = date
        activeSpaces = active
        if revision == inventoryRevision {
            for (id, spaces) in values where !spaces.isEmpty { membership[id] = spaces }
        }
        merge()
    }
    private mutating func merge() {
        if let activeSpaces { snapshot.activeSpaceIDs = activeSpaces }
        if let activation {
            if activation.include, !snapshot.apps.contains(where: { $0.pid == activation.app.pid }) { snapshot.apps.append(activation.app) }
            for index in snapshot.apps.indices {
                let frontmost = snapshot.apps[index].pid == activation.app.pid
                snapshot.apps[index].isFrontmost = frontmost
                if frontmost {
                    snapshot.apps[index].lastActivatedAt = activation.date
                    snapshot.apps[index].lastActiveSpaceIDs = Array(snapshot.activeSpaceIDs.values)
                }
            }
        }
        for index in snapshot.windows.indices {
            let id = snapshot.windows[index].id
            if let spaces = membership[id], !snapshot.windows[index].isMinimized {
                snapshot.windows[index].spaceIDs = spaces
                snapshot.windows[index].rememberedSpaceIDs = spaces
            }
            if let focus = focusDates[id], focus.pid == snapshot.windows[index].pid {
                snapshot.windows[index].lastFocusedAt = max(snapshot.windows[index].lastFocusedAt, focus.date)
            }
        }
        snapshot.windows.sort { $0.lastFocusedAt == $1.lastFocusedAt ? $0.id < $1.id : $0.lastFocusedAt > $1.lastFocusedAt }
    }
}
