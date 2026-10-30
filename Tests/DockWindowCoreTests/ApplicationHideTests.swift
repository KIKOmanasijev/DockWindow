import XCTest
@testable import DockWindowCore

final class ApplicationHideTests: XCTestCase {
    @MainActor func testNegativeAcknowledgementStillWaitsForHiddenState() async {
        var hidden = false
        var fallbackCalls = 0
        let result = await ApplicationHideOperation.run(isHidden: { hidden }, isTerminated: { false },
            isCancelled: { false }, requestHide: { false },
            setAXHidden: { fallbackCalls += 1; return false }, wait: { hidden = true })
        XCTAssertTrue(result)
        XCTAssertEqual(fallbackCalls, 0)
    }

    @MainActor func testAcceptedRequestWaitsForActualHiddenStateWithoutFallback() async {
        var hidden = false
        var fallbackCalls = 0
        let result = await ApplicationHideOperation.run(isHidden: { hidden }, isTerminated: { false },
            isCancelled: { false }, requestHide: { true },
            setAXHidden: { fallbackCalls += 1; return true }, wait: { hidden = true })
        XCTAssertTrue(result)
        XCTAssertEqual(fallbackCalls, 0)
    }

    @MainActor func testAcceptedButIneffectiveRequestUsesAccessibilityFallback() async {
        var hidden = false
        var fallbackCalls = 0
        let result = await ApplicationHideOperation.run(isHidden: { hidden }, isTerminated: { false },
            isCancelled: { false }, requestHide: { true },
            setAXHidden: { fallbackCalls += 1; hidden = true; return true }, wait: {})
        XCTAssertTrue(result)
        XCTAssertEqual(fallbackCalls, 1)
    }

    @MainActor func testSuccessfulAXRequestWithoutHiddenStateIsStillFailure() async {
        let result = await ApplicationHideOperation.run(isHidden: { false }, isTerminated: { false },
            isCancelled: { false }, requestHide: { false }, setAXHidden: { true }, wait: {})
        XCTAssertFalse(result)
    }

    @MainActor func testCancellationAndTerminatedAppsNeverReachFallback() async {
        for terminated in [false, true] {
            var cancelled = false
            var requests = 0
            var fallbacks = 0
            let result = await ApplicationHideOperation.run(isHidden: { false }, isTerminated: { terminated },
                isCancelled: { cancelled }, requestHide: { requests += 1; return true },
                setAXHidden: { fallbacks += 1; return true }, wait: { cancelled = true })
            XCTAssertFalse(result)
            XCTAssertEqual(requests, terminated ? 0 : 1)
            XCTAssertEqual(fallbacks, 0)
        }
    }
}
