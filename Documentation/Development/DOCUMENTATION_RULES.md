# Documentation Rules

Documentation is part of the product. These rules keep it accurate.

## Where documentation lives

```
/                              README.md and CLAUDE.md only (plus LICENSE, not Markdown)
Documentation/
├── README.md                  index of everything below
├── Architecture/              how the app is built
├── Decisions/                 ADRs, newest last, plus the index (README.md)
├── Design/                    branding, artwork, screenshots
├── Development/               setup, conventions, these rules
├── Product/                   requirements, privacy
├── Releases/                  release process, changelog, versioning
├── Testing/                   strategy, coverage, QA checklists, verification logs
└── User Guide/                how to use the app, written for users
```

- **`README.md` and `CLAUDE.md` stay at the repository root.** Every other Markdown file belongs under `Documentation/` ([ADR-021](../Decisions/ADR-021-documentation-structure.md)).
- New documents go in the folder that matches their purpose; add them to `Documentation/README.md`.
- Release notes go in `Releases/CHANGELOG.md`, decisions in `Decisions/`, and design or artwork notes in `Design/`.
- **`User Guide/` is written for people using the app**, not for contributors: what a control does, what a screen shows, what to do when something fails. Keep architecture, rationale, and build instructions out of it, and link to the owning document instead. Its file names contain spaces, so Markdown links to them are percent-encoded (`User%20Guide/Getting%20Started.md`); `scripts/check-doc-links.sh` decodes them before checking.
- Images live in `Design/Assets` (artwork) or `Design/Screenshots` (captured from the DEBUG demo build, never from real work data).
- **Screenshots must contain no personal data.** Demo mode supplies the work data and, since 1.3, sample calendars instead of the real calendar list. Still check every capture for names, paths, or other personal data before it is committed, and crop if needed. Every screenshot needs descriptive alt text.
- `scripts/check-doc-links.sh` enforces the root rule and checks every relative link; it runs in `scripts/verify.sh --full`.

## The accuracy rule

**Documentation describes what the code actually does, not what we intend to build.**

- Never describe a feature as implemented unless it is merged, builds, and has been tested or manually verified.
- Planned work goes only under **Future / Out of Scope** or `[Unreleased]` headings, and must be labeled as such.
- If something is partial, say what is missing (see the status keys in [PRODUCT_REQUIREMENTS.md](../Product/PRODUCT_REQUIREMENTS.md)).
- Numbers in docs (test counts, versions, limits such as the 500-session reconciliation window) must match the code. Update them in the same change that alters them.
- Use the full product name, **Calendar Time Logger**. `CTL` refers only to the logo artwork and the app's menu bar item (the “CTL item”, [ADR-015](../Decisions/ADR-015-persistent-ctl-menu-bar-item.md)); `calender_time_logger` is only an internal technical identifier.
- Don't use emoji in documentation examples of the app's UI; describe SF Symbols by name.

## Ownership

