import AppKit
import WebKit

// Compiled into a temporary fixture-only app by native-ui.mjs.
// Never changes wallpaper, login items, or the user's Application Support directory.
func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw WallpaperError.invalid("Native UI test failed: " + message) }
}
@MainActor
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

let application = NSApplication.shared
let editorApp = MainActor.assumeIsolated { EditorApp() }
application.delegate = editorApp
Task { @MainActor in
    do {
        let deadline = Date().addingTimeInterval(40)
        while !editorApp.ready && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(editorApp.ready, "startup: \(editorApp.status.stringValue)")
        editorApp.timer?.invalidate()
        let ui = editorApp.editorView
        try require(
            !descendants(editorApp.window.contentView!).contains { $0 is WKWebView },
            "web view in window hierarchy")
        try require(ui.preview.image != nil, "native image preview")
        try require(ui.table.numberOfRows > 0, "event rows")
        try require(ui.name.stringValue == "Prototype module", "saved module name")
        try require(ui.resolution.titleOfSelectedItem == "2880 × 1800", "custom saved image size")
        try require(ui.showTitle.state == .off, "legacy title default")
        try require(ui.includeWeekends.state == .off, "weekends default off")
        ui.includeWeekends.performClick(nil)
        let weekendDeadline = Date().addingTimeInterval(15)
        while ui.editor["includeWeekends"] as? Bool != true && Date() < weekendDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(
            ui.editor["includeWeekends"] as? Bool == true,
            "weekend inclusion action persists")
        try require(
            (editorApp.saved["editor"] as? [String: Any])?["futureSetting"] as? String == "kept",
            "unknown saved setting")
        try require(editorApp.refreshInterval == 1800, "saved refresh interval")

        if ProcessInfo.processInfo.environment["WAPACAL_UI_HOLD"] == "1" {
            print("Fixture UI ready")
            return
        }

        let mainMenu = NSApp.mainMenu!
        try require(
            editorApp.item.menu!.items.map { $0.title } == [
                "Open Wapacal", "Settings…", "Refresh & Apply", "Quit",
            ]
                && editorApp.item.menu!.items[2].action
                    == #selector(editorApp.refreshAndApplyNow),
            "compact menu bar refresh-and-apply action")
        let calendarMenu = mainMenu.items.first { $0.title == "Calendar" }!.submenu!
        try require(
            calendarMenu.items.first?.title == "Refresh & Apply"
                && calendarMenu.items.first?.action == #selector(editorApp.refreshAndApplyNow),
            "Calendar menu refresh-and-apply action")
        let fileMenu = mainMenu.items.first { $0.title == "File" }!.submenu!
        try require(
            fileMenu.items.first?.title == "Open wallpaper…"
                && fileMenu.items.first?.keyEquivalent == "o", "File menu import shortcut")
        let importer = editorApp.getCompanion()
        try require(
            importer.window == nil && NSApp.mainMenu === mainMenu,
            "creating importer opens no empty window or replacement menu")
        let missing = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["WAPACAL_UI_OUTPUT"]!
        ).appendingPathComponent("missing.heic")
        editorApp.openExportFile(missing.path)
        try require(
            importer.window == nil && editorApp.lastEditorError != nil,
            "invalid import reports error without empty preview")
        ui.showError("")

        // Settings reuse the original controls and state in a separate native window.
        try require(
            editorApp.urlField.window === editorApp.settingsWindow,
            "subscription field belongs to Settings")
        try require(!editorApp.settingsWindow.isVisible, "Settings stays closed at startup")
        let settingsItem = NSApp.mainMenu!.items[0].submenu!.items.first { $0.title == "Settings…" }
        try require(settingsItem?.keyEquivalent == ",", "standard Settings shortcut")
        editorApp.showSettings()
        editorApp.settingsWindow.contentView?.layoutSubtreeIfNeeded()
        try require(editorApp.settingsWindow.isVisible, "open Settings")
        try require(
            !descendants(editorApp.settingsWindow.contentView!).contains { $0 is WKWebView },
            "native Settings")
        try require(editorApp.urlField.frame.width > 450, "readable subscription URL field")
        editorApp.addSource()
        try require(
            editorApp.settingsWindow.firstResponder is NSTextView,
            "new calendar focuses Settings URL field")
        editorApp.sourcePicker.selectItem(at: 0)
        // Restore the fixture selection without changing saved subscriptions.
        editorApp.selectSource()
        editorApp.status.stringValue = "Settings status check"
        try require(
            editorApp.settingsStatus.stringValue == "Settings status check",
            "operation feedback in both windows")
        editorApp.settingsTabs.selectTabViewItem(withIdentifier: "general")
        try require(
            editorApp.automatic.window === editorApp.settingsWindow,
            "automatic updates belong to Settings")
        editorApp.refreshPicker.selectItem(at: 0)
        editorApp.changeRefreshInterval()
        try require(editorApp.refreshInterval == 900, "refresh frequency in Settings persists")
        editorApp.refreshPicker.selectItem(at: 1)
        editorApp.changeRefreshInterval()
        editorApp.window.performClose(nil)
        try require(
            editorApp.settingsWindow.isVisible && NSApp.activationPolicy() == .regular,
            "Settings remains usable after editor closes")
        editorApp.show()
        editorApp.showSettings()
        editorApp.closeWindow()
        try require(
            !editorApp.settingsWindow.isVisible && editorApp.window.isVisible,
            "Close Window targets Settings")
        try require(NSApp.activationPolicy() == .regular, "closing Settings keeps editor active")
        editorApp.showSettings()
        try require(
            editorApp.refreshPicker.indexOfSelectedItem == 1,
            "Settings reopens with retained values")
        editorApp.settingsWindow.performClose(nil)
        try require(ui.appearanceFields.isHidden, "appearance starts collapsed")
        ui.appearanceToggle.performClick(nil)
        try require(!ui.appearanceFields.isHidden, "appearance disclosure opens")
        try require(ui.theme.itemTitles == ["System", "Light", "Dark"], "appearance choices")
        try require(ui.exportMenu.menu!.items.count == 3, "both export formats remain accessible")

        // Drive target/action through real native controls.
        ui.theme.selectItem(at: 2)
        ui.changeControl(ui.theme)
        let darkDeadline = Date().addingTimeInterval(15)
        while ui.editor["theme"] as? String != "dark" && Date() < darkDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(ui.editor["theme"] as? String == "dark", "appearance action")
        ui.tabs.selectTabViewItem(withIdentifier: "events")
        editorApp.window.contentView?.layoutSubtreeIfNeeded()
        try require(
            ui.table.enclosingScrollView!.frame.width > 700, "event table fills the tab width")
        try require(
            ui.table.enclosingScrollView!.superview!.frame.height > 450,
            "event split fills the tab height: scroll=\(ui.table.enclosingScrollView!.frame), parent=\(ui.table.enclosingScrollView!.superview!.frame), editor=\(ui.view.frame), main=\(ui.tabs.superview!.frame), tab=\(ui.tabs.frame), content=\(ui.tabs.selectedTabViewItem!.view!.frame)"
        )
        ui.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try require(!ui.details.string.isEmpty, "native details")
        let eventID = ui.events[0]["uid"] as! String
        let checkboxCell =
            ui.tableView(ui.table, viewFor: ui.table.tableColumns[0], row: 0) as! NSTableCellView
        let checkbox = checkboxCell.subviews.compactMap { $0 as? NSButton }.first!
        checkbox.state = .off
        ui.includeEvent(checkbox)
        let exclusionDeadline = Date().addingTimeInterval(15)
        while !(ui.editor["excludedEventIds"] as? [String] ?? []).contains(eventID)
            && Date() < exclusionDeadline
        { try await Task.sleep(nanoseconds: 50_000_000) }
        try require(
            (ui.editor["excludedEventIds"] as? [String] ?? []).contains(eventID),
            "native event exclusion")

        let isolated = try await editorApp.engine.call(
            "return document.querySelector('input,button,a,iframe,svg,canvas') === null && !window.webkit?.messageHandlers?.wapacal"
        )
        try require(isolated as? Bool == true, "worker contains no interface or message bridge")
        let blocked = try await editorApp.engine.call(
            "try { await fetch('https://example.invalid/'); return false; } catch { return true; }")
        try require(blocked as? Bool == true, "worker network denied")
        let before = ui.editor
        var rejected = false
        do {
            _ = try await editorApp.js(
                "return window.nativeUpdate(patch)",
                ["patch": ["start": "2026-11-20", "end": "2026-09-01"]])
        } catch { rejected = true }
        try require(
            rejected && ui.editor["start"] as? String == before["start"] as? String,
            "invalid range retention")
        rejected = false
        do {
            _ = try await editorApp.js(
                "return window.nativeFeed(ics,date)",
                ["ics": "invalid ICS", "date": "2026-09-08T12:00:00Z"])
        } catch { rejected = true }
        try require(rejected && ui.events.count > 0, "invalid feed retention")

        let pair = try await editorApp.js("return await window.nativePair()") as! [String: Any]
        let light = Data(base64Encoded: pair["light"] as! String)!
        let dark = Data(base64Encoded: pair["dark"] as! String)!
        try require(light != dark, "different appearance pixels")
        let lightImage = try loadImage(light), darkImage = try loadImage(dark)
        try require(lightImage.width == 2880 && lightImage.height == 1800, "PNG dimensions")
        let output = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["WAPACAL_UI_OUTPUT"]!,
            isDirectory: true)
        try light.write(to: output.appendingPathComponent("worker-light.png"))
        try dark.write(to: output.appendingPathComponent("worker-dark.png"))
        try encodePair(
            light: lightImage, dark: darkImage, to: output.appendingPathComponent("worker.heic"))
        let info = try inspectData(Data(contentsOf: output.appendingPathComponent("worker.heic")))
        try require(
            info.frameCount == 2 && info.width == 2880 && info.darkIndex == 1, "HEIC export")

        editorApp.openExportFile(output.appendingPathComponent("worker.heic").path)
        try require(
            importer.window?.isVisible == true && importer.lightView.image != nil
                && importer.darkView.image != nil, "valid import opens populated preview")
        try require(NSApp.mainMenu === mainMenu, "import retains application menus")
        editorApp.window.performClose(nil)
        try require(
            NSApp.activationPolicy() == .regular && importer.window.isVisible,
            "import preview remains active after editor closes")
        importer.window.performClose(nil)
        try require(
            NSApp.activationPolicy() == .accessory, "closing final preview leaves menu bar app")
        editorApp.openExportFile(output.appendingPathComponent("worker.heic").path)
        try require(
            importer.window.isVisible && NSApp.mainMenu === mainMenu,
            "reopen existing import preview")
        editorApp.show()
        importer.window.performClose(nil)

        for (tab, file) in [
            ("preview", "native-preview"), ("events", "native-events"),
            ("suggestions", "native-suggestions"),
        ] {
            ui.tabs.selectTabViewItem(withIdentifier: tab)
            editorApp.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            let root = editorApp.window.contentView!
            let image = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent(file + ".png"))
            try require(!descendants(root).contains { $0 is WKWebView }, "web content in \(tab)")
        }
        // Minimum-size layout keeps controls accessible and the content area usable.
        editorApp.window.setContentSize(NSSize(width: 1060, height: 698))
        editorApp.window.contentView?.layoutSubtreeIfNeeded()
        try require(ui.tabs.frame.width > 700, "minimum-width tabs")
        try require(ui.preview.frame.width > 650, "minimum-width preview")
        // Suggestions remain editable and require a native button action.
        let buttons = descendants(ui.tabs.selectedTabViewItem!.view!).compactMap { $0 as? NSButton }
        try require(buttons.contains { $0.title == "Use module" }, "native suggestion button")
        buttons.first { $0.title == "Use module" }!.performClick(nil)
        let suggestionDeadline = Date().addingTimeInterval(15)
        while ui.editor["name"] as? String == "Prototype module" && Date() < suggestionDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(ui.editor["name"] as? String != "Prototype module", "accept suggestion")
        try require(
            (ui.editor["excludedEventIds"] as? [String] ?? []).contains(eventID),
            "suggestion preserves exclusions")
        editorApp.persist()
        let persisted =
            try JSONSerialization.jsonObject(with: Data(contentsOf: editorApp.stateURL))
            as! [String: Any]
        try require(
            (persisted["editor"] as? [String: Any])?["futureSetting"] as? String == "kept",
            "unknown field persists")
        _ = try await editorApp.js("return window.nativeLoad(payload)", ["payload": persisted])
        try require(
            (ui.editor["excludedEventIds"] as? [String] ?? []).contains(eventID), "reopen state")
        _ = try await editorApp.js("return window.nativeReset()")
        try require(
            ui.table.numberOfRows == 0 && ui.name.stringValue == "New module", "native reset")
        editorApp.window.performClose(nil)
        try require(!editorApp.window.isVisible, "close window")
        editorApp.show()
        try require(editorApp.window.isVisible, "menu bar reopen")
        print("Native UI and WebKit integration checks passed")
        application.terminate(nil)
    } catch {
        fputs(error.localizedDescription + "\n", stderr)
        exit(1)
    }
}
application.run()
