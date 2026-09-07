# Desktop background timetable

Research and proposed implementation, 6 September 2026. Target macOS, inferred from the current workspace. This is a plan, not an installed app.

Step 1 is complete. The repository now contains an ICAL.js parser, shared SVG layout renderer, local interactive preview, and four PNG/SVG exports at the detected display resolution of 3024 × 1964. September and the proposed October module each show all 12 course events without truncation. Calendar tests and preview interaction checks pass. The initial renderer uses plain JavaScript and SVG plus Sharp, so this step does not depend on WebKit snapshots. Native application integration and HEIC packaging remain unimplemented.

## Recommendation

Build a small menu bar app that fetches an ICS subscription, organizes events into a selected month or named module, renders light and dark PNGs, and sets the appropriate image as the desktop wallpaper. Keep settings, calendar data, and image generation on the Mac.

Start with manually named modules and start/end dates. The user prefers suggested date ranges eventually, with manual setup to keep the first version simple. Add suggestions after the basic workflow works. Suggestions must remain editable and must not silently change a saved module.

For a quick personal experiment, a custom calendar page displayed through Plash is the shortest alternative. For the intended app, use actual wallpaper images: the calendar stays visible after the app quits, and rendering only happens when needed. Package light/dark variants in an appearance-aware HEIC so macOS can switch them. The app still needs to run periodically to refresh calendar content and the current-day marker.

## What the supplied feed actually contains

The supplied URL was downloaded successfully on 6 September 2026. These observations describe that snapshot, not a guarantee about future responses.

- Calendar name: `TimeEdit-1DI300-20260801`.
- 56 events in total: 32 timed events and 24 date-only events.
- 24 events mention `1DI300`, between 8 September and 4 November 2026. September contains 12, October 11, November 1.
- The remaining events include university activities and holidays. The latest event begins on 26 June 2027.
- The declared date limit runs from 17 August 2026 to 7 September 2031. That does not mean teaching events are published throughout that period.
- There are no explicit module fields, categories, or module names in the inspected properties. Course code alone cannot distinguish modules.
- Timed events use UTC. Convert to `Europe/Stockholm`, including the autumn daylight-saving transition. Preserve date-only values as calendar dates.
- Useful session titles frequently appear in `DESCRIPTION`. `SUMMARY` often contains only the type and course code. Strip standalone trailing TimeEdit IDs from display text; keep the original fields internally.
- Some locations conflict with rooms named in descriptions. For example, the 8 September introduction has `M1104V Food lab` as its location and mentions `M1099B` in its description. Keep both available in the preview rather than silently choosing a room from prose.
- The feed contains folded lines and escaped punctuation. Use an ICS library in the app. The inspection script was only for examining this sample.
- Every event in this response shares its export-time `DTSTAMP` and `LAST-MODIFIED` value. Verify those fields across later responses before treating them as evidence that an event changed. Compare normalized event content to decide whether to regenerate images.
- `X-PUBLISHED-TTL` says 20 minutes, while the HTTP response advertises a cache lifetime of 4,200 seconds, or 70 minutes. Respect HTTP caching; do not promise immediate schedule updates. This response supplied neither an ETag nor an HTTP Last-Modified header.
- The server returned `Access-Control-Allow-Origin: *`, making a direct browser fetch plausible for this particular feed. Validate the actual browser request before choosing the Plash shortcut. A native fetch avoids depending on this behavior for other providers.

One plausible module starts with "Introduction Intersectionality & Norms" on 5 October and ends with "Final presentations" on 4 November. A Monday-aligned five-week display would cover 5 October through 8 November, weeks 41 to 45. This is an inference from session titles, not a confirmed module boundary.

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

