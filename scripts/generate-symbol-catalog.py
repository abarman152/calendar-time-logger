#!/usr/bin/env python3
"""Generates the template icon catalog from a curated list of SF Symbols.

Every name is checked against the SF Symbols catalog installed with macOS
(CoreGlyphs `name_availability.plist`). The script fails if a symbol does not
exist or requires a newer macOS than the deployment target, so the app never
ships a symbol name that doesn't render. Search keywords come from the system
catalog's own search terms.

    scripts/generate-symbol-catalog.py          regenerate the Swift file
    scripts/generate-symbol-catalog.py --check  verify only (used by verify.sh --full)
"""
import plistlib
import sys
from pathlib import Path

DEPLOYMENT_MACOS = (27, 0)
GLYPHS = Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
OUTPUT = Path(__file__).resolve().parent.parent / "CalendarTimeLoggerKit/Sources/CalendarTimeLoggerKit/Domain/SymbolCatalog+Generated.swift"

# Curated, ordered categories. Keep outline (non-fill) variants: the app draws
# icons on a tinted tile, where outline symbols read best at small sizes.
CATEGORIES = [
    ("development", "Development", [
        "laptopcomputer", "desktopcomputer", "chevron.left.forwardslash.chevron.right", "terminal",
        "curlybraces", "curlybraces.square", "apple.terminal", "cpu", "memorychip", "server.rack",
        "externaldrive", "internaldrive", "cloud", "network", "antenna.radiowaves.left.and.right",
        "gearshape", "gearshape.2", "hammer", "wrench.and.screwdriver", "ladybug", "ant",
        "swift", "command", "keyboard", "app.connected.to.app.below.fill", "square.stack.3d.up",
        "point.3.connected.trianglepath.dotted", "arrow.triangle.branch", "arrow.triangle.merge",
        "shippingbox", "cube", "puzzlepiece.extension",
    ]),
    ("education", "Education", [
        "book", "book.closed", "books.vertical", "text.book.closed", "graduationcap", "backpack",
        "studentdesk", "pencil.and.ruler", "ruler", "character.book.closed", "abc", "function",
        "sum", "percent", "x.squareroot", "globe", "globe.americas", "brain.head.profile",
        "lightbulb", "list.bullet.clipboard", "rectangle.and.pencil.and.ellipsis", "a.book.closed",
    ]),
    ("research", "Research", [
        "flask", "testtube.2", "atom", "text.magnifyingglass", "magnifyingglass", "doc.text.magnifyingglass",
        "chart.xyaxis.line", "chart.line.uptrend.xyaxis", "chart.dots.scatter", "waveform.path.ecg",
        "binoculars", "scope", "leaf", "globe.europe.africa", "sparkle.magnifyingglass",
        "questionmark.circle", "lightbulb.max", "brain",
    ]),
    ("writing", "Writing", [
        "pencil", "pencil.line", "square.and.pencil", "highlighter", "pencil.tip", "pencil.and.scribble",
        "scribble", "signature", "text.alignleft", "text.quote", "textformat", "doc.text",
        "doc.richtext", "note.text", "newspaper", "book.pages", "quote.opening", "character.cursor.ibeam",
        "list.bullet", "list.number", "text.page",
    ]),
    ("design", "Design", [
        "paintbrush", "paintbrush.pointed", "paintpalette", "swatchpalette", "eyedropper",
        "wand.and.stars", "sparkles", "photo.artframe", "square.on.circle", "circle.hexagongrid",
        "rectangle.3.group", "square.grid.3x3", "cube.transparent", "rotate.3d", "lasso",
        "crop", "slider.horizontal.3", "camera.filters", "pencil.and.outline", "ruler.fill",
        "rectangle.and.hand.point.up.left",
    ]),
    ("business", "Business", [
        "briefcase", "building.2", "building.columns", "chart.bar", "chart.pie", "chart.bar.doc.horizontal",
        "person.line.dotted.person", "person.3", "signature", "target", "flag", "trophy",
        "megaphone", "storefront", "cart", "bag", "tag", "creditcard", "doc.plaintext",
        "rectangle.3.group.bubble", "list.bullet.rectangle",
    ]),
    ("communication", "Communication", [
        "envelope", "tray", "paperplane", "message", "bubble.left.and.bubble.right", "phone",
        "video", "person.wave.2", "quote.bubble", "bubble.left", "at", "megaphone",
        "bell", "mic", "headphones", "person.2.wave.2", "shared.with.you", "antenna.radiowaves.left.and.right.circle",
    ]),
    ("productivity", "Productivity", [
        "checkmark.circle", "checklist", "list.bullet.clipboard", "calendar", "calendar.badge.clock",
        "clock", "timer", "stopwatch", "hourglass", "alarm", "target", "flag.checkered",
        "bolt", "square.grid.2x2", "rectangle.stack", "tray.full", "pin", "bookmark",
        "star", "arrow.clockwise", "repeat", "calendar.day.timeline.left",
    ]),
    ("files", "Files", [
        "folder", "folder.badge.gearshape", "doc", "doc.on.doc", "archivebox", "tray.2",
        "externaldrive.connected.to.line.below", "paperclip", "link", "square.and.arrow.down",
        "square.and.arrow.up", "doc.zipper", "tablecells", "list.bullet.below.rectangle",
        "folder.badge.person.crop", "icloud", "externaldrive.badge.icloud",
    ]),
    ("media", "Media", [
        "camera", "photo", "photo.on.rectangle", "film", "video", "play.rectangle", "music.note",
        "music.note.list", "guitars", "pianokeys", "headphones", "speaker.wave.2", "mic",
        "waveform", "tv", "sparkles.tv", "gamecontroller", "radio", "theatermasks",
    ]),
    ("finance", "Finance", [
        "dollarsign.circle", "eurosign.circle", "sterlingsign.circle", "yensign.circle", "indianrupeesign.circle",
        "banknote", "creditcard", "chart.line.uptrend.xyaxis", "chart.pie", "building.columns",
        "wallet.bifold", "percent", "sum", "cart", "bag", "receipt", "chart.bar.xaxis",
    ]),
    ("health", "Health", [
        "heart", "heart.text.square", "cross.case", "pills", "stethoscope", "figure.walk",
        "figure.run", "figure.yoga", "figure.strengthtraining.traditional", "dumbbell", "bicycle",
        "bed.double", "fork.knife", "cup.and.saucer", "drop", "lungs", "brain.head.profile",
        "leaf", "moon.zzz", "figure.mind.and.body",
    ]),
    ("travel", "Travel", [
        "airplane", "car", "bus", "tram", "train.side.front.car", "ferry", "bicycle", "map",
        "mappin.and.ellipse", "location", "globe.asia.australia", "suitcase", "suitcase.rolling",
        "bed.double", "tent", "mountain.2", "beach.umbrella", "fuelpump", "signpost.right",
    ]),
    ("tools", "Tools", [
        "hammer", "wrench.adjustable", "screwdriver", "wrench.and.screwdriver", "gearshape",
        "scissors", "ruler", "level", "paintbrush.pointed", "eyedropper", "flashlight.on.fill",
        "wrench", "powerplug", "bolt", "magnifyingglass", "slider.horizontal.3", "hammer.circle",
    ]),
    ("system", "System", [
        "gearshape", "switch.2", "slider.horizontal.3", "power", "lock", "key", "shield",
        "checkmark.shield", "exclamationmark.triangle", "info.circle", "bell", "wifi",
        "battery.100percent", "display", "macwindow", "menubar.rectangle", "sidebar.left",
        "square.grid.2x2", "arrow.triangle.2.circlepath", "icloud",
    ]),
    ("people", "People", [
        "person", "person.2", "person.3", "person.crop.circle", "person.crop.square",
        "person.badge.plus", "person.2.badge.gearshape", "figure.stand", "figure.wave",
        "figure.2", "figure.and.child.holdinghands", "hands.sparkles", "hand.raised",
        "hand.thumbsup", "person.bubble", "person.text.rectangle", "person.crop.rectangle.stack",
    ]),
    ("objects", "Objects", [
        "lightbulb", "gift", "cup.and.saucer", "mug", "book.closed", "backpack", "key", "lock",
        "house", "building", "sofa", "lamp.desk", "bag", "cart", "clock", "alarm", "umbrella",
        "puzzlepiece", "die.face.5", "crown", "graduationcap", "trophy", "balloon",
    ]),
    ("nature", "Nature", [
        "leaf", "tree", "camera.macro", "sun.max", "moon", "moon.stars", "cloud.sun", "cloud.rain",
        "snowflake", "wind", "flame", "drop", "bolt", "mountain.2", "globe.americas", "pawprint",
        "bird", "fish", "tortoise", "hare", "ladybug", "carrot", "sparkles",
    ]),
]


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


