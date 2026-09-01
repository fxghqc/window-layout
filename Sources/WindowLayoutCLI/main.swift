import AppKit
import ApplicationServices
import Foundation
import WindowLayoutCore

struct ActiveDisplay {
    var id: CGDirectDisplayID
    var identity: DisplayIdentity
    var frame: Rect
}


struct LiveWindow {
    var appName: String
    var bundleID: String
    var title: String
    var subrole: String
    var frame: Rect
    var element: AXUIElement
}

struct LiveWindowSnapshot {
    var windows: [String: [LiveWindow]] = [:]
    var runningBundles: Set<String> = []
    var accessibleBundles: Set<String> = []
    var errors: [String: [AXError]] = [:]
}

let usage = """
Usage:
  window-layout list
  window-layout diagnose-app <bundle-id>
  window-layout inspect <layout-name>
  window-layout check <layout-name>
  window-layout arrange <layout-name> [--dry-run]
  window-layout apply <layout-name> [--dry-run]
  window-layout save <layout-name>
  window-layout import-moom <layout-name>...

Layouts are stored in ~/Library/Application Support/window-layout/layouts.json.
Moom is only used by import-moom, so normal save/apply/list/inspect do not
depend on Moom.
"""

func toolDirectory() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
}

func appSupportDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("window-layout", isDirectory: true)
}

func layoutsURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["WINDOW_LAYOUT_CONFIG"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return appSupportDirectory().appendingPathComponent("layouts.json")
}

func timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

func parseRect(_ raw: String) -> Rect? {
    let pattern = #"-?\d+(?:\.\d+)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
    let nums = matches.compactMap { Double(ns.substring(with: $0.range)) }
    guard nums.count >= 4 else { return nil }
    return Rect(x: nums[0], y: nums[1], w: nums[2], h: nums[3])
}

func loadStore() throws -> LayoutStore {
    let url = layoutsURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        return LayoutStore(version: 2, updatedAt: timestamp(), layouts: [])
    }
    let decoder = JSONDecoder()
    return try decoder.decode(LayoutStore.self, from: try Data(contentsOf: url))
}

func saveStore(_ store: LayoutStore) throws {
    try FileManager.default.createDirectory(at: appSupportDirectory(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(store)
    try data.write(to: layoutsURL(), options: [.atomic])
}

func upsert(_ layout: Layout, into store: inout LayoutStore) {
    if let index = store.layouts.firstIndex(where: { $0.title == layout.title }) {
        store.layouts[index] = layout
    } else {
        store.layouts.append(layout)
    }
    store.layouts.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    store.updatedAt = timestamp()
}

func moomPlistPath() -> String {
    NSString(string: "~/Library/Preferences/com.manytricks.Moom.plist").expandingTildeInPath
}

func loadMoomLayouts() throws -> [Layout] {
    let data = try Data(contentsOf: URL(fileURLWithPath: moomPlistPath()))
    guard
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
        let controls = plist["Custom Controls (4001)"] as? [[String: Any]]
    else {
        throw NSError(domain: "window-layout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read Moom custom controls"])
    }

    return controls.compactMap { control in
        guard
            let title = control["Title"] as? String,
            let snapshot = control["Snapshot"] as? [[String: Any]],
            let screenStrings = control["Snapshot Screens"] as? [String]
        else { return nil }

        let screens = screenStrings.compactMap(parseRect)
        let windows = snapshot.compactMap { item -> SavedWindow? in
            guard
                let appName = item["Application Name"] as? String,
                let bundleID = item["Bundle Identifier"] as? String,
                let frameString = item["Window Frame"] as? String,
                let frame = parseRect(frameString)
            else { return nil }

            return SavedWindow(
                appName: appName,
                bundleID: bundleID,
                title: item["Window Title"] as? String ?? "",
                subrole: item["Window Subrole"] as? String ?? "",
                frame: frame
            )
        }
        return Layout(title: title, screens: screens, displayIdentities: nil, windows: windows)
    }
}

func displayUUID(_ id: CGDirectDisplayID) -> String {
    let raw = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
    return CFUUIDCreateString(nil, raw)! as String
}

func currentDisplays() -> [ActiveDisplay] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.map { id in
        let b = CGDisplayBounds(id)
        return ActiveDisplay(
            id: id,
            identity: DisplayIdentity(
                uuid: displayUUID(id),
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id)
            ),
            frame: Rect(x: b.origin.x, y: b.origin.y, w: b.width, h: b.height)
        )
    }
}

