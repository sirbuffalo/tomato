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
program, then in the project's `src/` (so a test in `tests/` imports the modules of `src/`), then in the seeds, then in `std/`. The
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
- A `main` that takes inputs must give each one a default, so that `tomato run` and `builds/NAME` with no words always work; a missing
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
| `[seeds]` | the seeds every build uses, each `"owner/name" = "1.2.0"` (a minimum version) or, in a project only, `{ path = "../folder" }` or `{ git = "URL", rev = "COMMIT" }` |
| `[test-seeds]` | the same forms, used only by `tomato test` (and the option `--test-seeds`); a seed's own `[test-seeds]` is read only by `tomato test` in that seed, never by its users |
| `[build]`, `[build.ENTRY]` | `mode` (`"debug"` or `"release"`) and `output` (a path); `target` is reserved |
| `[seed-store]` | `vendor = "folder"`: read and checked, not used yet (vendoring is not built) |
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
- **The user's `~/.tomato/config.toml`** may hold `[build] mode = "debug" | "release"`, the default of every build on the machine,
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

There is no registry and no network use yet. What works is **path seeds**:

```
tomato seed install [--locked]   lock every seed of both tables into tomato.lock (--locked: check it, write nothing)
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
  name: `name`, `version` (the seed's own), `source = "path"`, `path` (as written), `hash`, `modules`, `seeds = []`, and `test_only = true`
  only for a seed `[seeds]` does not list (design section 3; it replaced `entries`, D94b). There is no `index` field yet.
- **A build never resolves.** `run`, `build`, `compile` and `test` read the lock and check that each seed the build uses is in it,
  from the same path, and meets the minimum; if not they stop with `run: tomato seed install` (E569). A path seed is a working
  folder, so a build does **not** re-hash it (edit it freely): `tomato seed install --locked` is the check that the lock matches
  the files (E578), for a CI.
- **Where the compiler looks for `import m`:** `m.tom` next to the program (as before; it shadows anything), then `m.tom` in the project's `src/` folder
  (D94b: the `src/` of the folder that holds the nearest `tomato.toml`), then a module of a seed the build uses (the module map, `module TAB file TAB label` lines the compiler gets from the lock), then the standard
  library. A name in both a seed and the standard library is a compile error naming both (E581). Two seeds providing one module
  stop `install` (E577). An error in a seed's code shows `acme.example/thing 0.3.0: src/thing.tom:2:5`, and its warnings are not shown.
- A `git` seed and a plain version (a registry seed) are read and checked but cannot be installed: E570 and E571 say so.

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
| E570 | a `git` seed (not supported yet) |
| E571 | a registry seed (no registry yet) |
| E572 | a seed folder is missing or is not a seed |
| E573 | the seed's name is not the one it was listed under |
| E574 | a seed that uses seeds (not supported yet) |
| E575 | a seed's modules do not fit its name, are missing, or there are none |
| E576 | a symbolic link or other special file in a seed |
| E577 | two seeds provide one module |
| E578 | the lock is damaged, of another version, or `--locked` found it out of date |
| E579 | a seed module has a standard module's name |
| E580 | `tomato seed check`: the owner is not one a registry accepts |
| E581 | (a compile error) a module is in a seed and in the standard library |
| E590 | a table below `[seeds]` or `[test-seeds]` (`[seeds.test]`): use `[test-seeds]` |
| E591 | (a runtime error of a built program) its first word is no entry |
| E592 | (a runtime error) a `File` input cannot be opened |

## Not built yet

The registry, `index`, signatures, `tomato seed add/remove/update/outdated/tree/vendor/verify/registry`, git and the seed store
(`~/.tomato/seeds`), seeds that use seeds, MVS over a graph, `--offline`, the list of the `!name(...)` foreign symbols a seed declares that `tomato seed add` will show and the lock will record (D94b: such declarations are allowed, nothing rejects them), visibility of which seed may import which
(`docs/package-registry-design.md` sections 5 to 8, 12 and 15 stages 3 to 7).
