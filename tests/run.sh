#!/bin/sh
# The test suite, in shell: it needs only clang. Usage: tests/run.sh [-j N] [--fast] [--times]
#   1. builds the compiler from compiler/bootstrap/tomatoc.ll and checks that it reproduces itself and that the
#      checked-in IR is current (the fixed point)
#   2. compiles and runs every example with the expected output in tests/expected
#   3. checks the command line (tomato run/build/compile/repl/update/version/help)
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
fast_asan=" at_neg_rmul float_ownership loop_lifetime fast_paths loop_nests shapes objects cycle gc_cycles containers modules native_sort function_values lambdas sort_stable str_fast alloc_pool text_index json_accept json_fuzz msgpack_basic bigint_ownership bigint_unwind toml_valid toml_api json_files msgpack_file_basics open_errors mixed_tuples compact_lists temp_unwind async_tasks async_cancel async_sync socket_local socket_udp error_path_release error_classes time_module web_modules datetime_arith csv_module re_api re_limits sys_args os_files file_lines file_loop_close string_io assert_ok testing_lib "
# What the AddressSanitizer tests build (PATH:ARGUMENT, see t_asan); a program that is also one of the "decided rules" programs is built
# once, with AddressSanitizer, for both tests (t_program_asan)
asan_specs1="tests/programs/at_neg_rmul: tests/programs/loop_lifetime: tests/programs/fast_paths: tests/programs/loop_nests: examples/shapes: examples/objects:4 tests/programs/cycle: tests/programs/gc_cycles: tests/programs/containers: tests/programs/modules: tests/programs/borrow_elision: tests/programs/native_sort: tests/programs/function_values: tests/programs/lambdas: tests/programs/sort_stable: tests/programs/sort_errors: tests/programs/sort_key_cmp: tests/programs/sort_cmp_native: tests/programs/str_fast: tests/programs/alloc_pool: tests/programs/text_index: tests/programs/fstring_fuse: tests/programs/cache_lru: tests/programs/cache_multi: tests/programs/memoize: tests/programs/bit_types: tests/programs/int_shift: tests/programs/big_shift: tests/programs/int_bitwise_big: tests/programs/bit_chunks: tests/programs/json_strict: tests/programs/json_accept: tests/programs/json_dumps: tests/programs/json_access: tests/programs/json_depth: tests/programs/json_utf8: tests/programs/json_fuzz: tests/programs/msgpack_basic: tests/programs/msgpack_errors: tests/programs/msgpack_fuzz: tests/programs/bigint_ownership: tests/programs/bigint_ops: tests/programs/bigint_frames: tests/programs/bigint_unwind: tests/programs/big_numbers: tests/programs/big_mul: tests/programs/big_decimal: tests/programs/big_karatsuba: tests/programs/big_ntt: tests/programs/big_division: tests/programs/int_bitwise_runs: tests/programs/big_bad_text: tests/programs/int64_convert: tests/programs/unlimited_int: tests/programs/toml_valid: tests/programs/toml_invalid: tests/programs/toml_api:WORK tests/programs/json_files:WORK tests/programs/msgpack_files:WORK tests/programs/msgpack_file_basics:WORK tests/runtime/msgpack_full_disk: tests/programs/open_errors: tests/programs/unicode_case: tests/programs/unicode_case_full: tests/programs/unicode_class: tests/programs/mixed_tuples: tests/programs/tuple_type_args: tests/programs/union_show: tests/programs/toml_big: tests/programs/compact_lists: tests/programs/compact_fuzz: tests/programs/temp_unwind: tests/programs/text_dict_methods: tests/programs/dict_literal_inference: tests/programs/dict_keys_any: tests/programs/dict_keys_objects: tests/programs/dict_keys_forms: tests/programs/dict_keys_cycles: tests/programs/tuple_for: tests/programs/list_methods: tests/programs/utf8_invalid: tests/programs/async_tasks: tests/programs/async_cancel: tests/programs/async_sleep: tests/programs/async_toolkit: tests/programs/async_sync: tests/programs/async_queue_drop: tests/programs/async_gc_release: tests/programs/socket_local: tests/programs/socket_udp: tests/programs/socket_fair: tests/programs/error_path_release: tests/programs/int_ranges: tests/programs/range_wide: tests/programs/int_to_float: tests/programs/float_any_size: tests/programs/float_floor_mod: tests/programs/float_ownership: tests/programs/float_loops: tests/programs/float_keys: tests/programs/float_nests: tests/programs/float_library: tests/programs/fast_ranges: tests/runtime/error_classes: tests/programs/time_module: tests/programs/url_parse: tests/programs/url_quote: tests/programs/html_escape: tests/programs/base64_codec: tests/programs/hex_codec: tests/programs/web_modules: tests/programs/html_fuzz: tests/programs/web_large: tests/programs/datetime_arith: tests/programs/datetime_format: tests/programs/datetime_parse: tests/runtime/datetime_errors: tests/programs/csv_module: tests/programs/textwrap_module: tests/programs/statistics_module:"
asan_specs2="tests/programs/sys_args:7  tests/programs/os_env: tests/programs/os_files:WORK tests/programs/ospath_text: tests/programs/file_lines:WORK tests/programs/file_loop_close:WORK tests/programs/file_modes:WORK tests/programs/bytes_files:WORK tests/programs/string_io: tests/programs/re_api: tests/programs/re_limits: tests/programs/hashlib_vectors: tests/programs/struct_ints: tests/programs/struct_floats: tests/programs/struct_float_sweep: tests/programs/wave2_bytes: tests/programs/hmac_vectors: tests/programs/round_divmod_any_all: tests/programs/text_methods_more: tests/programs/math_more: tests/programs/fstring_specs: tests/runtime/text_math_caught: tests/programs/assert_ok: tests/programs/testing_lib:"
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
  arg=""; case "$name" in toml_api|json_files|msgpack_files|msgpack_file_basics|os_files|file_lines|file_loop_close|file_modes|bytes_files) arg="$work" ;; sys_basics) arg="alpha" ;; sys_args) arg="7 b c" ;; esac   # they write files: into this test's own folder, not a shared /tmp; the sys programs take inputs
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
  arg=""; case "$name" in toml_api|json_files|msgpack_files|msgpack_file_basics|os_files|file_lines|file_loop_close|file_modes|bytes_files) arg="$work" ;; sys_basics) arg="alpha" ;; sys_args) arg="7 b c" ;; esac   # they write files: into this test's own folder, not a shared /tmp; the sys programs take inputs
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
  "$c1" "tests/programs/$1.tom" main std/ release > "$work/p.ll" 2> "$work/e"
  if clang -O1 -w -g -fsanitize=address -o "$work/rel" "$work/p.ll" "$rt_asan" -pthread -lm 2>/dev/null; then
    if [ "$2" = leaks ]; then "$work/rel" > "$work/out" 2> "$work/e"; cat "$work/e" >> "$work/out"
    else ASAN_OPTIONS=detect_leaks=0 "$work/rel" > "$work/out" 2> "$work/e"; grep -v "never freed" "$work/e" >> "$work/out"; fi
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
for name in fast_paths loop_nests float_loops float_nests int_ranges int_fast_paths small_int_loops int_boundary temp_unwind native_sort compact_lists containers raise_paths raise_dead; do
  case "$name" in fast_paths|loop_nests|float_loops|float_nests|int_ranges|containers|raise_paths|raise_dead) ;; *) [ -n "$fast" ] && { skip "release $name"; continue; } ;; esac   # (the fast tier: eight of the fourteen)
  case "$name" in fast_paths|loop_nests|float_loops|float_nests|raise_paths|raise_dead) spawn_first t_release_asan "$name" leaks ;; *) spawn_first t_release_asan "$name" ;; esac
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
  printf 'from testing import assert_equal, skip\n\n@test\ndef adds():\n    assert_equal(1 + 1, 2)\n\n@test\ndef fails():\n    assert_equal(1 + 1, 3)\n\n@test\ndef lookup():\n    skip("no network")\n' > "$work/wt.tom"
  m="$(tjsc site/wasm run "$work/wt.tom" --entry=test 2>&1 | grep -v '^Could not open file: ')"   # real jsc's read() prints that on standard error for each std module it looks for beside the program, caught or not (tomato-repl drops it too)
  case "$m" in "ok   adds
