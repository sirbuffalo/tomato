# Tomato

Tomato is a language design in progress, directed by Davis McDowell.

The confirmed brief is an easy-to-use, typed, garbage-collected, compiled language with Python-like syntax, with earlier direction placing it somewhere between Python and Go. Those reference languages do not supply unstated rules.

Davis has selected LLVM for compilation and identified web servers, math, and web apps partly written in Tomato and compiled to WebAssembly as intended uses. Detailed target and runtime choices remain open.

Start with the [living specification](docs/specification.md), consult the [decision inventory](docs/decision-inventory.md), and follow the [decision log](docs/decisions.md).

Every accepted language decision is written in Markdown:

- [Living specification](docs/specification.md): all confirmed requirements and accepted rules, with examples and unresolved details.
- [Decision log](docs/decisions.md): acceptance evidence, alternatives, scope, and tradeoffs for every decision.
- [Decision inventory](docs/decision-inventory.md): accepted choices and the remaining coverage map.

The design remains incomplete. This repository contains design documents, not a compiler.
