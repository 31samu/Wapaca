import AppKit
import ImageIO
import UniformTypeIdentifiers

enum WallpaperError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

func loadImage(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
          let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
          let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
          width > 0, height > 0, width <= 7680, height <= 4320,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw WallpaperError.invalid("Cannot read this image, or it exceeds 7680 × 4320 pixels.")
    }
    return image
}

func readBounded(_ url: URL) throws -> Data {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 100_000_000 else { throw WallpaperError.invalid("The file exceeds 100 MB.") }
    return try Data(contentsOf: url)
}

// Appearance mapping follows the format documented by wallpapper:
// https://github.com/mczachurski/wallpapper#appearance
// apple_desktop:apr contains a base64 binary plist, with l/d frame indices.
func encodePair(light: CGImage, dark: CGImage, to url: URL) throws {
    guard light.width == dark.width, light.height == dark.height else {
        throw WallpaperError.invalid("Light and dark images must have the same dimensions.")
    }
    let metadata = CGImageMetadataCreateMutable()
    let namespace = "http://ns.apple.com/namespace/1.0/" as CFString
    let mapping = try PropertyListSerialization.data(fromPropertyList: ["l": 0, "d": 1], format: .binary, options: 0).base64EncodedString()
    guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, "apple_desktop" as CFString, nil),
          let tag = CGImageMetadataTagCreate(namespace, "apple_desktop" as CFString, "apr" as CFString, .string, mapping as CFString),
          CGImageMetadataSetTagWithPath(metadata, nil, "apple_desktop:apr" as CFString, tag) else {
        throw WallpaperError.invalid("Could not write the appearance metadata.")
    }
    let buffer = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(buffer, UTType.heic.identifier as CFString, 2, nil) else {
        throw WallpaperError.invalid("HEIC encoding is unavailable on this Mac.")
    }
    let options = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
    CGImageDestinationAddImageAndMetadata(destination, light, metadata, options)
    CGImageDestinationAddImage(destination, dark, options)
    guard CGImageDestinationFinalize(destination) else { throw WallpaperError.invalid("HEIC encoding failed.") }
    _ = try inspectData(buffer as Data)
    try (buffer as Data).write(to: url, options: .atomic)
}

struct HEICInfo: Codable {
    let frameCount: Int
    let width: Int
    let height: Int
    let lightIndex: Int
    let darkIndex: Int
}

func inspectData(_ data: Data) throws -> HEICInfo {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetType(source) as String? == UTType.heic.identifier,
          CGImageSourceGetCount(source) == 2,
          let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
          let encoded = CGImageMetadataCopyStringValueWithPath(metadata, nil, "apple_desktop:apr" as CFString) as String?,
          let plist = Data(base64Encoded: encoded),
          let mapping = try PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Int],
          mapping["l"] == 0, mapping["d"] == 1,
          let light = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let dark = CGImageSourceCreateImageAtIndex(source, 1, nil),
          light.width == dark.width, light.height == dark.height else {
        throw WallpaperError.invalid("Expected a two-image HEIC with light frame 0 and dark frame 1.")
    }
    return HEICInfo(frameCount: 2, width: light.width, height: light.height, lightIndex: 0, darkIndex: 1)
}

struct PairExport: Decodable {
    let version: Int
    let name: String
    let light: String
    let dark: String
}

func importPair(_ url: URL, to destination: URL) throws {
    let pair = try JSONDecoder().decode(PairExport.self, from: readBounded(url))
    guard pair.version == 1, let light = Data(base64Encoded: pair.light), let dark = Data(base64Encoded: pair.dark) else {
        throw WallpaperError.invalid("Invalid timetable export.")
    }
    try encodePair(light: loadImage(light), dark: loadImage(dark), to: destination)
}

func screenID(_ screen: NSScreen) -> String {
    let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() {
        return CFUUIDCreateString(nil, uuid) as String
    }
    return String(number)
}