| Document | Owner | Must be updated when |
| --- | --- | --- |
| [README.md](../../README.md) | Whoever changes user-visible behavior | Features, permissions, requirements, setup, or scope change |
| [CLAUDE.md](../../CLAUDE.md) | Whoever changes conventions or product rules | Layout, rules, or workflow for contributors change |
| [ARCHITECTURE.md](../Architecture/ARCHITECTURE.md) | Whoever changes structure | Layers, services, key types, data flow, persistence, entitlements, or error handling change |
| [PRODUCT_REQUIREMENTS.md](../Product/PRODUCT_REQUIREMENTS.md) | Product owner | A requirement is added, changed, completed, or descoped |
| [DECISIONS.md](../Decisions/README.md) + ADRs | Author of the decision | See [When an ADR is required](#when-an-adr-is-required) |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Whoever changes tooling or layout | Toolchain, folders, conventions, demo mode, scripts, or assets change |
| [BRANDING.md](../Design/BRANDING.md) | Whoever changes artwork or visual identity | Icon, CTL mark, menu bar presentation, or installer artwork change |
| [TESTING.md](../Testing/TESTING.md) | Whoever adds or removes tests | Suites, coverage, test counts, or the QA checklist change |
| [User Guide/](../User%20Guide/README.md) | Whoever changes user-visible behavior | A control, screen, message, default, or keyboard shortcut changes; a screenshot no longer matches the UI |
| [RELEASE.md](../Releases/RELEASE.md) | Release engineer | The release process, packaging, signing, or verification steps change |
| [PRIVACY.md](../Product/PRIVACY.md) | Whoever touches data or permissions | Stored data, Calendar content, permissions, entitlements, or network use change |
| [VERSION.md](../Releases/VERSION.md) | Release engineer | Version, build number, or policy change |
| [CHANGELOG.md](../Releases/CHANGELOG.md) | Every contributor | Every user-visible change |

In a single-maintainer project, the maintainer owns all of these. The table still defines *when* each document must change.

## When README must be updated

- A user-visible feature is added, removed, or changes behavior.
- Calendar, menu bar, template, session, or Work Log behavior changes.
- System requirements, permissions, or setup commands change.
- Scope or roadmap changes.

## When architecture docs must be updated

- A type is added, removed, or renamed in `Domain`, `Persistence`, or `Services`.
- The composition root, scenes, or dependency direction changes.
- Persistence layout, schema version, or migration plan changes.
- Entitlements, Info.plist keys, or platform settings change.
- The error-handling behavior table is no longer true.

## When an ADR is required

Write an ADR in `Documentation/Decisions/` when a change:

- Chooses between viable architectural approaches (framework, persistence, concurrency, module boundaries).
- Changes or relaxes a product rule (for example, allowing multiple active sessions).
- Changes how data is stored, identified, migrated, or synced.
- Adds a third-party dependency.
- Changes how the app interacts with the user's calendars or other external data.
- Introduces a platform-specific trade-off.

### ADR format

File name: `ADR-NNN-short-title.md`, numbered sequentially and never reused. Sections, in order:

```
# ADR-NNN — Title
Status: Proposed | Accepted | Superseded by ADR-XXX | Deprecated
Date: YYYY-MM-DD
## Context
## Decision
## Alternatives considered
## Consequences
```

Accepted ADRs are not rewritten. To change a decision, write a new ADR and mark the old one **Superseded**. Add every ADR to [DECISIONS.md](../Decisions/README.md).

## Changelog rules

- Follow the Keep a Changelog sections: **Added**, **Changed**, **Fixed**, **Removed**, **Security**, **Known Limitations**.
- Write for users: what changed and why it matters, not internal refactors (unless they affect behavior or developers).
- Add entries in the same change that introduces the behavior, under `[Unreleased]`.
- At release, rename `[Unreleased]` to the version with its date.
- Only list what is implemented.

## Versioning rules

Follow [VERSION.md](../Releases/VERSION.md). A version bump, CHANGELOG section, and build settings change happen together.

## Feature documentation rules

A feature is documented when:

1. README describes its user-visible behavior.
2. The [User Guide](../User%20Guide/README.md) page that owns the screen explains how to use it, with a current screenshot where one helps.
3. PRODUCT_REQUIREMENTS marks its status.
4. ARCHITECTURE covers any new service, model, or flow.
5. PRIVACY is updated if it touches data or permissions.
6. CHANGELOG has an entry.

## Testing documentation rules

- New test suites and their coverage are listed in [TESTING.md](../Testing/TESTING.md#coverage), with the total test count kept current.
- Behavior that is not covered by automated tests is listed explicitly under "What is not covered".
- Manual QA steps are added for any feature that can't be unit tested.
- The verification log records what was actually run for the version, with results.

## Release documentation rules

Before a release:

- Read every document in the table above against the build being released.
- Remove or correct any statement that is no longer true.
- Confirm Known Limitations are complete.
- Run `scripts/check-doc-links.sh`.

## Known limitations

- List them in the current version's **Known Limitations** section of [CHANGELOG.md](../Releases/CHANGELOG.md).
- Be specific: what doesn't work, under which conditions, and any workaround.
- Remove a limitation only when the fix ships, and record the fix under **Fixed**.

## Future and out-of-scope features

- Describe them only under headings titled **Future / Out of Scope for V1** (or the equivalent for later versions).
- Never use present tense for them ("will", "planned", not "supports").
- Don't create placeholder code, targets, or settings for them. Architectural preparation is documented in ADRs.

## Internal link validation

- Use relative links between documents (for example `../Decisions/ADR-014-sf-symbols-template-icons.md`).
- `scripts/check-doc-links.sh` verifies that every relative Markdown link points to an existing file. It runs as part of `scripts/verify.sh --full` and must pass before release.
- Anchors (`#section`) are not checked automatically; verify them when renaming headings.
