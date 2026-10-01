import Foundation

public func displayIdentityMatchScore(saved: DisplayIdentity, current: DisplayIdentity) -> Int? {
    if !saved.uuid.isEmpty, saved.uuid.caseInsensitiveCompare(current.uuid) == .orderedSame { return 10_000 }
    if saved.serial != 0,
       saved.vendor == current.vendor,
       saved.model == current.model,
       saved.serial == current.serial { return 1_000 }
    if saved.vendor == current.vendor && saved.model == current.model { return 100 }
    return nil
}

private struct DisplayMappingScore {
    var identityCounts = [0, 0, 0]
    var distance: Double = 0

    func isBetter(than other: DisplayMappingScore) -> Bool {
        for (count, otherCount) in zip(identityCounts, other.identityCounts) where count != otherCount {
            return count > otherCount
        }
        return distance < other.distance
    }
}

/// Returns current display indices in saved-screen order without changing either topology.
public func compatibleDisplayMapping(
    layout: Layout,
    currentScreens: [Rect],
    currentIdentities: [DisplayIdentity]
) -> [Int]? {
    guard !layout.screens.isEmpty,
          layout.screens.count == currentScreens.count,
          currentScreens.count == currentIdentities.count,
          (layout.screens + currentScreens).allSatisfy({
              $0.x.isFinite && $0.y.isFinite && $0.w.isFinite && $0.h.isFinite && $0.w > 0 && $0.h > 0
          }) else { return nil }
    let savedIdentities = layout.displayIdentities.flatMap {
        $0.count == layout.screens.count ? $0 : nil
    }
    var best: (indices: [Int], score: DisplayMappingScore)?

    func search(index: Int, used: Set<Int>, result: [Int], score: DisplayMappingScore) {
        if index == layout.screens.count {
            if best == nil || score.isBetter(than: best!.score) { best = (result, score) }
            return
        }
        let source = layout.screens[index]
        for currentIndex in currentScreens.indices where !used.contains(currentIndex) {
            let target = currentScreens[currentIndex]
            var nextScore = score
            if let savedIdentities,
               let identityScore = displayIdentityMatchScore(saved: savedIdentities[index], current: currentIdentities[currentIndex]) {
                let tier = identityScore == 10_000 ? 0 : (identityScore == 1_000 ? 1 : 2)
                nextScore.identityCounts[tier] += 1
            }
            nextScore.distance += abs(target.w - source.w) * 20 + abs(target.h - source.h) * 20
                + abs(target.x - source.x) + abs(target.y - source.y)
            var nextUsed = used
            nextUsed.insert(currentIndex)
            search(index: index + 1, used: nextUsed, result: result + [currentIndex], score: nextScore)
        }
    }

    // Rank identities globally so an unmatched screen cannot consume a known screen's match.
    search(index: 0, used: [], result: [], score: DisplayMappingScore())
    return best?.indices
}
