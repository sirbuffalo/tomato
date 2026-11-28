# tier: full
# The environment variables and exit statuses a script can rely on (docs/shell-to-tomato-plan.md, section 6): TOMATO_CACHE_DIR and TOMATO_CACHE,
# TOMATO_COLOR/NO_COLOR/TOMATO_WARNINGS (color.sh has those), and the status of `tomato run` when the program ends by sys.exit(N) or by a signal
# (128 + the signal), and of `tomato test`. (links a few programs)
. "$CONTRACT_DIR/lib.sh"

printf '@main\ndef main():\n    print("hello")\n' > hello.tom
# the compiled runtime is kept in TOMATO_CACHE_DIR; TOMATO_CACHE=off turns the cache off (nothing is written there)
( export TOMATO_CACHE_DIR="$W/cache1"; try "TOMATO_CACHE_DIR: a program runs with its own cache folder" 0 "hello" "" run hello.tom )
if [ -n "$(ls -A "$W/cache1" 2>/dev/null)" ]; then ok "TOMATO_CACHE_DIR: the compiled runtime was stored there"; else bad "TOMATO_CACHE_DIR: the compiled runtime was stored there" "$(files_in "$W")"; fi
( export TOMATO_CACHE_DIR="$W/cache1"; try "a second run with the same cache" 0 "hello" "" run hello.tom )
( export TOMATO_CACHE=off TOMATO_CACHE_DIR="$W/cache2"; try "TOMATO_CACHE=off: the program still runs" 0 "hello" "" run hello.tom )
if [ -z "$(ls -A "$W/cache2" 2>/dev/null)" ]; then ok "TOMATO_CACHE=off: nothing was stored"; else bad "TOMATO_CACHE=off: nothing was stored" "$(files_in "$W/cache2")"; fi
mkdir -p ro; printf 'x' > ro/notafolder
( export TOMATO_CACHE_DIR="$W/ro/notafolder/x"; try "a cache folder that cannot be made: the program still runs (the runtime is built beside it)" 0 "hello" "" run hello.tom )

# the status of `tomato run`: the program's own
printf 'import sys\n\n@main\ndef main():\n    sys.exit(7)\n' > exit7.tom
try "run: sys.exit(7) gives 7" 7 "" "" run exit7.tom
printf 'import os\nimport sys\n\n@main\ndef main():\n    sys.run(["kill", "-TERM", str(os.getpid())])\n' > term.tom
try "run: a program killed by SIGTERM gives 143 (what a shell says about the dead child is not part of the contract)" 143 "" - run term.tom
printf '@main\ndef main():\n    raise ValueError("x")\n' > raises.tom
try "run: an uncaught error gives 1" 1 "" "~error: ValueError: x" run raises.tom
try "run: an error of tomato itself (no such file) gives 1" 1 "" "error: cannot read none.tom" run none.tom
try "run: a usage error gives 2" 2 "" "error: --mode needs a value" run --mode
# a built program has the same statuses
"$TOMATO" build exit7.tom -o exit7_bin > /dev/null 2>&1
"$TOMATO" build term.tom -o term_bin > /dev/null 2>&1
./exit7_bin; check "built program: sys.exit(7) gives 7" 7 "$?"
./term_bin 2>/dev/null; check "built program: killed by SIGTERM gives 143 to its parent shell" 143 "$?"
# tomato test: 1 when any file failed, whatever the reason; how an exit status or a signal is said
mkdir -p tests
printf 'import sys\n\n@main\ndef main():\n    sys.exit(130)\n' > tests/e130.tom
try "test: a file that exits with 130 says it may have been killed by SIGINT" 1 "FAIL tests/e130.tom  (exit status 130 (killed by signal 2, or sys.exit(130)))
tomato test: 1 file, 0 passed, 1 failed, 0 skipped: FAILED" "" test
rm tests/e130.tom
printf 'import os\nimport sys\n\n@main\ndef main():\n    sys.run(["kill", "-TERM", str(os.getpid())])\n' > tests/killed.tom
try "test: a file killed by SIGTERM says so" 1 "~FAIL tests/killed.tom  (exit status 143 (killed by signal 15, or sys.exit(143)))" "" test
rm tests/killed.tom
printf 'from testing import skip\n\n@main\ndef main():\n    skip("later")\n' > tests/skipped.tom
try "test: a skipped file is not a failure: status 0" 0 "skip tests/skipped.tom  (later)
tomato test: 1 file, 0 passed, 0 failed, 1 skipped: ok" "" test
