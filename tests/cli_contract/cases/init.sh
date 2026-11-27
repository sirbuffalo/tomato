# tier: any
# `tomato init [NAME] [--seed]`: the files it writes (the golden files hold their text), what it prints, when it refuses, and that it writes nothing then.
. "$CONTRACT_DIR/lib.sh"

# a project in a folder with a plain name
within "$W/app" try "init: the message names the four files and the next commands" 0 "created tomato.toml, src/main.tom, tests/example.tom and .gitignore
next: tomato run, tomato build, tomato test" "" init
files="$(files_in "$W/app")"
check "init: exactly these files, nothing else" ".gitignore
src
src/main.tom
tests
tests/example.tom
tomato.toml" "$files"
# the golden files: tomato.toml says `tomato = "@MINV@"`: the major and minor of the command (the whole version for a pre-release)
for f in tomato.toml src/main.tom tests/example.tom .gitignore; do
  g="$(printf '%s' "$f" | tr / _)"
  norm < "$W/app/$f" > "$W/got.txt"
  if [ -n "${CONTRACT_UPDATE:-}" ]; then cp "$W/got.txt" "$golden/init_$g"; fi
  if cmp -s "$W/got.txt" "$golden/init_$g"; then ok "init: $f is the golden text"; else bad "init: $f is the golden text" "$(diff -u "$golden/init_$g" "$W/got.txt" | sed '1,2d' | head -20)"; fi
done
check "init: the manifest's tomato key is this command's MAJOR.MINOR" "tomato = \"$minv\"" "$(grep '^tomato' "$W/app/tomato.toml")"
check "init: the project is named after its folder" 'name = "app"' "$(grep '^name' "$W/app/tomato.toml")"
within "$W/app" try "init again: it will not overwrite, and names every file in the way" 1 "" "error: tomato init will not overwrite: tomato.toml, src/main.tom, tests/example.tom, .gitignore (nothing was written; move them away, or use another folder); an existing .gitignore needs the line builds/ added by hand" init
check "init again: the files are as they were" "$files" "$(files_in "$W/app")"

# NAME
within "$W/named" try "init NAME" 0 "~created tomato.toml" "" init demo
check "init NAME: the name in the manifest" 'name = "demo"' "$(grep '^name' "$W/named/tomato.toml")"
within "$W/quoted" try "init NAME with a quote" 0 "~created tomato.toml" "" init 'a"b'
check "init: a quote is escaped in the manifest" 'name = "a\"b"' "$(grep '^name' "$W/quoted/tomato.toml")"
# (a backslash in a name is not tested: the shell's echo changes it, see TODO.md)
within "$W/slash" try "init NAME with a slash" 0 "~created" "" init a/b
within "$W/two" try "init with two names" 1 "" "error: tomato init takes one NAME, not 'a' and 'b'" init a b
check "init with two names writes nothing" "" "$(files_in "$W/two")"
within "$W/opt" try "init with an unknown option" 1 "" "error: unknown option '--frob' for 'tomato init' (usage: tomato init [NAME] [--seed])" init --frob
check "init with an unknown option writes nothing" "" "$(files_in "$W/opt")"
within "$W/dash" try "init -x is an unknown option, not a name" 1 "" "error: unknown option '-x' for 'tomato init' (usage: tomato init [NAME] [--seed])" init -x
within "$W/tab" try "init NAME must be plain printable text" 1 "" "error: the name must be plain printable text" init "$(printf 'a\tb')"
within "$W/slashname" try "init / is no name" 1 "" "error: give the project a name: tomato init NAME" init /

# nothing is overwritten: each file alone is enough to refuse, and the others are not written
for f in tomato.toml src/main.tom tests/example.tom .gitignore; do
  d="$W/exists_$(printf '%s' "$f" | tr / _)"; mkdir -p "$d/$(dirname "$f")"; printf 'mine\n' > "$d/$f"
  hint=""; [ "$f" != .gitignore ] || hint="; an existing .gitignore needs the line builds/ added by hand"
  within "$d" try "init refuses when $f exists" 1 "" "error: tomato init will not overwrite: $f (nothing was written; move them away, or use another folder)$hint" init
  check "init: $f is untouched" "mine" "$(cat "$d/$f")"
  check "init: nothing else was written beside $f" "$(printf '%s\n' "$f" | sed 's|/.*||')" "$(cd "$d" && ls -A | tr '\n' ' ' | sed 's/ *$//')"
