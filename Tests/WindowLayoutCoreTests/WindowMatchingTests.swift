import XCTest
@testable import WindowLayoutCore

final class WindowMatchingTests: XCTestCase {
    func testChangedTabMustNotStealLaterExactMatch() {
        let matches = matchWindowTitles(
            saved: ["Closed - Google Chrome - Work", "Login - Google Chrome - Work"],
            live: ["Login - Google Chrome - Work", "Other - Google Chrome - Work"], strict: true)
        XCTAssertEqual(matches, [1: 0])
    }

    func testDuplicateTitlesMustNotDependOnFrontToBackOrder() {
        XCTAssertTrue(matchWindowTitles(saved: ["New Tab", "New Tab"], live: ["New Tab", "New Tab"], strict: true).isEmpty)
    }

    func testMemoryUsageIsNotWindowIdentity() {
        XCTAssertEqual(matchWindowTitles(
            saved: ["Wafer Map - High memory usage - 1,017 MB - Google Chrome - Work"],
            live: ["Wafer Map - High memory usage - 1,016 MB - Google Chrome - Work"], strict: true), [0: 0])
    }

    func testEmptyLiveTitleDoesNotMatchEverything() {
        XCTAssertEqual(titleScore(saved: "Login", live: ""), 0)
    }

    private func window(_ title: String, _ id: UInt32, pid: Int32 = 10, launch: Double = 100) -> WindowCandidate {
        WindowCandidate(title: title, identity: WindowIdentity(windowID: id, processID: pid, launchTime: launch))
    }

    func testIDsSurviveChangedTabsAndEveryEnumerationOrder() {
        let saved = [window("First", 1), window("Second", 2), window("Third", 3)]
        for order: [UInt32] in [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]] {
            let live = order.map { window("Identical new tab", $0) }
            let result = matchWindows(saved: saved, live: live, strict: true)
            XCTAssertEqual(result.count, 3)
            for (source, target) in result { XCTAssertEqual(saved[source].identity, live[target].identity) }
        }
    }

    func testIdentityWinsEvenIfTitlesSwap() {
        XCTAssertEqual(matchWindows(saved: [window("A", 1), window("B", 2)],
                                    live: [window("B", 1), window("A", 2)], strict: true), [0: 0, 1: 1])
    }

    func testTwoChromeProcessesCannotShareWindowIDs() {
        XCTAssertEqual(matchWindows(saved: [window("Old", 1, pid: 10), window("Old", 1, pid: 20)],
                                    live: [window("New", 1, pid: 20), window("New", 1, pid: 10)], strict: true), [0: 1, 1: 0])
    }

    func testRecycledPIDAndWindowIDAfterRestartDoNotMatch() {
        XCTAssertTrue(matchWindows(saved: [window("Old", 1)],
                                   live: [window("Unrelated", 1, launch: 200)], strict: true).isEmpty)
    }

    func testAfterRestartUniqueTitleCanMatch() {
        XCTAssertEqual(matchWindows(saved: [window("Named window", 1)],
                                    live: [window("Named window", 9, launch: 200)], strict: true), [0: 0])
    }

    func testClosedWindowDoesNotStealNewWindowWithSameTitle() {
        XCTAssertTrue(matchWindows(saved: [window("Login", 1)],
                                   live: [window("Login", 2)], strict: true).isEmpty)
    }

    func testChromeProfilesRemainDistinct() {
        XCTAssertTrue(matchWindowTitles(saved: ["Login - Google Chrome - Work"],
                                        live: ["Login - Google Chrome - Personal"], strict: true).isEmpty)
    }

    func testLegacySavedWindowDecodesWithoutIdentity() throws {
        let data = Data(#"{"appName":"Chrome","bundleID":"com.google.Chrome","title":"Login","subrole":"AXStandardWindow","frame":{"x":1,"y":2,"w":3,"h":4}}"#.utf8)
        var saved = try JSONDecoder().decode(SavedWindow.self, from: data)
        XCTAssertNil(saved.identity)
        saved.identity = window("", 1).identity
        XCTAssertEqual(try JSONDecoder().decode(SavedWindow.self, from: JSONEncoder().encode(saved)), saved)
    }

    func testNonBrowserExactMatchReservedBeforeFallback() {
        XCTAssertEqual(matchWindowTitles(saved: ["Closed", "Login"], live: ["Login", "Other"], strict: false), [0: 1, 1: 0])
    }
}
