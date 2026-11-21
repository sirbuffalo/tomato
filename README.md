# Tomato

Tomato is a statically typed, reference-counted language with indentation syntax, compiled through LLVM, designed by Davis McDowell. Its compiler is written in Tomato and compiles itself. There is no other implementation: an earlier Python prototype was retired and lives only in git history.

- **Version:** in `VERSION` (v0.x).
- **Install:** `./install-native.sh` builds the compiler from the checked-in IR with clang alone and installs `tomato` (`run`, `build`, `compile`, `repl`, `update`, `version`, `help`).
- **Test:** `tests/run.sh` (needs only clang).

## Layout

| Folder | What it holds |
| --- | --- |
| `compiler/src/` | the lexer, parser and compiler, written in Tomato |
| `compiler/bootstrap/` | `tomatoc.ll`, the compiler's own IR, so a machine with only clang can build it; `refresh.sh` regenerates it |
| `runtime/` | the C runtime every program links with |
| `std/` | the standard library, written in Tomato |
| `native/` | the `tomato` command and the repl (shell scripts) |
| `site/` | the website for tomato.davismcd.com; `site/wasm/` is the compiler, runtime and IR interpreter that run in the browser |
| `editors/` | the VS Code extension: TextMate grammar, snippets, language configuration |
| `release/` | `build.sh` builds the release archive and `latest.json` that `tomato update` reads |
| `docs/` | the specification, decision log, decision inventory, open questions and placeholders |
| `examples/` | sample programs |
| `tests/` | `run.sh`, the example list and expected outputs |
