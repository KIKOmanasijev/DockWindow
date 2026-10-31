import Foundation
import Darwin

/// Keeps framework handles alive for the lifetime of all resolved C function pointers.
internal enum RuntimeSymbols {
    static let handles: [UnsafeMutableRawPointer] = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
    ].compactMap { (path: String) in path.withCString { dlopen($0, RTLD_LAZY | RTLD_LOCAL) } }
    static func load<T>(_ names: [String], as type: T.Type) -> T? {
        guard MemoryLayout<T>.size == MemoryLayout<UnsafeMutableRawPointer>.size else { return nil }
        for name in names {
            for handle in handles {
                if let address = dlsym(handle, name) { return unsafeBitCast(address, to: type) }
            }
        }
        return nil
    }
}
