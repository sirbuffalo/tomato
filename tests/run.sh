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

echo "== examples =="
grep -v '^#' tests/examples.txt | while read -r name entry rest; do echo "$name $entry $rest"; done > "$work/list"
while read -r name entry rest; do
  "$work/c1" "examples/$name.tom" "$entry" std/ > "$work/p.ll" 2> "$work/e" || { echo "FAIL $name $entry: $(cat "$work/e")"; echo x >> "$work/failed"; continue; }
  clang -O1 -w -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm || { echo "FAIL $name $entry: link"; echo x >> "$work/failed"; continue; }
  # shellcheck disable=SC2086
  "$work/p" $rest > "$work/out" 2>&1 < /dev/null
  if cmp -s "$work/out" "tests/expected/$name.$entry.out"; then echo "ok   $name $entry"; echo x >> "$work/passed"; else echo "FAIL $name $entry"; diff "$work/out" "tests/expected/$name.$entry.out" | head -5 | sed 's/^/     /'; echo x >> "$work/failed"; fi
done < "$work/list"
[ -f "$work/passed" ] && passes=$((passes + $(wc -l < "$work/passed")))
[ -f "$work/failed" ] && fails=$((fails + $(wc -l < "$work/failed")))

echo "== command line =="
home="$work/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"
./install-native.sh > /dev/null 2>&1 && ok "install-native.sh" || bad "install-native.sh"
t="$home/bin/tomato"
check "version" "Tomato v$(cat VERSION) (compiler written in Tomato)" "$($t version)"
check "run with inputs" "17 True" "$($t run examples/args.tom prime 17)"
check "unknown command exits 2" "2" "$($t wghwrltghs >/dev/null 2>&1; echo $?)"
printf '@main\ndef main(a: str, b: str):\n    print("[" + a + "][" + b + "]")\n' > "$work/echo.tom"
check "glob and empty inputs survive" "[*][]" "$(cd "$work" && $t run echo.tom main '*' '')"
check "-- passes flag-like inputs" "[-o][--entry]" "$($t run "$work/echo.tom" -- main -o --entry)"
check "repl: variables, functions, new output only" "7
9
hi" "$(printf 'x = 3\nx + 4\ndef sq(n: int) -> int:\n    return n * n\n\nsq(x)\nprint("hi")\n:quit\n' | $t repl)"
check "repl: += works" "8" "$(printf 'x = 5\nx += 3\nx\n:quit\n' | $t repl)"
check "repl: leave() leaves" "a" "$(printf "print('a')\nleave()\nprint('b')\n" | $t repl)"
check "compile writes IR" "yes" "$($t compile examples/shapes.tom | grep -q 'define i32 @main' && echo yes)"

echo "== rejected programs =="
neg() { # file, message that the compiler must report
  msg="$("$work/c1" "tests/negative/$1.tom" main std/ 2>&1 >/dev/null)"; code=$?
  case "$msg" in *"$2"*) [ $code -ne 0 ] && ok "rejects $1" || bad "rejects $1" "exit status was 0";; *) bad "rejects $1" "wanted: $2
got:    $msg";; esac
}
neg type_mismatch "cannot use + with int and str"
neg fixed_range "does not fit uint[length=8]"
neg unknown_name "unknown name nothing"
neg bad_assign "the assigned value is str where int is needed"
neg non_bool_condition "a condition is int where bool is needed"

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


echo "== release files =="
check "VERSION matches site/latest.json" "$(cat VERSION)" "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)"
check "VERSION matches site/config.js" "$(cat VERSION)" "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)"
check "site/wasm matches the compiler IR and runtime" "$(cat compiler/bootstrap/tomatoc.ll runtime/tomato_rt.c | shasum -a 256 | cut -d' ' -f1)" "$(cat site/wasm/SOURCE.sha256 2>/dev/null)"

echo; echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
