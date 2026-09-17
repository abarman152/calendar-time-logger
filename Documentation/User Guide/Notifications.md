# Notifications

Calendar Time Logger delivers four kinds of notification. All of them are optional, and none is needed for work to be recorded.

## What exists

| Notification | When | Default |
| --- | --- | --- |
| **Session started** | You start a session | Off per template |
| **Long session reminder** | After each interval of *active* work | Off per template |
| **Work completed** | You finish a session | On |
| **Calendar sync problem** | A finished session could not be added to Calendar | On |

There is no scheduled daily or weekly summary. Today's total can be included in the completion notification, and that is the only summary the app sends.

### What each one says

**Session started** — "Started Software Engineering", with "Timer is running. Finish Work when you're done."

**Long session reminder** — "Still working on Software Engineering?", with the active work so far, for example "1h 30m of active work so far."

**Work completed** — "Work Completed: Software Engineering", with the time range and active work, for example "9:00 AM – 11:15 AM · 1h 50m active". When **Include today's total** is on, today's total is added on a second line.

**Calendar sync problem** — "Work saved, but not added to Calendar", with the template name and the reason. The title says the important part first: your work is saved.

## How reminders are timed

Reminders fire at each multiple of the interval of **active** work, not clock time. A 60-minute reminder on a session you pause for 20 minutes arrives after 60 minutes of actual work, not 60 minutes after you started.

Pausing cancels the pending reminders; resuming schedules them again from where your active time actually is. Finishing or cancelling clears them.

Choose the interval per template: off, or every 15, 30, 45, 60, 90, or 120 minutes.

## Two switches per notification

A notification is delivered only when **everything** allows it:

1. macOS has granted notification permission.
2. **Settings › Notifications › Enable notifications** is on.
3. The category is on, for example **Session ends**.
4. The template allows it, for start, end, and reminder notifications.

| Where | What it controls |
| --- | --- |
| **Settings › Notifications** | The master switch and each category, for the whole app |
| The template editor's **Notifications** card | Start, end, and reminder interval for that template |

Completion notifications and Calendar failures have no per-template switch beyond **Notify when session ends**.

## Permission

macOS permission is requested when you choose **Allow Notifications** — on the welcome screen or in **Settings › Notifications** — or the first time a template that actually wants a start notification or reminder begins a session. The app does not ask on launch for a permission it may never use.

**Settings › Notifications** shows the current system permission as **Not Requested**, **Allowed**, or **Off**, and offers **Open Notification Settings** when macOS has it turned off.

If permission is denied, notifications are simply skipped. Sessions, Work Logs, Calendar events, and analytics are unaffected.

---

[Back to User Guide](README.md) · [Previous: Analytics](Analytics.md) · [Next: Exporting Data](Exporting%20Data.md)
