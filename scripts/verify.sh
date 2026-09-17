#!/bin/zsh
# Builds and tests Calendar Time Logger.
#
#   scripts/verify.sh            unit tests + Debug app build
#   scripts/verify.sh --full     also audits icons and the SF Symbols catalog, runs the
#                                static analyzer and a Release build, and checks the
#                                documentation layout, links, and absence of emoji
#
# Uses DEVELOPER_DIR if set, otherwise the Xcode selected by xcode-select.
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED="${DERIVED_DATA:-$ROOT/.build/DerivedData}"
PROJECT="$ROOT/calender_time_logger/calender_time_logger.xcodeproj"
SCHEME="calender_time_logger"

step() { print -P "\n%F{blue}==>%f %B$1%b" }

step "Core package tests (swift test)"
(cd "$ROOT/CalendarTimeLoggerKit" && swift test)

step "App build (Debug)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates build | grep -E "warning:|error:|BUILD" || true

if [[ "${1:-}" == "--full" ]]; then
  step "SF Symbols catalog (validated against the installed SF Symbols)"
  /usr/bin/python3 "$ROOT/scripts/generate-symbol-catalog.py" --check

  step "UI icons (SF Symbols valid, no emoji)"
  /usr/bin/python3 "$ROOT/scripts/audit-ui-icons.py"

  step "Static analysis"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates analyze | grep -E "warning:|error:|ANALYZE" || true

  step "App build (Release)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates build | grep -E "warning:|error:|BUILD" || true

  step "Documentation links"
  "$ROOT/scripts/check-doc-links.sh"

  step "Documentation (no emoji in Markdown)"
  /usr/bin/python3 "$ROOT/scripts/audit-doc-emoji.py"
fi