struct WallpaperBackup: Codable {
    let screen: String
    let url: URL?
    let scaling: Int?
    let clipping: Bool?
    let color: [Double]?
    init(screen: NSScreen) {
        self.init(screenID: screenID(screen), url: NSWorkspace.shared.desktopImageURL(for: screen), options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
    }
    init(screenID: String, url: URL?, options: [NSWorkspace.DesktopImageOptionKey: Any]) {
        self.screen = screenID
        self.url = url
        scaling = (options[.imageScaling] as? NSNumber)?.intValue
        clipping = (options[.allowClipping] as? NSNumber)?.boolValue
        if let c = (options[.fillColor] as? NSColor)?.usingColorSpace(.deviceRGB) {
            color = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
        } else { color = nil }
    }
    var canRestore: Bool {
        Self.canRestore(url)
    }
    static func canRestore(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    var options: [NSWorkspace.DesktopImageOptionKey: Any] {
        var result: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling { result[.imageScaling] = scaling }
        if let clipping { result[.allowClipping] = clipping }
        if let c = color, c.count == 4 { result[.fillColor] = NSColor(deviceRed: c[0], green: c[1], blue: c[2], alpha: c[3]) }
        return result
    }
}

func workspaceDirectory() -> URL {
    if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.bundleURL.deletingLastPathComponent() }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("output")
}

func backupURL(_ screen: NSScreen) -> URL { workspaceDirectory().appendingPathComponent("restore-\(screenID(screen)).json") }

func applyWallpaper(_ url: URL, screen: NSScreen) throws -> Bool {
    let data = try readBounded(url)
    _ = try inspectData(data)
    let backup = backupURL(screen)
    if FileManager.default.fileExists(atPath: backup.path) {
        let previous = try JSONDecoder().decode(WallpaperBackup.self, from: Data(contentsOf: backup))
        if !previous.canRestore && WallpaperBackup(screen: screen).canRestore {
            try FileManager.default.moveItem(at: backup, to: workspaceDirectory().appendingPathComponent("unavailable-\(UUID().uuidString).json"))
        }
    }
    if !FileManager.default.fileExists(atPath: backup.path) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(WallpaperBackup(screen: screen)).write(to: backup, options: .atomic)
    }
    // A new filename prevents macOS reusing a cached render of the previous file.
    let applied = workspaceDirectory().appendingPathComponent("applied")
    try FileManager.default.createDirectory(at: applied, withIntermediateDirectories: true)
    let copy = applied.appendingPathComponent("timetable-\(UUID().uuidString).heic")
    try data.write(to: copy, options: .atomic)
    try NSWorkspace.shared.setDesktopImageURL(copy, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: false])
    let record = try JSONDecoder().decode(WallpaperBackup.self, from: Data(contentsOf: backup))
    return record.canRestore
}

func restoreWallpaper(screen: NSScreen) throws {
    let backup = backupURL(screen)
    let record = try JSONDecoder().decode(WallpaperBackup.self, from: Data(contentsOf: backup))
    guard record.screen == screenID(screen), record.canRestore, let original = record.url else {
        throw WallpaperError.invalid("The previous wallpaper file is unavailable. Choose another wallpaper in System Settings.")
    }
    try NSWorkspace.shared.setDesktopImageURL(original, for: screen, options: record.options)
    // WallpaperAgent applies the request asynchronously, after the API returns.
    let deadline = Date().addingTimeInterval(3)
    while NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL != original.standardizedFileURL && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == original.standardizedFileURL else {
        throw WallpaperError.invalid("macOS did not confirm restoration. The recovery file was retained.")
    }
    let archive = workspaceDirectory().appendingPathComponent("restored-\(UUID().uuidString).json")
    try FileManager.default.moveItem(at: backup, to: archive)
}

