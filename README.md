# Tomato

Tomato is a statically typed, reference-counted, Python-like language compiled through LLVM, designed by Davis McDowell. Its compiler is written in Tomato and compiles itself.

- **Versions:** the compiler written in Tomato is v0.x (the `tomato` command); the Python implementation is v-1.x (`tomato-py`). The number is in `VERSION`.
- **Install:** `./install-native.sh` builds the compiler from the checked-in IR with clang alone and installs `tomato` (`run`, `build`, `compile`, `repl`, `update`, `version`). `./install.sh` installs the Python command as `tomato-py` (which also has `bundle`, `explain` and the repl).

## Layout

| Folder | What it holds |
| --- | --- |
| `docs/` | the [specification](docs/specification.md), [decision log](docs/decisions.md), [decision inventory](docs/decision-inventory.md) and [open questions](docs/open-questions.md) |
| `compiler/src/` | the lexer, parser and compiler, written in Tomato |
| `compiler/bootstrap/` | `tomatoc.ll`, the compiler's own IR, so a machine with only clang can build it; `refresh.sh` regenerates it |
| `python/` | the Python implementation: the interpreter, the static check pass, the LLVM compiler, the repl (`python/bin/tomato`); its placeholders are in [PROVISIONAL.md](python/tomato/PROVISIONAL.md) |
| `native/` | the `tomato` command script |
| `server/` | the compile server behind the website's Run and Repl page |
| `site/` | the website for tomato.davismcd.com (`site/build.sh` assembles it) |
| `release/` | `build.sh` builds the release archive and `latest.json` that `tomato update` reads |
| `examples/` | sample programs |
| `tests/` | the test suite: `python3 -m unittest discover -s tests` (needs llvmlite for `!x` tests and clang) |
