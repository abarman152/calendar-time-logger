# Version

| Field | Value |
| --- | --- |
| **Current version** | **1.4.0** |
| Build number | 6 |
| Status | Packaged as a DMG on 2026-09-17; not notarized, not publicly distributed |
| Release name | Calendar Time Logger 1.4 |

1.4.0 is a MINOR release: backward-compatible features (category management with a stored category list, the Calendar event boundaries setting, clearer task priority) and fixes (the Edit and Delete audit). The persisted schema moves to version 4, which adds the `WorkCategoryRecord` entity; the V3 to V4 migration is lightweight and no template or work log is rewritten ([ADR-027](../Decisions/ADR-027-stored-category-list.md)). Build 6 follows build 5, which is 1.3.0 and was already installed, so the unreleased work could not keep 1.3.0 (5) without two incompatible stores sharing one version.

1.3.0 was a MINOR release: backward-compatible features (template and session categories, category analytics, category-aware Work Logs, a Category export column). The persisted schema moved to version 3, which added `category` to templates and sessions as a non-optional value defaulting to `General`; the migration is lightweight and no existing data is rewritten ([ADR-025](../Decisions/ADR-025-work-categories.md)). Build 5 follows build 4.

1.2.0 was a MINOR release: backward-compatible features (task priority tracking, Quick New Task, priority analytics, selectable Excel export columns, the CTL menu bar mark). The persisted schema moves to version 2, which adds `isUrgent` and `isImportant` to templates and sessions as non-optional values defaulting to `false`; the migration is lightweight and no existing data is rewritten ([ADR-022](../Decisions/ADR-022-task-priority-model.md)). Build 4 follows build 3, which was the first packaged as a DMG.

1.1.0 was a MINOR release (SF Symbols icons, CTL menu bar item, menu bar backgrounds, Excel export) and was never distributed; its 1.0 icon conversion still runs at launch ([ADR-014](../Decisions/ADR-014-sf-symbols-template-icons.md)).

The version lives in the Xcode target build settings:

- `MARKETING_VERSION` → `CFBundleShortVersionString` (currently `1.4.0`)
- `CURRENT_PROJECT_VERSION` → `CFBundleVersion` (currently `6`)

Both Debug and Release configurations must always carry the same values.

## Policy: Semantic Versioning

`MAJOR.MINOR.PATCH`

| Part | Bump when | Examples |
| --- | --- | --- |
| **MAJOR** | A change breaks existing user data, workflows, or a product rule; or a new platform generation (see roadmap) changes the product's scope | Incompatible store migration; V2 iCloud sync |
| **MINOR** | Backward-compatible features | New analytics view, new menu bar display mode |
| **PATCH** | Backward-compatible fixes with no new features | Timer rounding fix, copy change, crash fix |

Planned generations follow the roadmap: V2 iCloud sync (2.0.0), V3 iPhone and iPad (3.0.0), V4 Apple Watch (4.0.0). These are intentions, not commitments.

## Build numbers

- An integer that **increases with every build uploaded or distributed**, and is never reused.
- It doesn't reset when the marketing version changes.
- Local development builds don't need a new build number.

## Pre-releases

- Use `MAJOR.MINOR.PATCH-beta.N` or `-rc.N` in `CHANGELOG.md` and release notes (for example `1.1.0-beta.1`).
- `MARKETING_VERSION` stays numeric (`1.1.0`) because `CFBundleShortVersionString` doesn't allow suffixes. The build number distinguishes pre-releases.

## Changelog rules

- Every version bump has a matching `## [x.y.z]` section in [CHANGELOG.md](CHANGELOG.md) before release.
- Unreleased work goes under `## [Unreleased]` until it's assigned a version.
- See [DOCUMENTATION_RULES.md](../Development/DOCUMENTATION_RULES.md#changelog-rules).

## Schema versions

The persisted schema has its own version (`CalendarTimeLoggerSchemaV1`, `1.0.0`). It changes only when stored models change, and any change requires a migration stage and an ADR. 1.1.0 didn't change it. Value-level data changes (the icon conversion) and JSON configuration versions (`MenuBarConfiguration` `"version": 2`) are documented in the ADR that introduces them.