FAIL fails
     expected 3, got 2  (raised on line 9)
skip lookup  (no network)
1 passed, 1 failed, 1 skipped
~rc 1") ok "wasm: the entry test runs the @test functions";; *) bad "wasm: the entry test runs the @test functions" "$m";; esac
  m="$(tjsc site/wasm run "$work/wt.tom" 2>&1)"
  case "$m" in *"no function is marked @main"*"~rc 1") ok "wasm: a test file without @main is not a program";; *) bad "wasm: a test file without @main is not a program" "$m";; esac
}
t_wasm_site_errors() { r="$(jsc tests/site_errors.js 2>&1)"; [ "$r" = ok ] && ok "website: tomatoErrors keeps the words, escapes them, styles with classes" || bad "website: tomatoErrors" "$r"; }
t_highlighter_lists() { r="$(sh tests/highlighter_lists.sh 2>&1)"; [ "$r" = ok ] && ok "highlighters know every lexer keyword and built-in" || bad "highlighters" "$r"; }
t_wasm_site_editor() { r="$(jsc tests/site_editor.js 2>&1)"; [ "$r" = ok ] && ok "website: editor auto-indent after a colon, backspace and tab" || bad "website: editor auto-indent" "$r"; }
t_wasm_missing() { [ -n "$CI" ] && bad "wasm path" "jsc (macOS) or node is required in CI" || echo "skip: neither jsc nor node is available on this system"; }
if [ -n "$have_js" ]; then
  for name in trig_radians wave2_bytes hashlib_browser hmac_vectors struct_ints struct_floats angles at_neg_rmul containers compact_lists compact_fuzz open_errors msgpack_file_basics unicode_case list_methods finally inheritance fixed_width text_and_maps modules numbers_rules range_value iter_protocol async_tasks async_toolkit async_sync async_queue_drop generics bigint_ops bigint_ownership bigint_frames bigint_unwind big_karatsuba big_division function_values lambdas sort_stable sort_errors sort_key_cmp cache_lru cache_multi memoize bit_types bit_names builtin_layout text_dict_methods dict_literal_inference dict_keys_any dict_keys_objects dict_keys_forms dict_keys_cycles tuple_for unicode_class mixed_tuples union_show time_module int_ranges range_wide int_to_float fast_ranges tuple_type_args url_parse url_quote html_escape base64_codec hex_codec web_modules datetime_arith datetime_format datetime_parse csv_module textwrap_module statistics_module re_api ospath_text os_browser terminal_browser string_io assert_ok testing_lib float_any_size float_floor_mod float_ownership float_loops float_keys float_nests float_library float_limits; do
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
  check "runtime cache: a built program runs" "$want" "$("$work/echo_d" a b 2>&1)"
  check "runtime cache: release is another entry" "$want" "$($h/bin/tomato run "$work/echo.tom" main a b --mode release 2>&1)"
  check "runtime cache: release compiled the runtime once more" "2 2" "$(compiles) $(files)"
  $h/bin/tomato run "$work/echo.tom" main a b --mode release > /dev/null 2>&1; check "runtime cache: release hits too" "2 2" "$(compiles) $(files)"
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
  check "runtime cache: the program is the same with and without the cache" "$(TOMATO_CACHE=off $h/bin/tomato build "$work/echo.tom" -o "$work/e_off" >/dev/null 2>&1; "$work/e_off" a b 2>&1)" "$("$work/echo_d" a b 2>&1)"
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
  check "--version is version" "$($t version)" "$($t --version)"
  case "$($t help)" in *"tomato explain"*"tomato version"*) ok "help lists every command";; *) bad "help lists every command" "$($t help)";; esac
  check "explain says when the line is not in the file" "error[E01]: ZeroDivisionError: division by zero
  (line 999 is past the end of $work/dz.tom: is this the file the program was built from?)" "$($t explain E01:999 "$work/dz.tom")"
  check "unknown command exits 2" "2" "$($t wghwrltghs >/dev/null 2>&1; echo $?)"
}
t_cli_repl_1() {
  part="${1:-1}"; cli_setup
  if step 1; then
  check "glob and empty inputs survive" "[*][]" "$(cd "$work" && $t run echo.tom main '*' '')"
  check "-- passes flag-like inputs" "[-o][--entry]" "$($t run "$work/echo.tom" -- main -o --entry)"
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
t_cli_repl_history() {   # the pty session is slow (it compiles after each line): it is its own job, so it does not hold up the others
  cli_setup
  if command -v expect >/dev/null 2>&1; then check "repl: up-arrow recalls a multi-line block as one history entry" "ok" "$(PATH="$(dirname "$t"):$PATH" expect tests/repl_history.exp 2>&1 | tail -1)"; fi
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
t_cli_test() { # tomato test: the ok/FAIL lines and summary on standard output, the status, --filter, --mode, several files, errors (pack B)
  part="${1:-1}"; cli_setup
  printf 'from testing import assert_equal, skip\n\n@test\ndef adds():\n    assert_equal(1 + 1, 2)\n\n@test\ndef fails():\n    assert_equal(1 + 1, 3)\n\n@test\ndef lookup():\n    skip("no network")\n' > "$work/t3.tom"
  printf 'from testing import assert_equal\n\n@test\ndef one():\n    assert_equal(1, 1)\n\n@test\ndef two():\n    assert 2 > 1\n\n@test\ndef three():\n    assert_equal("a" + "b", "ab")\n' > "$work/tpass.tom"
  printf 'from testing import assert_equal\n\n@test\ndef broken():\n    assert_equal(undefined_name, 1)\n' > "$work/tbad.tom"
  printf '@test\ndef plain():\n    x = 2\n    assert x == 3, "x is not three"\n\n@test\ndef later():\n    print("later ran")\n' > "$work/tplain.tom"
  printf 'import testing\n\n@test\ndef q():\n    testing.assert_equal(1, 1)\n    testing.assert_raises(boom, "ValueError")\n\ndef boom():\n    raise ValueError("x")\n' > "$work/timport.tom"
  if step 1; then
  r="$($t test "$work/t3.tom" 2>/dev/null)"; rc=$?
  check "tomato test: the lines and the summary are on standard output" "ok   adds
FAIL fails
     expected 3, got 2  (raised on line 9)
skip lookup  (no network)
1 passed, 1 failed, 1 skipped" "$r"
  check "tomato test: a failing test makes the status 1" "1" "$rc"
  r="$($t test "$work/tpass.tom" 2>&1)"; rc=$?
  check "tomato test: an all-pass file" "ok   one
ok   two
ok   three
3 passed, 0 failed, 0 skipped" "$r"
  check "tomato test: an all-pass file exits 0" "0" "$rc"
  r="$($t test "$work/t3.tom" --filter adds 2>&1)"; rc=$?
  check "tomato test: --filter runs the tests whose name contains the text" "ok   adds
1 passed, 0 failed, 0 skipped" "$r"
  check "tomato test: a filtered run that passes exits 0" "0" "$rc"
  r="$($t test "$work/t3.tom" --filter nomatch 2>&1)"; rc=$?
  check "tomato test: a filter that matches no test says so, and the status stays 0" "warning: no test name contains 'nomatch'
0 passed, 0 failed, 0 skipped 0" "$r $rc"
  r="$($t test --filter ail "$work/t3.tom" 2>&1)"; rc=$?
  case "$r" in "FAIL fails"*"0 passed, 1 failed, 0 skipped") ok "tomato test: --filter before the file";; *) bad "tomato test: --filter before the file" "$r";; esac
  r="$($t test "$work/timport.tom" 2>&1)"; rc=$?
  check "tomato test: a file that imports testing itself (import testing) runs" "ok   q
1 passed, 0 failed, 0 skipped" "$r"
  fi; if step 2; then
  r="$($t test "$work/tbad.tom" 2>&1)"; rc=$?
  case "$r" in *"error[E227]: name 'undefined_name' is not defined"*) [ "$rc" = 1 ] && ok "tomato test: a compile error is reported and exits 1" || bad "tomato test: a compile error exits 1" "status $rc";; *) bad "tomato test: a compile error is reported" "$r";; esac
  r="$($t test "$work/tpass.tom" "$work/t3.tom" "$work/tbad.tom" 2>/dev/null)"; rc=$?
  check "tomato test: several files run one after another, each under its name" "==> $work/tpass.tom <==
