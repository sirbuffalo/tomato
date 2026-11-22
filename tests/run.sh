#!/bin/sh
# The test suite, in shell: it needs only clang. Usage: tests/run.sh
#   1. builds the compiler from compiler/bootstrap/tomatoc.ll and checks that it reproduces itself and that the
#      checked-in IR is current (the fixed point)
#   2. compiles and runs every example with the expected output in tests/expected
#   3. checks the command line (tomato run/build/compile/repl/update/version/help)
cd "$(dirname "$0")/.." || exit 1
root="$(pwd)"; work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fails=0; passes=0
ok() { passes=$((passes + 1)); echo "ok   $1"; }
bad() { fails=$((fails + 1)); echo "FAIL $1"; [ -n "$2" ] && echo "$2" | sed 's/^/     /'; }
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2
got:      $3"; fi
}
cc() { clang -O1 -w -o "$1" "$2" "$root/runtime/tomato_rt.c" -lm; }

echo "== compiler =="
cc "$work/c0" compiler/bootstrap/tomatoc.ll && ok "builds from the bootstrap IR" || { bad "builds from the bootstrap IR"; exit 1; }
"$work/c0" compiler/src/ctool.tom compile > "$work/ir1.ll" 2> "$work/e" && ok "compiles its own source" || bad "compiles its own source" "$(cat "$work/e")"
cc "$work/c1" "$work/ir1.ll" && "$work/c1" compiler/src/ctool.tom compile > "$work/ir2.ll"
cmp -s "$work/ir1.ll" "$work/ir2.ll" && ok "stage 2 reproduces itself (fixed point)" || bad "stage 2 reproduces itself (fixed point)"
cmp -s "$work/ir2.ll" compiler/bootstrap/tomatoc.ll && ok "compiler/bootstrap/tomatoc.ll is current" || bad "compiler/bootstrap/tomatoc.ll is current" "run compiler/bootstrap/refresh.sh"

grep -q '^;! ' "$work/ir1.ll" && bad "the compiler's own source compiles without warnings" "$(grep '^;! ' "$work/ir1.ll" | head -6)" || ok "the compiler's own source compiles without warnings"

echo "== examples =="
grep -v '^#' tests/examples.txt | while read -r name entry rest; do echo "$name $entry $rest"; done > "$work/list"
while read -r name entry rest; do
  "$work/c1" "examples/$name.tom" "$entry" std/ > "$work/p.ll" 2> "$work/e" || { echo "FAIL $name $entry: $(cat "$work/e")"; echo x >> "$work/failed"; continue; }
  grep -q '^;! ' "$work/p.ll" && { echo "FAIL $name $entry: warnings"; grep '^;! ' "$work/p.ll" | head -6 | sed 's/^/     /'; echo x >> "$work/failed"; continue; }
  clang -O1 -w -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm || { echo "FAIL $name $entry: link"; echo x >> "$work/failed"; continue; }
  # shellcheck disable=SC2086
  "$work/p" $rest > "$work/out" 2>&1 < /dev/null
  if cmp -s "$work/out" "tests/expected/$name.$entry.out"; then echo "ok   $name $entry"; echo x >> "$work/passed"; else echo "FAIL $name $entry"; diff "$work/out" "tests/expected/$name.$entry.out" | head -5 | sed 's/^/     /'; echo x >> "$work/failed"; fi
done < "$work/list"
[ -f "$work/passed" ] && passes=$((passes + $(wc -l < "$work/passed")))
[ -f "$work/failed" ] && fails=$((fails + $(wc -l < "$work/failed")))

echo "== decided rules (programs) =="
grep -v '^#' tests/programs.txt | while read -r name; do
  "$work/c1" "tests/programs/$name.tom" main std/ > "$work/p.ll" 2> "$work/e"
  if grep -q '^;! ' "$work/p.ll"; then echo "FAIL program $name has warnings"; echo x >> "$work/failed2"; continue; fi
  [ -s "$work/p.ll" ] && clang -O1 -w -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm && "$work/p" > "$work/out" 2>&1
  if cmp -s "$work/out" "tests/expected/$name.main.out"; then echo "ok   program $name"; echo x >> "$work/passed2"; else echo "FAIL program $name"; diff "$work/out" "tests/expected/$name.main.out" | head -5 | sed 's/^/     /'; echo x >> "$work/failed2"; fi