func containingDisplay(for frame: Rect, displays: [ActiveDisplay]) -> ActiveDisplay? {
    displays.first { display in
        frame.x >= display.frame.x - 1 &&
        frame.x < display.frame.x + display.frame.w + 1 &&
        frame.y >= display.frame.y - 1 &&
        frame.y < display.frame.y + display.frame.h + 1
    } ?? displays.first
}

func identityMatchScore(saved: DisplayIdentity, current: DisplayIdentity) -> Int? {
    if saved.uuid.caseInsensitiveCompare(current.uuid) == .orderedSame { return 10_000 }
    if saved.serial != 0,
       saved.vendor == current.vendor,
       saved.model == current.model,
       saved.serial == current.serial { return 1_000 }
    if saved.vendor == current.vendor && saved.model == current.model { return 100 }
    return nil
}

func legacyMatchScore(saved: Rect, current: Rect) -> Double {
    abs(current.w - saved.w) * 20 +
    abs(current.h - saved.h) * 20 +
    abs(current.x - saved.x) +
    abs(current.y - saved.y)
}

func bestLegacyMapping(saved: [Rect], current: [ActiveDisplay]) -> [ActiveDisplay]? {
    guard current.count >= saved.count else { return nil }
    var best: ([ActiveDisplay], Double)?

    func search(index: Int, used: Set<Int>, result: [ActiveDisplay], score: Double) {
        if index == saved.count {
            if best == nil || score < best!.1 { best = (result, score) }
            return
        }
        for currentIndex in current.indices where !used.contains(currentIndex) {
            var nextUsed = used
            nextUsed.insert(currentIndex)
            search(
                index: index + 1,
                used: nextUsed,
                result: result + [current[currentIndex]],
                score: score + legacyMatchScore(saved: saved[index], current: current[currentIndex].frame)
            )
        }
    }

    search(index: 0, used: [], result: [], score: 0)
    return best?.0
}

