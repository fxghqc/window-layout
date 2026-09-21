import XCTest
@testable import WindowLayoutCore

final class WindowPlacementTests: XCTestCase {
    let target = Rect(x: 800, y: 100, w: 700, h: 500)

    func testResizeRepositioningMustFinishInOneInvocation() {
        var actual = Rect(x: 10, y: 10, w: 1200, h: 800)
        let success = placeWindowFrame(target, read: { actual }, setPosition: {
            actual.x = $0.x; actual.y = $0.y
        }, setSize: {
            if actual.w != $0.w {
                actual.x = 300 // Simulate the application adjusting its origin on resize.
            }
            actual.w = $0.w; actual.h = $0.h
        }, wait: { _ in })
        XCTAssertTrue(success)
        XCTAssertEqual(actual, target)
    }

    func testAcceptedButIgnoredWritesMustNotReportSuccess() {
        let actual = Rect(x: 0, y: 0, w: 100, h: 100)
        var writes = 0
        XCTAssertFalse(placeWindowFrame(target, read: { actual }, setPosition: { _ in writes += 1 },
                                        setSize: { _ in }, wait: { _ in }))
        XCTAssertLessThanOrEqual(writes, 4)
    }

    func testDeferredResizeDriftIsRetriedOnSameWindow() {
        var actual = Rect(x: 0, y: 0, w: 100, h: 100)
        var waits = 0
        var positions = 0
        XCTAssertTrue(placeWindowFrame(target, read: { actual }, setPosition: {
            positions += 1
            actual.x = $0.x; actual.y = $0.y
        }, setSize: {
            actual.w = $0.w; actual.h = $0.h
        }, wait: { _ in
            waits += 1
            if waits == 2 { actual.x -= 100 }
        }))
        XCTAssertEqual(positions, 2)
        XCTAssertEqual(actual, target)
    }

    func testAsynchronousWritesAreWaitedFor() {
        var actual = Rect(x: 0, y: 0, w: 100, h: 100)
        var pending: Rect?
        XCTAssertTrue(placeWindowFrame(target, read: { actual }, setPosition: { pending = $0 },
                                      setSize: { _ in }, wait: { _ in
            if let update = pending { actual = update; pending = nil }
        }))
        XCTAssertEqual(actual, target)
    }

    func testFixedSizeWindowOnlyRequiresPosition() {
        var actual = Rect(x: 0, y: 0, w: 100, h: 100)
        XCTAssertTrue(placeWindowFrame(target, read: { actual }, setPosition: {
            actual.x = $0.x; actual.y = $0.y
        }, setSize: { _ in XCTFail("Fixed-size window must not be resized") },
                                      wait: { _ in }, resize: false))
    }

    func testUnreadableWindowCannotReportSuccess() {
        XCTAssertFalse(placeWindowFrame(target, read: { nil }, setPosition: { _ in },
                                       setSize: { _ in }, wait: { _ in }))
    }

    func testPlacementUsesRoundedAndMinimumDimensions() {
        let normalized = Rect(x: 1, y: -2, w: 40, h: 30)
        XCTAssertTrue(placementMatches(normalized, target: Rect(x: 1.2, y: -1.8, w: 10, h: 10)))
    }
}
