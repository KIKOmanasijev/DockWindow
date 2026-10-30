import Foundation

/// Stable tile identity, independent of mutable window titles, state and MRU timestamps.
public enum SwitcherTileID: Hashable {
    case window(UInt32)
    case app(pid_t)
}
extension SwitcherItem {
    public var tileID: SwitcherTileID {
        switch self { case .window(let window): return .window(window.id); case .windowlessApp(let app): return .app(app.pid) }
    }
}

/// Pure selection state for live switcher snapshots and quick switching.
public struct SwitcherSession {
    public private(set) var items: [SwitcherItem] = []
    public private(set) var selectedID: SwitcherTileID?
    public var selectedIndex: Int? { items.firstIndex { $0.tileID == selectedID } }
    public var selectedItem: SwitcherItem? { selectedIndex.map { items[$0] } }
    public init() {}
    public mutating func begin(items: [SwitcherItem], reverse: Bool) {
        self.items = items
        let index = SwitcherPolicy.nextIndex(current: 0, count: items.count, delta: reverse ? -1 : 1)
        selectedID = index.map { items[$0].tileID }
    }
    public mutating func update(items: [SwitcherItem]) {
        let oldIndex = selectedIndex ?? 0
        self.items = items
        if !items.contains(where: { $0.tileID == selectedID }) {
            selectedID = items.isEmpty ? nil : items[min(oldIndex, items.count - 1)].tileID
        }
    }
    public mutating func select(_ id: SwitcherTileID) {
        if items.contains(where: { $0.tileID == id }) { selectedID = id }
    }
    public mutating func move(delta: Int) {
        guard let index = SwitcherPolicy.nextIndex(current: selectedIndex ?? 0, count: items.count, delta: delta) else { return }
        selectedID = items[index].tileID
    }
    /// Vertical arrows keep the column when possible, clamping the final short row.
    public mutating func moveVertically(direction: Int, columns: Int) {
        guard let index = selectedIndex, !items.isEmpty else { return }
        let width = max(1, columns)
        let rows = (items.count + width - 1) / width
        let row = ((index / width + direction) % rows + rows) % rows
        selectedID = items[min(row * width + index % width, items.count - 1)].tileID
    }
}
