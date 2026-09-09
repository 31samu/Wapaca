# Development

See the [README](../README.md) for prerequisites and the standard build. The [architecture guide](native-interface.md) describes the native interface, shared renderer, storage, and tests.

## Private calendar builds

To embed your own subscriptions and cached events for development, copy `config.example.json` to `config.local.json`. Add these fields to the configuration, replacing the example URLs:

```json
"subscriptions": [
  {"id": "schedule", "name": "TimeEdit", "url": "https://example.com/schedule.ics", "kind": "timeedit"},
  {"id": "deadlines", "name": "Moodle", "url": "https://example.com/calendar/export", "kind": "generic"}
],
"allCalendars": true
```

Then run:

```sh
npm run refresh
npm run build:native:private
```

This replaces `output/Wapacal.app` with a build containing private calendar data. Do not share it. Run `npm run build:native` to replace it with an empty build. Existing app settings take precedence over bundled seed data.

`allCalendars` shows every feed by default; `course` controls course filtering and TimeEdit module suggestions. Private builds also support legacy `subscriptionUrl`, the `CALENDAR_URL` override, and `data/calendar.ics` snapshots. Missing snapshots are allowed; subscriptions can refresh after launch.

Local configuration, downloaded feeds, and generated output are excluded from Git. The standard native build ignores private configuration, snapshots, and `CALENDAR_URL`.

## Browser preview

After configuring and refreshing subscriptions, run `npm run build` and open `output/preview.html` in Firefox. The build generates SVGs, light/dark PNGs, normalized events, validation reports, and `module-appearance.json`. It does not refresh feeds automatically. Set `WAPACAL_TODAY=YYYY-MM-DD` for a reproducible date marker.

The preview is a separate development tool and is not bundled with the Mac app. Browser preferences are separate from native settings. Browser HEIC export produces a `.wapacal` transfer file that the native app can import. Sharp and browser rendering can differ slightly in typography.

## Formatting and tests

Run `npm run format` to format JavaScript, HTML, JSON, and Swift, or `npm run format:check` to check them. Prettier and `xcrun swift-format` use the checked-in configuration files.

After `npm run build:native`, run `npm run test:all`. Native UI and HEIC tests require a logged-in macOS graphical session. The suites use fictional fixtures and isolated app storage. Individual test commands are listed in [package.json](../package.json).

[GitHub Actions](../.github/workflows/checks.yml) installs dependencies, checks formatting, builds an empty app, and runs all tests. Its workflow file defines the runner and tool versions.

## Command-line tools

The built executable supports:

```sh
"output/Wapacal.app/Contents/MacOS/Wapacal" encode LIGHT.png DARK.png OUTPUT.heic
"output/Wapacal.app/Contents/MacOS/Wapacal" import EXPORT.wapacal OUTPUT.heic
"output/Wapacal.app/Contents/MacOS/Wapacal" inspect OUTPUT.heic [EXTRACT_DIRECTORY]
"output/Wapacal.app/Contents/MacOS/Wapacal" status
```

The app also opens paired HEIC wallpapers, `.wapacal` exports, and legacy `.timetable` files through **File → Open wallpaper** or Finder.
