import ApplicationServices
import Foundation

/// Runtime AX window IDs and remote tokens. No memory-layout reads of AX objects are used.
public final class AXPrivate {
    public static let shared = AXPrivate()
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private typealias Remote = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private let getWindow = RuntimeSymbols.load(["_AXUIElementGetWindow"], as: GetWindow.self)
    private let remote = RuntimeSymbols.load(["_AXUIElementCreateWithRemoteToken"], as: Remote.self)
    public var availability: [String: Bool] { ["_AXUIElementGetWindow": getWindow != nil, "_AXUIElementCreateWithRemoteToken": remote != nil] }
    public var isAvailable: Bool { getWindow != nil && remote != nil }
    private init() {}
    /// _AXUIElementGetWindow maps a window root or descendant to its WindowServer ID.
    public func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard getWindow?(element, &id) == AXError.success.rawValue, id != 0 else { return nil }
        return id
    }
    /// _AXUIElementCreateWithRemoteToken decodes pid, reserved, 'coco', and UInt64 element ID.
    public func element(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        var data = Data()
        var process = pid.littleEndian
        var reserved: UInt32 = 0
        var magic = UInt32(0x636f636f).littleEndian
        var identifier = elementID.littleEndian
        withUnsafeBytes(of: &process) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &reserved) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &magic) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &identifier) { data.append(contentsOf: $0) }
        return remote?(data as CFData)?.takeRetainedValue()
    }
}

internal enum AXRead {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func element(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = value(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
}
