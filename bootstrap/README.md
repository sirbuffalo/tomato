# Bootstrap

`tomatoc.ll` is the LLVM IR of the Tomato compiler written in Tomato (`selfhost/`), as written by the compiler itself
(stage 2, see `tests/test_stage2.py`). It lets a machine with only clang build the compiler without Python:

    clang -O1 -Wno-override-module -o tomatoc bootstrap/tomatoc.ll tomato/runtime/tomato_rt.c -lm

`./install-native.sh` does that and installs the `tomato` command. After you change anything in `selfhost/` or the
runtime, refresh the file with `bootstrap/refresh.sh`; a test fails while the file is out of date.
