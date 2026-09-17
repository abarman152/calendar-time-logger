# ADR-025 — Categories as a name captured per session

Status: Accepted; the derived category list is superseded by [ADR-027](ADR-027-stored-category-list.md)
Date: 2026-09-16

## Context

Users want to group work above the level of a template ("Development" covers Software Engineering, code reviews, and quick hotfixes) and see time by that grouping in Work Logs, Analytics, and exports. Every template must have a category, existing templates and work logs must keep working, and changing a template's category later must never change what history says.

Task priority already solved the same history problem by copying the template's values onto each session when it starts ([ADR-022](ADR-022-task-priority-model.md)). Template names, icons, and colors are snapshotted the same way ([ADR-004](ADR-004-worksession-source-of-truth.md)).

## Decision

- **A category is a name, not an entity.** `WorkTemplate.category` and `WorkSession.category` are non-optional `String` attributes defaulting to `"General"`. There is no `Category` model and no relationship.
- **The session owns its value.** Starting a session copies the template's category (or one chosen for that session) onto the session. Editing, renaming, or changing a template's category affects only sessions started afterwards. A completed work log's category changes only through **Edit Entry**.
- **Moving a session to another template** (Change Template, live or on a completed log) moves an *inherited* category — one still equal to the previous template's — and keeps one the user chose.
- **Identity is case-insensitive.** `WorkCategory.key` lowercases a whitespace-normalized name. When a name is saved, it takes the spelling already in use by a built-in category or another template, so "research" joins "Research" instead of creating a twin.
- **The list is derived** *(superseded by [ADR-027](ADR-027-stored-category-list.md), which stores the list with stable identities and adds create, migrate, and delete)*. Pickers offer six built-in categories (Development, Education, Research, Content, Design, General) plus every name a template uses. Adding a category is naming it on a template; a custom category no template uses disappears from the list on its own, so there is no delete operation. `PersistenceService.renameCategory` renames on templates only.
- **Validation.** A template's category must be non-blank and at most 40 characters (`TemplateValidationError.invalidCategory`). Session values are stored through `WorkCategory.stored`, so a session can never hold a blank category.
- **Analytics group by the recorded value** (`WorkAnalytics.categoryTotals`), in one pass over the logs already limited to the selected range, with template and priority totals nested per category.
- **Schema version 3** adds the two attributes. `CalendarTimeLoggerSchemaV2` becomes a frozen copy of the 1.2 models (as V1 is of 1.1), and the plan gains a lightweight V2 → V3 stage. Existing rows read `"General"`; nothing else is rewritten.

## Alternatives considered

- **A `Category` model with a relationship from templates and sessions.** Gives rename-everywhere and explicit management, but a relationship from sessions would make a rename rewrite history, which is the one thing the product forbids; avoiding that needs a snapshot anyway. It also adds a delete rule question (what happens to sessions of a deleted category), a unique-name constraint CloudKit cannot enforce ([ADR-010](ADR-010-future-icloud-compatibility.md)), and a heavier migration.
- **A fixed enum of categories.** Simple and fully predictable, but users' work doesn't fit one taxonomy, and adding a category would need an app update.
- **Deriving a log's category from its template at display time.** No migration for sessions, but violates the history rule and breaks for deleted templates and quick tasks.
- **Optional category (`String?`).** Would allow an "uncategorized" state the requirements rule out, and push nil handling into every view, filter, and export.

## Consequences

- Recorded work keeps its category through template edits, renames, and deletions, and quick tasks have one too.
- Renaming a category splits Analytics into old and new names for the affected period. This is intended: the report shows what was recorded. Individual logs can be corrected with Edit Entry; there is no bulk "rename in history".
- A typo on a template creates a new category until corrected; the canonical-spelling rule prevents case-only duplicates.
- Existing users see all templates and work logs in **General** after upgrading, until they set template categories.
- A future version 4 must freeze the V3 models, as this change froze V2.
