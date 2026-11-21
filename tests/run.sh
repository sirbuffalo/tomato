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

echo "== decided rules (programs) =="
grep -v '^#' tests/programs.txt | while read -r name; do
  "$work/c1" "tests/programs/$name.tom" main std/ > "$work/p.ll" 2> "$work/e" && clang -O1 -w -o "$work/p" "$work/p.ll" runtime/tomato_rt.c -lm && "$work/p" > "$work/out" 2>&1
  if cmp -s "$work/out" "tests/expected/$name.main.out"; then echo "ok   program $name"; echo x >> "$work/passed2"; else echo "FAIL program $name"; diff "$work/out" "tests/expected/$name.main.out" | head -5 | sed 's/^/     /'; echo x >> "$work/failed2"; fi
done
[ -f "$work/passed2" ] && passes=$((passes + $(wc -l < "$work/passed2")))
[ -f "$work/failed2" ] && fails=$((fails + $(wc -l < "$work/failed2")))

echo "== memory (AddressSanitizer and the runtime's leak check) =="
for spec in "examples/shapes:" "examples/objects:4" "tests/programs/cycle:" "tests/programs/containers:" "tests/programs/modules:"; do
  path="${spec%%:*}"; name="$(basename "$path")"; arg="${spec#*:}"
  "$work/c1" "$path.tom" main std/ > "$work/p.ll" 2>/dev/null
  if clang -O1 -w -g -fsanitize=address -o "$work/asan" "$work/p.ll" runtime/tomato_rt.c -lm 2>/dev/null; then
    out="$("$work/asan" $arg 2>&1 >/dev/null | head -3)"
    [ -z "$out" ] && ok "asan $name" || bad "asan $name" "$out"
  else bad "asan $name" "this clang cannot build with -fsanitize=address"; fi
done

echo "== the same programs through WebAssembly (site/wasm, the website and repl path) =="
jsc=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc
if [ -x "$jsc" ]; then
  for name in containers finally inheritance fixed_width text_and_maps; do
    "$jsc" native/tomato-jsc.js -- site/wasm run "tests/programs/$name.tom" > "$work/js.out" 2> "$work/js.err"
    # the runner drops one trailing newline and adds an "~rc" line; compare ignoring both
    if [ "$(cat "$work/js.out")" = "$(cat "tests/expected/$name.main.out")" ]; then ok "wasm $name"; else bad "wasm $name" "$(diff "$work/js.out" "tests/expected/$name.main.out" | head -4; head -2 "$work/js.err")"; fi
  done
else echo "skip: jsc is not available on this system"; fi

echo "== command line =="
home="$work/home"; export TOMATO_HOME="$home" TOMATO_BIN="$home/bin"
./install-native.sh > /dev/null 2>&1 && ok "install-native.sh" || bad "install-native.sh"
t="$home/bin/tomato"
printf 'print(1)\n' > "$work/top.tom"
r="$($t run "$work/top.tom" 2>&1)"; case "$r" in *"put them in a function marked @main"*) ok "top-level code gives a clear hint";; *) bad "top-level code gives a clear hint" "$r";; esac
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
r="$(TOMATO_UPDATE_URL=file://$fake/ok.json $t update 2>&1)"; case "$r" in *"not an official release URL"*) ok "update refuses a non-official URL";; *) bad "update refuses a non-official URL" "$r";; esac
TOMATO_UPDATE_URL=file://$fake/ok.json TOMATO_UPDATE_ALLOW_ANY_URL=1 $t update > /dev/null 2>&1
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
neg type_mismatch "cannot use + with int and str"
neg fixed_range "does not fit uint[length=8]"
neg unknown_name "unknown name nothing"
neg private_field "is private to class C"
neg const_field "cannot change after initialization"
neg bad_argument "argument 1 of f is str where int is needed"
neg bad_return "the returned value is str where int is needed"
neg dead_range_literal "does not fit uint[length=8]"
neg wrong_type_in_branch "the assigned value is str where int is needed"
neg non_ascii "only supports ASCII text literals"
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
rt dict_missing_key "the key is not there" 1
rt set_missing "the element is not there" 1


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
cmp -s docs/provisional.md site/docs/PROVISIONAL.md && ok "site/docs/PROVISIONAL.md is in sync" || bad "site/docs/PROVISIONAL.md is in sync" "run site/build.sh"
check "VERSION matches site/latest.json" "$(cat VERSION)" "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)"
check "VERSION matches site/config.js" "$(cat VERSION)" "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)"
check "site/wasm matches the compiler IR and runtime" "$(cat compiler/bootstrap/tomatoc.ll runtime/tomato_rt.c | shasum -a 256 | cut -d' ' -f1)" "$(cat site/wasm/SOURCE.sha256 2>/dev/null)"

echo; echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