func mapDisplays(layout: Layout, current: [ActiveDisplay]) -> [ActiveDisplay]? {
    guard let identities = layout.displayIdentities,
          identities.count == layout.screens.count else {
        return bestLegacyMapping(saved: layout.screens, current: current)
    }

    var result: [ActiveDisplay] = []
    var used = Set<Int>()
    for identity in identities {
        let candidates = current.indices.compactMap { index -> (Int, Int)? in
            guard !used.contains(index),
                  let score = identityMatchScore(saved: identity, current: current[index].identity) else { return nil }
            return (index, score)
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
        used.insert(best.0)
        result.append(current[best.0])
    }
    return result
}

func topologyMatches(layout: Layout, mapped: [ActiveDisplay]) -> Bool {
    mapped.count == layout.screens.count && zip(layout.screens, mapped).allSatisfy {
        rectMatches($0.0, $0.1.frame)
    }
}

func shortUUID(_ uuid: String) -> String {
    String(uuid.prefix(8))
}

func printTopologyDifferences(layout: Layout, mapped: [ActiveDisplay], prefix: String) {
    for (saved, active) in zip(layout.screens, mapped) where !rectMatches(saved, active.frame) {
        print("\(prefix) display \(shortUUID(active.identity.uuid)): \(Int(active.frame.x)),\(Int(active.frame.y)) -> \(Int(saved.x)),\(Int(saved.y)) \(Int(saved.w))x\(Int(saved.h))")
    }
}

func restoreDisplayArrangement(layout: Layout, mapped: [ActiveDisplay], dryRun: Bool) -> Bool {
    guard layout.displayIdentities?.count == layout.screens.count else {
        print("warning: layout has no display identities; screen arrangement was not changed")
        return true
    }
    guard !topologyMatches(layout: layout, mapped: mapped) else {
        print("display arrangement already matches \(layout.title)")
        return true
    }
    if dryRun {
        printTopologyDifferences(layout: layout, mapped: mapped, prefix: "would arrange")
        return true
    }

    var configuration: CGDisplayConfigRef?
    let beginResult = CGBeginDisplayConfiguration(&configuration)
    guard beginResult == .success, let configuration else {
        print("failed to begin display configuration: \(beginResult.rawValue)")
        return false
    }

    for (saved, active) in zip(layout.screens, mapped) {
        let result = CGConfigureDisplayOrigin(
            configuration,
            active.id,
            Int32(saved.x.rounded()),
            Int32(saved.y.rounded())
        )
        guard result == .success else {
            CGCancelDisplayConfiguration(configuration)
            print("failed to arrange display \(shortUUID(active.identity.uuid)): \(result.rawValue)")
            return false
        }
    }

    let completeResult = CGCompleteDisplayConfiguration(configuration, .permanently)
    guard completeResult == .success else {
        print("failed to apply display arrangement: \(completeResult.rawValue)")
        return false
    }

    for _ in 0..<30 {
        if let refreshed = mapDisplays(layout: layout, current: currentDisplays()),
           topologyMatches(layout: layout, mapped: refreshed) {
            print("restored display arrangement for \(layout.title)")
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("display arrangement did not stabilize for \(layout.title)")
    return false
}

func checkTopology(_ layout: Layout) -> Bool {
    guard layout.displayIdentities?.count == layout.screens.count else {
        print("FAIL: \(layout.title) has no saved display identities")
        return false
    }
    guard let mapped = mapDisplays(layout: layout, current: currentDisplays()) else {
        print("FAIL: connected displays do not match \(layout.title)")
        return false
    }
    guard topologyMatches(layout: layout, mapped: mapped) else {
        print("FAIL: active display topology does not match \(layout.title)")
        printTopologyDifferences(layout: layout, mapped: mapped, prefix: "mismatch")
        return false
    }
    print("PASS: active display topology matches \(layout.title)")
    return true
}

func axString(_ window: AXUIElement, _ attr: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, attr as CFString, &value) == .success else { return "" }
    return value as? String ?? ""
}

func axBool(_ window: AXUIElement, _ attr: String) -> Bool {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, attr as CFString, &value) == .success else { return false }
    return value as? Bool ?? false
}

func axFrame(_ window: AXUIElement) -> Rect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posRef,
          let sizeRef else { return nil }

    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
          AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
    return Rect(x: point.x, y: point.y, w: size.width, h: size.height)
}

func copyAXWindows(_ appElement: AXUIElement, into value: inout CFTypeRef?) -> AXError {
    value = nil
    return AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
}

func retryAXWindows(_ appElement: AXUIElement, value: inout CFTypeRef?) -> AXError {
    var error = copyAXWindows(appElement, into: &value)
    for _ in 0..<10 where error == .apiDisabled {
        Thread.sleep(forTimeInterval: 0.05)
        error = copyAXWindows(appElement, into: &value)
    }
    return error
}

