# tier: full
# `tomato seed install|check|hash` and the local seeds of docs/manifest.md (D95a): what each prints, the lock file, the content hash (it
# changes with the content and not with builds/), and the errors. Nothing is fetched. (the last checks run a program that imports a seed)
. "$CONTRACT_DIR/lib.sh"

mkdir -p app thing/src
printf '[seed]\nname = "acme.example/thing"\nversion = "0.3.0"\ntomato = "%s"\ndescription = "a thing"\nlicense = "MIT"\n' "$minv" > thing/tomato.toml
printf 'export def greet(n: str) -> str:\n    return "hello " + n\n' > thing/src/thing.tom
hashre='^sha256:[0-9a-f]\{64\}$'
h1="$("$TOMATO" seed hash thing 2>&1)"
if printf '%s' "$h1" | grep -q "$hashre"; then ok "seed hash FOLDER: sha256: and 64 hex digits"; else bad "seed hash FOLDER: sha256: and 64 hex digits" "$h1"; fi
check "seed hash: the same folder gives the same hash" "$h1" "$("$TOMATO" seed hash thing)"
check "seed hash: with no FOLDER it is the current folder" "$h1" "$(cd thing && "$TOMATO" seed hash)"
mkdir -p thing/builds; printf 'junk' > thing/builds/x
check "seed hash: builds/ is left out" "$h1" "$("$TOMATO" seed hash thing)"
printf 'export def greet(n: str) -> str:\n    return "bye " + n\n' > thing/src/thing.tom
h2="$("$TOMATO" seed hash thing)"
[ "$h1" != "$h2" ] && ok "seed hash: a change in a file changes the hash" || bad "seed hash: a change in a file changes the hash"
printf 'export def greet(n: str) -> str:\n    return "hello " + n\n' > thing/src/thing.tom
check "seed hash: changed back, the same hash" "$h1" "$("$TOMATO" seed hash thing)"
try "seed hash of a folder that is not there" 1 "" "error[E572]: nosuch is not a folder" seed hash nosuch
try "seed hash of two folders" 2 "" @help.txt seed hash a b
try "seed with no subcommand" 2 "" @help.txt seed
try "seed with an unknown subcommand" 1 "" "error: unknown seed command 'bogus' (run 'tomato help'; the commands here are install, add, remove, update, verify, vendor, check, hash, registry, alias and unalias)" seed bogus
try "seed install with an unknown option" 1 "" "error: unknown option '--bogus' for 'tomato seed install' (run 'tomato help')" seed install --bogus
try "seed install with a word that is no option" 1 "" "error: unknown option 'now' for 'tomato seed install' (run 'tomato help')" seed install --locked now
try "seed check with a word" 2 "" @help.txt seed check now
# the registry commands (D133a): they need no project and no network; with none set up they say how to set one up
try "seed registry with no word" 1 "" "error[E679]: usage: tomato seed registry add NAME URL [--maintainer KEY] | update [NAME] | list" seed registry
try "seed registry list with none set up" 0 "no registry is set up (tomato seed registry add NAME URL [--maintainer KEY])" "" seed registry list
try "seed registry update with none set up" 1 "" "error[E679]: there is no registry set up
  = help: tomato seed registry add NAME URL [--maintainer KEY]" seed registry update
try "seed alias lists none" 0 "no aliases are set (tomato seed alias NAME OWNER/NAME)" "" seed alias
try "seed alias needs a full name" 1 "" "error[E679]: \"json5\" is not a seed name: a seed name is owner/name with exactly one slash (an alias stands for a full owner/name)" seed alias j json5
try "seed unalias of a name that is not an alias" 1 "" "error[E679]: there is no alias \"j\" in $W/.tomato-home/config.toml" seed unalias j
mkdir -p noreg
printf '[project]\nname = "noreg"\nversion = "0.1.0"\ntomato = "%s"\n' "$minv" > noreg/tomato.toml
within noreg try "seed add NAME with no registry set up" 1 "" "error[E571]: there is no registry set up, so a seed cannot be looked up by name
  = help: tomato seed registry add NAME URL [--maintainer KEY] sets one up; or add the seed from where it lives: tomato seed add gh:USER/REPO --rev COMMIT, tomato seed add --git URL --rev COMMIT, or --path DIR" seed add json5
