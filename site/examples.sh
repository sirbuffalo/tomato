#!/bin/sh
# Writes site/examples.json (name -> source) from examples/*.tom, for the Run page's example menu.
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/site/examples.json"
printf '{' > "$out"; first=1
for f in "$root"/examples/*.tom; do
  name="$(basename "$f" .tom)"
  case "$name" in mathlib|http_get) continue ;; esac   # mathlib needs an LLVM file the page does not offer; http_get needs a network
  [ $first = 1 ] || printf ',' >> "$out"; first=0
  printf '\n  "%s": "' "$name" >> "$out"
  awk 'BEGIN{ORS=""} { gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); print $0 "\\n" }' "$f" >> "$out"
  printf '"' >> "$out"
done
printf '\n}\n' >> "$out"
