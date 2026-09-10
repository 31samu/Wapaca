<br><div align="center"><img src="assets/app-icon/Wapacal-iOS-Default-1024x1024@1x.png" alt="Wapacal App Icon" width="150"> </div> <br>

# Wapacal


Turn your calendar into a Mac desktop wallpaper. Wapacal combines ICS calendar subscriptions, including TimeEdit and Moodle feeds, into a month view or a custom date range.

- Choose which events appear and adjust the layout.
- Export PNGs or a HEIC wallpaper that switches between light and dark with macOS.
- Refresh calendars and update your wallpaper automatically while the app runs.
- Restore your previous wallpaper from Settings.

<p align="center">
  <img src="assets/screenshots/wapacal-editor.png" alt="Wapacal editor showing a calendar preview" width="1000">
</p>

Wapacal is an early macOS app built from source.

Wapacal is not currently notarized. If downloadable builds are added, macOS may block the first launch. Open **System Settings → Privacy & Security** and choose **Open Anyway**.

### Note from maker:
I wanted a calendar desktop wallpaper that updates automatically, so I made it. The project was largely slopped together and I don't have experience maintaining something open source, but I expect to update the app until it has all features I'd want or fix it when it breaks. Feel free to reach out, suggest something or fork the project.

## Build and run

You need macOS, Xcode Command Line Tools, and Node.js 22.14 or newer. The built app targets macOS 13 and later and runs without Node.

From the project directory:

```sh
npm ci
npm run build:native
open output/Wapacal.app
```

The default build includes no private calendars or settings. On first launch, add an ICS subscription URL in **Settings → Calendars**. Existing installations keep their saved settings.

## Make your wallpaper

Choose **Month** or **Module** in the sidebar. A module is a named date range, such as a course block. Enable **Include Saturdays and Sundays** when you want a seven-day calendar. Use **Choose events** to hide individual events and **Appearance** to adjust the image size, theme, and layout.

Click **Apply wallpaper** to use it on the selected display, or **Export** to save an image. Settings also offers automatic updates and launch at login. Closing the window keeps Wapacal running in the menu bar; choose **Quit** there to stop it.

<p align="center">
  <img src="assets/screenshots/wapacal-wallpaper.png" alt="A Wapacal calendar used as a Mac desktop wallpaper" width="1000">
</p>

From the menu bar, you can reopen Wapacal, change settings, refresh and apply the wallpaper, or quit the app:

<p align="center">
  <img src="assets/screenshots/wapacal-menubar-menu.png" alt="Wapacal menu bar menu" width="439">
</p>

Your settings and cached calendars stay on your Mac under `~/Library/Application Support/com.samuelkremer.wapacal/`.

## Current limits

- Feeds must use UTC times or all-day dates. Recurring events, recurrence exceptions, duplicate event IDs within a feed, and floating or named-zone times are not supported and cause the feed to be rejected.
- External displays, inactive Spaces, and older macOS versions still need live testing. Restoring Apple's dynamic or aerial wallpaper settings is not guaranteed.
- Wapacal currently requires a direct ICS subscription URL. It does not connect directly to Apple Calendar or Google Calendar accounts.

## Development

```sh
npm run format:check
npm run test:all
```

Build the app before running all tests. Native UI and HEIC tests need a logged-in macOS graphical session. Tests use fictional calendar fixtures.

See the [development guide](docs/development.md) for private builds, the Firefox preview, and command-line tools, or the [architecture guide](docs/native-interface.md) for how the app works.

## License

Copyright (C) 2026 Samuel Kremer. Wapacal is licensed under the [GNU General Public License version 3](LICENSE), GPL-3.0-only. Third-party dependencies retain their own licenses.
