# tier: full
# `tomato run` with a program, part two: File inputs, the program's own exit status and error text in both modes, standard input, the environment
# the program sees, warnings, and a FILE with a slash. (links a program per check; run_forms.sh is part one)
. "$CONTRACT_DIR/lib.sh"

cat > ent.tom <<'EOT'
import sys

@main
def main(a: str = "x", b: int = 3):
    print("[" + a + "]", b)

@echo
def echo(*words: tuple[str]):
    print(len(words), words)

@greet.loud
def loud():
    print("LOUD")

@greet.quiet
def quiet():
    print("quiet")

@num
def num(n: int, flag: bool = False):
    print(n, flag)

@exit3
def exit3():
    sys.exit(3)

@boom
def boom():
    raise ValueError("boom")

@cat
def cat(data: File):
    print(data.read())

@stdin_lines
async def stdin_lines():
    print(len(await input()))
EOT
printf '@main\ndef main():\n    print("hi")\n' > hi.tom
printf 'line1\nline2\n' > data.txt

# File inputs: the word is a file the runner opens before the entry runs; - is standard input
try "run: a File input is opened and read" 0 "line1
line2
" "" run ent.tom cat data.txt
printf 'from stdin\n' | "$TOMATO" run ent.tom cat - > "$W/o" 2> "$W/e"; rc=$?
check "run: a File input of - is standard input" "0 from stdin" "$rc $(cat "$W/o")"
try "run: a File input that cannot be opened is E592 naming the input" 1 "" "error[E592]: input 1 must be a file that can be read, but 'nosuch.txt' cannot be opened: No such file or directory" run ent.tom cat nosuch.txt
# the program's own end: its exit status, its error text, in both modes
try "run: sys.exit(3) is the exit status of tomato run" 3 "" "" run ent.tom exit3
try "run: an uncaught error: text and the call, status 1" 1 "" "error: ValueError: boom (raised on line 29)
  at boom (line 29)" run ent.tom boom
try "run: after the entry, --mode release is two inputs, not options" 1 "" "error[E352]: boom takes no inputs, but got 2
usage: boom" run ent.tom boom --mode release
try "run: --mode release before the entry" 1 "" "error[E11]: ValueError: boom (line 29)" run --mode release ent.tom boom
printf '@main\ndef main():\n    x = 0\n    print(5 // x)\n' > dz.tom
try "run: a runtime error in debug mode: id, message and the function with its line" 1 "" "error[E01]: division by zero
  at main (line 4)" run dz.tom
try "run: the same in release mode" 1 "" "error[E01]: division by zero (line 4)" run dz.tom --mode release
try "run: --mode debug is the default" 1 "" "error[E01]: division by zero
  at main (line 4)" run dz.tom --mode debug
printf '@main\ndef main():\n    x = 0\n    print(1)\n    print(1 // x)\n' > partial.tom
try "run: output before the error is kept, on standard output" 1 "1" "error[E01]: division by zero
  at main (line 5)" run partial.tom
printf 'print(1)\n' > top.tom
try "run: code outside a function gets a hint" 1 "" "~put it inside a function marked @main" run top.tom
# standard input and the environment reach the program unchanged
printf 'abc\n' | "$TOMATO" run ent.tom stdin_lines > "$W/o" 2> "$W/e"
check "run: the program reads tomato's standard input" "3" "$(cat "$W/o")"
printf 'import os\n\n@main\ndef main():\n    print(os.getenv("CONTRACT_PROBE"))\n    print(os.getenv("TOMATO_COLOR"))\n' > env.tom
CONTRACT_PROBE=seen "$TOMATO" run env.tom > "$W/o" 2> "$W/e"
check "run: the program sees the caller's environment" "seen
None" "$(cat "$W/o")"
"$TOMATO" run --color=always env.tom > "$W/o" 2> "$W/e"
check "run --color=always: the program is told, through TOMATO_COLOR" "None
always" "$(cat "$W/o")"
TOMATO_COLOR=never "$TOMATO" run env.tom > "$W/o" 2> "$W/e"
check "run: TOMATO_COLOR is passed on as it is" "None
never" "$(cat "$W/o")"
# a path with a slash is a FILE even when it does not end in .tom
mkdir -p sub; cp hi.tom sub/hi
try "run: a word with a slash is the file, whatever its ending" 0 "hi" "" run sub/hi
try "run: a path from another folder" 0 "[x] 3" "" run "$W/ent.tom"
# the warnings of the compiler come first, on standard error, and the program still runs
printf '@main\ndef main():\n    unused = 1\n    print(2)\n' > warn.tom
try "run: a warning is shown on standard error, then the program runs" 0 "2" @warning.txt run warn.tom
try "run --no-warnings hides it" 0 "2" "" run warn.tom --no-warnings
( export TOMATO_WARNINGS=off; try "run: TOMATO_WARNINGS=off hides it too" 0 "2" "" run warn.tom )
# a feature on the unstable list (docs/provisional.md, D121a) warns too, once, and the program still runs; the allow comment and the switches hide it
printf 'from random import Random, choice, sample\n\n@main\ndef main():\n    rng = Random(1)\n    print(len(sample(rng, [1, 2, 3], 2)), choice(rng, [7]))\n' > unstable.tom
try "run: a feature of the unstable list warns on standard error, then the program runs" 0 "2 7" @unstable_warning.txt run unstable.tom
try "run --no-warnings hides the unstable-feature warning" 0 "2 7" "" run unstable.tom --no-warnings
sed 's/^from random import .*/&  # allow: unstable/' unstable.tom > unstable_ok.tom
try "run: # allow: unstable on the import line hides it" 0 "2 7" "" run unstable_ok.tom
