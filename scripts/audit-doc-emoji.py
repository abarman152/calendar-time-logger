#!/usr/bin/env python3
"""Fails if any Markdown file contains an emoji.

Documentation describes the app's SF Symbols by name and never uses emoji
(see Documentation/Development/DOCUMENTATION_RULES.md). Box-drawing characters,
arrows, and the macOS modifier-key glyphs used in diagrams and shortcuts are
allowed; pictographic characters are not.

Runs as part of scripts/verify.sh --full.
"""
import pathlib
import sys
import unicodedata

# Blocks that contain pictographic emoji.
RANGES = [
    (0x1F000, 0x1FAFF),  # Mahjong through Symbols and Pictographs Extended-A
    (0x1F1E6, 0x1F1FF),  # Regional indicators (flags)
    (0x2300, 0x23FF),    # Miscellaneous Technical (⏸, ⏰, …)
    (0x2600, 0x27BF),    # Miscellaneous Symbols and Dingbats
    (0x2B00, 0x2BFF),    # Miscellaneous Symbols and Arrows
    (0xFE0E, 0xFE0F),    # Variation selectors that force text/emoji presentation
]

# Non-emoji characters from those blocks that documentation legitimately uses.
ALLOWED = set(
    "←↑→↓↔↕↳↲↰↱⇒⇐⇔"          # arrows in flow diagrams
    "⌘⌥⌃⇧⏎⌫⎋"                # macOS modifier keys in shortcuts
    "─│┌┐└┘├┤┬┴┼━┃┏┓┗┛┣┫┳┻╋╭╮╯╰"  # box drawing
    "▀▄█▌▐░▒▓▪▫▬▲►▼◄◆◇○●◦"    # blocks and geometric shapes
)

SKIP_DIRS = {".build", "dist", "node_modules", ".git"}


def offending(char: str) -> bool:
    if char in ALLOWED:
        return False
    code = ord(char)
    return any(low <= code <= high for low, high in RANGES)


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    failures = 0
    scanned = 0
    for doc in sorted(root.rglob("*.md")):
        if SKIP_DIRS & set(doc.relative_to(root).parts):
            continue
        scanned += 1
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            hits = sorted({c for c in line if offending(c)})
            if not hits:
                continue
            failures += 1
            names = ", ".join(f"U+{ord(c):04X} {unicodedata.name(c, '?')}" for c in hits)
            print(f"{doc.relative_to(root)}:{number}: {names}")
            print(f"    {line.strip()[:120]}")

    if failures:
        print(f"\n{failures} line(s) with emoji in {scanned} Markdown files.")
        print("Use professional text or the SF Symbol name instead.")
        return 1
    print(f"No emoji in {scanned} Markdown files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
