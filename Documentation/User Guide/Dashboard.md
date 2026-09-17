# Dashboard

The Dashboard is the home screen: what you are working on now, how the day is going, and what you have already recorded today.

## When you are not working

![The Dashboard with no session running, showing Ready to work, recent template cards, Today's Progress, Quick Actions, and Today's Work](../Design/Screenshots/01-dashboard.png)

**Ready to work** offers four ways to begin:

- **Start Work** opens a sheet showing your default template, its category, and its task priority, so you can change the category or priority for this session before the timer starts. Set the default template in **Settings › General › Default template**; when that is **Most Recently Used**, the sheet starts from whichever template you used last.
- The chevron beside **Start Work** lists every template and starts one immediately, with that template's own priority.
- **Quick New Task** (<kbd>⌥</kbd><kbd>⌘</kbd><kbd>N</kbd>) starts work without a template: a name, a category, and the two priority values. See [Task Priority](Task%20Priority.md).
- **Recent Templates** shows up to eight cards, most recently used first. One click starts that template.

If you have no templates, **Create Template** and **Quick New Task…** appear instead.

## When you are working

![The Dashboard during a session, showing Currently Working, the live timer, Pause and Finish Work, and a note field](../Design/Screenshots/02-dashboard-active-session.png)

**Currently Working** shows:

| Element | Detail |
| --- | --- |
| State badge | **Working** or **Paused** |
| Template | Icon, name, the session's **Urgent** and **Important** chips, and the template's tags |
| Start time | "Started at 9:22 AM" |
| Timer | Active work, counting up once a second in hours, minutes, and seconds |
| Paused line | "Paused 21m · Wall clock 2h 24m". Shown while the session is paused, and afterwards once the total paused time reaches a minute. |
| **Pause** / **Resume** | Stops or continues the active-time timer |
| **Finish Work** | Ends the session, saves it, then adds it to Calendar |
| Note field | Type and press Add to append a timestamped note |
| **Task Priority** | Changes the category, Urgent, and Important for this session |
| **Change Template** | Moves the session to another template without resetting the timer |
| **Cancel Session…** | Discards the session, after a confirmation |

The session card names the session's category beside its start time. The **⋯** button at the top right repeats Change Template, Change Category and Priority, Add Note, and Cancel Session.

While paused, the timer is dimmed and stops advancing.

## Banners

Banners appear above the cards when something needs your attention.

| Banner | Meaning |
| --- | --- |
| **"*n* work logs aren't in Calendar"** | Some completed sessions failed to sync or their event was deleted. **Review** opens the Calendar section. Your work is saved either way. |
| **"Paused while your Mac was asleep"** | The session was paused automatically because **Pause the session when my Mac sleeps** is on. |
| Storage error | The database could not be opened. New sessions are refused rather than recorded somewhere they would be lost. See [Troubleshooting](Troubleshooting.md). |

**Active Session Detected** appears here after a crash or quit with a session still open. See [Sessions](Sessions.md#recovering-a-session).

## Today's Progress

A ring split by template, the total in the middle, and up to four templates listed beside it with their active time.

Below the ring, **Daily Goal** shows a progress bar and a percentage. Set the goal in **Settings › General › Daily goal** — anything from 1 to 10 hours, or **Off** to hide this part entirely. The goal is measured in active work.

## Quick Actions

Five tiles, two of which depend on whether a session is running:

| Tile | Action |
| --- | --- |
| **Add Note** (while working) or **Quick New Task** (while idle) | Focuses the note field, or opens the Quick New Task sheet |
| **Task Priority** (while working) or **New Template** (while idle) | Changes the session's Urgent and Important, or opens the new-template sheet |
| **Export** | Opens the Excel export sheet |
| **View Calendar** | Opens the Apple Calendar app |
| **Work Logs** | Switches to the Work Logs section |

## Today's Work

Every session that **started** today, oldest first, with its time range and active duration, and a **Total** row at the bottom.

A running session is included and shows "In Progress" instead of a finish time; the total then notes that it includes the session in progress. **View All** opens Work Logs.

A session is counted on the day it started, so work that crosses midnight stays on the earlier day and is not split.

---

[Back to User Guide](README.md) · [Previous: Categories](Categories.md) · [Next: Templates](Templates.md)
