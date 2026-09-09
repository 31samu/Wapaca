import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    let app = NSApplication.shared; let delegate = MainActor.assumeIsolated { EditorApp() }; app.delegate = delegate; app.run()
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
        default: throw WallpaperError.invalid("Commands: encode LIGHT DARK OUTPUT.heic | import EXPORT.wapacal OUTPUT.heic | inspect FILE.heic [EXTRACT_DIRECTORY] | status. Run without arguments for the app.")
        }
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}
