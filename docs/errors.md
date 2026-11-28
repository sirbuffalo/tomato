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
- The next lines show that source line with a row of `^` under the offending text. For a problem with a value the caret is under
  the expression at fault (the whole `bytes('abc')` inside `print(1, bytes('abc'))`, the `'a'` of `y: int = 'a'`), and under the
  call at fault when there are several of the same function on the line (`print(f(3), f([1]))` points at the second `f`); for
  an operator it is under the operator's symbol; for a `catch` clause it is on the clause's own line. When the compiler knows only
  the line, the caret covers the statement (without a comment at its end).
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
| `unreachable` | a statement follows a `return`, `raise`, `break` or `continue` (or an `if`/`else` or `try` whose branches all leave; a `try` whose body always raises and whose `catch` clauses all leave counts even when they do not cover every error class, as an uncaught error leaves too) | `this code can never run, because the statement before it always leaves` |
| `unassigned` | a variable is read where some path to it did not give it a value | `'label' might not have a value here, because some paths above do not give it one` |
| `shadow` | a variable has the name of a built-in, or of a function, class or constant of the same file | `the variable 'len' has the same name as a function or class, which it hides here` |
| `loop-change` | a list is changed (`append`, `pop`, `remove` ...) inside a `for` loop that goes through it | `'xs' is changed while the loop goes through it` |
| `module-shadow` | a file of the project (next to the program or in `src/`) has the name of a std module, so `import json` gets the file; once for each name, at its first import (D115a) | `the file json.tom of this project shadows the standard module 'json'` |
| `unstable` | a program uses a feature that is still on the unstable list of `docs/provisional.md` (section 1): `progress_bar`, `random.choice`, `shuffle` or `sample`, a method marker beyond `@add` such as `@eq` or `@iter`, `start`, or a name of the std of stage 1 of the shell-to-Tomato plan such as `os.copy` or `signal.watch` (U7); once for each feature in a build, at its first use (D121a, D129a) | `'progress_bar' is an unstable feature (U3, the text progress_bar draws)` |
| `deprecated` | a program uses a std function, class, constant or module that a minor release has deprecated, and a later minor release may remove (D129a); once for each name in a build, at its first use | `'old_double' is deprecated (deprecated_fixture.old_double, since 1.1)` |
| `catch-order` | a `catch` clause comes after one for the same class or for a parent class, so it can never run (P16); `# allow: catch-order` on the clause hides it | `this 'catch ValueError' can never run: the clause for Error above it catches every ValueError first` |
| `type-test` | `x in T` with a type on the right, the old spelling of the type test `x is T` (D23i); it still works in 1.0.x | `'in' with a type is the old spelling of the type test` |

To silence one, write `# allow: KIND` as a comment on the line the warning points at (`total = 0  # allow: unused`). A name
that starts with `_` is meant to be unused, and loop variables, `catch` variables and parameters are never reported as unused.
`tomato run --no-warnings` (or `TOMATO_WARNINGS=off`) hides them all. The repl never shows warnings.

The `unstable` warning is given once for each feature of the unstable list, at the first use, whatever file it is in; it is about code you write, so a standard library module, a seed's module or a file with the std module's own name never gives it. It points at the `from module import name` line or at the first `module.name` (or `alias.name`) that names the feature; for U5, the marker beyond `@add` (`@eq`, `@lt`, `@iter` ... as the list in `docs/provisional.md` says) on the line above its method; for U6, the first `start`. `# allow: unstable` on that line hides that use; the next use on a line without the comment warns instead (so a program that starts tasks in five places needs the comment on five lines, or `--no-warnings`). The list is `compiler/src/unstable.tom`, and the suite checks that it agrees with `docs/provisional.md`. Two features of the list, the wording of messages and the host's input protocol, are not written in a program, so there is nothing to warn about.

