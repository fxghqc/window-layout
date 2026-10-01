import XCTest
@testable import WindowLayoutCore

final class DisplayMappingTests: XCTestCase {
    private let laptop = Rect(x: 0, y: 0, w: 2000, h: 1300)
    private let external = Rect(x: -600, y: -1800, w: 3200, h: 1800)

    private func identity(_ uuid: String, model: UInt32 = 1, serial: UInt32 = 0) -> DisplayIdentity {
        DisplayIdentity(uuid: uuid, vendor: 1, model: model, serial: serial)
    }

    private func layout(screens: [Rect], identities: [DisplayIdentity]? = nil) -> Layout {
        Layout(title: "Office", screens: screens, displayIdentities: identities, windows: [])
    }

    func testReplacedExternalDisplayIsMappedWhileLaptopIsPreserved() {
        let saved = layout(screens: [laptop, external], identities: [identity("laptop"), identity("old", model: 2)])
        let shifted = Rect(x: -1300, y: -1800, w: 3200, h: 1800)
        XCTAssertEqual(compatibleDisplayMapping(layout: saved, currentScreens: [shifted, laptop],
            currentIdentities: [identity("new", model: 3), identity("LAPTOP")]), [1, 0])
    }

    func testIdentityWinsEvenWhenGeometryWouldSwapDisplays() {
        let saved = layout(screens: [laptop, external], identities: [identity("laptop"), identity("old", model: 2)])
        XCTAssertEqual(compatibleDisplayMapping(layout: saved, currentScreens: [laptop, external],
            currentIdentities: [identity("new", model: 3), identity("laptop")]), [1, 0])
    }

    func testUnmatchedScreenCannotTakeLaterExactIdentityMatch() {
        let saved = layout(screens: [laptop, external], identities: [identity("old"), identity("known")])
        XCTAssertEqual(compatibleDisplayMapping(layout: saved, currentScreens: [laptop, external],
            currentIdentities: [identity("known"), identity("new")]), [1, 0])
    }

    func testSerialMatchIsPreferredOverSameModelMatch() {
        let saved = layout(screens: [laptop, external], identities: [identity("old-a", serial: 7), identity("old-b", serial: 8)])
        XCTAssertEqual(compatibleDisplayMapping(layout: saved, currentScreens: [laptop, external],
            currentIdentities: [identity("new-b", serial: 8), identity("new-a", serial: 7)]), [1, 0])
    }

    func testLegacyLayoutUsesResolutionAndPositionInsteadOfEnumerationOrder() {
        XCTAssertEqual(compatibleDisplayMapping(layout: layout(screens: [laptop, external]),
            currentScreens: [external, laptop], currentIdentities: [identity("new-a"), identity("new-b")]), [1, 0])
    }

    func testDifferentDisplayCountsAreRejected() {
        let saved = layout(screens: [laptop, external])
        XCTAssertNil(compatibleDisplayMapping(layout: saved, currentScreens: [laptop], currentIdentities: [identity("one")]))
        XCTAssertNil(compatibleDisplayMapping(layout: saved, currentScreens: [laptop, external, external],
            currentIdentities: [identity("one"), identity("two"), identity("three")]))
    }

    func testInvalidDisplayGeometryAndMetadataAreRejected() {
        XCTAssertNil(compatibleDisplayMapping(layout: layout(screens: []), currentScreens: [], currentIdentities: []))
        XCTAssertNil(compatibleDisplayMapping(layout: layout(screens: [laptop]), currentScreens: [laptop], currentIdentities: []))
        XCTAssertNil(compatibleDisplayMapping(layout: layout(screens: [Rect(x: 0, y: 0, w: 0, h: 1300)]),
            currentScreens: [laptop], currentIdentities: [identity("one")]))
    }

    func testMappedWindowScalesAndTranslatesWithoutChangingSavedLayout() throws {
        let saved = layout(screens: [laptop, external], identities: [identity("laptop"), identity("old", model: 2)])
        let original = saved
        let smaller = Rect(x: 2000, y: 0, w: 1600, h: 900)
        let current = [smaller, laptop]
        let indices = try XCTUnwrap(compatibleDisplayMapping(layout: saved, currentScreens: current,
            currentIdentities: [identity("new", model: 3), identity("laptop")]))
        let window = SavedWindow(appName: "Terminal", bundleID: "com.apple.Terminal", title: "Work",
            subrole: "AXStandardWindow", frame: Rect(x: -280, y: -1620, w: 1600, h: 900))
        XCTAssertEqual(targetFrame(savedWindow: window, savedScreens: saved.screens, targetScreens: indices.map { current[$0] }),
            Rect(x: 2160, y: 360, w: 800, h: 450))
        XCTAssertEqual(saved, original)
    }
}
