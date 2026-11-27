# tier: full
# `tomato run` with a program: the forms FILE, FILE ENTRY INPUTS..., options before the entry and raw inputs after it, `--` (links a program per check)
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

try "run FILE: runs main" 0 "[x] 3" "" run ent.tom
try "run FILE ENTRY: main by name" 0 "[x] 3" "" run ent.tom main
try "run FILE ENTRY INPUTS: converted to the parameter types" 0 "[hello] 7" "" run ent.tom main hello 7
try "run: an input that is not an int is refused by the program" 1 "" "~error" run ent.tom main hello seven
try "run: a dotted marker runs every function under it" 0 "LOUD
quiet" "" run ent.tom greet
try "run: the entry by its own full marker" 0 "LOUD" "" run ent.tom greet.loud
try "run: an entry takes int and bool inputs" 0 "5 True" "" run ent.tom num 5 true
try "run: the inputs after the entry are raw: options, empty words, globs, spaces and dollar signs stay as they are" 0 "8 ('a', 'b c', '', '*', '-o', '--mode', '--', '\$HOME')" "" run ent.tom echo a "b c" "" '*' -o --mode -- '$HOME'
try "run: options go before the entry, between the file and the entry too" 0 "1 ('-v',)" "" run --no-warnings ent.tom --color=never echo -v
try "run: -- ends the options earlier; the next word is still the file or the entry" 0 "1 ('-o',)" "" run ent.tom -- echo -o
try "run: -- first, then the file" 0 "1 ('-o',)" "" run -- ent.tom echo -o
try "run: no entry named, no inputs: main with its defaults" 0 "[x] 3" "" run ent.tom
try "run: no input for an input with no default" 1 "" "error[E352]: the entry point takes 2 input(s), got 0 (an input can be left out only if it has a default, as in def main(n: int = 10))" run ent.tom num
try "run: more inputs than the entry takes" 1 "" "error[E352]: the entry point takes 0 input(s), got 1" run hi.tom main extra
try "run: an option-like word after the entry is an input, the program refuses it" 1 "" "error[E352]: the entry point takes 0 input(s), got 1" run hi.tom main --bogus
try "run: -o after the entry is an input too" 1 "" "error[E352]: the entry point takes 0 input(s), got 1" run hi.tom main -o