ok   one
ok   two
ok   three
3 passed, 0 failed, 0 skipped
==> $work/t3.tom <==
ok   adds
FAIL fails
     expected 3, got 2  (raised on line 9)
skip lookup  (no network)
1 passed, 1 failed, 1 skipped
==> $work/tbad.tom <==" "$r"
  check "tomato test: any failing file makes the status 1" "1" "$rc"
  r="$($t test 2>&1)"; rc=$?
  case "$r" in *"tomato test FILE..."*) [ "$rc" = 2 ] && ok "tomato test: no file is a usage error" || bad "tomato test: no file is a usage error" "status $rc";; *) bad "tomato test: no file is a usage error" "$r";; esac
  r="$($t test "$work/nothing.tom" 2>&1)"; rc=$?
  check "tomato test: a missing file" "error: cannot read $work/nothing.tom" "$r"
  r="$($t test "$work/dz.tom" 2>&1)"; rc=$?
  case "$r" in *"error[E522]: no function is marked @test"*) [ "$rc" = 1 ] && ok "tomato test: a file with no @test function" || bad "tomato test: a file with no @test function" "status $rc";; *) bad "tomato test: a file with no @test function" "$r";; esac
  fi; if step 3; then
  r="$($t test "$work/tplain.tom" 2>&1)"; rc=$?
  check "tomato test: a plain assert fails the test with its message and line; the next test still runs" "FAIL plain
     x is not three  (raised on line 4)
