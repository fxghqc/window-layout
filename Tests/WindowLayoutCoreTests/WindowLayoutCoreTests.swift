import XCTest
@testable import WindowLayoutCore

final class WindowLayoutCoreTests: XCTestCase {
    func testTitleScorePrefersExactAndContainedTitles() {
        XCTAssertEqual(titleScore(saved: "Inbox", live: "Inbox"), 100)
        XCTAssertEqual(titleScore(saved: "Inbox", live: "Inbox - Mail"), 75)
        XCTAssertGreaterThan(
            titleScore(saved: "Project board - Google Chrome", live: "Project board - Chrome"),
            titleScore(saved: "Project board - Google Chrome", live: "Unrelated window")
        )
    }

    func testTargetFrameConvertsSavedBottomLeftCoordinatesToAXCoordinates() {
        let screen = Rect(x: 0, y: 0, w: 1920, h: 1080)
        let window = SavedWindow(
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "Terminal",
            subrole: "AXStandardWindow",
            frame: Rect(x: 100, y: 100, w: 800, h: 600)
        )

        XCTAssertEqual(
            targetFrame(savedWindow: window, savedScreens: [screen], targetScreens: [screen]),
            Rect(x: 100, y: 380, w: 800, h: 600)
        )
    }

    func testTargetFrameScalesWithDisplayResolution() {
        let source = Rect(x: 0, y: 0, w: 1920, h: 1080)
        let target = Rect(x: 0, y: 0, w: 960, h: 540)
        let window = SavedWindow(
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "Terminal",
            subrole: "AXStandardWindow",
            frame: Rect(x: 100, y: 100, w: 800, h: 600)
        )

        XCTAssertEqual(
            targetFrame(savedWindow: window, savedScreens: [source], targetScreens: [target]),
            Rect(x: 50, y: 190, w: 400, h: 300)
        )
    }

    func testSavedFrameIsInverseOfAXConversion() {
        let screen = Rect(x: 0, y: 0, w: 1920, h: 1080)
        XCTAssertEqual(
            savedFrame(fromAXFrame: Rect(x: 100, y: 380, w: 800, h: 600), display: screen),
            Rect(x: 100, y: 100, w: 800, h: 600)
        )
    }

    func testRectTolerance() {
        let expected = Rect(x: 0, y: 0, w: 1920, h: 1080)
        XCTAssertTrue(rectMatches(expected, Rect(x: 0.5, y: -0.5, w: 1920.5, h: 1079.5)))
        XCTAssertFalse(rectMatches(expected, Rect(x: 2, y: 0, w: 1920, h: 1080)))
    }
}
