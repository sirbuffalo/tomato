# tier: any
# The argument rules of run, build, compile and test that are decided before a program is linked: which word is a FILE, an ENTRY, an option
# or an input, what each mistake says, and the exit status (1 for an error with a message, 2 for a usage). Nothing here links a program.
. "$CONTRACT_DIR/lib.sh"

printf '@main\ndef main():\n    print("hi")\n' > hi.tom
printf '@main\ndef main(a: str, b: int = 3):\n    print(a, b)\n\n@greet.loud\ndef loud():\n    print("LOUD")\n' > ent.tom

# --- run: what is a FILE, an ENTRY, an option
try "run: no word and no project" 1 "" "error: there is no tomato.toml in this folder or a parent folder, so there is no project's src/main.tom to run: name a file (tomato run FILE.tom), or start a project here with tomato init" run
try "run: a file that is not there" 1 "" "error: cannot read nosuch.tom" run nosuch.tom
try "run: a path with a slash is a file even without .tom" 1 "" "error: cannot read dir/nosuch" run dir/nosuch
try "run: an unknown option before the file" 1 "" "error: unknown option '--bogus' for 'tomato run' (options go before the entry: the words after it are its inputs, read as they are; after -- no word is an option)" run --bogus hi.tom
try "run: an unknown option between the file and the entry" 1 "" "error: unknown option '--bogus' for 'tomato run' (options go before the entry: the words after it are its inputs, read as they are; after -- no word is an option)" run hi.tom --bogus
try "run: a second file word is refused, naming the first" 1 "" "error: 'other.tom' looks like a file, but the file is already hi.tom: after it comes an entry name such as main (tomato run FILE [ENTRY [INPUTS...]])" run hi.tom other.tom
try "run: a second word with a slash is a file too" 1 "" "error: 'x/y' looks like a file, but the file is already hi.tom: after it comes an entry name such as main (tomato run FILE [ENTRY [INPUTS...]])" run hi.tom x/y
try "run: -o is a usage error (run writes no program)" 2 "" @help.txt run -o out hi.tom
try "run: a bad --mode value" 1 "" "error[E282]: the mode must be debug or release, not 'bogus'" run hi.tom --mode bogus
try "run: an empty --mode is refused, not read as no flag" 1 "" "error[E282]: the mode must be debug or release, not ''" run hi.tom --mode ""
try "run: the mode normal was renamed" 1 "" "error[E281]: the mode 'normal' was renamed to 'release': use --mode release (the old release mode is gone)" run hi.tom --mode normal
try "run: a bad --color value" 1 "" "error: --color takes auto, always or never, not 'bogus'" run --color=bogus hi.tom
try "run: --color with a bad value (two words)" 1 "" "error: --color takes auto, always or never, not 'bogus'" run --color bogus hi.tom
try "run: --color after the file is an option too, before the entry" 1 "" "error: --color takes auto, always or never, not 'bogus'" run hi.tom --color=bogus
try "run: after -- the next word is still the entry" 1 "" "error[E228]: no function is marked @nosuch
  = help: write @nosuch on the line above the function that should start the program" run hi.tom -- nosuch
try "run: no function is marked with the entry named" 1 "" "error[E228]: no function is marked @nosuch
  = help: write @nosuch on the line above the function that should start the program" run hi.tom nosuch
try "run: --entry names the entry as well" 1 "" "error[E228]: no function is marked @nosuch
  = help: write @nosuch on the line above the function that should start the program" run --entry nosuch hi.tom

# --- compile: prints the IR, never links
try "compile: no word and no project" 1 "" "error: there is no tomato.toml in this folder or a parent folder, so there is no project's src/main.tom to compile: name a file (tomato compile FILE.tom), or start a project here with tomato init" compile
try "compile: a word that is not a file" 1 "" "error: 'hi' is not a file: a file ends in .tom or has a / in it (tomato compile [FILE]; with no FILE it is the project's src/main.tom)" compile hi
try "compile: an unknown option" 1 "" "error: unknown option '--bogus' for 'tomato compile' (run 'tomato help')" compile --bogus hi.tom
try "compile: two files are a usage error" 2 "" @help.txt compile hi.tom ent.tom
try "compile: a file that is not there" 1 "" "error: cannot read nosuch.tom" compile nosuch.tom
try "compile: an empty mode" 1 "" "error[E282]: the mode must be debug or release, not ''" compile hi.tom --mode ""
try "compile: a bad mode" 1 "" "error[E282]: the mode must be debug or release, not 'bogus'" compile hi.tom --mode bogus
try "compile: IR on standard output, nothing on standard error" 0 "~define i32 @main" "" compile hi.tom
"$TOMATO" compile hi.tom > ir.ll 2> /dev/null
check "compile: the IR has no comment lines the command adds for itself (warnings, settings)" "0" "$(grep -c -e '^;! ' -e '^;% ' ir.ll)"
"$TOMATO" compile hi.tom --mode release > ir_rel.ll 2> /dev/null
if ! cmp -s ir.ll ir_rel.ll && grep -q tomato_report_uncaught ir_rel.ll; then ok "compile --mode release is another program (release errors print ids)"; else bad "compile --mode release is another program"; fi
try "compile --entry: the entry's name is checked" 1 "" "error[E228]: no function is marked @nosuch
  = help: write @nosuch on the line above the function that should start the program" compile hi.tom --entry nosuch
