# Tomato

Tomato is a language design in progress, directed by Davis McDowell.

The confirmed brief is an easy-to-use, typed, garbage-collected, compiled language with Python-like syntax, with earlier direction placing it somewhere between Python and Go. Those reference languages do not supply unstated rules.

Davis has selected LLVM for compilation and identified web servers, math, and web apps partly written in Tomato and compiled to WebAssembly as intended uses. Detailed target and runtime choices remain open.

Start with the [living specification](docs/specification.md), consult the [decision inventory](docs/decision-inventory.md), and follow the [decision log](docs/decisions.md).

Every accepted language decision is written in Markdown:

- [Living specification](docs/specification.md): all confirmed requirements and accepted rules, with examples and unresolved details.
- [Decision log](docs/decisions.md): acceptance evidence, alternatives, scope, and tradeoffs for every decision.
- [Decision inventory](docs/decision-inventory.md): accepted choices and the remaining coverage map.

The design remains incomplete. `tomato/` holds a prototype parser and interpreter in Python (`bin/tomato run examples/primes.tom`; `bin/tomato run FILE ENTRY INPUTS...` runs another entry point), which implements only decided rules; its placeholders are listed in [PROVISIONAL.md](tomato/PROVISIONAL.md). With llvmlite installed, `bin/tomato run FILE --llvm file.ll` lets `!name(args)` call LLVM functions. `web/` is a local browser playground that runs it through Pyodide (see [web/README.md](web/README.md)). `bin/tomato compile FILE -o OUT.ll` compiles a core subset to LLVM IR, `bin/tomato build FILE -o OUT` links it into a native program with clang, `bin/tomato bundle` writes an executable holding the interpreter, `bin/tomato explain CODE FILE` decodes an error code, and `./install.sh` installs the `tomato` command. The compiler is a prototype in Python; the real one is to be written in Tomato.
