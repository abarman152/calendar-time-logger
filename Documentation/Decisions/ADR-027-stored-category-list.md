# ADR-027 — A stored category list with stable identity

Status: Accepted (partly supersedes [ADR-025](ADR-025-work-categories.md))
Date: 2026-09-17

## Context

[ADR-025](ADR-025-work-categories.md) made a category a name on templates and sessions, with the list derived from the built-ins plus names templates use. That kept history safe, but it made category management thin:

- A category couldn't exist until a template used it, and a custom category vanished as soon as none did, so **Add** and **Delete** had nothing to act on.
- A built-in category could never be removed.
- **Rename** was only offered for categories in use, and nothing explained what happens to templates, work logs, the session in progress, or future sessions.
- The Categories sheet had no way to move templates from one category to another.

Users need to create, rename, migrate, and delete categories safely, without changing what recorded work says.

## Decision

- **Categories are stored records.** Schema version 4 adds `WorkCategoryRecord` (`id: UUID`, `name`, `createdAt`, `modifiedAt`; every property has a default and there are no unique constraints, per [ADR-010](ADR-010-future-icloud-compatibility.md)). `CalendarTimeLoggerSchemaV3` becomes a frozen copy of the 1.3 models, and the plan gains a lightweight V3 → V4 stage. Templates and sessions are unchanged.
- **References stay by name.** A template's `category` still names its category, and a session still keeps the name it was recorded with (ADR-025). A record's `id` gives the category a stable identity: renaming changes the record's name in place, and pickers follow the record through a rename.
- **The list is reconciled, not derived.** `PersistenceService.reconcileCategories()` runs when a store opens and before every category operation. It is idempotent: an empty list (a new install, or a store just migrated from 1.3) gets the built-ins; General is always present; every name a template uses is present; case-only duplicates merge into the oldest record. **Work log names never add records**, so a deleted category stays deleted.
- **Operations**, each committed in one save and rolled back on failure so nothing is half-migrated:
  - `createCategory(named:)` — tidies the name; refuses blanks, names over 40 characters, and case-insensitive duplicates (so a repeated Add can't create a twin). `categoryNamed(_:)` returns an existing category or creates one, for naming a category in place in a picker.
  - `renameCategory(_:to:)` — renames the record and every template using it. Renaming onto an existing name merges into that record. General can't be renamed.
  - `migrateCategory(_:to:)` — moves every template to another category; both categories stay.
  - `deleteCategory(_:migratingTemplatesTo:)` — deletes an unused category directly. A category templates use requires a destination, and its templates move there in the same save as the delete, so no template ever names a deleted category. General can't be deleted. Deleting a category that is already gone does nothing.
- **What never changes:** completed work logs and the open session keep their recorded category through every operation. Analytics and exports report the recorded names. Templates moved by a migration start future sessions in their new category.
- **Usage is computed, not stored.** `CategoryUsage.compute` reports the templates, the number of completed work logs, and whether the open session uses each category. The Categories sheet computes it from live queries, so every change anywhere in the app shows at once.
- **Pickers resolve deletions.** A template's category picker follows a renamed category and falls back to where the template's category went when one is deleted. Session-level pickers (Edit Entry, Change Category and Priority) keep a deleted category's name and label it as deleted, because that name is part of what was recorded.

## Alternatives considered

- **Relationships from templates and sessions to the record.** A session relationship would make a rename rewrite history, and the delete rule would have to decide what happens to sessions of a deleted category. A template relationship was possible but would add a second representation for templates to keep in sync with the name that sessions copy, and a heavier migration. Name references plus a transactional rename keep one representation.
- **Keep the derived list and store only "extra" and "hidden" names in settings.** No schema change, but category changes would span two stores (SwiftData and `UserDefaults`), so a rename or delete couldn't be atomic.
- **Rewrite work logs on rename or delete.** Makes Analytics show one row per category after a rename, but changes recorded history, which the product forbids.

## Consequences

- Categories can exist unused, including built-ins the user keeps, and can be deleted, including built-ins other than General.
- A renamed category still appears under its old name in Analytics for work recorded before the rename (unchanged from ADR-025). Individual logs can be corrected with Edit Entry.
- Existing 1.3 stores migrate without rewriting any row; the category list is filled from the built-ins and the names templates use on first open.
- A future version 5 must freeze the V4 models, as this change froze V3.
- Covered by `CategoryManagementTests` (scenarios A–F: unused delete, delete with one template, migrate many then delete, delete with history only, rename, and relaunch) and `StoreMigrationTests.migratesV3Store`.
