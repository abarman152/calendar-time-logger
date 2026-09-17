# Troubleshooting

Each entry gives the symptom, the likely cause, and what to do.

## Sessions

### I can't start a session — Start Work is greyed out

**Cause.** A session is already open. Calendar Time Logger records one session at a time.

**Fix.** Finish or cancel it first. If you started the wrong template, use **Change Template** instead — it keeps the timer running.

### "Work can't be recorded because the database is unavailable"

**Cause.** The app could not open its database, usually a full disk or damaged container. It falls back to temporary storage and refuses to start sessions rather than record work that would be lost.

**Fix.** Free up disk space, then quit and reopen Calendar Time Logger. The banner on the Dashboard names the underlying reason.

### The app closed with a session still running

**Cause.** A quit, a crash, or a restart while a session was open. The session is still in the database.

**Fix.** The next launch shows **Active Session Detected** on the Dashboard and in the menu bar popover. Choose **Resume Session**, **Finish Work**, **Finish at *time*** (the last moment the app was known to be running), or **Cancel Session**. See [Sessions](Sessions.md#recovering-a-session).

### The timer kept running while my Mac was asleep

**Cause.** **Pause the session when my Mac sleeps** is off, the default — you may still be working away from your Mac.

**Fix.** Turn it on in **Settings › General**. For a session that already ran long, edit its finish time in Work Logs.

### A session's duration looks wrong

**Cause.** Most likely you are comparing two different numbers. **Active work** excludes pauses; **duration** is the wall clock from start to finish. Totals, the timer, and the daily goal use active work; a Calendar event covers the wall clock.

**Fix.** The Work Logs inspector shows both, plus the total paused time and the number of pauses.

## Menu bar

### The CTL item isn't in the menu bar

**Causes and fixes**, in order:

1. **Show CTL in the menu bar** is off — turn it on in **Settings › Menu Bar**.
2. The app isn't running — the item exists only while it does.
3. Your menu bar is full, so macOS hid it. Widen the window of items by quitting another menu bar app, or check the overflow area.

The item is not tied to sessions: if the app is running and the setting is on, it is there whether or not you are working.

### The menu bar shows a plain timer symbol instead of my template

**Cause.** That template's **Show in menu bar** is off, so it doesn't identify itself. The generic symbol still tells you a session is running.

**Fix.** Turn on **Show in menu bar** in the template editor.

### I can't read the menu bar item

**Cause.** A custom icon, name, or duration color that doesn't contrast with your menu bar or with the template's background pill.

**Fix.** Set the colors back to **Auto** in the template editor. Auto matches the menu bar in light and dark appearance, and switches to white or black on a colored pill. The **Menu Bar Preview** card previews light and dark before you save.

### Two CTL items appeared

**Cause.** Normally impossible: a second copy of the app activates the first and quits. A DEBUG demo build is the exception, and shows its own item alongside the installed app.

**Fix.** Quit the extra copy.

## Calendar

### Finishing a session shows "Sync Failed"

Your work log is saved. The message names the cause.

| Message | Fix |
| --- | --- |
| "…doesn't have access to your calendars." | Allow full access in System Settings › Privacy & Security › Calendars, then **Retry** |
| "…has 'Add Events Only' access." | Change it to full access. Add Events Only can't list calendars or update the app's own events. |
| "The selected calendar no longer exists." | Choose another calendar for the template, or in Settings › Calendar, then **Retry** |
| "The calendar *name* is read-only." | Choose a calendar you can edit, then **Retry** |
| "The Calendar event couldn't be saved." | **Retry**. The underlying reason is shown with the message. |

**Sync Issues** in the Calendar section lists everything that needs attention and has **Retry All**.

### No event was created and there's no error

**Cause.** **Add finished sessions to Calendar** is off. The confirmation says "Calendar sync is off, so no event was created." and the work log reads **Not in Calendar**.

**Fix.** Turn it on in **Settings › Calendar**, then use **Add to Calendar** on the work log.

### A work log says "Event Missing"

**Cause.** The event was deleted in Calendar outside Calendar Time Logger. Your work log is unchanged.

**Fix.** **Add to Calendar** in the Work Logs inspector creates it again.

### The event is in the wrong calendar

**Cause.** Calendar Time Logger uses the first of these that is set: the session's own calendar, then the template's, then **Settings › Calendar › Default calendar**, then your system default.

**Fix.** Set the level you meant to. Note that changing a template's calendar does **not** move events that already exist; use **Edit Entry › Calendar** on the individual work log for those.

### All my events are the same color

**Cause.** Apple Calendar colors events by the calendar they belong to, and EventKit has no per-event color. A template can't give its events their own color.

**Fix.** Point each template at a different calendar, chosen for its color, under **Recording › Calendar**. The template editor's **Calendar Event Appearance** card shows the resulting color.

### I edited a work log but the event didn't change

**Cause.** Calendar sync was off when you saved.

**Fix.** Turn on **Add finished sessions to Calendar**, then **Retry** on that work log.

### "View in Calendar" doesn't select my event

Expected. It opens the Calendar app; there is no public API to select a specific event. To go the other way, click the event's URL in Calendar — that opens Calendar Time Logger at the matching work log.

## Work Logs

### A finished session isn't in the list

**Causes.** It was **cancelled** rather than finished — cancelled sessions never appear anywhere. Or a search or filter is hiding it.

**Fix.** Clear the search field and choose **Clear Filters**. The subtitle tells you when a filter is limiting the list, for example "3 sessions of 19".

### Old work logs still show a template's previous category

Expected. A work log keeps the category it was recorded with, so changing or renaming a template's category only affects sessions started afterwards. To correct one work log, select it, choose **Edit Entry**, and change **Category**. See [Categories](Categories.md).

### Every template and work log is in General after upgrading

Expected. Categories were added in 1.3.0, and everything recorded before then was given the category **General**; nothing else changed. Set each template's category in **Templates**, and edit individual work logs if you want your history regrouped.

### My pauses changed after I edited the times

Expected, and the sheet warns before you save: pauses outside the new start and finish times are trimmed. Individual pauses cannot be edited.

### Deleting a work log didn't remove its Calendar event

**Cause.** You chose **Delete, Keep Calendar Event**.

**Fix.** Delete the event in Calendar yourself. Note that the app only ever removes events it created.

## Export

### The export failed

| Message | Fix |
| --- | --- |
| "…doesn't have permission to save *file*." | Choose a different folder, such as Documents or Desktop |
| "There isn't enough disk space…" | Free up space and try again |
| "The Excel workbook couldn't be saved." | The reason is shown; try another location |
| "The work logs couldn't be converted to an Excel workbook." | Reported before the Save panel, so nothing was written. Please report this one. |

Your work logs are never changed by an export, successful or not.

### The workbook is empty

**Cause.** The chosen scope has no completed sessions — for example **Today** before you have finished anything today.

**Fix.** The export sheet shows the session count before you export, and warns that an empty workbook will contain only column headers. Choose a wider scope.

### Durations show as strange numbers in another app

**Cause.** Durations are real Excel elapsed-time values, not text. A spreadsheet app that doesn't understand the format may show the underlying number.

**Fix.** Format the column as elapsed time (`[h]:mm:ss`). The workbook opens correctly in Microsoft Excel and Numbers as written.

## Notifications

### I'm not getting any notifications

Check each gate in turn — all must allow it:

1. macOS permission, shown in **Settings › Notifications › System permission**. If it reads **Off**, use **Open Notification Settings**.
2. **Enable notifications** in the same pane.
3. The category, for example **Session ends**.
4. The template's own setting, in the template editor's Notifications card.

Start notifications and reminders are **off by default per template**, so a fresh template sends neither.

### Reminders arrive at the wrong time

Expected behavior, not a bug: reminders count **active** work, not clock time. A 60-minute reminder on a session paused for 20 minutes arrives after 60 minutes of actual work. Pausing cancels pending reminders; resuming reschedules them.

## The app itself

### Calendar Time Logger won't open

- macOS 27.0 or later is required.
- Builds are signed with a personal Apple Development certificate and are **not notarized**, so macOS Gatekeeper blocks them on any Mac other than the developer's. Distribution to other Macs needs Developer ID signing and notarization; see [Release Process](../Releases/RELEASE.md).

### Closing the window didn't quit the app

By design. Closing the main window keeps Calendar Time Logger and its CTL item running, so a session in progress keeps running. Quit with <kbd>⌘</kbd><kbd>Q</kbd> or from the menu bar popover.

### Opening the app just brought the existing window forward

By design. Only one copy runs at a time, because a second would add a second menu bar item and write to the same database.

### Some screens feel slow

Work Logs, the Dashboard, and Analytics load every completed session into memory. With a very large history this can be noticeable.

## Starting over

To remove all local data — templates, sessions, and settings — quit Calendar Time Logger and delete:

```
~/Library/Containers/abirbarman.calender-time-logger
```

This cannot be undone, and it does not remove events already written to Apple Calendar. Export your work logs first if you want to keep them.

---

[Back to User Guide](README.md) · [Previous: Settings](Settings.md) · [Next: FAQ](FAQ.md)
