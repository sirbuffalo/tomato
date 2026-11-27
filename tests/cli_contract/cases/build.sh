# tier: full
# `tomato build`: what it prints and writes, -o and the default place, the built program's own command line (no word runs main, an entry name
# runs that entry, a first word that is no entry is E591, the inputs are raw), --entry, --mode, --llvm. (links a program per check)
. "$CONTRACT_DIR/lib.sh"

cat > prog.tom <<'EOT'
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

@test
def a_test():
    assert 1 + 1 == 2
EOT
try "build FILE -o OUT: says what it wrote, nothing on standard error" 0 "wrote out1" "" build prog.tom -o out1
[ -x out1 ] && ok "build: the program is an executable file" || bad "build: the program is an executable file"
# the built program: [ENTRY [INPUTS...]], the same rules as tomato run
runp() { "$@" > "$W/o" 2> "$W/e" < /dev/null; echo "$? $(cat "$W/o") | $(cat "$W/e")"; }
check "built program: no word runs main with its defaults" "0 [x] 3 | " "$(runp ./out1)"
check "built program: main by name with inputs" "0 [hi] 7 | " "$(runp ./out1 main hi 7)"
check "built program: an entry with raw inputs, options and all" "0 4 ('-o', '--mode', '', 'a b') | " "$(runp ./out1 echo -o --mode '' 'a b')"
check "built program: a dotted marker runs every function under it" "0 LOUD
quiet | " "$(runp ./out1 greet)"
check "built program: a dotted marker by its full name" "0 LOUD | " "$(runp ./out1 greet.loud)"
check "built program: a first word that is no entry is E591 listing the entries (in the order of the file; the tests are not entries)" "1  | error[E591]: this program has no entry 'nosuch' (its entries are: main, echo, greet, greet.loud, greet.quiet); the first word names the entry and its inputs follow it, as in: main INPUT..." "$(runp ./out1 nosuch)"
check "built program: an option-like first word is no entry either" "1  | error[E591]: this program has no entry '--help' (its entries are: main, echo, greet, greet.loud, greet.quiet); the first word names the entry and its inputs follow it, as in: main INPUT..." "$(runp ./out1 --help)"
# -o to another folder, and over an existing program
mkdir -p out_dir
try "build: -o into a folder that exists" 0 "wrote out_dir/p2" "" build prog.tom -o out_dir/p2
try "build: -o over an existing program replaces it" 0 "wrote out1" "" build prog.tom -o out1 --mode release
# --entry: a program with that one entry, which takes just its inputs
try "build --entry: one entry" 0 "wrote echo_only" "" build prog.tom --entry echo -o echo_only
check "build --entry: the program takes the inputs of that entry, with no entry word" "0 3 ('a', 'b', 'c') | " "$(runp ./echo_only a b c)"
check "build --entry: no input at all is no input" "0 0 () | " "$(runp ./echo_only)"
try "build: --entry a name that is no entry is E228" 1 "" "error[E228]: no function is marked @nosuch
  = help: write @nosuch on the line above the function that should start the program; the entries of this program are: main, echo, greet.loud, greet.quiet, test, greet" build prog.tom --entry nosuch -o x
# the default place: builds/NAME next to the project, in the current folder when there is no project; NAME is the file's name without .tom
try "build FILE with no -o and no project: builds/NAME in the current folder, the folder is made" 0 "wrote builds/prog" "" build prog.tom
[ -x builds/prog ] && ok "build: builds/prog is the program" || bad "build: builds/prog is the program"
mkdir -p sub; cp prog.tom sub/other.tom
try "build sub/other.tom: builds/other in the current folder, not in sub" 0 "wrote builds/other" "" build sub/other.tom
# the mode
printf '@main\ndef main():\n    x = 0\n    print(5 // x)\n' > dz.tom
try "build --mode release: the program prints short error ids" 0 "wrote dz_rel" "" build dz.tom --mode release -o dz_rel
check "build --mode release: its error is the id and the line" "1  | error E01:4" "$(runp ./dz_rel)"
try "build (debug): the program prints the readable error" 0 "wrote dz_dbg" "" build dz.tom -o dz_dbg
check "build: its error is the text and the function" "1  | error[E01]: division by zero
  at main (line 4)" "$(runp ./dz_dbg)"
# --llvm: extra LLVM IR files are linked in (D27b: !name declares a function from them)
printf '!add(a: int, b: int) -> int\n\n@main\ndef main():\n    print(!add(40, 2))\n' > ll.tom
printf 'define i64 @add(i64 %%a, i64 %%b) {\n  %%r = add i64 %%a, %%b\n  ret i64 %%r\n}\n' > add.ll
try "build --llvm FILE.ll links the IR in" 0 "wrote llbin" "" build ll.tom --llvm add.ll -o llbin
check "build --llvm: the program calls the function" "0 42 | " "$(runp ./llbin)"
try "run --llvm FILE.ll links the IR in, for run too" 0 "42" "" run ll.tom --llvm add.ll
