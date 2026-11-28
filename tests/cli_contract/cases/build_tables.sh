# tier: full
# The [build] and [build.ENTRY] tables of tomato.toml (docs/manifest.md, D92c): the mode and the output they give, and that the flags win.
# What this pins is what the command does today (the TODO item "Confirm how tomato run, test and build use the build tables" may refine it).
# The mode of a program shows in its errors: debug prints "error: ValueError: boom (raised on line N)", release "error[E11]: ValueError: boom (line N)".
. "$CONTRACT_DIR/lib.sh"

mkdir -p p/sub; cd p || exit 1
printf '@test.fails\ndef fails():\n    assert 1 == 2\n' > sub/tests_fail.tom
printf '@main\ndef main():\n    print(1)\n\n@crash\ndef crash():\n    raise ValueError("boom")\n\n@other\ndef other():\n    raise ValueError("boom")\n' > sub/prog.tom
printf '@main\ndef main():\n    assert 1 == 2\n' > sub/mainfails.tom
head="[project]
name = \"demo\"
version = \"0.3.0\"
tomato = \"$minv\"
"
tmode_of() { r="$("$@" 2>&1)"; case "$r" in *"raised on line"*) echo debug ;; *"assertion failed"*) echo release ;; *) echo "other: $r" ;; esac; }
mode_of() { r="$("$@" 2>&1)"; case "$r" in *"raised on line"*|*"  at "*) echo debug ;; *"error[E"[0-9]*"]: "*" (line "[0-9]*")"*) echo release ;; *) echo "other: $r" ;; esac; }
printf '%s' "$head" > tomato.toml
check "no [build]: debug" "debug" "$(mode_of "$TOMATO" run sub/prog.tom crash)"
printf '%s[build]\nmode = "release"\n' "$head" > tomato.toml
check "[build] mode release applies to run" "release" "$(mode_of "$TOMATO" run sub/prog.tom crash)"
check "--mode debug wins over the file" "debug" "$(mode_of "$TOMATO" run --mode debug sub/prog.tom crash)"
printf '%s[build]\nmode = "debug"\n' "$head" > tomato.toml
check "--mode release wins over a debug file" "release" "$(mode_of "$TOMATO" run --mode release sub/prog.tom crash)"
printf '%s[build]\nmode = "release"\n\n[build.crash]\nmode = "debug"\n' "$head" > tomato.toml
check "[build.ENTRY] overrides [build] for run of that entry, not for the others" "debug release" "$(mode_of "$TOMATO" run sub/prog.tom crash) $(mode_of "$TOMATO" run sub/prog.tom other)"
"$TOMATO" build sub/prog.tom -o all > /dev/null 2>&1
check "build with no --entry holds every entry in the mode of [build] ([build.ENTRY] does not apply)" "release release" "$(mode_of ./all crash) $(mode_of ./all other)"
"$TOMATO" build sub/prog.tom --entry crash -o one > /dev/null 2>&1
check "build --entry: [build.ENTRY] of that entry" "debug" "$(mode_of ./one)"
# tomato test: a file with @test functions is built for the entry test, so [build.test] applies; a file with @main is built for main
printf '%s[build]\nmode = "debug"\n\n[build.test]\nmode = "release"\n' "$head" > tomato.toml
check "test: a file with @test functions uses [build.test]" "release" "$(tmode_of "$TOMATO" test -v sub/tests_fail.tom)"
check "test: a file with @main only does not (its entry is main)" "debug" "$(mode_of "$TOMATO" test sub/mainfails.tom)"
check "test --mode release wins" "release" "$(mode_of "$TOMATO" test --mode release sub/mainfails.tom)"
# output: relative to the folder of the manifest, made when missing; -o wins; run ignores it; build with the file but no -o uses it
printf '%s[build]\noutput = "out/app"\n' "$head" > tomato.toml
try "build: [build] output is the program's place, relative to the manifest's folder (the folder is made)" 0 "wrote out/app" "" build sub/prog.tom
[ -x out/app ] && ok "build: the program is at out/app" || bad "build: the program is at out/app"
rm -rf out
cd sub && try "build from a subfolder: the same place, the manifest's folder" 0 "wrote $W/p/out/app" "" build prog.tom; cd ..
rm -rf out
try "build -o wins over output, and leaves the output folder alone" 0 "wrote other_app" "" build sub/prog.tom -o other_app
[ ! -e out ] && ok "build -o: the output folder was not made" || bad "build -o: the output folder was not made"
try "run ignores output" 0 "1" "" run sub/prog.tom
# a seed's [build] is read and ignored; `tomato config` says so
printf '[seed]\nname = "acme.example/demo"\nversion = "1.0.0"\ntomato = "%s"\n[build]\nmode = "release"\noutput = "out/app"\n' "$minv" > tomato.toml
check "[build] of a seed is ignored by run" "debug" "$(mode_of "$TOMATO" run sub/prog.tom crash)"
check "[build] of a seed is ignored by build (the default place is builds/NAME)" "wrote builds/prog" "$(cd "$W/p" && "$TOMATO" build sub/prog.tom 2>&1)"
check "config says the [build] of a seed is not read" "build: ignored, the [build] of a seed is not read" "$("$TOMATO" config sub/prog.tom | tail -n 1)"
printf '%s[build]\nmode = "fast"\n' "$head" > tomato.toml
try "a bad [build] mode is an error with an id, naming the file" 1 "" "error[E565]: $W/p/tomato.toml:6: build.mode must be \"debug\" or \"release\", not \"fast\"" run sub/prog.tom
printf '%s[build]\ntarget = "x"\n' "$head" > tomato.toml
try "[build] target is reserved" 1 "" "~error[E566]: $W/p/tomato.toml:6: build.target is reserved" run sub/prog.tom

