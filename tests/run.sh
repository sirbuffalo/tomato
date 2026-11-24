#!/bin/sh
# The test suite, in shell: it needs only clang. Usage: tests/run.sh [-j N] [--times]
#   1. builds the compiler from compiler/bootstrap/tomatoc.ll and checks that it reproduces itself and that the
#      checked-in IR is current (the fixed point)
#   2. compiles and runs every example with the expected output in tests/expected
#   3. checks the command line (tomato run/build/compile/repl/update/version/help)
#
# --times (or TOMATO_TEST_TIMES=1) adds, after the summary, the 20 slowest tests and the time per section; nothing else changes.
#
# The tests run in parallel: -j N (or TOMATO_TEST_JOBS=N) is the number of tests running at once. The default is a modest
# min(8, cores / 4) so that a shared machine is not starved; -j 1 runs the tests one after the other, printing each as it goes.
# Whatever N is, the output is the same and in the same order (a test's lines are printed when it is done, but never before
# the tests that come before it), and so are the final count and the exit status. With more than one job the WebAssembly
# checks get a 30 s limit instead of 5 s (TOMATO_WASM_TIMEOUT_MS, when you have not set it), because a busy machine is slow.
#
# How it works: every test is a function (t_NAME) that runs in a job of its own with its own temp folder ($work), so tests
# never share a file. The few things that are shared (the compiler built in step 1 and the installed `tomato` command) are
# made once, before the tests that need them, and only read afterwards. Tests that must not overlap with anything (the
# macOS package and disk image, the benchmarks, the rebuild of site/wasm) are run on their own, last (serial_last).
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1
root="$(pwd)"
jobs="${TOMATO_TEST_JOBS:-}"
case "${TOMATO_TEST_TIMES:-}" in ''|0) times="" ;; *) times=1 ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    -j) [ $# -ge 2 ] || { echo "tests/run.sh: -j needs a number" >&2; exit 2; }; jobs="$2"; shift 2 ;;
    -j*) jobs="${1#-j}"; shift ;;
    --times) times=1; shift ;;
    -h|--help) awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$self"; exit 0 ;;
    *) echo "usage: tests/run.sh [-j N] [--times]   (or TOMATO_TEST_JOBS=N, TOMATO_TEST_TIMES=1)" >&2; exit 2 ;;
  esac
done
if [ -z "$jobs" ]; then   # getconf works on macOS and Linux
  cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"
  case "$cores" in ''|*[!0-9]*) cores=4 ;; esac
  jobs=$((cores / 4)); [ "$jobs" -gt 8 ] && jobs=8
fi
case "$jobs" in ''|*[!0-9]*) echo "tests/run.sh: the number of jobs must be a number, not '$jobs'" >&2; exit 2 ;; esac
[ "$jobs" -ge 1 ] || jobs=1

# With several tests at once a machine is slower, and the WebAssembly runner stops a program after 5 s: give it more room
# (native/tomato-jsc.js reads this under node; set it yourself to change it).
[ "$jobs" -gt 1 ] && : "${TOMATO_WASM_TIMEOUT_MS:=30000}" && export TOMATO_WASM_TIMEOUT_MS
t_start="$(date +%s)"
work="$(mktemp -d)"; shared="$work"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }   # macOS has shasum, some Linux systems only sha256sum

# ---- the job pool -------------------------------------------------------------------------------------------------------
# $shared holds, per job N: out.N (its output), done.N (it is finished), and the files passed and failed (one line per test).
# Inside a job, $work is that job's own folder (removed when the job ends); $shared is still the common one.
n=0; m=0; next=1; running=""; nrun=0; deferred=""
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
section_name=""
job_run() { # id, function and arguments: runs it in a folder of its own
  id="$1"; shift; work="$shared/j$id"; mkdir -p "$work"
  if [ -n "$times" ]; then
    tm_start="$(ms)"; tm_label="${1#t_} $2"; "$@"; rc=$?   # (names the tests do not use)
    printf '%s\t%s\t%s\n' "$(($(ms) - tm_start))" "$section_name" "$tm_label" >> "$shared/times"
  else "$@"; rc=$?; fi
  rm -rf "$work"; return $rc
}
pump() { # prints the output of the finished jobs, in the order they were started
  while [ -f "$shared/done.$next" ]; do cat "$shared/out.$next"; rm -f "$shared/out.$next"; next=$((next + 1)); done
}
reap() { # forgets the jobs that are finished; a job that is gone without finishing (killed) is a failure, not a hang
  r=""; nrun=0
  for j in $running; do
    rid="${j%%:*}"
    [ -f "$shared/done.$rid" ] && continue
    if ! kill -0 "${j#*:}" 2>/dev/null && [ ! -f "$shared/done.$rid" ]; then
      echo "FAIL job $rid died before it finished" >> "$shared/out.$rid"; echo x >> "$shared/failed"; : > "$shared/done.$rid"; continue
    fi
    r="$r $j"; nrun=$((nrun + 1))
  done
  running="$r"
}
barrier() { while :; do reap; pump; [ "$nrun" -eq 0 ] && break; nap; done; pump; }
now() { # NAME ARGS: run a test here, alone, printing straight to the output (only when nothing is waiting to be printed)
  m=$((m + 1)); ( job_run "x$m" "$@" ) < /dev/null; rc=$?
  [ "$rc" -gt 128 ] && { echo "FAIL job died before it finished (status $rc)"; echo x >> "$shared/failed"; }   # killed by a signal
  return $rc
}
spawn() { # NAME ARGS: run a test in a job of its own, as soon as there is a free slot
  [ "$jobs" -le 1 ] && { now "$@"; return; }
  n=$((n + 1)); id=$n
  while :; do reap; pump; [ "$nrun" -lt "$jobs" ] && break; nap; done
  ( ( job_run "$id" "$@" ) > "$shared/out.$id" 2>&1 < /dev/null; rc=$?   # the inner subshell: a test that calls exit still gets its done marker
    [ "$rc" -gt 128 ] && { echo "FAIL job died before it finished (status $rc)" >> "$shared/out.$id"; echo x >> "$shared/failed"; }   # killed by a signal
    : > "$shared/done.$id" ) &
  running="$running $id:$!"; nrun=$((nrun + 1))
}
serial_last() { # NAME: run this test alone, after every other test (its output still comes in its place)
  if [ "$jobs" -le 1 ]; then now "$@"; return; fi
  n=$((n + 1)); deferred="$deferred $n:$1"; pump
}
section() { # prints a heading in its place
  section_name="$1"
  if [ "$jobs" -le 1 ]; then echo "$1"; return; fi
  n=$((n + 1)); echo "$1" > "$shared/out.$n"; : > "$shared/done.$n"; pump
}
finish() {
  barrier
  for d in $deferred; do
    id="${d%%:*}"
    ( job_run "d$id" "${d#*:}" > "$shared/out.$id" 2>&1 < /dev/null ); rc=$?
    [ "$rc" -gt 128 ] && { echo "FAIL job died before it finished (status $rc)" >> "$shared/out.$id"; echo x >> "$shared/failed"; }   # killed by a signal
    : > "$shared/done.$id"; pump
  done
  pump
}

