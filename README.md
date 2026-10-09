# EasyCalendar

<img src="App/Resources/AppIcon.png" width="96" alt="EasyCalendar icon">

A native macOS desktop calendar widget that uses events from Apple Calendar. Built with SwiftUI, WidgetKit, App Intents, and EventKit, with no third-party dependencies.

**Version:** 0.4.2 (7) · **License:** [GPL-3.0-only](LICENSE) · **Requires:** macOS 14 or later

## Features

- Select dates directly in the monthly calendar to view that day's events.
- Treat events from writable calendars as tasks: colored checkboxes, strikethrough and gray text when completed, and confirmation before deletion. Adding and deleting events updates Apple Calendar. Completion marks stay on this Mac; events are not converted into Reminders.
- Show holidays, subscriptions, and other read-only events in a light purple strip. Colored dots under calendar dates indicate events, with up to four distinct colors per day.
- When the selected day has no tasks, show upcoming incomplete tasks within the next 30 days. Use the up/down buttons to change pages.
- Use the top-right buttons to add an event on the selected date, open Apple Calendar, or open settings. Settings include System default, Simplified Chinese, English, calendar access, and version/license information.

## Install and use

1. Move `EasyCalendar.app` to **Applications**, open it, and click **Allow access & refresh**.
2. Right-click the desktop, choose **Edit Widgets**, search for **EasyCalendar**, and add the medium widget.
3. Select a date to view events. Click the gear to change the interface language or refresh calendar access.

There is no persistent menu bar icon. Open the app from Applications whenever you need its settings.

Changing the language requests a widget refresh. WidgetKit controls when that refresh appears. Event titles and calendar names retain their original text.

If the app has access but the widget still asks for permission, refresh from settings and check **System Settings → Privacy & Security → Calendars**. Rebuilding with an ad-hoc signature may require renewed permission. Do not reset calendar permissions for all apps.

## Old name or preview after an upgrade

macOS can register build copies and unpacked app backups as widget sources. If the gallery still shows OpenCalendarWidget or a preview without the gear, close the gallery and run this from the repository root in your Mac's Terminal:

```sh
bash scripts/refresh-widget.sh
```

The script verifies the installed app, unregisters copies within this project's build directory, registers the extension inside `/Applications/EasyCalendar.app`, and restarts Notification Center. Unregistered copies are skipped; connection or permission errors stop the script and show the cause. It preserves app files, calendar data, and completion marks, and does not reset the entire Launch Services database. Reopen **Edit Widgets** afterward.

## Build from source

Requires Xcode 16.2 or later and its command-line tools. From the repository root:

```sh
./scripts/build.sh Release
```

The app is written to `build/DerivedData/Build/Products/Release/EasyCalendar.app`. Omit `Release` for a Debug build. The script runs regression checks before building a universal Apple Silicon / Intel app and its widget extension. Build logs are saved to `build/build.log`.

Create an archive for a GitHub Release:

```sh
mkdir -p build/release
ditto -c -k --sequesterRsrc --keepParent \
  build/DerivedData/Build/Products/Release/EasyCalendar.app \
  build/release/EasyCalendar-0.4.2-macOS.zip
```

Current builds use ad-hoc signing and **are not Developer ID signed or notarized**. Installation, permissions, and security prompts on another Mac have not been verified. Complete signing, notarization, and installation checks on another Mac before distributing to general users. Provide the corresponding source and LICENSE alongside binary releases.

## Data and limitations

EventKit reads and writes system calendar events. Calendar accounts handle synchronization. EasyCalendar has no app server, analytics, or separate cloud synchronization.

The widget's sandbox stores the selected date, page, completion marks, and deletion confirmation. Widget instances share the selected date; the first interaction on a new day returns to today. Add-event links carry the selected date. Opening another add-event form does not overwrite an existing draft. Deleting a recurring event removes only that occurrence.

The app keeps the language selection in its standard preferences and publishes it to the dedicated `local.spacesands.EasyCalendar.SharedSettings` preference domain. The host has read/write access to this shared domain; the extension has read-only access. Core Foundation preferences are synchronized before requesting a widget refresh. The app's private preference domain is not used as the shared storage location. This local macOS build uses the shared-preference temporary exception entitlements; reassess sharing and signing before an App Store release.

Internal bundle identifiers, the URL scheme, widget kind, and local data directory retain the original OpenCalendarWidget identifiers to preserve existing widgets and completion marks after the rename.

WidgetKit does not support a custom right-click menu or gesture scrolling for this list, so the widget uses a gear button and pagination. Each timeline update reads events again and requests another update after 60 seconds. Actual refresh timing and click latency depend on system scheduling.

Editing existing events, standalone notes, MCP access, launch at login, and automatic updates are not implemented.

## Checks

The build includes a temporary executable bundle with the actual host bundle identifier to catch preference initialization errors that ordinary command-line checks would miss. The language bridge is checked with in-memory preference stand-ins for English/Chinese rendering, shared-domain consistency, synchronization errors, and invalid values. Neither check opens windows or changes real calendar data.

Other assertions cover language selection, settings URL validation, leap years, month boundaries, daylight saving time, overnight events, event colors, completion state, deletion confirmation, creation time validation, selected-date links, upcoming-task filtering and sorting, pagination height and bounds, and compatibility with older selection files.

Check refresh-script error handling separately:

```sh
python3 Checks/RefreshWidget.py
```

This check does not call system registration services. Desktop interaction and English language switching have been checked on the development Mac. Installation and permissions on another Mac have not been verified.

## License and icon

Source code and the included icon are licensed under [GPL-3.0-only](LICENSE). EasyCalendar is an independent implementation and includes no CalendarX or InstaCal source code or icons.

The icon was generated with the built-in ImageGen tool using this design brief: a white rounded-square background, a blue monoline calendar outline, and a teal checkmark, with no text, numbers, shadows, or 3D effects. The original PNG is `App/Resources/AppIcon.png`; system `sips` resizing produced the sizes packaged into `AppIcon.icns`. The app has no runtime dependency on an image-generation service.