within noreg try "seed add --registry names one that is not set up" 1 "" "error[E679]: --registry nope names the registry \"nope\", but $W/.tomato-home/config.toml has no [registries.nope] (it has: none)
  = help: tomato seed registry add nope URL" seed add acme.example/json5@1.0.0 --registry nope
# no manifest
within app try "seed check: no tomato.toml" 1 "" "error: there is no tomato.toml in this folder or a parent folder" seed check
within app try "seed install: no tomato.toml" 1 "" "error: there is no tomato.toml in this folder or a parent folder" seed install
within app try "seed install --locked: no tomato.toml" 1 "" "error: there is no tomato.toml in this folder or a parent folder" seed install --locked
# check: the seed in this folder
within thing try "seed check: the name and version, the modules, the content hash" 0 "acme.example/thing 0.3.0: ok
modules: thing
$h1" "" seed check
printf 'export def two() -> int:\n    return 2\n' > thing/src/thing_extra.tom
within thing try "seed check: the modules are src/STEM.tom and src/STEM_*.tom" 0 "~modules: thing, thing_extra" "" seed check
rm thing/src/thing_extra.tom
printf '\n[build.mian]\nmode = "debug"\n' >> thing/tomato.toml
within thing try "seed check: a [build.ENTRY] that names no entry is a warning (a typo?), not an error" 0 "~warning: [build.mian] names no entry: no function in src/ or tests/ is marked @mian (or @mian.something), so the table is never used (a typo?)" "" seed check
printf '[seed]\nname = "acme.example/thing"\nversion = "0.3.0"\ntomato = "%s"\ndescription = "a thing"\nlicense = "MIT"\n' "$minv" > thing/tomato.toml
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[seeds]\n"acme.example/thing" = { path = "../thing" }\n' "$minv" > app/tomato.toml
within app try "seed check in a project: it is not a seed" 1 "" "error[E572]: $W/app/tomato.toml: this is not a seed: it has no [seed] table (a [project] is a program that uses seeds)" seed check
# install: lock the path seeds
printf 'from thing import greet\n\n@main\ndef main():\n    print(greet("x"))\n' > app/m.tom
within app try "run before the lock: it says to run tomato seed install" 1 "" "error[E569]: $W/app/tomato.toml: this uses the seed acme.example/thing, but there is no tomato.lock beside it
  = help: run: tomato seed install" run m.tom
within app try "seed install: the seed, its version and hash and where it is from, then the file it wrote" 0 "acme.example/thing 0.3.0  $h1  (path ../thing)
wrote tomato.lock (1 seed)" "" seed install
check "seed install: the lock file" "# tomato.lock: generated by \`tomato seed install\`, do not edit
version = 1

