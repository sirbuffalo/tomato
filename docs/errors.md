# Errors the compiler reports

Every problem found before a program runs is reported in one format, whether it comes from `tomato run`, `tomato build`,
`tomato compile`, the repl or the website playground:

```
error[E227]: name 'tets' is not defined
 --> prog.tom:6:11
  |
6 |     print(tets)
  |           ^^^^
  = help: did you mean 'test'?
```

- The first line, `error[ID]: ...`, says what is wrong in plain words and quotes the offending name or text in single quotes.
- `--> FILE:LINE:COLUMN` says where. Lines and columns count from 1. In the repl the file is `repl` and the line is the line
  you just typed; on the website the file is `program.tom`.
- The next lines show that source line with a row of `^` under the offending text. When the compiler knows only the line, the
  caret covers the statement.
- `= help: ...` lines, when present, say how to fix it. A name that is close to a known one gets `did you mean '...'?`.
- A bad import is reported at its own line, in the repl and on the website too: a missing name (`E226`) gets a
  `did you mean` and lists what the module exports, and a missing module (`E183`) gets a `did you mean` and lists the standard modules.
- An error with no place in the source (for example, no function marked `@main`) has only the first line and its help.

Only the first error is reported. The command exits with status 1 and prints the message on standard error.

Messages never mention compiler internals (token names, temporary paths, decision numbers). A limit of the language is
described as what you cannot do and what to do instead ("`reduce` is not available" with the help "use a for loop instead").
An argument of the wrong type names the function and the parameter: `argument 1 of 'f' (the parameter
'a') has type str, but int is expected`.

## Warnings

A warning has the same layout with `warning:` in place of `error[ID]:` (a warning has no ID). It is about code that runs but is probably wrong or
useless, and it never stops the program or changes its exit status. All the warnings of a program are shown (in line order)
before it runs. The checks are:

| Kind | When | Example message |
| --- | --- | --- |
| `unused` | a variable is given a value that nothing reads; an imported name is never used | `the variable 'total' is given a value that is never used` |
| `unreachable` | a statement follows a `return`, `raise`, `break` or `continue` (or an `if`/`else` or `try` whose branches all leave) | `this code can never run, because the statement before it always leaves` |
| `unassigned` | a variable is read where some path to it did not give it a value | `'label' might not have a value here, because some paths above do not give it one` |
| `shadow` | a variable has the name of a built-in, or of a function, class or constant of the same file | `the variable 'len' has the same name as a function or class, which it hides here` |
| `loop-change` | a list is changed (`append`, `pop`, `remove` ...) inside a `for` loop that goes through it | `'xs' is changed while the loop goes through it` |

To silence one, write `# allow: KIND` as a comment on the line the warning points at (`total = 0  # allow: unused`). A name
that starts with `_` is meant to be unused, and loop variables, `catch` variables and parameters are never reported as unused.
`tomato run --no-warnings` (or `TOMATO_WARNINGS=off`) hides them all. The repl never shows warnings.

A warning is silent when a case is unclear, and the compiler, the standard library and the examples compile with none.
A lambda's parameters are its own names: `key=b -> -b` does not read a variable `b` of the function around it, so it never gives `unassigned`.

One problem of this family is an error, because the program could not work: a function that gives a value must end every
path with a `return` or `raise` (`the function 'sign' can reach its end without returning a value`). Repeated parameter or
method names, and a comparison of a value that can never be `None` with `None`, are errors too.

## Color

When standard error is a terminal, `tomato` colors what it prints; the words are exactly the same, only ANSI codes are added:

| Part | Style |
| --- | --- |
| `error:` | bold red |
| `warning:` | bold yellow |
| the message after it | bold |
| `-->` and the `|` gutter, `=` | blue |
| `FILE:LINE:COLUMN` | cyan |
| the `^` caret row | red (yellow for a warning) |
| `help:` and its text | green |
| call-trace lines (`at f (line 4)`) | dim |

Control it with `--color=auto|always|never` on any command (the default is `auto`: color when standard error is a terminal),
with `TOMATO_COLOR=auto|always|never`, or with `NO_COLOR` (any non-empty value turns it off; `--color=always` wins because it
was asked for). Programs built with `tomato build` follow `TOMATO_COLOR` and `NO_COLOR` too, for their own runtime errors.
A terminal that is `dumb` is never colored. When output goes to a pipe or a file the text is plain, which is what the tests
and the website's copy of the text see. On the website the same text is shown with CSS classes (`e-error`, `e-warning`, `e-loc`,
`e-caret`, `e-help` ...): the output is the terminal text with the ANSI codes replaced by styles.

## Errors while a program runs

