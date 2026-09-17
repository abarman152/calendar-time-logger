# ADR-021 — Documentation lives in Documentation/

Status: Accepted
Date: 2026-09-16

## Context

Ten Markdown files sat at the repository root (architecture, changelog, decisions index, development, documentation rules, privacy, product requirements, release, testing, version), next to `README.md`. The root was noisy, related documents weren't grouped, and there was no single entry point into the documentation.

## Decision

- The repository root keeps exactly two Markdown files: **`README.md`** (the public entry point) and **`CLAUDE.md`** (instructions for AI assistants and contributors).
- Everything else lives under `Documentation/`, grouped by purpose: `Architecture/`, `Decisions/`, `Design/`, `Development/`, `Product/`, `Releases/`, `Testing/`. `Documentation/README.md` indexes them, and the ADR index moved from `DECISIONS.md` to `Documentation/Decisions/README.md`.
- File names are unchanged, so existing references and search habits still work.
- Every relative link was rewritten for the new locations, and `scripts/check-doc-links.sh` now enforces both rules: only those two Markdown files at the root, and every relative link resolves. It runs in `scripts/verify.sh --full`.

## Alternatives considered

- **Leaving the files at the root.** No moving cost, but the root stays cluttered and unrelated documents sit together.
- **Renaming files to lowercase topic names** (`architecture.md`). Tidier, but it breaks every existing link and bookmark for no functional gain.
- **A documentation site generator.** Overkill for a single-maintainer project, and it would add a toolchain to keep working.

## Consequences

- The root lists source, project, scripts, and two Markdown files.
- New documentation has an obvious home, and the rules for where things belong are in `Documentation/Development/DOCUMENTATION_RULES.md`.
- Links are checked automatically, so moves can't silently break them.
