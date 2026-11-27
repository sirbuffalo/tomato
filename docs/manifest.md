# The manifest: `tomato.toml`

The sheet of what is built (decisions D95a and D94b in `docs/decisions.md`). The design, with the registry that is **not** built, is in
`docs/package-registry-design.md` sections 2 to 6; where the two differ this sheet says what the code does today.

## The layout of a project and a seed (D94b)

```
tomato.toml          the manifest, at the root
src/                 the code: a project's program is src/main.tom; a seed's modules are src/*.tom
tests/               the tests: every .tom file is one test (a program that passes when it runs without raising an error)
builds/              what tomato build writes (never part of a build; in .gitignore; left out of a seed's content hash)
tomato.lock          written by tomato seed install, committed
```

`tomato init` makes it (below). A program imports another module of its project by name: `import util` finds `util.tom` next to the
program, then in the project's `src/` (so a test in `tests/` imports the modules of `src/`), then in the seeds, then in `std/`; what a module shares is marked `export` (`export def parse(...)`). The
program `src/main.tom` cannot itself be imported (`main` is its own name): shared code goes in another file.
(The Tomato repository's own folders are not laid out this way yet.)

### `tomato init [NAME] [--seed]`

Writes, in the current folder: `tomato.toml` (`[project]` with `name` (NAME, else the folder's name), `version = "0.1.0"` and `tomato`
= the major and minor of this compiler, such as `1.0`; a pre-release compiler writes its whole version, `1.1.0-rc.1`, since `1.1` is newer
than it), `src/main.tom` (hello world with `@main`), `tests/example.tom` and `.gitignore` (`builds/`). With `--seed` the manifest is
`[seed]` (NAME is `owner/name`, default `yourdomain.example/FOLDER`, with placeholder description and license), the module is
`src/STEM.tom` (a seed has no `main`; `main.tom` would break the module rule of design section 5) and the test imports it.
It writes nothing and names the files when `tomato.toml`, the program, the example test or `.gitignore` exists.

### `run`, `build` and the built program

```
tomato run                           run src/main.tom of the project (the nearest tomato.toml upward)
tomato run ENTRY [INPUTS...]         an entry of src/main.tom (greet, greet.loud) with its inputs
tomato run FILE [ENTRY [INPUTS...]]  FILE is a word that ends in .tom or has a /; any other word is an ENTRY
tomato build [FILE]                  FILE (default src/main.tom) into builds/NAME, with every entry in the program
tomato build --entry ENTRY [FILE]    a program with only that entry, which takes just its inputs
builds/NAME [ENTRY [INPUTS...]]      the program: no word runs main; an entry name runs that entry with the inputs
```

- NAME is the project's `name` for its `src/main.tom`, else the file's name without `.tom`; `builds/` is in the project's folder (the
  current folder with no project). `[build.ENTRY] output` and `mode` (D92c) and the flags `-o` and `--mode` still apply, the flags winning.
- A `main` that takes inputs should give each one a default (a `float` or `File` input cannot have one), so that `tomato run` and `builds/NAME` with no words always work; a missing
  one stops the program with "the entry point takes N input(s), got 0 (an input can be left out only if it has a default ...)".
- In the built program a first word that is no entry is the error E591, which lists the entries. An entry is every `@` marker and every
  dotted beginning of one (`greet` for `@greet.loud`, which runs all `@greet.*`, as `tomato run FILE greet` does), except the tests; a
  name that would run several functions is an entry only when none of them takes inputs. `sys.argv()` is the program's name and then the inputs.
- **Inputs are raw.** An entry takes its inputs as text with `*args: tuple[str]` (or one by one, each converted to its parameter's type:
  `int`, `float`, `bool`, `str`, the fixed-width integers, and `File`). Everything after the FILE or the ENTRY is input: `tomato` reads no
  flag there. Its options go before the entry (`tomato run --mode release f.tom greet bob`; between FILE and ENTRY also works), and
  `--` ends the options earlier: `tomato run f.tom -- main -o` runs `main` with the input `-o`.
- **`File` inputs.** `def main(data: File)`: the word is the path of a file the runner opens for reading (text) before the entry runs and
  closes when it returns; `-` is standard input. A file that cannot be opened stops the program first, naming the input (E592). A `File`
  input has no default and `File | None` is not an input type, so a `main` with a `File` input needs its word.
- `tomato test` (`docs/testing.md`, D97a) runs every `tests/*.tom`, and `tomato test FILE ENTRY INPUTS...` passes the entry and its inputs on as
  `run` does (a test entry with a `File` input gets its file the same way). It builds each file with the option `--test-seeds`, which `run`,
  `build` and `compile` take too, so `[test-seeds]` is read only there.


`tomato.toml` is one file for a project, a seed and the build settings. The compiler reads it (`compiler/src/manifest.tom`,
on `std/toml`); `tomato` only finds it: the first `tomato.toml` in the program's folder or the nearest parent folder (`tomato
config [FILE]` shows which). A mistake in it stops `tomato run`, `build`, `compile`, `test`, `config` and `seed` with an
error that names the file, so a typo in a table or a key is never silently ignored. The browser takes the text of a
`tomato.toml` through `TomatoWasm.compile(source, entry, extra, config)` (and `--config=FILE` of `native/tomato-jsc.js`) and
checks it the same way; it has no folders, so no seeds.

## The tables

| Table | What it is |
| --- | --- |
| `[project]` | a program that uses seeds: `name`, `version`, `tomato` (all three required) |
| `[seed]` | a package: `name` (`owner/name`), `version`, `tomato` (required), `description`, `license`, `modules` (optional) |
| `[seeds]` | the seeds every build uses, each `"owner/name" = "1.2.0"` (a minimum version) or, in a project only, `{ path = "../folder" }` or `{ git = "URL", rev = "COMMIT" }` (git also takes `tag` or `branch`, which `tomato seed update` follows, and `path`, the folder of the repository that holds the seed) |
| `[test-seeds]` | the same forms, used only by `tomato test` (and the option `--test-seeds`); a seed's own `[test-seeds]` is read only by `tomato test` in that seed, never by its users |
| `[build]`, `[build.ENTRY]` | `mode` (`"debug"` or `"release"`) and `output` (a path); `target` is reserved |
| `[seed-store]` | `vendor = "folder"`: where `tomato seed vendor` copies the locked seeds, and where a build then takes them from (a folder below the project's) |
| `[limits]` | `exp_bits`, `format_digits` (D77g; checked by `compiler/src/config.tom`, also in `~/.tomato/config.toml`) |

A folder has `[project]` **or** `[seed]`, never both (E556). A file with neither (the settings-only file of D77g: `[limits]`,
`[build]`) is allowed and read as a project's; `[seeds]` needs one of the two (E567). Any other table or key outside a table is
E555; any other key inside one is E558. `~/.tomato/config.toml` is **not** checked for other tables (its tables are not all
defined yet): only the project's file is strict, except that a `[build]` table in the user's file is checked (see `[build]` below).

```toml
[project]
name = "todo-app"
version = "0.3.0"
tomato = "1.0"                         # the oldest compiler that builds it

[seeds]
"acme.example/json5" = "1.2.0"
"local/thing" = { path = "../thing" }

[test-seeds]                           # only tomato test reads this
"other.example/fixtures" = "1.0.0"

[build]
mode = "release"                       # the default of --mode
output = "bin/todo"                    # the default of -o (tomato build)

[build.test]
mode = "debug"                         # tomato test uses debug
```

### Versions and names

- A version (`version` of a project or a seed, and a minimum in `[seeds]`) is `MAJOR.MINOR.PATCH` with an optional SemVer
  pre-release after a hyphen: `1.2.0`, `1.0.0-rc.1`. No leading zeros, no `+build` part (E560). They are ordered by SemVer
  precedence (`1.0.0-rc.2 < 1.0.0-rc.10 < 1.0.0`); `tests/run.sh` checks the order against `semver_cmp` in `native/tomato`.
- `tomato` is a **minimum**: `MAJOR.MINOR` or `MAJOR.MINOR.PATCH` (`1.0` is `1.0.0`; the old `0.51` is `0.51.0`), with the same
  optional pre-release. If `tomato version` is older, the build stops with E562 and "install a newer release with `tomato
  update`". `1.2.0-rc.1` is older than `1.2`, so a pre-release compiler does not satisfy a release.
- A seed name is `owner/name` with one slash: the owner is lowercase letters, digits, dots and hyphens (a registry takes a
  domain name or `k-` and a key hash, which `tomato seed check` asks for), the name is `[a-z][a-z0-9_-]{0,63}` (E561).

### Which tables a build reads (D94b)

`[seeds]` always. `[test-seeds]` too when the build is for tests: `tomato test` does it, and the option `--test-seeds` does it for `run`,
`build` and `compile` by hand (`tomato run --test-seeds tests/x.tom`). There is no `[seeds.ENTRY]` any more (D92b, replaced): a table
below `[seeds]` or `[test-seeds]` (`[seeds.test]`) is E590, whose message points at `[test-seeds]`. `[build.T]` still applies to the
entry `x` when `T` is `x` or a prefix of it (the longer table wins, setting by setting, and `[build]` is the base); a plain
`run` or `build` is entry `main`.

One seed in both tables of one manifest: the higher minimum wins; a different source (a version in one, a path in another, two
paths) is E564. As for `[seeds]`, a `[seed]` manifest cannot use `git` or `path` forms in `[test-seeds]` (E563).

### `[build]` (D92c)

- `mode` is the default of `--mode`; `output` is the default of `tomato build -o`, a path relative to the manifest's folder
  (its folder is made when missing). A flag on the command line always wins. `run`, `test` and `compile` ignore `output`.
- **How the commands use it (D92c, checked by the suite).** `tomato run`, `tomato build`, `tomato compile` and `tomato test` all read the
  tables for the entry they compile (a plain `run` or `build` is `main`, `build --entry X` is `X`, `tomato test` builds each file with
  `--entry test` or the entry it was given). `mode` is used by all four; `output` only by `build` and only without `-o` (`run`, `test`
  and `compile` ignore it). The order of the settings is the flag (`--mode`, `-o`), then the most specific `[build.ENTRY]` that is the
  entry or a prefix of it, then `[build]`, then the user's `[build] mode` (below), then `debug`. A `tomato build` that holds every
  entry settles its mode and output as for `main`.
- **The user's `~/.tomato/config.toml`** (`$TOMATO_HOME/config.toml` when `TOMATO_HOME` is set) may hold `[build] mode = "debug" | "release"`, the default of every build on the machine,
  under the project's `[build]` and `[build.ENTRY]` and the flags (D99a). It may hold nothing else of `[build]`: `output` and
  `[build.ENTRY]` belong to a project (the path would have no folder to be relative to), and any other key is E558, a bad mode E565.
  It applies with no project and with a seed's folder (a seed's own `[build]` is ignored, not the user's default). `tomato config` shows it.
- `[build]` is read only in a project (and in a settings-only file). The `[build]` of a `[seed]` is checked and **ignored**
  (`tomato config` says so), and the `[build]` of a seed that a project uses is never read at all: a library cannot change how
  the program that uses it is built.
- `target` is reserved: setting it is E566. Other keys are E558; a bad `mode` is E565 (a bad `--mode` is still E281/E282).
- The compiler tells `tomato` the mode it settled on and the output as `;% mode release` and `;% output PATH` comment lines at the
  end of the IR (as warnings are `;!` lines); `tomato compile` removes them.

## Seeds without a registry

There is no registry, and no network use except what `git` does for a **git seed**. What works is **path seeds** and **git seeds** (D101a):

```
tomato seed install [--locked] [--offline] [--yes]   lock every seed of both tables into tomato.lock, fetching a git seed into the store
                                 (--locked: check it, write nothing; --offline: never run git; --yes: accept foreign symbols)
tomato seed add --path DIR       list a local seed in [seeds] of tomato.toml and lock it (--test: in [test-seeds])
tomato seed add --git URL --rev COMMIT   the same for a seed from git (the rev is a full 40-digit commit id)
tomato seed add --git URL --tag TAG | --branch BRANCH   the same, looking the tag or branch up once; its commit is the rev and `update` follows it
tomato seed add --git URL --rev COMMIT --subdir DIR   the seed is the folder DIR of the repository (several seeds in one repository)
tomato seed remove NAME          drop the seed from [seeds] and [test-seeds], lock again
tomato seed update [NAME...] [--dry-run] [--yes]   lock the named seeds (all with no name) again; a git seed that follows a tag or branch moves to its commit now
tomato seed verify               hash every locked seed again (store, vendor folder, path folders) against tomato.lock; exit 1 on a problem
tomato seed vendor               copy the locked seeds into the vendor folder ([seed-store] vendor, default vendor/)
tomato seed check                check the seed of this folder (its manifest, its src/ modules, the owner) and print its hash
tomato seed hash [FOLDER]        print the content hash, sha256:..., of a folder
```

- `tomato seed check` also prints a `warning:` line for each `[build.ENTRY]` table that names no entry: no function in the seed's `src/`
  or `tests/` is marked `@ENTRY` or `@ENTRY.something` (a typo such as `[build.mian]` is a valid table, D92c). It is a warning, not an
  error, and the table is ignored anyway (a seed's `[build]` is never used).
- A seed's folder holds `tomato.toml` with `[seed]` and its modules as `.tom` files directly in `src/`: all of them, or the
  ones listed in `seed.modules`. Each module is `stem.tom` or `stem_*.tom` where the stem is the seed's name with `-` as `_`
  (`acme.example/json5` provides `json5` and `json5_pretty`), and no module has the name of a standard module (E575, E579).
  The key in `[seeds]` (or `[test-seeds]`) must be the seed's own name (E573). A seed that itself lists `[seeds]` cannot be installed yet (E574).
- **The content hash** (design section 6, seed hash v1) is `sha256:` and the sha256 of the lines `sha256-of-file  mode  path`
  (mode `755` when the owner's execute bit is set, else `644`, as git records it; paths sorted bytewise) of every file under the folder except a `.git` folder and a top-level `builds/` folder (D94b); a symbolic link is
  refused (E576). `tests/run.sh` computes the same with `find`, `sort` and `sha256sum`.
- **`tomato.lock`** (next to the manifest, committed) holds `version = 1` and a `[[seed]]` for every seed of both tables, sorted by
  name: `name`, `version` (the seed's own), `source = "path"` with `path` (as written) or `"git"` with `git`, `commit` and, for a seed in a folder of its repository, `path`, `hash`, `modules`, `symbols` (only when the seed declares foreign symbols), `seeds = []`, and `test_only = true`
  only for a seed `[seeds]` does not list (design section 3; it replaced `entries`, D94b). There is no `index` field yet. **The format version** is `version = 1`, and `version = 2` only when an entry has a git `path`
  (what version 1 cannot say; an older Tomato reads 1 only, and stops at a 2 with "not version 1 or 2 ... a newer Tomato wrote it" instead of hashing another tree of the same URL and commit): a lock with no such entry is written as 1, byte for
  byte as before, and a version 1 lock that has a git `path` is a damaged lock (E578). Any other version is E578.
- **A build never resolves.** `run`, `build`, `compile` and `test` read the lock and check that each seed the build uses is in it,
  from the same path, and meets the minimum; if not they stop with `run: tomato seed install` (E569). A path seed is a working
  folder, so a build does **not** re-hash it (edit it freely): `tomato seed install --locked` is the check that the lock matches
  the files (E578), for a CI.
- **Where the compiler looks for `import m`:** `m.tom` next to the program (as before; it shadows anything), then `m.tom` in the project's `src/` folder
  (D94b: the `src/` of the folder that holds the nearest `tomato.toml`), then a module of a seed the build uses (the module map, `module TAB file TAB label` lines the compiler gets from the lock), then the standard
  library. A name in both a seed and the standard library is a compile error naming both (E581). Two seeds providing one module
  stop `install` (E577). An error in a seed's code shows `acme.example/thing 0.3.0: src/thing.tom:2:5`, and its warnings are not shown.
- A plain version (a registry seed) is read and checked but cannot be installed: E571 says so.

### `seed add` and `seed remove` (D101a)

- Only a `[project]` lists seeds this way (E604). `add` reads the seed (a `--path` folder, or the git tree at the rev), takes its name from its
  own `[seed]` table and writes `"owner/name" = { path = "DIR" }` (the path is written relative to the project's folder, or as given when
  it is absolute) or `{ git = "URL", rev = "COMMIT" }` into `[seeds]`, or `[test-seeds]` with `--test`. A seed that is already listed gets
  its value replaced, so `add` with another `--rev` is the update. `remove NAME` drops it from both tables. Both then lock again, as `install` does.
- **The manifest is edited as text** (`compiler/src/manedit.tom`), not written from its values, so every comment, blank line, key order and the
  spacing and end-of-line comment of an existing seed line stay as they are (std/toml's `dumps` would lose them). The new line goes after the last
  entry of the table; a missing table is made where the `# [seeds]` placeholder of `tomato init` is, else before the first table that is
  not `[project]` (`[test-seeds]` after `[seeds]`); a CRLF file stays CRLF. **What is not handled:** a seed written with a dotted key
  (`"a/b".path = ...`) or a value over several lines; `remove` refuses (nothing changes) and `add` finds the result unreadable or different
  from what it meant, puts the file back as it was and prints the line to write by hand (E603). Every edit is read again with the manifest reader and must be
  exactly the intended change; if the lock then fails (an unreadable seed, a clash of modules, a refused symbol) the manifest is put back too.
- `add` and `remove` print one line for the manifest and the lines of `install`. They never fetch for a seed that the lock and the store have.

### Git seeds and the store (D101a)

- `{ git = "URL", rev = "COMMIT" }`: the URL is `https://`, `ssh://`, `file://`, `host:path` or an absolute folder (`ext::`, `-...`, other schemes
  and relative folders are refused, E598); the rev must be a full commit id (a tag moves, so a build never follows one: `git rev-parse TAG^{commit}` is typed once, or `seed add --tag` does it).
- **`tag` and `branch` (D103a).** `{ git = "URL", rev = "COMMIT", tag = "v1.2" }` (or `branch = "main"`, not both) says what `tomato seed update` follows; the `rev` stays the commit that
  is built, so the manifest and a build are as exact as before. `seed add --git URL --tag v1.2` (or `--branch main`) asks git where it is (`refs/tags/v1.2` or `refs/heads/main`, an annotated tag followed to its
  commit), writes that commit as `rev` and keeps the name. A name is plain: no leading hyphen, no space or control character, none of `~ ^ : ? * [ \`, no `..`, `//` or `@{` (E598).
- **`path` (D103a, design sections 3 and 6): a repository that holds several seeds.** `{ git = "URL", rev = "COMMIT", path = "seeds/json5" }` (`seed add --subdir seeds/json5`) makes the folder `seeds/json5` of the commit the seed: only the files below it are
  fetched into the store, it must hold the seed's `tomato.toml` and `src/` as a folder of its own would, and the content hash is that of those files alone (the `path` is not part of it: the same files in another repository have the same hash).
  The rest of the repository is not looked at (a link or a submodule outside the folder does not matter; one inside it is E600). The path is a relative folder of plain parts with `/`: no leading or trailing slash, `.` or `..` part, backslash or `.git` (E598); a folder with no files, or a file, is E600. The lock keeps it as `path` (and is version 2, above).
  Two seeds of one repository are two entries of the manifest with the same `git` and `rev` and different paths; one fetch each.
- **The fetch** (`compiler/src/seedstore.tom`, through `sys.run`, no shell): a **bare clone kept for each repository URL** under `~/.tomato/seeds/git/HASH/`
  (a cache, safe to delete: a second fetch of the same repository adds only the new objects, and a commit the clone already holds is read with no
  network and no repository; a clone that cannot be used is replaced, and when the store is read-only the fetch works in a scratch folder under `~/.tomato/seeds/tmp/`),
  `git fetch --depth 1 URL COMMIT`, the commit checked to be the one asked for, `git ls-tree -r -z` and `git cat-file blob` of each file: **no
  checkout**, so no filter, hook or attribute can change a byte. `GIT_ALLOW_PROTOCOL` is `https:ssh` (plus `file` for a local URL), no prompts,
  no hooks, git's object check on. A symbolic link or submodule, a path with `..`, an absolute path, a `.git` part or a backslash, two names that
  differ only in case, a file over 10 MB, a seed over 64 MB or 5,000 files are refused (E600). A top-level `builds/` is not part of a seed (D94b)
  and is skipped. The scratch folder is removed whatever happens.
- **The store** is `${TOMATO_HOME:-$HOME/.tomato}/seeds/store/ab/ab12...64hex/`, one folder for each content hash (design section 6). A fetched seed is
  hashed (seed hash v1) and put there only when the hash is the one tomato.lock holds; `add` and the first `install` have no hash yet and lock
  what was fetched. A seed the lock knows whose folder is in the store is not fetched again, so `install` works with the repository gone and
  `--offline` is an error only for a seed that is in neither the store nor the vendor folder (E605).
- **The lock** has `source = "git"`, `git` (the URL), `commit`, `hash`, `modules`. **A build re-hashes** a git seed's store folder, and a vendored copy, against the
  lock every time (a path seed is a working folder and is not, D95a choice c): a changed copy is E601; a store folder that has gone says
  `run: tomato seed install` (E569). A build never fetches. `install --locked` also checks that the lock matches the manifest.
- **`seed vendor`** requires a current lock (the check of `install --locked`), copies each seed's files (what the hash covers, modes kept) to
  `VENDOR/owner/name` (written beside it first, then renamed, and hashed again before it replaces the old copy). With `[seed-store] vendor` set a
  build takes **every** seed (path seeds too) from there, re-hashed, so a project builds with no network, no git, no store and no sibling folders; without it
  `vendor` says what to add. `install` uses a vendor copy that matches the lock before it fetches; an edited one is ignored (E601 in a build, `vendor` again to fix).
- The hash of a git seed is the hash of the same files as a path seed (the test compares both with `find`, `sort` and `sha256sum`).

### Foreign symbols (D101a, D94b item 9)

A seed's modules may declare foreign functions, top-level `!name(...) -> T` lines (nothing rejects them). `add` and `install` find them by parsing
every module of the seed (`LlvmDecl` nodes), and when the seed declares a name that the lock's `symbols` for that seed do not hold, they list the
names with the module and line and ask once: `accept these symbols and record them in tomato.lock? [y/N]` (standard input is read, an
empty answer or `n` is no). `--yes` accepts without asking. With no terminal and no `--yes` the command refuses (E602) and changes nothing; so does
`install --locked` (a lock that lacks a declared symbol is out of date). The accepted names are written as `symbols = [...]` (sorted) in the seed's
lock entry; the entry has none when the seed declares none. A version that adds a name asks again; one that only drops names needs no answer. Moving the manifest back to an
older commit records the older list. **A symbol's meaning is not checked**: it links a function of the runtime or of C into the program
(a seed still cannot ship C or run build scripts); the question is the only gate.

### `seed update` (D103a)

`tomato seed update [NAME...] [--dry-run] [--yes]` locks the named seeds again (every seed with no name; a name that is not in the manifest is E604; a registry seed is E571). There is no registry, so nothing is "newest in its line": what moves is a git seed's commit.

- **A git seed with `tag` or `branch`**: git is asked where the tag or branch is now (one `git fetch --depth 1`). If it is the commit of the manifest nothing happens (`tag v1 is still at ...`). If not, the `rev` of its line (in both
  tables when it is in both) is replaced by the new commit with the same text edit as `add` (the comments, the order and the other keys stay), the seed is fetched, hashed and checked like any other, and **the new commit and the new content hash are always written into tomato.lock**.
  The lines say what changed: `name: 1.0.0 -> 1.1.0`, the old and new commit, the old and new hash (shortened), and a `warning:` when the version went down or a `note:` when the new version is not on the compatible line of the old one (a major bump, or a new `0.y`); both are only said, nothing is refused.
- **A version bump asks nothing.** The question about foreign symbols is the one of `add` (D101a): a `!name(...)` the lock does not hold for that seed lists the names with their module and line and asks `[y/N]` (`--yes` accepts; no terminal and no `--yes` is E602 and **nothing is changed in any seed**; an update that only drops names asks nothing).
- **A git seed with no tag or branch** is pinned to its commit: the line says so and how to move it (`tomato seed add --git URL --rev NEWCOMMIT`, or add a `tag` or `branch` to its line). A **path seed** is read again, as `install` does, and the lines say if its version or hash changed.
- **`--dry-run`** does all of it except the writes: tomato.toml and tomato.lock stay exactly as they were (a seed that had to be fetched stays in the store, which is a cache named by hash and not used by any lock that does not name it), the lines show the plan, and a new foreign symbol is reported as "the update would ask you to accept them". `--offline` is an error for a seed that follows a tag or branch (git has to be asked).
- If anything fails (git, a hash, a refused question, two seeds that now provide one module) tomato.toml is put back as it was and tomato.lock is not written, as for `add`.

### `seed verify` (D103a)

`tomato seed verify` hashes every copy of every locked seed again (seed hash v1) and compares it with `hash` in tomato.lock, writing one line for each: `ok`, `CHANGED` (another content hash, a file the lock's `modules` lists that is not there, or a link in the copy),
`MISSING` (the copy is not there) or `skipped`. The copies are the **store folder** of a git seed, the **vendor folder** of every seed when `[seed-store] vendor` is set, and the **folder of a path seed** (a working folder that a build does not check; a lock that went out of date after an edit shows here, and `install` writes it again). A path seed's folder that is gone while a vendor copy serves the build is `skipped`, not a problem.
Any `CHANGED`, `MISSING` or seed from a registry (which this version cannot check) makes the command end with E606 and exit status 1, after all the lines; with none it prints `verified N copies of M locked seeds: all match tomato.lock` and exits 0. It never fetches and never writes. With no lock and no seeds in the manifest there is nothing to verify (exit 0); seeds without a lock is E569.
`--inputs` and the list of revoked keys of design section 12 are not built (there are no signatures yet).

## Errors

All are `ConfigError` (`tomato explain E555`); the message starts with the file's path.

| Id | Meaning |
| --- | --- |
| E539, E540 | the file cannot be read; it is not valid TOML (D77g; also for `tomato.lock`) |
| E541 to E543 | `[limits]` (D77g) |
| E555 | an unknown top-level table or key |
| E556 | `[project]` and `[seed]` in one file |
| E557 | a required setting is missing |
| E558 | an unknown setting in a table |
| E559 | a setting has the wrong type |
| E560 | not a version (`version`, `tomato` or a minimum) |
| E561 | not a seed name |
| E562 | the manifest needs a newer Tomato |
| E563 | a `git` or `path` seed in a seed manifest |
| E564 | one seed with two different sources in two tables |
| E565 | `build.mode` is not `debug` or `release` |
| E566 | `build.target` is reserved |
| E567 | `[seeds]` with neither `[project]` nor `[seed]` |
| E568 | a seed requirement is not a version, `{ path }` or `{ git, rev }` |
| E569 | the lock is missing or does not hold what the run needs: run `tomato seed install` |
| E570 | (retired: git seeds are installed since D101a) |
| E571 | a registry seed (no registry yet) |
| E572 | a seed folder is missing or is not a seed |
| E573 | the seed's name is not the one it was listed under |
| E574 | a seed that uses seeds (not supported yet) |
| E575 | a seed's modules do not fit its name, are missing, or there are none |
| E576 | a symbolic link or other special file in a seed |
| E577 | two seeds provide one module |
| E578 | the lock is damaged, of a version other than 1 or 2, or `--locked` found it out of date (for a path seed whose files changed it names the seed and both hashes) |
| E579 | a seed module has a standard module's name |
| E580 | `tomato seed check`: the owner is not one a registry accepts |
| E581 | (a compile error) a module is in a seed and in the standard library |
| E582 | (a compile error) a file of a seed cannot be read |
| E583 | (a compile error) the same entry marker on two functions (D96a) |
| E584 | (a compile error) an entry that runs several functions has one that takes inputs or is `async` (D96a) |
| E590 | a table below `[seeds]` or `[test-seeds]` (`[seeds.test]`): use `[test-seeds]` |
| E591 | (a runtime error of a built program) its first word is no entry |
| E592 | (a runtime error) a `File` input cannot be opened |
| E593 | (a compile error) a `File` input has a default |
| E594 | (a compile error) `import main`: a module cannot be named `main` |
| E598 | a git URL, rev, tag, branch or path that cannot be used (a scheme, `ext::`, a leading hyphen, a rev that is not a full commit id, a `..` in a path) |
| E599 | `git` failed (or is not installed), or the store folder cannot be made |
| E600 | a git tree that cannot be a seed (a link, a submodule, an unsafe path, a file too large, a module that does not parse) |
| E601 | the content hash of a fetched seed, a stored copy or a vendored copy is not the one in tomato.lock |
| E602 | foreign symbols not accepted (no `--yes`, no terminal, `install --locked`, or the answer was no) |
| E603 | `seed add` or `remove` cannot edit this tomato.toml safely (it was put back as it was) |
| E604 | `seed add` or `remove` used on a file that is not a project, a seed that is not listed, or a vendor folder outside the project |
| E605 | `--offline`: the seed is in neither the store nor the vendor folder (or `update --offline` of a seed that follows a tag or branch) |
| E606 | `tomato seed verify` found a missing copy or one that does not match tomato.lock (D103a) |

## Not built yet

The registry, `index`, signatures, `tomato seed outdated/tree/why/registry`, `seed verify --inputs`, `seed update --accept-owner-change`, seeds that use seeds, MVS over a graph,
the index listing's record of symbols, visibility of which seed may import which
(`docs/package-registry-design.md` sections 5 to 8, 12 and 15 stages 4 to 7).
