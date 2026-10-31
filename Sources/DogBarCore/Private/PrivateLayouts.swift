import ApplicationServices
import Foundation

/// Pure byte encoders for the layouts recorded in Docs/PrivateAPIReference.md.
internal enum PrivateLayouts {
    static func remoteToken(pid: pid_t, elementID: UInt64) -> Data {
        var data = Data()
        var process = pid.littleEndian
        var reserved: UInt32 = 0
        var magic = UInt32(0x636f636f).littleEndian
        var identifier = elementID.littleEndian
        withUnsafeBytes(of: &process) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &reserved) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &magic) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &identifier) { data.append(contentsOf: $0) }
        return data
    }
    static func focusRecord(windowID: CGWindowID) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 256)
        record[4] = 248
        record[8] = 1
        record[58] = 16
        var identifier = windowID.littleEndian
        var point = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &identifier) { record.replaceSubrange(60..<64, with: $0) }
        withUnsafeBytes(of: &point) { record.replaceSubrange(32..<48, with: $0) }
        return record
    }
}