later ran
ok   later
1 passed, 1 failed, 0 skipped" "$r"
  r="$($t test "$work/tplain.tom" --mode release 2>&1)"; rc=$?
  check "tomato test --mode release: the same, without the line (release mode keeps no call trace)" "FAIL plain
     x is not three
later ran
ok   later
1 passed, 1 failed, 0 skipped" "$r"
  check "tomato test --mode release exits 1 on a failure" "1" "$rc"
  check "release mode runs testing_lib (assert_raises by class name) like debug" "$(cat tests/expected/testing_lib.main.out)" "$($t run tests/programs/testing_lib.tom --mode release 2>&1)"
  check "an uncaught failed assert has its release ID and line" "error E519:3" "$($t run tests/runtime/assert_failed.tom --mode release 2>&1)"
  r="$($t run "$work/t3.tom" 2>&1)"; rc=$?
  case "$r" in *"no function is marked @main"*) ok "tomato run on a test file without @main asks for @main";; *) bad "tomato run on a test file without @main" "$r";; esac
  case "$($t help)" in *"tomato test FILE... [--filter TEXT] [--mode MODE]"*) ok "tomato help lists the test command";; *) bad "tomato help lists the test command";; esac
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
spawn_cli t_cli_repl_history
spawn_cli t_cli_compile
spawn_cli t_cli_test 1
spawn_cli t_cli_test 2
spawn_cli t_cli_test 3
t_terminal_logic() { # std/terminal.tom: the pure parts as @test functions (the key decoder at every byte split, widths, SGR lowering, color depth), debug and release
  cli_setup
  for mode in debug release; do
    r="$($t test tests/terminal_logic.tom --mode $mode 2>&1 | tail -1)"
    case "$r" in *" passed, 0 failed, 0 skipped") ok "terminal: the @test functions pass ($mode mode): $r";; *) bad "terminal: the @test functions pass ($mode mode)" "$($t test tests/terminal_logic.tom --mode $mode 2>&1 | grep -v '^ok ' | head -12)";; esac
  done
}
t_terminal_pty() { # std/terminal.tom on a real terminal (a pty), through expect: raw mode, keys, size and resize, and the restore however the program ends
  cli_setup
  if ! command -v expect >/dev/null 2>&1; then
    [ -n "$CI" ] && bad "terminal pty test" "expect is required in CI" || echo "skip: expect is not installed, so the terminal pty test did not run"
    return
  fi
  if $t build tests/terminal_pty.tom -o "$work/terminal_pty" > "$work/e" 2>&1; then
    check "terminal: raw mode, keys, size, resize and the restore on a pty" "ok" "$(expect tests/terminal_pty.exp "$work/terminal_pty" 2>&1 | tail -1)"
  else bad "terminal pty test: tests/terminal_pty.tom does not build" "$(head -5 "$work/e")"; fi
}
spawn_cli t_terminal_logic
spawn_cli t_terminal_pty