cc() { clang -O1 -w -o "$1" "$2" "$root/runtime/tomato_rt.c" -lm; }
c1="$shared/c1"
home="$shared/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"; t="$home/bin/tomato"

# ---- compiler -----------------------------------------------------------------------------------------------------------
t_compiler_build() { # the compiler everything else uses: $shared/c0 (from the bootstrap IR) and $shared/c1 (built by c0)
  cc "$shared/c0" compiler/bootstrap/tomatoc.ll && ok "builds from the bootstrap IR" || { bad "builds from the bootstrap IR"; return 1; }
  "$shared/c0" compiler/src/ctool.tom compile > "$shared/ir1.ll" 2> "$work/e" && ok "compiles its own source" || bad "compiles its own source" "$(cat "$work/e")"
  cc "$c1" "$shared/ir1.ll"
}
t_fixed_point() {
  "$c1" compiler/src/ctool.tom compile > "$work/ir2.ll"
  cmp -s "$shared/ir1.ll" "$work/ir2.ll" && ok "stage 2 reproduces itself (fixed point)" || bad "stage 2 reproduces itself (fixed point)"
  cmp -s "$work/ir2.ll" compiler/bootstrap/tomatoc.ll && ok "compiler/bootstrap/tomatoc.ll is current" || bad "compiler/bootstrap/tomatoc.ll is current" "run compiler/bootstrap/refresh.sh"
  grep -q '^;! ' "$shared/ir1.ll" && bad "the compiler's own source compiles without warnings" "$(grep '^;! ' "$shared/ir1.ll" | head -6)" || ok "the compiler's own source compiles without warnings"
}
t_install() { # the installed `tomato` command: the command line tests use it, and only read it
  ./install-native.sh > /dev/null 2>&1; echo $? > "$shared/install.tmp"; mv "$shared/install.tmp" "$shared/install.rc"
}

section "== compiler =="
spawn t_install          # prints nothing: the result is reported in "command line"
now t_compiler_build || { barrier; exit 1; }   # not serial: the install above runs beside it, and prints nothing
spawn t_fixed_point

# ---- examples -----------------------------------------------------------------------------------------------------------
t_example() { # name, entry, the arguments
  name="$1"; entry="$2"; rest="$3"
  "$c1" "examples/$name.tom" "$entry" std/ > "$work/p.ll" 2> "$work/e" || { echo "FAIL $name $entry: $(cat "$work/e")"; echo x >> "$shared/failed"; return; }
  grep -q '^;! ' "$work/p.ll" && { echo "FAIL $name $entry: warnings"; grep '^;! ' "$work/p.ll" | head -6 | sed 's/^/     /'; echo x >> "$shared/failed"; return; }
  clang -O1 -w -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm || { echo "FAIL $name $entry: link"; echo x >> "$shared/failed"; return; }
  # shellcheck disable=SC2086
  "$work/p" $rest > "$work/out" 2>&1 < /dev/null
  if cmp -s "$work/out" "tests/expected/$name.$entry.out"; then echo "ok   $name $entry"; echo x >> "$shared/passed"; else echo "FAIL $name $entry"; diff "$work/out" "tests/expected/$name.$entry.out" | head -5 | sed 's/^/     /'; echo x >> "$shared/failed"; fi
}
section "== examples =="
grep -v '^#' tests/examples.txt | while read -r name entry rest; do echo "$name $entry $rest"; done > "$shared/list"
while read -r name entry rest; do spawn t_example "$name" "$entry" "$rest"; done < "$shared/list"

# ---- programs -----------------------------------------------------------------------------------------------------------
t_program() {
  name="$1"
  "$c1" "tests/programs/$name.tom" main std/ > "$work/p.ll" 2> "$work/e"
  if grep -q '^;! ' "$work/p.ll"; then echo "FAIL program $name has warnings"; echo x >> "$shared/failed"; return; fi
  arg=""; case "$name" in toml_api|json_files|msgpack_files|msgpack_file_basics) arg="$work" ;; esac   # they write files: into this test's own folder, not a shared /tmp
  # shellcheck disable=SC2086
  [ -s "$work/p.ll" ] && clang -O1 -w -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm && "$work/p" $arg > "$work/out" 2>&1
  if cmp -s "$work/out" "tests/expected/$name.main.out"; then echo "ok   program $name"; echo x >> "$shared/passed"; else echo "FAIL program $name"; { head -3 "$work/e"; diff "$work/out" "tests/expected/$name.main.out" | head -5; } | sed 's/^/     /'; echo x >> "$shared/failed"; fi
}
section "== decided rules (programs) =="
grep -v '^#' tests/programs.txt > "$shared/list"
while read -r name; do spawn t_program "$name"; done < "$shared/list"

