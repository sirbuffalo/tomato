# Errors the compiler reports

Every problem found before a program runs is reported in one format, whether it comes from `tomato run`, `tomato build`,
`tomato compile`, the repl or the website playground:

```
error: name 'tets' is not defined
 --> prog.tom:6:11
  |
6 |     print(tets)
  |           ^^^^
  = help: did you mean 'test'?
```

- The first line, `error: ...`, says what is wrong in plain words and quotes the offending name or text in single quotes.
- `--> FILE:LINE:COLUMN` says where. Lines and columns count from 1. In the repl the file is `repl` and the line is the line
  you just typed; on the website the file is `program.tom`.
- The next lines show that source line with a row of `^` under the offending text. When the compiler knows only the line, the
  caret covers the statement.
- `= help: ...` lines, when present, say how to fix it. A name that is close to a known one gets `did you mean '...'?`.
- An error with no place in the source (for example, no function marked `@main`) has only the first line and its help.

Only the first problem is reported. The command exits with status 1 and prints the message on standard error.

Messages never mention compiler internals (token names, temporary paths, decision numbers). A limit of the language is
described as what you cannot do and what to do instead ("`map` is not available: Tomato has no function values yet; use a
for loop instead").

## Errors while a program runs

An error that stops a running program prints `error: MESSAGE`, for example `error: division by zero`. An error the program
raises itself and nobody catches prints `error: ClassName: message (raised on line N)`. With `--mode normal` it prints a
short code that `tomato explain CODE FILE` turns back into the message and the source line; with `--mode release` it prints
nothing.

## For compiler authors

- Raise `CompileError(message, line)` (compiler), `ParseError(message, line, col)` or `LexError(message, line, col)`. Put help
  after a newline in the message: `"'x' is defined twice\nrename one of them"`. Quote names with single quotes: the column is
  found from the first quoted name when it is not given.
- `compiler/src/diag.tom` formats the message (`format_error`) and suggests names (`closest`). `compile_module` catches the three
  error classes and raises a `Diagnostic`, whose message is the finished text; the runtime prints a `Diagnostic` as it is.
- `tests/errors/NAME.tom` with the whole expected text in `NAME.out` is checked by `tests/run.sh`.