"$TOMATO" compile ent.tom --entry greet.loud > ir_entry.ll 2> /dev/null && ok "compile --entry takes a dotted entry" || bad "compile --entry takes a dotted entry"
try "compile: a file in a folder with a slash needs no .tom" 1 "" "error: cannot read lib/nosuch" compile lib/nosuch
# the error texts of the compiler: label, id, message, location, source line, caret (the golden file holds the whole text)
printf '@main\ndef main():\n    print(tets)\n' > typo.tom
try "compile error: the whole text on standard error, status 1, nothing on standard output" 1 "" @compile_error.txt compile typo.tom
printf '@main\ndef main():\n    x = "a" + 1\n' > mismatch.tom
try "compile error: a type mismatch" 1 "" "~error[E190]: cannot use '+' with str and int" compile mismatch.tom

# --- build: the same rules, and -o
try "build: no word and no project" 1 "" "error: there is no tomato.toml in this folder or a parent folder, so there is no project's src/main.tom to build: name a file (tomato build FILE.tom), or start a project here with tomato init" build
try "build: a word that is not a file" 1 "" "error: 'hi' is not a file: a file ends in .tom or has a / in it (tomato build [FILE]; with no FILE it is the project's src/main.tom)" build hi
try "build: an unknown option" 1 "" "error: unknown option '--bogus' for 'tomato build' (run 'tomato help')" build --bogus hi.tom
try "build: -o needs a value" 2 "" "error: -o needs a value" build hi.tom -o
try "build: the program would overwrite its own source" 1 "" "error: the program would overwrite its own source hi.tom: name it with -o" build hi.tom -o hi.tom
try "build: an empty mode" 1 "" "error[E282]: the mode must be debug or release, not ''" build hi.tom --mode ""
try "build: a bad mode" 1 "" "error[E282]: the mode must be debug or release, not 'bogus'" build hi.tom --mode bogus
try "build: a file that is not there" 1 "" "error: cannot read nosuch.tom" build nosuch.tom
try "build: a compile error leaves no program" 1 "" @compile_error.txt build typo.tom -o typo_out
[ ! -e typo_out ] && ok "build: no program after a compile error" || bad "build: no program after a compile error"

# --- the manifest is looked up from the folder of the file (and the current folder when there is no file)
mkdir -p proj/src proj/deep/er; printf '[project]\nname = "p"\nversion = "0.1.0"\ntomato = "%s"\n' "$minv" > proj/tomato.toml
within proj try "run: a project with no src/main.tom" 1 "" "error: the project in $W/proj has no src/main.tom (the program of a project is src/main.tom; tomato run FILE.tom runs another file)" run
within proj/deep/er try "build: the same from a subfolder, naming the project's folder" 1 "" "error: the project in $W/proj has no src/main.tom (the program of a project is src/main.tom; tomato build FILE.tom runs another file)" build
within proj try "compile: the same for compile" 1 "" "error: the project in $W/proj has no src/main.tom (the program of a project is src/main.tom; tomato compile FILE.tom runs another file)" compile

# --- test: the words
mkdir -p t/tests; printf '@main\ndef main():\n    pass\n' > t/tests/ok.tom; printf 'def helper():\n    pass\n' > t/tests/_helper.tom
within t try "test: a bare word before any file is an error that says what to write" 1 "" "error: 'ok' is not a file: write tomato test ok.tom (or tests/ok.tom); a word that is not a file is only accepted right after a file, as the entry to run in it (tomato test x.tom ok)" test ok
within t try "test: an unknown option" 1 "" "error: unknown option '--bogus' for 'tomato test' (options go before the files: the words after a file or its entry are not options; run 'tomato help')" test --bogus
within t try "test: --timeout 0" 1 "" "error: --timeout takes a whole number of seconds above 0, not '0'" test --timeout 0 tests/ok.tom
within t try "test: --timeout 00" 1 "" "error: --timeout takes a whole number of seconds above 0, not '00'" test --timeout 00 tests/ok.tom
within t try "test: --timeout abc" 1 "" "error: --timeout takes a whole number of seconds above 0, not 'abc'" test --timeout abc tests/ok.tom
within t try "test: --timeout -1" 1 "" "error: --timeout takes a whole number of seconds above 0, not '-1'" test --timeout -1 tests/ok.tom
within t try "test: a file that is not there" 1 "" "error: cannot read tests/nosuch.tom" test tests/nosuch.tom
mkdir -p t/empty t/helpers; printf 'def h():\n    pass\n' > t/helpers/_only.tom
within t try "test: a folder of helpers only has no test" 1 "" "error: no test file in helpers (each helpers/NAME.tom is one test; a name that starts with _ is a helper module, not a test)" test helpers
within t try "test: an empty folder" 1 "" "error: no test file in empty (each empty/NAME.tom is one test; a name that starts with _ is a helper module, not a test)" test empty
mkdir -p notests
within notests try "test: no tests folder" 1 "" "error: no tests folder here: run tomato test FILE..., or put test files in tests/ (each tests/NAME.tom is one test)" test
mkdir -p notests/tests
within notests try "test: an empty tests folder" 1 "" "error: no test file in tests (each tests/NAME.tom is one test; a name that starts with _ is a helper module, not a test)" test
within t try "test: a filter that no file matches only warns, and passes" 0 "warning: no file name contains 'zzz'
tomato test: 0 files, 0 passed, 0 failed, 0 skipped: ok" "" test --filter zzz
within t try "test: an option after a file is refused, and the message says where it goes" 1 "" "error: '--filter' comes after a file, so it is not an option (options go before the files: tomato test --filter tests/ok.tom); it can only be an input of an entry (tomato test tests/ok.tom ENTRY --filter)" test tests/ok.tom --filter x
within t try "test: -- ends the options, the next word is still the first file" 0 "ok   tests/ok.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "" test -- tests/ok.tom
within t try "test: --color and --no-warnings are options too, before the files" 0 "ok   tests/ok.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "" test --color=never --no-warnings tests/ok.tom
within t try "test: a bad --color value is refused" 1 "" "error: --color takes auto, always or never, not 'bogus'" test --color=bogus tests/ok.tom
