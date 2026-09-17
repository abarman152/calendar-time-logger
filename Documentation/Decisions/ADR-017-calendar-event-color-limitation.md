# ADR-017 — Calendar event color follows the calendar

Status: Accepted
Date: 2026-09-16

## Context

The redesign asked for per-template Calendar event colors ("System / Calendar color" or "Template color"), with the instruction not to fake it if EventKit can't do it. The macOS 27 SDK was inspected: `EKCalendar` has `color` and `cgColor`; `EKEvent` and `EKCalendarItem` have **no color property**. Apple Calendar draws every event in its calendar's color.

## Decision

- No per-event color setting is offered or stored. The template editor's **Calendar Event Appearance** card shows the color of the calendar the template's events will use, explains the limitation, and suggests choosing a calendar with the wanted color. It offers **Match Icon Color to Calendar**, which changes only the template's color inside Calendar Time Logger.
- Settings › Calendar states that event color is set by each event's calendar.
- Calendar Time Logger doesn't change calendar colors.

## Alternatives considered

- **Setting `EKCalendar.color`.** Supported, but it recolors every event in that calendar, including events the app didn't create, and may sync to the user's other devices. That contradicts [ADR-006](ADR-006-eventkit-abstraction-and-ownership.md), which limits the app to changing only its own events.
- **Creating a calendar per template.** Would give distinct colors, but adds calendars to the user's accounts without being asked. It could be offered as an explicit opt-in in a future version.
- **Storing an unused event color for later.** Would be a setting that does nothing.

## Consequences

- No misleading control. Future support needs only a new field in the template's JSON configuration, which decodes tolerantly, so no schema change.