# the user's ~/.tomato/config.toml ($TOMATO_HOME/config.toml) may hold [build] mode: the default of every build on the machine, under the
# project's [build] and [build.ENTRY] and the flags (D99a); it may hold nothing else of [build]
printf '[build]\nmode = "release"\n' > "$TOMATO_HOME/config.toml"
printf '%s' "$head" > tomato.toml
check "user [build] mode applies when the project says nothing" "release" "$(mode_of "$TOMATO" run sub/prog.tom crash)"
check "user [build] mode applies with no project at all" "release" "$(rm tomato.toml; mode_of "$TOMATO" run sub/prog.tom crash)"
printf '%s[build]\nmode = "debug"\n' "$head" > tomato.toml
check "the project's [build] wins over the user's" "debug" "$(mode_of "$TOMATO" run sub/prog.tom crash)"
printf '%s[build.crash]\nmode = "debug"\n' "$head" > tomato.toml
check "the project's [build.ENTRY] wins over the user's, other entries keep it" "debug release" "$(mode_of "$TOMATO" run sub/prog.tom crash) $(mode_of "$TOMATO" run sub/prog.tom other)"
printf '%s' "$head" > tomato.toml
printf '[build]\nmode = "debug"\n' > "$TOMATO_HOME/config.toml"
check "--mode release wins over the user's debug" "release" "$(mode_of "$TOMATO" run --mode release sub/prog.tom crash)"
printf '[build]\noutput = "x"\n' > "$TOMATO_HOME/config.toml"
try "the user's file may not set [build] output (it belongs to a project)" 1 "" "~error[E558]: $TOMATO_HOME/config.toml:2: unknown setting build.output (the user file may set only build.mode: output and [build.ENTRY] belong in a project's tomato.toml)" run sub/prog.tom
printf '[build]\nmode = "fast"\n' > "$TOMATO_HOME/config.toml"
try "a bad mode in the user's file is E565" 1 "" "~error[E565]: $TOMATO_HOME/config.toml:2: build.mode must be \"debug\" or \"release\", not \"fast\"" run sub/prog.tom
rm -f "$TOMATO_HOME/config.toml"

# a mistake in the user's file is reported even when --mode or the project's [build] decides the mode (not only when nothing overrides it)
printf '[build]\nmode = "fast"\n' > "$TOMATO_HOME/config.toml"
try "a bad mode in the user's file is E565 even with --mode" 1 "" "~error[E565]: $TOMATO_HOME/config.toml:2: build.mode must be \"debug\" or \"release\", not \"fast\"" run --mode release sub/prog.tom
printf '%s[build]\nmode = "release"\n' "$head" > tomato.toml
try "a bad mode in the user's file is E565 even when the project's [build] sets one" 1 "" "~error[E565]: $TOMATO_HOME/config.toml:2: build.mode must be \"debug\" or \"release\", not \"fast\"" run sub/prog.tom
rm -f "$TOMATO_HOME/config.toml"
