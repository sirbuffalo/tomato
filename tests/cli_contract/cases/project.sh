# tier: full
# A project made by `tomato init` and the commands that use its layout (tomato.toml, src/, tests/, builds/): run, build and test with no
# FILE, from the project's folder and from a folder below it; the name of the program; a seed's folder. (links a program per check)
. "$CONTRACT_DIR/lib.sh"

mkdir -p app; cd app || exit 1
"$TOMATO" init demo > /dev/null 2>&1
printf 'export def double(n: int) -> int:\n    return n * 2\n' > src/util.tom
printf 'from util import double\n\n@main\ndef main():\n    print(double(21))\n' > src/main.tom
printf 'from util import double\n\n@main\ndef main():\n    assert double(2) == 4\n' > tests/uses_util.tom
mkdir -p src/deeper
try "run: no word runs src/main.tom of the project (and a module of src/ is imported by name)" 0 "42" "" run
within src/deeper try "run: from a folder below the project, the nearest tomato.toml upward is the project" 0 "42" "" run
try "build: no word builds src/main.tom into builds/NAME, NAME being the project's name" 0 "wrote builds/demo" "" build
check "build: the program is the project's program" "42" "$(./builds/demo)"
within src/deeper try "build: from a folder below the project, the program goes to the project's builds/ (the path is then absolute)" 0 "wrote $W/app/builds/demo" "" build
check "build: builds/ is the project's, not the subfolder's" "demo" "$(ls builds)"
[ ! -e src/deeper/builds ] && ok "build: nothing is written below the project's folder" || bad "build: nothing is written below the project's folder"
try "build FILE.tom, another file of the project: its own name in builds/" 0 "wrote builds/uses_util" "" build tests/uses_util.tom
# tomato test: every tests/*.tom (the init's example, and the one that imports a module of src/), in the project's folder
try "test: no word runs every file of tests/, one line each, then the summary" 0 "ok   tests/example.tom
ok   tests/uses_util.tom
tomato test: 2 files, 2 passed, 0 failed, 0 skipped: ok" "" test
within src try "test: only looks for tests/ in the current folder" 1 "" "error: no tests folder here: run tomato test FILE..., or put test files in tests/ (each tests/NAME.tom is one test)" test
# the name of the program is the manifest's name made into a file name: anything but letters, digits, . _ - becomes -, and a leading . or - gets a p
mkdir -p names; cd names || exit 1
named() { # NAME EXPECTED-FILE
  mkdir -p "$2.d/src"; printf '[project]\nname = "%s"\nversion = "0.1.0"\ntomato = "%s"\n' "$1" "$minv" > "$2.d/tomato.toml"; printf '@main\ndef main():\n    print(1)\n' > "$2.d/src/main.tom"
  within "$2.d" try "build: the project name '$1' is the program builds/$2" 0 "wrote builds/$2" "" build
}
named "my app!" "my-app-"
named ".hid" "p.hid"
named "-dash" "p-dash"
named "a/b" "a-b"
cd ..
# a seed's folder has no program: run and build say so (tomato test works: its example test imports the module)
mkdir -p seeded; cd seeded || exit 1
"$TOMATO" init --seed a.example/thing > /dev/null 2>&1
try "run in a seed's folder: it has no src/main.tom" 1 "" "error: the project in $W/app/seeded has no src/main.tom (the program of a project is src/main.tom; tomato run FILE.tom runs another file)" run
try "test in a seed's folder: the example test imports the module" 0 "ok   tests/example.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "" test
