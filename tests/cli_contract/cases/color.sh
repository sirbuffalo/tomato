# tier: full
# Colors and warnings: --color=auto|always|never, TOMATO_COLOR, NO_COLOR, --no-warnings, TOMATO_WARNINGS. Errors and warnings go to standard
# error; the color is off when standard error is not a terminal (here it never is) unless asked for. (links a few programs)
. "$CONTRACT_DIR/lib.sh"

printf '@main\ndef main():\n    print(tets)\n' > typo.tom
printf '@main\ndef main():\n    half(0)\n\ndef half(n: int) -> int:\n    return 10 // n\n' > trace.tom
printf '@main\ndef main():\n    unused = 1\n    print(2)\n' > warn.tom
E=$(printf '\033')
try "no terminal: a compile error is plain" 1 "" @compile_error.txt run typo.tom
try "--color=never: plain" 1 "" @compile_error.txt run --color=never typo.tom
try "--color=always paints a compile error: label, location, gutter, caret" 1 "" @color_compile_error.txt run --color=always typo.tom
try "--color always (two words) is the same" 1 "" @color_compile_error.txt run --color always typo.tom
try "--color=always works for compile, build and test too: compile" 1 "" @color_compile_error.txt compile --color=always typo.tom
try "--color=always before the command word's other options: build" 1 "" @color_compile_error.txt build typo.tom --color=always -o x
try "--color=auto with no terminal is plain" 1 "" @compile_error.txt run --color=auto typo.tom
( export TOMATO_COLOR=always; try "TOMATO_COLOR=always is the same as the flag" 1 "" @color_compile_error.txt run typo.tom )
( export TOMATO_COLOR=always; try "the flag wins over TOMATO_COLOR" 1 "" @compile_error.txt run --color=never typo.tom )
( export NO_COLOR=1; try "NO_COLOR keeps it off" 1 "" @compile_error.txt run typo.tom )
try "a runtime error and its trace, painted (the trace dim)" 1 "" @color_trace.txt run --color=always trace.tom
try "a runtime error and its trace, plain" 1 "" @trace.txt run trace.tom
try "a warning, then the program" 0 "2" @warning.txt run warn.tom
try "--color=always paints a warning yellow" 0 "2" @color_warning.txt run --color=always warn.tom
try "--no-warnings hides it" 0 "2" "" run --no-warnings warn.tom
try "--no-warnings may stand anywhere before the entry" 0 "2" "" run warn.tom --no-warnings
( export TOMATO_WARNINGS=off; try "TOMATO_WARNINGS=off hides it" 0 "2" "" run warn.tom )
try "compile does not show the warning in the IR, nor anywhere else it prints" 0 "~define i32 @main" "" compile warn.tom --no-warnings
"$TOMATO" compile warn.tom 2> /dev/null > ir.ll
check "compile: no warning comment lines in the IR" "0" "$(grep -c '^;! ' ir.ll)"
try "build shows the warning too" 0 "wrote w" @warning.txt build warn.tom -o w
try "test: --no-warnings is accepted, the file passes" 0 "~tomato test: 1 files, 1 passed" "" test --no-warnings warn.tom
try "explain and version take --color too" 0 "error[E01]: ZeroDivisionError: division by zero" "" explain E01 --color=always