done
[ -f "$work/passed2" ] && passes=$((passes + $(wc -l < "$work/passed2")))
[ -f "$work/failed2" ] && fails=$((fails + $(wc -l < "$work/failed2")))

echo "== memory (AddressSanitizer and the runtime's leak check) =="
for spec in "examples/shapes:" "examples/objects:4" "tests/programs/cycle:" "tests/programs/gc_cycles:" "tests/programs/containers:" "tests/programs/modules:" "tests/programs/borrow_elision:" "tests/programs/native_sort:" "tests/programs/bigint_ownership:" "tests/programs/bigint_ops:" "tests/programs/bigint_frames:" "tests/programs/bigint_unwind:" "tests/programs/big_numbers:" "tests/programs/big_mul:" "tests/programs/unlimited_int:"; do
  path="${spec%%:*}"; name="$(basename "$path")"; arg="${spec#*:}"
  "$work/c1" "$path.tom" main std/ > "$work/p.ll" 2>/dev/null
  if clang -O1 -w -g -fsanitize=address -o "$work/asan" "$work/p.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
    out="$("$work/asan" $arg 2>&1 >/dev/null | head -3)"
    [ -z "$out" ] && ok "asan $name" || bad "asan $name" "$out"
  else bad "asan $name" "this clang cannot build with -fsanitize=address"; fi
done

echo "== sort: the heapsort fallback gives the same results =="
"$work/c1" tests/programs/native_sort.tom main std/ > "$work/p.ll" 2>/dev/null && clang -O1 -w -DSORT_DEPTH_MUL=0 -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm && "$work/p" > "$work/out" 2>&1
check "sort with the depth limit forced to 0" "$(cat tests/expected/native_sort.main.out)" "$(cat "$work/out")"

echo "== the same programs through WebAssembly (site/wasm, the website and repl path) =="
jsc=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc
if [ -x "$jsc" ]; then
  for name in angles containers finally inheritance fixed_width text_and_maps modules numbers_rules range_value iter_protocol async_tasks generics bigint_ops bigint_ownership bigint_frames bigint_unwind; do
    "$jsc" native/tomato-jsc.js -- site/wasm run "tests/programs/$name.tom" > "$work/js.out" 2> "$work/js.err"
    # the runner drops one trailing newline and adds an "~rc" line; compare ignoring both
    if [ "$(cat "$work/js.out")" = "$(cat "tests/expected/$name.main.out")" ]; then ok "wasm $name"; else bad "wasm $name" "$(diff "$work/js.out" "tests/expected/$name.main.out" | head -4; head -2 "$work/js.err")"; fi
  done
  # rejected programs and runtime errors through the same path (the messages and failures must agree with native)
  wasm_neg() { m="$("$jsc" native/tomato-jsc.js -- site/wasm run "tests/negative/$1.tom" 2>&1)"; case "$m" in *"$2"*"~rc 1"*) ok "wasm rejects $1";; *) bad "wasm rejects $1" "wanted: $2
got: $m";; esac; }
  wasm_rt() { m="$("$jsc" native/tomato-jsc.js -- site/wasm run "tests/runtime/$1.tom" 2>&1)"; case "$m" in *"$2"*"~rc $3"*) ok "wasm runtime $1";; *) bad "wasm runtime $1" "wanted: $2 (rc $3)
got: $m";; esac; }
  wasm_neg type_mismatch "cannot use '+' with int and str"
  wasm_neg fixed_range "300 does not fit in uint[length=8]"
  wasm_neg private_field "the field 'x' is private to class 'C'"
  wasm_neg bad_return "the returned value has type str, but int is expected"
  wasm_neg trig_needs_angle "argument 1 of 'sin' (the parameter 'a') has type float, but math.Angle is expected"
  wasm_rt divide_by_zero "division by zero" 1
  wasm_rt index "index out of range" 1
  wasm_rt overflow "integer overflow" 1
  wasm_rt dict_missing_key "the key is not there" 1
  wasm_rt caught "caught boom" 0
  wasm_rt stack_overflow "stack overflow" 1
  wasm_rt tan_quarter "tan is not defined at 90 deg" 1
  wasm_rt caught_domain "caught sqrt needs a number that is not negative" 0
  wasm_rt exp_overflow "exp(1000) is too large to be a float" 1
  wasm_rt trace_calls "at half (line 10)" 1
  r="$("$jsc" tests/site_errors.js 2>&1)"; [ "$r" = ok ] && ok "website: tomatoErrors keeps the words, escapes them, styles with classes" || bad "website: tomatoErrors" "$r"
