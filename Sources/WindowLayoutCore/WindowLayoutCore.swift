import Foundation

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct SavedWindow: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleID: String
    public var title: String
    public var subrole: String
    public var frame: Rect
    public var identity: WindowIdentity?

    public init(appName: String, bundleID: String, title: String, subrole: String, frame: Rect, identity: WindowIdentity? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.subrole = subrole
        self.frame = frame
        self.identity = identity
    }
}

public struct DisplayIdentity: Codable, Equatable, Sendable {
    public var uuid: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32

    public init(uuid: String, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }
}

public struct Layout: Codable, Equatable, Sendable {
    public var title: String
    public var screens: [Rect]
    public var displayIdentities: [DisplayIdentity]?
    public var windows: [SavedWindow]

    public init(
        title: String,
        screens: [Rect],
        displayIdentities: [DisplayIdentity]?,
        windows: [SavedWindow]
    ) {
        self.title = title
        self.screens = screens
        self.displayIdentities = displayIdentities
        self.windows = windows
    }
}

public struct LayoutStore: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: String
    public var layouts: [Layout]

    public init(version: Int, updatedAt: String, layouts: [Layout]) {
        self.version = version
        self.updatedAt = updatedAt
        self.layouts = layouts
    }
}

public func bundleKey(_ bundleID: String) -> String {
    bundleID.lowercased()
}

public func screenIndexForSavedWindow(_ window: SavedWindow, screens: [Rect]) -> Int? {
    screens.firstIndex { screen in
        window.frame.x >= screen.x - 1 &&
        window.frame.x < screen.x + screen.w + 1 &&
        window.frame.y >= screen.y - 1 &&
        window.frame.y < screen.y + screen.h + 1
    } ?? screens.indices.first
}

public func targetFrame(savedWindow: SavedWindow, savedScreens: [Rect], targetScreens: [Rect]) -> Rect? {
    guard let index = screenIndexForSavedWindow(savedWindow, screens: savedScreens),
          targetScreens.indices.contains(index) else { return nil }
    let source = savedScreens[index]
    let target = targetScreens[index]

    let relX = (savedWindow.frame.x - source.x) / source.w
    let relBottom = (savedWindow.frame.y - source.y) / source.h
    let relW = savedWindow.frame.w / source.w
    let relH = savedWindow.frame.h / source.h

    return Rect(
        x: target.x + relX * target.w,
        y: target.y + (1.0 - relBottom - relH) * target.h,
        w: relW * target.w,
        h: relH * target.h
    )
}

public func titleScore(saved: String, live: String) -> Int {
    let savedTitle = saved.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let liveTitle = live.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if savedTitle.isEmpty || liveTitle.isEmpty { return 0 }
    if savedTitle == liveTitle { return 100 }
    if liveTitle.contains(savedTitle) || savedTitle.contains(liveTitle) { return 75 }
    let savedWords = Set(savedTitle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    let liveWords = Set(liveTitle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    return savedWords.intersection(liveWords).count * 10
}

public func rectMatches(_ lhs: Rect, _ rhs: Rect, tolerance: Double = 1) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance &&
    abs(lhs.y - rhs.y) <= tolerance &&
    abs(lhs.w - rhs.w) <= tolerance &&
    abs(lhs.h - rhs.h) <= tolerance
}

public func savedFrame(fromAXFrame axFrame: Rect, display: Rect) -> Rect {
    Rect(
        x: axFrame.x,
        y: display.y + display.h - (axFrame.y - display.y) - axFrame.h,
        w: axFrame.w,
        h: axFrame.h
    )
}
