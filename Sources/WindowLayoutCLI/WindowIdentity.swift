import AppKit
import WindowLayoutCore

struct SystemWindow {
    var id: UInt32
    var pid: Int32
    var frame: Rect
}

func systemWindows() -> [SystemWindow] {
    let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { item in
        guard let layer = item[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
              let id = item[kCGWindowNumber as String] as? NSNumber,
              let pid = item[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return SystemWindow(id: id.uint32Value, pid: pid.int32Value,
                            frame: Rect(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height))
    }
}

func windowIdentity(app: NSRunningApplication, frame: Rect, windows: [SystemWindow]) -> WindowIdentity? {
    guard let launch = app.launchDate else { return nil }
    // Public AX does not expose CGWindowID. Join only unique bounds within this PID;
    // overlapping identical windows are deliberately left unidentified.
    let matches = windows.filter { $0.pid == app.processIdentifier && rectMatches($0.frame, frame, tolerance: 1) }
    guard matches.count == 1, let match = matches.first else { return nil }
    return WindowIdentity(windowID: match.id, processID: app.processIdentifier,
                          launchTime: launch.timeIntervalSince1970)
}
