<h1 align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="site/assets/tomato-logo-full-dark.svg"><img src="site/assets/tomato-logo-full.svg" alt="Tomato" height="96"></picture></h1>

Tomato is a statically typed, reference-counted language with indentation syntax, compiled through LLVM, designed by Davis McDowell. Its compiler is written in Tomato and compiles itself; there is no other implementation.

- **Status: an implemented subset.** The status table in `docs/specification.md` says what is built and what is not; `tests/known_gaps/` explains how unbuilt rules are tracked. Programs have no top-level code: they start at a function marked `@main`.
- **Version:** in `VERSION`: MAJOR.MINOR.PATCH from 1.0.0 on (before it 0.1 to 0.51), with pre-releases such as 1.1.0-rc.1; all 1.0.x releases are compatible, a minor release may change behaviour (`docs/releasing.md`, Version numbers).
- **Install on a Mac:** download `tomato-VERSION.pkg` (or the same package in a `tomato-VERSION.dmg` disk image) from the Download page (signed and notarized by Apple, see `docs/releasing.md`). It installs prebuilt universal binaries into `/usr/local/lib/tomato` and links `/usr/local/bin/tomato`; programs are still compiled with `clang`, so a Mac needs the command line tools (`xcode-select --install`). `release/pkg.sh` builds the package and `release/sign-pkg.sh` signs and notarizes it.
- **Install on Linux (x86-64) or from source:** needs `clang` (`apt install clang` or the like; the Linux release tests use clang 21) and `bash`; `tomato update` also needs `curl`, and the `requests` library the system libcurl. Download `tomato-VERSION.tar.gz` from the Download page, or clone the repository, and run `./install-native.sh`: it builds the compiler from the checked-in IR with clang alone into `~/.tomato/native` and links `~/.local/bin/tomato` (put `~/.local/bin` on your `PATH`; `TOMATO_HOME` and `TOMATO_BIN` choose other places). It installs `tomato` (`run`, `build`, `compile`, `explain`, `repl`, `update`, `version`, `help`) and builds the repl's line editor (`tomato-repl-edit`, from `compiler/src/repledit.tom` and the std library `lineedit`; when it cannot be built the install warns and the repl uses plain input).
- **Try it:** the website (https://tomato.davismcd.com) compiles and runs programs in the browser, with no install.
- **Numbers:** `int` has unlimited size (a number beyond 4.6 quintillion is a heap number that its variable, field or container owns, copies on assignment and frees when overwritten or dropped, D05av); fixed-width integers stop on overflow.
- **Errors:** compile errors, warnings, runtime errors (with a call trace) and the repl share one format, described in `docs/errors.md`; on a terminal they are colored (`--color=auto|always|never`, `NO_COLOR`), with the same words as plain text.
- **Update trust:** `tomato update` trusts HTTPS plus the checksum in `site/latest.json`; archives are not signed yet.
- **Test:** `tests/run.sh` (needs only clang. It runs the tests in parallel: `-j N` or `TOMATO_TEST_JOBS=N` sets how many at once, by default the smaller of 8 and a quarter of the cores, and `-j 1` runs them one after another; the output and the result are the same either way. The WebAssembly checks run in `jsc` on macOS or in `node` on Linux, via `native/jsc-on-node.js`, and are skipped when neither exists. `expect` is for the pty checks of the repl's line editor and of `terminal`). CI is GitHub Actions: `.github/workflows/tests.yml` runs it on macOS and `.github/workflows/pages.yml` deploys the website (independently of the tests); `.github/workflows/linux.yml` runs it on Ubuntu (clang, node, `expect`) with LeakSanitizer reporting leaks in the `-fsanitize=address` checks, which macOS cannot do. Run the Linux flavor locally with `ASAN_OPTIONS=detect_leaks=1 ASAN_SYMBOLIZER_PATH=$(command -v llvm-symbolizer) tests/run.sh`.

## Quick start

```
$ cat hello.tom
@main
def main():
    print("hello", 6 * 7)
$ tomato run hello.tom
hello 42
$ tomato build hello.tom -o hello && ./hello     # a native program
hello 42
```

Programs have no top-level code: statements go inside a function, and `@main` marks the one that starts the program. After an install, `~/.tomato/native/examples/` holds the sample programs (`tomato run ~/.tomato/native/examples/compiled.tom main 12`); the guide on the website tours the language.

## Layout

| Folder | What it holds |
| --- | --- |
| `compiler/src/` | the lexer, parser, error reporting and compiler, written in Tomato |
| `compiler/bootstrap/` | `tomatoc.ll`, the compiler's own IR, so a machine with only clang can build it; `refresh.sh` regenerates it |
| `runtime/` | the C runtime every program links with |
| `std/` | the standard library, written in Tomato: `math`, `rational`, `itertools`, `cache` (LRU cache, `memoize`), `time`, `json` (JSON and MessagePack), `toml`, `bitarray`, `requests` (HTTP); the folder `builtin/` holds the names every file can use (`Error`, `RuntimeError` and the other error classes) and `errors.txt` the table of error ids |
| `native/` | the `tomato` command and the repl (shell scripts), and the helpers that run the WebAssembly compiler in `jsc` or `node` |
| `site/` | the website for tomato.davismcd.com; `site/wasm/` is the compiler, runtime and IR interpreter that run in the browser |
| `editors/` | the VS Code extension: TextMate grammar, snippets, language configuration |
| `release/` | `release.sh` makes a whole release (see `docs/releasing.md`); `build.sh` builds the archive and the `latest.json` that `tomato update` reads, `pkg.sh`, `sign-pkg.sh` and `dmg.sh` the macOS installer, `linux-setup.sh` the Linux toolchains |
| `docs/` | the specification, decision log, decision inventory, open questions, placeholders (`provisional.md`) and the error-message guide (`errors.md`), which the website's Reference shows; also the style guide (`style.md`), `performance.md`, `releasing.md`, `next-features.md` (a ranked roadmap) and `handoff.md` |
| `examples/` | sample programs (the website's example menu is generated from them by `site/examples.sh`) |
| `benchmarks/` | the cross-language benchmark suite (see `benchmarks/README.md`) and its results |
| `tools/` | C programs that generate the Unicode case and character-class tables in the runtime |
| `tests/` | `run.sh`; programs, expected outputs, rejected programs (`negative/`, `errors/`), runtime failures (`runtime/`) and `known_gaps/` |
