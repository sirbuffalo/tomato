# Bootstrap

`tomatoc.ll` is the LLVM IR of the Tomato compiler written in Tomato (`compiler/src/`), as written by the compiler itself
(stage 2, see `tests/run.sh`). It lets a machine with only clang build the compiler (no other tools):

    clang -O1 -Wno-override-module -o tomatoc compiler/bootstrap/tomatoc.ll runtime/tomato_rt.c -pthread -lm

`./install-native.sh` does that and installs the `tomato` command. After you change anything in `compiler/src/` or the
runtime, refresh the file with `compiler/bootstrap/refresh.sh`; a test fails while the file is out of date.

`refresh.sh`, native installation and the test suite compile the IR in eight parallel parts with
`build-object.sh`. `split.awk` retains one shared definition of every global and
distributes complete functions; the canonical IR remains unchanged for fixed-point
checks and WebAssembly. The helper requires clang, awk and the platform linker.

Checked on macOS 27 arm64 (BWK awk 20200816, Apple clang 21 and ld) on 2026-11-25 at load about 9: `build-object.sh` takes the
split path, not the fallback, and takes about 3.9 s against 6.6-7.1 s for one `clang -O1` on the whole IR; the full tier
passed 990 and failed 2: the fixed point holds and the examples and benchmarks pass (hello-world included, as the
first program test), and the two failures, neither from the split build, are `os_files` (assumes a case-sensitive
filesystem) and a wasm `--entry=test` check that sees jsc's stderr `Could not open file` note.
