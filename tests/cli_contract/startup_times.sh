#!/bin/sh
# The startup numbers of docs/shell-to-tomato-plan.md section 2, measured through the command line only (any `tomato`: $TOMATO or PATH).
#   sh tests/cli_contract/startup_times.sh [RUNS]     (RUNS: runs of each cheap row, default 20; the rows that compile and link use half)
# It prints a table: the median, with the minimum and maximum in brackets, in milliseconds, and the load average it ran at. It only reports
# (the plan's budgets, a check that fails above twice the budget, come with the rewrite); the numbers of a loaded host are labelled as such
# when they go into docs/performance.md. The first run with an empty runtime cache is one run each (it compiles the C runtime).
runs="${1:-20}"; half=$((runs / 2)); [ "$half" -ge 3 ] || half=3
tomato="${TOMATO:-$(command -v tomato)}" || { echo "no tomato: set TOMATO" >&2; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
now_ms() { if command -v perl >/dev/null 2>&1; then perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; else echo $(($(date +%s) * 1000)); fi; }
printf '@main\ndef main():\n    print("hello, world")\n' > "$work/hello.tom"
cd "$work" || exit 1
# row LABEL RUNS COMMAND...: the median (min / max) of RUNS runs, in ms, output discarded
row() {
  label="$1"; n="$2"; shift 2; : > "$work/times"; i=0
  while [ "$i" -lt "$n" ]; do t0="$(now_ms)"; "$@" > /dev/null 2>&1; t1="$(now_ms)"; echo $((t1 - t0)) >> "$work/times"; i=$((i + 1)); done
  sort -n "$work/times" | awk -v label="$label" '{ a[NR] = $1 } END { m = (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2; printf "| %s | %d ms (%d / %d) |\n", label, m, a[1], a[NR] }'
}
echo "tomato: $tomato ($("$tomato" version 2>&1))"
echo "load average at the start: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || uptime | sed 's/.*load averages*: //')"
echo
echo "| What | Time |"; echo "| --- | --- |"
row 'sh -c true (the floor for any script)' "$runs" sh -c true
row 'tomato version' "$runs" "$tomato" version
row 'tomato help' "$runs" "$tomato" help
row 'tomato explain E01' "$runs" "$tomato" explain E01
row 'tomato config' "$runs" "$tomato" config
"$tomato" build hello.tom -o hello_bin > /dev/null 2>&1
row 'a built hello-world program, run (the binary alone)' "$runs" ./hello_bin
row 'tomato compile hello.tom (IR out)' "$half" "$tomato" compile hello.tom
row 'tomato build hello.tom, debug, runtime cached' "$half" "$tomato" build hello.tom -o hello_bin
row 'tomato run hello.tom, debug, runtime cached' "$half" "$tomato" run hello.tom
row 'tomato run hello.tom --mode release, runtime cached' "$half" "$tomato" run hello.tom --mode release
row 'clang --version' "$runs" clang --version
# the first run with the runtime cache empty (a folder of its own): debug, then release
for m in debug release; do
  t0="$(now_ms)"; TOMATO_CACHE_DIR="$work/cold-$m" "$tomato" run hello.tom --mode "$m" > /dev/null 2>&1; t1="$(now_ms)"
  echo "| first tomato run, runtime cache empty ($m, one run) | $((t1 - t0)) ms |"
done
echo
echo "load average at the end: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || uptime | sed 's/.*load averages*: //')"