Use SwiftUI for the menu bar/settings app and AppKit for desktop integration. Fetch through URLSession. Bundle a TypeScript calendar/layout component and [ical.js](https://github.com/kewisch/ical.js) inside a WKWebView, sharing that component between preview and image rendering. This allows the table styling to be developed in VS Code and previewed in Firefox. The installed app would use WebKit and would not need Firefox, Node, a local web server, or hosted services running.

ICAL.js supplies parsing and recurrence tools. Its documentation notes that timezone definitions are not bundled by default. For this UTC feed, format instants in Europe/Stockholm using platform timezone support. For broader feed support, register provided VTIMEZONE definitions and handle unknown TZIDs explicitly. Test recurring events and exceptions before advertising compatibility with arbitrary subscriptions.

The processing path is:

`Subscription → fetch/cache → parse and normalize → filter/module range → table layout → light/dark PNGs → macOS wallpaper`

Use [WKWebView snapshots](https://developer.apple.com/documentation/webkit/wkwebview/takesnapshot(with:completionhandler:)) to capture the completed table. Verify offscreen capture, font readiness, and Retina resolution in an early technical prototype. If that proves unreliable, use native Core Graphics/AppKit rendering for the same layout model before building the rest of the app around snapshotting.

Apply images with [NSWorkspace.setDesktopImageURL](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)). This API targets a screen. Its existence does not establish reliable behavior across every inactive macOS Space. Test Spaces, external displays, display reconnection, and wallpaper cropping on the target macOS release; document the supported behavior.

Generate both appearance variants after a content/layout change, then package them in a two-image HEIC with appearance metadata. The [wallpapper project](https://github.com/mczachurski/wallpapper#appearance) documents this workflow using a light image and a dark image. Prefer letting macOS switch the pair. Verify recognition, automatic appearance changes, and replacement of an updated HEIC on the target macOS version in step 2. Keep PNGs as preview/export assets and a fallback. If HEIC integration fails, the app can observe [effective appearance](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance) and switch PNGs. Offer System, Light, and Dark settings.

Offer launch at login through [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice). Refresh when HTTP cache freshness permits, on manual request, and after wake if due. Re-render locally at midnight and when the chosen range, appearance, or display changes. Hash normalized visible content so changing export timestamps alone does not cause wallpaper replacement.

Keep the last successful feed and rendered images if fetching/parsing fails. Show the last successful check and error in the menu bar app. A failed request must not replace the wallpaper with a blank calendar. On a valid full response, reconcile deleted and changed events; do not only append new records. When a feed's coverage changes, distinguish events outside coverage from confirmed deletions where possible.

Store subscription links in private local settings, avoid logging their full value, and render event text as text rather than executable HTML. Keep the calendar read-only. Provide Pause, Refresh, Preview, Export PNG, and Restore previous wallpaper actions. Restoration should preserve original per-screen options where supported and should not claim to reproduce every dynamic wallpaper or Space configuration.

## Build sequence and completion checks

1. **Data and layout proof.** Parse a local snapshot using the selected library, confirm the 24 course events, verify display titles and local times, and render a month plus the proposed five-week view in both appearances. Check the real screen size and dense dates. No wallpaper changes are needed for this step.
2. **Wallpaper feasibility.** Package the two rendered appearances in HEIC, verify embedded frames and metadata, and test macOS automatic switching. Prove applying an updated image and restoring the previous wallpaper in a minimal Mac app. Test display and Space behavior before treating the wallpaper integration as solved.
3. **Usable first version.** Add saved URLs, manual module name/date inputs, reviewable event filters, a preview, one selected display, PNG export, background refresh, caching, error recovery, and launch at login. Finish with end-to-end checks using the supplied subscription.
4. **Reliability and expansion.** Test moved/deleted/cancelled events, duplicate UIDs and recurrence exceptions, all-day exclusive end dates, daylight-saving transitions, offline startup, sleep/wake, and reconnecting monitors. Add multiple feeds and display-specific layouts when required.
5. **Suggested modules.** Look for introductions, examinations, topic changes, and schedule gaps. Present a proposed name and range with the supporting events. Require a user choice before saving a suggestion; keep manual editing available. Begin with deterministic rules. This feed is small enough that a language-model service is unnecessary.

## Progress — 7 September 2026

Module suggestions added on 8 September 2026: the editor offers local, editable proposals with supporting event titles and dates. Introductions, examinations, topic introductions and schedule gaps inform boundaries. The supplied course yields Worldbuilding from 8–30 September and Intersectionality & Norms from 5 October–4 November. Suggestions require an explicit Use module action; manual editing and saved exclusions remain available.

Step 1 is implemented, including weekday-only tables, complete boundary weeks, compact layout, and reversible individual event exclusions.

Step 2 now has an AppKit companion, a paired browser export, native ImageIO HEIC creation/inspection, per-display apply and restore controls, and recovery records. On macOS 26.6.2, the built-in display recognized the file as Automatic. The selected-wallpaper preview changed between the embedded light/dark frames when system appearance changed. A different module applied successfully, and the original static PNG and display options were restored. The user's Auto appearance setting was also restored. The implementation waits for WallpaperAgent's asynchronous restoration before confirming success.

Validation covers HEIC frame dimensions/mapping, image round-trip quality, invalid exports without overwriting, and preservation of event exclusions in both exported appearances. Only the current Space and built-in display were tested; inactive Spaces, external displays, and reconnection remain open feasibility checks. No fallback appearance observer is needed for the verified setup.

Step 3 is implemented as a local first version. The AppKit window now embeds the existing editor in WKWebView, and the built app uses bundled ICAL.js and URLSession without a Node runtime. It saves the subscription, module/month controls, filters, exclusions, display choice, and cache state. Direct Apply renders paired PNGs to HEIC. Optional wallpaper updates run after edits, refreshes, and local date changes. HTTP freshness and validators control scheduled checks; failures retain the prior calendar and wallpaper. A menu bar item keeps the app accessible when its window closes, and an optional SMAppService control registers launch at login.

Live verification covered the supplied feed, cache feedback, reopening saved data, direct Apply, and restoration. Automated checks cover editor state and exclusions across refresh, invalid calendar retention, paired rendering, cache policy, and missing wallpaper sources. The initial Apply regression came from requiring the old wallpaper file to exist before allowing a new one; Apply now works without that file and reports the restoration limitation.

The remaining work is lifecycle verification and packaging. Wake, midnight/month rollover, launch-at-login approval and a full login cycle, inactive Spaces, and external display reconnection have not been tested live. State still lives beside the app, and the private seed snapshot/URL are bundled for this local build. Moving state to Application Support and producing a distributable, notarized app remain packaging tasks.