def load(name):
    with open(GLYPHS / name, "rb") as handle:
        return plistlib.load(handle)


def main():
    availability = load("name_availability.plist")
    symbols = availability["symbols"]
    releases = availability["year_to_release"]
    search = load("symbol_search.plist")

    errors = []
    for _, title, names in CATEGORIES:
        seen = set()
        for name in names:
            if name in seen:
                errors.append(f"{title}: duplicate {name}")
            seen.add(name)
            year = symbols.get(name)
            if year is None:
                errors.append(f"{title}: '{name}' is not in the installed SF Symbols catalog")
                continue
            macos = releases.get(year, {}).get("macOS")
            if macos is None or version_tuple(macos) > DEPLOYMENT_MACOS:
                errors.append(f"{title}: '{name}' requires macOS {macos}")
    if errors:
        print("\n".join(errors))
        sys.exit(1)

    lines = [
        "// Generated by scripts/generate-symbol-catalog.py. Do not edit by hand.",
        "// Every name was validated against the installed SF Symbols catalog",
        f"// (available on macOS {DEPLOYMENT_MACOS[0]}.{DEPLOYMENT_MACOS[1]} or earlier).",
        "",
        "extension SymbolCatalog {",
        "    static let generatedCategories: [SymbolCategory] = [",
    ]
    for key, title, names in CATEGORIES:
        lines.append(f'        SymbolCategory(id: "{key}", title: "{title}", symbols: [')
        for name in names:
            keywords = sorted({k.lower() for k in search.get(name, []) if k and '"' not in k and "\\" not in k})
            keyword_list = ", ".join(f'"{k}"' for k in keywords)
            lines.append(f'            SymbolEntry(name: "{name}", keywords: [{keyword_list}]),')
        lines.append("        ]),")
    lines += ["    ]", "}", ""]
    generated = "\n".join(lines)

    if "--check" in sys.argv:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if current != generated:
            print(f"{OUTPUT.name} is out of date. Run scripts/generate-symbol-catalog.py.")
            sys.exit(1)
        total = sum(len(names) for _, _, names in CATEGORIES)
        print(f"Symbol catalog is current: {total} entries in {len(CATEGORIES)} categories, all valid.")
        return

    OUTPUT.write_text(generated)
    total = sum(len(names) for _, _, names in CATEGORIES)
    print(f"Wrote {OUTPUT.name}: {total} entries in {len(CATEGORIES)} categories.")


if __name__ == "__main__":
    main()