An error that stops a running program prints `error[ID]: MESSAGE`, with the diagnostic ID of the kind of failure (see "Error
classes and ids" below), for example `error[E01]: division by zero`, then a call trace: one `at FUNCTION (line N)` line for the
function where the error was raised and one for each function that called it, innermost first (`Class.method` for a method):

```
error[E01]: division by zero
  at half (line 6)
  at main (line 3)
```

An error the program raises itself with `raise` and nobody catches prints `error: ClassName: message (raised on line N)` (no
ID: the program made the message up) and then the same trace; in a release build its code is `E11`, "an error raised by the
program". A `catch` that handles the error discards its trace. At
most 24 lines are kept; further ones are counted (`... and 3 more calls`).

There are two modes (D34b). `--mode debug` (the default) prints the readable text above and reports objects that were never
freed. `--mode release` prints no trace, only a short code such as `error E01:4` (error id E01, source line 4) that
`tomato explain CODE [FILE]` turns back into the class, the message and, when a FILE is given, the source line (with a caret,
like a compiler error); it also links the program with a higher optimisation level (`clang -O2` with link-time optimisation, so
the runtime is inlined into the program, and no leak report or exit-time cycle collection; debug uses `-O1`). `tomato run`,
`build` and `compile` all take `--mode`; `--mode normal` is an error that says it was renamed to `release`.

## For compiler authors

- Raise `CompileError(message, line)` (compiler), `ParseError(message, line, col)` or `LexError(message, line, col)`. Put help
  after a newline in the message: `"'x' is defined twice\nrename one of them"`. Quote names with single quotes: the column is
  found from the first quoted name when it is not given.
- `compiler/src/diag.tom` formats the message (`format_error`, with `label='warning'` for warnings) and suggests names
  (`closest`). `compile_module` catches the three error classes and raises a `Diagnostic`, whose message is the finished
  text; the runtime prints a `Diagnostic` as it is.
- Warnings come from `compiler/src/lint.tom` (`lint_items` reads the syntax tree of one file and gives `Finding`s). The compiler
  formats them and appends them to the IR as `;! ` comment lines, which `tomato`, the repl and `site/wasm/tomato.js` take out
  and show. Add a check there, give it a kind word, keep it quiet when unsure, and make the repo's own code pass it.
- `tests/errors/NAME.tom` with the whole expected text in `NAME.out` (the error, or the warnings) is checked by `tests/run.sh`.
- Color is not the compiler's job: `tomato paint` (awk, in `native/tomato`), `use_color` in `runtime/tomato_rt.c` and
  `tomatoErrors` in `site/site.js` implement the same table.

## Types that are written but not built

A type the compiler understands but cannot build says what is unsupported, with what to do instead, rather than asking for a
type that was already written. `tomato explain` shows the id and text of each.

| Written | Message | Instead |
| --- | --- | --- |
| `x: int[length=8] \| None`, `list[uint[length=16] \| None]` | `'int[length=8]' cannot be combined with None, because only int, float, bool, str, lists, dicts, sets, classes and tuples can be None` (E459) | use `int \| None`, which holds every value |
| `x: int \| str \| None` | `a union cannot hold None together with two or more other types` (E458) | one type with `None`, or a class holding the choices |

| `Box[str \| None](...)`, `Cache[int \| str, int](...)` | `a union cannot be a type argument written in a call` (E537) | leave the brackets out and pass a variable of the union type (`Box(x)`), or wrap the union in a class |
| `Cache[Point, int](...)` where `Point` has no `@str` | `'Point' cannot be a cache key: it has no @str method` (E536, at the line that writes the cache) | add an `@str` method, or use a text or an int as the key |

Two more messages name the mistake instead of a symptom: unpacking something that is not a tuple, list or text (`c, d = 5`,
`for k, v, w in d` over ints) says `cannot unpack a value of type int into 2 variables` (E185), and a UTF-8 byte order mark at the
start of a file says `unexpected byte order mark (U+FEFF), an invisible character` (E538) and asks for the file to be saved without one.

Only a type the compiler has no reason for at all still gets `this variable cannot be given a type automatically`.

## Error classes and ids

Built-in errors have an ID formed from `E` and their line number in `std/errors.txt` (`E04` is `IndexError`, `index out of range`). The table
only grows, so an id never changes meaning. A compile error shows its id in the label (`error[E227]: name 'tets' is not defined`) and an
uncaught runtime error does too (`error[E04]: index out of range`). A program that catches an error can read `e.id` and `e.message`.

The language raises these classes, all of them a `RuntimeError` (so `catch RuntimeError` catches any of them) except `AssertionError`:

| Class | Raised for |
| --- | --- |
| `IndexError` | a list, text or range index or slice out of range; `pop()` from an empty list |
| `KeyError` | a dict key or set element that is not there |
| `ValueError` | `int("abc")`, `float("x")`, `chr`/`ord` with a bad argument, a step of 0, a negative shift count, a math domain error such as `sqrt(-1)` |
| `ZeroDivisionError` | `/`, `//` or `%` by zero |
| `OverflowError` | integer overflow, a number that does not fit its type, a float result that is infinite |
| `IOError`, `EOFError`, `CancelledError` | files, the end of input, a cancelled task |
| `AssertionError` | a failed `assert` statement or `testing` assertion; **not** a `RuntimeError`, a direct subclass of `Error` (E519), so `catch RuntimeError` does not catch it |
| `FileNotFoundError`, `FileExistsError`, `PermissionError`, `IsADirectoryError`, `NotADirectoryError` | the `IOError`s that say why a file or directory call failed (`open()`, `os`, `ospath`); each is an `IOError`, so `catch IOError` still catches them |

An `IOError` from a file says what failed: `could not open 'PATH': REASON` (E25), `could not read ...` (E381) and
`could not write ...` (E382). `f.write(text)` and `f.close()` on a file from `open(path, 'w')` raise E382 when the data cannot be
written (a full disk, a closed pipe, no permission): `could not write to the file: No space left on device`, or
`could not write to the file when closing it: ...` from `close()`. The C library buffers output, so a small write to a full disk
may fail only at `close()`; call `close()` inside `try` and catch `IOError` to be sure the data arrived.

A closed file is not an `IOError`: `close()` a second time does nothing, and `read()`, `readline()`, `readlines()`, `write()`, `writelines()`, `flush()` or a `for` loop over a file that `close()` was called on raise a `ValueError` (E547), `I/O operation on a closed file` (Python's rule; D93a). `f.closed()` is True after `close()`. A file whose last reference goes away (a variable reassigned, a function that returns, an error that unwinds) is closed too, so it is safe not to call `close()` on a file that was only read, though a file that was written should still be closed inside `try` to see a failed flush. `f.closed` without the parentheses is a compile error, E548 (`a file has no field 'closed'`): `closed` is a method.

`open()` raises the class that matches the reason (`FileNotFoundError`, `FileExistsError`, `PermissionError`, `IsADirectoryError`, `NotADirectoryError`, else a plain `IOError`) and keeps the id E25; the `os` and `ospath` functions raise the same classes with E505 to E509 (`IOError` E515 for another reason) and the text `could not list the directory 'PATH': REASON`. A mode other than `r`, `w`, `a` or `x` with an optional `+` is a `ValueError` (E510). Reading a file that cannot be read (a file opened for writing) is E381.

The libraries raise subclasses of their own, each also a `RuntimeError`: `JSONDecodeError`, `JSONEncodeError`, `JSONTypeError` and
`MsgpackError` (`json`), `TOMLDecodeError` (`toml`), `CacheMiss` (`cache`), and `requests.RequestError` (an `IOError`) with
`ConnectionError`, `TimeoutError`, `InvalidURL`, `TooManyRedirects` and `HTTPError`. They have ids too (`std/errors.txt`).

Write your own with `class MyError(RuntimeError)`. A class that declares no fields of its own inherits its parent's `@init`
(D93b), so `class NotFound(Error): pass` is made with `NotFound('no such user')` or `NotFound('no such user', 'E7')` (message,
then an optional id; both may be left out, and the message is then `""`), and so is `class Missing(NotFound): pass`. The class can give its own `@init` to take other arguments,
which calls the parent's with `Error.start(self, message, id)` (or `RuntimeError.make(self, message, id)` for a `RuntimeError`). A
class that declares fields (`code: int = 404`) does not inherit `@init`, because the parent's would leave those fields unset;
it needs an `@init` of its own, and `MyError('x')` without one is E128 with a help line saying so. The `message` and `id`
fields default to `""`.

**Printing an error.** `Error` has an `@str` that gives the message alone, as Python's `str(e)` does: `print(e)`, `str(e)` and
`f'{e}'` are `e.message`, with no class name and no id. An error nobody catches prints more, `error: ClassName: message (raised on
line N)` (above), because there the class name is the only clue to what went wrong. Every error class inherits the `@str`; a
class can give its own (one method marked `@str`, any name) and `print` then uses that, but the uncaught-error report does not: it
always prints the class name and the `message` field. Release builds print `error E04:12` with the ID and the line
where the error was raised. `tomato explain E04:12 prog.tom` shows the diagnostic and line from the supplied file. `tomato explain E04`
shows the class and message without a file. A line of zero means the runtime has no source location, for example when startup
input is invalid or the machine runs out of memory. These process failures and stack exhaustion report an ID and terminate.

A mistake in a configuration file (`tomato.toml` or `config.toml`, see `tomato config`) stops `tomato run`, `build`, `compile` and `config` with a `ConfigError` id: E539 the file cannot be read, E540 it is not valid TOML, E541 `limits` is not a table, E542 an unknown setting in `[limits]`, E543 a setting is not a whole number in its range.

To add an error, append a line in the form `Class text` to `std/errors.txt` and keep the existing line numbers. An id that is no longer raised is never deleted or reused: its line becomes `Class (retired: why; the id stays so that later ids do not move)`. Pass that ID when
raising an error in the standard library. For a compiler-emitted runtime check, the table text is a prefix of the message.
For a compile diagnostic, use `CompileError template`, with `{}` for dynamic parts of the first line. The compiler uses the
most specific matching template and falls back to E368 for unrecognized messages.
