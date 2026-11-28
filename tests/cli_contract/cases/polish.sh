# tier: full
# The polish of the fourth audit (P1 to P6): seed names and messages, [build.ENTRY] tables that name no entry, a tomato.toml that is not TOML, a
# `tomato test --filter` that keeps nothing, and a build that fails or writes into a folder that is not there. (links a program per check)
. "$CONTRACT_DIR/lib.sh"

mkdir -p thing/src other/src app/src
printf '[seed]\nname = "acme.example/thing"\nversion = "0.3.0"\ntomato = "%s"\ndescription = "a thing"\nlicense = "MIT"\n' "$minv" > thing/tomato.toml
printf 'export def greet(n: str) -> str:\n    return "hello " + n\n' > thing/src/thing.tom
printf '[seed]\nname = "other.example/thing"\nversion = "0.1.0"\ntomato = "%s"\ndescription = "another"\nlicense = "MIT"\n' "$minv" > other/tomato.toml
printf 'export def two() -> int:\n    return 2\n' > other/src/thing.tom
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[seeds]\n"acme.example/thing" = { path = "../thing" }\n' "$minv" > app/tomato.toml
printf '@main\ndef main():\n    print("app")\n' > app/src/main.tom

# P1: the short name `import` uses, and the names there are when it is wrong
within app try "seed install" 0 - "" seed install
within app try "seed remove: a name that is not listed says which seeds are" 1 "" "error[E604]: nosuch is not in [seeds] or [test-seeds] of tomato.toml (the seeds there: acme.example/thing)" seed remove nosuch
within app try "seed remove: the short name of the one seed that has it" 0 "removed acme.example/thing from [seeds] of tomato.toml
wrote tomato.lock (0 seeds)" "" seed remove thing
# P3: messages name the files as the user would, and a word of the command line has no file in front of it
within app try "seed add: a shortcut that is none is an error about the word, not about tomato.toml" 1 "" "~error[E621]: \"gh:\" is not a host shortcut: write gh:USER/REPO" seed add gh:
within app try "seed add --path: says where it wrote, without the long path" 0 "~added acme.example/thing 0.3.0 to [seeds] of tomato.toml" "" seed add --path ../thing
# the `# seeds:` line: the error names the file and the line it is in, and a seed named twice in one line is refused
printf '# seeds: acme.example/thing>=0.4\n@main\ndef main():\n    print("x")\n' > app/src/main.tom
within app try "seeds line: a minimum above the lock is an error at the line" 1 "" "~error[E622]: src/main.tom:1: the \"# seeds:\" line asks for acme.example/thing>=0.4.0, but tomato.lock has acme.example/thing 0.3.0" run
printf '# seeds: acme.example/thing, acme.example/thing\n@main\ndef main():\n    print("x")\n' > app/src/main.tom
within app try "seeds line: the same seed twice in one line is refused" 1 "" "~error[E622]: src/main.tom:1: the \"# seeds:\" line names acme.example/thing twice" run
printf '@main\ndef main():\n    print("app")\n' > app/src/main.tom

# P2: a [build.ENTRY] that names no entry is a warning on build and run, and config lists the entry tables
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[build.mian]\nmode = "release"\n' "$minv" > app/tomato.toml
within app try "run: a [build.ENTRY] that names no entry is a warning" 0 "app" "~warning: [build.mian] names no entry: no function in src/ or tests/ is marked @mian" run
within app try "run --no-warnings: it is not shown" 0 "app" "" run --no-warnings
within app try "config lists [build.ENTRY]" 0 "~build.mian.mode = release  (@W/app/tomato.toml)" "" config
# a dotted table makes its parent ([build.grp] for [build.grp.one]), which holds nothing and is not a typo
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[build.grp.one]\nmode = "debug"\n' "$minv" > app/tomato.toml
printf '@main\ndef main():\n    print("app")\n\n@grp.one\ndef one():\n    print("one")\n' > app/src/main.tom
within app try "run: [build.grp.one] for an entry grp.one is no warning, and its parent table is none either" 0 "one" "" run grp.one
printf '@main\ndef main():\n    print("app")\n' > app/src/main.tom
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n' "$minv" > app/tomato.toml

# P4: a --filter that keeps no file fails (a typo in CI must not pass), and the count says "1 file"
mkdir -p app/tests
printf 'from testing import assert_equal\n\n@test\ndef ok():\n    assert_equal(1, 1)\n' > app/tests/a_ok.tom
within app try "test --filter: nothing matches is an error" 1 "" "error: no test file name contains 'zzz'" test --filter zzz
within app try "test --filter: a match runs, and one file is '1 file'" 0 "ok   tests/a_ok.tom  (1 passed)
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test --filter a_ok

# P5: a tomato.toml that is not TOML shows the line and the caret, once (not once per test file)
printf 'from testing import assert_equal\n\n@test\ndef ok():\n    assert_equal(1, 1)\n' > app/tests/b_ok.tom
cp app/tomato.toml app/tomato.toml.good
printf '[project\nname = 1\n' > app/tomato.toml
within app try "test: a manifest that is not TOML is one error with the line and a caret" 1 "" "error[E540]: the configuration file $W/app/tomato.toml is not valid TOML: Expected ']' to close the table header
 --> $W/app/tomato.toml:1:9
  |
1 | [project
  |         ^" test
cp app/tomato.toml.good app/tomato.toml

# P6: a folder that is not there is said before anything is compiled, and a build that fails removes the old program of its name
within app try "build -o into a folder that does not exist" 1 "" "error: cannot write nodir/a: the folder nodir does not exist (make it, or name another file with -o)" build -o nodir/a
within app try "build: writes builds/NAME" 0 "wrote builds/app" "" build
[ -x app/builds/app ] && ok "build: the program is there" || bad "build: the program is there"
printf '@main\ndef main():\n    print(\n' > app/src/main.tom
within app try "build that fails: the old program is removed, and it says so" 1 "" "~note: removed the old builds/app, so a failed build leaves no program that runs the old code" build
[ ! -e app/builds/app ] && ok "build that fails: builds/app is gone" || bad "build that fails: builds/app is gone"
printf '@main\ndef main():\n    print("again")\n' > app/src/main.tom
within app try "build -o OUT, then a failure: OUT is removed too" 0 "wrote out2" "" build -o out2
printf '@main\ndef main():\n    print(\n' > app/src/main.tom
within app try "failing build -o: the old OUT is removed" 1 "" "~note: removed the old out2, so a failed build leaves no program that runs the old code" build -o out2
[ ! -e app/out2 ] && ok "failing build -o: out2 is gone" || bad "failing build -o: out2 is gone"
printf '#!/bin/sh\necho mine\n' > app/keep.sh; chmod +x app/keep.sh
within app try "failing build -o over a script: it is left alone" 1 "" "-" build -o keep.sh
[ -f app/keep.sh ] && ok "failing build -o over a script: the script is still there" || bad "failing build -o over a script: the script is still there"
