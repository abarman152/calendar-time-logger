# Privacy

This describes what Calendar Time Logger 1.1.0 actually does with your data, as implemented in code.

## Summary

- Your work data stays **on your Mac** in the app's sandbox container.
- **V1 has no iCloud sync.** The SwiftData store is created with `cloudKitDatabase: .none`, and the app has no iCloud entitlement.
- **The app makes no network requests of its own.** It is sandboxed without the outgoing-network entitlement, contains no analytics or crash-reporting SDKs, and has no third-party dependencies.
- The only data that leaves the app is the Calendar event for a finished session, written to **Apple Calendar** when you have Calendar sync on, and Excel files you explicitly export to a location you choose.

## What is stored locally

| Data | Where |
| --- | --- |
| Work Templates: name, icon, category, color, chosen calendar identifier, tags, notes, menu bar and notification settings, dates | SwiftData store in the app container |
| Work Sessions: template reference and snapshot (name, icon, color), category, task priority, start/finish times, pauses, state, notes, tags, calendar identifiers, Calendar event identifier, sync status and message, last heartbeat time | SwiftData store in the app container |
| Preferences: Calendar, notification, menu bar, appearance, export, and general settings (including the default template ID and daily goal) | App `UserDefaults` in the container |

Cancelled sessions are kept in the store but not shown. Deleting a work log removes it from the store.

## What is sent to Apple Calendar

Only when **Add finished sessions to Calendar** is on and you have granted Calendar access. For each finished session:

- **Title:** the template name
- **Start and end:** the session's start and finish times
- **Notes:** "Recorded with Calendar Time Logger", template name, category, active work, Urgent and Important, paused time; **tags** if "Include tags in events" is on; **your notes** if "Include session notes in events" is on
- **URL:** `calendartimelogger://session/<session-id>`, used to recognize events the app created

Once written, the event is part of your calendar. If that calendar belongs to an account such as iCloud, Google, or Exchange, Calendar syncs it the way it syncs any event. Calendar Time Logger has no control over that.

## Excel exports

Exports happen only when you choose **Export Work Logs**. The workbook contains, for each completed session in the chosen scope: date, start and end times, durations, template name, category, Urgent and Important, tags, notes, calendar name, Calendar event status, Calendar event identifier, and session status, plus optional totals. It doesn't contain internal database identifiers.

The file is written only where you choose in the macOS Save panel. The app's sandbox has the **user-selected files (read/write)** entitlement for this; it grants access only to the location you pick. After it's saved, the file is yours: anything you do with it (for example sharing or syncing it) is outside Calendar Time Logger.

## Permissions

| Permission | Why | When it's requested | If denied |
| --- | --- | --- | --- |
| **Calendars (Full Access)** | List your calendars so you can choose one, create events, and update or remove only the events this app created | When you click **Connect Apple Calendar**, or the first time you finish work if never asked | Work is still recorded; logs show Sync Failed with instructions |
| **Notifications** | Session started, reminders, work completed, Calendar sync problems | When you click **Allow Notifications**, or when a template with start notifications or reminders starts | No notifications; nothing else changes |
| **Files you choose** | Saving an Excel export | Each time you export, through the Save panel | Nothing is saved |

Full access is required because "Add Events Only" access can't read calendars or update existing events. With full access the app **reads** events only to find its own events, by their `calendartimelogger://` URL, near each session's time. It never modifies or deletes events it didn't create.

Reading from the Calendar database stays inside the app; nothing read from Calendar is sent anywhere.

## What V1 does not do

- No iCloud or other sync of templates or sessions
- No accounts, sign-in, or servers
- No analytics, tracking, or advertising
- No access to files other than exports you save, and no access to contacts, location, camera, or microphone
- No change to calendar colors or to events it didn't create

## Changing or removing data

- Turn off Calendar sync in Settings › Calendar. Existing events stay in Calendar.
- Revoke permissions in System Settings › Privacy & Security.
- Delete a work log in Work Logs and choose whether to remove its Calendar event.
- To remove all local data, quit the app and delete its container: `~/Library/Containers/abirbarman.calender-time-logger`.