The `deprecated` warning (D129a) is given for a std name that a minor release has deprecated, which a later minor release may remove (`docs/releasing.md`, Compatibility: std follows Python's rule). It is built like the unstable one: once for each name in a build, at the first `from module import name` or `module.name` (`alias.name`) that uses it, or, for a whole deprecated module, at its first import; it names the item, the version that deprecated it and what replaces it, `# allow: deprecated` on the line hides that use and `--no-warnings` hides all. Only code you write gives it, never a std module, a seed's module or a file with the std module's own name. The names are in `compiler/src/deprecated.tom`, one row for each, and in the table below; the suite checks that each exists in std and that the two agree. No std name is deprecated yet, so the table is empty. Deprecating a name takes a row in the file, a row in the table and a line under **Deprecated** in `docs/changelog.md`; removing it takes a later minor release (and a line under Breaking changes). The test-only rows of the file (`deprecated_fixture` in `tests/deprecated/`) are how the suite tries the warning and are not std.

Deprecated names (none yet):

| Name | Since | Use instead |
| --- | --- | --- |

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
ID: the program made the message up) and then the same trace; a release build prints it as `error[E11]: ClassName: message (line N)`
with no trace (below), `E11` being the id of "an error raised by the program". A `catch` that handles the error discards its trace. At
most 24 lines are kept; further ones are counted (`... and 3 more calls`).

