# tier: any
# `tomato help`, the usage that wrong arguments print, and an unknown command: the text, the stream it goes to and the exit status.
# (help goes to standard output with status 0; the usage of a command used wrongly goes to standard error with status 2: a script can rely on both.)
. "$CONTRACT_DIR/lib.sh"

try "help prints the commands on standard output, status 0" 0 @help.txt "" help
try "--help is the same" 0 @help.txt "" --help
try "-h is the same" 0 @help.txt "" -h
try "help ignores the words after it" 0 @help.txt "" help frobnicate
try "no word prints the same text on standard error, status 2" 2 "" @help.txt
try "an unknown command is named, with the way to the help, status 2" 2 "" @unknown_command.txt frobnicate
try "a word that looks like an option is an unknown command too" 2 "" "error: unknown command '--frobnicate'
run 'tomato help' for the commands" --frobnicate
# a command used wrongly prints the whole usage on standard error and ends with status 2 (not the 1 of an error with a message)
try "explain with no code" 2 "" @help.txt explain
try "explain with three words" 2 "" @help.txt explain E01 a.tom b.tom
try "config with two files" 2 "" @help.txt config a.tom b.tom
try "run: --mode needs a value" 2 "" @help.txt run --mode
try "run: --entry needs a value" 2 "" @help.txt run --entry
try "run: --llvm needs a value" 2 "" @help.txt run --llvm
try "run: -o is not an option of run" 2 "" @help.txt run -o out hello.tom
try "build: -o needs a value" 2 "" @help.txt build -o
try "build: --entry needs a value" 2 "" @help.txt build --entry
try "build: --mode needs a value" 2 "" @help.txt build --mode
try "compile: two files" 2 "" @help.txt compile a.tom b.tom
try "test: --filter needs a value" 2 "" @help.txt test --filter
try "test: --timeout needs a value" 2 "" @help.txt test --timeout
try "test: --mode needs a value" 2 "" @help.txt test --mode
try "seed with no subcommand" 2 "" @help.txt seed
try "seed install with a word that is no option" 1 "" "error: unknown option 'more' for 'tomato seed install' (run 'tomato help')" seed install --locked more
try "seed check takes no word" 2 "" @help.txt seed check now
try "seed hash takes one folder" 2 "" @help.txt seed hash a b
try "--color needs a value (the option every command takes)" 2 "" @help.txt help --color
# structure: the text names every command and every option the plan lists (so a rewrite cannot drop one unnoticed)
help="$("$TOMATO" help)"
for w in "tomato init" "tomato run" "tomato build" "tomato compile" "tomato test" "tomato explain" "tomato config" "tomato seed install" "tomato seed check" "tomato seed hash" "tomato repl" "tomato update" "tomato version" "--test-seeds" "--llvm" "--entry" "--mode" "--filter" "--timeout" "--color=auto|always|never" "--no-warnings" "TOMATO_COLOR" "NO_COLOR" "TOMATO_WARNINGS" "--minor" "--pre"; do
  case "$help" in *"$w"*) ok "the help names $w" ;; *) bad "the help names $w" ;; esac
done