else [ -n "$CI" ] && bad "wasm path" "jsc is required in CI (macOS runner)" || echo "skip: jsc is not available on this system"; fi

echo "== command line =="
home="$work/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"
./install-native.sh > /dev/null 2>&1 && ok "install-native.sh" || bad "install-native.sh"
t="$home/bin/tomato"
printf 'print(1)\n' > "$work/top.tom"
r="$($t run "$work/top.tom" 2>&1)"; case "$r" in *"put it inside a function marked @main"*) ok "top-level code gives a clear hint";; *) bad "top-level code gives a clear hint" "$r";; esac
check "version" "Tomato v$(cat VERSION) (compiler written in Tomato)" "$($t version)"
printf '@main\ndef main():\n    x = 0\n    print(5 // x)\n' > "$work/dz.tom"
check "mode debug is readable" "error: division by zero
  at main (line 4)" "$($t run "$work/dz.tom" 2>&1)"
check "mode release prints a code" "error E01:4" "$($t run "$work/dz.tom" --mode release 2>&1)"
check "mode normal was renamed to release" "error: the mode 'normal' was renamed to 'release': use --mode release (the old release mode is gone)" "$($t run "$work/dz.tom" --mode normal 2>&1)"
check "unknown mode is refused" "error: the mode must be debug or release, not 'fast'" "$($t run "$work/dz.tom" --mode fast 2>&1)"
$t build "$work/dz.tom" -o "$work/dz_rel" --mode release > /dev/null 2>&1; check "build --mode release makes a release binary" "error E01:4" "$("$work/dz_rel" 2>&1)"
check "compile --mode release works" "tomato_report_uncaught" "$($t compile "$work/dz.tom" --mode release 2>&1 | grep -o tomato_report_uncaught | head -1)"
# release links with LTO and an inlined runtime: the same programs must print exactly what debug mode prints
for name in int_boundary big_numbers bitwise floor_divide_power containers cycle list_ops compound_ops fixed_width numbers_rules; do
  check "release mode runs $name like debug" "$(cat "tests/expected/$name.main.out")" "$($t run "tests/programs/$name.tom" --mode release 2>&1)"
done
$t build tests/programs/cycle.tom -o "$work/cyc_rel" --mode release > /dev/null 2>&1; check "release mode does not print a leak report" "$(cat tests/expected/cycle.main.out)" "$("$work/cyc_rel" 2>&1)"
check "explain decodes a release code" "error: division by zero" "$($t explain E01:4 "$work/dz.tom" 2>&1 | head -1)"
check "explain decodes a code" "error: division by zero
  line 4: print(5 // x)" "$($t explain E01:4 "$work/dz.tom")"
check "run with inputs" "17 True" "$($t run examples/args.tom prime 17)"
check "--version is version" "$($t version)" "$($t --version)"
case "$($t help)" in *"tomato explain"*"tomato version"*) ok "help lists every command";; *) bad "help lists every command" "$($t help)";; esac
check "explain says when the line is not in the file" "error: division by zero
  (line 999 is past the end of $work/dz.tom: is this the file the program was built from?)" "$($t explain E01:999 "$work/dz.tom")"