There are two modes (D34b). `--mode debug` (the default) prints the readable text above and reports objects that were never
freed. `--mode release` prints the same head on **one line**, with the line where the error was raised and no trace (D34c):
`error[E01]: division by zero (line 4)` for the language's own failures, and `error[E11]: ValueError: config file missing key port
(line 3)` for an error the program raised (the class name is printed for these, as in debug mode, where the class is the only
clue; an id that the program gave its own error is printed in place of `E11`). Debug mode writes `(raised on line N)` and puts the
lines of the trace under it; release writes `(line N)` and nothing below. The message is whole, however long, and is the message
of `std/errors.txt` for a runtime failure; a message of several lines is printed as it is. A failure of the runtime itself with no
source location (out of memory, a stack overflow, invalid startup input) has no `(line N)`. `tomato explain CODE [FILE]` still
decodes an id and, given the id and line as `E01:4`, shows the source line with a caret, like a compiler error; it also links the program with a higher optimisation level (`clang -O2` with link-time optimisation, so
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
- The `unstable` warning is not made by `lint.tom` (it needs the names the compiler resolved): `warn_unstable` in `compiler/src/compiler.tom` reads `compiler/src/unstable.tom`, the one list of the unstable features. Add a feature there and in the table of `docs/provisional.md`; `tests/run.sh` (`t_unstable_features`) fails when the two differ. The `deprecated` warning (`warn_deprecated`) is the same kind of thing and reads `compiler/src/deprecated.tom`; `t_deprecated` checks it against std and the table "Deprecated names" above.
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
| `x: int \| None \| None`, `-> None \| None` | `None is written more than once in this union` (E610) | write `None` once |
| `x: None` | `this parameter type is not supported` (E313; a return type and a field say "return type" and "field type", with ids of their own) with the help `None alone is not a type` | write the type that can be None, such as `int \| None` |

These point at the type that is wrong (the caret is under the start of the union, or under `None`), not at the whole `def`.
Other smoothed messages: `self.s + 'x'` where `s` is a field of type `str | None` (E190) adds that a field is not narrowed by
`is not None`, so to copy it to a variable first; `xs = [1, None]` (E324) says to write the type of the list, `xs: list[int | None] = ...`;
`helper.f()` where `helper.tom` has `f` but not `export def f` is E225 ("module 'helper' does not export 'f'", with the help to put
`export` before its definition), as `from helper import f` already said.

| `Box[str \| None](...)`, `Cache[int \| str, int](...)` | `a union cannot be a type argument written in a call` (E537) | leave the brackets out and pass a variable of the union type (`Box(x)`), or wrap the union in a class |
| `Cache[Point, int](...)` where `Point` has no `@str` | `'Point' cannot be a cache key: it has no @str method` (E536, at the line that writes the cache) | add an `@str` method, or use a text or an int as the key |
| `Cache[tuple[Point, int], int](...)`, `Cache[list[Point], int](...)`, `memoize(f, n)` with `f(p: Point)` | the same E536, also when the class is inside a tuple or list key and also for `Memo` and `memoize` (never a message from inside `std/cache.tom`) | the same |

Two more messages name the mistake instead of a symptom: unpacking something that is not a tuple, list or text (`c, d = 5`,
`for k, v, w in d` over ints) says `cannot unpack a value of type int into 2 variables` (E185), and a UTF-8 byte order mark at the
start of a file says `unexpected byte order mark (U+FEFF), an invisible character` (E538) and asks for the file to be saved without one.

Only a type the compiler has no reason for at all still gets `this variable cannot be given a type automatically`.

## Operator methods, checked where they are written

A method marked `@add`, `@neg`, `@hash`, `@lt` and the other operator and protocol markers must have the shape its use needs, and the
compiler says so at the `def` line when it reads the class, whether or not the operator is ever used (an unused class with a wrong
marker used to compile): `@add`, `@sub`, `@mul`, `@div`, `@floordiv`, `@mod`, `@pow`, `@bitand`, `@bitor`, `@bitxor` and `@rmul` take one
argument besides `self` and return the result (E254, E551); `@eq`, `@lt`, `@le`, `@gt` and `@ge` take one argument and return `bool`
(E254, E253); `@neg` and `@invert` take nothing and return the result (E531, E552); `@hash` takes nothing and returns an `int` (E550);
`@str` takes nothing and returns `str` (E252). The caret is under the method's name and the help says what to write. A class whose
`@eq` compares with another type (`def same_x(self, x: int) -> bool`) can still be used as it is, but not as a dict key or set element,
where two keys are compared with each other: that says `its @eq method 'same_x' compares with int` (E554, at the line that makes the dict or set).

Other messages that used to be rough:

| Written | Message |
| --- | --- |
| `-u` with `u: Angle \| int` | `cannot use '-' on a value that can be math.Angle \| int, because a union has no '-' of its own` (E549), and the help shows `if u is Angle: ... -u` |
| `min(1, 2.5)`, `max(1, 2.5)` | `min() was given a value of type int first and then one of type float` (E553): the first value sets the type, so put the float first or write `float(...)` around the int (`min(2.5, 1)` works) |
| `a, b = None` | `cannot unpack None into 2 variables` (E185); the hidden variable of the unpack is never named |
| a wrong argument, or an unknown method, of `Cache[Point, int]` | the type is written as the program wrote it, `cache.Cache[Point, int]`, never with the compiler's internal `@Point` |
| `print(nothing(xs))`, `str(nothing(xs))`, `f"{nothing(xs)}"`, `nothing(xs) + 1`, `x = nothing(xs)`, `await nothing(xs)` where `nothing` returns nothing | `'nothing' gives no value, so it cannot be used inside an expression` (E652), the caret under the name; one check in the compiler for every place a value is used (D132a). A call on a line of its own is fine |
| a text where bytes are taken (`hashlib.sha256_hex('abc')`, `x: bytes = 'abc'`, `b'a' + 'a'`, `'a' in data`), bytes where text is taken, a `bytearray` where bytes are taken (`os.write_bytes(path, ba)`) or bytes where a `bytearray` is | the E324, E190 or E635 of before, with a help line: `encode it: s.encode() gives its UTF-8 bytes`, `decode it: b.decode() gives the text`, `a bytearray is not bytes: bytes(a) gives the bytes it holds now (a copy)`, `bytes cannot be changed: bytearray(b) makes a bytearray with a copy of them` (D134a). The type of a bytearray is written `bytearray` (and `bitarray`), as the program writes it, not `bytearray.bytearray` |
| `{ba: 1}`, `{ba}` and `hash(ba)` with `ba` a `bytearray` | `a bytearray can change, so it cannot be a dict key or set element` with the help `use bytes(a), which cannot change, as the key` (it said to add an `@hash` method to the class) |
| `bytes(range(4))`, `'é'.encode('ascii', 'ignore')` | E632 says `make a list of it first: bytes(list(range(4)))`; E626 for `encode` names the modes `'strict'` and `'replace'` and what replace puts in (`?`), where it spoke of U+FFFD, which is `decode`'s |
| `half(5)` where `half` takes a `float`, or `float \| None` (`sys.run(args, timeout=5)`) | E324 with the help `an int is not a float: write the number with a point (5.0), or convert it with float(n)` |
| `json.dumps(d)` with a `dict[str, int]`, `json.dumps('text')` | E324 with the help `a value.Value is built with the classes of the value module: from value import Value, Dict, List, Str, Int, Float, Bool` and an example (`Dict({'a': Int(1)})`) |
| `ba + 'x'`, `ba += 'x'` with `ba` a `bytearray` | E190 `cannot use '+' with bytearray and str`, with the help `a bytearray and text are different types: encode the text (s.encode()) or decode the bytearray (a.decode())` |
| `catch A, B as e:` or `catch (A, B):` | `a 'catch' clause names one error class, so it cannot list several` (E656), with the help to write one clause for each class or catch their parent (D135a) |
| `catch ProcessError:` with no import of `sys` | `'catch' needs an error class, but 'ProcessError' is not defined` (E657), and where the class is: `it is in the sys module: write sys.ProcessError after 'import sys', or 'from sys import ProcessError'` (D135a); a class that is no error is still E98 |
| `from math import sqrt as int`, `import math as str` | `'int' is the name of a built-in type, so it cannot be defined here` (E608), at the alias (D135a) |
| `def main(arg: bytes)`, `*ids: tuple[int]` of an entry | `the input 'arg' of the entry 'main' cannot have the type bytes` (E157), at the parameter, with what an input can be: int (of any width), float, bool, str, File, and a last `*name: tuple[str]` or `tuple[File]` (D136a) |
| `./prog stats` for `def stats(count: int, ratio: float, label: str = 'x')` | `stats takes 2 to 3 inputs (count, ratio, label), but got 0` (E352) and `usage: prog stats COUNT RATIO [LABEL]`; a word that does not fit is `input 2 (ratio) must be a number, found 'abc'` (E351) with the same usage line; `./prog -h` lists the entries and their inputs (D136a) |
| a text, list or object variable read where no assignment ran (`for s in items: ...` then `print(s)` when `items` is empty) | the catchable `RuntimeError` E658, `this variable has no value yet: 's' is read where no assignment to it has run` (D137a); the `unassigned` warning stays |
| `print(f)`, `str(f)` with `f` a `File`, or a task | `a value of type File cannot be printed` (E167), `... cannot be converted to text` (E166); they printed an empty line or were a raw clang error (D132a) |


## Error classes and ids

Built-in errors have an ID formed from `E` and their line number in `std/errors.txt` (`E04` is `IndexError`, `index out of range`). The table
only grows, so an id never changes meaning. A compile error shows its id in the label (`error[E227]: name 'tets' is not defined`) and an
uncaught runtime error does too (`error[E04]: index 10 is out of range for a list of 3 items`: the line of the table is the kind of error,
and the message of a list, text, bytes or range index names the index as it was written and the length). A program that catches an error can read `e.id` and `e.message`.

The language raises these classes, all of them a `RuntimeError` (so `catch RuntimeError` catches any of them) except `AssertionError`:

| Class | Raised for |
| --- | --- |
| `IndexError` | a list, text or range index or slice out of range; `pop()` from an empty list |
| `KeyError` | a dict key or set element that is not there |
| `ValueError` | `int("abc")`, `float("x")`, `chr`/`ord` with a bad argument, a step of 0, a negative shift count, a math domain error such as `sqrt(-1)` |
| `ZeroDivisionError` | `/`, `//` or `%` by zero |
| `OverflowError` | integer overflow, a number that does not fit its type, a float result that is infinite |
| `IOError`, `EOFError`, `CancelledError` | files, the end of input, a cancelled task |
| `TimeoutError`, `ConnectionError` | a wait that ran out of time, a connection that failed; both are `IOError`s, and the libraries' own timeouts and connection failures are their subclasses (below, D114a) |
| `AssertionError` | a failed `assert` statement or `testing` assertion; **not** a `RuntimeError`, a direct subclass of `Error` (E519), so `catch RuntimeError` does not catch it |
| `FileNotFoundError`, `FileExistsError`, `PermissionError`, `IsADirectoryError`, `NotADirectoryError` | the `IOError`s that say why a file or directory call failed (`open()`, `os`, `ospath`); each is an `IOError`, so `catch IOError` still catches them |
| `ProcessError`, `ProcessTimeout` (`sys`) | what `sys.run` and `sys.run_async` raise about a program that ran: `ProcessError` (E588) for `check=True` and a status other than 0, `ProcessTimeout` (E589, a `ProcessError`) for a program killed after its `timeout`; both are `RuntimeError`s (not `IOError`s) with the fields `program`, `status`, `signal`, `stdout` and `stderr`, and a message such as `'clang' exited with status 1: ` followed by the end of its standard error; a program that cannot be started is a `FileNotFoundError` (E505), `PermissionError` (E507) or other `IOError` (E515) saying `could not run 'NAME': REASON`, and an empty `args`, a NUL, a bad `env` name or a `timeout` of 0 or less is a `ValueError` (E585, E511, E512, E587; E586 for an empty `cwd`) (D98a); `sys.spawn` and its `Process` raise the same errors for a program that cannot be started and for a bad argument, and `ValueError` E595 for a stream of a program started with `capture=False`, E596 for `write` on an input that is not a pipe or is closed, E597 for a signal number outside 1 to 64, and `IOError` (E515) for a write to a program that has closed its input (D98b) |
| `Interrupted` (`sys`, raised by `signal`, new, unstable U7) | a signal that `signal.watch()` recorded (INT, TERM, HUP by default) was taken at a place that looks (`signal.check()`, `sys.run`, `sys.run_async`, `Process.wait()`): E661, a direct subclass of `Error` (not a `RuntimeError`, so `catch RuntimeError` and `catch IOError` do not hide it), with the fields `number` and `name`. When nothing catches it the program ends without a message and with status 128 plus the signal number (130 for Ctrl-C). A name that is not a signal this module knows, or `KILL` to watch, is a `ValueError` (E662); `signal.send` to a process that is not there is an `IOError` (E515), to one that is not yours a `PermissionError` (E507) (D139a) |
| the new `os`, `hashlib` and `requests` functions (new, unstable U7) | `os.copy`, `copytree`, `chmod`, `utime`, `symlink`, `readlink`, `realpath`, `mkdtemp`, `mkstemp`, `rmtree`, `exchange` raise the file classes above (`FileNotFoundError` E505, `FileExistsError` E506, `PermissionError` E507, `IsADirectoryError` E508, `NotADirectoryError` E509, `IOError` E515) with `could not WHAT: REASON`; a `/` in the prefix or suffix of `mkdtemp` or `mkstemp` is a `ValueError` (E659); `os.cache_dir` without `HOME` is an `IOError` (E660); `hashlib.sha256_file` raises the file classes; `requests.download` raises the errors of `requests` (`InvalidURL` E361 for an address or a redirect that is not https while `https_only` is on, `HTTPError` E358, `TimeoutError` E360, `ConnectionError` E364), a `RequestError` (E363) for a body larger than `max_bytes`, an `IOError` (E515) for a file that cannot be written, and a `ValueError` (E663) for a negative `max_bytes`. In the browser playground these raise `RuntimeError` (E514, `... is not available in the browser playground`) where they need the system (D139a) |
| `GzipError`, `TarError` (`gzip`, `tarfile`, new, unstable U7) | `gzip.GzipError` (a `ValueError`) is bad gzip data: E664 it does not start like gzip, E665 damaged, E666 cut short, E667 the checksum or size does not match, E668 longer than `max_size`, E669 something after its end, E670 could not be read; a `gzip` level outside 1 to 9 (E671) or a `max_size` under 1 (E672) is a plain `ValueError`. `tarfile.TarError` (a `ValueError`): E673 the archive is damaged or is not a tar archive (a header that does not match its checksum, a cut header), E674 an entry that is not extracted (a hard link, a device, a pipe, a sparse file, any other kind), E675 an entry that would leave the folder (an absolute name, a `..` part, a link that points out, a write through a link, a folder or file in the way), E676 more than `max_size` bytes of files, E677 something in a folder that cannot be archived (a pipe, a socket, a file of 8 GiB or more); a negative `strip` is a `ValueError` (E678). A damaged `.tar.gz` raises the `GzipError` of its kind, a file that cannot be read the file classes (D140a) |