func axWindows(_ appElement: AXUIElement) -> (error: AXError, windows: [AXUIElement], activation: String?) {
    var value: CFTypeRef?
    var error = copyAXWindows(appElement, into: &value)
    var activationSteps: [String] = []

    if error == .apiDisabled {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &roleValue)
        activationSteps.append("role=\(roleResult.rawValue)")
        error = retryAXWindows(appElement, value: &value)
    }

    if error == .apiDisabled {
        var mainWindowValue: CFTypeRef?
        let mainWindowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        )
        activationSteps.append("mainWindow=\(mainWindowResult.rawValue)")
        let target: AXUIElement
        if let mainWindowValue, CFGetTypeID(mainWindowValue) == AXUIElementGetTypeID() {
            target = unsafeBitCast(mainWindowValue, to: AXUIElement.self)
        } else {
            target = appElement
        }
        let enhancedResult = AXUIElementSetAttributeValue(
            target,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        activationSteps.append("enhanced=\(enhancedResult.rawValue)")
        if enhancedResult == .success {
            error = retryAXWindows(appElement, value: &value)
        }
    }

    return (error, value as? [AXUIElement] ?? [], activationSteps.isEmpty ? nil : activationSteps.joined(separator: ","))
}

func liveWindows() -> LiveWindowSnapshot {
    var result = LiveWindowSnapshot()
    for app in NSWorkspace.shared.runningApplications {
        guard let bundleID = app.bundleIdentifier else { continue }
        let key = bundleKey(bundleID)
        result.runningBundles.insert(key)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windowResult = axWindows(appElement)
        guard windowResult.error == .success else {
            result.errors[key, default: []].append(windowResult.error)
            continue
        }
        result.accessibleBundles.insert(key)

        for window in windowResult.windows {
            let subrole = axString(window, kAXSubroleAttribute)
            guard subrole == kAXStandardWindowSubrole as String else { continue }
            guard !axBool(window, kAXMinimizedAttribute) else { continue }
            guard let frame = axFrame(window), frame.w > 0, frame.h > 0 else { continue }
            let title = axString(window, kAXTitleAttribute)
            result.windows[key, default: []].append(LiveWindow(
                appName: app.localizedName ?? bundleID,
                bundleID: bundleID,
                title: title,
                subrole: subrole,
                frame: frame,
                element: window
            ))
        }
    }
    return result
}

func diagnoseApp(bundleID wantedBundleID: String) {
    let apps = NSWorkspace.shared.runningApplications.filter {
        bundleKey($0.bundleIdentifier ?? "") == bundleKey(wantedBundleID)
    }
    print("bundle=\(wantedBundleID) instances=\(apps.count) trusted=\(AXIsProcessTrusted())")
    for app in apps {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let result = axWindows(appElement)
        let activationText = result.activation.map { " activation=\($0)" } ?? ""
        print("pid=\(app.processIdentifier) name=\(app.localizedName ?? "") axError=\(result.error.rawValue) windows=\(result.windows.count) active=\(app.isActive) hidden=\(app.isHidden)\(activationText)")
        for (index, window) in result.windows.enumerated() {
            let subrole = axString(window, kAXSubroleAttribute)
            let minimized = axBool(window, kAXMinimizedAttribute)
            let frame = axFrame(window)
            let frameText = frame.map { "\(Int($0.x)),\(Int($0.y)) \(Int($0.w))x\(Int($0.h))" } ?? "unavailable"
            print("  [\(index)] subrole=\(subrole) minimized=\(minimized) frame=\(frameText) title=\(axString(window, kAXTitleAttribute))")
        }
    }
}

func allLiveWindows() -> [LiveWindow] {
    liveWindows().windows.values.flatMap { $0 }
}

func setFrame(_ frame: Rect, on window: AXUIElement) -> Bool {
    var point = CGPoint(x: frame.x.rounded(), y: frame.y.rounded())
    var size = CGSize(width: max(40, frame.w.rounded()), height: max(30, frame.h.rounded()))
    guard let positionValue = AXValueCreate(.cgPoint, &point),
          let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

    var canSetPosition = DarwinBoolean(false)
    var canSetSize = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canSetPosition)
    AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canSetSize)

    let p: AXError = canSetPosition.boolValue
        ? AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        : .failure
    let s: AXError = canSetSize.boolValue
        ? AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        : .success
    return p == .success && s == .success
}