check "unknown command exits 2" "2" "$($t wghwrltghs >/dev/null 2>&1; echo $?)"
printf '@main\ndef main():\n    print(tets)\n' > "$work/typo.tom"
printf '@main\ndef main(a: str, b: str):\n    print("[" + a + "][" + b + "]")\n' > "$work/echo.tom"
check "glob and empty inputs survive" "[*][]" "$(cd "$work" && $t run echo.tom main '*' '')"
check "-- passes flag-like inputs" "[-o][--entry]" "$($t run "$work/echo.tom" -- main -o --entry)"
check "repl: variables, functions, new output only" "7
9
hi" "$(printf 'x = 3\nx + 4\ndef sq(n: int) -> int:\n    return n * n\n\nsq(x)\nprint("hi")\n:quit\n' | $t repl)"
check "repl: std imports resolve (itertools, math)" "True
False" "$(printf 'from math import is_prime\nfrom itertools import progress_bar\nis_prime(97)\nis_prime(91)\n:quit\n' | $t repl 2>&1)"
check "repl: :load runs a program that has its own @main" "$(cat tests/expected/shapes.main.out)" "$(printf ':load examples/shapes.tom\n:quit\n' | $t repl)"
check "repl: a block, then a failing line, then a good one" "9
error: cannot use '+' with int and str
5" "$(printf 'def sq(n: int) -> int:\n    return n * n\n\nsq(3)\nprint(1 + "a")\nsq(2) + 1\n:quit\n' | $t repl 2>&1 | grep -E '^(9|5|error:)')"
check "repl: a misspelled name says so, with the line and a suggestion" "error: name 'tets' is not defined
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
printf '@main\ndef main():\n    print(range(100))\n    print(range(1, 100))\n    print(range(5, 10, 2))\n' > "$work/rangeprint.tom"
check "tomato run prints a range as range(start, stop, step)" "range(0, 100, 1)
range(1, 100, 1)
range(5, 10, 2)" "$($t run "$work/rangeprint.tom" 2>&1)"
check "tomato run shows the same error text" "error: name 'tets' is not defined
 --> $work/typo.tom:3:11" "$($t run "$work/typo.tom" 2>&1 | head -2)"
printf '@main\ndef main():\n    half(0)\n\ndef half(n: int) -> int:\n    return 10 // n\n' > "$work/trace.tom"
check "an uncaught error shows the call trace, innermost first" "error: division by zero
  at half (line 6)
  at main (line 3)" "$($t run "$work/trace.tom" 2>&1)"
printf '@main\ndef main():\n    raise Error("bad")\n' > "$work/raised.tom"
check "an error the program raises shows where, then the trace" "error: Error: bad (raised on line 3)
  at main (line 3)" "$($t run "$work/raised.tom" 2>&1)"
