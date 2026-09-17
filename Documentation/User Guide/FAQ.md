# FAQ

Short answers to common questions. Each links to the page with the details.

## Recording work

### Does starting a template put anything in my calendar?

No. Nothing is written to Apple Calendar until you choose **Finish Work**. See [Sessions](Sessions.md).

### How long is the Calendar event?

Exactly as long as the session: from the moment you started to the moment you finished, including pauses. The event notes record how much of that was active work. A template has no duration and never decides the length. See [Calendar](Calendar.md).

### What's the difference between Duration and Active Work?

**Duration** is wall-clock time from start to finish. **Active Work** is that time minus pauses. Totals in Analytics, the Dashboard, and Work Logs use active work.

### Can I run two sessions at once?

No. One session is open at a time, whether it came from a template or a Quick New Task. Finish or cancel it before starting another. See [Sessions](Sessions.md).

### I forgot to stop the timer. Can I fix the times?

Yes. Finish the session, then select it in **Work Logs** and choose **Edit Entry** to correct the start and finish times; its Calendar event is updated too. If the app quit while the session was running, the next launch offers **Finish at *time***, the last moment the app was known to be running. See [Work Logs](Work%20Logs.md#editing-a-session) and [Sessions](Sessions.md).

### I started the wrong template.

While it runs, use **Change Template**: the timer keeps going and the session takes the new template's name, icon, and color. After finishing, use **Change Template** in the Work Logs inspector. See [Sessions](Sessions.md).

### What is Quick New Task for?

Work that doesn't deserve a template: an interruption, a one-off fix. You give it a name, a category, and a priority, and it is recorded like any other session. No template is created. See [Task Priority](Task%20Priority.md#quick-new-task).

## Categories and priority

### If I change a template's category, do my old work logs change?

No. A work log keeps the category it was recorded with. Only sessions started afterwards use the new category. The same is true for Urgent and Important. See [Categories](Categories.md).

### How do I change the category of one past session?

Select it in **Work Logs**, choose **Edit Entry**, and change **Category**. No template is changed.

### Why is all my older work in General?

Categories were added in 1.3.0. Everything recorded before then was given **General** when the app upgraded; nothing else changed. See [Categories](Categories.md#upgrading-from-12).

### Can a session be both urgent and important?

Yes. Urgent and Important are separate Yes/No values, so there are four combinations. Analytics shows all four, plus overlapping totals for urgent work and important work. See [Task Priority](Task%20Priority.md).

## Calendar

### Why don't my events use my template's color?

Apple Calendar colors every event by the calendar it belongs to, and there is no per-event color. To make a kind of work stand out, send its template's events to a calendar with the color you want. See [Templates](Templates.md#calendar-event-appearance).

### Will the app change or delete my other events?

No. It only updates or removes events it created, which it recognizes by a link stored in each one. See [Calendar](Calendar.md).

### What happens if Calendar access is denied?

Your work is still recorded. Each session is marked **Sync Failed** and can be added to Calendar later, once access is granted. See [Troubleshooting](Troubleshooting.md#calendar).

## Data

### Where is my data, and does it leave my Mac?

Templates, sessions, notes, tags, and settings are stored on this Mac, in the app's sandbox container. There is no account, sync, or network access. Only the Calendar events for finished sessions, and any Excel files you export, leave the app. See [Settings](Settings.md#privacy).

### Can I export only some columns?

Yes. The export sheet lets you check the columns you want, drag them into order, or pick a preset such as **Category Analysis**. See [Exporting Data](Exporting%20Data.md).

### Can I use it on an iPhone or iPad, or sync between Macs?

Not at this time. Calendar Time Logger runs on macOS only and keeps data on one Mac.

## The app

### Where did the menu bar item go?

Check **Settings › Menu Bar › Show CTL in the menu bar**. If the menu bar is crowded, macOS may hide items that don't fit, particularly next to a display's camera housing. See [Troubleshooting](Troubleshooting.md#menu-bar).

### Can I use Shortcuts?

Yes. **Start Work**, **Pause or Resume Work**, and **Finish Work** are available as Shortcuts actions. See [App Overview](App%20Overview.md#shortcuts-actions).

### How do I see the welcome screen again?

**Settings › General › Show Welcome Screen Again**. See [Getting Started](Getting%20Started.md#2-the-welcome-screen).

---

[Back to User Guide](README.md) · [Previous: Troubleshooting](Troubleshooting.md)
