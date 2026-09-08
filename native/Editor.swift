import WebKit
import ServiceManagement
import CryptoKit

func savedRefreshInterval(_ value: Double?) -> TimeInterval {
    let choices: Set<Double> = [900, 1800, 3600, 10800, 21600, 43200, 86400]
    return value.flatMap { choices.contains($0) ? $0 : nil } ?? 3600
}

final class EditorApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var item: NSStatusItem!
    let status = NSTextField(wrappingLabelWithString: "Loading your calendar…")
    let urlField = NSTextField()
    let sourcePicker = NSPopUpButton()
    let sourceName = NSTextField()
    let saveSourceButton = NSButton(title:"Save & refresh",target:nil,action:nil)
    let refreshPicker = NSPopUpButton()
    let screenPicker = NSPopUpButton()
    let automatic = NSButton(checkboxWithTitle: "Update automatically while running", target: nil, action: nil)
    let login = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
    var saved: [String: Any] = [:]
    var companion: WallpaperApp?
    var pendingFiles: [String] = []
    var ready = false
    var fetching = false
    var refreshFailure: String?
    var rendering = false
    var rerender = false
    var dataGeneration = 0
    var timer: Timer?
    var saveTimer: Timer?
    var session = URLSession(configuration: .ephemeral)
    var stateURL: URL { stateDirectory().appendingPathComponent("app-state.json") }
    var nextCheck: Date { Date(timeIntervalSince1970: saved["nextCheck"] as? Double ?? 0) }
    var refreshInterval: TimeInterval { savedRefreshInterval(saved["refreshInterval"] as? Double) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try migrateLegacyWorkspace() }
        catch { status.stringValue = "Could not migrate older app data. The original files were kept. \(error.localizedDescription)" }
        do {
            let seed = Bundle.main.url(forResource: "seed", withExtension: "json")!
            saved = try JSONSerialization.jsonObject(with: Data(contentsOf: FileManager.default.fileExists(atPath: stateURL.path) ? stateURL : seed)) as? [String:Any] ?? [:]
        } catch { status.stringValue = "Could not load saved settings. \(error.localizedDescription)" }
        if saved["subscriptions"] == nil {
            if let url = saved["subscriptionUrl"] as? String, !url.isEmpty {
                var source: [String:Any] = ["id":"legacy", "name":"TimeEdit", "url":url, "kind":"auto", "legacyIds":true]
                for key in ["ics", "fetchedAt", "etag", "modified"] { source[key] = saved[key] }
                saved["subscriptions"] = [source]
            } else { saved["subscriptions"] = [] as [[String:Any]] }
            for key in ["subscriptionUrl", "ics", "etag", "modified"] { saved.removeValue(forKey:key) }
        }
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let sub = NSMenu(); sub.addItem(withTitle: "Quit Wapacal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = sub; NSApp.mainMenu = menu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName:"calendar",accessibilityDescription:"Wapacal")
        let tray = NSMenu()
        for (title, action) in [("Open Wapacal", #selector(show)), ("Refresh calendar", #selector(refreshNow)), ("Open exported wallpaper…", #selector(openExport)), ("Apply wallpaper", #selector(applyNow)), ("Restore previous wallpaper", #selector(restore)), ("Reset application data…", #selector(resetData)), ("Quit", #selector(NSApplication.terminate(_:)))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = title == "Quit" ? NSApp : self; tray.addItem(entry)
        }
        item.menu = tray
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1200,height:850),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Wapacal"; window.center(); window.isReleasedWhenClosed = false; window.minSize = NSSize(width:900,height:650); window.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 10; root.edgeInsets = NSEdgeInsets(top:12,left:12,bottom:12,right:12)
        let source = NSStackView(); source.orientation = .horizontal
        sourcePicker.target = self; sourcePicker.action = #selector(selectSource)
        sourcePicker.widthAnchor.constraint(equalToConstant:160).isActive = true
        sourceName.placeholderString = "Calendar name"
        sourceName.widthAnchor.constraint(equalToConstant:130).isActive = true
        urlField.placeholderString = "HTTPS calendar subscription URL"
        source.addArrangedSubview(sourcePicker); source.addArrangedSubview(sourceName); source.addArrangedSubview(urlField)
        source.addArrangedSubview(NSButton(title:"New calendar",target:self,action:#selector(addSource)))
        source.addArrangedSubview(NSButton(title:"Remove",target:self,action:#selector(removeSource)))
        reloadSources()
        let frequency = NSStackView(); frequency.orientation = .horizontal
        frequency.addArrangedSubview(NSTextField(labelWithString:"Refresh every"))
        for (title, seconds) in [("15 minutes",900.0),("30 minutes",1800.0),("1 hour",3600.0),("3 hours",10800.0),("6 hours",21600.0),("12 hours",43200.0),("24 hours",86400.0)] {
            refreshPicker.addItem(withTitle:title); refreshPicker.lastItem?.representedObject = seconds
        }
        refreshPicker.selectItem(at: refreshPicker.itemArray.firstIndex(where:{($0.representedObject as? Double)==refreshInterval}) ?? 2)
        refreshPicker.target = self; refreshPicker.action = #selector(changeRefreshInterval)
        frequency.addArrangedSubview(refreshPicker)
        saveSourceButton.target = self; saveSourceButton.action = #selector(saveSource)
        source.addArrangedSubview(saveSourceButton)
        root.addArrangedSubview(source); root.addArrangedSubview(frequency)
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 10
        controls.addArrangedSubview(screenPicker)
        controls.addArrangedSubview(NSButton(title:"Apply wallpaper",target:self,action:#selector(applyNow)))
        controls.addArrangedSubview(NSButton(title:"Restore previous",target:self,action:#selector(restore)))
        controls.addArrangedSubview(NSButton(title:"Reset data…",target:self,action:#selector(resetData)))
        automatic.target = self; automatic.action = #selector(toggleUpdates); automatic.state = saved["autoApply"] as? Bool == true ? .on : .off
        controls.addArrangedSubview(automatic)
        login.target = self; login.action = #selector(toggleLogin); login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        controls.addArrangedSubview(login); root.addArrangedSubview(controls)
        status.font = .systemFont(ofSize:12); root.addArrangedSubview(status)
        let config = WKWebViewConfiguration(); config.userContentController.add(self,name:"wapacal")
        web = WKWebView(frame:.zero,configuration:config); web.navigationDelegate = self
        root.addArrangedSubview(web); window.contentView = root
        for view in [source,frequency,controls,status,web!] { view.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-24).isActive = true }
        screenPicker.target = self; screenPicker.action = #selector(changeScreen)
        updateScreens()
        NotificationCenter.default.addObserver(self,selector:#selector(updateScreens),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(tick),name:NSWorkspace.didWakeNotification,object:nil)
        let file = Bundle.main.url(forResource:"editor",withExtension:"html")!
        web.loadFileURL(file,allowingReadAccessTo:file.deletingLastPathComponent())
        timer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in self?.tick() }
        show()
        for file in pendingFiles { openExportFile(file) }; pendingFiles.removeAll()
    }
    func getCompanion() -> WallpaperApp {
        if let companion { return companion }
        let controller = WallpaperApp(); controller.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification)); companion = controller
        return controller
    }
    @objc func openExport() { getCompanion().openFile() }
    func openExportFile(_ path:String) { getCompanion().openURL(URL(fileURLWithPath:path)) }
    func application(_ sender:NSApplication,openFiles filenames:[String]) {
        if window == nil { pendingFiles.append(contentsOf:filenames) }
        else { for file in filenames { openExportFile(file) } }
        sender.reply(toOpenOrPrint:.success)
    }
    @objc func show() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func persist() {
        do { try ensureWorkspaceDirectories(); try JSONSerialization.data(withJSONObject:saved,options:[.sortedKeys]).write(to:stateURL,options:.atomic) }
        catch { status.stringValue = "Settings could not be saved. \(error.localizedDescription)" }
    }
    @objc func updateScreens() {
        let previous = saved["screen"] as? String
        let wasConnected = screenPicker.itemArray.contains { ($0.representedObject as? String) == previous }
        screenPicker.removeAllItems()
        for screen in NSScreen.screens { screenPicker.addItem(withTitle:screen.localizedName); screenPicker.lastItem?.representedObject = screenID(screen) }
        if let index = NSScreen.screens.firstIndex(where:{screenID($0) == previous}) { screenPicker.selectItem(at:index) }
        else if previous != nil { screenPicker.select(nil) }
        if ready, previous != nil, !wasConnected, screenPicker.selectedItem != nil {
            saved.removeValue(forKey:"lastHash"); persist()
            if automatic.state == .on { applyNow() }
        }
    }
    @objc func changeScreen() { saved["screen"] = screenPicker.selectedItem?.representedObject as? String; saved.removeValue(forKey:"lastHash"); persist() }
    @objc func changeRefreshInterval() {
        saved["refreshInterval"] = refreshPicker.selectedItem?.representedObject as? Double ?? 3600
        saved["nextCheck"] = Date().addingTimeInterval(refreshInterval).timeIntervalSince1970
        persist()
        status.stringValue = "Refresh frequency saved. Next check \(nextCheck.formatted(date:.omitted,time:.shortened))."
    }
    func targetScreen() throws -> NSScreen {
        guard let id = screenPicker.selectedItem?.representedObject as? String, let screen = NSScreen.screens.first(where:{screenID($0)==id}) else { throw WallpaperError.invalid("Choose a connected display.") }
        return screen
    }
    func js(_ body:String, _ arguments:[String:Any] = [:]) async throws -> Any {
        try await web.callAsyncJavaScript(body,arguments:arguments,in:nil,contentWorld:.page) ?? NSNull()
    }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String:Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            Task { @MainActor in
                do { _ = try await js("window.nativeLoad(payload); return true",["payload":saved]); ready = true; status.stringValue = "Saved calendar loaded. Your edits are saved automatically."; tick() }
                catch { status.stringValue = "Could not load the calendar. \(error.localizedDescription)" }
            }
        case "settings":
            guard let editor = body["editor"] as? [String:Any] else { return }
            saved["editor"] = editor
            saveTimer?.invalidate(); saveTimer = Timer.scheduledTimer(withTimeInterval:0.4,repeats:false) { [weak self] _ in self?.persist(); if self?.ready == true && self?.automatic.state == .on { Task { @MainActor in await self?.makeAndApply(force:false) } } }
        case "apply":
            guard let pair = body["pair"] as? [String:Any] else { return }
            Task { @MainActor in do { try install(pair,force:true) } catch { status.stringValue = error.localizedDescription } }
        case "export":
            guard let ext = body["extension"] as? String, ext == "png", let encoded = body["base64"] as? String, let bytes = Data(base64Encoded:encoded) else { return }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "wapacal.\(ext)"
            if panel.runModal() == .OK, let url = panel.url { do { try bytes.write(to:url,options:.atomic); status.stringValue = "Export saved." } catch { status.stringValue = error.localizedDescription } }
        case "exportHeic":
            guard let pair = body["pair"] as? [String:Any] else { return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.heic]; panel.nameFieldStringValue = "wapacal.heic"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject:pair)
                let parsed = try JSONDecoder().decode(PairExport.self,from:data)
                guard let light = Data(base64Encoded:parsed.light), let dark = Data(base64Encoded:parsed.dark) else { throw WallpaperError.invalid("Could not render both appearances.") }
                try encodePair(light:loadImage(light),dark:loadImage(dark),to:url)
                status.stringValue = "HEIC saved with light and dark appearances."
            } catch { status.stringValue = "HEIC export failed. \(error.localizedDescription)" }
        default: break
        }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        decisionHandler(navigationAction.request.url?.standardizedFileURL == Bundle.main.url(forResource:"editor",withExtension:"html")?.standardizedFileURL ? .allow : .cancel)
    }
    var subscriptions: [[String:Any]] { saved["subscriptions"] as? [[String:Any]] ?? [] }
    func reloadSources(selected: String? = nil) {
        sourcePicker.removeAllItems()
        for source in subscriptions {
            let item = NSMenuItem(title:source["name"] as? String ?? "Calendar",action:nil,keyEquivalent:"")
            item.representedObject = source["id"]; sourcePicker.menu?.addItem(item)
        }
        if let selected, let index = subscriptions.firstIndex(where: { $0["id"] as? String == selected }) { sourcePicker.selectItem(at:index) }
        selectSource()
    }
    @objc func selectSource() {
        let index = sourcePicker.indexOfSelectedItem
        let source = subscriptions.indices.contains(index) ? subscriptions[index] : [:]
        urlField.stringValue = source["url"] as? String ?? ""
        sourceName.stringValue = source["name"] as? String ?? ""
        saveSourceButton.title = source.isEmpty ? "Add & refresh" : "Save & refresh"
        if ready && !fetching {
            status.stringValue = refreshFailure ?? (source.isEmpty ? "Enter a name and subscription URL, then choose Add & refresh." : "Editing \(sourceName.stringValue). Choose Save & refresh to save changes.")
        }
    }
    @objc func addSource() {
        let index = sourcePicker.indexOfSelectedItem
        if subscriptions.indices.contains(index) {
            let source = subscriptions[index]
            // Keep a new URL typed before starting the new-calendar entry.
            if urlField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines) == source["url"] as? String {
                urlField.stringValue = ""
            }
            if sourceName.stringValue == source["name"] as? String { sourceName.stringValue = "" }
            sourcePicker.select(nil)
        }
        saveSourceButton.title = "Add & refresh"
        window.makeFirstResponder(urlField)
        status.stringValue = "Enter a name and subscription URL, then choose Add & refresh."
    }
    @objc func removeSource() {
        guard ready, !fetching else { status.stringValue = "Wait for the current refresh to finish."; return }
        let index = sourcePicker.indexOfSelectedItem
        guard subscriptions.indices.contains(index) else { return }
        var sources = subscriptions; sources.remove(at:index)
        fetching = true
        Task { @MainActor in
            defer { fetching = false }
            do {
                _ = try await js("return window.nativeCalendars(subscriptions,fetchedAt)", ["subscriptions":sources,"fetchedAt":ISO8601DateFormatter().string(from:Date())])
                saved["subscriptions"] = sources; persist(); reloadSources()
                status.stringValue = "Calendar removed."
                if automatic.state == .on { await makeAndApply(force:false) }
            } catch { status.stringValue = "Could not remove calendar. \(error.localizedDescription)" }
        }
    }
    @objc func saveSource() {
        let value = urlField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let url = URL(string:value), url.scheme == "https", let host = url.host else { status.stringValue = "Enter an HTTPS calendar subscription URL."; return }
        guard ready, !fetching else { status.stringValue = "Wait for the current refresh to finish before changing subscriptions."; return }
        let index = sourcePicker.indexOfSelectedItem
        var sources = subscriptions
        guard !sources.enumerated().contains(where: { $0.offset != index && $0.element["url"] as? String == value }) else { status.stringValue = "That calendar is already subscribed."; return }
        let adding = !sources.indices.contains(index)
        var source: [String:Any] = adding ? ["id":UUID().uuidString] : sources[index]
        if source["url"] as? String != value {
            source.removeValue(forKey:"etag"); source.removeValue(forKey:"modified")
        }
        let name = sourceName.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        source["url"] = value; source["name"] = name.isEmpty ? host : name
        source["kind"] = host == "timeedit.net" || host.hasSuffix(".timeedit.net") ? "timeedit" : "generic"
        if adding { sources.append(source) } else { sources[index] = source }
        saved["subscriptions"] = sources; saved["nextCheck"] = 0.0
        if adding {
            var editor = saved["editor"] as? [String:Any] ?? [:]; editor["course"] = ""; saved["editor"] = editor
        }
        persist(); reloadSources(selected:source["id"] as? String)
        Task { @MainActor in
            do { _ = try await js("window.nativeLoad(payload); return true",["payload":saved]); refreshNow() }
            catch { status.stringValue = "Could not load subscriptions. \(error.localizedDescription)" }
        }
    }
    @objc func toggleUpdates() { saved["autoApply"] = automatic.state == .on; persist(); if automatic.state == .on { applyNow() } }
    @objc func toggleLogin() {
        do {
            if login.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            status.stringValue = SMAppService.mainApp.status == .requiresApproval ? "Allow Wapacal under System Settings → Login Items." : "Login preference saved."
        } catch { status.stringValue = "Could not update login preference. \(error.localizedDescription)" }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc func tick() {
        guard ready else { return }
        Task { @MainActor in
            do { let changed = try await js("return window.nativeDay()"); if changed as? Bool == true && automatic.state == .on { applyNow() } } catch { status.stringValue = error.localizedDescription }
        }
        if nextCheck <= Date() { beginRefresh(force:false) }
    }
    @objc func refreshNow() { beginRefresh(force:true) }
    func beginRefresh(force:Bool) {
        guard ready, !fetching else { return }
        guard force || nextCheck <= Date() else { return }
        guard !subscriptions.isEmpty else { status.stringValue = "Add a calendar subscription to refresh."; return }
        fetching = true; refreshFailure = nil; status.stringValue = "Checking calendars…"
        let generation = dataGeneration
        Task { @MainActor in
            defer { if generation == dataGeneration { fetching = false } }
            var sources = subscriptions
            var failures: [String] = []
            for index in sources.indices {
                guard generation == dataGeneration else { return }
                let source = sources[index]
                do {
                    guard let value = source["url"] as? String, let url = URL(string:value), url.scheme == "https", url.host != nil else { throw WallpaperError.invalid("Invalid subscription URL.") }
                    var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30)
                    if source["ics"] != nil {
                        request.setValue(source["etag"] as? String,forHTTPHeaderField:"If-None-Match")
                        request.setValue(source["modified"] as? String,forHTTPHeaderField:"If-Modified-Since")
                    }
                    let (data,response) = try await session.data(for:request)
                    guard generation == dataGeneration else { return }
                    guard let http = response as? HTTPURLResponse else { throw WallpaperError.invalid("Invalid response.") }
                    let now = ISO8601DateFormatter().string(from:Date())
                    if http.statusCode == 200 {
                        guard data.count <= 10_000_000, let ics = String(data:data,encoding:.utf8) else { throw WallpaperError.invalid("Calendar is too large or unreadable.") }
                        var candidate = source
                        candidate["ics"] = ics; candidate["fetchedAt"] = now
                        candidate["etag"] = http.value(forHTTPHeaderField:"ETag"); candidate["modified"] = http.value(forHTTPHeaderField:"Last-Modified")
                        var next = sources; next[index] = candidate
                        _ = try await js("return window.nativeCalendars(subscriptions,fetchedAt)",["subscriptions":next,"fetchedAt":now])
                        guard generation == dataGeneration else { return }
                        sources = next
                    } else if http.statusCode != 304 || source["ics"] == nil {
                        throw WallpaperError.invalid("HTTP \(http.statusCode).")
                    }
                    sources[index]["checkedAt"] = now
                } catch {
                    guard generation == dataGeneration else { return }
                    let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    failures.append("\(source["name"] as? String ?? "Calendar"): \(detail)")
                }
            }
            saved["subscriptions"] = sources
            saved["nextCheck"] = Date().addingTimeInterval(failures.isEmpty ? refreshInterval : 300).timeIntervalSince1970
            persist()
            refreshFailure = failures.isEmpty ? nil : "Refresh failed. \(failures.joined(separator:" ")) Saved events were kept. Retrying in 5 minutes."
            if automatic.state == .on { await makeAndApply(force:false) }
            status.stringValue = refreshFailure ?? "\(sources.count) calendars checked at \(Date().formatted(date:.omitted,time:.shortened))."
        }
    }
    @objc func applyNow() { Task { @MainActor in await makeAndApply(force:true) } }
    func makeAndApply(force:Bool) async {
        guard ready else { return }
        if rendering { rerender = true; return }
        rendering = true
        defer {
            rendering = false
            if rerender { rerender = false; Task { @MainActor in await makeAndApply(force:false) } }
        }
        do { guard let pair = try await js("return await window.nativePair()") as? [String:Any] else { throw WallpaperError.invalid("Could not render the wallpaper.") }; try install(pair,force:force) }
        catch { status.stringValue = "Wallpaper kept. \(error.localizedDescription)" }
    }
    func install(_ pair:[String:Any],force:Bool) throws {
        let data = try JSONSerialization.data(withJSONObject:pair,options:[.sortedKeys])
        let digest = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        let screen = try targetScreen()
        if !force && saved["lastHash"] as? String == digest && saved["screen"] as? String == screenID(screen) { return }
        let parsed = try JSONDecoder().decode(PairExport.self,from:data)
        guard let light = Data(base64Encoded:parsed.light),let dark = Data(base64Encoded:parsed.dark) else { throw WallpaperError.invalid("Could not render both appearances.") }
        let file = wallpapersDirectory().appendingPathComponent("editor-wallpaper.heic")
        try encodePair(light:loadImage(light),dark:loadImage(dark),to:file)
        let restorable = try applyWallpaper(file,screen:screen)
        saved["screen"] = screenID(screen); saved["lastHash"] = digest; persist()
        status.stringValue = refreshFailure ?? (restorable ? "Wallpaper applied. macOS switches between light and dark." : "Wallpaper applied. The previous wallpaper file is unavailable for restoration.")
    }
    @objc func restore() {
        do { try restoreWallpaper(screen:targetScreen()); automatic.state = .off; saved["autoApply"] = false; saved.removeValue(forKey:"lastHash"); persist(); status.stringValue = "Previous wallpaper restored. Automatic updates paused." }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc func resetData() {
        let alert = NSAlert()
        alert.messageText = "Reset Wapacal data?"
        alert.informativeText = "This removes the saved subscriptions, cached calendars, editor settings, and inactive generated wallpapers. Active wallpaper files and recovery records are kept so your desktop can still be restored."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset data")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            saveTimer?.invalidate()
            dataGeneration += 1; fetching = false; refreshFailure = nil
            session.invalidateAndCancel(); session = URLSession(configuration: .ephemeral)
            try? SMAppService.mainApp.unregister()
            automatic.state = .off; login.state = .off
            try resetInactiveRuntimeData()
            saved = ["subscriptions": [] as [[String:Any]], "courseCode": "", "refreshInterval": 3600.0, "nextCheck": 0.0]
            reloadSources()
            refreshPicker.selectItem(at: 2)
            persist()
            if ready {
                Task { @MainActor in
                    do { _ = try await js("return window.nativeReset()"); status.stringValue = "Application data reset. Active wallpaper recovery was kept." }
                    catch { status.stringValue = "Data reset, but the editor could not refresh. Reopen the app. \(error.localizedDescription)" }
                }
            } else { status.stringValue = "Application data reset. Active wallpaper recovery was kept." }
        } catch { status.stringValue = "Application data could not be reset. \(error.localizedDescription)" }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationWillTerminate(_ notification:Notification) { persist() }
}