func runnableSavedWindows(_ layout: Layout) -> [SavedWindow] {
    layout.windows.filter { window in
        window.subrole == kAXStandardWindowSubrole as String &&
        !window.bundleID.isEmpty
    }
}

func apply(_ layout: Layout, dryRun: Bool) {
    guard AXIsProcessTrusted() else {
        print("Accessibility permission is not granted for this process.")
        exit(2)
    }

    var displays = currentDisplays()
    guard var mappedDisplays = mapDisplays(layout: layout, current: displays) else {
        print("connected displays do not match \(layout.title)")
        return
    }
    guard restoreDisplayArrangement(layout: layout, mapped: mappedDisplays, dryRun: dryRun) else {
        return
    }
    if !dryRun, layout.displayIdentities?.count == layout.screens.count {
        displays = currentDisplays()
        guard let refreshed = mapDisplays(layout: layout, current: displays) else {
            print("could not rematch displays after restoring arrangement")
            return
        }
        mappedDisplays = refreshed
    }

    let targetScreens = layout.displayIdentities?.count == layout.screens.count
        ? layout.screens
        : mappedDisplays.map(\.frame)
    let saved = runnableSavedWindows(layout)
    let snapshot = liveWindows()
    var used: [String: Set<Int>] = [:]
    var moved = 0

    for savedWindow in saved {
        guard let frame = targetFrame(savedWindow: savedWindow, savedScreens: layout.screens, targetScreens: targetScreens) else {
            print("skip \(savedWindow.appName): no matching display")
            continue
        }
        let key = bundleKey(savedWindow.bundleID)
        let live = snapshot.windows[key] ?? []
        guard !live.isEmpty else {
            if !snapshot.runningBundles.contains(key) {
                print("skip \(savedWindow.appName): app not running")
            } else if !snapshot.accessibleBundles.contains(key),
                      snapshot.errors[key]?.allSatisfy({ $0 == .apiDisabled }) == true {
                print("skip \(savedWindow.appName): accessibility unavailable; restart the app")
            } else {
                print("skip \(savedWindow.appName): no standard window")
            }
            continue
        }

        let alreadyUsed = used[key, default: []]
        let available = live.enumerated().filter { !alreadyUsed.contains($0.offset) }
        guard let best = available.max(by: {
            titleScore(saved: savedWindow.title, live: $0.element.title) <
            titleScore(saved: savedWindow.title, live: $1.element.title)
        }) ?? available.first else {
            print("skip \(savedWindow.appName): no unused window")
            continue
        }

        used[key, default: []].insert(best.offset)
        let liveWindow = best.element
        let line = "\(savedWindow.appName) -> \(Int(frame.x)),\(Int(frame.y)) \(Int(frame.w))x\(Int(frame.h)) [\(liveWindow.title)]"
        if dryRun {
            print("would move " + line)
        } else if setFrame(frame, on: liveWindow.element) {
            moved += 1
            print("moved " + line)
        } else {
            print("failed " + line)
        }
    }

    if !dryRun {
        print("moved \(moved) window(s)")
    }
}

func saveCurrentLayout(named name: String) throws {
    guard AXIsProcessTrusted() else {
        print("Accessibility permission is not granted for this process.")
        exit(2)
    }

    let displays = currentDisplays()
    let windows = allLiveWindows().compactMap { live -> SavedWindow? in
        guard let display = containingDisplay(for: live.frame, displays: displays) else { return nil }
        return SavedWindow(
            appName: live.appName,
            bundleID: live.bundleID,
            title: live.title,
            subrole: live.subrole,
            frame: savedFrame(fromAXFrame: live.frame, display: display.frame)
        )
    }

    var store = try loadStore()
    store.version = 2
    upsert(Layout(
        title: name,
        screens: displays.map(\.frame),
        displayIdentities: displays.map(\.identity),
        windows: windows
    ), into: &store)
    try saveStore(store)
    print("saved \(name): \(displays.count) screen(s), \(windows.count) window(s)")
}

