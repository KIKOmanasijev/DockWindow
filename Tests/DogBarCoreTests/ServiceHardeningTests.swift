import XCTest
@testable import DogBarCore

final class ServiceHardeningTests: XCTestCase {
    func testPackedRemoteTokenHasNoAlignmentPadding() {
        let bytes = Array(PrivateLayouts.remoteToken(pid: 0x12345678, elementID: 0x0102030405060708))
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(Array(bytes[0..<4]), [0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(Array(bytes[4..<8]), [0, 0, 0, 0])
        XCTAssertEqual(Array(bytes[8..<12]), [0x6f, 0x63, 0x6f, 0x63])
        XCTAssertEqual(Array(bytes[12..<20]), [8, 7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(Array(PrivateLayouts.remoteToken(pid: -1, elementID: .max).suffix(8)), Array(repeating: 255, count: 8))
    }

    func testFocusRecordAllocationFieldsAndZeroedPadding() {
        let bytes = PrivateLayouts.focusRecord(windowID: 0x12345678)
        XCTAssertEqual(bytes.count, 256)
        XCTAssertEqual(Array(bytes[4..<8]), [248, 0, 0, 0])
        XCTAssertEqual(bytes[8], 1)
        XCTAssertEqual(bytes[58], 16)
        XCTAssertEqual(Array(bytes[60..<64]), [0x78, 0x56, 0x34, 0x12])
        for start in [32, 40] {
            let bits = bytes[start..<(start + 8)].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
            XCTAssertEqual(Double(bitPattern: bits), 300_000)
        }
        let fields = Set([4, 8, 58] + Array(32..<48) + Array(60..<64))
        XCTAssertTrue(bytes.indices.filter { !fields.contains($0) }.allSatisfy { bytes[$0] == 0 })
        XCTAssertEqual(Array(PrivateLayouts.focusRecord(windowID: .max)[60..<64]), [255, 255, 255, 255])
    }

    func testCaptureDimensionsPreserveAspectAndBoundInvalidInputs() {
        let result = CaptureDimensions.pixels(frame: CGSize(width: 1600, height: 900), size: CGSize(width: 320, height: 200), scale: 2)
        XCTAssertEqual(result.width, 640)
        XCTAssertEqual(result.height, 360)
        for invalid in [CGFloat.nan, .infinity, -.infinity, -1, 0] {
            let size = CaptureDimensions.pixels(frame: CGSize(width: invalid, height: 1), size: CGSize(width: 320, height: 200), scale: 2)
            XCTAssertEqual(size.width, 1)
            XCTAssertEqual(size.height, 1)
        }
        let huge = CaptureDimensions.pixels(frame: CGSize(width: 1, height: 1), size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), scale: CGFloat.greatestFiniteMagnitude)
        XCTAssertEqual(huge.width, 2048)
        XCTAssertEqual(huge.height, 2048)
    }

    func testCancellationIsStickyAcrossQueuedWork() {
        let cancellation = OperationCancellation()
        XCTAssertFalse(cancellation.isCancelled)
        cancellation.cancel()
        cancellation.cancel()
        let queue = DispatchQueue(label: "test.cancellation")
        XCTAssertTrue(queue.sync { cancellation.isCancelled })
    }

    @MainActor func testPrecancelledServicesReturnBeforeSystemWork() async {
        let tracker = WindowTracker()
        let opener = NewWindowOpener(tracker: tracker)
        let opening = Task { @MainActor in
            await opener.openPinned(bundleURL: URL(fileURLWithPath: "/nonexistent/Fixture.app"), onSpace: 7)
        }
        opening.cancel()
        if case .cancelled = await opening.value {} else { XCTFail("Cancelled launch must not reach NSWorkspace") }
        let actions = WindowActions(tracker: tracker)
        let focusing = Task { @MainActor in await actions.focusVerified(TrackedWindow(id: 1)) }
        focusing.cancel()
        let focused = await focusing.value
        XCTAssertFalse(focused)
    }

    func testRequestedDisplayCannotBeReplacedByAnotherDisplay() throws {
        let target = try XCTUnwrap(DesktopTarget(spaceID: 7, activeSpaceIDs: ["display-a": 7, "display-b": 8]))
        XCTAssertFalse(target.isCurrent(in: ["display-a": 8, "display-b": 7]))
        XCTAssertFalse(target.isCurrent(in: ["display-b": 7]))
        XCTAssertTrue(target.isCurrent(in: ["display-a": 7]))
    }
}
