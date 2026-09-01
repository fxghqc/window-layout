import AppKit
import ApplicationServices
import Foundation
import WindowLayoutCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let cliPath = NSString(string: "~/.local/bin/window-layout").expandingTildeInPath
    private let layoutsPath = NSString(string: "~/Library/Application Support/window-layout/layouts.json").expandingTildeInPath

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissionIfNeeded()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Window Layout")
            button.image?.isTemplate = true
            button.toolTip = "Window Layout"
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let title = NSMenuItem(title: "Window Layout", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let layouts = loadLayouts()
        if layouts.isEmpty {
            let empty = NSMenuItem(title: "No Layouts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for layout in layouts {
                let item = NSMenuItem(title: layout.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()

                let apply = NSMenuItem(title: "Apply", action: #selector(applyLayout(_:)), keyEquivalent: "")
                apply.target = self
                apply.representedObject = layout.title
                submenu.addItem(apply)

                let update = NSMenuItem(title: "Update from Current Windows", action: #selector(updateLayout(_:)), keyEquivalent: "")
                update.target = self
                update.representedObject = layout.title
                submenu.addItem(update)

                let info = NSMenuItem(title: "\(layout.screens.count) screen(s), \(layout.windows.count) window(s)", action: nil, keyEquivalent: "")
                info.isEnabled = false
                submenu.addItem(.separator())
                submenu.addItem(info)

                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let add = NSMenuItem(title: "Add New Layout...", action: #selector(addLayout), keyEquivalent: "n")
        add.target = self
        menu.addItem(add)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let openConfig = NSMenuItem(title: "Reveal Config", action: #selector(revealConfig), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func loadLayouts() -> [Layout] {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: layoutsPath))
            return try JSONDecoder().decode(LayoutStore.self, from: data).layouts
        } catch {
            return []
        }
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        run(["apply", name], successTitle: "Applied \(name)")
    }

    @objc private func updateLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        run(["save", name], successTitle: "Updated \(name)")
        rebuildMenu()
    }

    @objc private func addLayout() {
        let alert = NSAlert()
        alert.messageText = "Add New Layout"
        alert.informativeText = "Save the current window layout with this name."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "Layout name"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        run(["save", name], successTitle: "Saved \(name)")
        rebuildMenu()
    }

    @objc private func refreshMenu() {
        rebuildMenu()
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: layoutsPath)])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func run(_ arguments: [String], successTitle: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runCLI(arguments)
            DispatchQueue.main.async {
                if result.status == 0 {
                    self.showAlert(title: successTitle, text: result.output)
                } else {
                    self.showAlert(title: "Window Layout Failed", text: result.output)
                }
            }
        }
    }

    private func runCLI(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text.isEmpty ? "Done." : text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
