# Wapacal

Research started on 6 September 2026. Target: a local macOS calendar-to-wallpaper app.

The working prototype now includes the calendar parser, shared SVG renderer, browser preview, native AppKit interface, menu bar controls, scheduled calendar refresh, paired HEIC generation, wallpaper apply/restore, editable module suggestions, and launch-at-login support. Node and Sharp remain development tools; the built app runs with bundled JavaScript in WKWebView and native macOS frameworks.

The repository has also completed its first privacy and storage cleanup. Automated integration tests use fictional fixtures instead of the developer's calendar. Mutable app data lives in Application Support, older beside-the-app data migrates on first launch, generated history is bounded, and the app has a confirmed reset action. Public release packaging is deliberately deferred while the product is still changing.


## Empty public builds, 9 September 2026

The default native build now ignores local configuration, cached calendars, and `CALENDAR_URL`. It starts with an empty current-month view. `npm run build:native:private` retains optional private seed data for development. Missing snapshots no longer prevent a build. The release-packaging descriptions below record earlier plans; signing and distribution work remain deferred.


## Native interface migration, 8 September 2026

The application now presents only AppKit views. Layout controls, date pickers, event selection and full details, suggestions, previews, and export sheets are native. A detached private WebKit worker retains the shared parser and wallpaper renderer; it is never installed in a window. The browser preview remains a separate development tool and is absent from the app bundle.

Existing state keys, event IDs, subscriptions, refresh behavior, wallpaper recovery, HEIC mapping, legacy imports, and CLI commands remain compatible. Native integration tests use fictional data in a temporary app and verify that no WebKit view appears in any tab. See [native interface architecture](docs/native-interface.md) for the current design and [README.md](README.md) for current usage. The earlier prototype descriptions below are historical.

## Recommendation

Continue with the existing small menu bar app. It fetches an ICS subscription, organizes events into a selected month or named module, renders light and dark images, and installs an appearance-aware wallpaper. Keep settings, calendar data, and image generation on the Mac.

Keep manually named modules and start/end dates as the source of truth. Suggested ranges are now available, but remain editable and never replace saved settings without an explicit choice.

The chosen implementation uses actual wallpaper images rather than a persistent desktop overlay. The calendar stays visible after the app quits, and rendering only happens when needed. Light and dark variants are packaged in an appearance-aware HEIC so macOS can switch them. The app runs periodically only when automatic refresh and wallpaper updates are wanted.

Do not add an Xcode project, release signing, notarization, installer creation, or a large directory reorganization yet. Those tasks become worthwhile when the app is stable enough for an outside beta. Before sharing any build, add a release path that cannot embed the developer's private calendar or subscription URL.

## Feed behavior established during prototyping

The first local TimeEdit snapshot established the following behavior. The snapshot and subscription remain private and are not test fixtures or tracked project data.

- A feed can mix timed teaching events, date-only activities, holidays, and events outside the chosen course or visible date range.
- A declared subscription date limit does not guarantee that teaching events are published throughout the period.
- There are no explicit module fields, categories, or module names in the inspected properties. Course code alone cannot distinguish modules.
- Timed events may use UTC. Convert them to the configured time zone, including daylight-saving transitions. Preserve date-only values as calendar dates.
- Useful session titles frequently appear in `DESCRIPTION`. `SUMMARY` often contains only the type and course code. Strip standalone trailing TimeEdit IDs from display text; keep the original fields internally.
- Locations can conflict with rooms named in descriptions. Keep both available in the preview rather than silently choosing a room from prose.
- The feed contains folded lines and escaped punctuation. Use an ICS library in the app. The inspection script was only for examining this sample.
- Every event in this response shares its export-time `DTSTAMP` and `LAST-MODIFIED` value. Verify those fields across later responses before treating them as evidence that an event changed. Compare normalized event content to decide whether to regenerate images.
- `X-PUBLISHED-TTL` says 20 minutes, while the HTTP response advertises a cache lifetime of 4,200 seconds, or 70 minutes. Respect HTTP caching; do not promise immediate schedule updates. This response supplied neither an ETag nor an HTTP Last-Modified header.
- The server returned `Access-Control-Allow-Origin: *`, making a direct browser fetch plausible for this particular feed. Validate the actual browser request before choosing the Plash shortcut. A native fetch avoids depending on this behavior for other providers.

## Existing tools and projects