# ---- memory -------------------------------------------------------------------------------------------------------------
t_asan() { # PATH:ARGUMENT, the argument being a folder the program may write into when it is $work
  spec="$1"; path="${spec%%:*}"; name="$(basename "$path")"; arg="${spec#*:}"; [ "$arg" = WORK ] && arg="$work"
  "$c1" "$path.tom" main std/ > "$work/p.ll" 2>/dev/null
  if clang -O1 -w -g -fsanitize=address -o "$work/asan" "$work/p.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
    # a failure shows the head of the sanitizer report (with ASAN_SYMBOLIZER_PATH set, as the Linux CI job does, that includes the leaking allocation's stack)
    # shellcheck disable=SC2086
    out="$("$work/asan" $arg 2>&1 >/dev/null | head -14)"
    [ -z "$out" ] && ok "asan $name" || bad "asan $name" "$out"
  else bad "asan $name" "this clang cannot build with -fsanitize=address"; fi
}
section "== memory (AddressSanitizer and the runtime's leak check) =="
for spec in "examples/shapes:" "examples/objects:4" "tests/programs/cycle:" "tests/programs/gc_cycles:" "tests/programs/containers:" "tests/programs/modules:" "tests/programs/borrow_elision:" "tests/programs/native_sort:" "tests/programs/function_values:" "tests/programs/lambdas:" "tests/programs/sort_stable:" "tests/programs/sort_errors:" "tests/programs/sort_key_cmp:" "tests/programs/sort_cmp_native:" "tests/programs/str_fast:" "tests/programs/alloc_pool:" "tests/programs/text_index:" "tests/programs/fstring_fuse:" "tests/programs/cache_lru:" "tests/programs/memoize:" "tests/programs/bit_types:" "tests/programs/int_shift:" "tests/programs/bit_chunks:" "tests/programs/json_strict:" "tests/programs/json_accept:" "tests/programs/json_dumps:" "tests/programs/json_access:" "tests/programs/json_depth:" "tests/programs/json_utf8:" "tests/programs/json_fuzz:" "tests/programs/msgpack_basic:" "tests/programs/msgpack_errors:" "tests/programs/msgpack_fuzz:" "tests/programs/bigint_ownership:" "tests/programs/bigint_ops:" "tests/programs/bigint_frames:" "tests/programs/bigint_unwind:" "tests/programs/big_numbers:" "tests/programs/big_mul:" "tests/programs/unlimited_int:" "tests/programs/toml_valid:" "tests/programs/toml_invalid:" "tests/programs/toml_api:WORK" "tests/programs/json_files:WORK" "tests/programs/msgpack_files:WORK" "tests/programs/msgpack_file_basics:WORK" "tests/runtime/msgpack_full_disk:" "tests/programs/open_errors:" "tests/programs/unicode_case:" "tests/programs/unicode_class:" "tests/programs/mixed_tuples:" "tests/programs/tuple_type_args:" "tests/programs/union_show:" "tests/programs/toml_big:" "tests/programs/compact_lists:" "tests/programs/compact_fuzz:" "tests/programs/temp_unwind:" "tests/programs/text_dict_methods:" "tests/programs/dict_literal_inference:" "tests/programs/tuple_for:" "tests/programs/list_methods:" "tests/programs/utf8_invalid:" "tests/programs/async_tasks:" "tests/programs/async_cancel:" "tests/programs/async_sleep:" "tests/programs/error_path_release:" "tests/programs/int_ranges:" "tests/programs/range_wide:" "tests/programs/float_ranges:" "tests/programs/fast_ranges:" "tests/runtime/error_classes:" "tests/programs/time_module:" "tests/programs/url_parse:" "tests/programs/url_quote:" "tests/programs/html_escape:" "tests/programs/base64_codec:" "tests/programs/hex_codec:" "tests/programs/web_modules:" "tests/programs/html_fuzz:" "tests/programs/web_large:" "tests/programs/datetime_arith:" "tests/programs/datetime_format:" "tests/programs/datetime_parse:" "tests/runtime/datetime_errors:" "tests/programs/csv_module:" "tests/programs/textwrap_module:" "tests/programs/statistics_module:"; do
  spawn t_asan "$spec"
done

section "== memory: round, text methods, math additions and f-string specs =="
for spec in "tests/programs/round_divmod_any_all:" "tests/programs/text_methods_more:" "tests/programs/math_more:" "tests/programs/fstring_specs:" "tests/runtime/text_math_caught:"; do
  spawn t_asan "$spec"
done

t_sort_fallback() {
  "$c1" tests/programs/native_sort.tom main std/ > "$work/p.ll" 2>/dev/null && clang -O1 -w -DSORT_DEPTH_MUL=0 -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm && "$work/p" > "$work/out" 2>&1
  check "sort with the depth limit forced to 0" "$(cat tests/expected/native_sort.main.out)" "$(cat "$work/out")"
}
section "== sort: the heapsort fallback gives the same results =="
spawn t_sort_fallback