An `IOError` from a file says what failed: `could not open 'PATH': REASON` (E25), `could not read ...` (E381) and
`could not write ...` (E382). `f.write(text)` and `f.close()` on a file from `open(path, 'w')` raise E382 when the data cannot be
written (a full disk, a closed pipe, no permission): `could not write to the file: No space left on device`, or
`could not write to the file when closing it: ...` from `close()`. The C library buffers output, so a small write to a full disk
may fail only at `close()`; call `close()` inside `try` and catch `IOError` to be sure the data arrived.

Standard output is buffered the same way. When it cannot be written (`./prog > /dev/full`, a closed pipe that does not kill the
program), `sys.flush()` and `sys.write_stdout()` raise `IOError` E382 (`could not write to standard output: No space left on device`),
and a program that never looks is told at its end: the same line on standard error and status 1, where the status was 0 and
nothing was said (D134a). `print` itself does not raise, because the text is only buffered when `print` returns; a program that must
know sooner calls `sys.flush()` inside `try`. A killed process (`| head` ends the pipe with SIGPIPE, status 141) is as it was.

A closed file is not an `IOError`: `close()` a second time does nothing, and `read()`, `readline()`, `readlines()`, `write()`, `writelines()`, `flush()` or a `for` loop over a file that `close()` was called on raise a `ValueError` (E547), `I/O operation on a closed file` (Python's rule; D93a). `f.closed()` is True after `close()`. A file whose last reference goes away (a variable reassigned, a function that returns, an error that unwinds) is closed too, so it is safe not to call `close()` on a file that was only read, though a file that was written should still be closed inside `try` to see a failed flush. `f.closed` without the parentheses is a compile error, E548 (`a file has no field 'closed'`): `closed` is a method.

`open()` raises the class that matches the reason (`FileNotFoundError`, `FileExistsError`, `PermissionError`, `IsADirectoryError`, `NotADirectoryError`, else a plain `IOError`) and keeps the id E25; the `os` and `ospath` functions raise the same classes with E505 to E509 (`IOError` E515 for another reason) and the text `could not list the directory 'PATH': REASON`. That includes `os.read_text` and `os.write_text` (D134a: they read and write through `read_bytes` and `write_bytes`, so a missing file is E505 there and E25 from `open()`). A mode other than `r`, `w`, `a` or `x` with an optional `+` is a `ValueError` (E510). Reading a file that cannot be read (a file opened for writing) is E381.

**One tree (D114a).** The libraries raise subclasses of their own, each also a `RuntimeError`, and the tree has one place for each:

```
Error
  AssertionError                       a failed assert (not a RuntimeError)
  RuntimeError
    IndexError, ZeroDivisionError, OverflowError, EOFError, CancelledError, LockError (asyncio)
    KeyError            CacheMiss (cache)
    ValueError          StructError (struct), JSONDecodeError, JSONEncodeError, MsgpackError (json),
                        ValueTypeError (value: a wrong kind, a missing key or an index out of range in a value read by
                        json or toml, D122a; it was json.JSONTypeError; its message ends with `(at ['a'][0])`, the keys and indexes the value was read through, D143a), TOMLDecodeError (toml), RegexError (re)
    IOError             FileNotFoundError, FileExistsError, PermissionError, IsADirectoryError, NotADirectoryError,
                        TerminalError (terminal), requests.RequestError (InvalidURL, TooManyRedirects, HTTPError)
      TimeoutError      asyncio.TimeoutError, requests.TimeoutError
      ConnectionError   requests.ConnectionError, socket.SocketError (ConnectionRefusedError, ConnectionResetError, AddressError)
    ProcessError (sys)  ProcessTimeout
```

`catch TimeoutError` handles a timeout from `asyncio.wait_for` and from `requests` alike, `catch ConnectionError` a refused or reset
socket and a failed request, and `catch IOError` all of these and the file errors; `catch asyncio.TimeoutError` still handles only
asyncio's. The rule: a failure of the world outside the program (files, the network, the terminal) is an `IOError`; text or data a
function was given that it cannot accept is a `ValueError`; a lookup that finds nothing is a `KeyError`; the rest is a `RuntimeError`.
`requests.TimeoutError` and `requests.ConnectionError` are not `RequestError`s (a class has one parent). A library class may have the name of the class it extends (`class
TimeoutError(TimeoutError)` in `asyncio`). They have ids too (`std/errors.txt`), unchanged by the move.

**Raising again.** A bare `raise` in the body of a `catch` raises the caught error again (the innermost `catch` it is in): the same object, with
its class, id, message, the line it was first raised on and, in debug mode, its call trace, so an error that goes through a handler that
only logs it looks as if nothing had caught it:

```
try:
    load(path)
catch IOError as e:
    print('could not load', path)
    raise
```

Anywhere else a bare `raise` is a compile error, E614 (`'raise' with no error can only be used inside a 'catch' block`): outside any
`catch`, in the `try` body or its `finally`, and in a function that a `catch` calls (give that function the error as an argument and
`raise e`; `raise e` makes the error leave from that line, with a trace that starts there).

**The `catch` name belongs to its block (D131a).** In `catch ValueError as e:` the name `e` has a value only inside that block. Reading it after
the block (after the `try`, in its `else` or `finally`, or in the next pass of a loop) is a compile error, E651 (`the name 'e' belongs to a catch
block that has ended, so it has no value here`), because no error was caught on the path that skips the block and the program would stop there. To use the error afterwards,
copy it to a variable declared before the `try` (`last: ValueError | None = None`, then `last = e` in the block). A name that already had a value before the `try`
(a parameter, or a variable assigned earlier) is an ordinary variable that the `catch` gives a new value, and stays usable; the same name in two `catch` blocks
is fine. A variable that a loop or an `if` gives a value to is still the function's (P7), and the `unassigned` warning below covers it.

Write your own with `class MyError(RuntimeError)`. A class that declares no fields of its own inherits its parent's `@init`
(D93b), so `class NotFound(Error): pass` is made with `NotFound('no such user')` or `NotFound('no such user', 'E7')` (message,
then an optional id; both may be left out, and the message is then `""`), and so is `class Missing(NotFound): pass`. The class can give its own `@init` to take other arguments,
which calls the parent's with `Error.start(self, message, id)` (or `RuntimeError.make(self, message, id)` for a `RuntimeError`, `IOError.make_io` for an `IOError`). A
class that declares fields (`code: int = 404`) does not inherit `@init`, because the parent's would leave those fields unset;
it needs an `@init` of its own, and `MyError('x')` without one is E128 with a help line saying so. The `message` and `id`
fields default to `""`.

**Printing an error.** `Error` has an `@str` that gives the message alone, as Python's `str(e)` does: `print(e)`, `str(e)` and
`f'{e}'` are `e.message`, with no class name and no id. An error nobody catches prints more, `error: ClassName: message (raised on
line N)` (above), because there the class name is the only clue to what went wrong. Every error class inherits the `@str`; a
class can give its own (one method marked `@str`, any name) and `print` then uses that, found through the object's own class, so a
value typed `Error` that holds an `Own` shows `Own`'s text (D111a), but the uncaught-error report does not: it
always prints the class name and the `message` field. Release builds print the same on one line, with the line and no trace:
`error[E11]: ClassName: message (line 12)`, or `error[E04]: index 10 is out of range for a list of 3 items (line 12)` for a runtime failure.
`tomato explain E04:12 prog.tom` shows the diagnostic and line from the supplied file. `tomato explain E04`
shows the class and message without a file. A line of zero means the runtime has no source location, for example when startup
input is invalid or the machine runs out of memory. These process failures and stack exhaustion print `error[ID]: message`
(no line) and terminate.

A mistake in a configuration file (`tomato.toml` or `config.toml`, see `tomato config`) stops `tomato run`, `build`, `compile` and `config` with a `ConfigError` id: E539 the file cannot be read, E540 it is not valid TOML (the error shows the line and a caret, and `tomato test` reports it once), E541 `limits` is not a table, E542 an unknown setting in `[limits]`, E543 a setting is not a whole number in its range. The manifest checks add E555 to E568 (unknown tables and keys, missing or mistyped settings, versions, names, the `tomato` minimum, `[build]`) and the seed commands E569 to E580 (E570 is retired) and E598 to E606 (git, the seed store, the foreign symbols, the edits of `tomato seed add` and `remove`, D101a, and `tomato seed verify`, D103a), E621 (a word given to `tomato seed add` that is no host shortcut or seed name, D124a) and E622 (the `# seeds:` line of a program, D124a), and E679 to E685 (the index client, D141a: E679 the registry settings, `[aliases]` and the words of `tomato seed registry`, `alias` and `unalias`; E680 an index this Tomato cannot read; E681 `ssh-keygen` missing; E682 a seed, version or name the registry does not have or vouch for, with the ignored statements listed; E683 requirements on two incompatible lines of one seed; E684 a registry seed that is not what its signed entry says, or a lock and an index that disagree about a published version; E685 a version its owner yanked as malware, without `--allow-yanked`), and E571 when a name needs a registry and none is set up, with E581, E607 and E611 as compile errors (E611: a `!tomato_*` runtime function used outside `std/`, D112a; E612 is the seed command's refusal of the same) (a module of the project with the name of a module of a seed, D107a), and E590 for a table below `[seeds]` or `[test-seeds]` (D94b); `docs/manifest.md` lists them all. A built program started with a first word that is no entry stops with E591, and an entry input of type `File` that cannot be opened stops it with E592. A definition that takes the name of a built-in type (`def str`, `class list`, `const int`; D107a) is E608, and calling a constant (`const len = 4` then `len(x)`) is E609; a variable, parameter, loop or `catch` name or lambda parameter named like a built-in type (`str = 'a'`, `def f(list: int)`; any other name of a built-in may be defined and then wins in that module. A bare `raise` outside a `catch` block is E614 (D114a).

To add an error, append a line in the form `Class text` to `std/errors.txt` and keep the existing line numbers (the promise about ids, classes and wording is in `docs/releasing.md`, Compatibility). From 1.0.0 on the first lines of the file are frozen: `std/errors_frozen.txt` holds how many and their sha256, and the suite fails ("std/errors.txt is append-only after 1.0: add new errors at the end; to retire one, leave a tombstone line") when one of them is edited, moved or removed (`tomato run dev/freeze_errors.tom check` runs the same test; D142a). An id that is no longer raised is never deleted or reused: its line becomes a tombstone, `Class (retired: why; the id stays so that later ids do not move)`. Pass that ID when
raising an error in the standard library. For a compiler-emitted runtime check, the table text is a prefix of the message.
For a compile diagnostic, use `CompileError template`, with `{}` for dynamic parts of the first line. The compiler uses the
most specific matching template and falls back to E368 for unrecognized messages.

## Two branches that each add an error

An id is the line number of its template in `std/errors.txt`, so two branches that each append a line give the same id (say E607) to two different errors, and git sees a conflict at the end of the file. The rule that settles it follows from "an id never changes its meaning" (`docs/releasing.md`, Compatibility):

- **An id is fixed once it is on `main`.** Before that it is only a line number on one branch and belongs to nobody. A released id (any line of `std/errors.txt` in a tagged version) is never moved, whatever else happens; from 1.0.0 the suite enforces it.
- **The branch that merges second renumbers its own lines**, never the other branch's. This holds for every open task: a task started before a merge renumbers when it next merges `main`.

The steps, after `git merge main` reports a conflict in `std/errors.txt` (or, with no textual conflict, when the check below fails):

1. Take `main`'s version of the file: every line in `main`, in `main`'s order. Then append your lines, in your order, after its last line. A line you changed in the middle of the file is a mistake: put it back (a message is never edited in place, a retired error keeps its line: see above).
2. Your lines now have new numbers: the old id plus the number of lines `main` added. Change each use of every old id to the new one, **highest first** so that a new id never collides with an old one still to be changed: `grep -rn "'E607'" std site/wasm/std runtime tests docs`, then edit the raises in `std/*.tom` (and the copies in `site/wasm/std/`), the ids written in `runtime/tomato_rt.c`, the expected outputs (`tests/errors/*.out`, `tests/expected/*.out`) and any documentation that names the id. A compile error needs no source change: its id is found from its template.
3. Run the checks that notice a stale id: `tests/run.sh` (`t_error_raises` says which standard-library raise has no id for its class; the template check says which compile error has no line; the expected outputs name every id that moved).

When both branches add the same message (the same template), keep one line and point both uses to it. Do not "make room" by inserting a line in the middle of the file: every id after it would change meaning.