func importMoomLayouts(named names: [String]) throws {
    let moomLayouts = try loadMoomLayouts()
    var store = try loadStore()
    var imported = 0
    for name in names {
        guard let layout = moomLayouts.first(where: { $0.title == name }) else {
            print("skip \(name): not found in Moom")
            continue
        }
        upsert(layout, into: &store)
        imported += 1
        print("imported \(layout.title): \(layout.screens.count) screen(s), \(layout.windows.count) window(s)")
    }
    try saveStore(store)
    print("wrote \(imported) layout(s) to \(layoutsURL().path)")
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(64)
}

do {
    switch command {
    case "diagnose-app":
        guard args.count >= 2 else { print(usage); exit(64) }
        diagnoseApp(bundleID: args[1])
    case "list":
        let store = try loadStore()
        for layout in store.layouts {
            let runnable = runnableSavedWindows(layout).count
            print("\(layout.title)\t\(layout.screens.count) screen(s)\t\(layout.windows.count) saved\t\(runnable) standard")
        }
    case "inspect":
        guard args.count >= 2 else { print(usage); exit(64) }
        let name = args[1]
        let store = try loadStore()
        guard let layout = store.layouts.first(where: { $0.title == name }) else {
            print("Layout not found: \(name)")
            exit(1)
        }
        print("\(layout.title)")
        print("screens:")
        for (index, screen) in layout.screens.enumerated() {
            let identity = layout.displayIdentities.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            let label = identity.map { " uuid=\($0.uuid) vendor=\($0.vendor) model=\($0.model) serial=\($0.serial)" } ?? " identity=missing"
            print("  \(Int(screen.x)),\(Int(screen.y)) \(Int(screen.w))x\(Int(screen.h))\(label)")
        }
        print("windows:")
        for window in layout.windows {
            let marker = window.subrole == kAXStandardWindowSubrole as String ? "ok" : "skip"
            print("  [\(marker)] \(window.appName) \(window.subrole) \(Int(window.frame.x)),\(Int(window.frame.y)) \(Int(window.frame.w))x\(Int(window.frame.h)) \(window.title)")
        }
    case "check":
        guard args.count >= 2 else { print(usage); exit(64) }
        let name = args[1]
        let store = try loadStore()
        guard let layout = store.layouts.first(where: { $0.title == name }) else {
            print("Layout not found: \(name)")
            exit(1)
        }
        if !checkTopology(layout) { exit(1) }
    case "arrange":
        guard args.count >= 2 else { print(usage); exit(64) }
        let name = args[1]
        let dryRun = args.contains("--dry-run")
        let store = try loadStore()
        guard let layout = store.layouts.first(where: { $0.title == name }) else {
            print("Layout not found: \(name)")
            exit(1)
        }
        guard let mapped = mapDisplays(layout: layout, current: currentDisplays()) else {
            print("connected displays do not match \(layout.title)")
            exit(1)
        }
        if !restoreDisplayArrangement(layout: layout, mapped: mapped, dryRun: dryRun) { exit(1) }
    case "apply":
        guard args.count >= 2 else { print(usage); exit(64) }
        let name = args[1]
        let dryRun = args.contains("--dry-run")
        let store = try loadStore()
        guard let layout = store.layouts.first(where: { $0.title == name }) else {
            print("Layout not found: \(name)")
            exit(1)
        }
        apply(layout, dryRun: dryRun)
    case "save":
        guard args.count >= 2 else { print(usage); exit(64) }
        try saveCurrentLayout(named: args[1])
    case "import-moom":
        guard args.count >= 2 else { print(usage); exit(64) }
        try importMoomLayouts(named: Array(args.dropFirst()))
    default:
        print(usage)
        exit(64)
    }
} catch {
    print(error.localizedDescription)
    exit(1)
}
