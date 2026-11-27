#!/bin/sh
# The test suite, in shell: it needs only clang. Usage: tests/run.sh [-j N] [--fast] [--times]
#   1. builds the compiler from compiler/bootstrap/tomatoc.ll and checks that it reproduces itself and that the
#      checked-in IR is current (the fixed point)
#   2. compiles and runs every example with the expected output in tests/expected
#   3. checks the command line (tomato run/build/compile/repl/update/version/help), and the CLI contract (tests/cli_contract: a black-box
#      suite of the command, written to pass any `tomato`, the script today and a Tomato program later)
#
# Tiers: with no flag the whole suite runs (what CI and a release use). --fast (or TOMATO_TEST_FAST=1) runs a representative
# subset for a developer's edit-and-test loop and for an agent's check before a merge: the same checks on every kind of program,
# but fewer programs of the kinds that have many (the AddressSanitizer builds, the WebAssembly runs, the release-mode runs, the
# benchmark comparison). It prints, at the end, exactly which tests it skipped; tests/README.md describes both tiers.
#
# --times (or TOMATO_TEST_TIMES=1) adds, after the summary, the 20 slowest tests and the time per section; nothing else changes.
#
# The tests run in parallel: -j N (or TOMATO_TEST_JOBS=N) is the number of tests running at once. The default is half the cores
# (at most 64), less when the machine is already busy (about half of its idle cores, at least 4), so that a shared machine is not
# starved; -j 1 runs the tests one after the other, printing each as it goes. Whatever N is, the output is the same and in the
# same order (a test's lines are printed when it is done, but never before the tests that come before it), and so are the final
# count and the exit status: the tests are started longest first, and printed in their place.
#
# The WebAssembly checks run each program with a 30 s limit instead of the website's 5 s (TOMATO_WASM_TIMEOUT_MS, when you have
# not set it), because a busy machine (or a hosted CI runner) is slow, and the programs run in an interpreter. A run that the
# limit stopped (and only that: never a wrong answer) is run again, with three times the limit, up to three times. Real jsc has no
# environment, so the limit is passed to native/tomato-jsc.js as an argument (--timeout-ms=N).
#
# How it works: every test is a function (t_NAME) that runs in a job of its own with its own temp folder ($work), so tests
# never share a file. The few things that are shared (the compiler built in step 1, the installed `tomato` command and the
# compiled C runtime, from the cache that `tomato run` also uses: native/rtcache.sh) are made once, before the tests that need
# them, and only read afterwards. Tests that must not overlap with anything (the macOS package and disk image, the rebuild of
# site/wasm) are run on their own, last (last).
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1
root="$(pwd)"
jobs="${TOMATO_TEST_JOBS:-}"
case "${TOMATO_TEST_TIMES:-}" in ''|0) times="" ;; *) times=1 ;; esac
case "${TOMATO_TEST_FAST:-}" in ''|0) fast="" ;; *) fast=1 ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    -j) [ $# -ge 2 ] || { echo "tests/run.sh: -j needs a number" >&2; exit 2; }; jobs="$2"; shift 2 ;;
    -j*) jobs="${1#-j}"; shift ;;
    --times) times=1; shift ;;
    --fast) fast=1; shift ;;
    --full) fast=""; shift ;;
    -h|--help) awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$self"; exit 0 ;;
    *) echo "usage: tests/run.sh [-j N] [--fast] [--times]   (or TOMATO_TEST_JOBS=N, TOMATO_TEST_FAST=1, TOMATO_TEST_TIMES=1)" >&2; exit 2 ;;
  esac
done
cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"   # getconf works on macOS and Linux
case "$cores" in ''|*[!0-9]*) cores=4 ;; esac
if [ -z "$jobs" ]; then
  jobs=$((cores / 2)); [ "$jobs" -gt 64 ] && jobs=64
  # the load average (the whole number): /proc on Linux, sysctl on macOS, else uptime
  load="$(awk '{ print int($1) }' /proc/loadavg 2>/dev/null)"
  [ -n "$load" ] || load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{ print int($2) }')"
  [ -n "$load" ] || load="$(uptime 2>/dev/null | sed 's/.*load averages*: //' | awk '{ print int($1) }')"
  case "$load" in ''|*[!0-9]*) ;; *)   # a busy machine: about half of what is idle, but at least 4
    free=$(((cores - load) / 2)); [ "$free" -lt 4 ] && free=4; [ "$jobs" -gt "$free" ] && jobs=$free ;;
  esac
fi
case "$jobs" in ''|*[!0-9]*) echo "tests/run.sh: the number of jobs must be a number, not '$jobs'" >&2; exit 2 ;; esac
[ "$jobs" -ge 1 ] || jobs=1

# The WebAssembly runner stops a program after 5 s, which a loaded machine or a hosted CI runner can exceed (and the big
# programs run slowly in the interpreter): give it more room. tests/run.sh passes this to native/tomato-jsc.js as
# --timeout-ms (jsc, the macOS shell, has no environment to read it from); set TOMATO_WASM_TIMEOUT_MS yourself to change it.
case "${TOMATO_WASM_TIMEOUT_MS:-}" in ''|*[!0-9]*|0) TOMATO_WASM_TIMEOUT_MS=30000 ;; esac
export TOMATO_WASM_TIMEOUT_MS
t_start="$(date +%s)"
work="$(mktemp -d)"; shared="$work"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }   # macOS has shasum, some Linux systems only sha256sum

# ---- the job pool -------------------------------------------------------------------------------------------------------
# A test is first registered (spawn, section, last: in the order of the output, which gives it its number), and all of them are
# run at the end, by run_all, in the order that is best for the wall time: the ones that take long first. $shared holds, per
# job N: out.N (its output), rc.N (its status) and done.N (it is finished), and the files passed and failed (one line per test).
# Inside a job, $work is that job's own folder (removed when the job ends); $shared is still the common one.
n=0; next=1; running=""; nrun=0
free_ids=""; long_ids=""; first_ids=""; rest_ids=""; cli_ids=""; early_ids=""; gate_id=""; skipped=""
section_name=""
nap() { sleep 0.05 2>/dev/null || sleep 1; }
kill_tree() { for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
cleanup() { # when interrupted: stop the jobs, and everything they started, that are still going; then remove the temp folder
  for p in $(pgrep -P $$ 2>/dev/null); do kill_tree "$p"; done
  rm -rf "$work"
}
trap cleanup EXIT; trap 'exit 130' INT TERM
ok() { echo x >> "$shared/passed"; echo "ok   $1"; }
bad() { echo x >> "$shared/failed"; echo "FAIL $1"; [ -n "$2" ] && echo "$2" | sed 's/^/     /'; }
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2
got:      $3"; fi
}
if [ -n "$times" ]; then   # milliseconds: perl is on macOS and Linux; without it the timings are whole seconds
  if command -v perl >/dev/null 2>&1; then ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }; else ms() { echo $(($(date +%s) * 1000)); }; fi
fi
cpu_ms() { # sets $tm_cpu to the CPU time (user and system, in milliseconds) of what this job has run so far: it does not depend on how busy the machine is
  times > "$work/.times"   # (not in $(...): that would be another process, with no children yet)
  tm_cpu="$(sed -n 2p "$work/.times" | awk '{ t = 0; for (i = 1; i <= 2; i++) { split($i, a, "m"); sub(/s$/, "", a[2]); t += a[1] * 60 + a[2] } printf "%d", t * 1000 }')"
}
await_file() { # waits (up to 10 minutes) for a file another job writes; fails when it never comes
  i=0; until [ -f "$1" ]; do nap; i=$((i + 1)); [ "$i" -gt 12000 ] && return 1; done; return 0
}
await_object() { # waits for the bootstrap object t_compiler_build makes; fails at once when that build has failed
  i=0; until [ -f "$shared/c0.o.done" ]; do [ -f "$shared/c0.o.failed" ] && return 1; nap; i=$((i + 1)); [ "$i" -gt 12000 ] && return 1; done; return 0
}
job_run() { # id, function and arguments: runs it in a folder of its own
  id="$1"; shift; work="$shared/j$id"; mkdir -p "$work"; eval "section_name=\$sec_$id"
  case "$1" in   # (the ones that do not link a program with the runtime do not wait for it)
    t_install|t_compiler_build|t_cli_update|t_cli_update_versions|t_atomic_install|t_atomic_update|t_release_versions|t_release_resume|t_wasm_*|t_error_templates|t_error_raises|t_sys_version|t_builtin_folder|t_docs_in_sync|t_versions|t_highlighter_lists) ;;
    *) await_file "$shared/rt_o.path"; rt_o="$(cat "$shared/rt_o.path")" ;;
  esac
  if [ -n "$times" ]; then
    tm_start="$(ms)"; tm_label="${1#t_} $2"; "$@"; rc=$?   # (names the tests do not use)
    cpu_ms; printf '%s\t%s\t%s\t%s\n' "$(($(ms) - tm_start))" "$section_name" "$tm_label" "$tm_cpu" >> "$shared/times"
  else "$@"; rc=$?; fi
  rm -rf "$work"; return $rc
}
shquote() { # TEXT: sets $shq to TEXT between single quotes, so that eval gives it back unchanged (no process is started)
  shq_rest="$1"; shq_out=""
  while :; do
    case "$shq_rest" in
      *"'"*) shq_out="$shq_out${shq_rest%%"'"*}'\\''"; shq_rest="${shq_rest#*"'"}" ;;
      *) break ;;
    esac
  done
  shq="'$shq_out$shq_rest'"
}
register() { # KIND PLACE ARGS...: a test (function and arguments) takes the next number in the output
  kind="$1"; place="$2"; shift 2
  n=$((n + 1)); line=""
  for a in "$@"; do shquote "$a"; line="$line $shq"; done
  eval "cmd_$n=\$line; sec_$n=\$section_name; kind_$n=$kind"
  case "$place" in
    free) free_ids="$free_ids $n" ;;       # needs nothing the compiler build makes: started with it
    long) long_ids="$long_ids $n" ;;       # the longest: started before the others
    first) first_ids="$first_ids $n" ;;    # long: started before the rest
    early) early_ids="$early_ids $n" ;;    # needed by others: started at once
    gate) gate_id="$n" ;;                  # every test but the early ones waits for it
    cli) cli_ids="$cli_ids $n" ;;          # needs the installed `tomato`: started when the install is done
    *) rest_ids="$rest_ids $n" ;;
  esac
}
spawn() { register t rest "$@"; }              # NAME ARGS: a test; it is run when there is a free job
spawn_first() { register t first "$@"; }       # the same, for a test that takes long: it is started first
spawn_free() { register t free "$@"; }         # the same, for a test that does not use the compiler built above (it runs while that is built)
spawn_cli() { register t cli "$@"; }           # the same, for a test that uses the installed `tomato`
last() { register l rest "$@"; }               # a test that must be run alone, after every other test (its output still comes in its place)
section() { # prints a heading in its place
  section_name="$1"; n=$((n + 1))
  eval "txt_$n=\$1; kind_$n=s; sec_$n=\$1"
}
skip() { # NAME: a test the fast tier does not run (listed at the end, under the short name of its section)
  skip_sec="${section_name#== }"; skip_sec="${skip_sec%% (*}"; skip_sec="${skip_sec%% ==*}"
  skipped="$skipped
  $skip_sec: $1"
}
sections_are_done() { # a heading needs no job: it is ready to be printed
  i=1
  while [ "$i" -le "$n" ]; do
    eval "k=\$kind_$i"
    if [ "$k" = s ]; then eval "printf '%s\\n' \"\$txt_$i\"" > "$shared/out.$i"; : > "$shared/done.$i"; fi
    i=$((i + 1))
  done
}
pump() { # prints the output of the finished jobs, in the order they were registered
  while [ -f "$shared/done.$next" ]; do cat "$shared/out.$next"; rm -f "$shared/out.$next"; next=$((next + 1)); done
}
reap() { # forgets the jobs that are finished; a job that is gone without finishing (killed) is a failure, not a hang
  r=""; nrun=0
  for j in $running; do
    rid="${j%%:*}"
    [ -f "$shared/done.$rid" ] && continue
    if ! kill -0 "${j#*:}" 2>/dev/null && [ ! -f "$shared/done.$rid" ]; then
      echo "FAIL job $rid died before it finished" >> "$shared/out.$rid"; echo x >> "$shared/failed"; echo 1 > "$shared/rc.$rid"; : > "$shared/done.$rid"; continue
    fi
    r="$r $j"; nrun=$((nrun + 1))
  done
  running="$r"
}
barrier() { while :; do reap; pump; [ "$nrun" -eq 0 ] && break; nap; done; pump; }
launch() { # ID: starts a test in a job of its own, as soon as there is a free slot
  id="$1"; eval "line=\$cmd_$id"
  while :; do reap; pump; [ "$nrun" -lt "$jobs" ] && break; nap; done
  ( ( eval "job_run $id $line" ) > "$shared/out.$id" 2>&1 < /dev/null; rc=$?   # the inner subshell: a test that calls exit still gets its done marker
    [ "$rc" -gt 128 ] && { echo "FAIL job died before it finished (status $rc)" >> "$shared/out.$id"; echo x >> "$shared/failed"; }   # killed by a signal
    echo "$rc" > "$shared/rc.$id"; : > "$shared/done.$id" ) &
  running="$running $id:$!"; nrun=$((nrun + 1))
}
run_inline() { # ID: run a test here, alone, printing straight to the output (-j 1; and the tests that must be alone, after the others)
  id="$1"; eval "line=\$cmd_$id"
  ( eval "job_run $id $line" ) < /dev/null; rc=$?
  [ "$rc" -gt 128 ] && { echo "FAIL job died before it finished (status $rc)"; echo x >> "$shared/failed"; }   # killed by a signal
  echo "$rc" > "$shared/rc.$id"; : > "$shared/out.$id"; : > "$shared/done.$id"; pump
  return "$rc"
}
pop() { # LIST: sets $pick to the first number in the list called LIST (empty when there is none) and takes it out of the list
  pop_name="$1"; eval "set -- \$$pop_name"
  pick="${1:-}"; [ $# -gt 0 ] && shift
  eval "$pop_name=\"\$*\""
}
cli_ready() { # has the install finished (a job that died has not reported: its tests then fail, instead of waiting for it)
  [ -f "$shared/install.rc" ] && return 0
  [ -f "$shared/done.$install_id" ] && { echo 1 > "$shared/install.rc"; return 0; }
  return 1
}
run_all() {
  sections_are_done
  if [ "$jobs" -le 1 ]; then   # one after the other, in the order of the output
    i=1
    while [ "$i" -le "$n" ]; do
      eval "k=\$kind_$i"
      case "$k" in s) ;; *) run_inline "$i" || { [ "$i" = "$gate_id" ] && { pump; exit 1; }; } ;; esac
      pump; i=$((i + 1))
    done
    return
  fi
  set -- $early_ids; install_id="$1"
  for id in $early_ids; do launch "$id"; done
  if [ -n "$gate_id" ]; then   # the compiler: nothing else that uses it can start before it; the tests that do not run beside it
    launch "$gate_id"
    while [ -n "$free_ids" ] && [ ! -f "$shared/done.$gate_id" ]; do pop free_ids; launch "$pick"; done
    while [ ! -f "$shared/done.$gate_id" ]; do reap; pump; nap; done
    [ "$(cat "$shared/rc.$gate_id")" = 0 ] || { barrier; exit 1; }
  fi
  set -- $free_ids $long_ids $first_ids $rest_ids; todo="$*"; deferred=""
  while :; do   # the tests that need the installed `tomato` first, as soon as it is there; then the long ones; then the others
    if [ -n "$cli_ids" ] && cli_ready; then pop cli_ids
    elif [ -n "$todo" ]; then pop todo
    elif [ -n "$cli_ids" ]; then reap; pump; nap; continue
    else break; fi
    eval "k=\$kind_$pick"
    if [ "$k" = l ]; then deferred="$deferred $pick"; else launch "$pick"; fi
  done
  barrier
  for id in $deferred; do run_inline "$id"; done
  pump
}

# the C runtime, compiled once (and kept, for the next run too, in the cache that `tomato run` uses: native/rtcache.sh): $rt_o
# for the plain link, $rt_asan with AddressSanitizer (empty when this clang cannot build it: the tests then say so). They are made
# in the background while the compiler is built; without a usable object the C file itself is linked, as it always was.
. "$root/native/rtcache.sh"
( p="$(rtcache_get "$shared" o "$root/runtime/tomato_rt.c" -O1 -pthread -w)" || p="$root/runtime/tomato_rt.c"; echo "$p" > "$shared/rt_o.tmp"; mv "$shared/rt_o.tmp" "$shared/rt_o.path" ) > /dev/null 2>&1 &
( p="$(rtcache_get "$shared" o "$root/runtime/tomato_rt.c" -O1 -pthread -w -g -fsanitize=address)" || p=""; echo "$p" > "$shared/rt_asan.tmp"; mv "$shared/rt_asan.tmp" "$shared/rt_asan.path" ) > /dev/null 2>&1 &
# the runtimes that `tomato run` links, for the command-line tests: release's is bitcode (for link-time optimisation), debug's is the plain
# object that the tests above already made (the same flags as $rt_o). Made now, while the install is running, so that when it is done they
# all find it, instead of each of them compiling it at the same time (a cold cache)
( rtcache_get "$shared" bc "$root/runtime/tomato_rt.c" -O2 -flto -DTOMATO_RELEASE -pthread > /dev/null 2>&1 ) &
use_asan() { await_file "$shared/rt_asan.path"; rt_asan="$(cat "$shared/rt_asan.path")"; }
cc() { clang -O1 -w -o "$1" "$2" "$rt_o" -pthread -lm; }
c1="$shared/c1"
home="$shared/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"; t="$home/bin/tomato"

# ---- compiler -----------------------------------------------------------------------------------------------------------
t_compiler_build() { # the compiler everything else uses: $shared/c0 (from the bootstrap IR) and $shared/c1 (built by c0)
  # the IR is compiled while the runtime object is made (or fetched from the cache), then they are linked: the same program as one clang command
  compiler/bootstrap/build-object.sh "$shared/c0.o" 2> "$work/e" & ir_pid=$!
  await_file "$shared/rt_o.path"; rt_o="$(cat "$shared/rt_o.path")"
  if wait "$ir_pid"; then : > "$shared/c0.o.done"; else : > "$shared/c0.o.failed"; fi
  # build-object.sh falls back to one clang process when the parallel build fails; that works, so the suite would stay green and only slow: fail it here
  if grep -q 'the split build failed' "$work/e"; then bad "the bootstrap IR compiles in parallel parts" "$(head -5 "$work/e")"; else ok "the bootstrap IR compiles in parallel parts"; fi
  [ -f "$shared/c0.o.done" ] && clang -O1 -w -o "$shared/c0" "$shared/c0.o" "$rt_o" -pthread -lm 2>> "$work/e" && ok "builds from the bootstrap IR" || { bad "builds from the bootstrap IR" "$(head -5 "$work/e")"; return 1; }
  "$shared/c0" compiler/src/ctool.tom compile > "$shared/ir1.ll" 2> "$work/e" && ok "compiles its own source" || bad "compiles its own source" "$(cat "$work/e")"
  # c1 is c0 compiled from ir1.ll: when ir1.ll is the checked-in IR (the normal case, and what t_fixed_point checks) that is the very
  # program c0 already is, so it is not built a second time (half a minute); when it is not, c1 is built, and the tests use it
  if cmp -s "$shared/ir1.ll" compiler/bootstrap/tomatoc.ll; then cp "$shared/c0" "$c1"; else cc "$c1" "$shared/ir1.ll"; fi
  [ -x "$c1" ]
}
t_fixed_point() {
  "$c1" compiler/src/ctool.tom compile > "$work/ir2.ll"
  cmp -s "$shared/ir1.ll" "$work/ir2.ll" && ok "stage 2 reproduces itself (fixed point)" || bad "stage 2 reproduces itself (fixed point)"
  cmp -s "$work/ir2.ll" compiler/bootstrap/tomatoc.ll && ok "compiler/bootstrap/tomatoc.ll is current" || bad "compiler/bootstrap/tomatoc.ll is current" "run compiler/bootstrap/refresh.sh"
  grep -q '^;! ' "$shared/ir1.ll" && bad "the compiler's own source compiles without warnings" "$(grep '^;! ' "$shared/ir1.ll" | head -6)" || ok "the compiler's own source compiles without warnings"
}
# Installation reuses the same completed bootstrap object while still compiling the runtime and linking for real.
t_install() { # the installed `tomato` command: the command line tests use it, and only read it
  if await_object; then TOMATO_TEST_BOOTSTRAP_OBJECT="$shared/c0.o" ./install-native.sh > /dev/null 2>&1; echo $? > "$shared/install.tmp"
  else echo 1 > "$shared/install.tmp"; fi   # (the object never came: the compiler build failed, so the install fails too, at once)
  mv "$shared/install.tmp" "$shared/install.rc"
}

section "== compiler =="
register t early t_install        # prints nothing: the result is reported in "command line"
register t gate t_compiler_build  # the install runs beside it; every other test waits for it
spawn_first t_fixed_point

# ---- examples -----------------------------------------------------------------------------------------------------------
t_example() { # name, entry, the arguments
  name="$1"; entry="$2"; rest="$3"
  "$c1" "examples/$name.tom" "$entry" std/ > "$work/p.ll" 2> "$work/e" || { echo "FAIL $name $entry: $(cat "$work/e")"; echo x >> "$shared/failed"; return; }
  grep -q '^;! ' "$work/p.ll" && { echo "FAIL $name $entry: warnings"; grep '^;! ' "$work/p.ll" | head -6 | sed 's/^/     /'; echo x >> "$shared/failed"; return; }
  clang -O1 -w -o "$work/p" "$work/p.ll" "$rt_o" -pthread -lm || { echo "FAIL $name $entry: link"; echo x >> "$shared/failed"; return; }
  # shellcheck disable=SC2086
  "$work/p" $rest > "$work/out" 2>&1 < /dev/null
  if cmp -s "$work/out" "tests/expected/$name.$entry.out"; then echo "ok   $name $entry"; echo x >> "$shared/passed"; else echo "FAIL $name $entry"; diff "$work/out" "tests/expected/$name.$entry.out" | head -5 | sed 's/^/     /'; echo x >> "$shared/failed"; fi
}
section "== examples =="
grep -v '^#' tests/examples.txt | while read -r name entry rest; do echo "$name $entry $rest"; done > "$shared/list"
while read -r name entry rest; do spawn t_example "$name" "$entry" "$rest"; done < "$shared/list"

# ---- programs -----------------------------------------------------------------------------------------------------------
# the fast tier builds only these with AddressSanitizer (one or two programs of each kind of thing the suite looks at)
fast_asan=" at_neg_rmul float_ownership loop_lifetime fast_paths loop_nests shapes objects cycle gc_cycles containers modules native_sort function_values lambdas sort_stable str_fast alloc_pool text_index json_accept json_fuzz msgpack_basic bigint_ownership bigint_unwind toml_valid toml_api json_files msgpack_file_basics open_errors mixed_tuples compact_lists temp_unwind async_tasks async_cancel async_sync socket_local socket_udp error_path_release error_classes time_module web_modules datetime_arith csv_module re_api re_limits sys_args sys_run sys_async os_files file_lines file_loop_close file_closed file_drop_loop string_io assert_ok testing_lib testing_diff "
# What the AddressSanitizer tests build (PATH:ARGUMENT, see t_asan); a program that is also one of the "decided rules" programs is built
# once, with AddressSanitizer, for both tests (t_program_asan)
asan_specs1="tests/programs/at_neg_rmul: tests/programs/angle_lists: tests/programs/loop_lifetime: tests/programs/fast_paths: tests/programs/loop_nests: examples/shapes: examples/objects:4 tests/programs/cycle: tests/programs/gc_cycles: tests/programs/containers: tests/programs/modules: tests/programs/borrow_elision: tests/programs/native_sort: tests/programs/function_values: tests/programs/lambdas: tests/programs/sort_stable: tests/programs/sort_errors: tests/programs/sort_key_cmp: tests/programs/sort_cmp_native: tests/programs/sort_field: tests/programs/str_fast: tests/programs/alloc_pool: tests/programs/text_index: tests/programs/fstring_fuse: tests/programs/cache_lru: tests/programs/cache_multi: tests/programs/memoize: tests/programs/bit_types: tests/programs/int_shift: tests/programs/big_shift: tests/programs/int_bitwise_big: tests/programs/bit_chunks: tests/programs/json_strict: tests/programs/json_accept: tests/programs/json_dumps: tests/programs/json_access: tests/programs/json_depth: tests/programs/json_utf8: tests/programs/json_fuzz: tests/programs/msgpack_basic: tests/programs/msgpack_errors: tests/programs/msgpack_fuzz: tests/programs/bigint_ownership: tests/programs/bigint_ops: tests/programs/bigint_frames: tests/programs/bigint_unwind: tests/programs/big_numbers: tests/programs/big_mul: tests/programs/big_decimal: tests/programs/big_karatsuba: tests/programs/big_ntt: tests/programs/big_division: tests/programs/int_bitwise_runs: tests/programs/big_bad_text: tests/programs/int64_convert: tests/programs/unlimited_int: tests/programs/toml_valid: tests/programs/toml_invalid: tests/programs/toml_api:WORK tests/programs/json_files:WORK tests/programs/msgpack_files:WORK tests/programs/msgpack_file_basics:WORK tests/runtime/msgpack_full_disk: tests/programs/open_errors: tests/programs/unicode_case: tests/programs/unicode_case_full: tests/programs/unicode_class: tests/programs/mixed_tuples: tests/programs/tuple_type_args: tests/programs/union_show: tests/programs/optional_values: tests/programs/optional_lookups: tests/programs/optional_narrowing: tests/programs/optional_narrowing_flow: tests/programs/optional_narrowing_assign: tests/programs/optional_error_paths: tests/programs/toml_big: tests/programs/compact_lists: tests/programs/compact_fuzz: tests/programs/temp_unwind: tests/programs/text_dict_methods: tests/programs/dict_literal_inference: tests/programs/dict_keys_any: tests/programs/dict_keys_objects: tests/programs/dict_keys_forms: tests/programs/dict_keys_cycles: tests/programs/tuple_for: tests/programs/list_methods: tests/programs/utf8_invalid: tests/programs/async_tasks: tests/programs/async_cancel: tests/programs/async_sleep: tests/programs/async_toolkit: tests/programs/async_sync: tests/programs/async_queue_drop: tests/programs/async_gc_release: tests/programs/socket_local: tests/programs/socket_udp: tests/programs/socket_fair: tests/programs/error_path_release: tests/programs/int_ranges: tests/programs/range_wide: tests/programs/int_to_float: tests/programs/float_any_size: tests/programs/float_floor_mod: tests/programs/float_ownership: tests/programs/float_loops: tests/programs/float_keys: tests/programs/float_nests: tests/programs/float_library: tests/programs/fast_ranges: tests/runtime/error_classes: tests/programs/time_module: tests/programs/url_parse: tests/programs/url_quote: tests/programs/html_escape: tests/programs/base64_codec: tests/programs/hex_codec: tests/programs/web_modules: tests/programs/html_fuzz: tests/programs/web_large: tests/programs/datetime_arith: tests/programs/datetime_format: tests/programs/datetime_parse: tests/runtime/datetime_errors: tests/programs/csv_module: tests/programs/textwrap_module: tests/programs/statistics_module:"
asan_specs2="tests/programs/sys_args:7  tests/programs/os_env: tests/programs/os_files:WORK tests/programs/sys_run:WORK tests/programs/sys_async:WORK tests/programs/ospath_text: tests/programs/file_lines:WORK tests/programs/file_loop_close:WORK tests/programs/file_modes:WORK tests/programs/file_closed:WORK tests/programs/file_drop_loop:WORK tests/programs/bytes_files:WORK tests/programs/string_io: tests/programs/re_api: tests/programs/re_limits: tests/programs/hashlib_vectors: tests/programs/struct_ints: tests/programs/struct_floats: tests/programs/struct_float_sweep: tests/programs/wave2_bytes: tests/programs/hmac_vectors: tests/programs/round_divmod_any_all: tests/programs/text_methods_more: tests/programs/math_more: tests/programs/fstring_specs: tests/runtime/text_math_caught: tests/programs/assert_ok: tests/programs/testing_lib: tests/programs/testing_diff:"
asan_paths=" $(printf '%s\n' $asan_specs1 $asan_specs2 | sed 's/:.*//' | tr '\n' ' ')"
lent_loops_ok() { # IR NAME: a program whose first line says "# borrowed loops: N" must compile exactly N loops that borrow their item
  want="$(sed -n '1s/^# borrowed loops: //p' "tests/programs/$2.tom")"
  [ -z "$want" ] || [ "$(grep -c 'lent\.slot\.[0-9]* = alloca' "$1")" = "$want" ]
}
t_program() {
  name="$1"
  "$c1" "tests/programs/$name.tom" main std/ > "$work/p.ll" 2> "$work/e"
  if grep -q '^;! ' "$work/p.ll"; then echo "FAIL program $name has warnings"; echo x >> "$shared/failed"; return; fi
  lent_loops_ok "$work/p.ll" "$name" || { echo "FAIL program $name: the number of loops that borrow their item changed"; echo x >> "$shared/failed"; return; }
  arg=""; case "$name" in toml_api|json_files|msgpack_files|msgpack_file_basics|os_files|file_lines|file_loop_close|file_modes|file_closed|file_drop_loop|bytes_files|sys_run|sys_async) arg="$work" ;; sys_basics) arg="alpha" ;; sys_args) arg="7 b c" ;; esac   # they write files: into this test's own folder, not a shared /tmp; the sys programs take inputs
  # shellcheck disable=SC2086
  [ -s "$work/p.ll" ] && clang -O1 -w -o "$work/p" "$work/p.ll" "$rt_o" -pthread -lm && "$work/p" $arg > "$work/out" 2>&1
  if cmp -s "$work/out" "tests/expected/$name.main.out"; then echo "ok   program $name"; echo x >> "$shared/passed"; else echo "FAIL program $name"; { head -3 "$work/e"; diff "$work/out" "tests/expected/$name.main.out" | head -5; } | sed 's/^/     /'; echo x >> "$shared/failed"; fi
}
t_program_asan() { # the same test as t_program, for a program that an AddressSanitizer test builds too: its output (standard output and standard error)
  # from that build, which asan_build makes once for both: the same IR, the same -O1, with the checks of AddressSanitizer added
  name="$1"
  asan_build "tests/programs/$name"
  if grep -q '^;! ' "$asan_ll"; then echo "FAIL program $name has warnings"; echo x >> "$shared/failed"; return; fi
  lent_loops_ok "$asan_ll" "$name" || { echo "FAIL program $name: the number of loops that borrow their item changed"; echo x >> "$shared/failed"; return; }
  arg=""; case "$name" in toml_api|json_files|msgpack_files|msgpack_file_basics|os_files|file_lines|file_loop_close|file_modes|file_closed|file_drop_loop|bytes_files|sys_run|sys_async) arg="$work" ;; sys_basics) arg="alpha" ;; sys_args) arg="7 b c" ;; esac   # they write files: into this test's own folder, not a shared /tmp; the sys programs take inputs
  # shellcheck disable=SC2086
  [ -x "$asan_exe" ] && "$asan_exe" $arg > "$work/out" 2>&1
  if cmp -s "$work/out" "tests/expected/$name.main.out"; then echo "ok   program $name"; echo x >> "$shared/passed"; else echo "FAIL program $name"; { head -3 "$asan_err"; diff "$work/out" "tests/expected/$name.main.out" | head -5; } | sed 's/^/     /'; echo x >> "$shared/failed"; fi
}
section "== decided rules (programs) =="
grep -v '^#' tests/programs.txt > "$shared/list"
while read -r name; do
  # one that an AddressSanitizer test builds too (in this tier) is built once, with AddressSanitizer, for both
  if case "$asan_paths" in *" tests/programs/$name "*) true ;; *) false ;; esac && { [ -z "$fast" ] || case " $fast_asan " in *" $name "*) true ;; *) false ;; esac; }; then spawn_first t_program_asan "$name"
  else spawn t_program "$name"; fi
done < "$shared/list"

# ---- memory -------------------------------------------------------------------------------------------------------------
asan_build() { # PATH (without .tom): the IR of a program, with what the compiler said, and its AddressSanitizer build: $asan_ll, $asan_err, $asan_exe.
  # Made once, by the first of the tests that need it (the others wait for it); fails when this clang cannot build with AddressSanitizer
  use_asan; ab_key="$(printf '%s' "$1" | tr '/' '_')"; ab_dir="$shared/asan"; mkdir -p "$ab_dir"
  asan_ll="$ab_dir/$ab_key.ll"; asan_err="$ab_dir/$ab_key.err"; asan_exe="$ab_dir/$ab_key.exe"
  if mkdir "$ab_dir/$ab_key.lock" 2>/dev/null; then
    "$c1" "$1.tom" main std/ > "$asan_ll" 2> "$asan_err"
    clang -O1 -w -g -fsanitize=address -o "$asan_exe.tmp" "$asan_ll" "$rt_asan" -pthread -lm 2>/dev/null && mv "$asan_exe.tmp" "$asan_exe"
    : > "$ab_dir/$ab_key.done"
  else await_file "$ab_dir/$ab_key.done"; fi
  [ -x "$asan_exe" ]
}
t_asan() { # PATH:ARGUMENT, the argument being a folder the program may write into when it is $work
  spec="$1"; path="${spec%%:*}"; name="$(basename "$path")"; arg="${spec#*:}"; [ "$arg" = WORK ] && arg="$work"
  if asan_build "$path"; then
    # a failure shows the head of the sanitizer report (with ASAN_SYMBOLIZER_PATH set, as the Linux CI job does, that includes the leaking allocation's stack)
    # shellcheck disable=SC2086
    out="$("$asan_exe" $arg 2>&1 >/dev/null | head -14)"
    [ -z "$out" ] && ok "asan $name" || bad "asan $name" "$out"
  else bad "asan $name" "this clang cannot build with -fsanitize=address"; fi
}
spawn_asan() { # PATH:ARGUMENT
  case " $fast_asan " in *" $(basename "${1%%:*}") "*) ;; *) [ -n "$fast" ] && { skip "asan $(basename "${1%%:*}")"; return; } ;; esac
  spawn_first t_asan "$1"
}
section "== memory (AddressSanitizer and the runtime's leak check) =="
for spec in $asan_specs1; do
  spawn_asan "$spec"
done

section "== memory: round, text methods, math additions and f-string specs =="
for spec in $asan_specs2; do
  spawn_asan "$spec"
done

t_bigfloat() { # floats of any size, at the C level: fixed cases, then random ones against an exact reference (tests/bigfloat.c)
  if clang -O1 -w -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o "$work/bigfloat" tests/bigfloat.c -pthread -lm 2> "$work/e"; then
    out="$("$work/bigfloat" 1500 2>&1 | head -14)"
    [ "$out" = ok ] && ok "floats of any size (asan and ubsan, against an exact reference)" || bad "floats of any size" "$out"
  else bad "floats of any size" "tests/bigfloat.c does not build: $(head -3 "$work/e")"; fi
}
section "== memory: floats of any size (the C runtime; the compiler uses them in the programs float_any_size and float_ownership) =="
spawn t_bigfloat

t_bigdiv() {
  if clang -O1 -w -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o "$work/bigdiv" tests/bigdiv.c -lm 2> "$work/e"; then
    out="$("$work/bigdiv" 2>&1 | head -14)"
    [ "$out" = ok ] && ok "big integer division (asan and ubsan, against bitwise division)" || bad "big integer division" "$out"
  else bad "big integer division" "tests/bigdiv.c does not build: $(head -3 "$work/e")"; fi
}
spawn t_bigdiv

t_bigmul() {
  if clang -O1 -w -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o "$work/bigmul" tests/bigmul.c -lm 2> "$work/e"; then
    out="$("$work/bigmul" 2>&1 | head -14)"
    [ "$out" = ok ] && ok "big integer multiplication (asan and ubsan, Karatsuba and squaring against schoolbook)" || bad "big integer multiplication" "$out"
  else bad "big integer multiplication" "tests/bigmul.c does not build: $(head -3 "$work/e")"; fi
}
spawn t_bigmul

t_bigdec() { # FLAGS: decimal conversion both ways against the plain loops; as shipped, and with tiny cutoffs (many levels deep on small numbers)
  if clang -O1 -w -g -fsanitize=address,undefined -fno-sanitize-recover=undefined $1 -o "$work/bigdec" tests/bigdec.c -pthread -lm 2> "$work/e"; then
    out="$("$work/bigdec" 2>&1 | head -14)"
    [ "$out" = ok ] && ok "big integer decimal text${1:+ ($1)} (asan and ubsan, against the plain loops)" || bad "big integer decimal text $1" "$out"
  else bad "big integer decimal text" "tests/bigdec.c does not build: $(head -3 "$work/e")"; fi
}
spawn t_bigdec ""
spawn t_bigdec "-DDEC_BASE_LIMBS=8 -DDEC_RECIP_LIMBS=1 -DDEC_PARSE_DIGITS=19"

t_sort_fallback() {
  "$c1" tests/programs/native_sort.tom main std/ > "$work/p.ll" 2>/dev/null && clang -O1 -w -o "$work/p" "$work/p.ll" "$(rtcache_get "$work" o "$root/runtime/tomato_rt.c" -O1 -pthread -w -DSORT_DEPTH_MUL=0)" -pthread -lm && "$work/p" > "$work/out" 2>&1
  check "sort with the depth limit forced to 0" "$(cat tests/expected/native_sort.main.out)" "$(cat "$work/out")"
}
# Release mode makes other code (fused integer expressions, copies for small arguments, no error tests after calls that cannot raise).
# The runtime is built without TOMATO_RELEASE, so it reports what was never freed, and with AddressSanitizer. A release program
# leaves freeing what its entry function holds to the end of the process, so leaks are only looked for (the second argument)
# in programs whose entry function holds nothing: there, whatever is left at the end was leaked.
# A task waiting for a lock that the cycle collector frees must leave the runtime's list of lock waiters: the deadlock report after it
# names only the task that is really waiting, and AddressSanitizer sees no read of the freed frame or lock
t_lock_gc() {
  use_asan
  "$c1" tests/runtime/async_lock_gc.tom main std/ > "$work/g.ll" 2> "$work/e"
  if clang -O1 -w -g -fsanitize=address -o "$work/g" "$work/g.ll" "$rt_asan" -pthread -lm 2>/dev/null; then
    ASAN_OPTIONS=detect_leaks=0 "$work/g" > "$work/out" 2>&1
    n="$(grep -c '^  task [0-9]* is waiting' "$work/out")"
    if [ "$n" = 1 ] && grep -q 'task 1 is waiting at line 31 for a lock held since line 30' "$work/out" && ! grep -q 'AddressSanitizer' "$work/out"; then ok "lock waiters freed by the collector leave no stale report"
    else bad "lock waiters freed by the collector leave no stale report" "$(head -8 "$work/out")"; fi
  else bad "lock waiters freed by the collector leave no stale report" "does not build"; fi
}
t_release_asan() { # program, "leaks" to look for leaks too
  use_asan
  arg=""; case "$1" in file_closed|sys_run|sys_async) arg="$work" ;; esac   # it writes files: into this test's own folder
  "$c1" "tests/programs/$1.tom" main std/ release > "$work/p.ll" 2> "$work/e"
  if clang -O1 -w -g -fsanitize=address -o "$work/rel" "$work/p.ll" "$rt_asan" -pthread -lm 2>/dev/null; then
    if [ "$2" = leaks ]; then "$work/rel" $arg > "$work/out" 2> "$work/e"; cat "$work/e" >> "$work/out"
    else ASAN_OPTIONS=detect_leaks=0 "$work/rel" $arg > "$work/out" 2> "$work/e"; grep -v "never freed" "$work/e" >> "$work/out"; fi
    cmp -s "$work/out" "tests/expected/$1.main.out" && ok "release $1" || bad "release $1" "$(diff "$work/out" "tests/expected/$1.main.out" | head -5)"
  else bad "release $1" "does not build"; fi
}
t_release_leak() { # fused expressions over big numbers; the test itself is tested by taking the frees out of the runtime
  use_asan
  printf 'def work():\n    x = 2 ** 70\n    xs = [2 ** 65, 7]\n    for i in range(40):\n        x = x * 3 - i * xs[i %% 2] + 1\n        xs[1] = xs[1] * xs[0] - x %% 1000003\n    print(x %% 97, xs[1] %% 97)\n\n@main\ndef main():\n    work()\n' > "$work/leak.tom"
  "$c1" "$work/leak.tom" main std/ release > "$work/p.ll" 2> "$work/e" && clang -O1 -w -g -fsanitize=address -o "$work/rel" "$work/p.ll" "$rt_asan" -pthread -lm
  check "release: big numbers in fused expressions are freed" "55 51" "$("$work/rel" 2>&1)"
  sed 's/^#define INT_CONSUME(m, x, y) .*/#define INT_CONSUME(m, x, y) do { } while (0)/' runtime/tomato_rt.c > "$work/leaky.c"
  clang -O1 -w -o "$work/leaky" "$work/p.ll" "$(rtcache_get "$work" o "$work/leaky.c" -O1 -pthread -w)" -pthread -lm   # (kept in the cache by what the file holds)
  case "$("$work/leaky" 2>&1)" in *"never freed"*) ok "release: a big number that is not freed is reported";; *) bad "release: a big number that is not freed is reported";; esac
}
section "== release mode (AddressSanitizer; the same output as debug mode) =="
for name in fast_paths loop_nests float_loops float_nests int_ranges int_fast_paths small_int_loops int_boundary temp_unwind native_sort compact_lists containers raise_paths raise_dead file_closed sys_run sys_async optional_narrowing_flow optional_narrowing_assign; do
  case "$name" in fast_paths|loop_nests|float_loops|float_nests|int_ranges|containers|raise_paths|raise_dead|file_closed) ;; *) [ -n "$fast" ] && { skip "release $name"; continue; } ;; esac   # (the fast tier: nine of the fifteen)
  case "$name" in fast_paths|loop_nests|float_loops|float_nests|raise_paths|raise_dead|sys_run|sys_async) spawn_first t_release_asan "$name" leaks ;; *) spawn_first t_release_asan "$name" ;; esac
done
spawn_first t_release_leak
spawn_first t_lock_gc

section "== sort: the heapsort fallback gives the same results =="
spawn t_sort_fallback

t_socket_many() { # more waiting tasks than descriptors the process may open
  "$c1" tests/programs/socket_many.tom main std/ > "$work/p.ll" 2>/dev/null && clang -O1 -w -o "$work/p" "$work/p.ll" "$rt_o" -pthread -lm
  check "300 tasks accept on one server with ulimit -n 64" "$(cat tests/expected/socket_many.main.out)" "$(ulimit -n 64; "$work/p" 2>&1)"
}
t_fd_wait() {
  clang -O1 -w -ffunction-sections -fdata-sections tests/fd_wait.c -Wl,-dead_strip -lm -o "$work/fd_wait" 2>/dev/null ||
    clang -O1 -w -ffunction-sections -fdata-sections tests/fd_wait.c -Wl,--gc-sections -lm -o "$work/fd_wait" || { bad "descriptor wait lifecycle builds" "compile failed"; return; }
  "$work/fd_wait" && ok "descriptor wait lifecycle" || bad "descriptor wait lifecycle" "test failed"
}
section "== descriptor wait lifecycle =="
spawn t_fd_wait
t_tty_slots() {   # the raw-mode slots of the terminal block: a descriptor closed by other means and then reused (on pseudo-terminals)
  clang -O1 -w -ffunction-sections -fdata-sections tests/tty_slots.c -Wl,-dead_strip -lm -o "$work/tty_slots" 2>/dev/null ||
    clang -O1 -w -ffunction-sections -fdata-sections tests/tty_slots.c -Wl,--gc-sections -lm -o "$work/tty_slots" || { bad "terminal raw slots build" "compile failed"; return; }
  "$work/tty_slots" >/dev/null && ok "terminal raw slots: a reused descriptor number is not taken for the raw terminal it was" || bad "terminal raw slots" "test failed"
}
spawn t_tty_slots

section "== sockets: more waiting tasks than descriptors the process may open =="
spawn t_socket_many

t_socket_lookup_async() { # force a slow lookup while a timer and cancellation run
  "$c1" tests/programs/socket_lookup_async.tom main std/ > "$work/p.ll" 2> "$work/compile.err" &&
    clang -O1 -w -o "$work/p" "$work/p.ll" "$rt_o" tests/runtime/socket_slow_lookup.c -Wl,--wrap=getaddrinfo -pthread -lm || { bad "slow lookup compiles" "$(cat "$work/compile.err")"; return; }
  check "slow lookup leaves timers and cancellation running" "timer ran: True
lookup cancelled
next lookup: 127.0.0.1" "$("$work/p" 2>&1)"
}
if [ "$(uname)" = Linux ]; then spawn t_socket_lookup_async; fi

# ---- requests -----------------------------------------------------------------------------------------------------------
start_httpd() { # a local server for this job: sets $port and $httpd_pid
  clang -O1 -w -o "$work/httpd" tests/http_server.c 2>/dev/null || return 1
  "$work/httpd" > "$work/httpd.port" & httpd_pid=$!
  i=0; while [ ! -s "$work/httpd.port" ] && [ $i -lt 600 ]; do nap; i=$((i + 1)); done   # the server prints its port once it is listening (up to 30 s on a busy machine)
  port="$(cat "$work/httpd.port")"
}
t_requests() { # one local server for this job's own requests; three parts: 1 requests_local (and with AddressSanitizer), 2 overlap, 3 the example builds
  part="${1:-1}"
  if step 1; then
    use_asan
    if start_httpd; then
      "$c1" tests/programs/requests_local.tom main std/ > "$work/rq.ll" 2> "$work/e"
      if grep -q '^;! ' "$work/rq.ll"; then bad "requests_local has warnings" "$(grep '^;! ' "$work/rq.ll" | head -4)"; fi
      if clang -O1 -w -o "$work/rq" "$work/rq.ll" "$rt_o" -pthread -lm 2>/dev/null; then
        check "requests against the local server" "$(cat tests/expected/requests_local.main.out)" "$("$work/rq" "http://127.0.0.1:$port" 2>&1)"
        if clang -O1 -w -g -fsanitize=address -o "$work/rq_asan" "$work/rq.ll" "$rt_asan" -pthread -lm 2>/dev/null; then
          out="$("$work/rq_asan" "http://127.0.0.1:$port" 2>&1 >/dev/null | head -14)"
          [ -z "$out" ] && ok "asan requests_local" || bad "asan requests_local" "$out"
        else bad "asan requests_local" "this clang cannot build with -fsanitize=address"; fi
      else bad "requests against the local server" "did not build: $(cat "$work/e")"; fi
      kill "$httpd_pid" 2>/dev/null
    else bad "requests test server" "tests/http_server.c did not build"; fi
  fi
  if step 2; then
    start_httpd || bad "requests test server" "tests/http_server.c did not build"
    # five requests that each take 1 s must overlap: the whole run is far below 5 s (when serialized they take 5 s or more). On a busy
    # machine one run can be slow by itself, so a run that took too long is made again (up to three runs); a wrong output is not
    cp tests/programs/requests_overlap.tom "$work/overlap.tom"
    "$c1" "$work/overlap.tom" main std/ > "$work/ov.ll" 2>/dev/null && clang -O1 -w -o "$work/ov" "$work/ov.ll" "$rt_o" -pthread -lm
    ov_try=1
    while :; do
      t0="$(date +%s)"; ovo="$("$work/ov" "http://127.0.0.1:$port" 2>&1)"; t1="$(date +%s)"
      [ "$ovo" = done ] && [ $((t1 - t0)) -ge 4 ] && [ "$ov_try" -lt 3 ] && { ov_try=$((ov_try + 1)); continue; }
      break
    done
    [ "$ovo" = done ] && [ $((t1 - t0)) -lt 4 ] && ok "requests overlap (5 x 1 s took $((t1 - t0)) s)" || bad "requests overlap" "output '$ovo' after $((t1 - t0)) s"
    kill "$httpd_pid" 2>/dev/null
  fi
  if step 3; then
    "$c1" examples/http_get.tom main std/ > "$work/hg.ll" 2> "$work/e" && clang -O1 -w -o "$work/hg" "$work/hg.ll" "$rt_o" -pthread -lm && ok "examples/http_get.tom builds" || bad "examples/http_get.tom builds" "$(cat "$work/e")"
  fi
}
section "== requests (tests/http_server.c is a local server: no internet needed) =="
for part in 1 2 3; do register t long t_requests "$part"; done

# ---- the same programs through WebAssembly ------------------------------------------------------------------------------
section "== the same programs through WebAssembly (site/wasm, the website and repl path) =="
# a JavaScript shell: jsc on macOS, else Node running the same script through native/jsc-on-node.js (the script is not changed)
jsc_mac=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc; have_js=""
if [ -x "$jsc_mac" ]; then have_js=1; jsc() { "$jsc_mac" "$@"; }
elif command -v node > /dev/null 2>&1; then have_js=1; jsc() { node "$root/native/jsc-on-node.js" "$@"; }; fi
# the toolchain script, with the run limit. A run the limit stopped (the toolchain says error[E369]: it ran out of time, on a machine that
# is busy) is run again with three times the limit, up to three runs in all; a wrong answer, a compile error, a crash or anything else is
# the first run's result, never run again. What it prints is what the last run printed (standard output, then standard error).
tjsc() {
  tj_ms="$TOMATO_WASM_TIMEOUT_MS"; tj_try=1
  while :; do
    jsc native/tomato-jsc.js -- "--timeout-ms=$tj_ms" "$@" > "$work/tj.out" 2> "$work/tj.err"; tj_rc=$?
    if [ "$tj_try" -lt 3 ] && grep -q '^error\[E369\]' "$work/tj.err"; then tj_ms=$((tj_ms * 3)); tj_try=$((tj_try + 1)); continue; fi
    cat "$work/tj.out"; cat "$work/tj.err" >&2; return "$tj_rc"
  done
}
t_wasm_program() {
  name="$1"
  tjsc site/wasm run "tests/programs/$name.tom" > "$work/js.out" 2> "$work/js.err"
  # the runner drops one trailing newline and adds an "~rc" line; compare ignoring both
  if [ "$(cat "$work/js.out")" = "$(cat "tests/expected/$name.main.out")" ]; then ok "wasm $name"; else bad "wasm $name" "$(diff "$work/js.out" "tests/expected/$name.main.out" | head -4; head -2 "$work/js.err")"; fi
}
# rejected programs and runtime errors through the same path (the messages and failures must agree with native)
t_wasm_neg() { m="$(tjsc site/wasm run "tests/negative/$1.tom" 2>&1)"; case "$m" in *"$2"*"~rc 1"*) ok "wasm rejects $1";; *) bad "wasm rejects $1" "wanted: $2
got: $m";; esac; }
t_wasm_rt() { m="$(tjsc site/wasm run "tests/runtime/$1.tom" 2>&1)"; case "$m" in *"$2"*"~rc $3"*) ok "wasm runtime $1";; *) bad "wasm runtime $1" "wanted: $2 (rc $3)
got: $m";; esac; }
# the fast tier runs these through WebAssembly (the others only in the full suite): a few of each kind
fast_wasm=" p:angles p:at_neg_rmul p:containers p:compact_fuzz p:open_errors p:modules p:numbers_rules p:iter_protocol p:async_tasks p:async_sync p:bigint_ops p:function_values p:sort_stable p:text_dict_methods p:time_module p:int_ranges p:web_modules p:datetime_parse p:random_basic p:secrets_basic p:re_api p:os_browser p:ospath_text p:assert_ok n:type_mismatch n:private_field n:bad_return r:divide_by_zero r:index r:error_classes r:caught r:stack_overflow r:async_lock_deadlock r:overflow r:datetime_errors r:trace_calls r:random_randint_empty r:exit_status "
wasm_wanted() { # KIND:NAME (p program, n rejected, r runtime error): is it run in this tier?
  case " $fast_wasm " in *" $1 "*) return 0 ;; esac
  [ -z "$fast" ] && return 0
  skip "wasm ${1#?:}"; return 1
}
wasm_program() { wasm_wanted "p:$1" && spawn_free t_wasm_program "$1"; }
wasm_neg() { wasm_wanted "n:$1" && spawn_free t_wasm_neg "$@"; }
wasm_rt() { wasm_wanted "r:$1" && spawn_free t_wasm_rt "$@"; }
t_wasm_browser() { r="$(tjsc site/wasm run tests/programs/requests_browser.tom 2>&1 | grep "no network")"; check "wasm requests raise ConnectionError" "no network: True" "$r"; }
# the website repl wraps what you type in a program (wrapMain): a piece with only an import must still be checked, not fail with "no @main"
t_wasm_repl_import() {
  jsc tests/repl_wrap.js -- 'from itertools import progres_bar' > "$work/imp.tom" 2>&1
  m="$(tjsc site/wasm run "$work/imp.tom" 2>&1)"
  case "$m" in *"error[E226]: module 'itertools' has no 'progres_bar'"*"did you mean 'progress_bar'?"*"~rc 1"*) ok "wasm repl: a bad import is reported as itself";; *) bad "wasm repl: a bad import is reported as itself" "$m";; esac
  jsc tests/repl_wrap.js -- 'from itertools import progress_bar' > "$work/imp2.tom" 2>&1
  m="$(tjsc site/wasm run "$work/imp2.tom" 2>&1)"
  case "$m" in *"~rc 0"*) ok "wasm repl: a good import alone runs";; *) bad "wasm repl: a good import alone runs" "$m";; esac
}
t_wasm_sockets() { r="$(tjsc site/wasm run tests/programs/socket_browser.tom 2>&1 | grep '^no ')"; check "wasm sockets raise SocketError" "no sockets: True E446
no listening: E446
no udp: E446
no lookup: E446" "$r"; }
t_wasm_test_entry() { # the entry name `test` in the browser path: the driver runs the @test functions, with the line, and the status is 1
  printf 'from testing import assert_equal, skip\n\n@test.adds\ndef adds():\n    assert_equal(1 + 1, 2)\n\n@test.fails\ndef fails():\n    assert_equal(1 + 1, 3)\n\n@test.lookup\ndef lookup():\n    skip("no network")\n' > "$work/wt.tom"
  m="$(tjsc site/wasm run "$work/wt.tom" --entry=test 2>&1 | grep -v '^Could not open file: ')"   # real jsc's read() prints that on standard error for each std module it looks for beside the program, caught or not (tomato-repl drops it too)
  case "$m" in "ok   adds
FAIL fails
     expected 3, got 2  (raised on line 9)
skip lookup  (no network)
1 passed, 1 failed, 1 skipped
~rc 1") ok "wasm: the entry test runs the @test functions";; *) bad "wasm: the entry test runs the @test functions" "$m";; esac
  m="$(tjsc site/wasm run "$work/wt.tom" --entry=test.adds 2>&1 | grep -v '^Could not open file: ')"
  case "$m" in "ok   adds
1 passed, 0 failed, 0 skipped
~rc 0") ok "wasm: the entry test.adds runs one test";; *) bad "wasm: the entry test.adds runs one test" "$m";; esac
  m="$(tjsc site/wasm run "$work/wt.tom" 2>&1)"
  case "$m" in *"no function is marked @main"*"~rc 1") ok "wasm: a test file without @main is not a program";; *) bad "wasm: a test file without @main is not a program" "$m";; esac
}
t_wasm_config() { # the browser path takes the limits from a tomato.toml given to the compiler (D77g); without one the defaults apply
  cat > "$work/wl.tom" <<'EOF2'
from math import exp
@main
def main():
    try:
        print(len(str(exp(float('1e5000')))) > 0)
    catch OverflowError as e:
        print(e.message, e.id)
    try:
        print(len(f"{float('1e1500'):.1f}"))
    catch OverflowError as e:
        print(e.message, e.id)
EOF2
  printf '[limits]\nexp_bits = 2048\nformat_digits = 1000\n' > "$work/wl.toml"
  m="$(tjsc site/wasm run "$work/wl.tom" 2>&1 | grep -v '^Could not open file: ')"
  case "$m" in "True
1503
~rc 0") ok "wasm: no tomato.toml means the default limits";; *) bad "wasm: no tomato.toml means the default limits" "$m";; esac
  m="$(tjsc site/wasm run "$work/wl.tom" "--config=$work/wl.toml" 2>&1 | grep -v '^Could not open file: ')"
  case "$m" in "the result is too large to calculate: its exponent would have more than 2048 bits E528
the number is too large to write with f: it has more than 1000 digits before the point E529
~rc 0") ok "wasm: the limits come from a tomato.toml given to the compiler";; *) bad "wasm: the limits come from a tomato.toml given to the compiler" "$m";; esac
  printf '[limits]\nexp_bits = 5\n' > "$work/wl.toml"
  m="$(tjsc site/wasm compile "$work/wl.tom" "--config=$work/wl.toml" 2>&1)"
  case "$m" in *"error[E543]: /tomato.toml: limits.exp_bits must be a whole number from 2048 to 2147483647, not 5"*"~rc 1") ok "wasm: a bad tomato.toml is an error";; *) bad "wasm: a bad tomato.toml is an error" "$m";; esac
}
t_wasm_site_errors() { r="$(jsc tests/site_errors.js 2>&1)"; [ "$r" = ok ] && ok "website: tomatoErrors keeps the words, escapes them, styles with classes" || bad "website: tomatoErrors" "$r"; }
t_highlighter_lists() { r="$(sh tests/highlighter_lists.sh 2>&1)"; [ "$r" = ok ] && ok "highlighters know every lexer keyword and built-in" || bad "highlighters" "$r"; }
t_wasm_site_editor() { r="$(jsc tests/site_editor.js 2>&1)"; [ "$r" = ok ] && ok "website: editor auto-indent after a colon, backspace and tab" || bad "website: editor auto-indent" "$r"; }
t_wasm_missing() { [ -n "$CI" ] && bad "wasm path" "jsc (macOS) or node is required in CI" || echo "skip: neither jsc nor node is available on this system"; }
if [ -n "$have_js" ]; then
  for name in trig_radians wave2_bytes hashlib_browser hmac_vectors struct_ints struct_floats angles angle_lists at_neg_rmul containers compact_lists compact_fuzz open_errors msgpack_file_basics unicode_case list_methods finally inheritance fixed_width text_and_maps modules numbers_rules range_value iter_protocol async_tasks async_toolkit async_sync async_queue_drop generics bigint_ops bigint_ownership bigint_frames bigint_unwind big_karatsuba big_division function_values lambdas sort_stable sort_errors sort_key_cmp cache_lru cache_multi memoize bit_types bit_names builtin_layout text_dict_methods dict_literal_inference dict_keys_any dict_keys_objects dict_keys_forms dict_keys_cycles tuple_for unicode_class mixed_tuples union_show optional_values optional_lookups optional_narrowing optional_narrowing_flow optional_narrowing_assign optional_error_paths time_module int_ranges range_wide int_to_float fast_ranges tuple_type_args url_parse url_quote html_escape base64_codec hex_codec web_modules datetime_arith datetime_format datetime_parse csv_module textwrap_module statistics_module re_api ospath_text os_browser terminal_browser string_io assert_ok testing_lib testing_diff float_any_size float_floor_mod float_ownership float_loops float_keys float_nests float_library float_limits; do
    wasm_program "$name"
  done
  spawn_free t_wasm_browser
  spawn_free t_wasm_sockets
  wasm_neg type_mismatch "cannot use '+' with int and str"
  wasm_neg fixed_range "300 does not fit in uint[length=8]"
  wasm_neg float_length_32 "float has no length"
  wasm_neg float_length_key "float has no length"
  wasm_neg private_field "the field 'x' is private to class 'C'"
  wasm_neg type_arg_count "'list' does not take several types here"
  wasm_neg type_in_unknown "this type is not supported here"
  wasm_neg bad_return "the returned value has type str, but int is expected"
  wasm_neg trig_needs_angle "argument 1 of 'sin' (the parameter 'a') has type float, but math.Angle is expected"
  wasm_rt divide_by_zero "division by zero" 1
  wasm_rt optional_int_none "None where a value is needed" 1
  wasm_rt index "index out of range" 1
  wasm_rt csv_unclosed_quote "a quoted CSV field is not closed" 1
  wasm_rt statistics_empty "statistics needs at least one data point" 1
  wasm_rt error_classes "$(cat tests/runtime/error_classes.out)" 0
  wasm_rt error_class_uncaught "error[E04]: index out of range" 1
  wasm_rt error_std_uncaught "error[E51]:" 1
  wasm_rt datetime_errors "$(cat tests/runtime/datetime_errors.out)" 0
  wasm_rt datetime_overflow "error[E407]: OverflowError: date value out of range" 1
  wasm_rt list_pop_empty "pop from an empty list" 1
  wasm_rt overflow "integer overflow" 1
  wasm_rt dict_missing_key "the key is not there" 1
  wasm_rt caught "caught boom" 0
  wasm_rt async_lock_deadlock "task 1 is waiting at line 6 for a lock held since line 5" 1
  wasm_rt async_lock_deadlock_task "task 2 is waiting at line 4 for a lock held since line 9" 1
  wasm_rt stack_overflow "stack overflow" 1
  wasm_rt tan_quarter "tan is not defined at 90 deg" 1
  wasm_rt caught_domain "caught sqrt needs a number that is not negative" 0
  for name in round_divmod_any_all text_methods_more math_more fstring_specs; do wasm_program "$name"; done
  wasm_rt partition_empty "partition needs a separator that is not empty" 1
  wasm_rt divmod_zero "division by zero" 1
  wasm_rt factorial_negative "factorial needs a number that is not negative, but got -1" 1
  wasm_rt text_math_caught "$(cat tests/runtime/text_math_caught.out)" 0
  wasm_neg fstring_text_sign "a format spec for text cannot have a sign"
  wasm_neg round_bad_type "round() takes an int or a float, but this is str"
  wasm_rt exp_large "1.970071114017047e+434" 0
  wasm_rt trace_calls "at half (line 10)" 1
  wasm_rt url_bad_ipv6 "Invalid IPv6 URL" 1
  wasm_rt base64_bad_padding "misplaced padding" 1
  wasm_rt hex_bad_digit "a hex text holds only the digits" 1
  wasm_rt exit_status "pending" 3
  wasm_neg assert_not_bool "a condition has type int, but bool is expected"
  wasm_rt assert_failed "error[E519]: AssertionError: x should be 4, but is 3 (raised on line 3)" 1
  spawn_free t_wasm_test_entry
  spawn_free t_wasm_config
  spawn_free t_wasm_site_errors
  spawn_free t_wasm_repl_import
  spawn_free t_wasm_site_editor
else spawn_free t_wasm_missing; fi

spawn_free t_highlighter_lists

# ---- command line -------------------------------------------------------------------------------------------------------
need_install() { # waits (up to 10 minutes) for t_install; a job whose install never reported fails instead of waiting for ever
  i=0; until [ -f "$shared/install.rc" ]; do
    nap; i=$((i + 1))
    [ "$i" -gt 12000 ] && { bad "install-native.sh did not finish"; exit 1; }
  done
}
step() { [ "$part" = "$1" ]; }   # a test that is split in parts runs the checks of its own part: t_cli_modes 2 is the second part of t_cli_modes
# Each job makes its own copies of the small programs the checks use, and waits for the install (t_install, started first).
cli_setup() { need_install; cli_files; }
cli_files() {
  printf 'print(1)\n' > "$work/top.tom"
  printf '@main\ndef main():\n    x = 0\n    print(5 // x)\n' > "$work/dz.tom"
  printf '@main\ndef main():\n    print(tets)\n' > "$work/typo.tom"
  printf '@main\ndef main(a: str, b: str):\n    print("[" + a + "][" + b + "]")\n' > "$work/echo.tom"
  printf '@main\ndef main():\n    print(range(100))\n    print(range(1, 100))\n    print(range(5, 10, 2))\n' > "$work/rangeprint.tom"
  printf '@main\ndef main():\n    half(0)\n\ndef half(n: int) -> int:\n    return 10 // n\n' > "$work/trace.tom"
  printf '@main\ndef main():\n    raise Error("bad")\n' > "$work/raised.tom"
  printf '@main\ndef main():\n    unused = 1\n    print(2)\n' > "$work/warn.tom"
}
t_cli_modes() {
  part="${1:-1}"; cli_setup
  if step 1; then
  [ "$(cat "$shared/install.rc")" = 0 ] && ok "install-native.sh" || bad "install-native.sh"
  r="$($t run "$work/top.tom" 2>&1)"; case "$r" in *"put it inside a function marked @main"*) ok "top-level code gives a clear hint";; *) bad "top-level code gives a clear hint" "$r";; esac
  check "version" "Tomato v$(cat VERSION) (compiler written in Tomato)" "$($t version)"
  check "mode debug is readable" "error[E01]: division by zero
  at main (line 4)" "$($t run "$work/dz.tom" 2>&1)"
  check "mode release prints a code" "error E01:4" "$($t run "$work/dz.tom" --mode release 2>&1)"
  fi; if step 2; then
  check "release keeps caught messages and IDs" "$(cat tests/runtime/error_classes.out)" "$($t run tests/runtime/error_classes.tom --mode release 2>&1)"
  check "open error keeps its message and ID in release" "$(cat tests/expected/open_errors.main.out)" "$($t run tests/programs/open_errors.tom --mode release 2>&1)"
  fi; if step 3; then
  check "uncaught open error has its debug ID" "error[E25]: could not open '/nonexistent_dir_for_tomato/missing.txt': No such file or directory
  at main (line 3)" "$($t run tests/runtime/open_missing.tom 2>&1)"
  check "uncaught open error has its release ID" "error E25:3" "$($t run tests/runtime/open_missing.tom --mode release 2>&1)"
  check "an uncaught use of a closed file has its debug ID and line" "error[E547]: I/O operation on a closed file
  at main (line 7)" "$($t run tests/runtime/file_closed_uncaught.tom 2>&1)"
  check "an uncaught use of a closed file has its release ID and line" "error E547:7" "$($t run tests/runtime/file_closed_uncaught.tom --mode release 2>&1)"
  fi; if step 4; then
  r="$($t run tests/runtime/msgpack_missing.tom --mode release 2>&1)"
  case "$r" in "error E25:"[1-9]*) ok "load_msgpack open error has its release ID";; *) bad "load_msgpack open error has its release ID" "$r";; esac
  fi; if step 5; then
  r="$($t run tests/runtime/error_std_uncaught.tom --mode release 2>&1)"
  case "$r" in "error E51:"[1-9]*) ok "release prints a library error ID and line";; *) bad "release prints a library error ID and line" "$r";; esac
  check "mode normal was renamed to release" "error[E281]: the mode 'normal' was renamed to 'release': use --mode release (the old release mode is gone)" "$($t run "$work/dz.tom" --mode normal 2>&1)"
  check "unknown mode is refused" "error[E282]: the mode must be debug or release, not 'fast'" "$($t run "$work/dz.tom" --mode fast 2>&1)"
  fi; if step 6; then
  $t build "$work/dz.tom" -o "$work/dz_rel" --mode release > /dev/null 2>&1; check "build --mode release makes a release binary" "error E01:4" "$("$work/dz_rel" 2>&1)"
  $t compile "$work/dz.tom" --mode release > "$work/dz_rel.ll" 2>&1
  grep -q tomato_report_uncaught "$work/dz_rel.ll" && ok "compile --mode release works" || bad "compile --mode release works" "$(head -3 "$work/dz_rel.ll")"
  if grep -q '^@tomato.name\.' "$work/dz_rel.ll"; then bad "release omits class name metadata"; else ok "release omits class name metadata"; fi
  if grep -Eq 'br i1 .*label %stop\.[0-9]+, label %ok\.[0-9]+, !prof !1$' "$work/dz_rel.ll" && grep -q '^!1 = !{!"branch_weights", i32 1, i32 10}$' "$work/dz_rel.ll"; then ok "release marks error branches unlikely"; else bad "release marks error branches unlikely"; fi
  $t compile "$work/dz.tom" --mode debug > "$work/dz_debug.ll" 2>&1
  if grep -Eq 'br i1 .*label %stop\.[0-9]+, label %ok\.[0-9]+$' "$work/dz_debug.ll" && ! grep -q '!prof' "$work/dz_debug.ll"; then ok "debug error branches remain unweighted"; else bad "debug error branches remain unweighted"; fi
  if [ -n "$have_js" ]; then
    $t compile tests/runtime/error_classes.tom --mode release > "$work/errors_rel.ll" 2>&1
    r="$(tjsc site/wasm run-ir "$work/errors_rel.ll" 2> "$work/errors_rel.err")"
    check "wasm interpreter runs weighted error branches" "$(cat tests/runtime/error_classes.out)" "$r"
    grep -q '^~rc 0$' "$work/errors_rel.err" && ok "weighted wasm run succeeds" || bad "weighted wasm run succeeds" "$(cat "$work/errors_rel.err")"
  fi
  fi
}
# release links with LTO and an inlined runtime: the same programs must print exactly what debug mode prints
t_cli_release_like_debug() { cli_setup; check "release mode runs $1 like debug" "$(cat "tests/expected/$1.main.out")" "$($t run "tests/programs/$1.tom" --mode release 2>&1)"; }
t_cli_no_lto() { # release with a clang whose linker has no LLVM plugin (-flto fails when linking): clang merges the runtime into the program instead
  cli_setup
  mkdir -p "$work/nolto"; printf '#!/bin/sh\ncase " $* " in *" -flto "*) case " $* " in *" -c "*) ;; *) exit 1 ;; esac ;; esac\nexec "%s" "$@"\n' "$(command -v clang)" > "$work/nolto/clang"; chmod +x "$work/nolto/clang"
  m=release; PATH="$work/nolto:$PATH" $t run tests/programs/int_fast_paths.tom --mode "$m" > "$work/out" 2> "$work/err"
  check "without link-time optimisation in the linker ($m)" "$(cat tests/expected/int_fast_paths.main.out)" "$(cat "$work/out")"
  check "LTO fallback is visible ($m)" 'warning: LTO link failed; using clang bitcode merge instead' "$(cat "$work/err")"
  # Also force the merge to fail: the plain link must announce its loss of cross-module optimization.
  printf '#!/bin/sh\ncase " $* " in *" -mlink-bitcode-file "*) exit 1 ;; *" -flto "*) case " $* " in *" -c "*) ;; *) exit 1 ;; esac ;; esac\nexec "%s" "$@"\n' "$(command -v clang)" > "$work/nolto/clang"
  PATH="$work/nolto:$PATH" $t run tests/programs/int_fast_paths.tom --mode "$m" > "$work/out" 2> "$work/err"
  check "plain link output ($m)" "$(cat tests/expected/int_fast_paths.main.out)" "$(cat "$work/out")"
  check "plain link warning ($m)" 'warning: LTO link failed; linking without cross-module optimization' "$(cat "$work/err")"
}
t_cli_require_lto() { # Release gate: the real Tomato build must take the successful LTO link path.
  [ "${TOMATO_TEST_REQUIRE_LTO:-0}" = 1 ] || return 0
  cli_setup; mkdir -p "$work/spy"
  printf '#!/bin/sh\ncase " $* " in *" -flto "*) case " $* " in *" -c "*) ;; *) echo link >> "%s/lto-links" ;; esac ;; esac\nexec "%s" "$@"\n' "$work" "$(command -v clang)" > "$work/spy/clang"
  chmod +x "$work/spy/clang"
  for m in release; do   # (debug mode does not use LTO: t_cli_debug_link)
    rm -f "$work/lto-links" "$work/lto-program"
    PATH="$work/spy:$PATH" $t build tests/programs/int_fast_paths.tom --mode "$m" -o "$work/lto-program" > "$work/out" 2> "$work/err"
    if [ -x "$work/lto-program" ] && [ -s "$work/lto-links" ] && [ ! -s "$work/err" ]; then ok "Tomato $m build used LTO"; else bad "Tomato $m build used LTO" "$(cat "$work/err")"; fi
  done
}
t_cli_debug_link() { # debug mode links without LTO: the inline fast paths (runtime/tomato_inline.ll) are put in front of the program and its calls renamed
  cli_setup; mkdir -p "$work/spy"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in *.inl.ll) cp "$a" "%s/merged.ll"; [ -n "$FAIL_INLINE" ] && exit 1 ;; esac; done\necho "$*" >> "%s/args"\nexec "%s" "$@"\n' "$work" "$work" "$(command -v clang)" > "$work/spy/clang"
  chmod +x "$work/spy/clang"
  PATH="$work/spy:$PATH" $t run tests/programs/int_fast_paths.tom > "$work/out" 2> "$work/err"
  check "debug link: the program runs right" "$(cat tests/expected/int_fast_paths.main.out)" "$(cat "$work/out")"
  check "debug link: no warning" "" "$(cat "$work/err")"
  check "debug link: no LTO and no bitcode merge" "0" "$(grep -c -e '-flto' -e 'mlink-bitcode' "$work/args")"
  check "debug link: the inline fast paths are in the program" "yes" "$(grep -q '^define internal i64 @tomato_inl_int_add_c' "$work/merged.ll" && grep -q 'call i64 @tomato_inl_int_sub_c(' "$work/merged.ll" && echo yes)"
  check "debug link: the program no longer calls the runtime's own copies" "0" "$(grep -v '^  *%.* = call i64 @tomato_int_[a-z0-9_]*_c(i64 %x, i64 %y, i32 %m)$' "$work/merged.ll" | grep -c 'call i64 @tomato_int_\(add\|sub\|mul\)_c(')"
  rm -f "$work/merged.ll"
  FAIL_INLINE=1 PATH="$work/spy:$PATH" $t run tests/programs/int_fast_paths.tom > "$work/out" 2> "$work/err"
  check "debug link: without the inline fast paths the program still runs right" "$(cat tests/expected/int_fast_paths.main.out)" "$(cat "$work/out")"
  check "debug link: ... and says so" "warning: the inline fast paths could not be used; linked without them (slower)" "$(sed -n 1p "$work/err")"
  # text that looks like a call of a runtime function, inside string constants, must not be renamed (it made clang reject the merged program,
  # and the build fell back to the link without the inline copies)
  cat > "$work/inl_strings.tom" <<'EOS'
@main
def main():
    print('call void @tomato_retain(ptr')
    print('x @tomato_x(1) and @tomato_int_add_c(2) "q" @tomato_retain(')
    n = 0
    for i in range(3):
        n += i
    print(f'@tomato_int_dup({n})')
EOS
  rm -f "$work/merged.ll" "$work/args"
  PATH="$work/spy:$PATH" $t run "$work/inl_strings.tom" > "$work/out" 2> "$work/err"
  check "debug link: a program with @tomato_ text in strings runs right" "$(printf 'call void @tomato_retain(ptr\nx @tomato_x(1) and @tomato_int_add_c(2) "q" @tomato_retain(\n@tomato_int_dup(3)')" "$(cat "$work/out")"
  check "debug link: ... without a warning" "" "$(cat "$work/err")"
  check "debug link: ... the strings are kept as written, the calls are renamed" "yes" "$(grep -q 'c"call void @tomato_retain(ptr' "$work/merged.ll" && ! grep -q 'c".*@tomato_inl_' "$work/merged.ll" && grep -q 'call i64 @tomato_inl_int_add_c(' "$work/merged.ll" && echo yes)"
}
t_cli_inline_paths() { # the inline copies must do what the runtime's functions do: programs about the edges of the small number range, in the debug link
  cli_setup; check "debug link runs $1 like the plain link" "$(cat "tests/expected/$1.main.out")" "$($t run "tests/programs/$1.tom" 2>&1)"
}
t_cli_runtime_cache() { # the compiled runtime is kept in the cache folder: a hit, a miss for every change of key, concurrent runs, no cache
  # three parts, each with a cache folder of its own: 1 the entries (a hit, release is another entry), 2 the changes of the key (the runtime
  # source, the clang version), 3 concurrent runs and no cache. They use a copy of the command that the compiler built above completes
  # (the same layout as benchmarks/run.sh makes), not the installed one: the test is about the cache, and need not wait for the install
  part="${1:-1}"; cli_files
  h="$work/h"; mkdir -p "$h/bin"; cp native/tomato native/rtcache.sh "$h/bin/"; cp "$c1" "$h/bin/tomatoc"; cp -R runtime std VERSION "$h/"   # a copy whose runtime the test may change
  mkdir -p "$work/spy"; real="$(command -v clang)"
  # a clang that logs each compile of an object (-c) and, with FAKE_CLANG_VERSION, reports another version
  printf '#!/bin/sh\ncase " $* " in *" -c "*) echo "$*" >> "%s/compiles" ;; esac\n[ -n "$FAKE_CLANG_VERSION" ] && [ "$1" = --version ] && { echo "$FAKE_CLANG_VERSION"; exit 0; }\nexec "%s" "$@"\n' "$work" "$real" > "$work/spy/clang"; chmod +x "$work/spy/clang"
  export TOMATO_CACHE_DIR="$work/cache"; PATH="$work/spy:$PATH"
  r() { $h/bin/tomato run "$work/echo.tom" main a b "$@"; }   # (a program with arguments: --mode goes before them)
  compiles() { [ -f "$work/compiles" ] && wc -l < "$work/compiles" | tr -d ' ' || echo 0; }
  files() { ls "$work/cache" 2>/dev/null | grep -c '^rt-'; }
  want="[a][b]"
  if step 1; then
  check "runtime cache: a first run is right" "$want" "$(r 2>&1)"
  check "runtime cache: a first run compiles the runtime once and stores it" "1 1" "$(compiles) $(files)"
  ino="$(ls -i "$work/cache"/rt-* | cut -d' ' -f1)"
  check "runtime cache: a second run is right" "$want" "$(r 2>&1)"
  check "runtime cache: a second run is a hit (no compile, the file is not replaced)" "1 1 $ino" "$(compiles) $(files) $(ls -i "$work/cache"/rt-* | cut -d' ' -f1)"
  $h/bin/tomato build "$work/echo.tom" -o "$work/echo_d" > /dev/null 2>&1; check "runtime cache: build uses the same entry" "1 1" "$(compiles) $(files)"
  check "runtime cache: a built program runs" "$want" "$("$work/echo_d" main a b 2>&1)"
  check "runtime cache: release is another entry" "$want" "$($h/bin/tomato run --mode release "$work/echo.tom" main a b 2>&1)"
  check "runtime cache: release compiled the runtime once more" "2 2" "$(compiles) $(files)"
  $h/bin/tomato run --mode release "$work/echo.tom" main a b > /dev/null 2>&1; check "runtime cache: release hits too" "2 2" "$(compiles) $(files)"
  fi; if step 2; then
  r > /dev/null 2>&1; c0="$(compiles)"; f0="$(files)"   # (this part starts from one stored entry)
  printf '\n/* a change to the runtime */\n' >> "$h/runtime/tomato_rt.c"
  check "runtime cache: a changed runtime source is right" "$want" "$(r 2>&1)"
  check "runtime cache: a changed runtime source is a miss with its own entry" "$((c0 + 1)) $((f0 + 1))" "$(compiles) $(files)"
  check "runtime cache: another clang version is a miss with its own entry" "$want" "$(FAKE_CLANG_VERSION='clang version 0.0 (fake)' r 2>&1)"
  check "runtime cache: another clang version compiled once more" "$((c0 + 2)) $((f0 + 2))" "$(compiles) $(files)"
  fi; if step 3; then
  # concurrent runs on an empty cache: all right, one entry, no leftover temporary file, and the entry is whole (the next run hits)
  rm -rf "$work/cache"; : > "$work/compiles"; k=0; : > "$work/conc.out"
  while [ $k -lt 8 ]; do ( r > "$work/conc.$k" 2>&1 ) & k=$((k + 1)); done; wait
  k=0; bad_runs=0; while [ $k -lt 8 ]; do [ "$(cat "$work/conc.$k")" = "$want" ] || bad_runs=$((bad_runs + 1)); k=$((k + 1)); done
  check "runtime cache: 8 concurrent runs on an empty cache are all right" "0" "$bad_runs"
  check "runtime cache: concurrent runs leave one entry and no temporary file" "1 0" "$(files) $(ls -A "$work/cache" | grep -c '^\.tmp\.')"
  n0="$(compiles)"; r > /dev/null 2>&1; check "runtime cache: the entry the concurrent runs left is whole (a hit)" "$n0" "$(compiles)"
  fi; if step 4; then
  $h/bin/tomato build "$work/echo.tom" -o "$work/echo_d" > /dev/null 2>&1
  # no cache: off, and a folder that cannot be made (a file is in the way); both still run, and nothing is stored
  rm -rf "$work/cache"; check "runtime cache: TOMATO_CACHE=off still runs" "$want" "$(TOMATO_CACHE=off r 2>&1)"
  check "runtime cache: TOMATO_CACHE=off stores nothing" "0" "$(files)"
  : > "$work/notdir"; check "runtime cache: an unusable cache folder still runs" "$want" "$(TOMATO_CACHE_DIR="$work/notdir/x" r 2>&1)"
  check "runtime cache: the program is the same with and without the cache" "$(TOMATO_CACHE=off $h/bin/tomato build "$work/echo.tom" -o "$work/e_off" >/dev/null 2>&1; "$work/e_off" main a b 2>&1)" "$("$work/echo_d" main a b 2>&1)"
  fi
}
t_cli_build_keeps_source() { # tomato build of a file without .tom (or -o naming the source) must not overwrite the source
  cli_setup; mkdir -p "$work/bk"; printf '@main\ndef main():\n    print(7)\n' > "$work/bk/noext"; cp "$work/bk/noext" "$work/bk/p q.tom"
  (cd "$work/bk" && $t build noext > /dev/null 2>&1); r1=$?
  $t build "$work/bk/p q.tom" -o "$work/bk/p q.tom" > /dev/null 2>&1; r2=$?
  check "build refuses to overwrite its own source" "1 1 2" "$r1 $r2 $(cat "$work/bk/noext" "$work/bk/p q.tom" | grep -c 'print(7)')"
}
t_cli_release_no_leak() { cli_setup; $t build tests/programs/cycle.tom -o "$work/cyc_rel" --mode release > /dev/null 2>&1; check "release mode does not print a leak report" "$(cat tests/expected/cycle.main.out)" "$("$work/cyc_rel" 2>&1)"; }
t_cli_explain() {
  cli_setup
  check "explain decodes a release code" "error[E01]: ZeroDivisionError: division by zero" "$($t explain E01:4 "$work/dz.tom" 2>&1 | head -1)"
  check "explain shows the source line like a compile error" "error[E01]: ZeroDivisionError: division by zero
 --> $work/dz.tom:4
  |
4 |     print(5 // x)
  |     ^^^^^^^^^^^^^" "$($t explain E01:4 "$work/dz.tom")"
  check "explain decodes an id without a file" "error[E04]: IndexError: index out of range" "$($t explain E04)"
  check "explain accepts an ID with no source location" "error[E350]: RuntimeError: stack overflow: a function calls itself too deeply" "$($t explain E350:0 "$work/dz.tom")"
  check "explain rejects a malformed source line" "1" "$($t explain 'E04:4abc' "$work/dz.tom" >/dev/null 2>&1; echo $?)"
  check "run with inputs" "17 True" "$($t run examples/args.tom prime 17)"
  check "run with inputs and *args" "$(printf '8 2 True\nb\nc')" "$($t run tests/programs/sys_args.tom main 7 b c)"
  printf '@main\ndef main(n: int = 3):\n    print(n)\n' > "$work/bigin.tom"
  check "a big number given to an input with a default is freed" "99999999999999999999999" "$($t run "$work/bigin.tom" main 99999999999999999999999 2>&1)"
  check "--version is version" "$($t version)" "$($t --version)"
  case "$($t help)" in *"tomato explain"*"tomato version"*) ok "help lists every command";; *) bad "help lists every command" "$($t help)";; esac
  check "explain says when the line is not in the file" "error[E01]: ZeroDivisionError: division by zero
  (line 999 is past the end of $work/dz.tom: is this the file the program was built from?)" "$($t explain E01:999 "$work/dz.tom")"
  check "unknown command exits 2" "2" "$($t wghwrltghs >/dev/null 2>&1; echo $?)"
}
t_cli_config() { # [limits] in tomato.toml and the user's config.toml (D77g): found by tomato, read by the compiler, written into the program
  cli_setup
  P="$work/proj"; mkdir -p "$P/sub/deep" "$work/uh"
  cat > "$P/sub/deep/lim.tom" <<'EOF2'
from math import exp
@main
def main():
    try:
        print(len(str(exp(float('1e5000')))) > 0)
    catch OverflowError as e:
        print(e.message, e.id)
    try:
        print(len(f"{float('1e1500'):.1f}"))
    catch OverflowError as e:
        print(e.message, e.id)
    try:
        print(len(str(float('1e5000') ** float('1e5000'))) > 0)
    catch OverflowError as e:
        print(e.message, e.id)
EOF2
  here="$(cd "$P" && pwd -P)"
  noconf() { TOMATO_HOME="$work/uh" "$@"; }
  check "config: no files, the built-in defaults" "project file: none found
user file: none found
limits.exp_bits = 65536  (built-in default)
limits.format_digits = 100000  (built-in default)" "$(cd "$P" && noconf $t config)"
  check "config: with no limits set the program prints as before" "True
1503
True" "$(noconf $t run "$P/sub/deep/lim.tom")"
  noconf $t compile "$P/sub/deep/lim.tom" 2>&1 | grep -q tomato_set_limits && bad "config: default limits add nothing to the IR" || ok "config: default limits add nothing to the IR"
  printf '[limits]\nexp_bits = 2048\nformat_digits = 1_000\n' > "$P/tomato.toml"
  check "config: the nearest tomato.toml is found from a parent folder" "project file: $here/tomato.toml
user file: none found
limits.exp_bits = 2048  ($here/tomato.toml)
limits.format_digits = 1000  ($here/tomato.toml)" "$(noconf $t config "$P/sub/deep/lim.tom")"
  want="the result is too large to calculate: its exponent would have more than 2048 bits E528
the number is too large to write with f: it has more than 1000 digits before the point E529
the result is too large to calculate: its exponent would have more than 2048 bits E528"
  check "config: run uses the project limits (E528 and E529 say the number)" "$want" "$(noconf $t run "$P/sub/deep/lim.tom")"
  check "config: release mode uses them too" "$want" "$(noconf $t run "$P/sub/deep/lim.tom" --mode release)"
  noconf $t build "$P/sub/deep/lim.tom" -o "$work/lim_bin" > /dev/null 2>&1; rm "$P/tomato.toml"
  check "config: a built program keeps its limits and reads no file" "$want" "$("$work/lim_bin")"
  printf '[limits]\nexp_bits = 4096\nformat_digits = 7000\n' > "$work/uh/config.toml"
  printf '# a seed manifest too\n[seed]\nname = "a.example/x"\nversion = "1.0.0"\ntomato = "0.51"\n\n[limits]\nformat_digits = 9000\n' > "$P/sub/tomato.toml"
  check "config: the project file overrides the user's file, setting by setting; other tables are left alone" "project file: $here/sub/tomato.toml
user file: $work/uh/config.toml
limits.exp_bits = 4096  ($work/uh/config.toml)
limits.format_digits = 9000  ($here/sub/tomato.toml)
seed: a.example/x 1.0.0 (needs Tomato 0.51 or newer)" "$(TOMATO_HOME="$work/uh" $t config "$P/sub/deep/lim.tom")"
  rm "$P/sub/tomato.toml"; printf '[limits]\nformat_digits = 1000\n' > "$work/uh/config.toml"
  check "config: the user's file alone (the other limit stays at its default)" "True
the number is too large to write with f: it has more than 1000 digits before the point E529
True" "$(TOMATO_HOME="$work/uh" $t run "$P/sub/deep/lim.tom")"
  rm -f "$work/uh/config.toml"
  badcfg() { printf '%s' "$2" > "$P/tomato.toml"; r="$(noconf $t run "$P/sub/deep/lim.tom" 2>&1)"; rc=$?; check "config: $1" "$3
1" "$r
$rc"; }
  badcfg "a limit below what a double reaches is refused" '[limits]
exp_bits = 100
' "error[E543]: $here/tomato.toml: limits.exp_bits must be a whole number from 2048 to 2147483647, not 100"
  badcfg "a limit above what the runtime can build is refused" '[limits]
format_digits = 2147483648
' "error[E543]: $here/tomato.toml: limits.format_digits must be a whole number from 1000 to 2147483647, not 2147483648"
  badcfg "a limit that is not an integer is refused" '[limits]
format_digits = "many"
' "error[E543]: $here/tomato.toml: limits.format_digits must be a whole number from 1000 to 2147483647, not \"many\""
  badcfg "an unknown setting is an error" '[limits]
exp_bit = 5000
' "error[E542]: $here/tomato.toml: unknown setting limits.exp_bit (the settings are exp_bits and format_digits)"
  badcfg "limits must be a table" 'limits = 5
' "error[E541]: $here/tomato.toml: limits must be a table ([limits]), not an integer"
  r="$(printf '[limits\n' > "$P/tomato.toml"; noconf $t config "$P/sub/deep/lim.tom" 2>&1)"
  case "$r" in "error[E540]: the configuration file $here/tomato.toml is not valid TOML: "*) ok "config: text that is not TOML is an error naming the file";; *) bad "config: text that is not TOML is an error naming the file" "$r";; esac
  rm -f "$P/tomato.toml"; printf '[limits]\n' > "$work/uh/config.toml"; chmod 000 "$work/uh/config.toml"
  if [ ! -r "$work/uh/config.toml" ]; then   # (not when the tests run as root, which reads anything)
    r="$(noconf $t config "$P/sub/deep/lim.tom" 2>&1)"
    case "$r" in "error[E539]: the configuration file $work/uh/config.toml cannot be read: "*) ok "config: a file that cannot be read is an error naming the file";; *) bad "config: a file that cannot be read is an error naming the file" "$r";; esac
  fi
  check "explain knows the configuration errors" "error[E543]: ConfigError: {}: limits.{} must be a whole number from {} to {}, not {}" "$($t explain E543)"
  case "$($t help)" in *"tomato config [FILE]"*) ok "tomato help lists the config command";; *) bad "tomato help lists the config command" "$($t help)";; esac
}
t_cli_manifest() { # the strict reader of tomato.toml (D92a, D92b, D95a): tables, keys, errors with ids, the `tomato` minimum, `tomato config`
  cli_setup
  P="$work/mproj"; mkdir -p "$P/sub" "$work/uh"
  printf '@main\ndef main():\n    print(1)\n' > "$P/sub/prog.tom"
  here="$(cd "$P" && pwd -P)"
  noconf() { TOMATO_HOME="$work/uh" "$@"; }
  head='[project]
name = "demo"
version = "0.3.0"
tomato = "0.51"
'
  printf '%s' "$head" > "$P/tomato.toml"
  check "manifest: a project manifest is accepted" "1" "$(noconf $t run "$P/sub/prog.tom" 2>&1)"
  check "manifest: tomato config names the kind, the name, the version and the compiler it needs" "project file: $here/tomato.toml
user file: none found
limits.exp_bits = 65536  (built-in default)
limits.format_digits = 100000  (built-in default)
project: demo 0.3.0 (needs Tomato 0.51 or newer)" "$(noconf $t config "$P/sub/prog.tom")"
  printf '[seed]\nname = "acme.example/demo"\nversion = "1.0.0-rc.1"\ntomato = "0.51.0"\n' > "$P/tomato.toml"
  check "manifest: a seed manifest is accepted; config shows it" "seed: acme.example/demo 1.0.0-rc.1 (needs Tomato 0.51.0 or newer)" "$(noconf $t config "$P/sub/prog.tom" | tail -n 1)"
  printf '[limits]\nexp_bits = 4096\n' > "$P/tomato.toml"
  check "manifest: a settings-only file (D77g) is still accepted" "1" "$(noconf $t run "$P/sub/prog.tom" 2>&1)"
  badman() { printf '%s' "$2" > "$P/tomato.toml"; r="$(noconf $t run "$P/sub/prog.tom" 2>&1)"; check "manifest: $1" "$3" "$r"; }
  badman "an unknown table is an error, so a typo is caught" '[sedes]
' "error[E555]: $here/tomato.toml: unknown table [sedes] (the tables are project, seed, seeds, test-seeds, seed-store, build, limits; every setting is in a table)"
  badman "a key outside every table is an error" 'name = "x"
' "error[E555]: $here/tomato.toml: unknown key name (the tables are project, seed, seeds, test-seeds, seed-store, build, limits; every setting is in a table)"
  badman "a project and a seed together" "$head"'[seed]
name = "a.example/x"
version = "1.0.0"
tomato = "0.51"
' "error[E556]: $here/tomato.toml: the file has both [project] and [seed]: a folder is a project (a program that uses seeds) or a seed (a package), not both"
  badman "an unknown key in [project]" "$head"'license = "MIT"
' "error[E558]: $here/tomato.toml: unknown setting project.license (the settings of [project] are name, version, tomato)"
  badman "a missing setting" '[project]
name = "demo"
version = "0.3.0"
' "error[E557]: $here/tomato.toml: [project] needs the setting tomato"
  badman "a version needs three numbers" '[project]
name = "demo"
version = "0.3"
tomato = "0.51"
' "error[E560]: $here/tomato.toml: project.version is \"0.3\", which is not a version: it needs three numbers, MAJOR.MINOR.PATCH, such as 1.2.0"
  badman "a seed name needs an owner" '[seed]
name = "json5"
version = "1.0.0"
tomato = "0.51"
' "error[E561]: $here/tomato.toml: seed.name \"json5\" is not a seed name: a seed name is owner/name with exactly one slash"
  badman "a git seed in a seed is refused" '[seed]
name = "a.example/x"
version = "1.0.0"
tomato = "0.51"
[seeds]
"b.example/y" = { git = "https://h/y.git", rev = "abc" }
' "error[E563]: $here/tomato.toml: seeds.\"b.example/y\" is a git seed, and only a project can use those: a seed can use only registered seeds, written as \"1.2.0\""
  badman "[seeds] without a project or a seed" '[seeds]
"b.example/y" = "1.0.0"
' "error[E567]: $here/tomato.toml: [seeds] needs a [project] table (a program) or a [seed] table (a package) in the same file"
  badman "the build mode is checked" "$head"'[build.test]
mode = "fast"
' "error[E565]: $here/tomato.toml: build.test.mode must be \"debug\" or \"release\", not \"fast\""
  badman "build.target is reserved" "$head"'[build]
target = "wasm"
' "error[E566]: $here/tomato.toml: build.target is reserved for a later version and cannot be set yet"
  badman "an unknown build setting" "$head"'[build]
flags = []
' "error[E558]: $here/tomato.toml: unknown setting build.flags (the settings of [build] are mode and output, and a table [build.ENTRY] sets them for one entry)"
  badman "a [seeds.ENTRY] table is refused and points at [test-seeds] (D94b)" "$head"'[seeds.test]
"a.example/x" = "1.0.0"
' "error[E590]: $here/tomato.toml: [seeds.test] is not allowed: a table in [seeds] names a seed with a slash, \"owner/name\"; seeds used only by tests go in [test-seeds], the one table for them"
  badman "a [test-seeds] table below it is refused too" "$head"'[test-seeds.x]
"a.example/x" = "1.0.0"
' "error[E590]: $here/tomato.toml: [test-seeds.x] is not allowed: a table in [test-seeds] names a seed with a slash, \"owner/name\"; seeds used only by tests go in [test-seeds], the one table for them"
  badman "[test-seeds] needs a project or a seed" '[test-seeds]
"a.example/x" = "1.0.0"
' "error[E567]: $here/tomato.toml: [test-seeds] needs a [project] table (a program) or a [seed] table (a package) in the same file"
  badman "[test-seeds] takes seeds, not other keys" "$head"'[test-seeds]
foo = "1.0.0"
' "error[E555]: $here/tomato.toml: unknown key \"foo\" in [test-seeds]: a seed is written \"owner/name\" with a slash"
  printf '%s[test-seeds]\n"a.example/x" = "1.0.0"\n' "$head" > "$P/tomato.toml"
  check "manifest: a manifest with [test-seeds] is accepted" "1" "$(noconf $t run "$P/sub/prog.tom" 2>&1)"
  rm -f "$P/tomato.toml"
  badman "a minimum compiler version newer than this one stops the build" '[project]
name = "demo"
version = "0.3.0"
tomato = "9.1"
' "error[E562]: $here/tomato.toml: this needs Tomato 9.1 or newer, and this is Tomato $(cat VERSION)
  = help: install a newer release with \`tomato update\`"
  badman "a minimum equal to this compiler passes" "[project]
name = \"demo\"
version = \"0.3.0\"
tomato = \"$(cat VERSION)\"
" "1"
  check "manifest: the file is checked by every command, config included" "error[E555]: $here/tomato.toml: unknown table [x] (the tables are project, seed, seeds, test-seeds, seed-store, build, limits; every setting is in a table)" "$(printf '[x]\n' > "$P/tomato.toml"; noconf $t config "$P/sub/prog.tom" 2>&1)"
  check "manifest: so is compile" "error[E555]: $here/tomato.toml: unknown table [x] (the tables are project, seed, seeds, test-seeds, seed-store, build, limits; every setting is in a table)" "$(noconf $t compile "$P/sub/prog.tom" 2>&1)"
  check "explain knows the manifest errors" "error[E555]: ConfigError: {}: unknown {} {} (the tables are {}; every setting is in a table)" "$($t explain E555)"
  check "tomato help lists the seed commands" "8" "$($t help | grep -c 'tomato seed ')"
}
t_cli_build_tables() { # [build] and [build.ENTRY] (D92c): mode and output, the flags win, a seed's [build] is ignored
  cli_setup
  P="$work/bproj"; mkdir -p "$P/sub" "$work/uh"
  here="$(cd "$P" && pwd -P)"
  noconf() { TOMATO_HOME="$work/uh" "$@"; }
  # a program that fails: debug mode says what and where, release mode prints a short code
  printf '@main\ndef main():\n    print(1)\n\n@crash\ndef crash():\n    raise ValueError("boom")\n\n@other\ndef other():\n    raise ValueError("boom")\n\n@test\ndef a_test():\n    assert 1 + 1 == 2\n' > "$P/sub/prog.tom"
  head='[project]
name = "demo"
version = "0.3.0"
tomato = "0.51"
'
  mode_of() { case "$("$@" 2>&1)" in "error E"*) echo release ;; "error: ValueError: boom"*) echo debug ;; *) echo other ;; esac; }
  printf '%s' "$head" > "$P/tomato.toml"
  check "build tables: no [build] means debug" "debug" "$(mode_of noconf $t run "$P/sub/prog.tom" crash)"
  printf '%s[build]\nmode = "release"\n' "$head" > "$P/tomato.toml"
  check "build tables: [build] mode release applies to run" "release" "$(mode_of noconf $t run "$P/sub/prog.tom" crash)"
  check "build tables: --mode debug wins over the file" "debug" "$(mode_of noconf $t run --mode debug "$P/sub/prog.tom" crash)"
  printf '%s[build]\nmode = "debug"\n' "$head" > "$P/tomato.toml"
  check "build tables: --mode release wins over a debug file" "release" "$(mode_of noconf $t run --mode release "$P/sub/prog.tom" crash)"
  printf '%s[build]\nmode = "release"\n[build.crash]\nmode = "debug"\n' "$head" > "$P/tomato.toml"
  check "build tables: [build.ENTRY] overrides [build] for that entry" "debug release" "$(mode_of noconf $t run "$P/sub/prog.tom" crash) $(mode_of noconf $t run "$P/sub/prog.tom" other)"
  check "build tables: build takes --entry the same way" "wrote e1" "$(cd "$P" && noconf $t build sub/prog.tom --entry crash -o e1 2>&1)"
  printf '%s[build]\nmode = "release"\n[build.test]\nmode = "debug"\n' "$head" > "$P/tomato.toml"
  r="$(noconf $t test "$P/sub/prog.tom" 2>&1)"
  case "$r" in "ok   $P/sub/prog.tom  (1 passed)"*"tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok") ok "build tables: tomato test reads [build.test]";; *) bad "build tables: tomato test reads [build.test]" "$r";; esac
  r="$(noconf $t test --mode release "$P/sub/prog.tom" 2>&1)"
  case "$r" in *"(1 passed)"*"tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok") ok "build tables: tomato test --mode release still runs";; *) bad "build tables: tomato test --mode release still runs" "$r";; esac
  # output
  printf '%s[build]\noutput = "out/app"\n[build.crash]\noutput = "/dev/null/never"\n' "$head" > "$P/tomato.toml"
  r="$(noconf $t build "$P/sub/prog.tom" 2>&1)"
  check "build tables: [build] output is relative to the manifest's folder and its folder is made" "wrote $here/out/app" "$(echo "$r" | sed "s#$work/bproj#$here#")"
  check "build tables: the program is there and runs" "1" "$("$P/out/app" 2>&1)"
  rm -rf "$P/out"
  r="$(cd "$work" && noconf $t build "$P/sub/prog.tom" -o "$work/other_app" 2>&1)"
  check "build tables: -o wins over output" "wrote $work/other_app" "$r"
  [ ! -e "$P/out" ] && ok "build tables: -o leaves the output folder alone" || bad "build tables: -o leaves the output folder alone"
  r="$(noconf $t run "$P/sub/prog.tom" 2>&1)"
  check "build tables: run ignores output" "1" "$r"
  # a seed's [build] is read and ignored; a bad one is still an error
  printf '[seed]\nname = "acme.example/demo"\nversion = "1.0.0"\ntomato = "0.51"\n[build]\nmode = "release"\n' > "$P/tomato.toml"
  check "build tables: [build] of a seed is ignored" "debug" "$(mode_of noconf $t run "$P/sub/prog.tom" crash)"
  check "build tables: tomato config says so" "build: ignored, the [build] of a seed is not read" "$(noconf $t config "$P/sub/prog.tom" | tail -n 1)"
  printf '[limits]\n[build]\nmode = "release"\n' > "$P/tomato.toml"
  check "build tables: a settings-only file applies [build]" "release" "$(mode_of noconf $t run "$P/sub/prog.tom" crash)"
  check "build tables: tomato config shows the top [build] table" "build.mode = release  ($here/tomato.toml)" "$(noconf $t config "$P/sub/prog.tom" | tail -n 1)"
  check "build tables: tomato compile prints no settings comment" "0" "$(noconf $t compile "$P/sub/prog.tom" | grep -c '^;%')"
  # build and test honor the mode (D92c item 3), the flags win, the dotted-prefix rule holds, a seed's folder ignores [build]
  printf '@main\ndef main():\n    print(1)\n\n@oth.x\ndef x():\n    raise ValueError("boom")\n\n@grp.one\ndef one():\n    raise ValueError("boom")\n\n@grp.two\ndef two():\n    raise ValueError("boom")\n\n@test.t\ndef t():\n    assert 1 + 1 == 2\n' > "$P/sub/dot.tom"
  printf '%s[build]\nmode = "release"\n' "$head" > "$P/tomato.toml"
  noconf $t build "$P/sub/dot.tom" -o "$work/b_rel" > /dev/null 2>&1
  check "build tables: build uses [build] mode (the built program prints a short code)" "release" "$(mode_of "$work/b_rel" grp.one)"
  noconf $t build "$P/sub/dot.tom" -o "$work/b_dbg" --mode debug > /dev/null 2>&1
  check "build tables: build --mode debug wins over [build] mode release" "debug" "$(mode_of "$work/b_dbg" grp.one)"
  printf '%s[build]\nmode = "release"\n[build.grp]\nmode = "debug"\n' "$head" > "$P/tomato.toml"
  check "build tables: [build.grp] applies to grp.one (the dotted-prefix rule)" "debug" "$(mode_of noconf $t run "$P/sub/dot.tom" grp.one)"
  printf '%s[build]\nmode = "debug"\n[build.grp.one]\nmode = "release"\n' "$head" > "$P/tomato.toml"
  check "build tables: [build.grp.one] applies to grp.one and not to grp (a table below the entry is not used)" "release debug" "$(mode_of noconf $t run "$P/sub/dot.tom" grp.one) $(mode_of noconf $t run "$P/sub/dot.tom" grp)"
  check "build tables: a table for the prefix text (grp.o) does not apply" "debug" "$(printf '%s[build]\nmode = "debug"\n[build.grp.o]\nmode = "release"\n' "$head" > "$P/tomato.toml"; mode_of noconf $t run "$P/sub/dot.tom" grp.one)"
  printf '%s[build]\nmode = "debug"\n[build.grp.one]\nmode = "release"\n' "$head" > "$P/tomato.toml"
  noconf $t build "$P/sub/dot.tom" --entry grp.one -o "$work/b_ent" > /dev/null 2>&1
  check "build tables: build --entry reads [build.ENTRY]" "release" "$(mode_of "$work/b_ent")"
  printf '%s[build]\nmode = "release"\n[build.test]\nmode = "debug"\n[build.test.t]\noutput = "should/not/matter"\n' "$head" > "$P/tomato.toml"
  r="$(noconf $t test "$P/sub/dot.tom" 2>&1)"; case "$r" in *"(1 passed)"*": ok") ok "build tables: tomato test runs with [build.test] and ignores output";; *) bad "build tables: tomato test runs with [build.test] and ignores output" "$r";; esac
  [ ! -e "$P/should" ] && ok "build tables: tomato test makes no output folder" || bad "build tables: tomato test makes no output folder"
  # a seed's own folder: its [build] mode and output are ignored by run, build and test
  printf '[seed]\nname = "acme.example/demo"\nversion = "1.0.0"\ntomato = "0.51"\n[build]\nmode = "release"\noutput = "seedout/app"\n[build.test]\nmode = "release"\n' > "$P/tomato.toml"
  r="$(cd "$P" && noconf $t build sub/dot.tom -o sb 2>&1)"; check "build tables: build in a seed's folder ignores its [build] output" "wrote sb" "$r"
  check "build tables: ... and its mode" "debug" "$(mode_of "$P/sb" grp.one)"
  [ ! -e "$P/seedout" ] && ok "build tables: no seed output folder" || bad "build tables: no seed output folder"
  check "build tables: tomato test in a seed's folder ignores [build.test]" "debug" "$(noconf $t test "$P/sub/dot.tom" >/dev/null 2>&1; mode_of noconf $t run "$P/sub/dot.tom" grp.one)"
  # the user's config.toml: [build] mode is the default under the project's [build] and the flags; nothing else of [build] is allowed there
  printf '[build]\nmode = "release"\n' > "$work/uh/config.toml"
  rm -f "$P/tomato.toml"
  check "build tables: the user's [build] mode applies with no project file" "release" "$(mode_of noconf $t run "$P/sub/dot.tom" grp.one)"
  check "build tables: --mode wins over the user's [build] mode" "debug" "$(mode_of noconf $t run --mode debug "$P/sub/dot.tom" grp.one)"
  printf '%s' "$head" > "$P/tomato.toml"
  check "build tables: a project without [build] still gets the user's mode" "release" "$(mode_of noconf $t run "$P/sub/dot.tom" grp.one)"
  printf '%s[build]\nmode = "debug"\n' "$head" > "$P/tomato.toml"
  check "build tables: the project's [build] mode wins over the user's" "debug" "$(mode_of noconf $t run "$P/sub/dot.tom" grp.one)"
  printf '%s[build.grp]\nmode = "debug"\n' "$head" > "$P/tomato.toml"
  check "build tables: the user's mode is the base of the project's entry tables" "debug release" "$(mode_of noconf $t run "$P/sub/dot.tom" grp.one) $(mode_of noconf $t run "$P/sub/dot.tom" oth.x)"
  check "build tables: tomato config shows the user's mode" "1" "$(noconf $t config "$P/sub/dot.tom" | grep -c "^build.mode = release  ($work/uh/config.toml")"
  noconf $t build "$P/sub/dot.tom" -o "$work/b_user" > /dev/null 2>&1
  check "build tables: build uses the user's mode too" "release" "$(mode_of "$work/b_user" grp.one)"
  printf '[build]\noutput = "x"\n' > "$work/uh/config.toml"
  case "$(noconf $t run "$P/sub/dot.tom" 2>&1)" in "error[E558]: $work/uh/config.toml: unknown setting build.output"*) ok "build tables: output is refused in the user's file";; *) bad "build tables: output is refused in the user's file" "$(noconf $t run "$P/sub/dot.tom" 2>&1)";; esac
  printf '[build]\nmode = "fast"\n' > "$work/uh/config.toml"
  check "build tables: a bad mode in the user's file is E565" "error[E565]: $work/uh/config.toml: build.mode must be \"debug\" or \"release\", not \"fast\"" "$(noconf $t run "$P/sub/dot.tom" 2>&1)"
  rm -f "$work/uh/config.toml"
  rm -f "$P/tomato.toml"
  check "build tables: with no manifest --mode alone decides" "release debug" "$(mode_of noconf $t run --mode release "$P/sub/prog.tom" crash) $(mode_of noconf $t run "$P/sub/prog.tom" crash)"
  check "build tables: a bad --mode is still refused first" "error[E282]: the mode must be debug or release, not 'fast'" "$(noconf $t run "$P/sub/prog.tom" --mode fast 2>&1)"
}
t_cli_seeds() { # local seeds (D95a): tomato seed install/check/hash, tomato.lock, the seed lookup between the program's folder and std/
  cli_setup
  W="$work/sd"; mkdir -p "$W/app/sub" "$W/thing/src" "$W/other/src" "$work/uh"
  noconf() { TOMATO_HOME="$work/uh" "$@"; }
  sum256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi; }
  # the seed hash v1 of section 6, computed with find, sort and the system's sha256 (independent of the Tomato code)
  indep_hash() { printf 'sha256:%s' "$(cd "$1" && find . -type f ! -path './.git/*' ! -path './builds/*' | sed 's#^\./##' | LC_ALL=C sort | while read -r f; do m=644; [ -x "$f" ] && m=755; printf '%s  %s  %s\n' "$(sum256 < "$f")" "$m" "$f"; done | sum256)"; }
  printf '[seed]\nname = "acme.example/thing"\nversion = "0.3.0"\ntomato = "0.51"\ndescription = "a thing"\nlicense = "MIT"\n' > "$W/thing/tomato.toml"
  printf 'export def greet(n: str) -> str:\n    return "hello " + n\n' > "$W/thing/src/thing.tom"
  printf 'from thing import greet\n\nexport def shout(n: str) -> str:\n    return greet(n).upper()\n' > "$W/thing/src/thing_extra.tom"
  printf '[seed]\nname = "acme.example/other"\nversion = "1.4.2"\ntomato = "0.51"\n' > "$W/other/tomato.toml"
  printf 'export def seven() -> int:\n    return 7\n' > "$W/other/src/other.tom"
  printf 'from thing import greet\nfrom thing_extra import shout\n\n@main\ndef main():\n    print(greet("tomato"))\n    print(shout("tomato"))\n' > "$W/app/sub/prog.tom"
  printf 'from other import seven\n\n@main\ndef main():\n    print(seven())\n\n@test\ndef sevens():\n    assert seven() == 7\n' > "$W/app/sub/needs_other.tom"
  head='[project]
name = "app"
version = "0.1.0"
tomato = "0.51"
[seeds]
"acme.example/thing" = { path = "../thing" }
'
  printf '%s' "$head" > "$W/app/tomato.toml"
  here="$(cd "$W" && pwd -P)"
  r="$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)"
  check "seeds: a build with no lock says to run tomato seed install" "error[E569]: $here/app/tomato.toml: this uses the seed acme.example/thing, but there is no tomato.lock beside it
  = help: run: tomato seed install" "$r"
  h="$(indep_hash "$W/thing")"
  r="$(cd "$W/app" && noconf $t seed install 2>&1)"
  check "seeds: install locks a path seed and says what it wrote" "acme.example/thing 0.3.0  $h  (path ../thing)
wrote $here/app/tomato.lock (1 seed)" "$r"
  check "seeds: the lock holds the name, version, source, path, content hash and modules" '# tomato.lock: generated by `tomato seed install`, do not edit
version = 1

[[seed]]
name = "acme.example/thing"
version = "0.3.0"
source = "path"
path = "../thing"
hash = "'"$h"'"
modules = ["thing", "thing_extra"]
seeds = []' "$(cat "$W/app/tomato.lock")"
  check "seeds: the content hash agrees with find, sort and sha256sum" "$h" "$(cd "$W/app" && noconf $t seed hash ../thing)"
  check "seeds: a program uses the seed's modules" "hello tomato
HELLO TOMATO" "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)"
  check "seeds: so does a release build" "hello tomato
HELLO TOMATO" "$(cd "$W/app" && noconf $t run sub/prog.tom --mode release 2>&1)"
  case "$(cd "$W/app" && noconf $t compile sub/prog.tom 2>&1)" in *"hello "*) ok "seeds: tomato compile finds them too";; *) bad "seeds: tomato compile finds them too";; esac
  check "seeds: install --locked passes when the lock is current" "acme.example/thing 0.3.0  $h  (path ../thing)
tomato.lock is up to date" "$(cd "$W/app" && noconf $t seed install --locked 2>&1)"
  # the same program compiles to the same IR twice (design section 15, stage 2)
  (cd "$W/app" && noconf $t compile sub/prog.tom > "$work/ir1.ll" 2>&1; noconf $t compile sub/prog.tom > "$work/ir2.ll" 2>&1)
  cmp -s "$work/ir1.ll" "$work/ir2.ll" && ok "seeds: a seeded program compiles to the same IR twice" || bad "seeds: a seeded program compiles to the same IR twice"
  # the project's own file shadows a seed's module (as it shadows std)
  printf 'export def greet(n: str) -> str:\n    return "mine " + n\n' > "$W/app/sub/thing.tom"
  check "seeds: a file next to the program shadows the seed's module" "mine tomato
MINE TOMATO" "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)"
  printf 'export def greet(n: str) -> str:\n    unused = 1\n    return "mine " + n\n' > "$W/app/sub/thing.tom"
  case "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)" in *"warning: the variable 'unused'"*" --> thing.tom:2:5"*) ok "seeds: a file that shadows a seed's module is the program's own code (its warnings show, with its own name)";; *) bad "seeds: a file that shadows a seed's module is the program's own code (its warnings show, with its own name)" "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)";; esac
  rm "$W/app/sub/thing.tom"
  printf 'export def extra() -> int:\n    return 1\n' > "$W/thing/src/thing_util.tom"; printf 'from thing_util import extra\n@main\ndef main():\n    print(extra())\n' > "$W/app/sub/util.tom"
  case "$(cd "$W/app" && noconf $t run sub/util.tom 2>&1)" in *"cannot find the module 'thing_util'"*"if a seed has a new module, run: tomato seed install"*) ok "seeds: a module added to a seed after the lock says to run install";; *) bad "seeds: a module added to a seed after the lock says to run install" "$(cd "$W/app" && noconf $t run sub/util.tom 2>&1)";; esac
  rm "$W/thing/src/thing_util.tom"
  # a path seed is a working folder: a change does not stop a build, but the lock is no longer current
  printf '\n' >> "$W/thing/src/thing.tom"
  check "seeds: a changed seed still builds (path seeds are for development)" "hello tomato
HELLO TOMATO" "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)"
  r="$(cd "$W/app" && noconf $t seed install --locked 2>&1; echo "rc=$?")"
  check "seeds: install --locked fails when the seed's content changed" "error[E578]: $here/app/tomato.toml: tomato.lock does not match this manifest: run \`tomato seed install\` and commit the new lock
rc=1" "$r"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  check "seeds: install again records the new hash" "$(indep_hash "$W/thing")" "$(sed -n 's/^hash = "\(.*\)"/\1/p' "$W/app/tomato.lock")"
  # [test-seeds] (D94b): a seed only a test needs is locked with test_only, and compiled only for tests
  printf '%s[test-seeds]\n"acme.example/other" = { path = "../other" }\n' "$head" > "$W/app/tomato.toml"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  check "seeds: a seed of [test-seeds] is in the lock with test_only" 'name = "acme.example/other"
version = "1.4.2"
source = "path"
path = "../other"
hash = "'"$(indep_hash "$W/other")"'"
modules = ["other"]
seeds = []
test_only = true' "$(sed -n '/name = "acme.example\/other"/,/^test_only/p' "$W/app/tomato.lock")"
  check "seeds: the seed of [test-seeds] is not in a plain build" "1" "$(cd "$W/app" && noconf $t run sub/needs_other.tom 2>&1 | grep -c "cannot find the module 'other'")"
  check "seeds: the option --test-seeds finds it" "7" "$(cd "$W/app" && noconf $t run --test-seeds sub/needs_other.tom 2>&1)"
  check "seeds: so does build --test-seeds" "7" "$(cd "$W/app" && noconf $t build sub/needs_other.tom --test-seeds -o "$work/no_bin" >/dev/null 2>&1 && "$work/no_bin" 2>&1)"
  r="$(cd "$W/app" && noconf $t test sub/needs_other.tom 2>&1)"
  case "$r" in *"ok   sub/needs_other.tom  (1 passed)"*"tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok") ok "seeds: tomato test reads [test-seeds], so its seeds are found";; *) bad "seeds: tomato test reads [test-seeds], so its seeds are found" "$r";; esac
  printf '%s' "$head" > "$W/app/tomato.toml"
  # the lock must hold what the run uses
  r="$(cd "$W/app" && printf '# tomato.lock\nversion = 1\n' > tomato.lock && noconf $t run sub/prog.tom 2>&1)"
  check "seeds: a seed missing from the lock says to install" "error[E569]: $here/app/tomato.toml: the seed acme.example/thing is in tomato.toml but not in tomato.lock
  = help: run: tomato seed install" "$r"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  printf 'x = [\n' > "$W/app/tomato.lock"
  case "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)" in "error[E540]: the configuration file $here/app/tomato.lock is not valid TOML: "*) ok "seeds: a lock that is not TOML is an error naming the file";; *) bad "seeds: a lock that is not TOML is an error naming the file";; esac
  printf 'version = 3\n' > "$W/app/tomato.lock"
  check "seeds: a lock of another version is refused" "error[E578]: $here/app/tomato.lock: this lock is not version 1 or 2 (a newer Tomato wrote it?): run \`tomato seed install\` to write it again" "$(cd "$W/app" && noconf $t run sub/prog.tom 2>&1)"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  # errors name the seed, warnings from a seed are not shown
  printf 'export def bad() -> int:\n    return "x"\n' > "$W/thing/src/thing_bad.tom"
  printf 'export def w():\n    unused = 1\n    return\n' > "$W/thing/src/thing_warn.tom"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  printf 'from thing_bad import bad\n@main\ndef main():\n    print(bad())\n' > "$W/app/sub/bad.tom"
  printf 'from thing_warn import w\n@main\ndef main():\n    w()\n    print("done")\n' > "$W/app/sub/warn.tom"
  check "seeds: an error in a seed names the seed, its version and the file" "error[E324]: the returned value has type str, but int is expected
 --> acme.example/thing 0.3.0: src/thing_bad.tom:2:5
  |
2 |     return \"x\"
  |     ^^^^^^^^^^" "$(cd "$W/app" && noconf $t run sub/bad.tom 2>&1)"
  check "seeds: a warning in a seed is not shown" "done" "$(cd "$W/app" && noconf $t run sub/warn.tom 2>&1)"
  rm "$W/thing/src/thing_bad.tom" "$W/thing/src/thing_warn.tom"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  # a module that is also in std: the compiler says so instead of choosing
  mkdir -p "$W/mathseed/src"
  printf '[seed]\nname = "acme.example/math"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/mathseed/tomato.toml"
  printf 'export def f() -> int:\n    return 1\n' > "$W/mathseed/src/math.tom"
  printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "0.51"\n[seeds]\n"acme.example/math" = { path = "../mathseed" }\n' > "$W/app/tomato.toml"
  case "$(cd "$W/app" && noconf $t seed install 2>&1)" in "error[E579]: $here/mathseed/tomato.toml: the module 'math' has the name of a standard module, so imports of it would change meaning") ok "seeds: install refuses a module with a standard module's name";; *) bad "seeds: install refuses a module with a standard module's name" "$(cd "$W/app" && noconf $t seed install 2>&1)";; esac
  printf 'version = 1\n\n[[seed]]\nname = "acme.example/math"\nversion = "1.0.0"\nsource = "path"\npath = "../mathseed"\nhash = "sha256:0"\nmodules = ["math"]\n' > "$W/app/tomato.lock"
  printf 'import math\n@main\ndef main():\n    print(math.pi)\n' > "$W/app/sub/usemath.tom"
  check "seeds: a seed module that is also a standard module is an error naming both" "error[E581]: the module 'math' is in the seed acme.example/math 1.0.0 and in the standard library, so the import is ambiguous
 --> sub/usemath.tom:1:8
  |
1 | import math
  |        ^^^^
  = help: the standard library gained a module of the seed's name: ask the seed's author to rename it, or put your own math.tom next to the program" "$(cd "$W/app" && noconf $t run sub/usemath.tom 2>&1)" 
  printf '%s' "$head" > "$W/app/tomato.toml"; rm -f "$W/app/tomato.lock"
  (cd "$W/app" && noconf $t seed install >/dev/null 2>&1)
  # two seeds with one module
  mkdir -p "$W/twin/src"
  printf '[seed]\nname = "twin.example/thing"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/twin/tomato.toml"
  printf 'export def greet(n: str) -> str:\n    return "twin"\n' > "$W/twin/src/thing.tom"
  printf '%s"twin.example/thing" = { path = "../twin" }\n' "$head" > "$W/app/tomato.toml"
  check "seeds: two seeds that provide one module cannot be installed together" "error[E577]: $here/app/tomato.toml: the seeds acme.example/thing and twin.example/thing both provide the module 'thing': one program holds one copy of a module" "$(cd "$W/app" && noconf $t seed install 2>&1)"
  printf '%s' "$head" > "$W/app/tomato.toml"
  # what install cannot do yet
  badseed() { printf '%s%s\n' "$head" "$2" > "$W/app/tomato.toml"; check "seeds: $1" "$3" "$(cd "$W/app" && noconf $t seed install 2>&1 | sed "s#$here#HERE#g")"; }
  badseed "a git seed whose rev is not a full commit id is refused before git is started" '"d.example/g" = { git = "https://h/g.git", rev = "abc" }' "error[E598]: HERE/app/tomato.toml: the rev \"abc\" of the seed d.example/g is not a full commit id (40 lowercase hex digits): a tag or a branch moves, so the manifest names the commit (git rev-parse TAG^{commit} prints it)"
  badseed "a git seed with a URL of another scheme is refused" '"d.example/g" = { git = "http://h/g.git", rev = "0123456789012345678901234567890123456789" }' "error[E598]: HERE/app/tomato.toml: the git URL of the seed d.example/g cannot be used: the scheme http:// is not used for seeds (the schemes are https, ssh and file)"
  badseed "a registry seed is reported as not supported yet" '"d.example/r" = "1.2.0"' "error[E571]: HERE/app/tomato.toml: the seed d.example/r 1.2.0 would come from a registry, and there is none yet; only { path = \"../folder\" } and { git = \"URL\", rev = \"COMMIT\" } seeds can be installed"
  badseed "a path that is not a folder" '"d.example/nope" = { path = "../nope" }' "error[E572]: HERE/app/tomato.toml: the seed d.example/nope is at \"../nope\", which is not a folder (a relative path starts at the folder of tomato.toml)"
  mkdir -p "$W/bare"
  badseed "a folder with no tomato.toml" '"d.example/bare" = { path = "../bare" }' "error[E572]: HERE/app/tomato.toml: the seed d.example/bare at \"../bare\" has no tomato.toml: the folder of a seed needs one with a [seed] table"
  badseed "a seed listed under another name than its own" '"acme.example/alias" = { path = "../thing" }' "error[E573]: HERE/app/tomato.toml: \"acme.example/alias\" is listed with the path \"../thing\", but the seed there is called \"acme.example/thing\""
  printf '[project]\nname = "x"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/bare/tomato.toml"
  badseed "a folder that is a project, not a seed" '"d.example/bare" = { path = "../bare" }' "error[E572]: HERE/bare/tomato.toml: the folder is listed as the seed d.example/bare, but its tomato.toml has no [seed] table"
  # the seed's own rules
  mkdir -p "$W/hasdeps/src"
  printf '[seed]\nname = "d.example/hasdeps"\nversion = "1.0.0"\ntomato = "0.51"\n[seeds]\n"a.example/y" = "1.0.0"\n' > "$W/hasdeps/tomato.toml"
  printf 'export def f() -> int:\n    return 1\n' > "$W/hasdeps/src/hasdeps.tom"
  badseed "a seed that uses seeds cannot be installed yet" '"d.example/hasdeps" = { path = "../hasdeps" }' "error[E574]: HERE/app/tomato.toml: the seed d.example/hasdeps itself uses the seed a.example/y, and seeds that use seeds cannot be installed yet: there is no registry"
  mkdir -p "$W/badname/src"
  printf '[seed]\nname = "d.example/badname"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/badname/tomato.toml"
  printf 'export def f() -> int:\n    return 1\n' > "$W/badname/src/helpers.tom"
  badseed "a module that does not fit the seed's name" '"d.example/badname" = { path = "../badname" }' "error[E575]: HERE/badname/tomato.toml: the module 'helpers' does not fit the seed name d.example/badname: a seed may contain only badname.tom and badname_*.tom"
  rm "$W/badname/src/helpers.tom"
  badseed "a seed with no modules" '"d.example/badname" = { path = "../badname" }' "error[E575]: HERE/badname/tomato.toml: the seed has no modules: put badname.tom in HERE/badname/src"
  printf 'export def f() -> int:\n    return 1\n' > "$W/badname/src/badname.tom"; ln -s src/badname.tom "$W/badname/link.tom"
  badseed "a symbolic link in a seed" '"d.example/badname" = { path = "../badname" }' "error[E576]: HERE/badname: link.tom is a symbolic link, which a seed cannot contain (it could point outside the seed)"
  rm "$W/badname/link.tom"
  printf '[seed]\nname = "d.example/badname"\nversion = "1.0.0"\ntomato = "9.0"\n' > "$W/badname/tomato.toml"
  badseed "a seed that needs a newer Tomato" '"d.example/badname" = { path = "../badname" }' "error[E562]: HERE/badname/tomato.toml: this needs Tomato 9.0 or newer, and this is Tomato $(cat VERSION)
  = help: install a newer release with \`tomato update\`"
  # one seed in two tables
  printf '%s[test-seeds]\n"acme.example/thing" = { path = "../other" }\n' "$head" > "$W/app/tomato.toml"
  case "$(cd "$W/app" && noconf $t seed install 2>&1)" in "error[E564]: "*"the seed acme.example/thing has the path \"../thing\" in [seeds] and \"../other\" in [test-seeds]") ok "seeds: one seed with two paths is an error";; *) bad "seeds: one seed with two paths is an error";; esac
  # no seeds at all
  printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "0.51"\n' > "$W/app/tomato.toml"; rm -f "$W/app/tomato.lock"
  check "seeds: a manifest with no seeds locks nothing" "the manifest lists no seeds: nothing to lock" "$(cd "$W/app" && noconf $t seed install 2>&1)"
  [ ! -e "$W/app/tomato.lock" ] && ok "seeds: and writes no lock" || bad "seeds: and writes no lock"
  rm -f "$W/app/tomato.toml"
  check "seeds: install needs a tomato.toml" "error: there is no tomato.toml in this folder or a parent folder" "$(cd "$W/app" && noconf $t seed install 2>&1)"
  # tomato seed check and hash
  check "seeds: check of a good seed prints its modules and hash" "acme.example/thing 0.3.0: ok
modules: thing, thing_extra
$(indep_hash "$W/thing")" "$(cd "$W/thing" && noconf $t seed check 2>&1)"
  check "seeds: check of a seed without a description or license says so" "acme.example/other 1.4.2: ok
modules: other
note: seed.description is not set
note: seed.license is not set
$(indep_hash "$W/other")" "$(cd "$W/other" && noconf $t seed check 2>&1)"
  # a [build.ENTRY] that names no entry is a warning (D92c): a marker in src/ or tests/ equal to it or below it counts
  cp -r "$W/other" "$W/warn"; mkdir -p "$W/warn/tests"
  printf '\n@greet.loud\ndef loud():\n    pass\n' >> "$W/warn/src/other.tom"; printf '@test.a\ndef a():\n    pass\n' > "$W/warn/tests/t.tom"
  printf '[seed]\nname = "acme.example/other"\nversion = "1.4.2"\ntomato = "0.51"\n[build.greet]\nmode = "debug"\n[build.test.a]\nmode = "debug"\n[build.mian]\nmode = "debug"\n[build.greet.quiet]\nmode = "debug"\n' > "$W/warn/tomato.toml"
  check "seeds: check warns about a [build.ENTRY] that names no entry" "warning: [build.greet.quiet] names no entry: no function in src/ or tests/ is marked @greet.quiet (or @greet.quiet.something), so the table is never used (a typo?)
warning: [build.mian] names no entry: no function in src/ or tests/ is marked @mian (or @mian.something), so the table is never used (a typo?)" "$(cd "$W/warn" && noconf $t seed check 2>&1 | grep '^warning:')"
  printf '[seed]\nname = "local/x"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/bare/tomato.toml"; mkdir -p "$W/bare/src"; printf 'export def f() -> int:\n    return 1\n' > "$W/bare/src/x.tom"
  case "$(cd "$W/bare" && noconf $t seed check 2>&1 | sed "s#$here#HERE#")" in 'error[E580]: HERE/bare/tomato.toml: the owner "local" is not one a registry accepts: '*) ok "seeds: check wants a domain or key owner";; *) bad "seeds: check wants a domain or key owner" "$(cd "$W/bare" && noconf $t seed check 2>&1)";; esac
  printf '[project]\nname = "x"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/bare/tomato.toml"
  check "seeds: check of a project is refused" "error[E572]: $here/bare/tomato.toml: this is not a seed: it has no [seed] table (a [project] is a program that uses seeds)" "$(cd "$W/bare" && noconf $t seed check 2>&1)"
  # hash: modes, nested folders, .git left out, content order
  mkdir -p "$W/h/a/b" "$W/h/.git"; printf 'one' > "$W/h/z.txt"; printf 'two' > "$W/h/a/b/y"; printf 'x' > "$W/h/.git/config"; printf '#!/bin/sh\n' > "$W/h/run.sh"; chmod 755 "$W/h/run.sh"
  mkdir -p "$W/h2"; printf 'one' > "$W/h2/z.txt"; chmod 644 "$W/h2/z.txt"
  check "seeds: a group or other execute bit alone is mode 644, as git records it" "$(cd "$W/h2" && noconf $t seed hash .)" "$(mkdir -p "$W/h3" && printf 'one' > "$W/h3/z.txt" && chmod 654 "$W/h3/z.txt" && cd "$W/h3" && noconf $t seed hash .)"
  check "seeds: the hash covers nested files, modes, byte order and leaves .git out" "$(indep_hash "$W/h")" "$(noconf $t seed hash "$W/h")"
  case "$(noconf $t seed hash 2>&1)" in "sha256:"*) ok "seeds: hash of no argument is the current folder's";; *) bad "seeds: hash of no argument is the current folder's";; esac
  check "seeds: hash of a missing folder" "error[E572]: $W/nope is not a folder" "$(noconf $t seed hash "$W/nope" 2>&1)"
  check "seeds: an unknown seed command" "error: unknown seed command 'frob' (run 'tomato help'; the commands here are install, add, remove, update, verify, vendor, check and hash)" "$(noconf $t seed frob 2>&1)"
}
t_cli_seed_store() { # tomato seed add/remove/vendor, git seeds and the seed store, the foreign-symbol question (D100a); local bare git repos only, no network
  cli_setup
  if ! command -v git >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "seed store: git is required in CI" || echo "skip: git is not installed, so the seed store tests did not run"
    return
  fi
  W="$work/ss"; mkdir -p "$W"; cd "$W" || return 1
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.t
  th="$W/home"; mkdir -p "$th"; here="$(pwd -P)"
  tm() { TOMATO_HOME="$th" "$@"; }
  sum256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi; }
  # the seed hash v1 of section 6 with find, sort and the system's sha256 (independent of the Tomato code), as in t_cli_seeds
  indep_hash() { printf 'sha256:%s' "$(cd "$1" && find . -type f ! -path './.git/*' ! -path './builds/*' | sed 's#^\./##' | LC_ALL=C sort | while read -r f; do m=644; [ -x "$f" ] && m=755; printf '%s  %s  %s\n' "$(sum256 < "$f")" "$m" "$f"; done | sum256)"; }
  norm() { sed "s#$here#HERE#g"; }
  commit() { git -C "$1" add -A >/dev/null && git -C "$1" commit -q -m "$2" && git -C "$1" rev-parse HEAD; }   # DIR MESSAGE: prints the commit id
  bare() { rm -rf "$2"; git clone -q --bare "$1" "$2"; }                                                       # REPO BARE
  seed_toml() { printf '[seed]\nname = "%s"\nversion = "%s"\ntomato = "0.51"\n' "$1" "$2"; }                  # NAME VERSION
  # ---- the seeds: a path seed, and a git seed in two commits (the second declares a foreign symbol)
  mkdir -p "$W/loc/src"
  seed_toml acme.example/loc 0.3.0 > "$W/loc/tomato.toml"
  printf 'export def local_name() -> str:\n    return "loc"\n' > "$W/loc/src/loc.tom"
  git init -q -b main "$W/gs"; mkdir -p "$W/gs/src"
  seed_toml g.example/gs 1.0.0 > "$W/gs/tomato.toml"
  printf 'export def hi() -> str:\n    return "hi from git"\n' > "$W/gs/src/gs.tom"
  printf '#!/bin/sh\necho tool\n' > "$W/gs/tool.sh"; chmod 755 "$W/gs/tool.sh"
  C1="$(commit "$W/gs" one)"
  H1="$(indep_hash "$W/gs")"
  seed_toml g.example/gs 1.1.0 > "$W/gs/tomato.toml"
  printf '!tomato_json_quote(text: str, ascii: int) -> str\nexport def hi() -> str:\n    return "hi from git 1.1"\n' > "$W/gs/src/gs.tom"
  C2="$(commit "$W/gs" two)"
  H2="$(indep_hash "$W/gs")"
  bare "$W/gs" "$W/gs.git"
  mkdir -p "$W/app/src"; A="$W/app"
  head='[project]
name = "app"
version = "0.1.0"
tomato = "0.51"
'
  printf 'from loc import local_name\n\n@main\ndef main():\n    print(local_name())\n' > "$A/src/main.tom"
  printf 'from gs import hi\n\n@main\ndef main():\n    print(hi())\n' > "$A/src/usegs.tom"
  gsurl="$W/gs.git"
  # ---- seed add --path: the manifest keeps its comments and order, the new line goes where it belongs
  printf '# my app\n%s\n# what it uses\n[seeds]\n# the first\n"b.example/b" = "1.0.0"   # kept\n\n[build]\nmode = "release"\n' "$head" > "$A/tomato.toml"
  cp "$A/tomato.toml" "$W/manifest.before"
r="$(cd "$A" && tm $t run src/usegs.tom 2>&1 | norm)"
  cmp -s "$W/manifest.before" "$A/tomato.toml" && ok "seed add: a failed add leaves tomato.toml exactly as it was" || bad "seed add: a failed add leaves tomato.toml exactly as it was" "$(diff "$W/manifest.before" "$A/tomato.toml")"
  printf '# my app\n%s\n# what it uses\n[seeds]\n# the first\n"b.example/b" = { path = "../loc" }   # kept\n\n[build]\nmode = "release"\n' "$head" > "$A/tomato.toml"
  printf '[seed]\nname = "b.example/b"\nversion = "1.0.0"\ntomato = "0.51"\n' > "$W/loc/tomato.toml"; mkdir -p "$W/b/src"; mv "$W/loc/tomato.toml" "$W/b/tomato.toml"; printf 'export def b() -> int:\n    return 1\n' > "$W/b/src/b.tom"
  printf '# my app\n%s\n# what it uses\n[seeds]\n# the first\n"b.example/b" = { path = "../b" }   # kept\n\n[build]\nmode = "release"\n' "$head" > "$A/tomato.toml"
  seed_toml acme.example/loc 0.3.0 > "$W/loc/tomato.toml"
  cp "$A/tomato.toml" "$W/manifest.before"
  r="$(cd "$A" && tm $t seed add --path ../loc 2>&1 | norm)"
  check "seed add: a path seed is listed and locked" "added acme.example/loc 0.3.0 to [seeds] of HERE/app/tomato.toml
b.example/b 1.0.0  $(indep_hash "$W/b")  (path ../b)
acme.example/loc 0.3.0  $(indep_hash "$W/loc")  (path ../loc)
wrote HERE/app/tomato.lock (2 seeds)" "$r"
  check "seed add: only the new line is added, after the last seed of [seeds], with every comment and blank line where it was" '+"acme.example/loc" = { path = "../loc" }' "$(diff "$W/manifest.before" "$A/tomato.toml" | grep '^[<>]' | sed 's/^> */+/')"
  check "seed add: the lock holds the seeds, with the content hash of find, sort and sha256" "$(indep_hash "$W/loc")" "$(sed -n '/name = "acme.example\/loc"/,/^seeds/p' "$A/tomato.lock" | sed -n 's/^hash = "\(.*\)"/\1/p')"
  check "seed add: a program uses the seed" "loc" "$(cd "$A" && tm $t run 2>&1)"
  cp "$A/tomato.toml" "$W/manifest.once"; cp "$A/tomato.lock" "$W/lock.once"
  r="$(cd "$A" && tm $t seed add --path "$W/loc" 2>&1 | norm | sed -n 1p)"
  check "seed add: the same seed again (as an absolute path) replaces its line" 'added acme.example/loc 0.3.0 to [seeds] of HERE/app/tomato.toml' "$r"
  check "seed add: and keeps the order (one line differs, the path as written)" "+\"acme.example/loc\" = { path = \"$W/loc\" }" "$(diff "$W/manifest.once" "$A/tomato.toml" | grep '^>' | sed 's/^> */+/')"
  (cd "$A" && tm $t seed add --path ../loc >/dev/null 2>&1)
  cmp -s "$W/manifest.once" "$A/tomato.toml" && cmp -s "$W/lock.once" "$A/tomato.lock" && ok "seed add: add, add again and add the first form again end where it began" || bad "seed add: add again ends where it began"
  # --test: [test-seeds], created after [seeds]
  mkdir -p "$W/tl/src"; seed_toml acme.example/tl 1.0.0 > "$W/tl/tomato.toml"; printf 'export def t() -> int:\n    return 1\n' > "$W/tl/src/tl.tom"
  (cd "$A" && tm $t seed add --path ../tl --test >/dev/null 2>&1)
  check "seed add: --test writes [test-seeds], right after [seeds]" '"acme.example/loc" = { path = "../loc" }   # kept

[test-seeds]
"acme.example/tl" = { path = "../tl" }

[build]' "$(sed -n '/^"acme.example\/loc"/,/^\[build\]/p' "$A/tomato.toml" | sed 's/^"acme.example\/loc" = { path = "..\/loc" }$/&   # kept/' | sed '1s/   # kept   # kept/   # kept/')"
  check "seed add: the lock marks it test_only" "test_only = true" "$(sed -n '/acme.example\/tl/,$p' "$A/tomato.lock" | grep test_only)"
  # ---- seed remove
  r="$(cd "$A" && tm $t seed remove acme.example/tl 2>&1 | norm)"
  check "seed remove: says what it removed and locked" "removed acme.example/tl from [test-seeds] of HERE/app/tomato.toml
b.example/b 1.0.0  $(indep_hash "$W/b")  (path ../b)
acme.example/loc 0.3.0  $(indep_hash "$W/loc")  (path ../loc)
wrote HERE/app/tomato.lock (2 seeds)" "$r"
  check "seed remove: only its line goes (the now empty [test-seeds] and the comments stay)" '+[test-seeds]
+' "$(diff "$W/manifest.once" "$A/tomato.toml" | grep '^[<>]' | sed 's/^> */+/')"
  check "seed remove: the lock no longer has it" "0" "$(grep -c 'acme.example/tl' "$A/tomato.lock")"
  r="$(cd "$A" && tm $t seed remove acme.example/nothing 2>&1 | norm; echo "rc=$?")"
  check "seed remove: a seed that is not listed is an error" "error[E604]: HERE/app/tomato.toml: acme.example/nothing is not in [seeds] or [test-seeds] of this tomato.toml
rc=0" "$r"
  r="$(cd "$A" && tm $t seed remove acme.example/loc >/dev/null 2>&1; tm $t seed remove b.example/b 2>&1 | norm)"
  check "seed remove: the last seed leaves a lock with no seeds" "removed b.example/b from [seeds] of HERE/app/tomato.toml
wrote HERE/app/tomato.lock (0 seeds)" "$r"
  check "seed remove: a lock with no seeds is only the version" '# tomato.lock: generated by `tomato seed install`, do not edit
version = 1' "$(cat "$A/tomato.lock")"
  # ---- forms that are not edited, and what is not a project
  printf '%s[seeds]\n"acme.example/loc".path = "../loc"\n' "$head" > "$A/tomato.toml"; cp "$A/tomato.toml" "$W/manifest.before"
  r="$(cd "$A" && tm $t seed remove acme.example/loc 2>&1 | norm | cut -c1-210)"
  check "seed remove: a dotted key is not edited, the manifest stays" 'error[E603]: HERE/app/tomato.toml: tomato.toml has a form this command does not edit (a dotted key, a multi-line value): nothing was changed. Remove the line of "acme.example/loc" yourself' "$r"
  r="$(cd "$A" && tm $t seed add --path ../loc 2>&1 | norm)"
  case "$r" in "error[E603]: HERE/app/tomato.toml: the edit would leave tomato.toml unreadable ("*"); it was put back as it was. Add this line to [seeds] yourself: \"acme.example/loc\" = { path = \"../loc\" }") ok "seed add: a dotted key is not edited either (a second line would be a duplicate): the manifest is put back";; *) bad "seed add: a dotted key is not edited either" "$r";; esac
  cmp -s "$W/manifest.before" "$A/tomato.toml" && ok "seed add: and it is exactly as it was" || bad "seed add: and it is exactly as it was"
  r="$(cd "$W/loc" && tm $t seed add --path ../tl 2>&1 | norm)"
  check "seed add: a seed's manifest is refused (only a project lists seeds that are not registered)" "error[E604]: HERE/loc/tomato.toml: seeds are added to a [project], and this file is a seed (a package can use only registered seeds, and there is no registry yet)" "$r"
  r="$(cd "$A" && printf '%s' "$head" > tomato.toml && tm $t seed add --path ../nothing 2>&1 | norm)"
  check "seed add: a folder that does not exist" "error[E572]: HERE/app/tomato.toml: ../nothing is not a folder" "$r"
  mkdir -p "$W/empty"
  check "seed add: a folder with no tomato.toml" "error[E572]: HERE/app/tomato.toml: ../empty has no tomato.toml: the folder of a seed needs one with a [seed] table" "$(cd "$A" && tm $t seed add --path ../empty 2>&1 | norm)"
  # a failed lock puts the manifest back: two seeds with one module
  mkdir -p "$W/twin/src"; seed_toml twin.example/loc 1.0.0 > "$W/twin/tomato.toml"; printf 'export def x() -> int:\n    return 2\n' > "$W/twin/src/loc.tom"
  (cd "$A" && printf '%s' "$head" > tomato.toml && tm $t seed add --path ../loc >/dev/null 2>&1); cp "$A/tomato.toml" "$W/manifest.before"; cp "$A/tomato.lock" "$W/lock.before"
  r="$(cd "$A" && tm $t seed add --path ../twin 2>&1 | norm)"
  check "seed add: two seeds with one module stop the add" "error[E577]: HERE/app/tomato.toml: the seeds acme.example/loc and twin.example/loc both provide the module 'loc': one program holds one copy of a module" "$r"
  cmp -s "$W/manifest.before" "$A/tomato.toml" && cmp -s "$W/lock.before" "$A/tomato.lock" && ok "seed add: the manifest and the lock are as they were" || bad "seed add: the manifest and the lock are as they were"
  # ---- seed add --git: fetched with git into the store, named by the content hash
  printf '%s' "$head" > "$A/tomato.toml"; rm -f "$A/tomato.lock"
  r="$(cd "$A" && tm $t seed add --git "$gsurl" --rev "$C1" 2>&1 | norm)"
  check "seed add --git: the seed is fetched, listed and locked" "added g.example/gs 1.0.0 to [seeds] of HERE/app/tomato.toml
g.example/gs 1.0.0  $H1  (git HERE/gs.git ${C1%????????????????????????????})
wrote HERE/app/tomato.lock (1 seed)" "$r"
  check "seed add --git: the line has the URL and the commit" "\"g.example/gs\" = { git = \"$gsurl\", rev = \"$C1\" }" "$(sed -n '/^\[seeds\]/,$p' "$A/tomato.toml" | sed -n 2p)"
  check "seed add --git: the lock has source, git, commit and the hash that find, sort and sha256 give for the files at that commit" "source = \"git\"
git = \"$gsurl\"
commit = \"$C1\"
hash = \"$H1\"
modules = [\"gs\"]" "$(sed -n '/^source/,/^modules/p' "$A/tomato.lock")"
  hx="${H1#sha256:}"; store="$th/seeds/store/$(echo "$hx" | cut -c1-2)/$hx"
  [ -f "$store/src/gs.tom" ] && [ -x "$store/tool.sh" ] && [ ! -x "$store/src/gs.tom" ] && ok "seed add --git: the files are in the store under their hash, with the modes git records" || bad "seed add --git: the files are in the store under their hash, with the modes git records" "$(ls -lR "$th/seeds" | head -20)"
  check "seed add --git: nothing is left in the scratch folder" "" "$(ls "$th/seeds/tmp")"
  check "seed add --git: the store folder hashes to the lock's hash" "$H1" "$(tm $t seed hash "$store")"
  check "seed add --git: a program uses the seed from the store" "hi from git" "$(cd "$A" && tm $t run src/usegs.tom 2>&1)"
  # offline: the repository can go away, the store has it
  mv "$W/gs.git" "$W/gs.moved"
  check "seed install --locked --offline: needs neither the repository nor git" "g.example/gs 1.0.0  $H1  (git HERE/gs.git ${C1%????????????????????????????})
tomato.lock is up to date" "$(cd "$A" && tm $t seed install --locked --offline 2>&1 | norm)"
  check "seed install: and so does install with the repository gone" "g.example/gs 1.0.0  $H1  (git HERE/gs.git ${C1%????????????????????????????})
wrote HERE/app/tomato.lock (1 seed)" "$(cd "$A" && tm $t seed install 2>&1 | norm)"
  check "a build never fetches: it runs from the store with the repository gone" "hi from git" "$(cd "$A" && tm $t run src/usegs.tom 2>&1)"
  mv "$store" "$W/store.moved"
  r="$(cd "$A" && tm $t seed install --offline 2>&1 | norm)"
  check "seed install --offline: a seed that is not in the store is an error, git is not run" "error[E605]: HERE/app/tomato.toml: the seed g.example/gs is not in the seed store ($(echo "$store" | norm)) or the vendor folder, and --offline does not run git: run \`tomato seed install\` once with the network" "$r"
  r="$(cd "$A" && tm $t run src/usegs.tom 2>&1 | norm)"
  check "a build says to install when the store has lost the seed" "error[E569]: HERE/app/tomato.toml: the seed g.example/gs is not in the seed store ($(echo "$store" | norm))
  = help: run: tomato seed install" "$r"
  r="$(cd "$A" && tm $t seed install 2>&1 | norm | cut -c1-60)"
  r="$(cd "$A" && tm $t seed install 2>&1 | norm | cut -c1-60)"
  case "$r" in "error[E599]: fetching "*" from HERE/gs.git failed: "*) ok "seed install: git failing (the repository is gone) is an error";; *) bad "seed install: git failing (the repository is gone) is an error" "$r";; esac
  [ ! -e "$store" ] && ok "seed install: the failed fetch stored nothing" || bad "seed install: the failed fetch stored nothing"
  check "seed install: and left no scratch folder" "" "$(ls "$th/seeds/tmp")"
  mv "$W/gs.moved" "$W/gs.git"
  check "seed install: with the repository back it fetches the missing seed" "g.example/gs 1.0.0  $H1  (git HERE/gs.git ${C1%????????????????????????????})
wrote HERE/app/tomato.lock (1 seed)" "$(cd "$A" && tm $t seed install 2>&1 | norm)"
  check "seed install: and the store has it again, as it was" "$H1" "$(tm $t seed hash "$store")"
  # a store folder changed after it was stored is caught by a build and by install
  printf '# changed\n' >> "$store/src/gs.tom"
  r="$(cd "$A" && tm $t run src/usegs.tom 2>&1 | norm)"
  case "$r" in "error[E601]: HERE/app/tomato.toml: the copy of g.example/gs in $(echo "$store" | norm) has the content hash "*"it was changed after it was put there (remove the folder and run \`tomato seed install\` to fetch it again)") ok "seed store: a build checks the stored copy against the lock";; *) bad "seed store: a build checks the stored copy against the lock" "$r";; esac
  r="$(cd "$A" && tm $t seed install 2>&1 | norm)"
  case "$r" in "error[E601]: HERE/app/tomato.toml: the copy of g.example/gs in $(echo "$store" | norm) has the content hash "*) ok "seed store: so does install";; *) bad "seed store: so does install" "$r";; esac
  rm -rf "$store"; (cd "$A" && tm $t seed install >/dev/null 2>&1)
  # a lock that does not match the repository: the hash decides, nothing is stored
  cp "$A/tomato.lock" "$W/lock.good"
  fake="sha256:0000000000000000000000000000000000000000000000000000000000000001"
  sed "s#^hash = .*#hash = \"$fake\"#" "$W/lock.good" > "$A/tomato.lock"
  rm -rf "$th/seeds/store"
  r="$(cd "$A" && tm $t seed install 2>&1 | norm)"
  check "seed install: a fetched seed that does not hash to the lock's hash is refused" "error[E601]: HERE/app/tomato.toml: the seed g.example/gs fetched from HERE/gs.git at $(echo "$C1" | cut -c1-12) has the content hash $H1, but tomato.lock says $fake: the repository does not hold what was locked (nothing was stored)" "$r"
  check "seed install: and nothing is in the store, not even a scratch folder" "" "$(find "$th/seeds/store" -type f 2>/dev/null; ls "$th/seeds/tmp")"
  cp "$W/lock.good" "$A/tomato.lock"
  # the hash of a git seed is the hash of the same files as a path seed
  rm -rf "$W/gs_files"; mkdir "$W/gs_files"; git -C "$W/gs" archive "$C1" | tar -x -C "$W/gs_files"
  check "the same files as a path seed have the same hash" "$H1" "$(tm $t seed hash "$W/gs_files")"
  # ---- the foreign symbols (D94b item 9)
  (cd "$A" && tm $t seed install >/dev/null 2>&1)
  cp "$A/tomato.toml" "$W/manifest.before"; cp "$A/tomato.lock" "$W/lock.before"
  r="$(cd "$A" && tm $t seed add --git "$gsurl" --rev "$C2" 2>&1 < /dev/null | norm)"
  check "foreign symbols: an update that adds one asks again, and with no terminal refuses" "error[E602]: HERE/app/tomato.toml: the seed g.example/gs 1.1.0 declares foreign symbols, !name(...) declarations that link functions of the runtime or of C into your program, with no check of their types by the compiler:
  tomato_json_quote  (src/gs.tom:1)
  = help: this command cannot ask here (standard input is not a terminal): run it at a terminal, or add --yes to accept them; nothing was changed" "$r"
  cmp -s "$W/manifest.before" "$A/tomato.toml" && cmp -s "$W/lock.before" "$A/tomato.lock" && ok "foreign symbols: the refusal changed neither the manifest nor the lock" || bad "foreign symbols: the refusal changed neither the manifest nor the lock"
  r="$(cd "$A" && tm $t seed add --git "$gsurl" --rev "$C2" --yes 2>&1 | norm)"
  check "foreign symbols: --yes lists them and goes on" "the seed g.example/gs 1.1.0 declares foreign symbols, !name(...) declarations that link functions of the runtime or of C into your program, with no check of their types by the compiler:
  tomato_json_quote  (src/gs.tom:1)
accepted with --yes; they are recorded in tomato.lock
added g.example/gs 1.1.0 to [seeds] of HERE/app/tomato.toml
g.example/gs 1.1.0  $H2  (git HERE/gs.git ${C2%????????????????????????????})
wrote HERE/app/tomato.lock (1 seed)" "$r"
  check "foreign symbols: the lock records the accepted symbols" 'symbols = ["tomato_json_quote"]' "$(grep '^symbols' "$A/tomato.lock")"
  check "foreign symbols: the manifest line has the new commit (an update is the same command with another --rev)" "\"g.example/gs\" = { git = \"$gsurl\", rev = \"$C2\" }" "$(sed -n '/^\[seeds\]/,$p' "$A/tomato.toml" | sed -n 2p)"
  check "foreign symbols: install asks nothing once they are in the lock" "g.example/gs 1.1.0  $H2  (git HERE/gs.git ${C2%????????????????????????????})
tomato.lock is up to date" "$(cd "$A" && tm $t seed install --locked < /dev/null 2>&1 | norm)"
  check "foreign symbols: and a program that does not touch them still runs" "hi from git 1.1" "$(cd "$A" && tm $t run src/usegs.tom 2>&1)"
  printf '%s[seeds]\n"g.example/gs" = { git = "%s", rev = "%s" }\n' "$head" "$gsurl" "$C1" > "$A/tomato.toml"
  r="$(cd "$A" && tm $t seed install < /dev/null 2>&1 | norm | sed -n 1p)"
  check "foreign symbols: going back to the version without them needs no answer" "g.example/gs 1.0.0  $H1  (git HERE/gs.git ${C1%????????????????????????????})" "$r"
  check "foreign symbols: and the lock no longer lists any" "0" "$(grep -c '^symbols' "$A/tomato.lock")"
  printf '%s[seeds]\n"g.example/gs" = { git = "%s", rev = "%s" }\n' "$head" "$gsurl" "$C2" > "$A/tomato.toml"
  r="$(cd "$A" && tm $t seed install < /dev/null 2>&1 | norm | sed -n 1p | cut -c1-60)"
  check "foreign symbols: going forward by editing the manifest asks again; install refuses with no terminal" "error[E602]: HERE/app/tomato.toml: the seed g.example/gs 1.1" "$r"
  r="$(cd "$A" && tm $t seed install --locked 2>&1 | norm | tail -n 1)"
  check "foreign symbols: install --locked says the lock is out of date (it has the old commit)" "error[E578]: HERE/app/tomato.toml: tomato.lock does not match this manifest: run \`tomato seed install\` and commit the new lock" "$r"
  (cd "$A" && tm $t seed install --yes >/dev/null 2>&1)
  check "foreign symbols: install --yes accepts them" 'symbols = ["tomato_json_quote"]' "$(grep '^symbols' "$A/tomato.lock")"
  # a path seed: the same, and the question on a terminal
  printf '!tomato_json_quote(text: str, ascii: int) -> str\nexport def local_name() -> str:\n    return "loc"\n' > "$W/loc/src/loc.tom"
  printf '%s' "$head" > "$A/tomato.toml"; rm -f "$A/tomato.lock"
  if command -v expect >/dev/null 2>&1; then
    check "foreign symbols: the question on a terminal (n and Enter refuse, y accepts)" "ok" "$(cd "$A" && PATH="$(dirname "$t"):$PATH" TOMATO_HOME="$th" expect "$root/tests/seed_prompt_pty.exp" "$A" "$W/loc" 2>&1 | tail -1)"
  else
    [ -n "$CI" ] && bad "seed prompt pty test" "expect is required in CI" || echo "skip: expect is not installed, so the seed prompt pty test did not run"
    (cd "$A" && tm $t seed add --path ../loc --yes >/dev/null 2>&1)
  fi
  # ---- hostile and unusable trees are refused, and nothing is stored
  mkdir -p "$W/bad"; rm -rf "$th/seeds/store"
  badrepo() { # NAME: a repository $W/bad/NAME with a valid seed that the caller then spoils; prints nothing
    git init -q -b main "$W/bad/$1"; mkdir -p "$W/bad/$1/src"; seed_toml bad.example/b 1.0.0 > "$W/bad/$1/tomato.toml"; printf 'export def f() -> int:\n    return 1\n' > "$W/bad/$1/src/b.tom"; }
  tryrepo() { # NAME [COMMIT]: commit the repository (unless it is committed already) and try to add it; prints the first line of the answer
    c="${2:-$(commit "$W/bad/$1" x)}"; bare "$W/bad/$1" "$W/bad/$1.git"
    (cd "$A" && tm $t seed add --git "$W/bad/$1.git" --rev "$c" --yes 2>&1 | norm | sed -n 1p | cut -c1-200); }
  badrepo link; ln -s /etc/passwd "$W/bad/link/src/l.tom"
  r="$(tryrepo link)"; case "$r" in "error[E600]: the seed at HERE/bad/link.git ("*"cannot be used: src/l.tom is a symbolic link, which a seed cannot contain (it could point outside the seed)") ok "seed add --git: a symbolic link in the tree is refused";; *) bad "seed add --git: a symbolic link in the tree is refused" "$r";; esac
  badrepo sub; git -C "$W/bad/sub" add -A >/dev/null; git -C "$W/bad/sub" update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,vendor/other; git -C "$W/bad/sub" commit -q -m x; csub="$(git -C "$W/bad/sub" rev-parse HEAD)"
  r="$(tryrepo sub "$csub")"; case "$r" in "error[E600]: the seed at HERE/bad/sub.git ("*"cannot be used: vendor/other is a submodule or another special entry, and a seed holds only plain files") ok "seed add --git: a submodule in the tree is refused";; *) bad "seed add --git: a submodule in the tree is refused" "$r";; esac
  badrepo case; printf 'export def g() -> int:\n    return 2\n' > "$W/bad/case/src/B.tom"
  r="$(tryrepo case)"; case "$r" in *"cannot be used: src/b.tom has the same name as another file when upper and lower case are the same"|*"cannot be used: src/B.tom has the same name as another file when upper and lower case are the same") ok "seed add --git: names that differ only in case are refused";; *) bad "seed add --git: names that differ only in case are refused" "$r";; esac
  badrepo big; head -c 10485761 /dev/zero > "$W/bad/big/data.bin"
  r="$(tryrepo big)"; case "$r" in *"cannot be used: data.bin is 10485761 bytes, over the limit of 10485760 for one file") ok "seed add --git: a file over the size limit is refused";; *) bad "seed add --git: a file over the size limit is refused" "$r";; esac
  badrepo noseed; rm "$W/bad/noseed/tomato.toml"
  r="$(tryrepo noseed)"; case "$r" in "error[E572]: "*"/tomato.toml"*) ok "seed add --git: a tree that has no tomato.toml is not a seed";; *) bad "seed add --git: a tree that has no tomato.toml is not a seed" "$r";; esac
  badrepo nomod; printf 'def (\n' > "$W/bad/nomod/src/b.tom"
  r="$(tryrepo nomod)"; case "$r" in "error[E600]: "*"cannot read the module to look for foreign symbols: "*) ok "seed add --git: a module that does not parse is refused (the symbols cannot be found)";; *) bad "seed add --git: a module that does not parse is refused" "$r";; esac
  check "seed store: nothing from the refused trees reached the store" "" "$(find "$th/seeds/store" -type f 2>/dev/null)"
  [ -z "$(ls "$th/seeds/tmp")" ] && ok "seed store: and no scratch folder is left" || bad "seed store: and no scratch folder is left" "$(ls "$th/seeds/tmp")"
  # a top-level builds/ folder in the tree is not part of the seed (D94b): it is not stored and not hashed
  badrepo builds; mkdir -p "$W/bad/builds/builds"; printf 'junk' > "$W/bad/builds/builds/junk"
  r="$(tryrepo builds)"; bh="$(indep_hash "$W/bad/builds")"; bd="$th/seeds/store/$(echo "${bh#sha256:}" | cut -c1-2)/${bh#sha256:}"
  case "$r" in "added bad.example/b 1.0.0 to [seeds]"*) ok "seed add --git: a tree with a top-level builds/ is a seed";; *) bad "seed add --git: a tree with a top-level builds/ is a seed" "$r";; esac
  [ -f "$bd/src/b.tom" ] && [ ! -e "$bd/builds" ] && ok "seed add --git: its builds/ was not written to the store (the hash is of the other files, as for a path)" || bad "seed add --git: its builds/ was not written to the store" "$(find "$th/seeds/store" | head)"
  # ---- URLs and revisions that are refused before git is started
  urlcheck() { # the words after `seed add`: sets r to the first line of the answer
    r="$(cd "$A" && tm $t seed add "$@" 2>&1 | norm | sed -n 1p | cut -c1-200)"; }
  urlcheck --git 'ext::sh-c-touch' --rev "$C1"; case "$r" in "error[E598]: HERE/app/tomato.toml: the git URL of the seed at ext::sh-c-touch cannot be used: a URL with :: names a helper program of git, which is refused") ok "seed add --git: a URL for a helper program (ext::) is refused";; *) bad "seed add --git: a URL for a helper program (ext::) is refused" "$r";; esac
  urlcheck --git '-oProxyCommand=x' --rev "$C1"; case "$r" in *"a URL cannot start with a hyphen"*) ok "seed add --git: a URL that starts with a hyphen is refused";; *) bad "seed add --git: a URL that starts with a hyphen is refused" "$r";; esac
  urlcheck --git 'http://example.invalid/x.git' --rev "$C1"; case "$r" in *"the scheme http:// is not used for seeds (the schemes are https, ssh and file)"*) ok "seed add --git: http:// is refused";; *) bad "seed add --git: http:// is refused" "$r";; esac
  urlcheck --git '../gs.git' --rev "$C1"; case "$r" in *"a folder on this machine is written as an absolute path or file:///path"*) ok "seed add --git: a relative folder is refused";; *) bad "seed add --git: a relative folder is refused" "$r";; esac
  urlcheck --git "$gsurl" --rev v1.0; case "$r" in *"is not a full commit id (40 lowercase hex digits)"*) ok "seed add --git: a tag as the rev is refused (a tag moves)";; *) bad "seed add --git: a tag as the rev is refused" "$r";; esac
  check "seed add --git: a rev of 40 digits that the repository does not have is a git error, and nothing is stored" "error[E599]:" "$(cd "$A" && tm $t seed add --git "$gsurl" --rev 0123456789012345678901234567890123456789 2>&1 | cut -c1-12)"
  check "seed add --offline: a git seed that the lock does not know is an error, git is not run" "error[E605]:" "$(cd "$A" && tm $t seed add --git "$gsurl" --rev "$C1" --offline 2>&1 | cut -c1-12)"
  check "seed add: --git needs --rev" "error: a git seed needs one of --rev COMMIT (the full commit id), --tag TAG or --branch BRANCH (usage: tomato seed add --path DIR | --git URL (--rev COMMIT | --tag TAG | --branch BRANCH) [--subdir DIR] [--test] [--yes] [--offline])" "$(cd "$A" && tm $t seed add --git "$gsurl" 2>&1)"
  check "seed add: --path takes no --rev" "error: --rev, --tag, --branch and --subdir go with --git, not with --path" "$(cd "$A" && tm $t seed add --path ../loc --rev "$C1" 2>&1)"
  check "seed add: it takes --path or --git, not a name (there is no registry)" "error: unknown option 'acme.example/x' for 'tomato seed add' (usage: tomato seed add --path DIR | --git URL (--rev COMMIT | --tag TAG | --branch BRANCH) [--subdir DIR] [--test] [--yes] [--offline])" "$(cd "$A" && tm $t seed add acme.example/x 2>&1)"
  check "seed add: with no source" "error: tomato seed add takes --path DIR or --git URL --rev COMMIT, one of them once (a registry name is not supported yet: there is no registry)" "$(cd "$A" && tm $t seed add --test 2>&1)"
  # ---- seed vendor and [seed-store] vendor
  (cd "$A" && printf '%s' "$head" > tomato.toml && rm -f tomato.lock && tm $t seed add --path ../loc --yes >/dev/null 2>&1 && tm $t seed add --git "$gsurl" --rev "$C1" >/dev/null 2>&1)
  r="$(cd "$A" && tm $t seed vendor 2>&1 | norm)"
  check "seed vendor: copies the locked seeds to vendor/OWNER/NAME" "vendored acme.example/loc 0.3.0 into HERE/app/vendor/acme.example/loc
vendored g.example/gs 1.0.0 into HERE/app/vendor/g.example/gs
builds use the vendor folder once tomato.toml says so: add  [seed-store]  vendor = \"vendor\"" "$r"
  check "seed vendor: the folders hash to the lock's hashes (a copy of a path seed and of a git seed)" "$(indep_hash "$W/loc") $H1" "$(indep_hash "$A/vendor/acme.example/loc") $(indep_hash "$A/vendor/g.example/gs")"
  [ -x "$A/vendor/g.example/gs/tool.sh" ] && ok "seed vendor: the executable file is still executable" || bad "seed vendor: the executable file is still executable"
  printf '\n[seed-store]\nvendor = "vendor"\n' >> "$A/tomato.toml"
  mv "$W/gs.git" "$W/gs.moved"; rm -rf "$th/seeds/store"; mv "$W/loc" "$W/loc.moved"
  check "[seed-store] vendor: a build uses the vendor folder, with no store, no repository and no path seed folder" "loc
hi from git" "$(cd "$A" && tm $t run src/main.tom 2>&1; tm $t run src/usegs.tom 2>&1)"
  mv "$W/loc.moved" "$W/loc"; mv "$W/gs.moved" "$W/gs.git"
  printf '# edited\n' >> "$A/vendor/g.example/gs/src/gs.tom"
  r="$(cd "$A" && tm $t run src/usegs.tom 2>&1 | norm)"
  case "$r" in "error[E601]: HERE/app/tomato.toml: the copy of g.example/gs in HERE/app/vendor/g.example/gs has the content hash "*) ok "[seed-store] vendor: an edited vendor copy is caught by every build";; *) bad "[seed-store] vendor: an edited vendor copy is caught by every build" "$r";; esac
  case "$(cd "$A" && tm $t run src/usegs.tom 2>&1 | norm)" in *"(run \`tomato seed vendor\` to copy it again)") ok "[seed-store] vendor: and says to vendor it again";; *) bad "[seed-store] vendor: and says to vendor it again";; esac
  (cd "$A" && tm $t seed vendor >/dev/null 2>&1)
  check "seed vendor: vendoring again replaces the edited copy" "hi from git" "$(cd "$A" && tm $t run src/usegs.tom 2>&1)"
  rm -rf "$A/vendor"
  r="$(cd "$A" && tm $t run src/usegs.tom 2>&1 | norm)"
  check "[seed-store] vendor: a build says to vendor when the folder is missing" "error[E569]: HERE/app/tomato.toml: the seed acme.example/loc is not in the vendor folder (HERE/app/vendor/acme.example/loc)
  = help: run: tomato seed vendor" "$r"
  printf '%s[seeds]\n"acme.example/loc" = { path = "../loc" }\n\n[seed-store]\nvendor = "../outside"\n' "$head" > "$A/tomato.toml"
  check "seed vendor: a vendor folder that leaves the project is refused" 'error[E604]: HERE/app/tomato.toml: seed-store.vendor is "../outside", but the vendor folder must be a folder below the one with tomato.toml (no leading / and no ..)' "$(cd "$A" && tm $t seed vendor 2>&1 | norm)"
  printf '%s[seeds]\n"acme.example/loc" = { path = "../loc" }\n' "$head" > "$A/tomato.toml"
  printf 'x\n' >> "$W/loc/src/loc.tom"
  case "$(cd "$A" && tm $t seed vendor 2>&1 | norm)" in "error[E578]: HERE/app/tomato.toml: tomato.lock does not match this manifest: run \`tomato seed install\` and commit the new lock") ok "seed vendor: a lock that is out of date is an error (install first)";; *) bad "seed vendor: a lock that is out of date is an error (install first)" "$(cd "$A" && tm $t seed vendor 2>&1 | norm)";; esac
  cd "$work" || true
}
t_cli_seed_update() { # tomato seed verify, seed update (tag and branch, --dry-run, the question about new symbols) and the git seed's path (a folder of a repository); local bare git repos only, no network
  cli_setup
  if ! command -v git >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "seed update: git is required in CI" || echo "skip: git is not installed, so the seed update tests did not run"
    return
  fi
  W="$work/su"; mkdir -p "$W"; cd "$W" || return 1
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.t
  th="$W/home"; mkdir -p "$th"; here="$(pwd -P)"
  tm() { TOMATO_HOME="$th" "$@"; }
  sum256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi; }
  indep_hash() { printf 'sha256:%s' "$(cd "$1" && find . -type f ! -path './.git/*' ! -path './builds/*' | sed 's#^\./##' | LC_ALL=C sort | while read -r f; do m=644; [ -x "$f" ] && m=755; printf '%s  %s  %s\n' "$(sum256 < "$f")" "$m" "$f"; done | sum256)"; }
  norm() { sed "s#$here#HERE#g"; }
  commit() { git -C "$1" add -A >/dev/null && git -C "$1" commit -q -m "$2" && git -C "$1" rev-parse HEAD; }
  bare() { rm -rf "$2"; git clone -q --bare "$1" "$2"; }
  seed_toml() { printf '[seed]\nname = "%s"\nversion = "%s"\ntomato = "0.51"\n' "$1" "$2"; }
  c12() { printf '%s' "$1" | cut -c1-12; }
  c19() { printf '%s' "$1" | cut -c1-19; }
  store_of() { printf '%s/seeds/store/%s/%s' "$th" "$(printf '%s' "${1#sha256:}" | cut -c1-2)" "${1#sha256:}"; }
  lockfield() { n="$(printf '%s' "$1" | sed 's#/#\\/#g')"; sed -n "/name = \"$n\"/,/^seeds/p" "$A/tomato.lock" | sed -n "s/^$2 = \"\\(.*\\)\"/\\1/p"; }
  checkn() { check "$1" "$(printf '%s' "$2" | norm)" "$3"; }
  # ---- the repositories: gs (tag v1 on 1.0.0, later moved), br (a branch), pin (no tag, no branch), mono (two seeds in folders of one repository)
  git init -q -b main "$W/gs"; mkdir -p "$W/gs/src"; seed_toml g.example/gs 1.0.0 > "$W/gs/tomato.toml"
  printf 'export def hi() -> str:\n    return "hi 1.0"\n' > "$W/gs/src/gs.tom"
  GC1="$(commit "$W/gs" one)"; git -C "$W/gs" tag v1; GH1="$(indep_hash "$W/gs")"; bare "$W/gs" "$W/gs.git"
  git init -q -b main "$W/br"; mkdir -p "$W/br/src"; seed_toml b.example/br 0.1.0 > "$W/br/tomato.toml"
  printf 'export def f() -> int:\n    return 1\n' > "$W/br/src/br.tom"
  BC1="$(commit "$W/br" one)"; bare "$W/br" "$W/br.git"
  git init -q -b main "$W/pin"; mkdir -p "$W/pin/src"; seed_toml p.example/pin 2.0.0 > "$W/pin/tomato.toml"
  printf 'export def p() -> int:\n    return 7\n' > "$W/pin/src/pin.tom"
  PC1="$(commit "$W/pin" one)"; bare "$W/pin" "$W/pin.git"
  git init -q -b main "$W/mono"; mkdir -p "$W/mono/seeds/a/src" "$W/mono/seeds/b/src" "$W/mono/other"
  seed_toml m.example/a 1.0.0 > "$W/mono/seeds/a/tomato.toml"; printf 'export def a() -> str:\n    return "a from mono"\n' > "$W/mono/seeds/a/src/a.tom"
  seed_toml m.example/b 1.0.0 > "$W/mono/seeds/b/tomato.toml"; printf 'export def b() -> str:\n    return "b from mono"\n' > "$W/mono/seeds/b/src/b.tom"
  printf '#!/bin/sh\necho tool\n' > "$W/mono/seeds/a/tool.sh"; chmod 755 "$W/mono/seeds/a/tool.sh"
  printf 'not a seed\n' > "$W/mono/README"; ln -s ../README "$W/mono/other/link"
  MC1="$(commit "$W/mono" one)"; bare "$W/mono" "$W/mono.git"
  mkdir -p "$W/app/src"; A="$W/app"
  head='[project]
name = "app"
version = "0.1.0"
tomato = "0.51"
'
  printf '%s' "$head" > "$A/tomato.toml"
  printf 'from gs import hi\n\n@main\ndef main():\n    print(hi())\n' > "$A/src/main.tom"
  # ---- seed add --tag: the tag is looked up once; the manifest holds the commit and the tag
  r="$(cd "$A" && tm $t seed add --git "$W/gs.git" --tag v1 2>&1 | norm)"
  checkn "seed add --tag: says which commit the tag is at" "added g.example/gs 1.0.0 to [seeds] of HERE/app/tomato.toml (tag v1 is at $(c12 "$GC1"))
g.example/gs 1.0.0  $GH1  (git HERE/gs.git $(c12 "$GC1"))
wrote HERE/app/tomato.lock (1 seed)" "$r"
  checkn "seed add --tag: tomato.toml holds the commit and the tag" "\"g.example/gs\" = { git = \"$W/gs.git\", rev = \"$GC1\", tag = \"v1\" }" "$(sed -n '/^\[seeds\]/,$p' "$A/tomato.toml" | sed 1d | norm)"
  checkn "seed add --tag: the program uses the seed" "hi 1.0" "$(cd "$A" && tm $t run 2>&1)"
  checkn "seed add --tag: a lock that needs no path is still version 1" "version = 1" "$(sed -n 2p "$A/tomato.lock")"
  # ---- seed verify: a fresh install matches
  r="$(cd "$A" && tm $t seed verify 2>&1 | norm; echo "rc=$?")"
  checkn "seed verify: every copy matches the lock" "ok       g.example/gs 1.0.0  store: $(store_of "$GH1" | norm)
verified 1 copy of 1 locked seed: all match tomato.lock
rc=0" "$r"
  # ---- seed update: nothing to do, then the tag moves (an annotated tag, which has to be followed to its commit)
  r="$(cd "$A" && tm $t seed update 2>&1 | norm)"
  checkn "seed update: a tag that did not move changes nothing" "g.example/gs: tag v1 is still at $(c12 "$GC1")
g.example/gs 1.0.0: unchanged
tomato.lock is already up to date" "$r"
  seed_toml g.example/gs 1.1.0 > "$W/gs/tomato.toml"
  printf 'export def hi() -> str:\n    return "hi 1.1"\n' > "$W/gs/src/gs.tom"
  GC2="$(commit "$W/gs" two)"; git -C "$W/gs" tag -a -f -m "version 1.1" v1 >/dev/null 2>&1; GH2="$(indep_hash "$W/gs")"; bare "$W/gs" "$W/gs.git"
  cp "$A/tomato.toml" "$W/manifest.before"; cp "$A/tomato.lock" "$W/lock.before"
  r="$(cd "$A" && tm $t seed update --dry-run 2>&1 | norm)"
  checkn "seed update --dry-run: shows the new commit, version and hash, and writes nothing" "g.example/gs: tag v1 is now at $(c12 "$GC2") (was $(c12 "$GC1"))
g.example/gs: 1.0.0 -> 1.1.0
  commit  $(c12 "$GC1") -> $(c12 "$GC2")
  hash    $(c19 "$GH1")... -> $(c19 "$GH2")...
dry run: tomato.toml and tomato.lock are as they were
the seeds above would move; run without --dry-run to do it" "$r"
  cmp -s "$W/manifest.before" "$A/tomato.toml" && cmp -s "$W/lock.before" "$A/tomato.lock" && ok "seed update --dry-run: tomato.toml and tomato.lock are exactly as they were" || bad "seed update --dry-run: tomato.toml and tomato.lock are exactly as they were"
  r="$(cd "$A" && tm $t seed update 2>&1 | norm)"
  checkn "seed update: a version bump asks nothing, moves the rev and writes the new hash" "g.example/gs: tag v1 is now at $(c12 "$GC2") (was $(c12 "$GC1"))
g.example/gs: 1.0.0 -> 1.1.0
  commit  $(c12 "$GC1") -> $(c12 "$GC2")
  hash    $(c19 "$GH1")... -> $(c19 "$GH2")...
wrote HERE/app/tomato.lock (1 seed)" "$r"
  checkn "seed update: only the rev of the line changed, the tag stayed" "+\"g.example/gs\" = { git = \"$W/gs.git\", rev = \"$GC2\", tag = \"v1\" }" "$(diff "$W/manifest.before" "$A/tomato.toml" | grep '^>' | sed 's/^> */+/' | norm)"
  checkn "seed update: the lock has the new commit and the hash of find, sort and sha256" "$GC2 $GH2 1.1.0" "$(lockfield g.example/gs commit) $(lockfield g.example/gs hash) $(lockfield g.example/gs version)"
  checkn "seed update: the program uses the new version" "hi 1.1" "$(cd "$A" && tm $t run 2>&1)"
  checkn "seed update: install --locked agrees with the new manifest and lock" "tomato.lock is up to date" "$(cd "$A" && tm $t seed install --locked 2>&1 | tail -n 1)"
  checkn "seed update: a second update has nothing to do" "tomato.lock is already up to date" "$(cd "$A" && tm $t seed update 2>&1 | tail -n 1)"
  # ---- a new foreign symbol asks again: with no terminal and no --yes the update changes nothing, and --yes accepts
  printf '!tomato_json_quote(text: str, ascii: int) -> str\nexport def hi() -> str:\n    return "hi 1.2"\n' > "$W/gs/src/gs.tom"
  seed_toml g.example/gs 1.2.0 > "$W/gs/tomato.toml"
  GC3="$(commit "$W/gs" three)"; git -C "$W/gs" tag -f v1 >/dev/null 2>&1; bare "$W/gs" "$W/gs.git"
  cp "$A/tomato.toml" "$W/manifest.before"; cp "$A/tomato.lock" "$W/lock.before"
  r="$(cd "$A" && tm $t seed update --dry-run 2>&1 | norm | sed -n '4,5p')"
  checkn "seed update --dry-run: says that it would ask about the new symbol" "  hash    $(c19 "$GH2")... -> $(indep_hash "$W/gs" | cut -c1-19)...
  new foreign symbols: tomato_json_quote (the update would ask you to accept them)" "$r"
  r="$(cd "$A" && tm $t seed update 2>&1 | norm | cut -c1-200)"
  case "$r" in *"error[E602]: HERE/app/tomato.toml: the seed g.example/gs 1.2.0 declares foreign symbols"*"this command cannot ask here"*"nothing was changed") ok "seed update: a new foreign symbol is asked about again (no terminal, no --yes: refused)";; *) bad "seed update: a new foreign symbol is asked about again" "$r";; esac
  cmp -s "$W/manifest.before" "$A/tomato.toml" && cmp -s "$W/lock.before" "$A/tomato.lock" && ok "seed update: a refused question leaves tomato.toml and tomato.lock exactly as they were" || bad "seed update: a refused question leaves tomato.toml and tomato.lock exactly as they were" "$(diff "$W/manifest.before" "$A/tomato.toml")"
  r="$(cd "$A" && tm $t seed update --yes 2>&1 | norm | tail -n 3)"
  checkn "seed update --yes: accepts and records them" "accepted with --yes; they are recorded in tomato.lock
wrote HERE/app/tomato.lock (1 seed)" "$(printf '%s\n' "$r" | tail -n 2)"
  checkn "seed update --yes: the lock has the symbol and the new commit" "tomato_json_quote $GC3" "$(sed -n 's/^symbols = \["\(.*\)"\]/\1/p' "$A/tomato.lock") $(lockfield g.example/gs commit)"
  # ---- only the named seeds move; one that is pinned is said to be; a branch is followed
  r="$(cd "$A" && tm $t seed add --git "$W/br.git" --branch main 2>&1 | norm | sed -n 1p)"
  checkn "seed add --branch: the branch is looked up and its commit written" "added b.example/br 0.1.0 to [seeds] of HERE/app/tomato.toml (branch main is at $(c12 "$BC1"))" "$r"
  r="$(cd "$A" && tm $t seed add --git "$W/pin.git" --rev "$PC1" 2>&1 | norm | sed -n 1p)"
  checkn "seed add --rev: a pinned seed (no tag, no branch)" "added p.example/pin 2.0.0 to [seeds] of HERE/app/tomato.toml" "$r"
  printf 'export def f() -> int:\n    return 2\n' > "$W/br/src/br.tom"; seed_toml b.example/br 0.2.0 > "$W/br/tomato.toml"; BC2="$(commit "$W/br" two)"; bare "$W/br" "$W/br.git"
  printf 'export def hi() -> str:\n    return "hi 1.3"\n' > "$W/gs/src/gs.tom"; seed_toml g.example/gs 1.3.0 > "$W/gs/tomato.toml"; GC4="$(commit "$W/gs" four)"; git -C "$W/gs" tag -f v1 >/dev/null 2>&1; bare "$W/gs" "$W/gs.git"
  cp "$A/tomato.toml" "$W/manifest.before"; BH1="$(lockfield b.example/br hash)"
  r="$(cd "$A" && tm $t seed update b.example/br p.example/pin 2>&1 | norm)"
  checkn "seed update NAME...: only the named seeds are looked at; a branch moves, a pinned seed is left" "b.example/br: branch main is now at $(c12 "$BC2") (was $(c12 "$BC1"))
p.example/pin: pinned to the commit $(c12 "$PC1"), with no tag or branch to follow (add tag = \"...\" or branch = \"...\" to its line in tomato.toml, or: tomato seed add --git $W/pin.git --rev NEWCOMMIT)
b.example/br: 0.1.0 -> 0.2.0
  commit  $(c12 "$BC1") -> $(c12 "$BC2")
  hash    $(c19 "$BH1")... -> $(indep_hash "$W/br" | cut -c1-19)...
  note: 0.2.0 is not on the compatible line of 0.1.0 (a new major version, or a new minor one below 1.0)
p.example/pin 2.0.0: unchanged
wrote HERE/app/tomato.lock (3 seeds)" "$r"
  checkn "seed update NAME...: g.example/gs was not named, so its rev did not move" "$GC3" "$(lockfield g.example/gs commit)"
  checkn "seed update NAME...: and only the branch seed's line differs" "+\"b.example/br\" = { git = \"$W/br.git\", rev = \"$BC2\", branch = \"main\" }" "$(diff "$W/manifest.before" "$A/tomato.toml" | grep '^>' | sed 's/^> */+/' | norm)"
  r="$(cd "$A" && tm $t seed update --yes 2>&1 | norm | grep -c 'is now at')"
  checkn "seed update: with no name every seed that follows a tag or branch moves" "1" "$r"
  r="$(cd "$A" && tm $t seed update nope.example/x 2>&1 | norm)"
  checkn "seed update: a name that is not in the manifest is an error" "error[E604]: HERE/app/tomato.toml: nope.example/x is not in [seeds] or [test-seeds] of this tomato.toml (the seeds here: g.example/gs, b.example/br, p.example/pin)" "$r"
  printf '%s[seeds]\n"x.example/y" = "1.0.0"\n' "$head" > "$W/regapp.toml"; mkdir -p "$W/reg"; cp "$W/regapp.toml" "$W/reg/tomato.toml"
  r="$(cd "$W/reg" && tm $t seed update 2>&1 | norm)"
  checkn "seed update: a registry seed cannot be updated (there is no registry)" 'error[E571]: HERE/reg/tomato.toml: the seed x.example/y 1.0.0 would come from a registry, and there is none yet; only { path = "../folder" } and { git = "URL", rev = "COMMIT" } seeds can be updated' "$r"
  r="$(cd "$W/gs" && tm $t seed update 2>&1 | norm)"
  checkn "seed update: a seed's own manifest is refused" "error[E604]: HERE/gs/tomato.toml: seeds are updated in a [project], and this file is a seed (a package can use only registered seeds, and there is no registry yet)" "$r"
  r="$(cd "$W/empty" 2>/dev/null || { mkdir -p "$W/empty" && cd "$W/empty"; }; printf '%s' "$head" > tomato.toml; tm $t seed update 2>&1; echo "rc=$?")"
  checkn "seed update: a project with no seeds has nothing to update" "the manifest lists no seeds: nothing to update
rc=0" "$r"
  # a refused question changes nothing in any seed (two seeds move, the second declares a symbol)
  printf '!sym_one() -> int\nexport def f() -> int:\n    return 3\n' > "$W/br/src/br.tom"; BC3="$(commit "$W/br" three)"; bare "$W/br" "$W/br.git"
  printf 'export def hi() -> str:\n    return "hi 1.4"\n' > "$W/gs/src/gs.tom"; GC5="$(commit "$W/gs" five)"; git -C "$W/gs" tag -f v1 >/dev/null 2>&1; bare "$W/gs" "$W/gs.git"
  cp "$A/tomato.toml" "$W/manifest.before"; cp "$A/tomato.lock" "$W/lock.before"
  (cd "$A" && tm $t seed update 2>&1 | grep -c 'E602' | sed 's/^/x/') >/dev/null
  cmp -s "$W/manifest.before" "$A/tomato.toml" && cmp -s "$W/lock.before" "$A/tomato.lock" && ok "seed update: when one of two moving seeds is refused, neither moves" || bad "seed update: when one of two moving seeds is refused, neither moves"
  (cd "$A" && tm $t seed update --yes >/dev/null 2>&1)
  checkn "seed update --yes: both moved after the answer" "$GC5 $BC3" "$(lockfield g.example/gs commit) $(lockfield b.example/br commit)"
  # ---- a tag that does not exist, and names that git would read as options
  git -C "$W/gs" tag -d v1 >/dev/null 2>&1; bare "$W/gs" "$W/gs.git"
  r="$(cd "$A" && tm $t seed update g.example/gs 2>&1 | norm | cut -c1-120)"
  case "$r" in "error[E599]: fetching the tag v1 from "*) ok "seed update: a tag that the repository no longer has is an error from git (nothing is changed)";; *) bad "seed update: a missing tag" "$r";; esac
  r="$(cd "$A" && tm $t seed add --git "$W/gs.git" --tag=-x 2>&1 | norm | cut -c1-120)"
  case "$r" in *"unknown option"*) ok "seed add: --tag=x is not a form (the option takes the next word)";; *) bad "seed add: --tag=x is not a form" "$r";; esac
  r="$(cd "$A" && tm $t seed add --git "$W/gs.git" --tag -x 2>&1 | norm)"
  checkn "seed add --tag: a name that starts with a hyphen is refused before git is started" "error[E598]: HERE/app/tomato.toml: the tag \"-x\" of the seed at $W/gs.git cannot be used: a name cannot start with a hyphen (it would be read as an option of git)" "$r"
  r="$(cd "$A" && tm $t seed add --git "$W/gs.git" --tag v1 --rev "$GC1" 2>&1 | norm | cut -c1-140)"
  case "$r" in "error: a git seed needs one of --rev COMMIT"*) ok "seed add: --rev and --tag together are refused";; *) bad "seed add: --rev and --tag together" "$r";; esac
  # ---- the path of a seed in a repository that holds several
  printf '%s' "$head" > "$A/tomato.toml"; rm -f "$A/tomato.lock"
  r="$(cd "$A" && tm $t seed add --git "$W/mono.git" --rev "$MC1" --subdir seeds/a 2>&1 | norm)"
  MAH="$(indep_hash "$W/mono/seeds/a")"
  checkn "seed add --subdir: the seed is the folder of the repository" "added m.example/a 1.0.0 to [seeds] of HERE/app/tomato.toml
m.example/a 1.0.0  $MAH  (git HERE/mono.git $(c12 "$MC1") path seeds/a)
wrote HERE/app/tomato.lock (1 seed)" "$r"
  checkn "seed add --subdir: tomato.toml has path" "\"m.example/a\" = { git = \"$W/mono.git\", rev = \"$MC1\", path = \"seeds/a\" }" "$(sed -n '/^\[seeds\]/,$p' "$A/tomato.toml" | sed 1d | norm)"
  checkn "seed add --subdir: the lock has path and is version 2 (version 1 cannot say it)" "version = 2 seeds/a" "$(sed -n 2p "$A/tomato.lock") $(lockfield m.example/a path)"
  checkn "seed add --subdir: the hash is that of the folder alone (find, sort, sha256), the mode of the tool kept" "$MAH 755" "$(lockfield m.example/a hash) $(stat -c %a "$(store_of "$MAH")/tool.sh" 2>/dev/null || stat -f %Lp "$(store_of "$MAH")/tool.sh")"
  (cd "$A" && tm $t seed add --git "$W/mono.git" --rev "$MC1" --subdir seeds/b >/dev/null 2>&1)
  printf 'from a import a\nfrom b import b\n\n@main\ndef main():\n    print(a())\n    print(b())\n' > "$A/src/main.tom"
  checkn "seed add --subdir: two seeds of one repository, both used" "a from mono
b from mono" "$(cd "$A" && tm $t run 2>&1)"
  checkn "seed add --subdir: install --locked agrees" "tomato.lock is up to date" "$(cd "$A" && tm $t seed install --locked 2>&1 | tail -n 1)"
  checkn "seed update: a seed with a path and no tag is pinned (the path stays)" "m.example/a: pinned to the commit $(c12 "$MC1"), with no tag or branch to follow (add tag = \"...\" or branch = \"...\" to its line in tomato.toml, or: tomato seed add --git $W/mono.git --rev NEWCOMMIT)" "$(cd "$A" && tm $t seed update m.example/a 2>&1 | sed -n 1p | norm)"
  r="$(cd "$A" && tm $t seed verify 2>&1 | norm | tail -n 1)"
  checkn "seed verify: seeds of one repository are two copies" "verified 2 copies of 2 locked seeds: all match tomato.lock" "$r"
  r="$(cd "$A" && tm $t seed add --git "$W/mono.git" --rev "$MC1" --subdir seeds/c 2>&1 | norm)"
  checkn "seed add --subdir: a folder with nothing in it" "error[E600]: the seed at $W/mono.git ($(c12 "$MC1")) cannot be used: it has no files in the folder seeds/c (is that path right?)" "$r"
  r="$(cd "$A" && tm $t seed add --git "$W/mono.git" --rev "$MC1" --subdir other 2>&1 | norm)"
  checkn "seed add --subdir: a symbolic link inside the folder is refused (the one outside it, in another folder, is not looked at)" "error[E600]: the seed at $W/mono.git ($(c12 "$MC1")) cannot be used: link is a symbolic link, which a seed cannot contain (it could point outside the seed)" "$r"
  r="$(cd "$A" && tm $t seed add --git "$W/mono.git" --rev "$MC1" --subdir README 2>&1 | norm)"
  checkn "seed add --subdir: a path that is a file, not a folder" "error[E600]: the seed at $W/mono.git ($(c12 "$MC1")) cannot be used: README is a file (or a link or a submodule), not a folder" "$r"
  for bad_sub in ../x /abs seeds//a seeds/a/ seeds/./a; do
    r="$(cd "$A" && tm $t seed add --git "$W/mono.git" --rev "$MC1" --subdir "$bad_sub" 2>&1 | norm | cut -c1-70)"
    case "$r" in "error[E598]: HERE/app/tomato.toml: the path \"$bad_sub\" of the seed at"*|"error[E598]: the path \"$bad_sub\" of the seed at"*) ok "seed add --subdir: '$bad_sub' is refused before git is started";; *) bad "seed add --subdir: '$bad_sub' is refused" "$r";; esac
  done
  # a path in tomato.toml that is not a git seed's: path with a rev but no git is a missing setting; tag and branch together are refused
  printf '%s[seeds]\n"m.example/a" = { rev = "%s", path = "seeds/a" }\n' "$head" "$MC1" > "$A/tomato.toml.x"
  r="$(cd "$A" && cp tomato.toml tomato.toml.keep && cp tomato.toml.x tomato.toml && tm $t seed install 2>&1 | norm; cp tomato.toml.keep tomato.toml)"
  checkn "tomato.toml: a rev and a path with no git is refused (a mix of the two forms)" "error[E568]: HERE/app/tomato.toml: seeds.\"m.example/a\" has path and also rev, tag or branch but no git: a path seed is only { path = \"../folder\" }, and a git seed needs git (its path is the folder of the repository)" "$r"
  printf '%s[seeds]\n"m.example/a" = { git = "%s/mono.git", rev = "%s", tag = "v1", branch = "main" }\n' "$head" "$W" "$MC1" > "$A/tomato.toml"
  checkn "tomato.toml: a tag and a branch together are refused" "error[E568]: HERE/app/tomato.toml: seeds.\"m.example/a\" has tag and also branch: a seed follows one or the other" "$(cd "$A" && tm $t seed install 2>&1 | norm)"
  printf '%s[seeds]\n"m.example/a" = { git = "%s/mono.git", rev = "%s", path = "seeds/a" }\n"m.example/b" = { git = "%s/mono.git", rev = "%s", path = "seeds/b", tag = "-x" }\n' "$head" "$W" "$MC1" "$W" "$MC1" > "$A/tomato.toml"
  r="$(cd "$A" && tm $t seed install 2>&1 | norm)"
  checkn "tomato.toml: a tag that git would read as an option is refused" "error[E598]: HERE/app/tomato.toml: the tag \"-x\" of the seed m.example/b cannot be used: a name cannot start with a hyphen (it would be read as an option of git)" "$r"
  # a build checks the path too: the lock says another path than the manifest
  printf '%s[seeds]\n"m.example/a" = { git = "%s/mono.git", rev = "%s", path = "seeds/a" }\n' "$head" "$W" "$MC1" > "$A/tomato.toml"
  (cd "$A" && tm $t seed install >/dev/null 2>&1)
  sed -i.bak 's#path = "seeds/a"#path = "seeds/b"#' "$A/tomato.toml" && rm -f "$A/tomato.toml.bak"
  printf 'from a import a\n\n@main\ndef main():\n    print(a())\n' > "$A/src/main.tom"
  checkn "a build: the lock holds another path than tomato.toml, so run says install" "error[E569]: HERE/app/tomato.toml: tomato.lock has the seed m.example/a from another source than the git URL and rev in tomato.toml
  = help: run: tomato seed install" "$(cd "$A" && tm $t run 2>&1 | norm | head -n 2)"
  sed -i.bak 's#path = "seeds/b"#path = "seeds/a"#' "$A/tomato.toml" && rm -f "$A/tomato.toml.bak"
  # ---- the lock's format version
  cp "$A/tomato.lock" "$W/lock.v2"
  sed -i.bak 's/^version = 2/version = 3/' "$A/tomato.lock" && rm -f "$A/tomato.lock.bak"
  checkn "tomato.lock: a version this Tomato does not know is refused (a newer Tomato wrote it)" "error[E578]: HERE/app/tomato.lock: this lock is not version 1 or 2 (a newer Tomato wrote it?): run \`tomato seed install\` to write it again" "$(cd "$A" && tm $t seed verify 2>&1 | norm | head -n 1)"
  sed -i.bak 's/^version = 3/version = 1/' "$A/tomato.lock" && rm -f "$A/tomato.lock.bak"
  checkn "tomato.lock: a git path in a version 1 lock is a damaged lock" "error[E578]: HERE/app/tomato.lock: a git [[seed]] entry has a path, which only a lock of version 2 has: the lock is damaged, run \`tomato seed install\`" "$(cd "$A" && tm $t seed verify 2>&1 | norm | head -n 1)"
  cp "$W/lock.v2" "$A/tomato.lock"
  checkn "tomato.lock: install --locked on a version 2 lock that is right" "tomato.lock is up to date" "$(cd "$A" && tm $t seed install --locked 2>&1 | tail -n 1)"
  # ---- seed verify finds a changed copy, a missing copy, an edited path seed, and a vendored copy
  mkdir -p "$W/loc/src"; seed_toml acme.example/loc 0.3.0 > "$W/loc/tomato.toml"; printf 'export def local_name() -> str:\n    return "loc"\n' > "$W/loc/src/loc.tom"
  (cd "$A" && tm $t seed add --path ../loc >/dev/null 2>&1)
  MAH="$(lockfield m.example/a hash)"; LH="$(lockfield acme.example/loc hash)"
  r="$(cd "$A" && tm $t seed verify 2>&1 | norm; echo "rc=$?")"
  checkn "seed verify: a git seed in the store and a path seed, one line each" "ok       acme.example/loc 0.3.0  path: HERE/loc
ok       m.example/a 1.0.0  store: $(store_of "$MAH" | norm)
verified 2 copies of 2 locked seeds: all match tomato.lock
rc=0" "$r"
  chmod -R u+w "$(store_of "$MAH")"; printf 'x\n' >> "$(store_of "$MAH")/src/a.tom"
  printf 'x\n' >> "$W/loc/src/loc.tom"
  r="$(cd "$A" && tm $t seed verify > "$W/v.out" 2> "$W/v.err"; echo "rc=$?"; norm < "$W/v.out"; norm < "$W/v.err")"
  checkn "seed verify: a changed store copy and an edited path folder are problems, every copy is listed, exit status 1" "rc=1
CHANGED  acme.example/loc 0.3.0: the path copy $W/loc has the content hash $(indep_hash "$W/loc"), but tomato.lock says $LH; the folder was edited after it was locked: run: tomato seed install
CHANGED  m.example/a 1.0.0: the store copy $(store_of "$MAH") has the content hash $(indep_hash "$(store_of "$MAH")"), but tomato.lock says $MAH; remove the folder and run: tomato seed install
error[E606]: HERE/app/tomato.lock: verify found 2 problems in 2 locked seeds (2 copies checked)" "$(printf '%s' "$r" | sed "s#$W#HERE/su#g")"
  rm -rf "$(store_of "$MAH")"
  r="$(cd "$A" && tm $t seed verify 2>/dev/null | grep MISSING | norm)"
  checkn "seed verify: a seed that is not in the store is missing" "MISSING  m.example/a 1.0.0: the store copy $(store_of "$MAH" | norm) is not there (run: tomato seed install)" "$r"
  sed -i.bak '$d' "$W/loc/src/loc.tom"; rm -f "$W/loc/src/loc.tom.bak"
  (cd "$A" && tm $t seed install >/dev/null 2>&1)
  checkn "seed verify: install fetches the missing copy again, and the edit was undone (no change of the lock)" "verified 2 copies of 2 locked seeds: all match tomato.lock" "$(cd "$A" && tm $t seed verify 2>&1 | tail -n 1)"
  # the vendor folder
  printf '[seed-store]\nvendor = "vendor"\n' >> "$A/tomato.toml"
  r="$(cd "$A" && tm $t seed vendor >/dev/null 2>&1; tm $t seed verify 2>&1 | norm)"
  checkn "seed verify: with [seed-store] vendor, the vendor copies are checked too" "ok       acme.example/loc 0.3.0  path: HERE/loc
ok       acme.example/loc 0.3.0  vendor: HERE/app/vendor/acme.example/loc
ok       m.example/a 1.0.0  store: $(store_of "$MAH" | norm)
ok       m.example/a 1.0.0  vendor: HERE/app/vendor/m.example/a
verified 4 copies of 2 locked seeds: all match tomato.lock" "$r"
  printf 'x\n' >> "$A/vendor/m.example/a/src/a.tom"; mv "$A/vendor/acme.example/loc" "$W/loc.moved"; mv "$W/loc" "$W/loc.away"
  r="$(cd "$A" && tm $t seed verify > "$W/v.out" 2>&1; echo "rc=$?"; norm < "$W/v.out" | sed "s#$MAH#MAH#g; s#$(indep_hash "$A/vendor/m.example/a")#NEW#")"
  checkn "seed verify: an edited vendor copy, a missing one, and a path folder that is gone (the vendor copy serves the build: skipped)" "rc=1
skipped  acme.example/loc 0.3.0: the folder HERE/loc is not here, and the build uses the vendor copy
MISSING  acme.example/loc 0.3.0: the vendor copy HERE/app/vendor/acme.example/loc is not there (run: tomato seed vendor)
ok       m.example/a 1.0.0  store: $(store_of "$MAH" | norm | sed "s#$MAH#MAH#")
CHANGED  m.example/a 1.0.0: the vendor copy HERE/app/vendor/m.example/a has the content hash NEW, but tomato.lock says MAH; run: tomato seed vendor
error[E606]: HERE/app/tomato.lock: verify found 2 problems in 2 locked seeds (2 copies checked)" "$(printf '%s' "$r" | sed "s#$W#HERE/su#g")"
  mv "$W/loc.away" "$W/loc"; mv "$W/loc.moved" "$A/vendor/acme.example/loc"
  # verify with no lock, and with a lock that has no seeds
  mkdir -p "$W/nolock"; printf '%s' "$head" > "$W/nolock/tomato.toml"
  checkn "seed verify: no lock and no seeds is nothing to verify" "there is no tomato.lock and the manifest lists no seeds: nothing to verify" "$(cd "$W/nolock" && tm $t seed verify 2>&1)"
  printf '%s[seeds]\n"acme.example/loc" = { path = "../loc" }\n' "$head" > "$W/nolock/tomato.toml"
  mkdir -p "$W/nolock2"; cp "$W/nolock/tomato.toml" "$W/nolock2/tomato.toml"; sed -i.bak 's#\.\./loc#../loc#' "$W/nolock2/tomato.toml"; rm -f "$W/nolock2/tomato.toml.bak"
  checkn "seed verify: seeds in the manifest and no lock is an error that says install" "error[E569]: HERE/nolock/tomato.toml: the manifest lists seeds, but there is no tomato.lock beside it
  = help: run: tomato seed install" "$(cd "$W/nolock" && tm $t seed verify 2>&1 | norm | sed "s#$W#HERE/su#g; s#HERE/HERE/su#HERE/su#")"
  r="$(cd "$A" && tm $t seed verify extra 2>&1)"
  checkn "seed verify: takes no words" "error: tomato seed verify takes no words (usage: tomato seed verify)" "$r"
  # a seed listed in [seeds] and in [test-seeds] moves in both
  git init -q -b main "$W/two"; mkdir -p "$W/two/src"; seed_toml t.example/two 1.0.0 > "$W/two/tomato.toml"; printf 'export def two() -> int:\n    return 1\n' > "$W/two/src/two.tom"
  commit "$W/two" one >/dev/null; git -C "$W/two" tag v1; bare "$W/two" "$W/two.git"
  mkdir -p "$W/app2"; printf '%s' "$head" > "$W/app2/tomato.toml"
  (cd "$W/app2" && tm $t seed add --git "$W/two.git" --tag v1 >/dev/null 2>&1; tm $t seed add --git "$W/two.git" --tag v1 --test >/dev/null 2>&1)
  printf 'export def two() -> int:\n    return 2\n' > "$W/two/src/two.tom"; seed_toml t.example/two 1.0.1 > "$W/two/tomato.toml"
  TC2="$(commit "$W/two" two)"; git -C "$W/two" tag -f v1 >/dev/null 2>&1; bare "$W/two" "$W/two.git"
  (cd "$W/app2" && tm $t seed update >/dev/null 2>&1)
  check "seed update: a seed in [seeds] and [test-seeds] gets the new rev in both lines" "2 $TC2" "$(grep -c "rev = \"$TC2\", tag = \"v1\"" "$W/app2/tomato.toml") $(sed -n 's/^commit = "\(.*\)"/\1/p' "$W/app2/tomato.lock")"
  cd "$work" || true
}
t_cli_project() { # the project layout and the commands that use it (D94b): init, run, build, the built program, raw inputs, File inputs
  cli_setup
  noconf() { TOMATO_HOME="$work/uh" "$@"; }
  mkdir -p "$work/uh"; B="$work/proj"; mkdir -p "$B/hello"; cd "$B/hello" || return 1
  # ---- tomato init
  r="$(noconf $t init 2>&1)"
  check "init: says what it made" "created tomato.toml, src/main.tom, tests/example.tom and .gitignore
next: tomato run, tomato build, tomato test" "$r"
  check "init: the project's name is the folder's, the version 0.1.0, tomato the compiler's major and minor" '[project]
name = "hello"
version = "0.1.0"
tomato = "'"$(cat "$root/VERSION" | awk -F. '{ print $1 "." $2 }')"'"' "$(sed -n 1,4p tomato.toml)"
  check "init: .gitignore leaves builds/ out" "builds/" "$(cat .gitignore)"
  check "init: the layout" "src/main.tom tests/example.tom" "$(ls src/* tests/* | tr '\n' ' ' | sed 's/ $//')"
  check "init: the manifest passes tomato config" "project: hello 0.1.0 (needs Tomato $(cat "$root/VERSION" | awk -F. '{ print $1 "." $2 }') or newer)" "$(noconf $t config | tail -n 1)"
  r="$(noconf $t init 2>&1)"; rc=$?
  check "init: refuses to overwrite and names the files" "error: tomato init will not overwrite: tomato.toml, src/main.tom, tests/example.tom, .gitignore (nothing was written; move them away, or use another folder); an existing .gitignore needs the line builds/ added by hand
rc=1" "$r
rc=$rc"
  rm -f tests/example.tom
  check "init: one existing file is named, and the others are not written" "error: tomato init will not overwrite: tomato.toml, src/main.tom, .gitignore (nothing was written; move them away, or use another folder); an existing .gitignore needs the line builds/ added by hand $([ ! -e tests/example.tom ] && echo none-written)" "$(noconf $t init 2>&1 | tr '\n' ' ')$([ ! -e tests/example.tom ] && echo none-written)"
  mkdir -p "$B/named" && (cd "$B/named" && noconf $t init 'my "app"' >/dev/null 2>&1; check "init: NAME is the project's name, quoted in the file" 'name = "my \"app\""' "$(sed -n 2p tomato.toml)"; check "init: the example test passes" "" "$(noconf $t run tests/example.tom 2>&1)"; check "init: and the hello world runs" "hello, world" "$(noconf $t run 2>&1)")
  mkdir -p "$B/seedy" && (cd "$B/seedy" && noconf $t init --seed acme.example/thing-x >/dev/null 2>&1
    check "init --seed: a seed manifest, a module named for the seed, a test that imports it" "[seed] acme.example/thing-x src/thing_x.tom tests/example.tom" "$(sed -n 1p tomato.toml) $(sed -n 2p tomato.toml | sed 's/name = \"\(.*\)\"/\1/') $(ls src/* tests/* | tr '\n' ' ' | sed 's/ $//')"
    check "init --seed: the placeholders are there, and the seed passes tomato seed check up to the owner" "1" "$(grep -c 'TODO' tomato.toml | sed 's/^2$/1/')"
    check "init --seed: the example test runs" "" "$(noconf $t run tests/example.tom 2>&1)"
    check "init --seed: the default owner is a placeholder that seed check accepts as a name" "yourdomain.example/seedy" "$(mkdir -p ../seedy2 && cd ../seedy2 && noconf $t init --seed >/dev/null 2>&1; sed -n 2p tomato.toml | sed 's/name = \"\(.*\)\"/\1/' | sed 's/seedy2/seedy/')")
  mkdir -p "$B/bad" && (cd "$B/bad"
    check "init: a bad seed name is refused" "error: 'Bad' is not a seed name: write tomato init --seed owner/name (an owner is lowercase letters, digits, dots and hyphens, a name starts with a letter)" "$(noconf $t init --seed Bad 2>&1)"
    check "init: an unknown option is refused" "error: unknown option '--lib' for 'tomato init' (usage: tomato init [NAME] [--seed])" "$(noconf $t init --lib 2>&1)"
    check "init: two names are refused" "error: tomato init takes one NAME, not 'a' and 'b'" "$(noconf $t init a b 2>&1)"
    [ -z "$(ls -A)" ] && ok "init: a refused init writes nothing" || bad "init: a refused init writes nothing" "$(ls -A)")
  cd "$B/hello" || return 1
  # ---- run
  check "run: no word runs src/main.tom of the project" "hello, world" "$(noconf $t run 2>&1)"
  check "run: from a folder below the project" "hello, world" "$(cd tests && noconf $t run 2>&1)"
  cat > src/main.tom <<'EOF'
from util import twice

@main
def main(who: str = 'world', times: int = 1):
    for i in range(times):
        print('hello,', who)

@prime
def prime(n: int):
    print(n, twice(n))

@greet
def greet():
    print('group greet')

@greet.loud
def loud():
    print('LOUD')

@greet.quiet
def quiet():
    print('quiet')

@all
def all(*args: tuple[str]):
    print(len(args), args)

@lines
def lines(data: File):
    for l in data:
        print('>', l.strip())

@nums
def nums(a: int, b: int = 2):
    print(a + b)
EOF
  printf 'export def twice(n: int) -> int:\n    return n * 2\n' > src/util.tom
  check "run: an entry of src/main.tom and its inputs (a word with no .tom and no / is an entry)" "17 34" "$(noconf $t run prime 17 2>&1)"
  check "run: main's defaults, and main given its inputs" "hello, world
hello, bob
hello, bob" "$(noconf $t run 2>&1; noconf $t run main bob 2 2>&1)"
  check "run: a dotted entry, and the group of a dotted name" "LOUD
group greet
LOUD
quiet" "$(noconf $t run greet.loud 2>&1; noconf $t run greet 2>&1)"
  check "run: FILE ENTRY INPUTS is the full form" "17 34" "$(noconf $t run src/main.tom prime 17 2>&1)"
  check "run: everything after the entry is raw input, options included" "4 ('a', '--mode', 'release', '-o')" "$(noconf $t run all a --mode release -o 2>&1)"
  check "run: -- ends the options, and the next word is still the entry" "2 ('-x', '--mode')" "$(noconf $t run -- all -x --mode 2>&1)"
  check "run: an option before the entry is read, and the entry still runs" "17 34" "$(noconf $t run --mode debug prime 17 2>&1)"
  check "run: an option before the entry is read (--mode release makes the release error text)" "error E01:6" "$(printf '@main\ndef main():\n    half(0)\n\ndef half(n: int):\n    print(5 // n)\n' > src/zero.tom; noconf $t run --mode release src/zero.tom 2>&1)"
  check "run: an unknown option before the entry is refused" "error: unknown option '-x' for 'tomato run' (options go before the entry: the words after it are its inputs, read as they are; after -- no word is an option)" "$(noconf $t run -x 2>&1)"
  check "run: a second file word is refused with a hint" "error: 'src/util.tom' looks like a file, but the file is already src/main.tom: after it comes an entry name such as main (tomato run FILE [ENTRY [INPUTS...]])" "$(noconf $t run src/main.tom src/util.tom 2>&1)"
  r="$(noconf $t run nosuch 2>&1)"; case "$r" in "error[E"*"]: no function is marked @nosuch"*) ok "run: an entry that does not exist is a compile error";; *) bad "run: an entry that does not exist is a compile error" "$r";; esac
  check "run: an input that is not a number names its position" "1" "$(noconf $t run prime x 2>&1 | grep -c "input 1 must be a whole number, found 'x'")"
  check "run: too few inputs says that an input needs a default to be left out" "1" "$(noconf $t run nums 2>&1 | grep -c "takes 2 input(s), got 0 (an input can be left out only if it has a default")"
  # ---- File inputs
  printf 'one\ntwo\n' > in.txt
  check "File input: a file is opened for reading and closed after the entry" "> one
> two" "$(noconf $t run lines in.txt 2>&1)"
  check "File input: - is standard input" "> x
> y" "$(printf 'x\ny\n' | noconf $t run lines - 2>&1)"
  check "File input: a missing file stops with a message naming the input before the entry runs" "error[E592]: input 1 must be a file that can be read, but 'nofile.txt' cannot be opened: No such file or directory" "$(noconf $t run lines nofile.txt 2>&1 | head -n 1)"
  check "File input: a folder cannot be read either" "1" "$(noconf $t run lines src 2>&1 | grep -c "input 1 must be a file that can be read, but 'src' cannot be opened")"
  check "File input: no word for it is the usage error" "1" "$(noconf $t run lines 2>&1 | grep -c "takes 1 input(s), got 0")"
  printf '@main\ndef main(f: File = None):\n    print(1)\n' > src/dflt.tom
  r="$(noconf $t run src/dflt.tom 2>&1 | head -n 1)"
  case "$r" in "error[E"*"]: a File input cannot have a default"*|"error[E"*"]: "*) ok "File input: a default is refused at compile time";; *) bad "File input: a default is refused at compile time" "$r";; esac
  check "File input: and the message says why" "1" "$(noconf $t run src/dflt.tom 2>&1 | grep -c 'a File input cannot have a default')"
  # ---- build and the built program
  rm -f src/dflt.tom src/zero.tom
  check "build: no word builds src/main.tom into builds/NAME (the project's name)" "wrote builds/hello" "$(noconf $t build 2>&1)"
  check "builds/NAME: no word runs main" "hello, world" "$(builds/hello 2>&1)"
  check "builds/NAME: main with inputs, named" "hello, bob" "$(builds/hello main bob 2>&1)"
  check "builds/NAME: an entry and its inputs" "17 34" "$(builds/hello prime 17 2>&1)"
  check "builds/NAME: a dotted entry and a group" "LOUD
group greet
LOUD
quiet" "$(builds/hello greet.loud 2>&1; builds/hello greet 2>&1)"
  check "builds/NAME: raw inputs, options included" "3 ('a', '-b', '--mode')" "$(builds/hello all a -b --mode 2>&1)"
  check "builds/NAME: a File input from a file and from standard input" "> one
> two
> x" "$(builds/hello lines in.txt 2>&1; printf 'x\n' | builds/hello lines - 2>&1)"
  check "builds/NAME: a missing file stops first" "error[E592]: input 1 must be a file that can be read, but 'no.txt' cannot be opened: No such file or directory" "$(builds/hello lines no.txt 2>&1 | head -n 1)"
  check "builds/NAME: a first word that is no entry is an error that lists the entries" "error[E591]: this program has no entry '5' (its entries are: main, prime, greet, greet.loud, greet.quiet, all, lines, nums); the first word names the entry and its inputs follow it, as in: main INPUT..." "$(builds/hello 5 2>&1 | head -n 1)"
  check "builds/NAME: tests are not entries" "1" "$(printf '\n@test.x\ndef x():\n    assert True\n' >> src/main.tom; noconf $t build >/dev/null 2>&1; builds/hello test 2>&1 | grep -c "has no entry 'test'")"
  check "builds/NAME: sys.argv is the program and the inputs" "2 [x]" "$(printf '\nimport sys\n@argv\ndef argv(*a: tuple[str]):\n    print(len(sys.argv()), a)\n' >> src/main.tom; noconf $t build >/dev/null 2>&1; builds/hello argv x 2>&1 | sed 's/\[.*\]/[x]/' | sed 's/^2 .*/2 [x]/')"
  check "build --entry: a program with the one entry, taking just its inputs" "34" "$(noconf $t build --entry prime -o builds/p1 >/dev/null 2>&1 && builds/p1 17 2>&1 | sed 's/17 //')"
  check "build -o: wins over builds/NAME" "wrote other/prog" "$(mkdir -p other; noconf $t build -o other/prog 2>&1 | sed 's#^wrote .*other/prog#wrote other/prog#')"
  check "build FILE: builds/STEM for another file" "wrote builds/util_main" "$(printf '@main\ndef main():\n    print(7)\n' > src/util_main.tom; noconf $t build src/util_main.tom 2>&1)"
  check "build: ... and it runs" "7" "$(builds/util_main 2>&1)"
  check "build: a word that is no file is refused" "error: 'prime' is not a file: a file ends in .tom or has a / in it (tomato build [FILE]; with no FILE it is the project's src/main.tom)" "$(noconf $t build prime 2>&1)"
  check "build: [build] output of the manifest still applies (D92c)" "wrote $B/hello/out/app" "$(printf '[build]\noutput = "out/app"\n' >> tomato.toml; noconf $t build 2>&1)"
  check "build: ... and builds/ is then left alone" "no" "$(rm -rf builds; noconf $t build >/dev/null 2>&1; [ -e builds ] && echo yes || echo no)"
  sed -i '/^\[build\]/,$d' tomato.toml
  check "build: from a folder below the project, builds/ is the project's" "wrote $B/hello/builds/hello" "$(cd tests && noconf $t build 2>&1)"
  # ---- src/ is found from tests/
  printf 'from util import twice\n\n@main\ndef main():\n    assert twice(4) == 8\n    print("ok")\n' > tests/uses_src.tom
  check "src: a test in tests/ imports a module of src/" "ok" "$(noconf $t run tests/uses_src.tom 2>&1)"
  printf 'from util import twice\n\n@main\ndef main():\n    assert twice(4) == 9\n' > tests/fails.tom
  r="$(noconf $t run tests/fails.tom 2>&1)"; rc=$?
  check "src: a failing assert in a test is an error and a status of 1" "1 1" "$(echo "$r" | grep -c 'assert') $rc"
  printf 'import main\n\n@main\ndef main():\n    print(1)\n' > tests/imports_main.tom
  check "src: main cannot be imported, and the message says what to do" "1" "$(noconf $t run tests/imports_main.tom 2>&1 | grep -c "cannot import 'main'")"
  printf 'import nosuch\n\n@main\ndef main():\n    nosuch.f()\n' > tests/importer.tom
  check "src: the module that is not found lists the src folder among the places" "1" "$(noconf $t run tests/importer.tom 2>&1 | grep -c 'next to the program, in the src folder of the project and in the standard library')"
  printf 'from util import twice\n\n@main\ndef main():\n    print(twice("x"))\n' > tests/typo.tom
  check "src: an error in a module of src/ names src/util.tom" "1" "$(noconf $t run tests/typo.tom 2>&1 | grep -c -- '--> src/util.tom\|--> tests/typo.tom')"
  rm -f tests/fails.tom tests/imports_main.tom tests/importer.tom tests/typo.tom
  # the example project of the repository
  cp -R "$root/examples/project" "$work/exproj" && cd "$work/exproj" || return 1
  check "examples/project: tomato run is the usage line" "usage: tomato run count FILE    (a file, or - for standard input)" "$(noconf $t run 2>&1)"
  check "examples/project: an entry with a File input" "9" "$(noconf $t run count words.txt 2>&1)"
  check "examples/project: from standard input" "3" "$(printf 'a b c' | noconf $t run count - 2>&1)"
  check "examples/project: its test (a module of src/ imported from tests/) passes" "" "$(noconf $t run tests/test_words.tom 2>&1)"
  check "examples/project: built and run" "9" "$(noconf $t build >/dev/null 2>&1 && builds/wordcount count words.txt 2>&1)"
  cd "$B/hello" || return 1
  # ---- outside a project
  mkdir -p "$B/loose" && cd "$B/loose" || return 1
  printf '@main\ndef main():\n    print(3)\n' > a.tom
  check "run: no word and no project is an error that says what to do" "error: there is no tomato.toml in this folder or a parent folder, so there is no project's src/main.tom to run: name a file (tomato run FILE.tom), or start a project here with tomato init" "$(noconf $t run 2>&1)"
  check "build: no word and no project is the same error" "error: there is no tomato.toml in this folder or a parent folder, so there is no project's src/main.tom to build: name a file (tomato build FILE.tom), or start a project here with tomato init" "$(noconf $t build 2>&1)"
  check "build: a file outside a project goes to builds/ of the current folder" "wrote builds/a" "$(noconf $t build a.tom 2>&1)"
  check "build: ... and runs" "3" "$(builds/a)"
  mkdir -p "$B/empty/src" && cd "$B/empty" && printf '[project]\nname = "e"\nversion = "0.1.0"\ntomato = "0.51"\n' > tomato.toml
  check "run: a project with no src/main.tom says so" "error: the project in $B/empty has no src/main.tom (the program of a project is src/main.tom; tomato run FILE.tom runs another file)" "$(noconf $t run 2>&1)"
  # ---- a seed's hash leaves builds/ out
  mkdir -p "$B/sd/src" && cd "$B/sd" && printf '[seed]\nname = "acme.example/sd"\nversion = "1.0.0"\ntomato = "0.51"\n' > tomato.toml && printf 'export def f() -> int:\n    return 1\n' > src/sd.tom
  h1="$(noconf $t seed hash .)"; mkdir -p builds && printf 'x' > builds/prog; h2="$(noconf $t seed hash .)"
  check "seed hash: a top-level builds/ is not part of the seed" "$h1" "$h2"
  mkdir -p src/builds && printf 'y' > src/builds/z.tom; h3="$(noconf $t seed hash .)"
  [ "$h1" != "$h3" ] && ok "seed hash: a builds folder deeper down still counts" || bad "seed hash: a builds folder deeper down still counts"
  cd "$root" || return 1
}
t_manedit_logic() { # the text editor of tomato.toml behind `tomato seed add` and `remove` (compiler/src/manedit.tom): what it changes and what it leaves alone
  cli_setup
  mkdir -p "$work/me"; cp compiler/src/manedit.tom tests/manedit_logic.tom "$work/me/"
  r="$(cd "$work/me" && $t run manedit_logic.tom test 2>&1 | tail -n 1)"
  case "$r" in *" passed, 0 failed, 0 skipped") ok "manedit: the editor's rules: $r";; *) bad "manedit: the editor's rules" "$(cd "$work/me" && $t run manedit_logic.tom test 2>&1 | grep -v '^ok ' | head -12)";; esac
}
t_manifest_logic() { # the rules of compiler/src/manifest.tom as @test functions, and its version order against the shell's semver_cmp
  cli_setup
  mkdir -p "$work/ml"; cp compiler/src/manifest.tom compiler/src/config.tom tests/manifest_logic.tom "$work/ml/"
  r="$(cd "$work/ml" && $t run manifest_logic.tom test 2>&1 | tail -n 1)"
  case "$r" in *" passed, 0 failed, 0 skipped") ok "manifest: the reader's rules: $r";; *) bad "manifest: the reader's rules" "$(cd "$work/ml" && $t run manifest_logic.tom test 2>&1 | grep -v '^ok ' | head -12)";; esac
  # the order of versions: Tomato's compare_versions and the shell's semver_cmp give the same answer for every pair
  eval "$(sed -n '/^semver_cmp() {/,/^}/p' native/tomato)"
  list="0.9 0.51 0.51.0 1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0-rc.2 1.0.0-rc.10 1.0.0 1.0 1.0.1 1.0.10 1.0.9 1.1.0 2.0.0 10.0.0 1.0.0-0 1.0.0-1 1.0.0-x-y"
  want=""; pairs=""
  for a in $list; do for b in $list; do want="$want $(semver_cmp "$a" "$b")"; pairs="$pairs $a:$b"; done; done
  { printf 'from manifest import compare_versions\n@main\ndef main(*pairs: tuple[str]):\n    out: list[str] = []\n    for p in pairs:\n        w = p.split(":")\n        out.append(str(compare_versions(w[0], w[1])))\n    print(" ".join(out))\n'; } > "$work/ml/order.tom"
  got="$(cd "$work/ml" && $t run order.tom main $pairs 2>&1)"
  check "manifest: compare_versions agrees with native/tomato's semver_cmp on every pair" "${want# }" "$got"
}
t_cli_repl_1() {
  part="${1:-1}"; cli_setup
  if step 1; then
  check "glob and empty inputs survive" "[*][]" "$(cd "$work" && $t run echo.tom main '*' '')"
  check "-- passes flag-like inputs" "[-o][--entry]" "$($t run "$work/echo.tom" -- main -o --entry)"
  r="$(sh native/tomato update 2>&1)"; case "$r" in *"is not one (run ./install-native.sh in a checkout)"*) ok "update refuses to run from a checkout (it would replace its native/ folder)";; *) bad "update refuses to run from a checkout (it would replace its native/ folder)" "$r";; esac
  # an option at the end without its value is a usage error (it once took a word moved to the end as its value: `build f x -o` wrote x)
  check "an option at the end without its value is a usage error" "2 2 2 none" "$(cd "$work" && { $t run echo.tom --color > /dev/null 2>&1; a=$?; $t build echo.tom -o > /dev/null 2>&1; b=$?; $t test --filter > /dev/null 2>&1; c=$?; [ -e x ] && w=made || w=none; echo "$a $b $c $w"; })"
  check "repl: variables, functions, new output only" "7
9
hi" "$(printf 'x = 3\nx + 4\ndef sq(n: int) -> int:\n    return n * n\n\nsq(x)\nprint("hi")\n:quit\n' | $t repl)"
  fi; if step 2; then
  check "repl: std imports resolve (itertools, math)" "True
False" "$(printf 'from math import is_prime\nfrom itertools import progress_bar\nis_prime(97)\nis_prime(91)\n:quit\n' | $t repl 2>&1)"
  check "repl: an import of a missing name says so, with a suggestion and the names there are" "error[E226]: module 'itertools' has no 'progres_bar'
 --> repl:1:6
  |
1 | from itertools import progres_bar
  |      ^^^^^^^^^
  = help: did you mean 'progress_bar'?
  = help: module 'itertools' exports: progress_bar, permutations, combinations, combinations_with_replacement, product, product_repeat, accumulate, chain, pairwise, batched, repeat" "$(printf 'from itertools import progres_bar\n:quit\n' | $t repl 2>&1)"
  check "repl: an import of a missing module suggests one and lists the standard modules" "error[E183]: cannot find the module 'itertoolz'
 --> repl:1:8
  |
1 | import itertoolz
  |        ^^^^^^^^^
  = help: did you mean 'itertools'?
  = help: looked for itertoolz.tom next to the program and in the standard library
  = help: standard modules: $(ls std/*.tom std/builtin/bitarray.tom | sed 's#.*/##; s#\.tom$##' | sort | paste -sd, - | sed 's/,/, /g')" "$(printf 'import itertoolz\n:quit\n' | $t repl 2>&1)"
  check "repl: an import alone is accepted, and a later line uses it" "ok
2" "$(printf 'import datetime\nfrom itertools import progress_bar\nprint("ok")\nfrom math import isqrt\nisqrt(5)\n:quit\n' | $t repl 2>&1)"
  check "repl: :load runs a program that has its own @main" "$(cat tests/expected/shapes.main.out)" "$(printf ':load examples/shapes.tom\n:quit\n' | $t repl)"
  check "repl: a block, then a failing line, then a good one" "9
error[E190]: cannot use '+' with int and str
5" "$(printf 'def sq(n: int) -> int:\n    return n * n\n\nsq(3)\nprint(1 + "a")\nsq(2) + 1\n:quit\n' | $t repl 2>&1 | grep -E '^(9|5|error\[)')"
  fi; if step 3; then
  check "repl: a misspelled name says so, with the line and a suggestion" "error[E227]: name 'tets' is not defined
 --> repl:1:1
  |
1 | tets
  | ^^^^
  = help: did you mean 'test'?" "$(printf 'def test(n: int) -> int:\n    return n\n\ntets\n:quit\n' | $t repl 2>&1)"
  check "repl: lists print like Python" "[2, 3, 5]
[3, 4]" "$(printf 'primes = [2, 3, 5]\nprimes\nlist(range(1, 6))[2:4]\n:quit\n' | $t repl 2>&1)"
  check "repl: print(range(100)) shows start, stop and step" "range(0, 100, 1)
range(1, 100, 1)
range(0, 5, 1)" "$(printf 'print(range(100))\nx = range(1, 100)\nx\nrange(5)\n:quit\n' | $t repl 2>&1)"
  fi
}
t_cli_color() {
  part="${1:-1}"; cli_setup
  if step 1; then
  check "tomato run prints a range as range(start, stop, step)" "range(0, 100, 1)
range(1, 100, 1)
range(5, 10, 2)" "$($t run "$work/rangeprint.tom" 2>&1)"
  check "tomato run shows the same error text" "error[E227]: name 'tets' is not defined
 --> $work/typo.tom:3:11" "$($t run "$work/typo.tom" 2>&1 | head -2)"
  check "an uncaught error shows the call trace, innermost first" "error[E01]: division by zero
  at half (line 6)
  at main (line 3)" "$($t run "$work/trace.tom" 2>&1)"
  check "an error the program raises shows where, then the trace" "error: Error: bad (raised on line 3)
  at main (line 3)" "$($t run "$work/raised.tom" 2>&1)"
  fi; if step 2; then
  check "--color=always paints a runtime error and its trace" "^[[1;31merror[E01]:^[[0m ^[[1mdivision by zero^[[0m
^[[2m  at half (line 6)^[[0m
^[[2m  at main (line 3)^[[0m" "$($t run "$work/trace.tom" --color=always 2>&1 | cat -v)"
  check "--color=never keeps the plain words" "error[E01]: division by zero
  at half (line 6)
  at main (line 3)" "$($t run "$work/trace.tom" --color=never 2>&1 | cat -v)"
  check "TOMATO_COLOR=always works like the flag" "^[[1;31merror[E01]:^[[0m ^[[1mdivision by zero^[[0m" "$(TOMATO_COLOR=always $t run "$work/trace.tom" 2>&1 | cat -v | head -1)"
  fi; if step 3; then
  check "without a terminal the color stays off (and NO_COLOR keeps it off)" "error[E01]: division by zero" "$(NO_COLOR=1 $t run "$work/trace.tom" 2>&1 | head -1)"
  check "a bad --color value is refused" "error: --color takes auto, always or never, not 'blue'" "$($t run "$work/trace.tom" --color=blue 2>&1)"
  check "--color=always paints a compile error: label, location, gutter, caret" "^[[1;31merror[E227]:^[[0m ^[[1mname 'tets' is not defined^[[0m
 ^[[1;34m-->^[[0m ^[[36m$work/typo.tom:3:11^[[0m
^[[1;34m  |^[[0m
^[[1;34m3 |^[[0m     print(tets)
^[[1;34m  |^[[0m           ^[[1;31m^^^^^[[0m" "$($t run "$work/typo.tom" --color=always 2>&1 | cat -v)"
  fi
}
t_cli_warnings() {
  part="${1:-1}"; cli_setup
  if step 1; then
  check "a warning is shown, then the program runs" "warning: the variable 'unused' is given a value that is never used
 --> $work/warn.tom:3:5
  |
3 |     unused = 1
  |     ^^^^^^
  = help: remove it, or rename it '_unused' to show that this is intended
2" "$($t run "$work/warn.tom" 2>&1)"
  check "--no-warnings hides warnings" "2" "$($t run "$work/warn.tom" --no-warnings 2>&1)"
  check "a warning is yellow with --color=always" "^[[1;33mwarning:^[[0m ^[[1mthe variable 'unused' is given a value that is never used^[[0m" "$($t run "$work/warn.tom" --color=always 2>&1 | cat -v | head -1)"
  check "compile prints the IR without the warning comments" "0" "$($t compile "$work/warn.tom" 2>/dev/null | grep -c '^;! ')"
  fi; if step 2; then
  check "repl: warnings are not shown" "3" "$(printf 'unused = 1\nprint(3)\n:quit\n' | $t repl 2>&1)"
  check "repl: --color=always paints the label red" "^[[1;31merror[E190]:^[[0m ^[[1mcannot use '+' with int and str^[[0m" "$(printf 'print(1 + "a")\n:quit\n' | $t repl --color=always 2>&1 | cat -v | head -1)"
  check "repl: a runtime error shows no call trace of the generated program" "error[E01]: division by zero" "$(printf 'x = 0\nprint(1 // x)\n:quit\n' | $t repl 2>&1)"
  fi
}
t_cli_repl_2() {
  part="${1:-1}"; cli_setup
  if step 1; then
  check "repl: == is a comparison, = is an assignment" "False
3" "$(printf 'x = 3\nx == 4\nx\n:quit\n' | $t repl)"
  case "$(printf ':help\n:quit\n' | $t repl 2>&1)" in *":reset"*":quit"*) ok "repl: :help lists every command";; *) bad "repl: :help lists every command";; esac
  r="$(printf 'from nosuch_mod import a\n:quit\n' | $t repl 2>&1)"; case "$r" in *"Could not open"*|*"${TMPDIR:-/tmp}/"*|*"/var/folders/"*) bad "repl: a missing module shows no temp path or tool noise" "$r";; *"nosuch_mod"*) ok "repl: a missing module shows no temp path or tool noise";; *) bad "repl: a missing module shows no temp path or tool noise" "$r";; esac
  fi; if step 2; then
  check "repl: += works" "8" "$(printf 'x = 5\nx += 3\nx\n:quit\n' | $t repl)"
  check "repl: input asks once, then the answer is replayed" "Name? Ann
hi Ann
Ann" "$(printf "name = await input('Name? ')\nAnn\nprint('hi', name)\nprint(name)\n:quit\n" | $t repl)"
  check "repl: async functions and start work" "3
6" "$(printf "async def f(x: int) -> int:\n    return x + 1\n\nprint(await f(2))\nt = start f(5)\nprint(await t)\n:quit\n" | $t repl)"
  fi; if step 3; then
  check "repl: input works without the fast path too" "Name? Ann
hi Ann" "$(printf "name = await input('Name? ')\nAnn\nprint('hi', name)\n:quit\n" | TOMATO_JSC=/nonexistent $t repl)"
  check "tomato run reads standard input" "Name? How many? hi Ann 6" "$(printf 'Ann\n3\n' | $t run tests/input/ask_and_status.tom 2>&1 | head -1)"
  check "repl: leave() leaves" "a" "$(printf "print('a')\nleave()\nprint('b')\n" | $t repl)"
  fi
}
t_cli_repl_redef() {   # a function, class or interface defined again replaces the earlier one (it was E120 "defined twice")
  cli_setup
  P1='class P:\n    x: int\n    @init\n    def make(self, x: int):\n        self.x = x\n\n'
  P2='class P:\n    x: int\n    y: int\n    @init\n    def make(self, x: int, y: int):\n        self.x = x\n        self.y = y\n\n'
  P3='class P:\n    x: int\n    @init\n    def make(self, x: int):\n        self.x = x * 2\n    def get(self) -> int:\n        return self.x\n\n'
  check "repl: a function defined again replaces the earlier one, and shows no output of its own" "1
2
3" "$(printf 'def f() -> int:\n    return 1\n\nprint(f())\ndef f() -> int:\n    return 2\n\nprint(f())\nf() + 1\n:quit\n' | $t repl 2>&1)"
  check "repl: a class defined again: the object an earlier line made is built by the new class, and the old output is not shown again" "5
10" "$(printf "${P1}p = P(5)\nprint(p.x)\n${P3}p.get()\n:quit\n" | $t repl 2>&1)"
  check "repl: a definition that calls a redefined function uses the new one" "4" "$(printf 'def one() -> int:\n    return 1\n\ndef two() -> int:\n    return one()\n\ndef one() -> int:\n    return 4\n\ntwo()\n:quit\n' | $t repl 2>&1)"
  check "repl: a redefinition an earlier line does not fit is refused at that line, with a hint, and the old one stays" "error[E128]: 'P' takes 2 arguments, but 1 given
 --> session:1:5
  |
1 | p = P(5)
  |     ^
hint: the earlier lines of the session run again with the new P, and one of them does not work with it; the earlier definition is kept
5" "$(printf "${P1}p = P(5)\n${P2}p.x\n:quit\n" | $t repl 2>&1)"
  check "repl: a refused redeclaration of a variable keeps the old variable and its value" "error[E324]: the value has type str, but int is expected
 --> repl:1:1
  |
1 | x: int = \"a\"
  | ^^^^^^^^^^^^
2
@main
def tomato_repl_main():
    x: int = 1
    print(x + 1)" "$(printf 'x: int = 1\nx: int = "a"\nx + 1\n:program\n:quit\n' | $t repl 2>&1)"
  check "repl: a redeclared variable takes the place of the old one, so an earlier line that used it runs with the new value" "1
2
@main
def tomato_repl_main():
    x: int = 2
    print(x)
    print(x)" "$(printf 'x: int = 1\nprint(x)\nx: int = 2\nprint(x)\n:program\n:quit\n' | $t repl 2>&1)"
  check "repl: a variable redeclared with another type, with every earlier line fitting it" "1
2.5
@main
def tomato_repl_main():
    x: float = 2.5
    print(x)
    print(x)" "$(printf 'x: int = 1\nprint(x)\nx: float = 2.5\nx\n:program\n:quit\n' | $t repl 2>&1)"
  check "repl: a redeclaration an earlier line does not fit is refused at that line, with a hint, and the old variable and its value stay" "error[E190]: cannot use '+' with str and int
 --> session:2:7
  |
2 | y = x + 1
  |       ^
hint: the earlier lines of the session run again with the new declaration of x, and one of them does not work with it; the earlier declaration is kept
2" "$(printf 'x: int = 1\ny = x + 1\nx: str = "a"\ny\n:quit\n' | $t repl 2>&1)"
  printf 'x: int = 3\nprint(x + 1)\n' > "$work/v2.tom"
  check "repl: a variable redeclared from one declared after it is put at the end of the session instead" "20" "$(printf 'x: int = 1\ny: int = 2\nx: int = y * 10\nx\n:quit\n' | $t repl 2>&1)"
  check "repl: a piece that redeclares a variable and has statements shows only the output of the statements after it" "1
4" "$(printf 'x: int = 1\nprint(x)\n:load %s\n:quit\n' "$work/v2.tom" | $t repl 2>&1)"
  check "repl: after a refused redefinition :program still has the old definition" "1
def f(n: int) -> int:
    return n
@main
def tomato_repl_main():
    print(f(1))" "$(printf 'def f(n: int) -> int:\n    return n\n\nprint(f(1))\ndef f(n: int, m: int) -> int:\n    return n\n\n:program\n:quit\n' | $t repl 2>/dev/null | sed '/^$/d')"
  check "repl: a function that now fails at run time is refused too" "2
error[E01]: division by zero
hint: the earlier lines of the session run again with the new f, and one of them does not work with it; the earlier definition is kept" "$(printf 'def f(n: int) -> int:\n    return 10 // n\n\nprint(f(5))\ndef f(n: int) -> int:\n    return 10 // (n - 5)\n\n:quit\n' | $t repl 2>&1)"
  printf 'def f() -> int:\n    return 1\n\ndef f() -> int:\n    return 2\n' > "$work/twice.tom"
  check "repl: a name defined twice in one piece is still an error" "error[E120]: 'f' is defined twice in module 'main'" "$(printf ':load %s\n:quit\n' "$work/twice.tom" | $t repl 2>&1 | head -1)"
  printf 'def f() -> int:\n    return 2\n\nprint(f())\n' > "$work/mixed.tom"
  check "repl: a piece with a redefinition and statements shows only its statements" "1
2" "$(printf 'def f() -> int:\n    return 1\n\nprint(f())\n:load %s\n:quit\n' "$work/mixed.tom" | $t repl 2>&1)"
  check "repl: :program holds one definition of a redefined name, and my_f is not f" "def my_f() -> int:
    return 5

def f() -> int:
    return 2" "$(printf 'def my_f() -> int:\n    return 5\n\ndef f() -> int:\n    return 1\n\ndef f() -> int:\n    return 2\n\n:program\n:quit\n' | $t repl 2>&1 | sed -n '1,5p')"
  printf 'def g() -> int:\n    return 1\n' > "$work/g1.tom"; printf 'def g() -> int:\n    return 9\n' > "$work/g2.tom"
  check "repl: :load of a changed file replaces its definitions" "1
9" "$(printf ':load %s\nprint(g())\n:load %s\nprint(g())\n:quit\n' "$work/g1.tom" "$work/g2.tom" | $t repl 2>&1)"
}
t_cli_repl_history() {   # the pty session is slow (it compiles after each line): it is its own job, so it does not hold up the others
  cli_setup
  # the line editor install-native.sh built: the pty test fails (it never skips) when it is missing, so a helper that stops building is seen
  edit="$home/native/bin/tomato-repl-edit"
  if ! command -v expect >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "repl pty test" "expect is required in CI" || echo "skip: expect is not installed, so the repl pty test did not run"
    return
  fi
  check "repl: the line editor on a pty (recall and edit a block, Ctrl-C, paste, UTF-8, resize, the history file, the fallbacks)" "ok" \
    "$(PATH="$(dirname "$t"):$PATH" TOMATO_REPL_EDIT="$edit" expect tests/repl_history.exp 2>&1 | tail -1)"
}
t_progress_streams() { # progress_bar never opens /dev/stderr: plain lines on a pipe, nothing breaks with stderr closed, stdout stays clean
  cli_setup
  cat > "$work/pb.tom" <<'EOT'
from itertools import progress_bar
@main
def main():
    for i in progress_bar(range(1, 21), 'p', 10):
        if i % 10 == 0:
            print(i)
EOT
  $t build "$work/pb.tom" -o "$work/pb" > "$work/e" 2>&1 || { bad "progress_bar streams: build" "$(head -5 "$work/e")"; return; }
  check "progress_bar: stdout holds only the program's output (stderr to a file)" "10
20" "$("$work/pb" 2> "$work/err")"
  check "progress_bar: stderr to a pipe gets plain lines, no carriage returns" "p:   5%|#| 1/20
p:  10%|#| 2/20
p:  20%|#| 4/20" "$("$work/pb" 2>&1 > /dev/null | head -3 | sed 's/|[#-]*|/|#|/')"
  check "progress_bar: no carriage return on a pipe" "0" "$("$work/pb" 2>&1 > /dev/null | grep -c "$(printf '\r')")"
  check "progress_bar: the last line is the finished bar" "p: 100%|##########| 20/20" "$(cat "$work/err" | tail -1)"
  "$work/pb" 2>&- > "$work/o"; rc=$?
  check "progress_bar: stderr closed does not fail the program" "0 10 20" "$rc $(tr '\n' ' ' < "$work/o" | sed 's/ $//')"
  "$work/pb" 2>/dev/full > "$work/o"; rc=$?
  check "progress_bar: stderr that cannot be written does not fail the program" "0" "$rc"
}
t_repl_progress() { # tomato repl on a pseudo-terminal shows the bar on the terminal
  cli_setup
  if ! command -v expect >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "repl progress test" "expect is required in CI" || echo "skip: expect is not installed, so the repl progress test did not run"
    return
  fi
  check "repl: a progress bar draws on the terminal and the loop output follows" "ok" "$(PATH="$(dirname "$t"):$PATH" expect tests/repl_progress.exp 2>&1 | tail -1)"
}
spawn_cli t_progress_streams
spawn_cli t_repl_progress
t_lineedit_logic() { # std/lineedit.tom without a terminal (Buffer, History, layout, frames, whole sessions on a FakeTerminal), debug and release
  cli_setup
  for mode in debug release; do
    r="$($t run --mode $mode tests/lineedit_logic.tom test 2>&1 | tail -1)"
    case "$r" in *" passed, 0 failed, 0 skipped") ok "lineedit: the @test functions pass ($mode mode): $r";; *) bad "lineedit: the @test functions pass ($mode mode)" "$($t run --mode $mode tests/lineedit_logic.tom test 2>&1 | grep -v '^ok ' | head -12)";; esac
  done
}
t_todo_shell_logic() { # the worked example examples/todo_shell.tom: its commands, its Completer and whole shell sessions on a FakeTerminal, debug and release (the files are copied together: the test imports the example from beside it)
  cli_setup
  cp examples/todo_shell.tom tests/todo_shell_logic.tom "$work/"
  for mode in debug release; do
    r="$($t run --mode $mode "$work/todo_shell_logic.tom" test 2>&1 | tail -1)"
    case "$r" in *" passed, 0 failed, 0 skipped") ok "todo_shell example: the @test functions pass ($mode mode): $r";; *) bad "todo_shell example: the @test functions pass ($mode mode)" "$($t run --mode $mode "$work/todo_shell_logic.tom" test 2>&1 | grep -v '^ok ' | head -12)";; esac
  done
  check "todo_shell example: piped input runs the commands" "todo shell: add, done, undo, rm, list, clear, help, quit
added 1: milk
  1 [ ] milk
1 is done: milk
bye" "$(printf 'add milk\nlist\ndone 1\nquit\nadd never\n' | $t run examples/todo_shell.tom 2>&1)"
}
t_todo_shell_pty() { # the worked example run with `tomato run` on a pty: Tab, the list of candidates, history, paste, Ctrl-D, and the terminal's settings the same afterwards
  cli_setup
  if ! command -v expect >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "todo_shell pty test" "expect is required in CI" || echo "skip: expect is not installed, so the todo_shell pty test did not run"
    return
  fi
  check "todo_shell example: completion, history and paste on a pty" "ok" "$(PATH="$(dirname "$t"):$PATH" expect tests/todo_shell_pty.exp 2>&1 | tail -1)"
}
t_std_sheets() { # every name that std/terminal.tom and std/lineedit.tom export is in its API sheet (docs/terminal-api.md, docs/lineedit-api.md)
  for m in terminal lineedit; do
    missing=""
    for n in $(grep -E '^export (def|class|interface|const) ' "std/$m.tom" | sed -E 's/^export (def|class|interface|const) ([A-Za-z_0-9]+).*/\2/'); do
      grep -qw -- "$n" "docs/$m-api.md" || missing="$missing $n"
    done
    [ -z "$missing" ] && ok "docs/$m-api.md names everything std/$m.tom exports" || bad "docs/$m-api.md names everything std/$m.tom exports" "missing from the sheet:$missing"
  done
}
t_lexer_spans() { # lex_spans in compiler/src/lexer.tom: never raises, covers the text, agrees with lex over every .tom file and every prefix of some lines (the files are copied together, the repository is the current folder)
  cli_setup
  cp compiler/src/lexer.tom tests/lexer_spans.tom "$work/"
  r="$($t run "$work/lexer_spans.tom" test 2>&1 | tail -1)"
  case "$r" in *" passed, 0 failed, 0 skipped") ok "lexer: lex_spans is tolerant and agrees with lex: $r";; *) bad "lexer: lex_spans is tolerant and agrees with lex" "$($t run "$work/lexer_spans.tom" test 2>&1 | grep -v '^ok ' | head -12)";; esac
}
t_repledit_logic() { # the repl's rules in compiler/src/repledit.tom (it imports the lexer beside it, so the files are copied together, as the installer does)
  cli_setup
  cp compiler/src/repledit.tom compiler/src/lexer.tom compiler/src/hltomato.tom tests/repledit_logic.tom "$work/"
  r="$($t run "$work/repledit_logic.tom" test 2>&1 | tail -1)"
  case "$r" in *" passed, 0 failed, 0 skipped") ok "repl editor: the validator, the indenter and the history rules: $r";; *) bad "repl editor: the validator, the indenter and the history rules" "$($t run "$work/repledit_logic.tom" test 2>&1 | grep -v '^ok ' | head -12)";; esac
  cp tests/hltomato_logic.tom "$work/"
  r="$($t run "$work/hltomato_logic.tom" test 2>&1 | tail -1)"
  case "$r" in *" passed, 0 failed, 0 skipped") ok "repl editor: the highlighter and the palette: $r";; *) bad "repl editor: the highlighter and the palette" "$($t run "$work/hltomato_logic.tom" test 2>&1 | grep -v '^ok ' | head -12)";; esac
  check "install-native.sh built the repl line editor" "yes" "$([ -x "$home/native/bin/tomato-repl-edit" ] && echo yes || echo no)"
  # standard input that is not a terminal never uses the editor, even when one is named (this one would fail)
  printf '#!/bin/sh\necho used >&2; exit 1\n' > "$work/bad-edit"; chmod +x "$work/bad-edit"
  check "repl: piped input does not use the line editor" "3" "$(printf 'print(3)\n:quit\n' | TOMATO_REPL_EDIT="$work/bad-edit" $t repl 2>&1)"
}
# tomato update: a fake release, checksum failures and non-official URLs. It changes the installed command, so it has one of its own.
t_cli_update() {
  # The installed command this test starts from is the `tomato` script, its cache helper and a VERSION, laid out as install-native.sh
  # lays them out (a link in bin/ to native/bin/tomato): `tomato update` does not use the compiler it replaces, and the real install
  # (half a minute of compiling the compiler) is the one the update itself makes, from the release archive built below.
  await_object || { bad "update installs a verified release" "the bootstrap object never came"; return 1; }
  TOMATO_TEST_BOOTSTRAP_OBJECT="$shared/c0.o"; export TOMATO_TEST_BOOTSTRAP_OBJECT
  home="$work/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"; t="$home/bin/tomato"
  mkdir -p "$home/native/bin" "$home/bin"; cp native/tomato native/rtcache.sh "$home/native/bin/"; chmod +x "$home/native/bin/tomato"
  cp VERSION "$home/native/VERSION"; ln -s "$home/native/bin/tomato" "$t"
  fake="$work/fake"; mkdir -p "$fake"; cp VERSION "$fake/VERSION.old"
  TOMATO_RELEASE_OUT="$fake/out" sh release/build.sh "file://$fake/t.tar.gz" > /dev/null && cp "$fake"/out/tomato-*.tar.gz "$fake/t.tar.gz"
  want="$(sha256 "$fake/t.tar.gz" | cut -d' ' -f1)"
  # the update's install reuses the object above, so check separately that the archive ships the parallel build and that it splits
  mkdir -p "$fake/unpacked" && tar -xzf "$fake/t.tar.gz" -C "$fake/unpacked" && b="$(echo "$fake"/unpacked/tomato-*/compiler/bootstrap)" && mkdir -p "$fake/parts" \
    && cmp -s "$b/build-object.sh" compiler/bootstrap/build-object.sh && cmp -s "$b/split.awk" compiler/bootstrap/split.awk \
    && awk -v parts=8 -v dir="$fake/parts" -f "$b/split.awk" "$b/tomatoc.ll" "$b/tomatoc.ll" && [ -s "$fake/parts/part7.ll" ] \
    && ok "the release archive ships the parallel bootstrap build" || bad "the release archive ships the parallel bootstrap build"
  echo 0.0 > "$home/native/VERSION"
  printf '{"version":"%s","url":"file://%s/t.tar.gz","sha256":"%s"}' "$(cat VERSION)" "$fake" "$want" > "$fake/ok.json"
  printf '{"version":"%s","url":"file://%s/t.tar.gz"}' "$(cat VERSION)" "$fake" > "$fake/nosum.json"
  printf '{"version":"%s","url":"file://%s/t.tar.gz","sha256":"%s"}' "$(cat VERSION)" "$fake" "0000000000000000000000000000000000000000000000000000000000000000" > "$fake/badsum.json"
  r="$(TOMATO_UPDATE_URL=file://$fake/nosum.json TOMATO_UPDATE_ALLOW_ANY_URL=1 $t update 2>&1)"; case "$r" in *"no valid sha256"*) ok "update refuses a manifest without a checksum";; *) bad "update refuses a manifest without a checksum" "$r";; esac
  r="$(TOMATO_UPDATE_URL=file://$fake/badsum.json TOMATO_UPDATE_ALLOW_ANY_URL=1 $t update 2>&1)"; case "$r" in *"does not match its checksum"*) ok "update refuses a wrong checksum";; *) bad "update refuses a wrong checksum" "$r";; esac
  r="$(TOMATO_UPDATE_URL=file://$fake/ok.json TOMATO_UPDATE_ALLOW_FILE=1 $t update 2>&1)"; case "$r" in *"not an official release URL"*) ok "update refuses a non-official URL";; *) bad "update refuses a non-official URL" "$r";; esac
  TOMATO_UPDATE_URL=file://$fake/ok.json TOMATO_UPDATE_ALLOW_ANY_URL=1 $t update > /dev/null 2>&1
  r="$(TOMATO_UPDATE_URL=file:///nonexistent.json TOMATO_UPDATE_FALLBACK=file://$fake/ok.json TOMATO_UPDATE_ALLOW_ANY_URL=1 $t update 2>&1)"; case "$r" in *"is the latest"*|*"installed"*|*"updating"*) ok "update falls back to the release manifest";; *) bad "update falls back to the release manifest" "$r";; esac
  r="$(TOMATO_UPDATE_URL=file://$fake/ok.json TOMATO_UPDATE_FALLBACK=file://$fake/ok.json $t update 2>&1)"; case "$r" in *"cannot read"*) ok "update refuses non-https sources";; *) bad "update refuses non-https sources" "$r";; esac
  check "update installs a verified release" "Tomato v$(cat VERSION) (compiler written in Tomato)" "$($t version)"
  printf '{"version":"0.0.1","url":"file://%s/t.tar.gz","sha256":"%s"}' "$fake" "$want" > "$fake/old.json"
  r="$(TOMATO_UPDATE_URL=file://$fake/old.json TOMATO_UPDATE_ALLOW_ANY_URL=1 $t update 2>&1)"; case "$r" in *"is the latest"*) ok "update never downgrades";; *) bad "update never downgrades" "$r";; esac
  manifest_sum="$(sed -n 's/.*"sha256" *: *"\([^"]*\)".*/\1/p' "$fake/out/latest.json")"
  check "release manifest names its own archive's checksum" "$(sha256 "$fake/out/tomato-$(cat VERSION).tar.gz" | cut -d' ' -f1)" "$manifest_sum"
}
t_cli_update_versions() { # tomato update: SemVer order (old 0.NN numbers too), the pre-release channel and the gate for a new minor version
  h="$work/h"; mkdir -p "$h/bin"; cp native/tomato native/rtcache.sh "$h/bin/"; chmod +x "$h/bin/tomato"
  upd() { # HAVE STABLE PRE [FLAGS]: what update does: same, minor (stops at the gate) or the version it starts to install
    echo "$1" > "$h/VERSION"; sum="$(printf '%064d' 0)"
    printf '{"version":"%s","url":"file:///nonexistent_dir_for_tomato/t.tar.gz","sha256":"%s"}' "$2" "$sum" > "$work/m.json"
    if [ -n "$3" ]; then printf '{"version":"%s","url":"file:///nonexistent_dir_for_tomato/p.tar.gz","sha256":"%s"}' "$3" "$sum" > "$work/p.json"; else rm -f "$work/p.json"; fi
    have="$1"; shift 3
    r="$(TOMATO_UPDATE_URL="file://$work/m.json" TOMATO_UPDATE_PRE_URL="file://$work/p.json" TOMATO_UPDATE_ALLOW_ANY_URL=1 "$h/bin/tomato" update "$@" 2>&1)"
    case "$r" in *"is the latest"*) echo same ;; *"update --minor"*) echo minor ;; *"updating v$have -> v"*) echo "$r" | sed -n 's/.*-> v//p' | head -1 ;; *) echo "? $r" ;; esac
  }
  got=""; for pair in 0.51:1.0.0 0.9:0.51 1.0.9:1.0.10 1.0.0:1.0.0 1.0.0:0.52 1.0.10:1.0.9 2.0.0:1.99.99 1.0.0:1.0 1.0.0-rc.1:1.0.0 1.0.0:1.0.0-rc.1; do
    got="$got $(upd "${pair%%:*}" "${pair#*:}" "")"; done
  check "update orders versions by number, part by part, a pre-release below its release" " 1.0.0 0.51 1.0.10 same same same same same 1.0.0 same" "$got"
  check "update: a new minor or major version needs --minor; patches install at once" "minor minor 1.1.0 2.0.0 1.0.3" "$(upd 1.0.2 1.1.0 "") $(upd 1.4.0 2.0.0 "") $(upd 1.0.2 1.1.0 "" --minor) $(upd 1.9.0 2.0.0 "" --minor) $(upd 1.0.2 1.0.3 "")"
  check "update: a stable install gets a pre-release only with --pre" "1.0.1 1.0.1-rc.1 1.0.1" "$(upd 1.0.0 1.0.1 1.0.2-rc.1) $(upd 1.0.0 1.0.0 1.0.1-rc.1 --pre) $(upd 1.0.0 1.0.1 1.0.1-rc.1 --pre)"
  r="$(upd 1.0.0 1.0.0 1.1.0-rc.1 --pre) $(TOMATO_UPDATE_URL="file://$work/m.json" TOMATO_UPDATE_PRE_URL="file://$work/p.json" TOMATO_UPDATE_ALLOW_ANY_URL=1 "$h/bin/tomato" update --pre 2>&1 | grep -c 'tomato update --minor --pre$') $(upd 1.0.0 1.0.0 1.1.0-rc.1 --pre --minor)"
  check "update: the gate's hint for a new minor pre-release keeps --pre, and that command installs it" "minor 1 1.1.0-rc.1" "$r"
  check "update: a pre-release install gets a later pre-release or the release" "1.0.0-rc.10 1.0.0 same 1.0.0-beta" "$(upd 1.0.0-rc.2 0.51 1.0.0-rc.10) $(upd 1.0.0-rc.10 1.0.0 1.0.0-rc.10) $(upd 1.0.0-rc.1 0.51 1.0.0-beta.9) $(upd 1.0.0-alpha.1 0.51 1.0.0-beta)"
  check "update: tomato and release.sh share one SemVer comparison" "$(sed -n '/^semver_cmp() {/,/^}/p' native/tomato)" "$(sed -n '/^semver_cmp() {/,/^}/p' release/release.sh)"
}
# The install is replaced as a whole and nothing is left behind when a command is stopped. These tests run the real install-native.sh,
# native/tomato (update, run) and use stand-ins for clang, curl and mv (and a stand-in compiler) on the PATH, so no compile happens: a
# stand-in hangs at the phase a test names, the test sends it Ctrl-C (SIGINT to the whole session, as a terminal does, to a command that
# was not started in the background), SIGTERM or SIGHUP, and checks the old install and the folders afterwards.
atomic_setup() { # sets $th (a TOMATO_HOME with an old install), $shim and $tmpd
  th="$work/h"; shim="$work/shim"; tmpd="$work/tmp"; rm -rf "$th" "$tmpd"; mkdir -p "$th/native/bin" "$th/native/std" "$work/b" "$tmpd" "$shim"
  echo OLD > "$th/native/VERSION"; echo old > "$th/native/std/old.tom"; echo old > "$th/native/bin/tomatoc"
  [ -f "$shim/clang" ] && return 0
  cat > "$shim/clang" <<'SH'
#!/bin/sh
# stand-in clang: writes an empty object or a small program to the -o file; stops (after saving its pid) when an argument list matches $FAKE_HANG
out=""; prev=""; for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
[ -n "$out" ] || exit 0
case "$*" in *${FAKE_HANG:-@no-such-phase@}*) echo "$$" > "$FAKE_MARK"; exec sleep 60 ;; esac
case "$*" in *" -c "*) echo object > "$out" ;; *) printf '%s\n' "#!/bin/sh" "${FAKE_PROGRAM:-echo program}" > "$out"; chmod +x "$out" ;; esac
SH
  cat > "$shim/curl" <<'SH'
#!/bin/sh
# stand-in curl: the real one, except that the archive download stops when $FAKE_HANG is set to download
case "$*" in *.tar.gz*) [ "${FAKE_HANG:-}" = download ] && { echo "$$" > "$FAKE_MARK"; exec sleep 60; } ;; esac
exec env PATH="$FAKE_REAL_PATH" curl "$@"
SH
  cat > "$shim/mv" <<'SH'
#!/bin/sh
# stand-in mv as BSD (macOS) has it: no --exchange; $FAKE_MV_FAIL makes moving the staged install into place fail
[ -n "$FAKE_NO_EXCHANGE" ] && case "$1" in --exchange) echo "mv: illegal option" >&2; exit 64 ;; esac
case "$1" in */.native.new.*) [ -n "$FAKE_MV_FAIL" ] && { echo "mv: stand-in failure" >&2; exit 1; } ;; esac
exec env PATH="$FAKE_REAL_PATH" mv "$@"
SH
  chmod +x "$shim/clang" "$shim/curl" "$shim/mv"
}
sig_run() { # SIGNAL COMMAND...: runs it in a session of its own, sends the signal once it has stopped at the stand-in, sets $sig_rc and $sig_pid
  s="$1"; shift; rm -f "$work/mark"
  perl -e 'use POSIX; setsid(); $SIG{INT} = "DEFAULT"; $SIG{HUP} = "DEFAULT"; exec @ARGV' -- "$@" > "$work/sig.out" 2>&1 & sp=$!
  i=0; until [ -s "$work/mark" ]; do nap; i=$((i + 1)); [ "$i" -gt 400 ] && break; done
  kill -s "$s" -- "-$sp" 2>/dev/null
  wait "$sp"; sig_rc=$?; sig_pid="$(cat "$work/mark" 2>/dev/null)"
  i=0; while [ -n "$sig_pid" ] && kill -0 "$sig_pid" 2>/dev/null && [ "$i" -lt 100 ]; do nap; i=$((i + 1)); done
  if [ -n "$sig_pid" ] && kill -0 "$sig_pid" 2>/dev/null; then sig_gone=no; kill "$sig_pid" 2>/dev/null; else sig_gone=yes; fi
}
t_atomic_install() {
  command -v perl >/dev/null 2>&1 || { ok "atomic install: skipped (no perl)"; return 0; }
  real_path="$PATH"; atomic_setup; echo object > "$work/c0.o"
  export FAKE_REAL_PATH="$real_path" PATH="$shim:$real_path" FAKE_MARK="$work/mark" TOMATO_TEST_BOOTSTRAP_OBJECT="$work/c0.o" TOMATO_HOME="$th" TOMATO_BIN="$work/b"
  # stopped while the runtime is compiled, and while the compiler is linked: the old install is untouched, nothing is left, nothing runs on
  for phase in " -c " "bin/tomatoc"; do
    for sg in INT TERM HUP; do
      atomic_setup; FAKE_HANG="$phase"; export FAKE_HANG; sig_run "$sg" sh ./install-native.sh; unset FAKE_HANG
      case "$sg" in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; esac
      left="$(ls -A "$th" | tr '\n' ' ')"
      check "install stopped by $sg at [$phase]: status $want, the old install intact, nothing left behind, the compile stopped" "$want OLD old native  yes" \
        "$sig_rc $(cat "$th/native/VERSION") $(cat "$th/native/std/old.tom") $left $sig_gone"
    done
  done
  # an install that completes replaces everything (no file of the old one stays) and leaves no folder of its own, with mv --exchange and without it
  for variant in exchange rename; do
    atomic_setup; [ $variant = rename ] && export FAKE_NO_EXCHANGE=1
    sh ./install-native.sh > "$work/inst.out" 2>&1; rc=$?; unset FAKE_NO_EXCHANGE
    check "install replaces the old one as a whole ($variant swap)" "0 $(cat VERSION) no 1" "$rc $(cat "$th/native/VERSION") $([ -e "$th/native/std/old.tom" ] && echo yes || echo no) $(ls -A "$th" | wc -l | tr -d ' ')"
    check "install: the new compiler and scripts are in place ($variant swap)" "yes yes" "$([ -x "$th/native/bin/tomatoc" ] && [ "$(cat "$th/native/bin/tomatoc")" != old ] && echo yes) $([ -x "$th/native/bin/tomato" ] && [ -f "$th/native/std/errors.txt" ] && echo yes)"
  done
  # the second rename of the fallback swap fails: the old install is put back, and the failure is reported
  atomic_setup; FAKE_NO_EXCHANGE=1 FAKE_MV_FAIL=1 sh ./install-native.sh > "$work/inst.out" 2>&1; rc=$?
  check "install: a failed swap puts the old install back" "1 OLD native yes" "$rc $(cat "$th/native/VERSION") $(ls -A "$th" | tr '\n' ' ' | sed 's/ $//') $(grep -q 'old one is kept' "$work/inst.out" && echo yes)"
  # leftovers of a dead installer (SIGKILL): removed by the next install, and an old install moved aside but never replaced comes back first
  atomic_setup; mkdir "$th/.native.new.99999991"; mv "$th/native" "$th/.native.old.99999992"
  sh ./install-native.sh > "$work/inst.out" 2>&1; rc=$?
  check "install clears the leftovers of an installer that was killed" "0 $(cat VERSION) native" "$rc $(cat "$th/native/VERSION") $(ls -A "$th" | tr '\n' ' ' | sed 's/ $//')"
  # a first install (nothing to swap)
  rm -rf "$th"; sh ./install-native.sh > "$work/inst.out" 2>&1; rc=$?
  check "install: a first install works" "0 $(cat VERSION) native" "$rc $(cat "$th/native/VERSION") $(ls -A "$th" | tr '\n' ' ' | sed 's/ $//')"
}
t_atomic_update() { # tomato update and tomato run, stopped at each phase: their temporary folders go, and what they started stops
  command -v perl >/dev/null 2>&1 || { ok "atomic update: skipped (no perl)"; return 0; }
  real_path="$PATH"; atomic_setup; uh="$work/u"; rh="$work/r"; arc="$work/arc"
  export FAKE_REAL_PATH="$real_path" PATH="$shim:$real_path" FAKE_MARK="$work/mark" TMPDIR="$tmpd" TOMATO_CACHE_DIR="$work/cache"
  # an installed command (the link in bin/ goes to native/bin/tomato) and a release archive whose installer stops at once
  mkdir -p "$uh/native/bin" "$uh/bin" "$arc/tomato-1.0.1"; cp native/tomato native/rtcache.sh "$uh/native/bin/"; chmod +x "$uh/native/bin/tomato"
  echo 1.0.0 > "$uh/native/VERSION"; ln -s "$uh/native/bin/tomato" "$uh/bin/tomato"
  printf '#!/bin/sh\necho "$$" > "$FAKE_MARK"\nexec sleep 60\n' > "$arc/tomato-1.0.1/install-native.sh"; chmod +x "$arc/tomato-1.0.1/install-native.sh"
  tar -czf "$arc/t.tar.gz" -C "$arc" tomato-1.0.1
  printf '{"version":"1.0.1","url":"file://%s/t.tar.gz","sha256":"%s"}' "$arc" "$(sha256 "$arc/t.tar.gz" | cut -d' ' -f1)" > "$arc/m.json"
  export TOMATO_UPDATE_URL="file://$arc/m.json" TOMATO_UPDATE_ALLOW_ANY_URL=1 TOMATO_HOME="$uh" TOMATO_BIN="$uh/bin"
  for phase in download installer; do
    for sg in INT TERM HUP; do
      rm -rf "$tmpd"; mkdir "$tmpd"; FAKE_HANG=""; [ $phase = download ] && FAKE_HANG=download; export FAKE_HANG
      sig_run "$sg" "$uh/bin/tomato" update; unset FAKE_HANG
      case "$sg" in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; esac
      check "update stopped by $sg during the $phase: status $want, no temporary folder left, the download or installer stopped, the install untouched" "$want  yes 1.0.0" "$sig_rc $(ls -A "$tmpd" | tr '\n' ' ') $sig_gone $(cat "$uh/native/VERSION")"
    done
  done
  # tomato run: the compiler stopped, and the program stopped (^C reaches it too: its own exit status, 7 here, is the answer)
  mkdir -p "$rh/bin" "$rh/runtime"; cp native/tomato native/rtcache.sh "$rh/bin/"; chmod +x "$rh/bin/tomato"; echo 1.0.0 > "$rh/VERSION"; echo "// runtime" > "$rh/runtime/tomato_rt.c"
  printf '#!/bin/sh\nif [ -n "$FAKE_TOMATOC_HANG" ]; then echo "$$" > "$FAKE_MARK"; exec sleep 60; fi\necho "define i32 @main() { ret i32 0 }"\n' > "$rh/bin/tomatoc"; chmod +x "$rh/bin/tomatoc"
  printf '@main\ndef main():\n    pass\n' > "$work/p.tom"
  for sg in INT TERM HUP; do
    rm -rf "$tmpd"; mkdir "$tmpd"; FAKE_TOMATOC_HANG=1; export FAKE_TOMATOC_HANG
    sig_run "$sg" "$rh/bin/tomato" run "$work/p.tom"; unset FAKE_TOMATOC_HANG
    case "$sg" in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; esac
    check "run stopped by $sg during the compile: status $want, no temporary folder left, the compiler stopped" "$want  yes" "$sig_rc $(ls -A "$tmpd" | tr '\n' ' ') $sig_gone"
  done
  FAKE_PROGRAM='trap "exit 7" INT; echo "$$" > "$FAKE_MARK"; sleep 60 & p=$!; trap "kill $p; exit 7" INT; wait'; export FAKE_PROGRAM
  for sg in INT TERM; do
    rm -rf "$tmpd"; mkdir "$tmpd"; sig_run "$sg" "$rh/bin/tomato" run "$work/p.tom"
    case "$sg" in INT) want=7 ;; TERM) want=143 ;; esac
    check "run: $sg while the program runs: status $want, the program stopped, no temporary folder left" "$want  yes" "$sig_rc $(ls -A "$tmpd" | tr '\n' ' ') $sig_gone"
  done
}
t_release_versions() { # the version release/release.sh picks (--next-version: no clone, no tag or GitHub checks), and the ones it refuses
  nv() { cur="$1"; shift; r="$(sh release/release.sh "$@" --next-version "$cur" 2>&1)" && echo "$r" || echo refused; }
  check "release.sh picks MAJOR.MINOR.PATCH and SemVer pre-releases" "refused 1.0.0 1.0.0-rc.1 1.0.0 1.0.1 1.1.0 2.0.0 refused 1.0.0 1.0.0-rc.2 1.0.0-rc.10" \
    "$(nv 0.51) $(nv 0.51 --version 1.0.0) $(nv 0.51 --version 1.0.0-rc.1) $(nv 0.51 --bump major) $(nv 1.0.0) $(nv 1.0.0 --bump minor) $(nv 1.4.2 --bump major) $(nv 1.0.0-rc.1) $(nv 1.0.0-rc.1 --version 1.0.0) $(nv 1.0.0-rc.1 --version 1.0.0-rc.2) $(nv 1.0.0-rc.9 --version 1.0.0-rc.10)"
  check "release.sh refuses older, malformed and build-tagged versions" "refused refused refused refused refused refused refused" \
    "$(nv 1.0.0-rc.2 --version 1.0.0-rc.1) $(nv 1.0.0 --version 1.0.0-rc.1) $(nv 1.0.0 --version 0.99.0) $(nv 1.0.0 --version 1.0.1+b) $(nv 1.0.0 --version 1.0.1-rc.01) $(nv 1.0.0 --version 1.0) $(nv 1.0.0-rc.1 --bump patch)"
}
t_release_resume() { # release/release.sh after a failure (--resume, --from, --restart), in a sandbox: tests/release_resume.sh has the fake Mac tools and a local "origin", so nothing is signed, published or pushed anywhere
  sh tests/release_resume.sh "$work/rr" > "$work/rr.out" 2>&1; rc=$?
  while IFS= read -r l; do case "$l" in "ok   "*) echo x >> "$shared/passed" ;; "FAIL "*) echo x >> "$shared/failed" ;; esac; done < "$work/rr.out"
  cat "$work/rr.out"
  [ "$rc" = 0 ] || [ -n "$(grep '^FAIL' "$work/rr.out")" ] || bad "release resume sandbox tests ran (status $rc)"
}
t_cli_test() { # tomato test (D81a, D97a): each file in tests/ is one test, in a process of its own; the forms FILE and FILE ENTRY INPUTS..., the summary line, the status, --filter, --timeout, -v
  part="${1:-1}"; cli_setup
  # the lines of the report that do not depend on the traces in the output of a failed file: one line for each file and the summary
  lines() { grep -E '^(ok|FAIL|skip) |^tomato test: |^warning|^error'; }
  mkdir -p "$work/proj/tests"; cd "$work/proj"
  printf 'from testing import assert_equal\n\n@main\ndef main():\n    assert_equal(1 + 1, 2)\n    print("a ran")\n' > tests/a_pass.tom
  printf 'from testing import assert_equal\n\n@main\ndef main():\n    print("before")\n    assert_equal([1, 2], [1, 3])\n' > tests/b_fail.tom
  printf 'from testing import skip\n\n@main\ndef main():\n    skip("no network")\n' > tests/c_skip.tom
  printf 'import sys\n\n@main\ndef main():\n    sys.exit(3)\n' > tests/d_exit.tom
  printf 'from testing import assert_equal, skip\n\n@test.adds\ndef adds():\n    assert_equal(1 + 1, 2)\n\n@test.lookup\ndef lookup():\n    skip("later")\n\n@test.subs\ndef subs():\n    assert_equal(3 - 1, 2)\n' > tests/e_group.tom
  printf 'def helper() -> int:\n    return 1\n' > tests/_helper.tom
  if step 1; then
  r="$($t test 2>&1)"; rc=$?
  check "tomato test: every tests/*.tom, one line each (a helper module that starts with _ is left out), then the summary" "ok   tests/a_pass.tom
FAIL tests/b_fail.tom  (exit status 1)
skip tests/c_skip.tom  (no network)
FAIL tests/d_exit.tom  (exit status 3)
ok   tests/e_group.tom  (2 passed, 1 skipped)
tomato test: 5 files, 2 passed, 2 failed, 1 skipped: FAILED" "$(printf '%s\n' "$r" | lines)"
  check "tomato test: the status is 1 when a file failed" "1" "$rc"
  case "$r" in *"    before
    error"*"AssertionError: lists differ at [1]: expected 3, got 2"*"      expected: [1, 3]
      actual:   [1, 2]"*) ok "tomato test: a failed file shows its output under its line, with the diff";; *) bad "tomato test: a failed file shows its output under its line, with the diff" "$r";; esac
  case "$r" in *"a ran"*) bad "tomato test: a passing file's output is not shown" "$r";; *) ok "tomato test: a passing file's output is not shown";; esac
  r="$($t test -v tests/a_pass.tom tests/e_group.tom 2>&1)"; rc=$?
  check "tomato test -v shows the output of the files that pass, a file with @test functions shows its functions" "ok   tests/a_pass.tom
    a ran
ok   tests/e_group.tom  (2 passed, 1 skipped)
    ok   adds
    skip lookup  (later)
    ok   subs
    2 passed, 0 failed, 1 skipped
tomato test: 2 files, 2 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test --mode release tests/a_pass.tom 2>&1)"; rc=$?
  check "tomato test --mode release runs the file in release mode" "ok   tests/a_pass.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test --filter pass tests 2>&1)"; rc=$?
  check "tomato test --filter keeps the files whose name contains the text; a folder stands for its test files" "ok   tests/a_pass.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test --filter zzz tests/a_pass.tom 2>&1)"; rc=$?
  check "tomato test --filter that keeps no file says so and the status stays 0" "warning: no file name contains 'zzz'
tomato test: 0 files, 0 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test tests/a_pass.tom tests/c_skip.tom 2>&1)"; rc=$?
  check "tomato test FILE FILE: the files in the order given, a skipped file does not fail the run" "ok   tests/a_pass.tom
skip tests/c_skip.tom  (no network)
tomato test: 2 files, 1 passed, 0 failed, 1 skipped: ok
0" "$(printf '%s\n' "$r" | lines)
$rc"
  r="$($t test --mode release tests/c_skip.tom 2>&1)"
  check "tomato test: a skipped file in release mode" "skip tests/c_skip.tom
tomato test: 1 files, 0 passed, 0 failed, 1 skipped: ok" "$(printf '%s\n' "$r" | lines)"
  fi; if step 2; then
  # errors in the command line, a file that does not compile or has nothing to run
  printf 'from testing import assert_equal\n\n@main\ndef main():\n    assert_equal(undefined_name, 1)\n' > "$work/tbad.tom"
  printf 'def nothing() -> int:\n    return 1\n' > "$work/tnone.tom"
  r="$($t test "$work/tbad.tom" "$work/tnone.tom" tests/a_pass.tom 2>&1)"; rc=$?
  check "tomato test: a file that does not compile or has no @main fails, with the compiler's message, and the next file still runs" "FAIL $work/tbad.tom  (did not compile)
    error[E227]: name 'undefined_name' is not defined
FAIL $work/tnone.tom  (did not compile)
    error[E228]: no function is marked @main
ok   tests/a_pass.tom
tomato test: 3 files, 1 passed, 2 failed, 0 skipped: FAILED
1" "$(printf '%s\n' "$r" | grep -E '^(ok|FAIL|skip) |^tomato test: |^    error\[')
$rc"
  r="$($t test x 2>&1)"; rc=$?
  check "tomato test x (a bare word) is an error that suggests x.tom" "error: 'x' is not a file: write tomato test x.tom (or tests/x.tom); a word that is not a file is only accepted right after a file, as the entry to run in it (tomato test x.tom x)
1" "$r
$rc"
  r="$($t test tests/a_pass.tom x tests/b_fail.tom 2>&1 | head -3)"
  case "$r" in *"error[E352]"*|*"FAIL tests/a_pass.tom"*) ok "tomato test FILE x: the word after a file is its entry";; *) bad "tomato test FILE x: the word after a file is its entry" "$r";; esac
  r="$($t test "$work/nothing.tom" 2>&1)"; rc=$?
  check "tomato test: a file that does not exist" "error: cannot read $work/nothing.tom
1" "$r
$rc"
  mkdir -p "$work/none"; cd "$work/none"
  r="$($t test 2>&1)"; rc=$?
  check "tomato test with no file and no tests folder says what to do" "error: no tests folder here: run tomato test FILE..., or put test files in tests/ (each tests/NAME.tom is one test)
1" "$r
$rc"
  mkdir -p "$work/none/tests"; printf 'def helper() -> int:\n    return 1\n' > "$work/none/tests/_h.tom"
  r="$($t test 2>&1)"; rc=$?
  check "tomato test: a tests folder with only helper modules has no test" "error: no test file in tests (each tests/NAME.tom is one test; a name that starts with _ is a helper module, not a test)
1" "$r
$rc"
  cd "$work/proj"
  r="$($t test --bogus 2>&1)"; rc=$?
  check "tomato test: an unknown option is an error" "error: unknown option '--bogus' for 'tomato test' (options go before the files: the words after a file or its entry are not options; run 'tomato help')
1" "$r
$rc"
  r="$($t test --timeout x tests/a_pass.tom 2>&1)"; rc=$?
  check "tomato test: --timeout takes whole seconds" "error: --timeout takes a whole number of seconds above 0, not 'x'
1" "$r
$rc"
  case "$($t help)" in *"tomato test [--filter TEXT] [--timeout SECONDS] [--mode MODE] [-v] [FILE]... | FILE ENTRY [INPUTS...]"*) ok "tomato help lists the test command";; *) bad "tomato help lists the test command" "$($t help | grep 'tomato test')";; esac
  # the inputs of main have defaults: a bare tomato test can always run it
  printf 'from testing import assert_equal\n\n@main\ndef main(n: int = 3, word: str = "w"):\n    print("n =", n, "word =", word)\n    assert_equal(n, 3)\n' > tests/f_defaults.tom
  printf '@main\ndef main(n: int):\n    print(n)\n' > "$work/tneeds.tom"
  r="$($t test -v tests/f_defaults.tom 2>&1)"
  check "tomato test: a main whose inputs have defaults runs with none" "ok   tests/f_defaults.tom
    n = 3 word = w
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "$r"
  r="$($t test "$work/tneeds.tom" 2>&1)"; rc=$?
  check "tomato test: a main with an input that has no default fails, says the rule and shows the runtime's message" "FAIL $work/tneeds.tom  (exit status 1: a function run with no inputs must give every input a default (or be run with inputs: tomato test FILE ENTRY INPUTS...))
    error[E352]: the entry point takes 1 input(s), got 0 (an input can be left out only if it has a default, as in def main(n: int = 10))
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED
1" "$r
$rc"
  fi; if step 3; then
  # FILE ENTRY INPUTS...: as tomato run FILE ENTRY INPUTS...
  printf 'from testing import assert_equal\n\n@main\ndef main():\n    print("main ran")\n\n@check\ndef check(n: int, word: str = "w"):\n    print("check", n, word)\n    assert_equal(n, 4)\n' > "$work/tentries.tom"
  r="$($t test -v "$work/tentries.tom" check 4 hi 2>&1)"; rc=$?
  check "tomato test FILE ENTRY INPUTS: the entry runs with the inputs" "ok   $work/tentries.tom
    check 4 hi
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  printf '@main\ndef main(n: int = 3):\n    assert n < 0\n' > "$work/tneg.tom"
  r="$($t test "$work/tneg.tom" main -5 2>&1)"; rc=$?
  check "tomato test FILE ENTRY -5: a word that starts with - after a file is an input, as for tomato run" "ok   $work/tneg.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  # options are read only before the files: after a file or its entry every word is raw input, even --filter
  printf '@main\ndef main(a: str = "", b: str = "", c: str = ""):\n    print(f"inputs {a} {b} {c}".strip())\n' > "$work/tinp.tom"
  r="$($t test -v "$work/tinp.tom" main --filter -v --mode 2>&1)"; rc=$?
  check "tomato test FILE ENTRY --filter -v --mode: the words after the entry are inputs, no option is read there" "ok   $work/tinp.tom
    inputs --filter -v --mode
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test -v "$work/tinp.tom" main -- --filter 2>&1)"
  check "tomato test FILE ENTRY -- --filter: a -- after the entry is an input too" "ok   $work/tinp.tom
    inputs -- --filter
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "$r"
  r="$($t test --filter tinp -v --mode release "$work/tinp.tom" main --timeout 5 2>&1)"; rc=$?
  check "tomato test: options before the file still work, and --timeout after the entry is an input" "ok   $work/tinp.tom
    inputs --timeout 5
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test -v -- "$work/tinp.tom" main --filter x 2>&1)"
  check "tomato test -- FILE: the separator ends the options, the next word is the file" "ok   $work/tinp.tom
    inputs --filter x
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "$r"
  r="$($t test -v -- --filter 2>&1)"; rc=$?
  check "tomato test -- --filter: after the separator an option-like word is no option (it is not a file either)" "error: '--filter' is not a file: write tomato test --filter.tom (or tests/--filter.tom); a word that is not a file is only accepted right after a file, as the entry to run in it (tomato test x.tom --filter)
1" "$r
$rc"
  r="$($t test "$work/tinp.tom" --filter x 2>&1)"; rc=$?
  check "tomato test FILE --filter: an option after the file is refused, not read" "error: '--filter' comes after a file, so it is not an option (options go before the files: tomato test --filter $work/tinp.tom); it can only be an input of an entry (tomato test $work/tinp.tom ENTRY --filter)
1" "$r
$rc"
  r="$($t test "$work/tinp.tom" main --color never -v 2>&1)"; rc=$?
  check "tomato test FILE ENTRY: --color and -v after the entry are inputs" "ok   $work/tinp.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test "$work/tentries.tom" check 5 2>&1)"; rc=$?
  check "tomato test FILE ENTRY INPUTS: an assertion in the entry fails the file" "FAIL $work/tentries.tom  (exit status 1)
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED
1" "$(printf '%s\n' "$r" | grep -E '^(ok|FAIL|skip) |^tomato test: ')
$rc"
  r="$($t test -v "$work/tentries.tom" main 2>&1)"
  check "tomato test FILE ENTRY: the entry main" "ok   $work/tentries.tom
    main ran
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "$r"
  r="$($t test "$work/tentries.tom" check 2>&1)"
  check "tomato test FILE ENTRY with the inputs missing fails, says the rule and shows the runtime's message" "FAIL $work/tentries.tom  (exit status 1: a function run with no inputs must give every input a default (or be run with inputs: tomato test FILE ENTRY INPUTS...))
    error[E352]: the entry point takes 2 input(s), got 0 (an input can be left out only if it has a default, as in def main(n: int = 10))
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED" "$r"
  r="$($t test "$work/tentries.tom" nosuch 2>&1)"
  check "tomato test FILE ENTRY: an entry that is not in the file fails with the compiler's message" "FAIL $work/tentries.tom  (did not compile)
    error[E228]: no function is marked @nosuch" "$(printf '%s\n' "$r" | sed -n 1,2p)"
  r="$($t test tests/e_group.tom test 2>&1)"
  check "tomato test FILE test: the entry test runs the file's @test functions, as when there is no @main" "ok   tests/e_group.tom  (2 passed, 1 skipped)
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "$r"
  r="$($t test tests/e_group.tom test 1 2>&1)"
  check "tomato test FILE test INPUTS: the entry test takes no inputs" "FAIL tests/e_group.tom  (the entry test (the functions marked @test) takes no inputs)
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED" "$r"
  r="$($t test tests/a_pass.tom tests/e_group.tom 2>&1 | lines)"
  check "tomato test FILE FILE: a second file is a file, not an entry" "ok   tests/a_pass.tom
ok   tests/e_group.tom  (2 passed, 1 skipped)
tomato test: 2 files, 2 passed, 0 failed, 0 skipped: ok" "$r"
  fi; if step 4; then
  # one process for each file: a file that ends the program, overflows the stack or hangs fails alone, and the next file still runs
  printf 'import sys\n\n@test.first\ndef first():\n    assert 1 == 1\n\n@test.quits\ndef quits():\n    sys.exit(0)\n\n@test.never\ndef never():\n    assert 1 == 1\n' > "$work/exits.tom"
  printf 'def down(n: int) -> int:\n    return down(n + 1) + 1\n\n@main\ndef main():\n    print(down(0))\n' > "$work/deep.tom"
  printf '@main\ndef main():\n    x = 0\n    while True:\n        x += 1\n' > "$work/hang.tom"
  printf 'import sys\n\n@main\ndef main():\n    sys.exit(0)\n' > "$work/ends.tom"
  r="$($t test "$work/exits.tom" "$work/deep.tom" "$work/ends.tom" tests/a_pass.tom 2>/dev/null)"; rc=$?
  check "tomato test: sys.exit(0) in a test function, a stack overflow, sys.exit(0) in a main: each file alone; the later files still run" "FAIL $work/exits.tom  (the program ended in quits with status 0 (a test must not call sys.exit))
ok   $work/ends.tom
ok   tests/a_pass.tom
tomato test: 4 files, 2 passed, 2 failed, 0 skipped: FAILED
1" "$(printf '%s\n' "$r" | grep -E '^(ok|FAIL|skip) |^tomato test: ' | grep -v "deep.tom")
$rc"
  case "$r" in *"FAIL $work/deep.tom  (exit status 1)"*"stack overflow"*) ok "tomato test: a stack overflow fails its file with the runtime's message";; *) bad "tomato test: a stack overflow fails its file with the runtime's message" "$r";; esac
  printf 'import sys\n\n@main\ndef main():\n    sys.exit(130)\n' > "$work/e130.tom"
  r="$($t test "$work/e130.tom" 2>&1)"
  check "tomato test: an exit status above 128 is not called a signal for sure" "FAIL $work/e130.tom  (exit status 130 (killed by signal 2, or sys.exit(130)))
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED" "$r"
  r="$($t test --timeout 2 "$work/hang.tom" tests/a_pass.tom 2>&1)"; rc=$?
  check "tomato test --timeout: a file that runs too long is stopped and named, the next file runs" "FAIL $work/hang.tom  (timed out after 2 seconds)
ok   tests/a_pass.tom
tomato test: 2 files, 1 passed, 1 failed, 0 skipped: FAILED
1" "$r
$rc"
  r="$($t test --timeout 30 tests/a_pass.tom 2>&1)"; rc=$?
  check "tomato test --timeout: a file that finishes in time is unaffected" "ok   tests/a_pass.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  fi; if step 5; then
  # dotted entry markers (D96a): every marker marks one function; the entry `x` runs @x and every @x.*, `x.y` runs that one
  cat > "$work/tg.tom" <<'TG'
@greet
def hello():
    print('hello')

@greet.loud
def loud():
    print('HELLO')

@greet.quiet
def quiet():
    print('hello...')

@greetx
def other():
    print('other')

@calc.add
def add(n: int = 2):
    print(n + 1)

@main
def main():
    print('main')
TG
  check "entry greet runs @greet and every @greet.*, in the order written" "hello
HELLO
hello..." "$($t run "$work/tg.tom" greet 2>&1)"
  check "entry greet.loud runs only that function" "HELLO" "$($t run "$work/tg.tom" greet.loud 2>&1)"
  check "entry greet does not run @greetx (a dot, not a prefix)" "other" "$($t run "$work/tg.tom" greetx 2>&1)"
  check "entry calc selects one function, which takes its inputs" "6" "$($t run "$work/tg.tom" calc 5 2>&1)"
  check "entry calc.add runs it with the default input" "3" "$($t run "$work/tg.tom" calc.add 2>&1)"
  check "the default entry is still @main" "main" "$($t run "$work/tg.tom" 2>&1)"
  check "a group runs in release mode too" "hello
HELLO
hello..." "$($t run --mode release "$work/tg.tom" greet 2>&1)"
  check "tomato build --entry greet.quiet writes a program that runs only that function" "hello..." "$($t build "$work/tg.tom" --entry greet.quiet -o "$work/tg_quiet" >/dev/null 2>&1 && "$work/tg_quiet" 2>&1)"
  cat > "$work/tdot.tom" <<'TD'
from testing import assert_equal

@test
def bare():
    assert_equal(1, 1)

@test.a.x
def a_x():
    assert_equal(2, 2)

@test.a.y
def a_y():
    assert_equal(3, 3)

@test.ab
def ab():
    assert_equal(4, 4)

@test.fails
def fails():
    assert_equal(1, 2)
TD
  r="$($t run "$work/tdot.tom" test 2>&1)"; rc=$?
  check "the entry test runs @test and every @test.*, in the order written" "ok   bare
ok   a_x
ok   a_y
ok   ab
FAIL fails
     expected 2, got 1  (raised on line 21)
4 passed, 1 failed, 0 skipped" "$r"
  check "that failing run exits 1" "1" "$rc"
  r="$($t run "$work/tdot.tom" test.a 2>&1)"; rc=$?
  check "the entry test.a runs @test.a.x and @test.a.y, not @test.ab" "ok   a_x
ok   a_y
2 passed, 0 failed, 0 skipped" "$r"
  check "a selected run that passes exits 0" "0" "$rc"
  r="$($t run --mode release "$work/tdot.tom" test.fails 2>&1)"; rc=$?
  check "the entry test.fails runs that test alone, and exits 1" "FAIL fails
     expected 2, got 1
0 passed, 1 failed, 0 skipped 1" "$r $rc"
  r="$($t run "$work/tdot.tom" test.a --filter y 2>&1)"
  check "--filter works inside a selected entry" "ok   a_y
1 passed, 0 failed, 0 skipped" "$r"
  r="$($t run "$work/tdot.tom" test.ab 2>&1)"
  check "tomato run FILE test.ab is the same selection" "ok   ab
1 passed, 0 failed, 0 skipped" "$r"
  # tomato test FILE ENTRY with a dotted entry: one function (or a group) of a file, as a test
  r="$($t test "$work/tdot.tom" test.a 2>&1)"; rc=$?
  check "tomato test FILE test.a: the entry is a group of the file's @test functions" "ok   $work/tdot.tom  (2 passed)
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok
0" "$r
$rc"
  r="$($t test "$work/tdot.tom" test.fails 2>&1)"; rc=$?
  check "tomato test FILE test.fails: a failing function fails the file" "FAIL $work/tdot.tom  (1 of 1 tests failed)
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED
1" "$(printf '%s\n' "$r" | grep -E '^(ok|FAIL|skip) |^tomato test: ')
$rc"
  r="$($t test "$work/tdot.tom" test.zzz 2>&1)"; rc=$?
  case "$r" in *"error[E228]: no function is marked @test.zzz"*) [ "$rc" = 1 ] && ok "tomato test FILE test.zzz: a marker nothing has" || bad "tomato test FILE test.zzz: a marker nothing has" "status $rc";; *) bad "tomato test FILE test.zzz: a marker nothing has" "$r";; esac
  fi
}
t_cli_compile() { cli_setup; check "compile writes IR" "yes" "$($t compile examples/shapes.tom | grep -q 'define i32 @main' && echo yes)"; }
section "== command line =="
register t early t_cli_update      # it needs no installed command: it makes its own install, which takes long (the compiler is built)
spawn_cli t_cli_modes 1
spawn_cli t_cli_modes 2
spawn_cli t_cli_modes 3
spawn_cli t_cli_modes 4
spawn_cli t_cli_modes 5
spawn_cli t_cli_modes 6
for name in int_boundary big_numbers bitwise floor_divide_power containers cycle list_ops compound_ops fixed_width numbers_rules; do
  case "$name" in int_boundary|containers|cycle) ;; *) [ -n "$fast" ] && { skip "release mode runs $name like debug"; continue; } ;; esac   # (the fast tier: three of the ten)
  spawn_cli t_cli_release_like_debug "$name"
done
spawn_cli t_cli_release_no_leak
spawn_cli t_cli_build_keeps_source
spawn_free t_cli_update_versions
spawn_free t_atomic_install
spawn_free t_atomic_update
spawn_free t_release_versions
spawn_free t_release_resume
spawn_cli t_cli_no_lto
spawn_cli t_cli_require_lto
spawn_cli t_cli_debug_link
for name in int_fast_paths int_boundary bitwise floor_divide_power big_numbers numbers_rules small_int_loops fast_paths compound_ops fixed_width; do
  case "$name" in int_fast_paths|int_boundary|bitwise) ;; *) [ -n "$fast" ] && { skip "debug link runs $name like the plain link"; continue; } ;; esac   # (the fast tier: three of the ten)
  spawn_cli t_cli_inline_paths "$name"
done
spawn_first t_cli_runtime_cache 1   # (not the installed command: it only needs the compiler)
spawn_first t_cli_runtime_cache 2
spawn_first t_cli_runtime_cache 3
spawn_first t_cli_runtime_cache 4
spawn_cli t_cli_explain
spawn_cli t_cli_config
spawn_cli t_cli_manifest
spawn_cli t_cli_build_tables
spawn_cli t_cli_seeds
spawn_cli t_cli_seed_store
spawn_cli t_cli_seed_update
spawn_cli t_cli_project
spawn_cli t_manifest_logic
spawn_cli t_manedit_logic
spawn_cli t_cli_repl_1 1
spawn_cli t_cli_repl_1 2
spawn_cli t_cli_repl_1 3
spawn_cli t_cli_color 1
spawn_cli t_cli_color 2
spawn_cli t_cli_color 3
spawn_cli t_cli_warnings 1
spawn_cli t_cli_warnings 2
spawn_cli t_cli_repl_2 1
spawn_cli t_cli_repl_2 2
spawn_cli t_cli_repl_2 3
spawn_cli t_cli_repl_redef
spawn_cli t_cli_repl_history
spawn_cli t_cli_compile
spawn_cli t_cli_test 1
spawn_cli t_cli_test 2
spawn_cli t_cli_test 3
spawn_cli t_cli_test 4
spawn_cli t_cli_test 5
t_terminal_logic() { # std/terminal.tom: the pure parts as @test functions (the key decoder at every byte split, widths, SGR lowering, color depth), debug and release
  cli_setup
  for mode in debug release; do
    r="$($t run --mode $mode tests/terminal_logic.tom test 2>&1 | tail -1)"
    case "$r" in *" passed, 0 failed, 0 skipped") ok "terminal: the @test functions pass ($mode mode): $r";; *) bad "terminal: the @test functions pass ($mode mode)" "$($t run --mode $mode tests/terminal_logic.tom test 2>&1 | grep -v '^ok ' | head -12)";; esac
  done
}
t_terminal_pty() { # std/terminal.tom on a real terminal (a pty), through expect: raw mode, keys, size and resize, and the restore however the program ends
  cli_setup
  if ! command -v expect >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "terminal pty test" "expect is required in CI" || echo "skip: expect is not installed, so the terminal pty test did not run"
    return
  fi
  if $t build tests/terminal_pty.tom --entry main -o "$work/terminal_pty" > "$work/e" 2>&1; then
    check "terminal: raw mode, keys, size, resize and the restore on a pty" "ok" "$(expect tests/terminal_pty.exp "$work/terminal_pty" 2>&1 | tail -1)"
  else bad "terminal pty test: tests/terminal_pty.tom does not build" "$(head -5 "$work/e")"; fi
}
spawn_cli t_terminal_logic
spawn_cli t_terminal_pty
spawn_cli t_lineedit_logic
spawn_cli t_repledit_logic
spawn_cli t_lexer_spans
spawn_cli t_todo_shell_logic
spawn_cli t_todo_shell_pty
spawn t_std_sheets

# ---- the CLI contract ---------------------------------------------------------------------------------------------------
# tests/cli_contract: a black-box suite of the `tomato` command (docs/shell-to-tomato-plan.md, sections 6 and 12), written to pass any
# `tomato` (today the script, later the compiled Tomato program that replaces it) and to know nothing of how it is made. Here it runs against
# the installed command ($t). One test per case file (tests/cli_contract/cases/NAME.sh); the fast tier skips the cases that link many
# programs (the ones that say `# tier: full` on their second line) and runs the others. `sh tests/cli_contract/run.sh --help` runs it alone.
t_cli_contract() { # NAME: the lines of the case become the suite's ok and FAIL lines
  cli_setup
  TOMATO="$t" CONTRACT_FAST="$fast" CONTRACT_JOBS=1 sh tests/cli_contract/run.sh "$1" > "$work/contract.out" 2>&1 < /dev/null; contract_rc=$?
  detail=""; failing=""
  while IFS= read -r line; do
    case "$line" in
      "ok   "*) [ -z "$failing" ] || { bad "$failing" "$detail"; failing=""; detail=""; }; ok "${line#ok   }" ;;
      "FAIL "*) [ -z "$failing" ] || bad "$failing" "$detail"; failing="${line#FAIL }"; detail="" ;;
      "     "*) [ -z "$failing" ] || detail="$detail${detail:+
}${line#     }" ;;
      "skip "*) [ -z "$failing" ] || { bad "$failing" "$detail"; failing=""; detail=""; }; echo "$line" ;;
      "tomato under test:"*|"cli contract: "*|"") ;;
      *) [ -z "$failing" ] || { bad "$failing" "$detail"; failing=""; detail=""; }; echo "$line" ;;
    esac
  done < "$work/contract.out"
  [ -z "$failing" ] || bad "$failing" "$detail"
  [ "$contract_rc" -le 1 ] || bad "cli contract $1: the runner failed (status $contract_rc)" "$(cat "$work/contract.out")"
}
section "== CLI contract (tests/cli_contract: what a user sees of the tomato command, whatever it is made of) =="
for cf in tests/cli_contract/cases/*.sh; do
  cn="$(basename "$cf" .sh)"
  if [ -n "$fast" ] && sed -n '2p' "$cf" | grep -q '^# tier: full'; then skip "cli contract $cn"; else spawn_cli t_cli_contract "$cn"; fi
done

# ---- rejected programs --------------------------------------------------------------------------------------------------
t_neg() { # file, message that the compiler must report, and the entry name (default main; `test` for the @test checks)
  msg="$("$c1" "tests/negative/$1.tom" "${3:-main}" std/ 2>&1 >/dev/null)"; code=$?
  case "$msg" in *"$2"*) [ $code -ne 0 ] && ok "rejects $1" || bad "rejects $1" "exit status was 0";; *) bad "rejects $1" "wanted: $2
got:    $msg";; esac
}
neg() { spawn t_neg "$@"; }
section "== rejected programs =="
neg error_subclass_args "'NotFound' takes 2 arguments, but 3 given"
neg fixed_int_or_none "'int[length=8]' cannot be combined with None, because only int, float, bool, str, lists, dicts, sets, classes and tuples can be None"
neg list_of_fixed_or_none "'uint[length=16]' cannot be combined with None"
neg param_fixed_or_none "'int[length=32]' cannot be combined with None"
neg optional_int_as_text "the value has type int | None, but str is expected"
neg optional_int_as_float "the value has type int | None, but float | None is expected"
neg optional_float_from_int "the value has type int, but float | None is expected"
neg optional_bool_from_int "the value has type int, but bool | None is expected"
neg optional_int_condition "a condition has type int | None, but bool is expected"
neg int_never_none "a value of type int is never None, so it cannot be compared with None"
neg optional_int_len "the argument of len has type int | None, but str is expected"
neg optional_int_conditional "the two values of this conditional expression have different types: int and None"
neg dict_get_optional_values "get(key) gives None for a missing key, but a value of type int | None cannot be None"
neg optional_int_three_way "a union cannot hold None together with two or more other types"
neg optional_narrow_field "cannot use '+' with str | None and str"
neg optional_narrow_assigned "cannot use '+' with str | None and str"
neg optional_narrow_nested_assign "cannot use '+' with str | None and str"
neg optional_narrow_no_exit "cannot use '+' with str | None and str"
neg optional_narrow_after_if "cannot use '+' with str | None and str"
neg optional_narrow_or_right "cannot use '+' with str | None and str"
neg optional_narrow_after_while "cannot use '+' with str | None and str"
neg optional_narrow_while_exit "cannot use '+' with str | None and str"
neg optional_narrow_loop_assign "cannot use '+' with str | None and str"
neg optional_narrow_other_variable "cannot use '+' with str | None and str"
neg optional_narrow_int_ends "cannot use '+' with int | None and str"
neg optional_narrow_derived "the assigned value has type None, but str is expected"
neg optional_assign_optional "cannot use '+' with str | None and str"
neg optional_assign_none_branch "cannot use '+' with str | None and str"
neg optional_assign_one_branch "cannot use '+' with str | None and str"
neg optional_assign_elif_no_else "cannot use '+' with str | None and str"
neg optional_assign_call "cannot use '+' with str | None and str"
neg optional_assign_after_loop "cannot use '+' with str | None and str"
neg optional_assign_loop_head "cannot use '+' with str | None and str"
neg optional_assign_try "cannot use '+' with str | None and str"
neg optional_assign_branch_empty "cannot use '+' with str | None and str"
neg optional_assign_nested_leave "cannot use '+' with str | None and str"
neg optional_assign_ended "cannot use '+' with str | None and str"
neg optional_assign_int_branch "cannot use '+' with int | None and str"
neg optional_assign_int_narrowed "cannot use '+' with int and str"
neg optional_assign_derived "the assigned value has type None, but str is expected"
neg union_with_none "a union cannot hold None together with two or more other types"
neg type_mismatch "cannot use '+' with int and str"
neg dict_key_no_hash "'Point' has no method marked @hash, so it cannot be a dict key or set element"
neg dict_key_eq_only "'Point' has a method marked @eq but none marked @hash"
neg dict_key_list "a list can change, so it cannot be a dict key or set element"
neg set_elem_set "a set can change, so it cannot be a dict key or set element"
neg dict_key_union_list "a list can change, so it cannot be a dict key or set element"
neg dict_key_iface_no_hash "values cannot be a dict key or set element: the class 'Sq' implements it but has no method marked @hash"
neg dict_key_optional_no_hash "'Point' has no method marked @hash, so it cannot be a dict key or set element"
neg dict_key_function "a value of type fn(int) -> int cannot be a dict key or set element"
neg internal_helper_name "the function '_cast' is not defined"
neg hash_of_list "hash() cannot take a value of type list[int]"
neg hash_bad_signature "must take nothing besides self and return an int"
neg generic_keyword_args "keyword arguments are not supported when creating an object"
neg clock_args "clock() takes no arguments"
neg fixed_range "300 does not fit in uint[length=8]"
neg int_to_int64 "argument 1 of 'id64' (the parameter 'a') has type int, but int[length=64] is expected"
neg float_length_32 "float has no length"
neg float_length_key "float has no length"
neg float_length_call "float has no length"
neg float_length_type_arg "float has no length"
neg unknown_name "name 'nothing' is not defined"
neg private_field "the field 'x' is private to class 'C'"
neg const_field "the const field 'x' cannot be changed after the object is created"
neg bad_argument "argument 1 of 'f' (the parameter 'a') has type str, but int is expected"
neg bad_return "the returned value has type str, but int is expected"
neg trig_needs_angle "argument 1 of 'sin' (the parameter 'a') has type float, but math.Angle is expected"
neg dead_range_literal "300 does not fit in uint[length=8]"
neg wrong_type_in_branch "the assigned value has type str, but int is expected"
neg bad_assign "the assigned value has type str, but int is expected"
neg constant_division_by_zero "the divisor is the constant 0"
neg dead_constant_division "the divisor is the constant 0"
neg dead_fixed_width_overflow "does not fit in int[length=8]"
neg keyword_twice "the argument 'a' of 'f' is given twice"
neg keyword_unknown "'f' has no parameter named 'b'"
neg too_many_arguments "'f' takes 1 argument, but 2 given"
neg union_wrong_member "has type float, but int | str is expected"
neg union_narrowed_assign "is known to be int inside this check"
neg tuple_append "a tuple cannot be changed"
neg tuple_assign "a tuple cannot be changed"
neg non_bool_condition "a condition has type int, but bool is expected"
neg sync_input "input() is async, so it must be awaited"
neg sync_sleep "sleep() is async, so it must be awaited"
neg async_call_without_await "'work' is async, so it must be awaited or started"
neg async_unstarted_index "'work' is async, so it must be awaited or started"
neg async_unstarted_after_start "'work' is async, so it must be awaited or started"
neg async_unstarted_constructor "'work' is async, so it must be awaited or started"
neg await_outside_async "'await' can only be used inside an async function"
neg generic_no_type "'Box' is generic, so it needs its type arguments: Box[T]"
neg generic_cannot_infer "cannot tell what T is in this call of 'Stack'"
neg generic_wrong_item "argument 1 of 'put' (the parameter 'item') has type str, but int is expected"
neg generic_mixed_items "a list item has type str, but int is expected"
neg generic_six_params "a class or function takes at most five type parameters"
neg cache_one_type "'Cache' takes 2, 3, 4 or 5 type arguments, but 1 given"
neg cache_wrong_key "argument 2 of 'set' (the parameter 'k2') has type int, but str is expected"
neg await_non_task "only a task can be awaited, but this is int"
neg await_in_conditional "an await cannot be in either value of a conditional expression"
neg async_init "cannot be async"
neg invert_on_text "cannot use '~' on str"
neg neg_on_list "cannot use '-' on list[int]"
neg neg_without_marker "cannot use '-' on 'Box' objects"
neg neg_marker_arguments "the @neg method 'flip' must take nothing besides self and return the result"
neg neg_marker_no_result "the @neg method 'flip' must take nothing besides self and return the result"
neg rmul_without_marker "add a method marked @rmul to 'Box'"
neg sorted_no_lt "add a method marked @lt to 'Box'"
neg min_no_lt "add a method marked @lt to 'Box'"
neg sum_no_add "add a method marked @add to 'Box'"
neg sort_method_no_lt "sort() needs a list of numbers or text, or of objects of a class with a method marked @lt"
neg rmul_marker_arguments "the @rmul method 'times' must take exactly one argument besides self"
neg rmul_wrong_left "the left operand of * has type float, but int is expected"
neg set_item_without_marker "objects cannot be assigned by index"
neg frozen_item_assign "'bitarray.frozenbitarray' objects cannot be assigned by index"
neg import_builtin_part "cannot find the module 'sorting'"
neg mixed_bit_types "the right operand of & has type bitarray.frozenbitarray"
neg frozen_bits_field "the field 'bits' is private to class 'bitarray.frozenbitarray'"
neg async_arg_of_plain_call "'f' is async, so it must be awaited or started"
neg gather_no_results "gather() gives the results of the tasks, but these tasks give none"
neg generic_async_arg_not_started "'f' is async, so it must be awaited or started"
neg async_override_mismatch "must take and return the same types"
neg for_async_iter "needs async for"
neg fn_arity "takes 1 argument, but 2 given"
neg fn_argtype "fn(str) -> str, but fn(int) -> int is expected"
neg fn_capture "cannot use the variable 'k'"
neg fn_equal "cannot use '==' with fn(int) -> int"
neg fn_printit "cannot be printed"
neg fn_sortboth "not both"
neg fn_sortkey "key= needs a function of one int item"
neg fn_maptype "map() needs a function of one str item"
neg fn_lamnoctx "a lambda needs to know its parameter types"
neg list_equal_objects "cannot use '==' on list[Dot]"
neg list_equal_types "cannot use '==' with list[int] and list[str]"
neg list_pop_args "pop() takes at most 1 argument"
neg list_extend_type "a list item has type str, but int is expected"
neg tuple_pop "a tuple cannot be changed, so it has no 'pop'"
neg fstring_text_sign "a format spec for text cannot have a sign"
neg fstring_text_comma "a format spec for text cannot have a ','"
neg fstring_text_number_type "the format type 'd' is for numbers, but this value is text"
neg fstring_number_text_type "the format type 's' is for text, but this value is int"
neg fstring_int_precision "a format spec for an int cannot have a precision unless its type is f, e or g"
neg fstring_float_whole_type "the format type 'd' is for whole numbers, but this value is float"
neg fstring_bool_spec "a format spec needs a text, an int or a float, but this value is bool"
neg fstring_list_spec "a format spec needs a text, an int or a float, but this value is list[int]"
neg round_bad_type "round() takes an int or a float, but this is str"
neg round_no_args "round() takes a number and optionally ndigits"
neg round_three_args "round() takes a number and optionally ndigits"
neg divmod_float "argument 1 of 'divmod' (the parameter 'a') has type float, but int is expected"
neg any_ints "a list item has type int, but bool is expected"
neg zfill_missing_width "'zfill' needs a value for 'width'"
neg center_bad_fill "argument 2 of 'center' (the parameter 'fillchar') has type int, but str is expected"
neg text_no_such_method "text has no method 'zfilll'"
neg type_arg_count "'list' does not take several types here"
neg type_in_unknown "this type is not supported here"
neg assert_not_bool "a condition has type int, but bool is expected"
neg assert_tuple "a condition has type tuple[bool, str], but bool is expected"
neg assert_message_not_text "argument 1 of AssertionError has type int, but str is expected"
neg test_on_async "is marked @test.waits, but it is async, and async tests are not supported yet" test
neg test_with_parameter "is marked @test.adds, so it must take no parameters and return nothing" test
neg test_with_result "is marked @test.adds, so it must take no parameters and return nothing" test
neg duplicate_test_name "'adds' is defined twice in module 'main'" test
neg test_none_marked "no function is marked @test" test
neg test_bare_repeated "'one' and 'two' are both marked @test" test
neg entry_main_repeated "'first' and 'second' are both marked @main"
neg entry_dotted_repeated "'loud' and 'shout' are both marked @greet.loud" greet
neg entry_group_with_input "the function 'loud' is marked @greet.loud, and the entry 'greet' runs several functions, so it must take no inputs" greet
neg entry_group_async "the function 'late' is marked @greet.late, and the entry 'greet' runs several functions, so it must take no inputs and cannot be async" greet
neg entry_group_result "an entry point (a function marked with @main or similar) cannot return a value" greet
neg entry_dotted_unmatched "no function is marked @greet.whisper" greet.whisper
neg entry_dotted_unmatched_test "no function is marked @test.missing" test.missing
neg entry_marker_dot_end "expected a name" greet

# ---- input --------------------------------------------------------------------------------------------------------------
t_input() {
  f="$1"; n="$(basename "$f" .tom)"
  "$c1" "$f" main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" "$rt_o" -pthread -lm || { bad "input $n" "did not build: $(cat "$work/e")"; return; }
  "$work/i" < "tests/input/$n.in" > "$work/o" 2>&1
  if cmp -s "$work/o" "tests/input/$n.out"; then ok "input $n"; else bad "input $n" "$(diff "$work/o" "tests/input/$n.out" | head -6)"; fi
  if [ -n "$have_js" ]; then
    tjsc site/wasm run "$f" "tests/input/$n.in" > "$work/js.out" 2> "$work/js.err"
    if [ "$(cat "$work/js.out" "$work/js.err" | grep -v '^~rc ')" = "$(cat "tests/input/$n.out")" ]; then ok "wasm input $n"; else bad "wasm input $n" "$(cat "$work/js.out" "$work/js.err" | head -6)"; fi
  fi
}
section "== input (tests/input: the file NAME.in is the standard input, NAME.out the whole output) =="
for f in tests/input/*.tom; do spawn t_input "$f"; done

# The writer leaves a partial line in the pipe while a socket exchange and an input timeout run. The cancelled
# reader must leave that partial line for the next waiter; a second buffered line and EOF must also be delivered.
t_input_concurrent() {
  "$c1" tests/input_concurrent.tom main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" "$rt_o" -pthread -lm || { bad "input overlaps I/O" "did not build: $(cat "$work/e")"; return; }
  start_httpd || { bad "input overlaps I/O" "test server did not build"; return; }
  (printf 'par'; i=0; while ! grep -q 'timed out' "$work/o" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; printf 'tial\nnext\n') | "$work/i" "http://127.0.0.1:$port" > "$work/o" 2>&1
  kill "$httpd_pid" 2>/dev/null
  # The request and socket may finish in either order, but both must finish before the timeout and input.
  first="$(sed -n '1,2p' "$work/o" | sed 's/^first? //' | sort)"
  rest="$(sed -n '3,$p' "$work/o")"
  check "input overlaps I/O" "$(printf 'http 200\nreceived socket')
timed out
second? line: partial
next: next
end" "$first
$rest"
}
spawn t_input_concurrent

t_input_timer() {
  "$c1" tests/input_timer.tom main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" "$rt_o" -pthread -lm || { bad "input overlaps a timer without network" "did not build: $(cat "$work/e")"; return; }
  (printf 'par'; i=0; while ! grep -q 'timed out' "$work/o" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; printf 'tial\n') | "$work/i" > "$work/o" 2>&1
  check "input overlaps a timer without network" "first? timed out
second? line: partial" "$(cat "$work/o")"
}
spawn t_input_timer

t_input_fair() {
  "$c1" tests/input_fair.tom main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" "$rt_o" -pthread -lm || { bad "input with zero sleeps" "did not build: $(cat "$work/e")"; return; }
  (printf 'ready\npar'; i=0; while ! grep -q 'timed out' "$work/o" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; printf 'tial\n') | "$work/i" > "$work/o" 2>&1
  check "input with zero sleeps" "first? got ready False
waiting? timed out False
next? line partial" "$(cat "$work/o")"
}
spawn t_input_fair

t_input_traffic() {
  "$c1" tests/input_traffic.tom main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" "$rt_o" -pthread -lm || { bad "input with socket traffic" "did not build: $(cat "$work/e")"; return; }
  # an endless socket exchange must not keep a waiting input from a line that is already there
  out="$(printf 'ready\n' | "$work/i" 2>&1)"
  check "input with socket traffic" "ready? line ready" "$out"
}
spawn t_input_traffic

t_input_ask() {
  "$c1" tests/input_ask.tom main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" "$rt_o" -pthread -lm || { bad "input asks last" "did not build: $(cat "$work/e")"; return; }
  # with no answer in the pipe, the host is asked (exit 75) only after the task that was due has printed
  out="$(TOMATO_INPUT_ASK=1 "$work/i" < /dev/null 2>&1; echo "rc=$?")"
  check "input asks last" "tick
ready? rc=75" "$out"
}
spawn t_input_ask

# ---- error ids ----------------------------------------------------------------------------------------------------------
# The case tables and the width tables (and, against Python itself, the isalpha/isdigit tables) in runtime/tomato_rt.c are written by tools/gen_case_table.py and tools/gen_width_table.py
# from Python's unicodedata (Unicode 16.0.0 = Python 3.14): each generator is run in --check mode and must find the file current.
# A Python with another Unicode version cannot say (the generators exit 2 and name the version they need): that is a skip locally
# and a failure in CI, as for jsc.
t_generated_tables() {
  py=""
  for p in python3.14 python3; do
    command -v "$p" >/dev/null 2>&1 && [ "$("$p" -I -c 'import unicodedata; print(unicodedata.unidata_version)' 2>/dev/null)" = "16.0.0" ] && { py="$p"; break; }
  done
  if [ -z "$py" ]; then
    [ -n "$CI" ] && bad "generated tables" "a Python 3.14 (Unicode 16.0.0) is required in CI: the case and width tables cannot be checked" || echo "skip: no Python with Unicode 16.0.0 (Python 3.14) to check the generated case and width tables"
    return
  fi
  for g in case width; do
    if r="$("$py" -I "tools/gen_${g}_table.py" --check runtime/tomato_rt.c 2>&1)"; then ok "generated $g tables in runtime/tomato_rt.c are what tools/gen_${g}_table.py makes"
    else bad "generated $g tables" "$r (rewrite with: python3.14 -I tools/gen_${g}_table.py runtime/tomato_rt.c)"; fi
  done
  # the letter and digit tables come from tools/gen_ctype_table.c (UnicodeData.txt); here they are checked against Python's own str.isalpha/isdigit
  if r="$("$py" -I tools/check_ctype_table.py runtime/tomato_rt.c 2>&1)"; then ok "isalpha/isdigit tables in runtime/tomato_rt.c agree with Python 3.14 (tools/check_ctype_table.py)"
  else bad "isalpha/isdigit tables" "$r (regenerate with tools/gen_ctype_table.c, see its header)"; fi
}
t_error_templates() {
  tests/error_templates.sh | awk '{ l=$0; gsub(/\{\}/,"",l); if (length(l) >= 12) print }' > "$work/templates"
  missing=""
  while IFS= read -r tpl; do grep -qxF "CompileError $tpl" std/errors.txt || missing="$missing
  $tpl"; done < "$work/templates"
  [ -z "$missing" ] && ok "every extracted compile error template has an id in std/errors.txt" || bad "every extracted compile error template has an id in std/errors.txt" "add these lines (CompileError TEMPLATE):$missing"
}
# sys.version() is a literal in std/sys.tom (and its copy for the website) that the release script's bump step rewrites: it must say what VERSION says
t_sys_version() {
  v="$(cat VERSION)"
  wrong=""
  for f in std/sys.tom site/wasm/std/sys.tom; do
    got="$(awk '/^export def version\(\)/ { inside = 1; next } inside && /return / { gsub(/^[^\047]*\047|\047.*$/, ""); print; exit }' "$f")"
    [ "$got" = "$v" ] || wrong="$wrong $f says '$got' but VERSION says '$v';"
  done
  [ -z "$wrong" ] && ok "sys.version() says what VERSION says" || bad "sys.version() says what VERSION says" "$wrong"
}
t_error_raises() {
  missing="$(awk '
    NR == FNR { classes[NR] = $1; next }
    (/raise [A-Z][[:alnum:]_]*\(/ || /return [A-Z][[:alnum:]_]*Error\(/) && !/^ *#/ {   # (a function that makes an error returns it)
      line = $0
      sub(/^.*(raise|return) /, "", line)
      sub(/\(.*/, "", line)
      if (!match($0, /\047E[0-9]+\047\)$/) || classes[substr($0, RSTART + 2, RLENGTH - 4) + 0] != line)
        print FILENAME ":" FNR ": " $0
    }' std/errors.txt std/*.tom std/builtin/*.tom)"
  [ -z "$missing" ] && ok "standard-library raises have IDs for their classes" || bad "standard-library raises have IDs for their classes" "$missing"
}
t_builtin_folder() { # every file of std/builtin/ is a part of the built-ins or a module found there (builtin_parts and builtin_modules
  # in the compiler), and the website loads it (TomatoWasm.STD in site/wasm/tomato.js)
  names="$(sed -n -e '/^def builtin_parts()/,/return/p' -e '/^def builtin_modules()/,/return/p' compiler/src/compiler.tom | sed -n 's/^ *return \[//p' | tr -d "]',")"
  missing=""
  for f in std/builtin/*.tom; do
    n="$(basename "$f" .tom)"
    case " $(echo $names) " in *" $n "*) ;; *) missing="$missing $f(not named in compiler.tom)";; esac
    grep -q "\"builtin/$n\"" site/wasm/tomato.js || missing="$missing $f(not in TomatoWasm.STD)"
  done
  for n in $names; do [ -f "std/builtin/$n.tom" ] || missing="$missing std/builtin/$n.tom(missing)"; done
  [ -z "$missing" ] && ok "std/builtin/ matches the compiler's list and the website's" || bad "std/builtin/ matches the compiler's list and the website's" "$missing"
}
t_std_modules() { # std_modules() in the compiler (the help of "cannot find the module") lists every module of std/
  names="$(sed -n '/^\(export \)\{0,1\}def std_modules()/,/return/p' compiler/src/compiler.tom | sed -n 's/^ *return \[//p' | tr -d "]',")"
  have="$(ls std/*.tom std/builtin/bitarray.tom | sed 's#.*/##; s#\.tom$##' | sort | tr '\n' ' ')"
  [ "$(echo $names | tr ' ' '\n' | sort | tr '\n' ' ')" = "$have" ] && ok "std_modules lists the modules of std/" || bad "std_modules lists the modules of std/" "compiler: $names / std: $have"
}
section "== error ids =="
spawn_free t_error_templates
spawn_free t_generated_tables
spawn_free t_error_raises
spawn_free t_sys_version
spawn_free t_builtin_folder
spawn t_std_modules

# ---- error messages -----------------------------------------------------------------------------------------------------
t_error_text() {
  f="$1"; n="$(basename "$f" .tom)"; "$c1" "$f" main std/ > "$work/err.ll" 2> "$work/err.out"
  grep '^;! ' "$work/err.ll" | sed 's/^;! //' >> "$work/err.out"   # warnings travel as comment lines at the end of the IR
  if cmp -s "$work/err.out" "tests/errors/$n.out"; then ok "error text: $n"; else bad "error text: $n" "$(diff "$work/err.out" "tests/errors/$n.out" | head -6)"; fi
}
section "== error messages (tests/errors: the whole text, the one format everywhere) =="
for f in tests/errors/*.tom; do spawn t_error_text "$f"; done

# ---- runtime errors -----------------------------------------------------------------------------------------------------
t_rt() { # file, expected stderr text, expected exit status
  "$c1" "tests/runtime/$1.tom" main std/ > "$work/r.ll" 2>/dev/null && clang -O1 -w -o "$work/r" "$work/r.ll" "$rt_o" -pthread -lm || { bad "runtime $1" "did not build"; return; }
  "$work/r" > "$work/o" 2> "$work/e2"; code=$?
  case "$(cat "$work/o" "$work/e2")" in *"$2"*) [ "$code" = "$3" ] && ok "runtime $1" || bad "runtime $1" "exit status $code, wanted $3";; *) bad "runtime $1" "wanted '$2', got: $(cat "$work/o" "$work/e2")";; esac
}
rt() { spawn t_rt "$@"; }
section "== runtime errors and modes =="
rt divide_by_zero "division by zero" 1
rt optional_int_none "None where a value is needed" 1
rt optional_float_none "None where a value is needed" 1
rt optional_narrow_ended "None where a value is needed" 1
rt dict_remove_missing "the key is not in the dict" 1
rt index "index out of range" 1
rt overflow "integer overflow" 1
rt shift_negative "negative shift count" 1
rt shift_huge "the shift count is too big" 1
rt shift_overflow "does not fit" 1
rt caught "caught boom" 0
rt async_unread "in a task nobody awaited" 1
rt async_lock_deadlock "task 1 is waiting at line 6 for a lock held since line 5" 1
rt async_lock_deadlock_task "task 2 is waiting at line 4 for a lock held since line 9" 1
rt dict_missing_key "the key is not there" 1
rt set_missing "the element is not there" 1
rt rational_zero "a rational cannot have a zero denominator" 1
rt progress_bar_live "live: 100%|####| 2/2" 0
rt negative_exponent "a negative exponent needs a float" 1
rt stack_overflow "stack overflow" 1
rt tan_quarter "tan is not defined at 90 deg" 1
rt sqrt_negative "sqrt needs a number that is not negative, but got -4.0" 1
rt asin_domain "asin needs a number from -1 to 1, but got 1.5" 1
rt atan2_origin "atan2(0, 0) has no angle" 1
rt float_pow_too_large "the result is too large to calculate: its exponent would have more than 65536 bits" 1
rt exp_large "1.970071114017047e+434" 0
rt log_zero "log needs a positive number, but got 0.0" 1
rt log_base_zero "a logarithm base must be positive and not 1, but got 0.0" 1
rt caught_domain "caught sqrt needs a number that is not negative" 0
rt error_subclass_uncaught "error: Missing: the file is gone (raised on line 9)" 1
rt angle_base "Angle is a base class" 1
rt chr_range "chr() takes a number from 0 to 1114111, not a surrogate" 1
rt ord_length "ord() takes a text of exactly one character" 1
rt chr_huge "chr() takes a number from 0 to 1114111, not a surrogate" 1
rt msgpack_missing "error[E25]: IOError: could not open '/nonexistent_dir_for_tomato/missing.msgpack': No such file or directory" 1
[ -e /dev/full ] && rt text_write_full_disk "E382 could not write to the file: No space left on device" 0
[ -e /dev/full ] && rt text_close_full_disk "E382 could not write to the file when closing it: No space left on device" 0
[ -e /dev/full ] && rt msgpack_full_disk "E382 could not write '/dev/full': No space left on device" 0
rt trace_calls "at half (line 10)" 1
rt list_pop_empty "pop from an empty list" 1
rt error_classes "$(cat tests/runtime/error_classes.out)" 0
rt error_class_uncaught "error[E04]: index out of range" 1
rt error_std_uncaught "error[E51]:" 1
rt url_bad_ipv6 "error[E390]: ValueError: Invalid IPv6 URL" 1
rt url_ipv4_in_brackets "An IPv4 address cannot be in brackets" 1
rt base64_bad_char "error[E392]: ValueError: the base64 text has a character that is not in the base64 alphabet" 1
rt base64_bad_padding "error[E393]: ValueError: the base64 text has the wrong length or misplaced padding" 1
rt base64_bad_byte "error[E391]: ValueError: a byte must be a whole number from 0 to 255, but got 256" 1
rt hex_odd_length "error[E394]: ValueError: a hex text needs an even number of digits, but got 3" 1
rt hex_bad_digit "error[E395]: ValueError: a hex text holds only the digits 0-9 and a-f, but got 'g'" 1
rt csv_bad_delimiter "error[E408]: ValueError: a CSV delimiter must be one character" 1
rt csv_unclosed_quote "error[E410]: ValueError: a quoted CSV field is not closed" 1
rt csv_after_quote "error[E409]: ValueError: a closing quote in CSV text must be followed by" 1
rt csv_extra_fields "error[E411]: ValueError: a CSV row has 3 fields, but the header has 2" 1
rt textwrap_width "error[E412]: ValueError: textwrap needs a width of at least 1, but got 0" 1
rt textwrap_placeholder "error[E413]: ValueError: the placeholder is too large for the width 3" 1
rt statistics_empty "error[E414]: ValueError: statistics needs at least one data point" 1
rt statistics_one_point "error[E415]: ValueError: statistics needs at least two data points" 1
rt statistics_quantiles_n "error[E416]: ValueError: quantiles needs n of at least 1, but got 0" 1
rt datetime_errors "$(cat tests/runtime/datetime_errors.out)" 0
rt datetime_overflow "error[E407]: OverflowError: date value out of range" 1
rt divmod_zero "division by zero" 1
rt partition_empty "partition needs a separator that is not empty" 1
rt rpartition_empty "rpartition needs a separator that is not empty" 1
rt fill_length "center needs a fill character of exactly one character" 1
rt fill_empty "ljust needs a fill character of exactly one character" 1
rt factorial_negative "factorial needs a number that is not negative, but got -1" 1
rt comb_negative "comb needs numbers that are not negative, but got 5 and -1" 1
rt perm_negative "perm needs numbers that are not negative, but got -5 and 2" 1
rt isqrt_negative "isqrt needs a number that is not negative, but got -4" 1
rt text_math_caught "$(cat tests/runtime/text_math_caught.out)" 0
rt file_closed_uncaught "error[E547]: I/O operation on a closed file" 1
rt assert_failed "error[E519]: AssertionError: x should be 4, but is 3 (raised on line 3)" 1
rt assert_default "error[E519]: AssertionError: assertion failed (raised on line 5)" 1
t_exit_status() { # sys.exit: the status, what is flushed (print and write_stdout), and what does not run (finally, the code after)
  for t in exit_status:3 exit_default:0; do
    n="${t%%:*}"; want_code="${t#*:}"
    "$c1" "tests/runtime/$n.tom" main std/ > "$work/x.ll" 2>/dev/null && clang -O1 -w -o "$work/x" "$work/x.ll" "$rt_o" -lm || { bad "sys.exit $n" "did not build"; continue; }
    out="$("$work/x" 2>&1)"; code=$?
    case "$n" in exit_status) want_out="$(printf 'before\npending ')" ;; *) want_out="partial line" ;; esac
    check "sys.exit $n: output" "$want_out" "$out"
    check "sys.exit $n: status" "$want_code" "$code"
  done
}
spawn t_exit_status

t_no_entropy() {
  n="$1"
  "$c1" "tests/runtime/$n.tom" main std/ > "$work/r.ll" 2>/dev/null && clang -O1 -w -o "$work/r" "$work/r.ll" "$(rtcache_get "$work" o "$root/runtime/tomato_rt.c" -O1 -pthread -w -DTOMATO_TEST_NO_ENTROPY)" -pthread -lm || { bad "runtime $n" "did not build"; return; }
  "$work/r" > "$work/o" 2> "$work/e2"; code=$?
  case "$(cat "$work/o" "$work/e2")" in *"secure random bytes are not available on this system"*) [ "$code" = 1 ] && ok "runtime $n" || bad "runtime $n" "exit status $code, wanted 1";; *) bad "runtime $n" "wanted the entropy error, got: $(cat "$work/o" "$work/e2")";; esac
}
section "== random, secrets and uuid (std/random.tom, std/secrets.tom, std/uuid.tom) =="
for ent in random_randint_empty:"randint needs a <= b, but got 3 and 2" random_zero_step:"randrange needs a step that is not zero" random_sample_size:"sample needs a size from 0 to 2, but got 3" random_choice_empty:"choice needs a list that is not empty" secrets_negative_length:"token_bytes needs a length of 0 or more, but got -1" secrets_bound_zero:"randbelow needs a bound above 0, but got 0" uuid_bad_text:"a UUID text needs 32 hexadecimal digits, but got not-a-uuid"; do
  rt "${ent%%:*}" "${ent#*:}" 1
done
# a runtime built with TOMATO_TEST_NO_ENTROPY has no secure entropy: secrets and uuid4 must stop, never fall back to a generator
for ent in secrets_no_entropy uuid4_no_entropy; do spawn t_no_entropy "$ent"; done
# the same seed gives the same numbers in the browser's path as natively, and the entropy comes through WASI random_get
if [ -n "$have_js" ]; then
  for name in random_basic random_lists secrets_basic uuid_basic; do wasm_program "$name"; done
  wasm_rt random_randint_empty "randint needs a <= b, but got 3 and 2" 1
  wasm_rt secrets_negative_length "token_bytes needs a length of 0 or more, but got -1" 1
fi

# ---- known gaps ---------------------------------------------------------------------------------------------------------
# Each file is a program a decision says must be rejected (should_reject_*) or must work (should_work_*). The test passes
# while the gap exists and FAILS when the compiler gains the behavior, so the list cannot go stale: then move the program
# to tests/negative or tests/programs.
t_gap() {
  f="$1"; n="$(basename "$f" .tom)"
  accepted=no
  if "$c1" "$f" main std/ > "$work/g.ll" 2>/dev/null && clang -O1 -w -o "$work/g" "$work/g.ll" "$rt_o" -pthread -lm 2>/dev/null; then
    accepted=yes; "$work/g" > /dev/null 2>&1 || accepted=fails
  fi
  case "$n" in
    should_reject_*) [ "$accepted" = no ] && bad "known gap closed: $n" "move it to tests/negative" || ok "known gap: $n (still accepted)";;
    should_work_*) [ "$accepted" = yes ] && bad "known gap closed: $n" "move it to tests/programs" || ok "known gap: $n (still unsupported)";;
  esac
}
section "== known gaps (decided behavior the compiler does not have yet) =="
for f in tests/known_gaps/*.tom; do spawn t_gap "$f"; done

# ---- release files ------------------------------------------------------------------------------------------------------
t_docs_in_sync() { for d in specification decisions decision-inventory open-questions; do cmp -s "docs/$d.md" "site/docs/$d.md" && ok "site/docs/$d.md is in sync" || bad "site/docs/$d.md is in sync" "run site/build.sh"; done; }
t_release_pkg() { # macOS only, and serial (last): it builds the installer package and a disk image, which mounts it
  fake="$work/fake"; mkdir -p "$fake"
  TOMATO_RELEASE_OUT="$fake/out" sh release/build.sh "file://$fake/t.tar.gz" > /dev/null
  TOMATO_RELEASE_OUT="$fake/out" sh release/pkg.sh > /dev/null 2>&1; pkg="$(ls "$fake"/out/tomato-*.pkg 2>/dev/null)"
  if [ -n "$pkg" ] && pkgutil --expand-full "$pkg" "$work/pkgx" 2>/dev/null; then
    pp="$work/pkgx/component.pkg/Payload"
    check "pkg: the compiler is universal" "arm64 x86_64" "$(lipo -archs "$pp/usr/local/lib/tomato/native/bin/tomatoc" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
    check "pkg: the repl line editor is universal" "arm64 x86_64" "$(lipo -archs "$pp/usr/local/lib/tomato/native/bin/tomato-repl-edit" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
    check "pkg: /usr/local/bin/tomato is a relative link into the install" "../lib/tomato/native/bin/tomato" "$(readlink "$pp/usr/local/bin/tomato")"
    check "pkg: the installed command runs" "Tomato v$(cat VERSION) (compiler written in Tomato)" "$("$pp/usr/local/bin/tomato" version)"
    check "pkg: the installed command compiles and runs a program" "fib 12 = 144" "$("$pp/usr/local/bin/tomato" run examples/compiled.tom main 12 2>&1 | head -1)"
  # an update-style reinstall into a package layout with a read-only bin folder must not fail at the link step
  if [ -d "$work/pkgx" ]; then
    u="$work/upd"; mkdir -p "$u/lib/tomato" "$u/bin"; cp -R "$work/pkgx/component.pkg/Payload/usr/local/lib/tomato/native" "$u/lib/tomato/native"
    ln -s ../lib/tomato/native/bin/tomato "$u/bin/tomato"; chmod 555 "$u/bin"
    r="$(TOMATO_HOME="$u/lib/tomato" TOMATO_BIN="$u/bin" sh install-native.sh 2>&1)"; rc=$?; chmod 755 "$u/bin"
    check "pkg: a reinstall (tomato update) works with a root-owned bin folder" "0" "$rc"
  fi
  else bad "pkg: builds and expands"; fi
  # the disk image around the package, unsigned (a release signs, notarizes and staples it); run twice, as a resumed release would
  if [ -n "$pkg" ]; then
    lj="$fake/out/latest.json"; tsum="$(shasum -a 256 "$fake"/out/tomato-*.tar.gz | cut -d' ' -f1)"
    if TOMATO_NO_SIGN=1 TOMATO_LATEST_JSON="$lj" sh release/dmg.sh "$pkg" "$work/t.dmg" > "$work/dmg.log" 2>&1 &&
       TOMATO_NO_SIGN=1 TOMATO_LATEST_JSON="$lj" sh release/dmg.sh "$pkg" "$work/t.dmg" > "$work/dmg.log" 2>&1; then
      ok "dmg: builds, and holds exactly the package (dmg.sh mounts it and compares)"
      check "dmg: latest.json records the image's sha256" "$(shasum -a 256 "$work/t.dmg" | cut -d' ' -f1)" "$(sed -n 's/.*"dmg_sha256" *: *"\([^"]*\)".*/\1/p' "$lj")"
      plutil -convert xml1 -o /dev/null "$lj" 2>/dev/null && ok "dmg: latest.json is still valid JSON" || bad "dmg: latest.json is still valid JSON" "$(cat "$lj")"
      check "dmg: latest.json keeps all seven keys" "7" "$(grep -c -E '^  "(version|url|sha256|pkg_url|pkg_sha256|dmg_url|dmg_sha256)":' "$lj")"
      # tomato update reads "url" and "sha256" with these same patterns (native/tomato): the new keys must not shadow them
      check "dmg: tomato update still reads the tarball's sha256" "$tsum" "$(sed -n 's/.*"sha256" *: *"\([^"]*\)".*/\1/p' "$lj" | head -1)"
    else bad "dmg: builds, and holds exactly the package" "$(tail -3 "$work/dmg.log")"; fi
  fi
}
section "== release files =="
spawn_free t_docs_in_sync
if [ "$(uname)" = Darwin ] && command -v pkgbuild >/dev/null 2>&1; then last t_release_pkg; fi   # the macOS installer package

# ---- benchmarks and the rest --------------------------------------------------------------------------------------------
# One benchmark at a time (so they run beside the other tests): benchmarks/run.sh --smoke builds it in Tomato and in the other languages and
# checks that every version prints what Tomato's prints. The inputs are tiny and nothing is timed, so it does not matter what else runs.
# It uses the compiler built above (c1, the same program as the one benchmarks/run.sh would build from the bootstrap IR).
t_benchmark() { # name, the languages
  # a missing toolchain is skipped by benchmarks/run.sh, with a "skipping" line: that must not fail the test
  out="$(sh benchmarks/run.sh --smoke --langs "$2" --only "$1" --out "$work/results" --tomatoc "$c1" 2>&1)"; rc=$?
  line="$(printf '%s\n' "$out" | grep '^ok: every benchmark prints the same in ' | tail -1)"
  if [ $rc -eq 0 ] && [ -n "$line" ]; then
    skipped="$(printf '%s\n' "$out" | sed -n 's/^skipping \([a-z]*\):.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
    ok "benchmarks: $1 prints the same (${line#ok: every benchmark prints the same in }${skipped:+; skipped, not installed: $skipped})"
  else bad "benchmarks: $1 prints the same" "$(printf '%s\n' "$out" | grep -v -e " done$" -e " built$" -e " runs$" | tail -20)"; fi
}
t_versions() {
  cmp -s docs/provisional.md site/docs/PROVISIONAL.md && ok "site/docs/PROVISIONAL.md is in sync" || bad "site/docs/PROVISIONAL.md is in sync" "run site/build.sh"
  # a stable VERSION is in site/latest.json and site/config.js; a pre-release (1.1.0-rc.1) in site/latest-pre.json, while those two keep
  # the latest stable release (docs/releasing.md, Version numbers)
  man=site/latest.json; case "$(cat VERSION)" in *-*) man=site/latest-pre.json ;; esac
  check "VERSION matches $man" "$(cat VERSION)" "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' "$man" 2>/dev/null)"
  check "VERSION matches std/sys.tom (sys.version)" "$(cat VERSION)" "$(sed -n "s/^    return '\\([0-9A-Za-z.-]*\\)'\$/\\1/p" std/sys.tom | tail -1)"
  check "site/config.js matches site/latest.json" "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)" "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)"
  check "site/wasm matches the compiler IR and runtime" "$(cat compiler/bootstrap/tomatoc.ll runtime/tomato_rt.c | sha256 | cut -d' ' -f1)" "$(sed -n 1p site/wasm/SOURCE.sha256 2>/dev/null)"
  check "the checked-in wasm files are the ones that were built" "$(sed -n 2,3p site/wasm/SOURCE.sha256)" "$(sha256 site/wasm/tomatoc.wasm site/wasm/runtime.wasm | cut -d' ' -f1)"
}
t_wasm_sections() {
  # the wasm files must be the same on every host (site/wasm/build.sh): no debug sections, which name the SDK's build folder
  for f in tomatoc runtime; do
    sh site/wasm/sections.sh "site/wasm/$f.wasm" > "$work/sections" 2>&1 || bad "site/wasm/sections.sh reads $f.wasm" "$(tail -3 "$work/sections")"
    check "site/wasm/sections.sh accounts for every byte of $f.wasm" "$(wc -c < "site/wasm/$f.wasm" | tr -d ' ')" "$(awk '{ n += $2 } END { print n + 8 }' "$work/sections")"
    r="$(grep -E ' custom:\.debug|custom:external_debug' "$work/sections" | awk '{ print $4 }' | tr '\n' ' ')"
    [ -z "$r" ] && ok "$f.wasm has no debug sections (they differ between the macOS and Linux WASI SDKs)" || bad "$f.wasm has no debug sections" "found: $r
run site/wasm/build.sh (it links with --strip-debug) and commit"
  done
  # sections.sh names the section that differs: change one byte inside the data section of a copy
  sh site/wasm/sections.sh site/wasm/runtime.wasm > "$work/sections"
  awk '$4 == "data" { print $1 + $2 - 1 }' "$work/sections" > "$work/at"
  { head -c "$(cat "$work/at")" site/wasm/runtime.wasm; printf 'X'; tail -c "+$(($(cat "$work/at") + 2))" site/wasm/runtime.wasm; } > "$work/changed.wasm"
  r="$(sh site/wasm/sections.sh site/wasm/runtime.wasm "$work/changed.wasm" | sed 1d)"
  check "site/wasm/sections.sh names the section that differs" "  data: same size ($(awk '$4 == "data" { print $2 }' "$work/sections") bytes), different bytes" "$r"
  sh site/wasm/sections.sh site/wasm/runtime.wasm site/wasm/runtime.wasm && ok "site/wasm/sections.sh: identical files compare equal" || bad "site/wasm/sections.sh: identical files compare equal"
}
t_wasm_rebuild() { # serial (last): it rewrites site/wasm, which the other tests read
  cp -R site/wasm "$work/wasm_orig"
  if WASI_SDK="$WASI_SDK" sh site/wasm/build.sh > "$work/wasm_build.log" 2>&1; then
    r=""; for f in tomatoc runtime; do
      cmp -s "$work/wasm_orig/$f.wasm" "site/wasm/$f.wasm" || r="$r$(sh site/wasm/sections.sh "$work/wasm_orig/$f.wasm" "site/wasm/$f.wasm" | sed "s|$work/wasm_orig/$f.wasm|the committed $f.wasm|; s|site/wasm/$f.wasm|the rebuilt one|")
"; done
    [ -z "$r" ] && ok "wasm files rebuild identically" || bad "wasm files rebuild identically" "${r}the rebuilt files are now in site/wasm; docs/releasing.md (The wasm files) says what each kind of difference means"
  else bad "wasm files rebuild identically" "site/wasm/build.sh failed:
$(cat "$work/wasm_build.log")"; fi
}
section "== benchmarks (tiny inputs only; the real run is benchmarks/run.sh) =="
for b in $(grep -v '^#' benchmarks/sizes.txt | awk 'NF { print $1 }'); do
  case " fib sieve strings sort wordcount hof " in
    *" $b "*) if [ -n "$fast" ]; then register t long t_benchmark "$b" c,python; else register t long t_benchmark "$b" go,rust,python,c,javascript; fi ;;   # (the fast tier: six, and only C and Python besides Tomato)
    *) if [ -n "$fast" ]; then skip "benchmark $b"; else register t long t_benchmark "$b" go,rust,python,c,javascript; fi ;;
  esac
done
spawn_free t_versions
spawn_free t_wasm_sections
if [ -n "$WASI_SDK" ]; then last t_wasm_rebuild; fi   # with the toolchain, rebuild and compare byte for byte

run_all
t_end="$(date +%s)"
passes=0; fails=0
[ -f "$shared/passed" ] && passes=$(($(wc -l < "$shared/passed")))
[ -f "$shared/failed" ] && fails=$(($(wc -l < "$shared/failed")))
echo; echo "$passes passed, $fails failed"
if [ -n "$fast" ]; then   # the tests the fast tier did not run
  echo; echo "fast tier: $(printf '%s\n' "$skipped" | grep -c '^  ') tests were not run (tests/run.sh with no flag runs them all):$skipped"
fi
if [ -n "$times" ] && [ -s "$shared/times" ]; then   # --times: where the time goes (a test's time is its own, from start to end; tests overlap, so the run is shorter than the sum)
  # wall seconds depend on what else the machine is doing; the CPU seconds (user and system, of the test and everything it started) mostly do not
  echo; echo "slowest 20 tests (wall seconds, and CPU seconds), of the whole run's $((t_end - t_start)) s:"
  sort -t "$(printf '\t')" -rn -k1,1 "$shared/times" | head -20 | awk -F'\t' '{ s = $2; sub(/^== /, "", s); sub(/ ==$/, "", s); printf "%8.1f %8.1f  %s   [%s]\n", $1 / 1000, $4 / 1000, $3, substr(s, 1, 44) }'
  echo; echo "per section (seconds): wall and CPU summed over its tests, the slowest test (wall), the number of tests"
  awk -F'\t' '{ t[$2] += $1; u[$2] += $4; if ($1 > m[$2]) m[$2] = $1; c[$2]++ }
    END { for (k in t) { s = k; sub(/^== /, "", s); sub(/ ==$/, "", s); printf "%9.1f %9.1f %8.1f %5d  %s\n", t[k] / 1000, u[k] / 1000, m[k] / 1000, c[k], substr(s, 1, 60) } }' "$shared/times" | sort -rn
  awk -F'\t' '{ w += $1; u += $4; c++ } END { printf "\ntotal over %d tests: %.0f s wall (summed), %.0f s CPU. CPU is what the machine paid; wall includes waiting for cores.\n", c, w / 1000, u / 1000 }' "$shared/times"
  echo "load average at the end: $(cut -d' ' -f1 /proc/loadavg 2>/dev/null || uptime | sed 's/.*load averages*: //'), jobs: $jobs, cores: $cores"
fi
[ "$fails" -eq 0 ]
