# Native interface architecture

Wapacal's application interface is AppKit. Its window contains native controls, a raster image preview, an event table with selectable plain-text details, and editable module suggestions. Save and open dialogs, errors, menus, the menu bar item, and the wallpaper import window are also native.

`CalendarEngine` privately owns a detached `WKWebView`. It never exposes that view or adds it to a window, responder chain, or accessibility hierarchy. The worker loads only `calendar-worker.html`, which contains bundled parsing and rendering code and no interface. The app bundle does not contain `preview.html` or the old `editor.html`.

The main window keeps schedule editing beside Preview, Choose events, and Suggested modules. Appearance options expand in the sidebar; the top row provides the display selector, Refresh, Settings, Export, and Apply. Snapshot details remain available in the event-count label's tooltip.

Settings opens in a separate reusable window with Calendars and General tabs. It uses the existing subscription and preference controls, preserving their actions and saved keys. Both windows show the same operation status. Command-comma opens Settings, Command-W closes the key window, and the app stays in the Dock while either window is visible. The import preview also keeps the app in the Dock while visible. Closing the last window keeps the menu bar app running.

The menu bar item offers Open Wapacal, Settings, Refresh calendars, and Quit. File → Open wallpaper opens a file picker without creating an empty preview. The importer builds and shows its window only after successfully validating and decoding a wallpaper, and leaves the editor's main menu intact. Finder imports use the same path; older transfer formats remain supported.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| `native/EditorView.swift` | AppKit presentation, native input, date pickers, event inclusion controls, full event details, suggestion drafts, image preview |
| `native/Editor.swift` | Application lifecycle, Settings window, subscriptions and URLSession, persistence, command sequencing, refresh and automatic application, native export sheets |
| `native/CalendarEngine.swift` | Serialized calls to the private worker, load and operation timeouts, navigation restriction, worker failure reporting |
| `src/native-editor.js` | Calendar and editor transactions, serializable snapshots, day rollover, suggestions, PNG and paired image rendering |
| `src/calendar.mjs`, `src/layout.mjs`, `src/suggestions.mjs` | Shared parser, wallpaper layout and module heuristics, also used by development tools |
| `native/Wallpaper.swift` | ImageIO HEIC encoding and validation, desktop application/restoration, recovery records, legacy imports and CLI |

## Data flow

1. AppKit loads `app-state.json`, falling back to the development seed only when that file does not exist. Existing legacy workspace and single-subscription migration runs as before. An unreadable state file is retained and writes are disabled until an explicit reset.
2. Swift passes cached subscriptions and editor settings to the worker as structured JavaScript arguments. Strings are never interpolated into executable code. The worker validates the selected layout before committing a replacement.
3. A native control submits a settings patch or an event ID and inclusion flag. A successful transaction returns editor settings, visible event candidates, warnings, suggestions, and PNG bytes. Swift displays these using AppKit and saves the settings dictionary atomically.
4. URLSession fetches each feed independently. A rejected feed keeps its prior snapshot; valid feeds can still update. Subscription changes use the worker's current editor state, so they cannot overwrite queued edits with an older settings copy.
5. Export and Apply wait for pending native edits. Paired exports capture both SVG strings before asynchronous rasterization. A change during rendering cannot mix appearances from different calendars. Swift writes PNGs or encodes the pair with ImageIO.
6. Reset invalidates operations from the old data generation. Quit waits for pending editor transactions and saves their results before terminating.

The worker uses a nonpersistent website data store, disables inspection and popup creation, and restricts navigation to its bundled file. Its content security policy denies network connections, frames, forms, and external assets. PNG creation uses a detached canvas, never a DOM preview. No JavaScript message handlers, HTML controls, browser local storage, or browser download links are part of the application.

Calls run in order across asynchronous image rendering. Startup and calls have 30-second timeouts. A terminated or timed-out worker disables editor operations and reports a native error; reopening the app starts a fresh worker. No web fallback window is available.

## Compatibility

The bundle identifier, Application Support location, editor field names, subscription IDs, event IDs, HTTP validators, selected display, refresh intervals, and recovery-file formats remain unchanged. Unknown editor fields are retained. Existing exclusions, custom image dimensions, fixed modules, historical months, and following-current-month behavior remain supported. The parser and wallpaper renderer are unchanged, including their existing ICS limitations and weekday-only layout.

Both `.wapacal` and legacy `.timetable` imports, paired HEIC files, the existing CLI commands, and appearance mapping remain supported. The minimum deployment target is macOS 13; actual GUI execution is tested on the development Mac, not on every supported macOS release.

The browser preview remains a separate development and compatibility tool. It is neither bundled nor opened by the app. Its browser-local preferences remain separate from the app's existing saved state.

## Verification

`npm run build:native` compiles and signs the app without requiring a generated browser preview. `npm run test:all` runs parser, layout, subscriptions, browser compatibility, worker, HEIC/storage, and native UI integration tests.

`test/native-ui.mjs` compiles a temporary application from the production Swift sources and uses the bundled production worker with fictional cached feeds and an isolated Application Support directory. It exercises native target/action controls, validates image dimensions and paired HEIC data, rejects invalid edits and feeds, checks persistence, accepts suggestions, tests reset and close/reopen, and asserts that each tab contains no WebKit view. It also checks normal/minimum window geometry, Settings control ownership and persistence, shared status messages, appearance disclosure, export choices, and closing/reopening both windows. The tests never apply wallpaper or register login items.

The AppKit and HEIC suites require a logged-in macOS graphical session with access to WindowServer and ImageIO. Restricted execution sandboxes can prevent these services from working. Full login, wake, inactive Spaces, external displays, and reconnecting monitors still need live lifecycle testing.
