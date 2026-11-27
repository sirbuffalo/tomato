#!/bin/sh
# The CLI contract tests: a black-box suite of the `tomato` command, run against any `tomato`: the one on PATH, or the one in $TOMATO.
#   sh tests/cli_contract/run.sh [-j N] [--fast] [--update] [--list] [CASE ...]
# A CASE is a file of tests/cli_contract/cases (cases/init.sh is the case `init`); with none, every case runs. The cases are plain sh files
# that start the command and check what a user sees (standard output, standard error, exit status, files written): they know nothing of how
# the command is made, so the same suite must pass the shell script `native/tomato` today and the compiled Tomato program that replaces it
# (docs/shell-to-tomato-plan.md, sections 6 and 12). The text it expects is in tests/cli_contract/golden/ and in the cases themselves.
#   -j N      cases at a time (CONTRACT_JOBS, default 4); a case has a folder of its own and shares nothing with the others
#   --fast    the fast tier: skips the cases that say `# tier: full` on their second line (the ones that build many programs or wait)
#   --update  writes the golden files from what the command prints now (review the diff: a change to them is a change to the contract)
#   --list    prints the names of the cases
# The output is `ok`, `FAIL` and `skip` lines in the order of the cases, then the count; the status is 1 when anything failed.
# Environment: TOMATO (the command; else tomato on PATH), CONTRACT_JOBS, CONTRACT_TIMEOUT (seconds a case may take, default 900).
self="$(cd "$(dirname "$0")" && pwd)"
jobs="${CONTRACT_JOBS:-4}"; fast="${CONTRACT_FAST:-}"; update=""; list=""; names=""
while [ $# -gt 0 ]; do
  case "$1" in
    -j) [ $# -ge 2 ] || { echo "tests/cli_contract/run.sh: -j needs a number" >&2; exit 2; }; jobs="$2"; shift 2 ;;
    -j*) jobs="${1#-j}"; shift ;;
    --fast) fast=1; shift ;;
    --full) fast=""; shift ;;
    --update) update=1; shift ;;
    --list) list=1; shift ;;
    -h|--help) awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) echo "usage: tests/cli_contract/run.sh [-j N] [--fast] [--update] [--list] [CASE ...]" >&2; exit 2 ;;
    *) names="$names ${1%.sh}"; shift ;;
  esac
done
case "$jobs" in ''|*[!0-9]*|0) echo "tests/cli_contract/run.sh: the number of jobs must be a number above 0, not '$jobs'" >&2; exit 2 ;; esac
[ -n "$names" ] || names="$(cd "$self/cases" && for f in *.sh; do echo "${f%.sh}"; done)"
if [ -n "$list" ]; then for n in $names; do echo "$n"; done; exit 0; fi
for n in $names; do [ -f "$self/cases/$n.sh" ] || { echo "tests/cli_contract/run.sh: no case $n (the cases: $(cd "$self/cases" && ls | sed 's/\.sh$//' | tr '\n' ' '))" >&2; exit 2; }; done
# the command under test, as an absolute path (a case changes folders)
tomato="${TOMATO:-}"
if [ -z "$tomato" ]; then tomato="$(command -v tomato)" || { echo "tests/cli_contract/run.sh: no tomato on PATH (set TOMATO=/path/to/tomato)" >&2; exit 2; }; fi
case "$tomato" in */*) tomato="$(cd "$(dirname "$tomato")" && pwd)/$(basename "$tomato")" ;; *) tomato="$(command -v "$tomato")" || { echo "tests/cli_contract/run.sh: $tomato is not on PATH" >&2; exit 2; } ;; esac
[ -x "$tomato" ] || { echo "tests/cli_contract/run.sh: $tomato is not an executable file" >&2; exit 2; }
"$tomato" version > /dev/null 2>&1 || { echo "tests/cli_contract/run.sh: '$tomato version' fails: not a working tomato" >&2; exit 2; }
if [ -n "$update" ]; then jobs=1; fi
work="$(mktemp -d)" || exit 2
trap 'for p in $(pgrep -P $$ 2>/dev/null); do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done; rm -rf "$work"; exit 130' INT TERM
trap 'rm -rf "$work"' EXIT
echo "tomato under test: $tomato ($("$tomato" version))"
# run_case NAME: the case's output goes to $work/out.NAME and its exit status to $work/rc.NAME
run_case() {
  rc_n="$1"; rc_w="$work/w.$rc_n"; mkdir -p "$rc_w"; rc_w="$(cd "$rc_w" && pwd -P)"
  if [ -n "$fast" ] && sed -n '2p' "$self/cases/$rc_n.sh" | grep -q '^# tier: full'; then
    echo "skip cli contract: $rc_n: not in the fast tier" > "$work/out.$rc_n"; echo 0 > "$work/rc.$rc_n"; : > "$work/done.$rc_n"; return 0
  fi
  (
    cd "$rc_w" || exit 1
    TOMATO="$tomato" CONTRACT_DIR="$self" W="$rc_w" CONTRACT_FAST="$fast" CONTRACT_UPDATE="$update" sh "$self/cases/$rc_n.sh" > "$work/out.$rc_n" 2>&1 < /dev/null &
    pid=$!
    ( sleep "${CONTRACT_TIMEOUT:-900}"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; : > "$work/timeout.$rc_n" ) > /dev/null 2>&1 &
    dog=$!
    wait "$pid"; rc=$?
    kill "$dog" 2>/dev/null; pkill -P "$dog" 2>/dev/null
    if [ -f "$work/timeout.$rc_n" ]; then echo "FAIL cli contract: $rc_n: the case did not finish in ${CONTRACT_TIMEOUT:-900} seconds" >> "$work/out.$rc_n"; rc=1
    elif [ "$rc" -ne 0 ]; then echo "FAIL cli contract: $rc_n: the case ended with status $rc" >> "$work/out.$rc_n"; fi
    echo "$rc" > "$work/rc.$rc_n"; : > "$work/done.$rc_n"
  ) &
}
launched=""; running=0
count_running() { running=0; for c in $launched; do [ -f "$work/done.$c" ] || running=$((running + 1)); done; }
for n in $names; do
  while :; do count_running; [ "$running" -lt "$jobs" ] && break; sleep 0.1 2>/dev/null || sleep 1; done
  launched="$launched $n"
  run_case "$n"
done
for n in $names; do
  while [ ! -f "$work/done.$n" ]; do sleep 0.1 2>/dev/null || sleep 1; done
  cat "$work/out.$n"
done
passed=0; failed=0
for n in $names; do
  p="$(grep -c '^ok   ' "$work/out.$n")"; f="$(grep -c '^FAIL ' "$work/out.$n")"
  passed=$((passed + p)); failed=$((failed + f))
done
echo; echo "cli contract: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