check "--color=always paints a runtime error and its trace" "^[[1;31merror:^[[0m ^[[1mdivision by zero^[[0m
^[[2m  at half (line 6)^[[0m
^[[2m  at main (line 3)^[[0m" "$($t run "$work/trace.tom" --color=always 2>&1 | cat -v)"
check "--color=never keeps the plain words" "error: division by zero
  at half (line 6)
  at main (line 3)" "$($t run "$work/trace.tom" --color=never 2>&1 | cat -v)"
check "TOMATO_COLOR=always works like the flag" "^[[1;31merror:^[[0m ^[[1mdivision by zero^[[0m" "$(TOMATO_COLOR=always $t run "$work/trace.tom" 2>&1 | cat -v | head -1)"
check "without a terminal the color stays off (and NO_COLOR keeps it off)" "error: division by zero" "$(NO_COLOR=1 $t run "$work/trace.tom" 2>&1 | head -1)"
check "a bad --color value is refused" "error: --color takes auto, always or never, not 'blue'" "$($t run "$work/trace.tom" --color=blue 2>&1)"
check "--color=always paints a compile error: label, location, gutter, caret" "^[[1;31merror:^[[0m ^[[1mname 'tets' is not defined^[[0m
 ^[[1;34m-->^[[0m ^[[36m$work/typo.tom:3:11^[[0m
^[[1;34m  |^[[0m
^[[1;34m3 |^[[0m     print(tets)
^[[1;34m  |^[[0m           ^[[1;31m^^^^^[[0m" "$($t run "$work/typo.tom" --color=always 2>&1 | cat -v)"
printf '@main\ndef main():\n    unused = 1\n    print(2)\n' > "$work/warn.tom"
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
check "repl: --color=always paints the label red" "^[[1;31merror:^[[0m ^[[1mcannot use '+' with int and str^[[0m" "$(printf 'print(1 + "a")\n:quit\n' | $t repl --color=always 2>&1 | cat -v | head -1)"
check "repl: a runtime error shows no call trace of the generated program" "error: division by zero" "$(printf 'x = 0\nprint(1 // x)\n:quit\n' | $t repl 2>&1)"
check "repl: == is a comparison, = is an assignment" "False
3" "$(printf 'x = 3\nx == 4\nx\n:quit\n' | $t repl)"
case "$(printf ':help\n:quit\n' | $t repl 2>&1)" in *":reset"*":quit"*) ok "repl: :help lists every command";; *) bad "repl: :help lists every command";; esac
r="$(printf 'from nosuch_mod import a\n:quit\n' | $t repl 2>&1)"; case "$r" in *"Could not open"*|*"$TMPDIR"*|*"/tmp/"*|*"/var/folders/"*) bad "repl: a missing module shows no temp path or tool noise" "$r";; *"nosuch_mod"*) ok "repl: a missing module shows no temp path or tool noise";; *) bad "repl: a missing module shows no temp path or tool noise" "$r";; esac
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
if command -v expect >/dev/null 2>&1; then check "repl: up-arrow recalls a multi-line block as one history entry" "ok" "$(PATH="$(dirname "$t"):$PATH" expect tests/repl_history.exp 2>&1 | tail -1)"; fi
# tomato update: a fake release, checksum failures and non-official URLs
fake="$work/fake"; mkdir -p "$fake"; cp VERSION "$fake/VERSION.old"
TOMATO_RELEASE_OUT="$fake/out" sh release/build.sh "file://$fake/t.tar.gz" > /dev/null && cp "$fake"/out/tomato-*.tar.gz "$fake/t.tar.gz"
want="$(shasum -a 256 "$fake/t.tar.gz" | cut -d' ' -f1)"
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
check "release manifest names its own archive's checksum" "$(shasum -a 256 "$fake/out/tomato-$(cat VERSION).tar.gz" | cut -d' ' -f1)" "$manifest_sum"
check "compile writes IR" "yes" "$($t compile examples/shapes.tom | grep -q 'define i32 @main' && echo yes)"

echo "== rejected programs =="
neg() { # file, message that the compiler must report
  msg="$("$work/c1" "tests/negative/$1.tom" main std/ 2>&1 >/dev/null)"; code=$?
  case "$msg" in *"$2"*) [ $code -ne 0 ] && ok "rejects $1" || bad "rejects $1" "exit status was 0";; *) bad "rejects $1" "wanted: $2
got:    $msg";; esac
}
neg type_mismatch "cannot use '+' with int and str"
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
neg async_override_mismatch "must take and return the same types"
neg for_async_iter "needs async for"

echo "== input (tests/input: the file NAME.in is the standard input, NAME.out the whole output) =="
for f in tests/input/*.tom; do
  n="$(basename "$f" .tom)"
  "$work/c1" "$f" main std/ > "$work/i.ll" 2> "$work/e" && clang -O1 -w -o "$work/i" "$work/i.ll" runtime/tomato_rt.c -lm || { bad "input $n" "did not build: $(cat "$work/e")"; continue; }
  "$work/i" < "tests/input/$n.in" > "$work/o" 2>&1
  if cmp -s "$work/o" "tests/input/$n.out"; then ok "input $n"; else bad "input $n" "$(diff "$work/o" "tests/input/$n.out" | head -6)"; fi
  if [ -x "$jsc" ]; then
    "$jsc" native/tomato-jsc.js -- site/wasm run "$f" "tests/input/$n.in" > "$work/js.out" 2> "$work/js.err"
    if [ "$(cat "$work/js.out" "$work/js.err" | grep -v '^~rc ')" = "$(cat "tests/input/$n.out")" ]; then ok "wasm input $n"; else bad "wasm input $n" "$(cat "$work/js.out" "$work/js.err" | head -6)"; fi
  fi
done

echo "== error messages (tests/errors: the whole text, the one format everywhere) =="
for f in tests/errors/*.tom; do
  n="$(basename "$f" .tom)"; "$work/c1" "$f" main std/ > "$work/err.ll" 2> "$work/err.out"
  grep '^;! ' "$work/err.ll" | sed 's/^;! //' >> "$work/err.out"   # warnings travel as comment lines at the end of the IR
  if cmp -s "$work/err.out" "tests/errors/$n.out"; then ok "error text: $n"; else bad "error text: $n" "$(diff "$work/err.out" "tests/errors/$n.out" | head -6)"; fi
done

echo "== runtime errors and modes =="
rt() { # file, expected stderr text, expected exit status
  "$work/c1" "tests/runtime/$1.tom" main std/ > "$work/r.ll" 2>/dev/null && clang -O1 -w -o "$work/r" "$work/r.ll" runtime/tomato_rt.c -lm || { bad "runtime $1" "did not build"; return; }
  "$work/r" > "$work/o" 2> "$work/e2"; code=$?
  case "$(cat "$work/o" "$work/e2")" in *"$2"*) [ "$code" = "$3" ] && ok "runtime $1" || bad "runtime $1" "exit status $code, wanted $3";; *) bad "runtime $1" "wanted '$2', got: $(cat "$work/o" "$work/e2")";; esac
}
rt divide_by_zero "division by zero" 1
rt index "index out of range" 1
rt overflow "integer overflow" 1
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
rt trace_calls "at half (line 10)" 1


echo "== known gaps (decided behavior the compiler does not have yet) =="
# Each file is a program a decision says must be rejected (should_reject_*) or must work (should_work_*). The test passes
# while the gap exists and FAILS when the compiler gains the behavior, so the list cannot go stale: then move the program
# to tests/negative or tests/programs.
for f in tests/known_gaps/*.tom; do
  n="$(basename "$f" .tom)"
  accepted=no
  if "$work/c1" "$f" main std/ > "$work/g.ll" 2>/dev/null && clang -O1 -w -o "$work/g" "$work/g.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
    accepted=yes; "$work/g" > /dev/null 2>&1 || accepted=fails
  fi
  case "$n" in
    should_reject_*) [ "$accepted" = no ] && bad "known gap closed: $n" "move it to tests/negative" || ok "known gap: $n (still accepted)";;
    should_work_*) [ "$accepted" = yes ] && bad "known gap closed: $n" "move it to tests/programs" || ok "known gap: $n (still unsupported)";;
  esac
done

echo "== release files =="
for d in specification decisions decision-inventory open-questions; do cmp -s "docs/$d.md" "site/docs/$d.md" && ok "site/docs/$d.md is in sync" || bad "site/docs/$d.md is in sync" "run site/build.sh"; done
if [ "$(uname)" = Darwin ] && command -v pkgbuild >/dev/null 2>&1; then   # the macOS installer package
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
fi
echo "== benchmarks (tiny inputs only; the real run is benchmarks/run.sh) =="
r="$(sh benchmarks/run.sh --smoke 2>&1 | grep -v -e " done$" -e " built$" -e " runs$" | tail -20)"; rc=$?; [ -n "${r##ok:*}" ] && rc=1
if [ $rc -eq 0 ]; then ok "benchmarks: the Tomato, Go, Rust and Python versions print the same"; else bad "benchmarks: the versions print the same" "$r"; fi
cmp -s docs/provisional.md site/docs/PROVISIONAL.md && ok "site/docs/PROVISIONAL.md is in sync" || bad "site/docs/PROVISIONAL.md is in sync" "run site/build.sh"
check "VERSION matches site/latest.json" "$(cat VERSION)" "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)"
check "VERSION matches site/config.js" "$(cat VERSION)" "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)"
check "site/wasm matches the compiler IR and runtime" "$(cat compiler/bootstrap/tomatoc.ll runtime/tomato_rt.c | shasum -a 256 | cut -d' ' -f1)" "$(sed -n 1p site/wasm/SOURCE.sha256 2>/dev/null)"
check "the checked-in wasm files are the ones that were built" "$(sed -n 2,3p site/wasm/SOURCE.sha256)" "$(shasum -a 256 site/wasm/tomatoc.wasm site/wasm/runtime.wasm | cut -d' ' -f1)"
if [ -n "$WASI_SDK" ]; then   # with the toolchain, rebuild and compare byte for byte
  cp -R site/wasm "$work/wasm_orig"; WASI_SDK="$WASI_SDK" sh site/wasm/build.sh > /dev/null 2>&1
  cmp -s site/wasm/tomatoc.wasm "$work/wasm_orig/tomatoc.wasm" && cmp -s site/wasm/runtime.wasm "$work/wasm_orig/runtime.wasm" && ok "wasm files rebuild identically" || bad "wasm files rebuild identically" "run site/wasm/build.sh and commit"
fi

echo; echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
