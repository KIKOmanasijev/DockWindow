import Foundation
import CoreGraphics

/// Runtime-only SkyLight calls. Signatures checked against AltTab's framework declarations.
public final class SkyLight {
    public static let shared = SkyLight()
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Active = @convention(c) (UInt32) -> UInt64
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias Current = @convention(c) (UInt32, CFString) -> UInt64
    private typealias Spaces = @convention(c) (UInt32, Int, CFArray) -> Unmanaged<CFArray>?
    private typealias Windows = @convention(c) (UInt32, Int, CFArray, Int, UnsafeMutablePointer<Int>, UnsafeMutablePointer<Int>) -> Unmanaged<CFArray>?
    private let connection = RuntimeSymbols.load(["CGSMainConnectionID", "SLSMainConnectionID"], as: Connection.self)
    private let active = RuntimeSymbols.load(["CGSGetActiveSpace"], as: Active.self)
    private let displays = RuntimeSymbols.load(["CGSCopyManagedDisplaySpaces", "SLSCopyManagedDisplaySpaces"], as: Displays.self)
    private let current = RuntimeSymbols.load(["CGSManagedDisplayGetCurrentSpace", "SLSManagedDisplayGetCurrentSpace"], as: Current.self)
    private let spaces = RuntimeSymbols.load(["CGSCopySpacesForWindows", "SLSCopySpacesForWindows"], as: Spaces.self)
    private let windows = RuntimeSymbols.load(["CGSCopyWindowsWithOptionsAndTags", "SLSCopyWindowsWithOptionsAndTags"], as: Windows.self)
    public var availability: [String: Bool] {
        ["CGSGetActiveSpace": active != nil, "CGSMainConnectionID": connection != nil, "CGSCopyManagedDisplaySpaces": displays != nil,
         "CGSManagedDisplayGetCurrentSpace": current != nil, "CGSCopySpacesForWindows": spaces != nil,
         "CGSCopyWindowsWithOptionsAndTags": windows != nil]
    }
    public var isAvailable: Bool { connection != nil && displays != nil && spaces != nil && windows != nil }
    private init() {}
    /// CGSGetActiveSpace supplies a shared desktop fallback when per-display topology is unavailable.
    public func activeSpace() -> UInt64? {
        guard let cid = connection?(), let value = active?(cid), value != 0 else { return nil }
        return value
    }
    /// CGSCopyManagedDisplaySpaces describes every display and its desktop topology.
    public func managedDisplays() -> [[String: Any]] {
        guard let cid = connection?(), let result = displays?(cid)?.takeRetainedValue() else { return [] }
        return result as? [[String: Any]] ?? []
    }
    /// CGSManagedDisplayGetCurrentSpace resolves the current desktop of a display UUID.
    public func currentSpace(display: String) -> UInt64? {
        guard let cid = connection?(), let value = current?(cid, display as CFString), value != 0 else { return nil }
        return value
    }
    /// CGSCopySpacesForWindows returns a union, never a parallel array indexed by window.
    public func spaces(containing ids: [CGWindowID]) -> [UInt64]? {
        guard !ids.isEmpty, let cid = connection?(), let array = spaces?(cid, 7, ids.map { NSNumber(value: $0) } as CFArray)?.takeRetainedValue() else { return nil }
        return (array as? [NSNumber])?.map(\.uint64Value)
    }
    /// CGSCopyWindowsWithOptionsAndTags inverts membership in one request per Space, independent of window count.
    public func windows(on space: UInt64) -> Set<CGWindowID>? {
        guard let cid = connection?() else { return nil }
        var setTags = 0
        var clearTags = 0
        guard let array = windows?(cid, 0, [NSNumber(value: space)] as CFArray, 7, &setTags, &clearTags)?.takeRetainedValue(),
              let numbers = array as? [NSNumber] else { return nil }
        return Set(numbers.map(\.uint32Value))
    }
}
