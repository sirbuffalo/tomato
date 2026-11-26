#!/bin/sh
# Writes the "## vVERSION snapshot" section of docs/performance.md from the last benchmark run
# (benchmarks/results/results.{json,md}; instructions.md when it was made for this VERSION; and, when release/release.sh ran the
# Linux step, benchmarks/results/linux-x86_64/{results.json,results.md,instructions.md}).
# The section holds the median seconds per program and Tomato's time divided by each language's time (below 1.0 Tomato is
# faster, above 1.0 slower), with the Linux x86-64 columns next to the Mac ones. The previous newest snapshot is marked
# "(earlier)"; running this twice replaces its own section.
# Usage: release/perf-snapshot.sh VERSION [DOC]   (DOC defaults to docs/performance.md)
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] || { echo "usage: $0 VERSION [DOC]" >&2; exit 2; }
version="$1"; doc="${2:-$root/docs/performance.md}"
res="$root/benchmarks/results"; lin="$res/linux-x86_64"
[ -f "$res/results.md" ] && [ -f "$res/results.json" ] || { echo "error: no benchmark results in $res" >&2; exit 1; }
[ -f "$doc" ] || { echo "error: $doc not found" >&2; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
jget() { sed -n "s/.*\"$2\": *\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$1" | head -1; }   # FILE KEY
[ "$(jget "$res/results.json" tomato)" = "$version" ] || { echo "error: benchmarks/results is for Tomato v$(jget "$res/results.json" tomato), not v$version" >&2; exit 1; }
have_linux=0
if [ -f "$lin/results.json" ] && [ -f "$lin/results.md" ]; then
  if [ "$(jget "$lin/results.json" tomato)" = "$version" ]; then have_linux=1; else echo "note: $lin is for another version; left out" >&2; fi
fi
# the Tomato column of the seconds table (release mode)
secs_of() { awk -F'|' '/^\| benchmark \| input \| tomato \(s\)/ { t = 1; next } t && /^\| ---/ { next } t && /^\| / { gsub(/ /, "", $2); gsub(/ /, "", $4); printf "%s%s %s", (n++ ? ", " : ""), $2, $4; next } t { exit }' "$1"; }
# a ratio table (benchmark, ÷ go, ÷ rust, ÷ python) from FILE, after the line matching PATTERN: rows only, "name|go|rust|python"
ratio_rows() { awk -F'|' -v pat="$2" '$0 ~ pat { t = 1; next } t && /^\| / && !/^\| (benchmark|---)/ { for (i = 2; i <= 5; i++) gsub(/^ +| +$/, "", $i); print $2 "|" $3 "|" $4 "|" $5; n++; next } t && n { exit }' "$1"; }
# join two row files on the benchmark name: "name|a|b|c" + "name|d|e|f" -> a markdown row; empty cells for a missing row
join_rows() { awk -F'|' 'NR == FNR { m[$1] = $2 "|" $3 "|" $4; next } { o = ($1 in m) ? m[$1] : "n/a|n/a|n/a"; split($2 "|" $3 "|" $4, a, "|"); split(o, b, "|"); printf "| %s | %s | %s | %s | %s | %s | %s |\n", $1, a[1], a[2], a[3], b[1], b[2], b[3] }' "$2" "$1"; }   # FIRST-file SECOND-file
mac_secs="$(secs_of "$res/results.md")"
[ -n "$mac_secs" ] || { echo "error: cannot read the seconds table from results.md" >&2; exit 1; }
ratio_rows "$res/results.md" "^Tomato.s time divided by" > "$work/mac_t"
[ "$(wc -l < "$work/mac_t")" -ge 4 ] || { echo "error: cannot read the ratio table from results.md" >&2; exit 1; }
{
  echo "## v$version snapshot"
  echo
  echo "v$version, median of $(jget "$res/results.json" runs) runs per program (Python too), all runs in one shuffled order (seed $(jget "$res/results.json" seed)), $(jget "$res/results.json" cpu), load average (1, 5 and 15 minutes) $(jget "$res/results.json" load_before) before and $(jget "$res/results.json" load_after) after. Written by \`release/perf-snapshot.sh\` from \`benchmarks/results/results.md\`, which has the full tables. Seconds (release mode): $mac_secs."
  echo
  if [ $have_linux = 1 ]; then
    ratio_rows "$lin/results.md" "^Tomato.s time divided by" > "$work/lin_t"
    echo "Linux x86-64 (\`benchmarks/results/linux-x86_64/results.md\`): $(jget "$lin/results.json" cpu), $(jget "$lin/results.json" cores) cores, median of $(jget "$lin/results.json" runs) runs, seed $(jget "$lin/results.json" seed), load average $(jget "$lin/results.json" load_before) before and $(jget "$lin/results.json" load_after) after (a shared machine: read its times with that load in mind). Seconds (release mode): $(secs_of "$lin/results.md")."
    echo
    echo "Tomato's time divided by each language's time (below 1.0 Tomato is faster, above 1.0 it is slower):"
    echo
    echo "| benchmark | Tomato ÷ Go (Mac) | Tomato ÷ Rust (Mac) | Tomato ÷ Python (Mac) | Tomato ÷ Go (Linux) | Tomato ÷ Rust (Linux) | Tomato ÷ Python (Linux) |"
    echo "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"
    join_rows "$work/mac_t" "$work/lin_t"
  else
    echo "Tomato's time divided by each language's time (below 1.0 Tomato is faster, above 1.0 it is slower):"
    echo
    echo "| benchmark | Tomato ÷ Go | Tomato ÷ Rust | Tomato ÷ Python |"
    echo "| --- | ---: | ---: | ---: |"
    awk -F'|' '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }' "$work/mac_t"
  fi
  ic="$res/instructions.md"; lic="$lin/instructions.md"
  mac_ic=0; lin_ic=0
  [ -f "$ic" ] && grep -q "^Tomato v$version " "$ic" && mac_ic=1
  [ $have_linux = 1 ] && [ -f "$lic" ] && grep -q "^Tomato v$version " "$lic" && lin_ic=1
  if [ $mac_ic = 1 ] && [ $lin_ic = 1 ]; then
    ratio_rows "$ic" "^Tomato.s instructions divided by" > "$work/mac_i"; ratio_rows "$lic" "^Tomato.s instructions divided by" > "$work/lin_i"
    echo
    echo "Instructions executed (deterministic, \`benchmarks/count.sh\`, callgrind), Tomato's count divided by each language's (below 1.0 Tomato executes fewer): arm64 in a Linux VM on the Mac, and x86-64 on the Linux machine."
    echo
    echo "| benchmark | Tomato ÷ Go (arm64) | Tomato ÷ Rust (arm64) | Tomato ÷ Python (arm64) | Tomato ÷ Go (x86-64) | Tomato ÷ Rust (x86-64) | Tomato ÷ Python (x86-64) |"
    echo "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"
    join_rows "$work/mac_i" "$work/lin_i"
  elif [ $mac_ic = 1 ] || [ $lin_ic = 1 ]; then
    f="$ic"; [ $lin_ic = 1 ] && f="$lic"
    ratio_rows "$f" "^Tomato.s instructions divided by" > "$work/one_i"
    echo
    echo "Instructions executed (deterministic, \`benchmarks/count.sh\`, callgrind$([ $lin_ic = 1 ] && echo ', Linux x86-64' || echo ', arm64 Linux VM')), Tomato's count divided by each language's (below 1.0 Tomato executes fewer):"
    echo
    echo "| benchmark | Tomato ÷ Go | Tomato ÷ Rust | Tomato ÷ Python |"
    echo "| --- | ---: | ---: | ---: |"
    awk -F'|' '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }' "$work/one_i"
  fi
  echo
} > "$work/section"
# drop an older section for this very version, mark the other snapshots "(earlier)", put the new one first
awk -v v="$version" '
  $0 ~ "^## v" v " snapshot" { skip = 1; next }
  /^## / { skip = 0 }
  skip { next }
  /^## v[0-9A-Za-z.-]+ snapshot$/ { print $0 " (earlier)"; next }
  { print }' "$doc" > "$work/rest"
awk -v sec="$work/section" '
  !done && /^## v[0-9A-Za-z.-]+ snapshot/ { while ((getline line < sec) > 0) print line; done = 1 }
  { print }' "$work/rest" > "$work/new"
grep -q "^## v$version snapshot\$" "$work/new" || { echo "error: no earlier snapshot heading in $doc to insert before" >&2; exit 1; }
cp "$work/new" "$doc"
echo "wrote the v$version snapshot in $doc"
