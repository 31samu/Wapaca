# Wapacal

Wapacal is a local calendar-to-wallpaper Mac app with a native AppKit interface. It combines saved ICS subscriptions, including TimeEdit and Moodle, and produces month and module wallpapers in light and dark.

Open `output/Wapacal.app` to manage subscriptions, edit the layout, choose events, review module suggestions, export PNG or paired HEIC images, and apply or restore wallpaper. Every visible part of the app is native. WebKit runs privately as a parser and image renderer, with no visible or interactive web content.

## Build and run

Development requires macOS, Xcode Command Line Tools, and Node.js 22.14 or newer. The built app targets macOS 13 and later and does not require Node.

1. Install dependencies with `npm ci`.
2. Copy `config.example.json` to `config.local.json` and adjust the course, time zone, image dimensions, and initial module dates.
3. Optionally add a `subscriptions` array. Each entry needs a stable `id`, a `name`, and an HTTPS `url`. Set `kind` to `timeedit` or `generic`, or omit it to detect TimeEdit from the hostname.

   ```json
   "subscriptions": [
     {"id": "schedule", "name": "TimeEdit", "url": "https://example.com/schedule.ics", "kind": "timeedit"},
     {"id": "deadlines", "name": "Moodle", "url": "https://example.com/calendar/export", "kind": "generic"}
   ],
   "allCalendars": true
   ```

4. Run `npm run refresh` to fetch configured calendars, then `npm run build:native` and open `output/Wapacal.app`. You can also build without a snapshot and add subscriptions in the app.
5. Run `npm run test:all` after building for the complete test suite. AppKit and ImageIO tests need a logged-in macOS graphical session.

`allCalendars` shows every feed by default. The course filter and TimeEdit suggestions still use `course`. Legacy `subscriptionUrl`, the `CALENDAR_URL` environment override, and `data/calendar.ics` snapshots remain supported. The supplied subscriptions are already in this workspace's ignored `config.local.json`.

Native builds read the configuration and cached feeds directly. They do not require `output/preview.html`. The development bundle includes its seed subscriptions and calendar data, so it is not a generic installer. Local settings, snapshots, and generated outputs are excluded from Git.

## Using the app

- Open **Settings…** with the toolbar button or **⌘,**. In **Calendars**, select a calendar to edit its name or URL, then choose **Save & refresh**. **New calendar** starts a new entry and retains an unfinished URL. **Add & refresh** saves it and switches to all events. **Remove** removes the selected calendar and its events.
- The **Schedule** sidebar contains Module or Month, dates, the module name, and the course filter. Expand **Appearance** for the preview theme, image size, title visibility, rooms, and space for desktop icons. Edits save automatically; text edits finish on Return or when leaving the field.
- Open **Choose events** to include or exclude individual sessions. Select a row for the full title, time, location, description, source, and room-conflict warning. Exclusions affect the wallpaper and both export appearances and survive refreshes, moves, and temporary deletions using stable subscription and event IDs.
- The **Suggested modules** tab shows editable proposals with supporting events and dates. Suggestions use introductions, topic changes, examinations, and schedule gaps from TimeEdit course events, excluding unchecked events and weekends. Only **Use module** changes the active layout. Accepted suggestions follow the automatic wallpaper update preference.
- The **Export** menu offers **PNG** for the selected appearance and **HEIC** for both appearances, each using a native save sheet. **Apply wallpaper** renders a paired HEIC for the selected display. macOS controls light/dark switching after the app quits.
- In **Settings → General**, **Automatically apply wallpaper changes** applies changed output after edits, refreshes, and local date changes. Identical output is skipped. **Restore previous wallpaper** restores the saved wallpaper and display options and pauses automatic wallpaper changes.
- **Settings → General → Check calendars every** offers 15 or 30 minutes, 1, 3, 6, 12, or 24 hours. The toolbar **Refresh** button or **⌘R** checks immediately. The app uses per-feed ETag and Last-Modified validators. Failed feeds keep their last valid snapshots and retry after five minutes; successful feeds can still update.
- **⌘W** closes the focused window. Closing both windows leaves the menu bar app running. Its calendar menu offers Open Wapacal, Settings, Refresh calendars, and Quit. Quit stops background checks. **Settings → General → Open at login** uses macOS Service Management and reports required approval or registration errors.

A once-per-minute timer and wake notifications check whether refresh is due. Day changes update the current-day marker; a month view following the current month advances at rollover. Historical month selections and fixed module dates stay fixed. Escape ends text editing or returns from event/suggestion views to the preview. Native Edit-menu shortcuts support text editing.

