#!/bin/zsh
# Verifies the documentation layout and links:
#   - Only README.md and CLAUDE.md are Markdown files at the repository root;
#     all other documentation lives under Documentation/.
#   - Every relative Markdown link points to a file that exists.
# External (http/https/mailto) links and pure #anchors are skipped.
set -uo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
failures=0
checked=0

for doc in *.md(N); do
  if [[ "$doc" != "README.md" && "$doc" != "CLAUDE.md" ]]; then
    print "Documentation file at the repository root: $doc (move it under Documentation/)"
    failures=$((failures + 1))
  fi
done

# All Markdown except build output.
for doc in **/*.md(N); do
  [[ "$doc" == .build/* || "$doc" == dist/* || "$doc" == */.build/* ]] && continue
  dir="${doc:h}"
  # Extract link targets from [text](target). Note: `path` is reserved in zsh
  # (it mirrors $PATH), so link variables use other names.
  links=$(grep -oE '\]\([^)]+\)' "$doc" | sed -E 's/^\]\(([^)]+)\)$/\1/') || true
  for target in ${(f)links}; do
    [[ -z "$target" ]] && continue
    [[ "$target" == http* || "$target" == mailto:* || "$target" == \#* ]] && continue
    link_file="${target%%#*}"
    link_file="${link_file%% *}"
    # Markdown links percent-encode spaces (User%20Guide); compare against the real path.
    link_file="${link_file//\%20/ }"
    checked=$((checked + 1))
    if [[ ! -e "$dir/$link_file" ]]; then
      print "Broken link in $doc: $target"
      failures=$((failures + 1))
    fi
  done
done

if (( checked == 0 )); then
  print "No links were checked; the link extraction is broken."
  exit 1
fi
if (( failures > 0 )); then
  print "$failures documentation problem(s); $checked relative links checked."
  exit 1
fi
print "Documentation layout is valid and all $checked relative documentation links resolve."