# ---- rejected programs --------------------------------------------------------------------------------------------------
t_neg() { # file, message that the compiler must report, and the entry name (default main; `test` for the @test checks)
  msg="$("$c1" "tests/negative/$1.tom" "${3:-main}" std/ 2>&1 >/dev/null)"; code=$?
  case "$msg" in *"$2"*) [ $code -ne 0 ] && ok "rejects $1" || bad "rejects $1" "exit status was 0";; *) bad "rejects $1" "wanted: $2
got:    $msg";; esac
}
neg() { spawn t_neg "$@"; }
section "== rejected programs =="
neg int_or_none "'int' cannot be combined with None, because only str, lists, dicts, sets, classes and tuples can be None"
neg list_of_int_or_none "'int' cannot be combined with None"
neg param_int_or_none "'int' cannot be combined with None"
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
neg test_on_async "is marked @test, but it is async, and async tests are not supported yet" test
neg test_with_parameter "is marked @test, so it must take no parameters and return nothing" test
neg test_with_result "is marked @test, so it must take no parameters and return nothing" test
neg duplicate_test_name "'adds' is defined twice in module 'main'" test
neg test_none_marked "no function is marked @test" test

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
  names="$(sed -n '/^def std_modules()/,/return/p' compiler/src/compiler.tom | sed -n 's/^ *return \[//p' | tr -d "]',")"
  have="$(ls std/*.tom std/builtin/bitarray.tom | sed 's#.*/##; s#\.tom$##' | sort | tr '\n' ' ')"
  [ "$(echo $names | tr ' ' '\n' | sort | tr '\n' ' ')" = "$have" ] && ok "std_modules lists the modules of std/" || bad "std_modules lists the modules of std/" "compiler: $names / std: $have"
}
section "== error ids =="
spawn_free t_error_templates
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