| Tool | What it provides | Fit for this project |
| --- | --- | --- |
| [Plash](https://sindresorhus.com/plash) | Displays a local or remote webpage above the Mac wallpaper, with automatic reloading and custom styling. | Best route to a quick custom prototype. It is an overlay, has limited multi-display support, and does not appear on the lock screen. Its [repository](https://github.com/sindresorhus/Plash) says the app is no longer open source. |
| [Übersicht](https://tracesof.net/uebersicht/) | Open-source desktop widgets using HTML, JavaScript/React, and system command output. | Useful implementation reference and another host for a custom timetable. Still requires building the feed handling and module layout. Its [widget documentation](https://github.com/felixhageloh/uebersicht/blob/master/README.md) explains refresh scheduling and state updates. |
| [WallCal](https://wallcal.app/) | Mac desktop calendar with monthly and agenda views, appearance controls, and calendar-account integration. | Closest ready-made Mac product to evaluate for a conventional monthly calendar. I found no documented support for named modules with fixed five-week ranges. Direct ICS entry was not verified. |
| [DejaDesktop](https://www.companionlink.com/dejadesktop/) | Generates calendar content on wallpaper for Mac and Windows, with calendar data integrations. | Similar image-generation approach. Its published workflows center on ordinary month/day calendars; custom module ranges were not established. |
| [CalPaper](https://calpaper.eu/) | Windows wallpaper calendar with ICS support and per-display layouts. | Close product reference if Windows becomes a target. Not a Mac solution. |

This comparison is based on current product documentation and project pages, not hands-on testing of installed apps.

## Product behavior

The setup flow is: paste subscription URL, preview parsed events, choose the course/events to include, enter a module name and date range, choose appearance and screen, then apply the wallpaper.

Support two initial views:

1. A fixed module view with one row per week and Monday through Friday columns. Keep its range unchanged as the module progresses. Permit other module lengths instead of forcing every module into exactly five weeks.
2. A current-month view with the four to six calendar rows that month requires, also Monday through Friday only. Weekend support is deferred.

The selected dates determine the week rows. Fill every visible weekday with all matching events, including dates outside the selected month or module range. Do not add extra weeks for events outside those rows. Exclude weekend-only events from the visible count and event details. Preserve the selected course filter.

Use 24-hour times, ISO week numbers, clear session titles, and compact room labels. Highlight today and examinations without depending on color alone. Preserve empty days. Reserve adjustable space for desktop icons, the menu bar, and Dock. Render to each selected display's dimensions and pixel density.

For busy dates, wrap titles and use an explicit overflow indicator if an event cannot fit. The preview must reveal omitted details and let the user increase the timetable area or change density. Wallpaper cannot scroll or provide clickable event details; those belong in the app preview.

Save each module independently, retain its light/dark exports, and display one chosen module at a time by default. An optional setting can select the module containing today's date. Keep a manual override. If ranges overlap or no module matches, retain the current choice and offer a selection in the menu.

Start with a reviewable course-code filter, not an irreversible rule that every untagged event is irrelevant. Allow individual inclusions/exclusions. Keep local title and room overrides separate from source data so later feed refreshes preserve them.

## Proposed implementation

Use the current AppKit application for the window, menu bar, display controls, and desktop integration. Fetch through URLSession. Bundle the JavaScript calendar/layout code and [ical.js](https://github.com/kewisch/ical.js) inside WKWebView, sharing the renderer between browser development, exports, and the native editor. This keeps styling work in VS Code and previewable in Firefox. The installed app uses WebKit and does not need Firefox, Node, a local server, or a hosted service.

ICAL.js supplies parsing and recurrence tools. Its documentation notes that timezone definitions are not bundled by default. For this UTC feed, format instants in Europe/Stockholm using platform timezone support. For broader feed support, register provided VTIMEZONE definitions and handle unknown TZIDs explicitly. Test recurring events and exceptions before advertising compatibility with arbitrary subscriptions.

The processing path is:

`Subscription → fetch/cache → parse and normalize → filter/module range → table layout → light/dark PNGs → macOS wallpaper`

The renderer produces SVG directly. Browser canvas or Sharp creates PNG exports, while the embedded editor passes paired PNG data to Swift for HEIC encoding. This avoids depending on WKWebView snapshot behavior and keeps the browser and native layouts on the same rendering path.

Apply images with [NSWorkspace.setDesktopImageURL](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)). This API targets a screen. Its existence does not establish reliable behavior across every inactive macOS Space. Test Spaces, external displays, display reconnection, and wallpaper cropping on the target macOS release; document the supported behavior.

Generate both appearance variants after a content/layout change, then package them in a two-image HEIC with appearance metadata. The [wallpapper project](https://github.com/mczachurski/wallpapper#appearance) documents this workflow using a light image and a dark image. Prefer letting macOS switch the pair. Verify recognition, automatic appearance changes, and replacement of an updated HEIC on the target macOS version in step 2. Keep PNGs as preview/export assets and a fallback. If HEIC integration fails, the app can observe [effective appearance](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance) and switch PNGs. Offer System, Light, and Dark settings.

Offer launch at login through [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice). Refresh when HTTP cache freshness permits, on manual request, and after wake if due. Re-render locally at midnight and when the chosen range, appearance, or display changes. Hash normalized visible content so changing export timestamps alone does not cause wallpaper replacement.

Keep the last successful feed and rendered images if fetching/parsing fails. Show the last successful check and error in the menu bar app. A failed request must not replace the wallpaper with a blank calendar. On a valid full response, reconcile deleted and changed events; do not only append new records. When a feed's coverage changes, distinguish events outside coverage from confirmed deletions where possible.

Store subscription links and cached calendars under the app's Application Support directory, avoid logging the full URL, and render event text as text rather than executable HTML. Keep the calendar read-only. Provide Pause, Refresh, Preview, Export PNG, Reset data, and Restore previous wallpaper actions. Reset must retain active wallpaper files and current recovery records. Restoration should preserve original per-screen options where supported and should not claim to reproduce every dynamic wallpaper or Space configuration.

## Build sequence and completion checks

1. **Data and layout proof, complete.** Parse and normalize ICS data, verify local times, and render month and module views in both appearances. Cover dense dates, escaping, boundary weeks, overflow, and event exclusions.
2. **Wallpaper feasibility, complete for the tested setup.** Package two appearances in HEIC, verify frames and metadata, apply an updated image, and restore the previous wallpaper. Inactive Spaces and external-display lifecycle behavior still need live testing.
3. **Usable local version, complete.** Save the subscription and editor settings, refresh in the background, preserve the last working data after failures, export PNG/HEIC, update the selected display, and support launch at login.
4. **Module suggestions, complete.** Use deterministic introductions, examinations, topic changes, and schedule gaps. Show supporting events and require an explicit choice before changing the editor.
5. **Privacy and storage baseline, complete.** Use fictional integration fixtures, ignore local fetch metadata, store mutable data under Application Support, migrate older local state safely, bound generated history, and offer a reset action.
6. **Reliability work, ongoing.** Continue testing recurrence behavior, offline startup, sleep/wake, midnight changes, login approval, inactive Spaces, and reconnecting monitors. Add multiple feeds or display-specific layouts only when the product needs them.
7. **Public release, deferred.** When outside testing is likely, create a generic release build with no private seed data, choose a permanent bundle identifier, then add the native project, signing, notarization, packaging, and clean-machine verification.

## Progress — 8 September 2026

Module suggestions are local and editable, with supporting event titles and dates. Introductions, examinations, topic introductions, and schedule gaps inform boundaries. Suggestions require an explicit Use module action; manual editing and saved exclusions remain available.

Step 1 is implemented, including weekday-only tables, complete boundary weeks, compact layout, and reversible individual event exclusions.

Step 2 now has an AppKit companion, a paired browser export, native ImageIO HEIC creation/inspection, per-display apply and restore controls, and recovery records. On macOS 26.6.2, the built-in display recognized the file as Automatic. The selected-wallpaper preview changed between the embedded light/dark frames when system appearance changed. A different module applied successfully, and the original static PNG and display options were restored. The user's Auto appearance setting was also restored. The implementation waits for WallpaperAgent's asynchronous restoration before confirming success.

Validation covers HEIC frame dimensions/mapping, image round-trip quality, invalid exports without overwriting, and preservation of event exclusions in both exported appearances. Only the current Space and built-in display were tested; inactive Spaces, external displays, and reconnection remain open feasibility checks. No fallback appearance observer is needed for the verified setup.

Step 3 is implemented as a local first version. The AppKit window now embeds the existing editor in WKWebView, and the built app uses bundled ICAL.js and URLSession without a Node runtime. It saves the subscription, module/month controls, filters, exclusions, display choice, and cache state. Direct Apply renders paired PNGs to HEIC. Optional wallpaper updates run after edits, refreshes, and local date changes. HTTP freshness and validators control scheduled checks; failures retain the prior calendar and wallpaper. A menu bar item keeps the app accessible when its window closes, and an optional SMAppService control registers launch at login.

Live verification covered the local feed, cache feedback, reopening saved data, direct Apply, and restoration. Automated checks cover editor state and exclusions across refresh, invalid calendar retention, paired rendering, cache policy, missing wallpaper sources, storage migration, and data reset. Preview and editor integration tests now build from fictional fixtures instead of the private calendar snapshot.

Runtime settings, cached calendar data, recovery records, and generated wallpapers now live under `~/Library/Application Support/local.wapacal.app/`. The first Wapacal launch copies older runtime files from `local.timetable.wallpaper` or from beside the previous bundle and removes each source only after its destination succeeds. Files currently used as wallpapers remain in place. Inactive applied wallpaper history is capped at 24 files, archived recovery history at 20, and Reset data clears private state without breaking the active wallpaper or current restore path.

The remaining near-term work is product development and lifecycle verification. Wake, midnight/month rollover, launch-at-login approval and a full login cycle, inactive Spaces, and external display reconnection have not all been tested live. The development bundle still embeds the local seed snapshot and subscription URL. A generic build, permanent bundle identity, Xcode project, release signing, notarization, and installer remain deferred until an outside beta is plausible.
