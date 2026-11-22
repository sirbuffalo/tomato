# Tomato

Tomato is a statically typed, reference-counted language with indentation syntax, compiled through LLVM, designed by Davis McDowell. Its compiler is written in Tomato and compiles itself; there is no other implementation.

- **Status: an implemented subset.** The status table in `docs/specification.md` says what is built and what is not; `tests/known_gaps/` explains how unbuilt rules are tracked. Programs have no top-level code: they start at a function marked `@main`.
- **Version:** in `VERSION` (v0.x).
- **Install on a Mac:** download `tomato-VERSION.pkg` from the Download page (signed and notarized by Apple, see `docs/releasing.md`). It installs prebuilt universal binaries into `/usr/local/lib/tomato` and links `/usr/local/bin/tomato`; `release/pkg.sh` builds it and `release/sign-pkg.sh` signs and notarizes it.
- **Install:** `./install-native.sh` builds the compiler from the checked-in IR with clang alone and installs `tomato` (`run`, `build`, `compile`, `explain`, `repl`, `update`, `version`, `help`).
- **Try it:** the website (https://tomato.davismcd.com) compiles and runs programs in the browser, with no install.
- **Numbers:** `int` has unlimited size (a number beyond 4.6 quintillion is a heap number that its variable, field or container owns, copies on assignment and frees when overwritten or dropped, D05av); fixed-width integers stop on overflow.
- **Errors:** compile errors, warnings, runtime errors (with a call trace) and the repl share one format, described in `docs/errors.md`; on a terminal they are colored (`--color=auto|always|never`, `NO_COLOR`), with the same words as plain text.
- **Update trust:** `tomato update` trusts HTTPS plus the checksum in `site/latest.json`; archives are not signed yet.
- **Test:** `tests/run.sh` (needs only clang; `jsc` on macOS for the WebAssembly checks, `expect` for the repl history check).

## Layout

| Folder | What it holds |
| --- | --- |
| `compiler/src/` | the lexer, parser, error reporting and compiler, written in Tomato |
| `compiler/bootstrap/` | `tomatoc.ll`, the compiler's own IR, so a machine with only clang can build it; `refresh.sh` regenerates it |
| `runtime/` | the C runtime every program links with |
| `std/` | the standard library, written in Tomato |
| `native/` | the `tomato` command and the repl (shell scripts) |
| `site/` | the website for tomato.davismcd.com; `site/wasm/` is the compiler, runtime and IR interpreter that run in the browser |
| `editors/` | the VS Code extension: TextMate grammar, snippets, language configuration |
| `release/` | `build.sh` builds the release archive and `latest.json` that `tomato update` reads |
| `docs/` | the specification, decision log, decision inventory, open questions, placeholders and the error-message guide |
| `examples/` | sample programs |
| `tests/` | `run.sh`; programs, expected outputs, rejected programs (`negative/`, `errors/`), runtime failures (`runtime/`) and `known_gaps/` |
