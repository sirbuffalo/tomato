# Bootstrap

`tomatoc.ll` is the LLVM IR of the Tomato compiler written in Tomato (`compiler/src/`), as written by the compiler itself
(stage 2, see `tests/run.sh`). It lets a machine with only clang build the compiler (no other tools):

    clang -O1 -Wno-override-module -o tomatoc compiler/bootstrap/tomatoc.ll runtime/tomato_rt.c -pthread -lm

`./install-native.sh` does that and installs the `tomato` command. After you change anything in `compiler/src/` or the
runtime, refresh the file with `compiler/bootstrap/refresh.sh`; a test fails while the file is out of date.

Native installation and the test suite compile the IR in eight parallel parts with
`build-object.sh`. `split.awk` retains one shared definition of every global and
distributes complete functions; the canonical IR remains unchanged for fixed-point
checks and WebAssembly. The helper requires clang, awk and the platform linker.
