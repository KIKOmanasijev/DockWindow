import Foundation

/// Captures the display owning a requested desktop so later checks do not accept another display.
public struct DesktopTarget: Equatable {
    public let spaceID: UInt64
    public let displayID: String
    public init?(spaceID: UInt64, activeSpaceIDs: [String: UInt64]) {
        guard spaceID != 0, let display = activeSpaceIDs.keys.sorted().first(where: { activeSpaceIDs[$0] == spaceID }) else { return nil }
        self.spaceID = spaceID; displayID = display
    }
    public func isCurrent(in activeSpaceIDs: [String: UInt64]) -> Bool { activeSpaceIDs[displayID] == spaceID }
}
