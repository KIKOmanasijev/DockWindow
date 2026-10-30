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
        let data = PrivateLayouts.remoteToken(pid: pid, elementID: elementID)
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
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(p, to: AXValue.self), .cgPoint, &point), AXValueGetValue(unsafeDowncast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        guard point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width >= 0, size.height >= 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func elements(_ value: CFTypeRef?) -> [AXUIElement] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(item, to: AXUIElement.self)
        }
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] { elements(value(element, kAXChildrenAttribute)) }
}
