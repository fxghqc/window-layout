import Foundation

public func normalizedPlacementFrame(_ frame: Rect) -> Rect {
    Rect(x: frame.x.rounded(), y: frame.y.rounded(),
         w: max(40, frame.w.rounded()), h: max(30, frame.h.rounded()))
}

public func placementMatches(_ actual: Rect?, target: Rect, resize: Bool = true) -> Bool {
    guard let actual else { return false }
    let expected = normalizedPlacementFrame(target)
    return abs(actual.x - expected.x) <= 2 && abs(actual.y - expected.y) <= 2 &&
        (!resize || (abs(actual.w - expected.w) <= 2 && abs(actual.h - expected.h) <= 2))
}

public func placeWindowFrame(
    _ target: Rect,
    read: () -> Rect?,
    setPosition: (Rect) -> Void,
    setSize: (Rect) -> Void,
    wait: (TimeInterval) -> Void,
    resize: Bool = true,
    attempts: Int = 4
) -> Bool {
    guard attempts > 0 else { return false }
    let expected = normalizedPlacementFrame(target)
    for _ in 0..<attempts {
        // Resize can reposition a window; crossing screens can also clamp size.
        // Keep correcting the same window until two readbacks agree with the target.
        if resize { setSize(expected) }
        setPosition(expected)
        wait(0.12)
        if placementMatches(read(), target: expected, resize: resize) {
            wait(0.12)
            if placementMatches(read(), target: expected, resize: resize) { return true }
        }
    }
    return false
}