## Saved data and compatibility

Settings, cached feeds, selected display, editor fields, and exclusions remain at `~/Library/Application Support/local.wapacal.app/state/app-state.json`. This migration keeps the bundle identity, saved field names, custom image sizes, legacy event IDs, and unknown editor fields. Existing installations retain their saved settings instead of being replaced by the development seed.

First launch copies older runtime files from `local.timetable.wallpaper` or beside the previous app. Each old copy is removed only after its destination succeeds. Active wallpaper files stay in place. Applied wallpaper history is capped at 24 inactive files and archived recovery history at 20 files.

**Reset data…** confirms before clearing subscriptions, editor settings, cached calendars, inactive wallpapers, and archived recovery records. Active wallpaper files and current restore records remain available. An unreadable settings file is preserved until explicit reset. Tests using `WAPACAL_APP_SUPPORT` isolate legacy migration as well as new writes.

**File → Open wallpaper…** or **⌘O** opens paired HEIC wallpapers, `.wapacal` exports, and legacy `.timetable` transfer files. The native import preview appears only after a file is successfully loaded. Canceling the picker leaves the current windows unchanged. Opening supported files from Finder still works. ImageIO validates both HEIC frames and their light/dark mapping before writing. Invalid imports or mismatched image dimensions leave existing files intact. A missing previous wallpaper does not block Apply; the app reports when restoration is unavailable. Restoring arbitrary Apple dynamic/aerial wallpaper configuration is not guaranteed.

The executable retains these commands:

```sh
"output/Wapacal.app/Contents/MacOS/Wapacal" encode LIGHT.png DARK.png OUTPUT.heic
"output/Wapacal.app/Contents/MacOS/Wapacal" import EXPORT.wapacal OUTPUT.heic
"output/Wapacal.app/Contents/MacOS/Wapacal" inspect OUTPUT.heic [EXTRACT_DIRECTORY]
"output/Wapacal.app/Contents/MacOS/Wapacal" status
```

## Calendar behavior

The shared ICAL.js parser unfolds ICS text, uses SUMMARY for generic titles, preserves TimeEdit description titles and room hints, removes trailing display-only TimeEdit IDs, converts UTC times to the configured time zone, and preserves all-day events with exclusive end dates. Cancelled events are omitted. Timed deadlines without an end show a single time. Identical UIDs across subscriptions remain independent.

The parser accepts concrete UTC and date-only events. Recurrence, recurrence exceptions, duplicate UIDs within a feed, and floating/named-zone timed events remain unsupported and reject the affected feed. This migration does not broaden ICS compatibility.

Both views show Monday through Friday. Selected dates determine the week rows, and matching events on boundary weekdays remain visible outside the exact selected range. Weekend events and events outside those rows do not appear in the wallpaper or event list. The maximum range is 12 weeks.

Rows adapt to busy days. Long titles wrap and then shorten with explicit warnings; events that cannot fit show an overflow count. Full details remain available in the native event table. Room disagreements are marked in the image and explained in event details. The shared SVG renderer and its typography remain unchanged.

## Development tools and verification

`npm run build` still generates the separate browser development preview, SVGs, light/dark PNGs, normalized events, validation reports, and `module-appearance.json` under `output/`. `WAPACAL_TODAY=YYYY-MM-DD` makes that build's date marker reproducible. It does not refresh feeds automatically.

`output/preview.html` remains available for renderer development in Firefox and legacy transfer exports. It is not bundled or opened by Wapacal. Browser preferences remain separate from Mac settings. Browser HEIC export creates a `.wapacal` transfer file; the native app writes HEIC directly. Sharp and browser SVG rasterization can differ slightly in font rendering.

The test suites use fictional fixtures. `test:editor` checks the worker's transactions, state compatibility, feed rejection, rollover, exclusions, suggestions, and export consistency. `test:native` checks icons, ImageIO round trips, legacy imports, refresh settings, storage migration, and recovery. `test:native-ui` runs a temporary native app with isolated settings and verifies real controls, image rendering, persistence, window layout, and the absence of visible WebKit views.

The native GUI and detached renderer have been exercised on the development Mac. Earlier wallpaper checks verified Automatic appearance mapping, applying images, and restoring the original wallpaper on the built-in display and current Space. Full login, wake, inactive Spaces, external displays, reconnection, and older macOS versions still require live testing. The app remains locally ad-hoc signed and is not notarized for distribution.

See [native interface architecture](docs/native-interface.md) for ownership, data flow, and compatibility details, and [PLAN.md](PLAN.md) for earlier development history.
