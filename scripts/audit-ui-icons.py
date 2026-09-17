#!/usr/bin/env python3
"""Audits UI iconography in the app and package sources.

1. Every SF Symbol name written as a literal (`systemImage: "…"`,
   `systemName: "…"`, `Image(systemName: "…")`, `symbol: "…"`, and the
   symbol tables in `AppSection`/`SettingsPane`) must exist in the SF Symbols
   catalog installed with macOS and be available on the deployment target.
2. No emoji may appear in Swift sources, except in the 1.0 emoji → symbol
   migration table and the DEBUG demo code that simulates 1.0 data.

    scripts/audit-ui-icons.py     (part of scripts/verify.sh --full)
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "calender_time_logger/calender_time_logger", ROOT / "CalendarTimeLoggerKit/Sources"]
GLYPHS = Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
DEPLOYMENT = (27, 0)
# Files allowed to contain emoji: legacy data mapping and DEBUG-only legacy seeding.
EMOJI_ALLOWED = {"SymbolCatalog.swift", "DemoMode.swift"}

SYMBOL_PATTERNS = [
    re.compile(r'(?:systemImage|systemName|symbolName|symbol|systemImageName)\s*:\s*"([a-z0-9.]+)"'),
    re.compile(r'Image\(systemName:\s*"([a-z0-9.]+)"\)'),
    re.compile(r'case \.[A-Za-z]+:\s*"([a-z0-9]+(?:\.[a-z0-9]+)+|[a-z]+)"'),
]
# `case .x: "…"` also matches ordinary strings; only names containing a dot or
# listed below are treated as symbols from those tables.
PLAIN_SYMBOLS = {"house", "calendar", "gearshape", "clock", "timer", "power", "tag", "bolt"}


def is_emoji(ch):
    cp = ord(ch)
    return cp >= 0x1F000 or 0x2600 <= cp <= 0x27BF or cp in (0xFE0F, 0x23F0, 0x23F1, 0x23F8, 0x2328)


def main():
    with open(GLYPHS, "rb") as handle:
        availability = plistlib.load(handle)
    symbols, releases = availability["symbols"], availability["year_to_release"]

    problems, checked = [], set()
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            if path.name.endswith("+Generated.swift"):
                continue  # validated by generate-symbol-catalog.py --check
            text = path.read_text()
            rel = path.relative_to(ROOT)
            for number, line in enumerate(text.splitlines(), 1):
                if path.name not in EMOJI_ALLOWED and any(is_emoji(ch) for ch in line):
                    problems.append(f"{rel}:{number}: emoji in source: {line.strip()[:80]}")
                for index, pattern in enumerate(SYMBOL_PATTERNS):
                    for name in pattern.findall(line):
                        if index == 2 and "." not in name and name not in PLAIN_SYMBOLS:
                            continue
                        checked.add(name)
                        year = symbols.get(name)
                        if year is None:
                            problems.append(f"{rel}:{number}: unknown SF Symbol '{name}'")
                            continue
                        macos = releases.get(year, {}).get("macOS", "99")
                        if tuple(int(p) for p in macos.split(".")) > DEPLOYMENT:
                            problems.append(f"{rel}:{number}: '{name}' needs macOS {macos}")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"UI icon audit passed: {len(checked)} SF Symbol names valid on macOS {DEPLOYMENT[0]}.{DEPLOYMENT[1]}; no emoji in UI sources.")


if __name__ == "__main__":
    main()
