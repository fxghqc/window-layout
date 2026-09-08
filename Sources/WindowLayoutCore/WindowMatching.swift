import Foundation

public struct WindowIdentity: Codable, Equatable, Hashable, Sendable {
    public var windowID: UInt32
    public var processID: Int32
    public var launchTime: Double

    public init(windowID: UInt32, processID: Int32, launchTime: Double) {
        self.windowID = windowID
        self.processID = processID
        self.launchTime = launchTime
    }

    public func sameProcess(as other: WindowIdentity) -> Bool {
        processID == other.processID && launchTime == other.launchTime
    }
}

public struct WindowCandidate {
    public var title: String
    public var identity: WindowIdentity?

    public init(title: String, identity: WindowIdentity? = nil) {
        self.title = title
        self.identity = identity
    }
}

public func normalizedWindowTitle(_ title: String) -> String {
    // Chrome decorates the title with a changing memory counter. Keep profile names.
    title.replacingOccurrences(
        of: #" - High memory usage - [\d,.]+\s*[KMGT]?B(?= - Google Chrome(?: - .*)?$)"#,
        with: "", options: [.regularExpression, .caseInsensitive]
    ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

public func matchWindowTitles(saved: [String], live: [String], strict: Bool) -> [Int: Int] {
    matchWindows(saved: saved.map { WindowCandidate(title: $0) },
                 live: live.map { WindowCandidate(title: $0) }, strict: strict)
}

/// Plans the entire application's assignment before any window is moved.
public func matchWindows(saved: [WindowCandidate], live: [WindowCandidate], strict: Bool) -> [Int: Int] {
    var matches: [Int: Int] = [:]
    var used = Set<Int>()
    var blocked = Set<Int>()

    for index in saved.indices {
        guard let identity = saved[index].identity else { continue }
        let targets = live.indices.filter { live[$0].identity == identity }
        let sources = saved.indices.filter { saved[$0].identity == identity }
        if targets.count == 1, sources.count == 1, let target = targets.first {
            matches[index] = target
            used.insert(target)
        } else if strict && (targets.count > 1 || live.contains(where: {
            $0.identity.map { identity.sameProcess(as: $0) } ?? false
        })) {
            // A missing window from the same process was closed, not renamed.
            blocked.insert(index)
        }
    }

    let savedTitles = saved.map { normalizedWindowTitle($0.title) }
    let liveTitles = live.map { normalizedWindowTitle($0.title) }
    for title in Set(savedTitles) where !title.isEmpty {
        let sources = saved.indices.filter { matches[$0] == nil && !blocked.contains($0) && savedTitles[$0] == title }
        let targets = live.indices.filter { !used.contains($0) && liveTitles[$0] == title }
        if sources.count == 1, targets.count == 1, let source = sources.first, let target = targets.first {
            matches[source] = target
            used.insert(target)
        }
    }

    // Legacy fallback remains available for non-browser apps only.
    if !strict {
        for index in saved.indices where matches[index] == nil {
            let available = live.indices.filter { !used.contains($0) }
            if let best = available.max(by: {
                titleScore(saved: saved[index].title, live: live[$0].title) <
                titleScore(saved: saved[index].title, live: live[$1].title)
            }) {
                matches[index] = best
                used.insert(best)
            }
        }
    }
    return matches
}