final class WallpaperApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let status = NSTextField(wrappingLabelWithString: "Open a paired HEIC or a .timetable export from the preview.")
    let picker = NSPopUpButton(frame: .zero)
    let lightView = NSImageView(); let darkView = NSImageView()
    var applyButton: NSButton!
    var selected: URL?
    var screens: [NSScreen] = []
    var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let submenu = NSMenu(); submenu.addItem(withTitle: "Quit Timetable Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = submenu; NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 510), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Timetable Wallpaper"; window.center(); window.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let title = NSTextField(labelWithString: "One wallpaper. Two appearances."); title.font = .systemFont(ofSize: 24, weight: .medium)
        root.addArrangedSubview(title)
        let previews = NSStackView(); previews.orientation = .horizontal; previews.spacing = 16
        for (label, view) in [("Light", lightView), ("Dark", darkView)] {
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
            view.imageScaling = .scaleProportionallyUpOrDown
            view.widthAnchor.constraint(equalToConstant: 378).isActive = true; view.heightAnchor.constraint(equalToConstant: 246).isActive = true
            stack.addArrangedSubview(NSTextField(labelWithString: label)); stack.addArrangedSubview(view); previews.addArrangedSubview(stack)
        }
        root.addArrangedSubview(previews)
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 10
        controls.addArrangedSubview(NSButton(title: "Open wallpaper or export…", target: self, action: #selector(openFile)))
        controls.addArrangedSubview(picker)
        applyButton = NSButton(title: "Apply wallpaper", target: self, action: #selector(apply)); applyButton.isEnabled = false; controls.addArrangedSubview(applyButton)
        controls.addArrangedSubview(NSButton(title: "Restore previous", target: self, action: #selector(restore)))
        root.addArrangedSubview(controls)
        status.font = .systemFont(ofSize: 12); root.addArrangedSubview(status)
        window.contentView = root
        NotificationCenter.default.addObserver(self, selector: #selector(updateScreens), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updateScreens(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        for url in pendingFiles { openURL(url) }; pendingFiles.removeAll()
    }

    @objc func updateScreens() {
        let old = picker.selectedItem?.representedObject as? String
        screens = NSScreen.screens; picker.removeAllItems()
        for screen in screens { picker.addItem(withTitle: screen.localizedName); picker.lastItem?.representedObject = screenID(screen) }
        if let old, let index = screens.firstIndex(where: {screenID($0) == old}) { picker.selectItem(at: index) }
        applyButton?.isEnabled = selected != nil && !screens.isEmpty
    }
    func targetScreen() throws -> NSScreen {
        guard let id = picker.selectedItem?.representedObject as? String, let screen = NSScreen.screens.first(where: {screenID($0) == id}) else { throw WallpaperError.invalid("The selected display is disconnected.") }
        return screen
    }
    func showError(_ error: Error) { status.stringValue = error.localizedDescription }

    @objc func openFile() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Select a paired HEIC or a .timetable export."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openURL(url)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if window == nil { pendingFiles.append(contentsOf: urls) }
        else { for url in urls { openURL(url) } }
        sender.reply(toOpenOrPrint: .success)
    }
    func openURL(_ url: URL) {
        do {
            var wallpaper = url
            if url.pathExtension.lowercased() != "heic" {
                let save = NSSavePanel(); save.allowedContentTypes = [.heic]; save.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".heic"
                guard save.runModal() == .OK, let destination = save.url else { return }
                try importPair(url, to: destination); wallpaper = destination
            }
            let data = try readBounded(wallpaper); let info = try inspectData(data)
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            lightView.image = NSImage(cgImage: CGImageSourceCreateImageAtIndex(source, 0, nil)!, size: .zero)
            darkView.image = NSImage(cgImage: CGImageSourceCreateImageAtIndex(source, 1, nil)!, size: .zero)
            selected = wallpaper; applyButton.isEnabled = !screens.isEmpty
            status.stringValue = "\(wallpaper.lastPathComponent) · \(info.width) × \(info.height) · Verified light/dark pair."
        } catch { showError(error) }
    }
    @objc func apply() {
        guard let selected else { return }
        do {
            let canRestore = try applyWallpaper(selected, screen: targetScreen())
            status.stringValue = canRestore
                ? "Applied. macOS controls the appearance. Your previous wallpaper is saved for restoration."
                : "Applied. The previous wallpaper file is unavailable, so it cannot be restored by this app."
        } catch { showError(error) }
    }
    @objc func restore() {
        do { try restoreWallpaper(screen: targetScreen()); status.stringValue = "Previous wallpaper and display options restored." } catch { showError(error) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try encoder.encode(value), encoding: .utf8)!)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    let app = NSApplication.shared; let delegate = WallpaperApp(); app.delegate = delegate; app.run()
} else {
    do {
        switch args[0] {
        case "encode" where args.count == 4:
            try encodePair(light: loadImage(readBounded(URL(fileURLWithPath: args[1]))), dark: loadImage(readBounded(URL(fileURLWithPath: args[2]))), to: URL(fileURLWithPath: args[3]))
            try printJSON(inspectData(readBounded(URL(fileURLWithPath: args[3]))))
        case "import" where args.count == 3:
            try importPair(URL(fileURLWithPath: args[1]), to: URL(fileURLWithPath: args[2]))
            try printJSON(inspectData(readBounded(URL(fileURLWithPath: args[2]))))
        case "inspect" where args.count >= 2:
            let data = try readBounded(URL(fileURLWithPath: args[1])); try printJSON(inspectData(data))
            if args.count == 3 {
                let directory = URL(fileURLWithPath: args[2]); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let source = CGImageSourceCreateWithData(data as CFData, nil)!
                for (index, name) in ["light", "dark"].enumerated() {
                    let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
                    CGImageDestinationAddImage(destination, CGImageSourceCreateImageAtIndex(source, index, nil)!, nil)
                    guard CGImageDestinationFinalize(destination) else { throw WallpaperError.invalid("Could not extract frame.") }
                }
            }
        case "status":
            try printJSON(NSScreen.screens.map { ["name": $0.localizedName, "id": screenID($0), "wallpaper": NSWorkspace.shared.desktopImageURL(for: $0)?.absoluteString ?? "", "appearance": NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])?.rawValue ?? "unknown"] })
        default: throw WallpaperError.invalid("Commands: encode LIGHT DARK OUTPUT.heic | import EXPORT.timetable OUTPUT.heic | inspect FILE.heic [EXTRACT_DIRECTORY] | status. Run without arguments for the app.")
        }
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}