# ---- requests -----------------------------------------------------------------------------------------------------------
t_requests() { # one local server for this job's own requests
  if clang -O1 -w -o "$work/httpd" tests/http_server.c 2>/dev/null; then
    "$work/httpd" > "$work/httpd.port" & httpd_pid=$!
    i=0; while [ ! -s "$work/httpd.port" ] && [ $i -lt 600 ]; do nap; i=$((i + 1)); done   # the server prints its port once it is listening (up to 30 s on a busy machine)
    port="$(cat "$work/httpd.port")"
    "$c1" tests/programs/requests_local.tom main std/ > "$work/rq.ll" 2> "$work/e"
    if grep -q '^;! ' "$work/rq.ll"; then bad "requests_local has warnings" "$(grep '^;! ' "$work/rq.ll" | head -4)"; fi
    if clang -O1 -w -o "$work/rq" "$work/rq.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
      check "requests against the local server" "$(cat tests/expected/requests_local.main.out)" "$("$work/rq" "http://127.0.0.1:$port" 2>&1)"
      if clang -O1 -w -g -fsanitize=address -o "$work/rq_asan" "$work/rq.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
        out="$("$work/rq_asan" "http://127.0.0.1:$port" 2>&1 >/dev/null | head -14)"
        [ -z "$out" ] && ok "asan requests_local" || bad "asan requests_local" "$out"
      else bad "asan requests_local" "this clang cannot build with -fsanitize=address"; fi
      # five requests that each take 1 s must overlap: the whole run is far below 5 s
      cp tests/programs/requests_overlap.tom "$work/overlap.tom"
      "$c1" "$work/overlap.tom" main std/ > "$work/ov.ll" 2>/dev/null && clang -O1 -w -o "$work/ov" "$work/ov.ll" runtime/tomato_rt.c -lm
      t0="$(date +%s)"; ovo="$("$work/ov" "http://127.0.0.1:$port" 2>&1)"; t1="$(date +%s)"
      [ "$ovo" = done ] && [ $((t1 - t0)) -lt 4 ] && ok "requests overlap (5 x 1 s took $((t1 - t0)) s)" || bad "requests overlap" "output '$ovo' after $((t1 - t0)) s"
    else bad "requests against the local server" "did not build: $(cat "$work/e")"; fi
    kill "$httpd_pid" 2>/dev/null
  else bad "requests test server" "tests/http_server.c did not build"; fi
  "$c1" examples/http_get.tom main std/ > "$work/hg.ll" 2> "$work/e" && clang -O1 -w -o "$work/hg" "$work/hg.ll" runtime/tomato_rt.c -lm && ok "examples/http_get.tom builds" || bad "examples/http_get.tom builds" "$(cat "$work/e")"
}
section "== requests (tests/http_server.c is a local server: no internet needed) =="
spawn t_requests

# ---- the same programs through WebAssembly ------------------------------------------------------------------------------
section "== the same programs through WebAssembly (site/wasm, the website and repl path) =="
# a JavaScript shell: jsc on macOS, else Node running the same script through native/jsc-on-node.js (the script is not changed)
jsc_mac=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc; have_js=""
if [ -x "$jsc_mac" ]; then have_js=1; jsc() { "$jsc_mac" "$@"; }
elif command -v node > /dev/null 2>&1; then have_js=1; jsc() { node "$root/native/jsc-on-node.js" "$@"; }; fi
t_wasm_program() {
  name="$1"
  jsc native/tomato-jsc.js -- site/wasm run "tests/programs/$name.tom" > "$work/js.out" 2> "$work/js.err"
  # the runner drops one trailing newline and adds an "~rc" line; compare ignoring both
  if [ "$(cat "$work/js.out")" = "$(cat "tests/expected/$name.main.out")" ]; then ok "wasm $name"; else bad "wasm $name" "$(diff "$work/js.out" "tests/expected/$name.main.out" | head -4; head -2 "$work/js.err")"; fi
}
# rejected programs and runtime errors through the same path (the messages and failures must agree with native)
t_wasm_neg() { m="$(jsc native/tomato-jsc.js -- site/wasm run "tests/negative/$1.tom" 2>&1)"; case "$m" in *"$2"*"~rc 1"*) ok "wasm rejects $1";; *) bad "wasm rejects $1" "wanted: $2
got: $m";; esac; }
t_wasm_rt() { m="$(jsc native/tomato-jsc.js -- site/wasm run "tests/runtime/$1.tom" 2>&1)"; case "$m" in *"$2"*"~rc $3"*) ok "wasm runtime $1";; *) bad "wasm runtime $1" "wanted: $2 (rc $3)
got: $m";; esac; }
wasm_neg() { spawn t_wasm_neg "$@"; }
wasm_rt() { spawn t_wasm_rt "$@"; }
t_wasm_browser() { r="$(jsc native/tomato-jsc.js -- site/wasm run tests/programs/requests_browser.tom 2>&1 | grep "no network")"; check "wasm requests raise ConnectionError" "no network: True" "$r"; }
t_wasm_site_errors() { r="$(jsc tests/site_errors.js 2>&1)"; [ "$r" = ok ] && ok "website: tomatoErrors keeps the words, escapes them, styles with classes" || bad "website: tomatoErrors" "$r"; }
t_wasm_missing() { [ -n "$CI" ] && bad "wasm path" "jsc (macOS) or node is required in CI" || echo "skip: neither jsc nor node is available on this system"; }
if [ -n "$have_js" ]; then
  for name in angles containers compact_lists compact_fuzz open_errors msgpack_file_basics unicode_case list_methods finally inheritance fixed_width text_and_maps modules numbers_rules range_value iter_protocol async_tasks generics bigint_ops bigint_ownership bigint_frames bigint_unwind function_values lambdas sort_stable sort_errors sort_key_cmp cache_lru memoize bit_types bit_names text_dict_methods dict_literal_inference tuple_for unicode_class mixed_tuples union_show time_module int_ranges range_wide float_ranges fast_ranges tuple_type_args url_parse url_quote html_escape base64_codec hex_codec web_modules datetime_arith datetime_format datetime_parse csv_module textwrap_module statistics_module; do
    spawn t_wasm_program "$name"
  done
  spawn t_wasm_browser
  wasm_neg type_mismatch "cannot use '+' with int and str"
  wasm_neg fixed_range "300 does not fit in uint[length=8]"
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
  wasm_rt stack_overflow "stack overflow" 1
  wasm_rt tan_quarter "tan is not defined at 90 deg" 1
  wasm_rt caught_domain "caught sqrt needs a number that is not negative" 0
  for name in round_divmod_any_all text_methods_more math_more fstring_specs; do spawn t_wasm_program "$name"; done
  wasm_rt partition_empty "partition needs a separator that is not empty" 1
  wasm_rt divmod_zero "division by zero" 1
  wasm_rt factorial_negative "factorial needs a number that is not negative, but got -1" 1
  wasm_rt text_math_caught "$(cat tests/runtime/text_math_caught.out)" 0
  wasm_neg fstring_text_sign "a format spec for text cannot have a sign"
  wasm_neg round_bad_type "round() takes an int or a float, but this is str"
  wasm_rt exp_overflow "exp(1000) is too large to be a float" 1
  wasm_rt trace_calls "at half (line 10)" 1
  wasm_rt url_bad_ipv6 "Invalid IPv6 URL" 1
  wasm_rt base64_bad_padding "misplaced padding" 1
  wasm_rt hex_bad_digit "a hex text holds only the digits" 1
  spawn t_wasm_site_errors