[[seed]]
name = \"acme.example/thing\"
version = \"0.3.0\"
source = \"path\"
path = \"../thing\"
hash = \"$h1\"
modules = [\"thing\"]
seeds = []" "$(cat app/tomato.lock)"
within app try "seed install --locked: checks without writing" 0 "acme.example/thing 0.3.0  $h1  (path ../thing)
tomato.lock is up to date" "" seed install --locked
within app try "run: the program imports the seed" 0 "hello x" "" run m.tom
within app/.. try "run from another folder: the manifest is found from the file" 0 "hello x" "" run app/m.tom
# a path seed that changed after the lock was written: --locked says which seed and why (a build still uses the changed files: a path seed is a working folder)
printf 'export def greet(n: str) -> str:\n    return "bye " + n\n' > thing/src/thing.tom
h2="$("$TOMATO" seed hash thing)"
within app try "seed install --locked: a path seed whose files changed says so, with both hashes" 1 "" "error[E578]: $W/app/tomato.toml: tomato.lock does not match this manifest: the files of the path seed acme.example/thing (../thing) changed since the lock was written (hash $(printf '%s' "$h1" | cut -c1-19)... in tomato.lock, $(printf '%s' "$h2" | cut -c1-19)... now): run \`tomato seed install\` and commit the new lock" seed install --locked
within app try "run: a path seed that changed still builds" 0 "bye x" "" run m.tom
printf 'export def greet(n: str) -> str:\n    return "hello " + n\n' > thing/src/thing.tom
# a `!name(...)` symbol added to a path seed after it was locked is asked about by a build, as `seed install` asks (not linked silently)
printf '!getpid() -> int\n' >> thing/src/thing.tom
within app try "run: a foreign symbol added to a locked path seed is refused until it is accepted" 1 "" "~  = help: tomato.lock does not hold these symbols: run \`tomato seed install\` and answer, or add --yes" run m.tom
within app try "seed install --yes accepts it, and the build runs again" 0 "~wrote tomato.lock (1 seed)" "" seed install --yes
within app try "run: with the symbol in the lock the build goes on" 0 "hello x" "" run m.tom
printf 'export def greet(n: str) -> str:\n    return "hello " + n\n' > thing/src/thing.tom
within app try "seed install --yes: the lock without the symbol again" 0 "~wrote tomato.lock (1 seed)" "" seed install --yes
# a module of the project with the name of a module of a seed is ambiguous (as a seed module with a standard module's name is, E581)
cp thing/src/thing.tom app/thing.tom
within app try "run: a module next to the program with the name of a seed's module is an error naming both" 1 "" "~the module 'thing' is in thing.tom and in the seed acme.example/thing 0.3.0, so the import is ambiguous" run m.tom
rm app/thing.tom
# seed check: the placeholders of `tomato init --seed`, and seed remove with no name
mkdir -p ph; within ph "$TOMATO" init --seed acme.example/ph > /dev/null
within ph try "seed check: the TODO placeholders of init --seed are warnings" 0 "~warning: seed.description is still the placeholder \`tomato init --seed\` wrote: say what the seed is for" "" seed check
within ph try "seed check: and the license one too" 0 "~warning: seed.license is still the placeholder \`tomato init --seed\` wrote: name a license such as MIT" "" seed check
within app try "seed remove with no name is one line, status 2" 2 "" "error: tomato seed remove needs the name of a seed (usage: tomato seed remove NAME)" seed remove
# [seed-store] vendor: a folder of its own below the project's
for v in '.' 'src' '' './tests'; do
  printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[seeds]\n"acme.example/thing" = { path = "../thing" }\n\n[seed-store]\nvendor = "%s"\n' "$minv" "$v" > app/tomato.toml
  within app try "vendor = \"$v\" is refused, naming the line" 1 "" "~error[E604]: $W/app/tomato.toml:10: seed-store.vendor is \"$v\", which cannot be the vendor folder: " seed vendor
done
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[seeds]\n"acme.example/thing" = { path = "../thing" }\n\n[seed-store]\nvendor = "m.tom"\n' "$minv" > app/tomato.toml
within app try "vendor naming a file is refused with a message, not a trace" 1 "" "~error[E604]: $W/app/tomato.toml: the vendor folder $W/app/m.tom is a file, not a folder" seed vendor
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n\n[seeds]\n"acme.example/thing" = { path = "../thing" }\n' "$minv" > app/tomato.toml
# a manifest that lists no seeds
mkdir -p noseeds; printf '[project]\nname = "n"\nversion = "0.1.0"\ntomato = "%s"\n' "$minv" > noseeds/tomato.toml
within noseeds try "seed install with no seeds listed" 0 "the manifest lists no seeds: nothing to lock" "" seed install
[ ! -e noseeds/tomato.lock ] && ok "seed install with no seeds writes no lock" || bad "seed install with no seeds writes no lock"
# the lock must match the manifest
printf '[project]\nname = "app"\nversion = "0.1.0"\ntomato = "%s"\n' "$minv" > app/tomato.toml
within app try "seed install --locked with a lock the manifest no longer needs" '!' "" "~E578" seed install --locked