done
mkdir -p "$W/linked"; ln -s nowhere "$W/linked/tomato.toml"
within "$W/linked" try "init refuses a dangling symlink where a file would go" 1 "" "error: tomato init will not overwrite: tomato.toml (nothing was written; move them away, or use another folder)" init
mkdir -p "$W/srcfile"; printf 'x' > "$W/srcfile/src"
within "$W/srcfile" try "init refuses when src is a file" 1 "" "error: src exists and is not a folder (nothing was written)" init
check "init: nothing was written when src is a file" "src" "$(files_in "$W/srcfile")"
mkdir -p "$W/testsfile"; printf 'x' > "$W/testsfile/tests"
within "$W/testsfile" try "init refuses when tests is a file" 1 "" "error: tests exists and is not a folder (nothing was written)" init
mkdir -p "$W/partial/src" "$W/partial/tests"
within "$W/partial" try "init uses the src and tests folders that are already there" 0 "~created tomato.toml" "" init

# a seed
within "$W/lib" try "init --seed OWNER/NAME: the files and the next step" 0 "created tomato.toml, src/lib_name.tom, tests/example.tom and .gitignore
next: edit tomato.toml (the owner, description and license), then tomato seed check" "" init --seed acme.example/lib-name
check "init --seed: exactly these files" ".gitignore
src
src/lib_name.tom
tests
tests/example.tom
tomato.toml" "$(files_in "$W/lib")"
for f in tomato.toml src/lib_name.tom tests/example.tom .gitignore; do
  g="seed_$(printf '%s' "$f" | tr / _)"
  norm < "$W/lib/$f" | sed 's/lib_name/@STEM@/g; s|lib-name|@NAME@|g' > "$W/got.txt"
  if [ -n "${CONTRACT_UPDATE:-}" ]; then cp "$W/got.txt" "$golden/init_$(printf '%s' "$g" | sed 's/lib_name/stem/')"; fi
  gold="$golden/init_$(printf '%s' "$g" | sed 's/lib_name/stem/')"
  if cmp -s "$W/got.txt" "$gold"; then ok "init --seed: $f is the golden text"; else bad "init --seed: $f is the golden text" "$(diff -u "$gold" "$W/got.txt" | sed '1,2d' | head -20)"; fi
done
within "$W/Some Folder" try "init --seed with no name takes the folder's name, lowercased, under a placeholder owner" 0 "~created tomato.toml, src/some_folder.tom," "" init --seed
check "init --seed: the placeholder name" 'name = "yourdomain.example/some-folder"' "$(grep '^name' "$W/Some Folder/tomato.toml")"
within "$W/seedflag" try "init --seed works with the flag first or last" 0 "~created" "" init --seed other.example/x
within "$W/seedflag2" try "init NAME --seed" 0 "~created tomato.toml, src/y.tom," "" init other.example/y --seed
bad_seed() { within "$W/badseed_$1" try "init --seed $2 is not a seed name" 1 "" "error: '$2' is not a seed name: write tomato init --seed owner/name (an owner is lowercase letters, digits, dots and hyphens, a name starts with a letter)" init --seed "$2"; check "init --seed $2 writes nothing" "" "$(files_in "$W/badseed_$1")"; }
bad_seed 1 acme
bad_seed 2 Acme/x
bad_seed 3 acme/X
bad_seed 4 acme/1x
bad_seed 5 /x
bad_seed 6 acme.example/
within "$W/seedexists" try "init --seed refuses to overwrite too" 0 "~created" "" init --seed a.example/b
within "$W/seedexists" try "init --seed again" 1 "" "error: tomato init will not overwrite: tomato.toml, src/b.tom, tests/example.tom, .gitignore (nothing was written; move them away, or use another folder); an existing .gitignore needs the line builds/ added by hand" init --seed a.example/b
# the folder where init is run is not a project yet: a project's folder is found upward, so init inside a project's subfolder makes a second one
within "$W/app/sub" try "init inside a project's subfolder makes a project there" 0 "~created" "" init