else spawn t_wasm_missing; fi

# ---- command line -------------------------------------------------------------------------------------------------------
need_install() { # waits (up to 10 minutes) for t_install; a job whose install never reported fails instead of waiting for ever
  i=0; until [ -f "$shared/install.rc" ]; do
    nap; i=$((i + 1))
    [ "$i" -gt 12000 ] && { bad "install-native.sh did not finish"; exit 1; }
  done
}
# Each job makes its own copies of the small programs the checks use, and waits for the install (t_install, started first).
cli_setup() {
  need_install
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
  cli_setup
  [ "$(cat "$shared/install.rc")" = 0 ] && ok "install-native.sh" || bad "install-native.sh"
  r="$($t run "$work/top.tom" 2>&1)"; case "$r" in *"put it inside a function marked @main"*) ok "top-level code gives a clear hint";; *) bad "top-level code gives a clear hint" "$r";; esac
  check "version" "Tomato v$(cat VERSION) (compiler written in Tomato)" "$($t version)"
  check "mode debug is readable" "error[E01]: division by zero
  at main (line 4)" "$($t run "$work/dz.tom" 2>&1)"
  check "mode release prints a code" "error E01:4" "$($t run "$work/dz.tom" --mode release 2>&1)"
  check "release keeps caught messages and IDs" "$(cat tests/runtime/error_classes.out)" "$($t run tests/runtime/error_classes.tom --mode release 2>&1)"
  check "open error keeps its message and ID in release" "$(cat tests/expected/open_errors.main.out)" "$($t run tests/programs/open_errors.tom --mode release 2>&1)"
  check "uncaught open error has its debug ID" "error[E25]: could not open '/nonexistent_dir_for_tomato/missing.txt': No such file or directory
  at main (line 3)" "$($t run tests/runtime/open_missing.tom 2>&1)"
  check "uncaught open error has its release ID" "error E25:3" "$($t run tests/runtime/open_missing.tom --mode release 2>&1)"
  r="$($t run tests/runtime/msgpack_missing.tom --mode release 2>&1)"
  case "$r" in "error E25:"[1-9]*) ok "load_msgpack open error has its release ID";; *) bad "load_msgpack open error has its release ID" "$r";; esac
  r="$($t run tests/runtime/error_std_uncaught.tom --mode release 2>&1)"
  case "$r" in "error E51:"[1-9]*) ok "release prints a library error ID and line";; *) bad "release prints a library error ID and line" "$r";; esac
  check "mode normal was renamed to release" "error[E281]: the mode 'normal' was renamed to 'release': use --mode release (the old release mode is gone)" "$($t run "$work/dz.tom" --mode normal 2>&1)"
  check "unknown mode is refused" "error[E282]: the mode must be debug or release, not 'fast'" "$($t run "$work/dz.tom" --mode fast 2>&1)"
  $t build "$work/dz.tom" -o "$work/dz_rel" --mode release > /dev/null 2>&1; check "build --mode release makes a release binary" "error E01:4" "$("$work/dz_rel" 2>&1)"
  $t compile "$work/dz.tom" --mode release > "$work/dz_rel.ll" 2>&1
  grep -q tomato_report_uncaught "$work/dz_rel.ll" && ok "compile --mode release works" || bad "compile --mode release works" "$(head -3 "$work/dz_rel.ll")"
  if grep -q '^@tomato.name\.' "$work/dz_rel.ll"; then bad "release omits class name metadata"; else ok "release omits class name metadata"; fi
}
# release links with LTO and an inlined runtime: the same programs must print exactly what debug mode prints
t_cli_release_like_debug() { cli_setup; check "release mode runs $1 like debug" "$(cat "tests/expected/$1.main.out")" "$($t run "tests/programs/$1.tom" --mode release 2>&1)"; }
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
  check "--version is version" "$($t version)" "$($t --version)"
  case "$($t help)" in *"tomato explain"*"tomato version"*) ok "help lists every command";; *) bad "help lists every command" "$($t help)";; esac
  check "explain says when the line is not in the file" "error[E01]: ZeroDivisionError: division by zero
  (line 999 is past the end of $work/dz.tom: is this the file the program was built from?)" "$($t explain E01:999 "$work/dz.tom")"
  check "unknown command exits 2" "2" "$($t wghwrltghs >/dev/null 2>&1; echo $?)"
}
t_cli_repl_1() {
  cli_setup
  check "glob and empty inputs survive" "[*][]" "$(cd "$work" && $t run echo.tom main '*' '')"
  check "-- passes flag-like inputs" "[-o][--entry]" "$($t run "$work/echo.tom" -- main -o --entry)"
  check "repl: variables, functions, new output only" "7
9
hi" "$(printf 'x = 3\nx + 4\ndef sq(n: int) -> int:\n    return n * n\n\nsq(x)\nprint("hi")\n:quit\n' | $t repl)"
  check "repl: std imports resolve (itertools, math)" "True
False" "$(printf 'from math import is_prime\nfrom itertools import progress_bar\nis_prime(97)\nis_prime(91)\n:quit\n' | $t repl 2>&1)"
  check "repl: :load runs a program that has its own @main" "$(cat tests/expected/shapes.main.out)" "$(printf ':load examples/shapes.tom\n:quit\n' | $t repl)"
  check "repl: a block, then a failing line, then a good one" "9
error[E190]: cannot use '+' with int and str
5" "$(printf 'def sq(n: int) -> int:\n    return n * n\n\nsq(3)\nprint(1 + "a")\nsq(2) + 1\n:quit\n' | $t repl 2>&1 | grep -E '^(9|5|error\[)')"
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
}
t_cli_color() {
  cli_setup
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
  check "--color=always paints a runtime error and its trace" "^[[1;31merror[E01]:^[[0m ^[[1mdivision by zero^[[0m
^[[2m  at half (line 6)^[[0m
^[[2m  at main (line 3)^[[0m" "$($t run "$work/trace.tom" --color=always 2>&1 | cat -v)"
  check "--color=never keeps the plain words" "error[E01]: division by zero
  at half (line 6)
  at main (line 3)" "$($t run "$work/trace.tom" --color=never 2>&1 | cat -v)"
  check "TOMATO_COLOR=always works like the flag" "^[[1;31merror[E01]:^[[0m ^[[1mdivision by zero^[[0m" "$(TOMATO_COLOR=always $t run "$work/trace.tom" 2>&1 | cat -v | head -1)"
  check "without a terminal the color stays off (and NO_COLOR keeps it off)" "error[E01]: division by zero" "$(NO_COLOR=1 $t run "$work/trace.tom" 2>&1 | head -1)"
  check "a bad --color value is refused" "error: --color takes auto, always or never, not 'blue'" "$($t run "$work/trace.tom" --color=blue 2>&1)"
  check "--color=always paints a compile error: label, location, gutter, caret" "^[[1;31merror[E227]:^[[0m ^[[1mname 'tets' is not defined^[[0m
 ^[[1;34m-->^[[0m ^[[36m$work/typo.tom:3:11^[[0m
^[[1;34m  |^[[0m
^[[1;34m3 |^[[0m     print(tets)
^[[1;34m  |^[[0m           ^[[1;31m^^^^^[[0m" "$($t run "$work/typo.tom" --color=always 2>&1 | cat -v)"
}
t_cli_warnings() {
  cli_setup
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
  check "repl: warnings are not shown" "3" "$(printf 'unused = 1\nprint(3)\n:quit\n' | $t repl 2>&1)"
  check "repl: --color=always paints the label red" "^[[1;31merror[E190]:^[[0m ^[[1mcannot use '+' with int and str^[[0m" "$(printf 'print(1 + "a")\n:quit\n' | $t repl --color=always 2>&1 | cat -v | head -1)"
  check "repl: a runtime error shows no call trace of the generated program" "error[E01]: division by zero" "$(printf 'x = 0\nprint(1 // x)\n:quit\n' | $t repl 2>&1)"
}
t_cli_repl_2() {
  cli_setup
  check "repl: == is a comparison, = is an assignment" "False
3" "$(printf 'x = 3\nx == 4\nx\n:quit\n' | $t repl)"
  case "$(printf ':help\n:quit\n' | $t repl 2>&1)" in *":reset"*":quit"*) ok "repl: :help lists every command";; *) bad "repl: :help lists every command";; esac
  r="$(printf 'from nosuch_mod import a\n:quit\n' | $t repl 2>&1)"; case "$r" in *"Could not open"*|*"${TMPDIR:-/tmp}/"*|*"/var/folders/"*) bad "repl: a missing module shows no temp path or tool noise" "$r";; *"nosuch_mod"*) ok "repl: a missing module shows no temp path or tool noise";; *) bad "repl: a missing module shows no temp path or tool noise" "$r";; esac
  check "repl: += works" "8" "$(printf 'x = 5\nx += 3\nx\n:quit\n' | $t repl)"
  check "repl: input asks once, then the answer is replayed" "Name? Ann
hi Ann
Ann" "$(printf "name = await input('Name? ')\nAnn\nprint('hi', name)\nprint(name)\n:quit\n" | $t repl)"
  check "repl: async functions and start work" "3
6" "$(printf "async def f(x: int) -> int:\n    return x + 1\n\nprint(await f(2))\nt = start f(5)\nprint(await t)\n:quit\n" | $t repl)"
  check "repl: input works without the fast path too" "Name? Ann
hi Ann" "$(printf "name = await input('Name? ')\nAnn\nprint('hi', name)\n:quit\n" | TOMATO_JSC=/nonexistent $t repl)"
  check "tomato run reads standard input" "Name? How many? hi Ann 6" "$(printf 'Ann\n3\n' | $t run tests/input/ask_and_status.tom 2>&1 | head -1)"
  check "repl: leave() leaves" "a" "$(printf "print('a')\nleave()\nprint('b')\n" | $t repl)"
}
t_cli_repl_history() {   # the pty session sleeps between keys: it is its own job, so it does not hold up the others
  cli_setup
  if command -v expect >/dev/null 2>&1; then check "repl: up-arrow recalls a multi-line block as one history entry" "ok" "$(PATH="$(dirname "$t"):$PATH" expect tests/repl_history.exp 2>&1 | tail -1)"; fi
}
# tomato update: a fake release, checksum failures and non-official URLs. It changes the installed command, so it has one of its own.
t_cli_update() {
  need_install
  home="$work/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"; t="$home/bin/tomato"
  ./install-native.sh > /dev/null 2>&1
  fake="$work/fake"; mkdir -p "$fake"; cp VERSION "$fake/VERSION.old"
  TOMATO_RELEASE_OUT="$fake/out" sh release/build.sh "file://$fake/t.tar.gz" > /dev/null && cp "$fake"/out/tomato-*.tar.gz "$fake/t.tar.gz"
  want="$(sha256 "$fake/t.tar.gz" | cut -d' ' -f1)"
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
t_cli_compile() { cli_setup; check "compile writes IR" "yes" "$($t compile examples/shapes.tom | grep -q 'define i32 @main' && echo yes)"; }
section "== command line =="
spawn t_cli_modes
for name in int_boundary big_numbers bitwise floor_divide_power containers cycle list_ops compound_ops fixed_width numbers_rules; do
  spawn t_cli_release_like_debug "$name"
done
spawn t_cli_release_no_leak
spawn t_cli_explain
spawn t_cli_repl_1
spawn t_cli_color
spawn t_cli_warnings
spawn t_cli_repl_2
spawn t_cli_repl_history
spawn t_cli_update
spawn t_cli_compile

# ---- rejected programs --------------------------------------------------------------------------------------------------
t_neg() { # file, message that the compiler must report
  msg="$("$c1" "tests/negative/$1.tom" main std/ 2>&1 >/dev/null)"; code=$?
  case "$msg" in *"$2"*) [ $code -ne 0 ] && ok "rejects $1" || bad "rejects $1" "exit status was 0";; *) bad "rejects $1" "wanted: $2
got:    $msg";; esac
}
neg() { spawn t_neg "$@"; }
section "== rejected programs =="
neg type_mismatch "cannot use '+' with int and str"
neg generic_keyword_args "keyword arguments are not supported when creating an object"
neg clock_args "clock() takes no arguments"
neg fixed_range "300 does not fit in uint[length=8]"
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
neg await_outside_async "'await' can only be used inside an async function"
neg generic_no_type "'Box' is generic, so it needs its type arguments: Box[T]"
neg generic_cannot_infer "cannot tell what T is in this call of 'Stack'"
neg generic_wrong_item "argument 1 of 'put' (the parameter 'item') has type str, but int is expected"
neg generic_mixed_items "a list item has type str, but int is expected"
neg await_non_task "only a task can be awaited, but this is int"
neg await_in_conditional "an await cannot be in either value of a conditional expression"
neg async_init "cannot be async"
neg invert_on_text "cannot use '~' on str"
neg set_item_without_marker "objects cannot be assigned by index"
neg frozen_item_assign "'bitarray.frozenbitarray' objects cannot be assigned by index"
neg mixed_bit_types "the right operand of & has type bitarray.frozenbitarray"
neg frozen_bits_field "the field 'bits' is private to class 'bitarray.frozenbitarray'"
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

# ---- input --------------------------------------------------------------------------------------------------------------
t_input() {
  f="$1"; n="$(basename "$f" .tom)"
  "$c1" "$f" main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" runtime/tomato_rt.c -lm || { bad "input $n" "did not build: $(cat "$work/e")"; return; }
  "$work/i" < "tests/input/$n.in" > "$work/o" 2>&1
  if cmp -s "$work/o" "tests/input/$n.out"; then ok "input $n"; else bad "input $n" "$(diff "$work/o" "tests/input/$n.out" | head -6)"; fi
  if [ -n "$have_js" ]; then
    jsc native/tomato-jsc.js -- site/wasm run "$f" "tests/input/$n.in" > "$work/js.out" 2> "$work/js.err"
    if [ "$(cat "$work/js.out" "$work/js.err" | grep -v '^~rc ')" = "$(cat "tests/input/$n.out")" ]; then ok "wasm input $n"; else bad "wasm input $n" "$(cat "$work/js.out" "$work/js.err" | head -6)"; fi
  fi
}
section "== input (tests/input: the file NAME.in is the standard input, NAME.out the whole output) =="
for f in tests/input/*.tom; do spawn t_input "$f"; done

# ---- error ids ----------------------------------------------------------------------------------------------------------
t_error_templates() {
  tests/error_templates.sh | awk '{ l=$0; gsub(/\{\}/,"",l); if (length(l) >= 12) print }' > "$work/templates"
  missing=""
  while IFS= read -r tpl; do grep -qxF "CompileError $tpl" std/errors.txt || missing="$missing
  $tpl"; done < "$work/templates"
  [ -z "$missing" ] && ok "every extracted compile error template has an id in std/errors.txt" || bad "every extracted compile error template has an id in std/errors.txt" "add these lines (CompileError TEMPLATE):$missing"
}
t_error_raises() {
  missing="$(awk '
    NR == FNR { classes[NR] = $1; next }
    /raise [[:alnum:]_]+\(/ && !/^ *#/ {
      line = $0
      sub(/^.*raise /, "", line)
      sub(/\(.*/, "", line)
      if (!match($0, /\047E[0-9]+\047\)$/) || classes[substr($0, RSTART + 2, RLENGTH - 4) + 0] != line)
        print FILENAME ":" FNR ": " $0
    }' std/errors.txt std/*.tom)"
  [ -z "$missing" ] && ok "standard-library raises have IDs for their classes" || bad "standard-library raises have IDs for their classes" "$missing"
}
section "== error ids =="
spawn t_error_templates
spawn t_error_raises

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
  "$c1" "tests/runtime/$1.tom" main std/ > "$work/r.ll" 2>/dev/null && clang -O1 -w -o "$work/r" "$work/r.ll" runtime/tomato_rt.c -lm || { bad "runtime $1" "did not build"; return; }
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
rt dict_missing_key "the key is not there" 1
rt set_missing "the element is not there" 1
rt rational_zero "a rational cannot have a zero denominator" 1
rt progress_bar_live "live: 100%|####| 2/2" 0
rt float_overflow "infinite or not a number" 1
rt negative_exponent "a negative exponent needs a float" 1
rt stack_overflow "stack overflow" 1
rt tan_quarter "tan is not defined at 90 deg" 1
rt sqrt_negative "sqrt needs a number that is not negative, but got -4.0" 1
rt asin_domain "asin needs a number from -1 to 1, but got 1.5" 1
rt atan2_origin "atan2(0, 0) has no angle" 1
rt exp_overflow "exp(1000) is too large to be a float" 1
rt log_zero "log needs a positive number, but got 0.0" 1
rt log_base_zero "a logarithm base must be positive and not 1, but got 0.0" 1
rt caught_domain "caught sqrt needs a number that is not negative" 0
rt angle_base "Angle is a base class" 1
rt chr_range "chr() takes a number from 0 to 1114111, not a surrogate" 1
rt ord_length "ord() takes a text of exactly one character" 1
rt chr_huge "chr() takes a number from 0 to 1114111, not a surrogate" 1
rt msgpack_missing "error[E25]: IOError: could not open '/nonexistent_dir_for_tomato/missing.msgpack': No such file or directory" 1
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

t_no_entropy() {
  n="$1"
  "$c1" "tests/runtime/$n.tom" main std/ > "$work/r.ll" 2>/dev/null && clang -O1 -w -DTOMATO_TEST_NO_ENTROPY -o "$work/r" "$work/r.ll" runtime/tomato_rt.c -lm || { bad "runtime $n" "did not build"; return; }
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
  for name in random_basic random_lists secrets_basic uuid_basic; do spawn t_wasm_program "$name"; done
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
  if "$c1" "$f" main std/ > "$work/g.ll" 2>/dev/null && clang -O1 -w -o "$work/g" "$work/g.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
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
spawn t_docs_in_sync
if [ "$(uname)" = Darwin ] && command -v pkgbuild >/dev/null 2>&1; then serial_last t_release_pkg; fi   # the macOS installer package

# ---- benchmarks and the rest --------------------------------------------------------------------------------------------
t_benchmarks() { # serial (last): it measures, so it must not compete with the other tests
  r="$(sh benchmarks/run.sh --smoke 2>&1 | grep -v -e " done$" -e " built$" -e " runs$" | tail -20)"; rc=$?; [ -n "${r##ok:*}" ] && rc=1
  if [ $rc -eq 0 ]; then ok "benchmarks: the Tomato, Go, Rust and Python versions print the same"; else bad "benchmarks: the versions print the same" "$r"; fi
}
t_versions() {
  cmp -s docs/provisional.md site/docs/PROVISIONAL.md && ok "site/docs/PROVISIONAL.md is in sync" || bad "site/docs/PROVISIONAL.md is in sync" "run site/build.sh"
  check "VERSION matches site/latest.json" "$(cat VERSION)" "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)"
  check "VERSION matches site/config.js" "$(cat VERSION)" "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)"
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
serial_last t_benchmarks
spawn t_versions
spawn t_wasm_sections
if [ -n "$WASI_SDK" ]; then serial_last t_wasm_rebuild; fi   # with the toolchain, rebuild and compare byte for byte

finish
t_end="$(date +%s)"
passes=0; fails=0
[ -f "$shared/passed" ] && passes=$(($(wc -l < "$shared/passed")))
[ -f "$shared/failed" ] && fails=$(($(wc -l < "$shared/failed")))
echo; echo "$passes passed, $fails failed"
if [ -n "$times" ] && [ -s "$shared/times" ]; then   # --times: where the time goes (a test's time is its own, from start to end; tests overlap, so the run is shorter than the sum)
  echo; echo "slowest 20 tests (seconds), of the whole run's $((t_end - t_start)) s:"
  sort -t "$(printf '\t')" -rn -k1,1 "$shared/times" | head -20 | awk -F'\t' '{ s = $2; sub(/^== /, "", s); sub(/ ==$/, "", s); printf "%8.1f  %s   [%s]\n", $1 / 1000, $3, substr(s, 1, 44) }'
  echo; echo "per section (seconds): the sum of its tests, the slowest one, the number of tests"
  awk -F'\t' '{ t[$2] += $1; if ($1 > m[$2]) m[$2] = $1; c[$2]++ }
    END { for (k in t) { s = k; sub(/^== /, "", s); sub(/ ==$/, "", s); printf "%9.1f %8.1f %5d  %s\n", t[k] / 1000, m[k] / 1000, c[k], substr(s, 1, 60) } }' "$shared/times" | sort -rn
fi
[ "$fails" -eq 0 ]
