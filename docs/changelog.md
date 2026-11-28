# Changelog

What changed in each release, for people who use Tomato. The GitHub release page also lists every merged commit
(`release/release.sh` creates it with `--generate-notes`); this file is the short, readable version. Decision numbers
(D78a and so on) point into `docs/decisions.md`.

From 1.0.0 on, all releases of one minor version (1.0.0, 1.0.1, ...) are compatible with each other: a program that
works on one works the same on the others (except the 7 features on the unstable list in `docs/provisional.md`). A new minor version
(1.1.0) may change behaviour, and its section lists each such change under **Breaking changes**; a patch release has
none. `tomato update` installs patch releases at once and a new minor version only with `tomato update --minor`.

## 1.0.0 (draft, not released yet)

Everything since v0.51 (2026-11-23). From this release on, versions are MAJOR.MINOR.PATCH (the releases before were
numbered 0.1 to 0.51), with pre-releases such as 1.1.0-rc.1 that only `tomato update --pre` installs; `tomato update`
on an older install moves to 1.0.0 as usual.

### Breaking changes

- The repl and the website playground show a bare expression with the built-in `print` even when the session defines its own `print` (the echo is written `_core_print`, which the lexer reads as the built-in).
- `!tomato_NAME(...)` declarations and calls are a compile error outside `std/` (E611, D112a): the runtime's `tomato_*` functions belong to the runtime and are not part of the language, so use the std module that wraps one. `!name` for any other symbol (libc, your own C or IR) works as before, and a seed that declares a `tomato_*` symbol is refused (E612) instead of listed for consent.
- In `--mode release` an uncaught error prints one line with the class and the message, and the line, with no call trace (D34c):
  `error[E11]: ValueError: config file missing key port (line 3)`, or `error[E01]: division by zero (line 4)` for the language's own
  failures. It printed only `error E11:3` and `error E01:4`. `tomato explain` still takes `E01:4`.
- A function, class or constant that a program defines with the name of a built-in function or class (`print`, `open`, `len`, `range`, ...) is used in that module, where the built-in was used before and the definition ignored (D108a). A definition with the name of a built-in type (`def str`, `class list`) is a compile error (E608); it was ignored.
- A set of marker names is reserved (D113a): a top-level marker that is, or starts with, `main`, `test`, `bench`, `example`, `setup`, `teardown`, `deprecated`, `init` or an operator marker (`@add`, `@hash`, ...) is a compile error (E613) unless the language defines it (`@main`, `@test`, `@test.NAME`); rename it (`@bench_sort`). `@add.fast` and the like were entry names before.
- The type test is written `x is T` (and `x is not T`), not `x in T` (D23i): `if v is Circle:`, `if x is int:`, `if s is None:`. `x in T` with a type on the right still works in 1.0.x and prints a warning (`type-test`, `# allow: type-test` silences it); membership stays `in` (`if a in items:`). `a is b` on two objects, lists, dicts or sets is now identity (it was an error); on numbers, text and tuples it is an error that says to use `==`.
- `x is Class` checks the class of the object, not the declared type of the variable (D112a): with `a: Animal = Dog()`, `a is Dog` is now True (it was False; `a is Animal` was and is True), `a is Cat` is False, and the same holds for interface values, `Animal | None` and unions such as `Animal | int`. `x is Dog` on an `Animal` also makes `a` a `Dog` inside the branch (`if a is Dog: print(a.tricks)`), as `x is not None` makes an optional its type.
- A program built by `tomato build` takes `[ENTRY [INPUTS...]]` as its arguments (D94b): no word runs `main`, a first word that names an entry
  runs that entry with the words after it, and any other first word is an error that lists the entries. What was `./prog 30` for a
  `main(n: int)` is now `./prog main 30`; `tomato build FILE --entry NAME` still makes a program with that one entry that takes only its inputs.
- `tomato run X` where X has no `.tom` and no `/` is an entry name, not a file; the options of `tomato run` go before the entry (what
  follows it is raw input, `tomato run f.tom greet --mode` passes `--mode` to `greet`), and `--` ends the options earlier.
- `tomato build` with no `-o` writes `builds/NAME` (in the project's folder, or the current folder when there is none), not `./NAME`.
- `[seeds.ENTRY]` tables of `tomato.toml` are gone (D94b, they were never in a release): `[test-seeds]` lists the seeds only tests use, and
  `[seeds.test]` is an error that says so. In `tomato.lock` `test_only = true` replaces `entries`.
- Passing an `int` where an `int[length=64]` is expected is a compile error (convert with `int[length=64](x)`, which
  now checks the range), and `int[length=64]` mixed with `int` is `int` arithmetic.
- `sin`, `cos` and `tan` of a radian angle give the C library's answer: `sin(rad(pi))` is `1.2246467991473532e-16`
  instead of `0.0`, and `tan` of a radian angle no longer raises E47 (D83a).
- `float[length=64]` is not a type (it was added and removed again during this release; D77c).
- `tomato update` stops before a new minor or major version unless given `--minor`.
- `upper()`, `lower()`, `title()` and `capitalize()` use Python's full Unicode case mapping instead of the one-letter
  one: `'ß'.upper()` is `'SS'`, `'ßa'.title()` is `'Ssa'`, `'ΌΣΟΣ'.lower()` ends in the final sigma `'ς'`, `'ǆ'.title()`
  is `'ǅ'`, so the length of the result can differ from the text's (D17d).
- Float `//` and `%` are Python's (D87a): `3.7 // 1e-5` is `369999.0` (it was `370000.0`), and a zero remainder takes
  the divisor's sign (`6.0 % -2.0` and `2.0 ** 64 % -1.0` are `-0.0`).
- **One error class tree (D114a)**: the built-in classes `TimeoutError` and `ConnectionError` are `IOError`s, and the libraries' own timeouts and connection failures extend them. These classes have a new parent (each is still a `RuntimeError`, ids and messages are unchanged), so a `catch` of the old parent no longer handles them and a `catch` of the new one does:
  - `asyncio.TimeoutError`: was a `RuntimeError`, is a `TimeoutError` (an `IOError`): `catch IOError` now handles it too.
  - `requests.TimeoutError`: was a `requests.RequestError`, is a `TimeoutError` (an `IOError`); `requests.ConnectionError`: was a `requests.RequestError`, is a `ConnectionError` (an `IOError`). `catch requests.RequestError` no longer handles them: use `catch IOError`, or name them.
  - `socket.SocketError` and its subclasses `ConnectionRefusedError`, `ConnectionResetError` and `AddressError`: were `IOError`s, are `ConnectionError`s (still `IOError`s, so `catch IOError` and `catch SocketError` work as before).
  - `json.JSONDecodeError`, `JSONEncodeError`, `JSONTypeError`, `MsgpackError`, `toml.TOMLDecodeError` and `re.RegexError`: were `RuntimeError`s, are `ValueError`s; `cache.CacheMiss`: was a `RuntimeError`, is a `KeyError`.
  - Unchanged: the file errors (`FileNotFoundError` and the others, under `IOError`, D80a), `AssertionError` (a direct subclass of `Error`, D81a), `ProcessError` and `ProcessTimeout`, `TerminalError`, `LockError`, `StructError`, `requests.RequestError`, `InvalidURL`, `TooManyRedirects` and `HTTPError`.
- A class of a module may have the name of the class it extends (`class TimeoutError(TimeoutError)`): its parent is the built-in of that name (it ended in a stack overflow of the compiler).

### Language

- **A bare `raise` in a `catch` raises the caught error again (D114a)**: the same object, with its class, id, message, the line it was first raised on and, in debug mode, its call trace. `catch IOError as e: print('could not load'); raise`. In the innermost `catch` it is that error. Anywhere else (outside a `catch`, in the `try` body or its `finally`, in a function called from a `catch`) it is a compile error, E614.
- **`import x as y` and `from x import a as b`** (D115a): `import math as m` then `m.sqrt(2.0)` (the original name is not bound), `from math import sqrt as root, floor`. The name is the file's own, so a std module, a module of the project and a seed's module all work, and it shadows a built-in's name like any import (D108a). It was a syntax error (E335).
- **Std's module names are reserved and shadowing std warns** (D115a): `std/reserved.txt` lists the modules std has and 55 names it may add later (`http`, `log`, `bytes`, `queue`, ...). A seed cannot take one (`tomato seed check` and the manifest reader refuse a seed named `acme.example/queue`, E561); a file `json.tom` next to a program or in `src/` still replaces `std/json.tom`, now with a warning naming both (once for each name; `# allow: module-shadow` on the import line silences it); a file with a name std only keeps (`queue.tom`) is allowed and silent until std adds the module.
- **A module's own definitions shadow the built-ins** (D108a): `def len(x: int) -> int` makes `len(3)` a call of the module's `len` (it was silently ignored: the built-in `len` won and `len(3)` was E324), and the same for `print`, `open`, `range`, `zip` and `enumerate` in `for`, the error classes and every other built-in function or class, for a function, class, interface or constant the module defines and a name it brings in with `from m import name`. Only that module is affected: another module, and the standard library, still see the built-in. f-strings, `assert`, unpacking, `enumerate` and `zip` loops and comprehensions keep using the built-ins in a module that shadows them. A built-in added in a later release therefore cannot break a program that has a function of that name. The names of the built-in types (`int`, `uint`, `float`, `bool`, `str`, `File`, `list`, `dict`, `set`, `tuple`) are reserved: defining one is a compile error (E608). A constant that is called is E609. A class of a program with the name of a class of the built-ins (`range`, `ValueError`) works now (it gave a confusing error). Local variables are as before.
- **Error classes are easier to write** (D93b): a class that declares no fields inherits its parent's `@init`, so `class NotFound(Error): pass` takes `NotFound('message')` (and an optional id), and `print(e)`, `str(e)` and `f'{e}'` give an error's message alone. An uncaught error still prints its class name (`error: NotFound: message (raised on line N)`).
- **Floats of any size** (D77a-e): `float` keeps a 53-bit significand but its exponent has no limit, so nothing
  overflows or underflows (`1e300 * 1e300` is `1.0000000000000001e+600`, `float(10 ** 400)` is `1e+400`). `int` and
  `float` compare exactly. `std/math`, `round`, f-strings and the `f`/`e`/`g` formats take them. Results whose
  exponent needs more than 2^16 bits (`exp`, `expm1`, `sinh`, `cosh`, `**`) and `f` formats with more than 100,000
  digits before the point are an `OverflowError` (E528, E529; D77f); a `[limits]` table in `tomato.toml` or
  `~/.tomato/config.toml` sets both numbers (`exp_bits`, `format_digits`), and `tomato config` shows what is in effect
  (D77g). `float[length=64]` is not a type (D77c).
- **`int | None`, `float | None` and `bool | None`** (D94a) work like `str | None`: declarations, parameters, returns, fields,
  collections, generics, printing, and `d.get(key)` for a dict of any value type (it was a compile error for `int`,
  `float` and `bool` values). A `None` used as a number stops with a catchable "None where a value is needed".
- **Optionals are narrowed by assignment** (D102b): `if x is None: x = default` leaves `x` a `T` (`str`, `int`, an object ...)
  for the rest of the block, and so does any plain `x = value` of a value that is not `None`. After an `if` the variable is
  narrowed when every branch that does not leave has it narrowed (assigned a non-`None` value, or narrowed before and not
  ended): `if c: s = 'a' else: s = 'b'`, `if s is None: s = ''`, `if c: s = s + '+'` after a test. A branch that assigns `None`
  or an optional, an `if` without that branch, a loop that assigns the variable and a `try` leave it an optional as before.
  `x: T | None = value` (a declaration) does not narrow. A copy `y = x` of a narrowed variable is a `T`, so more programs
  that assign `None` to such a copy fail to compile. Also fixed: in release mode a loop nest that narrowed an `int`, `float`
  or `bool` optional between its loops could read 0 for its number after leaving the fast copy.
- **Optionals are narrowed by `is None` and `is not None`** (D102a): a local variable or parameter of type `T | None`
  (text, lists, objects, `int`, `float`, `bool` and the rest) is a `T` where a test shows it is not `None`: in the true
  branch of `x is not None`, in the `else` of `x is None`, in the right side of `and` / `or`, in a conditional
  expression, in a `while` body, and to the end of the block after `if x is None: return` (or `raise`, `break`,
  `continue`, or `assert x is not None`). So `s + '!'` and `abs(x)` need no check and cannot stop there. An assignment
  to the variable ends the narrowing; fields (`self.x`) are never narrowed. A variable copied from a narrowed one
  has the type `T`, so assigning `None` to the copy later is now a compile error.
- **Dict keys and set elements of any hashable type** (D78a): `int`, `bool`, `float`, `str`, tuples of those,
  optionals, unions, and objects of classes with an `@hash` method; the builtin `hash(x)`.
- **Bitwise `&`, `|`, `^`, `~` on integers of any size** with Python's two's-complement rules; shifts, `2 ** n` and
  single-limb division of big integers are now linear time.
- **A `File` opened in a `for` loop header is closed when the loop is left** (D82a).
- **Dotted entry markers** (D96a): every `@` entry marker marks exactly one function and may be
  dotted: `@test.parse_empty` marks one test, `tomato test FILE` runs every `@test.*`, and `tomato test FILE
  test.parse_empty` (or `tomato run FILE test.parse_empty`) runs one; `tomato run FILE greet` runs every
  `@greet.*` and `greet.loud` runs one. The same marker on two functions is an error (E583).
- **`assert`, `tomato test` and `testing`** (D81a, D97a): a file in `tests/` is one test (a program that passes when it ends with status 0); `tomato test` runs every `tests/*.tom`, each file as a process of its own, so a `sys.exit`, crash or hang ends only that file; one line for each file and a summary line for CI; `tomato test [OPTIONS] FILE ENTRY INPUTS...` (options only before the first file; every word after the file or entry is an input, even `--filter`), `--filter`, `--timeout`, `-v`; `assert_equal` shows where the first difference is in long text, lists and dicts; `assert_less` and friends; `@test` functions in one file still work. See `docs/testing.md`.
- **`@neg` and `@rmul`** (D85a): `-x` and `number * x` on objects of any class. `math.Angle` uses them (`-deg(30)` is
  `-30 deg`, `3 * deg(30)` is `90 deg`) and has an `@hash`, so angles are dict keys and set elements.
- `sum`, `min`, `max`, `sorted` and `list.sort()` take a list of objects whose class has `@add` (`sum`) or `@lt` (the
  others), so they work on lists of angles (D85b).
- `tuple[A, B]` parses in expression position; mixed tuples, lists and objects inside unions print properly.
- `set.discard(x)` compiles correctly.
- **The compatibility promise has a short list of exceptions (D109a).** `docs/provisional.md` was triaged: 58 of its 91 rows are decided, 26 removed and 7 are the *unstable list* that 1.0.x does not promise (error message wording, the edges of the type test, `!name` foreign functions, entry markers other than `@main`, the host input protocol, the text `progress_bar` draws, `random.choice`/`shuffle`/`sample`). Proposed, to be confirmed: an error id never changes its meaning, the class an operation raises does not change within a minor version, and message text may be reworded in a patch release (`docs/releasing.md`). `docs/errors.md` says how two branches that each add an error resolve the id clash.

### Faster big integers

- Multiplication uses Karatsuba, then a three-prime NTT for huge operands; division of big divisors uses
  Burnikel-Ziegler; `str(int)` and `int(text)` of long integers are divide and conquer. Big integers are divided 64
  bits at a time.

### Standard library

New modules: `asyncio` (`gather`, `wait_all`, `wait_for`, `Queue`, `Lock`, `Semaphore`, `Event`), `socket` (TCP, UDP,
asynchronous address lookup), `re` (regular expressions, D79a), `datetime` (`date`, `time`, `datetime`, `timedelta`
with fixed offsets), `csv`, `textwrap`, `statistics`, `random`, `secrets`, `uuid`, `hashlib`, `hmac`, `base64`,
`hex`, `html`, `urlparse`, `struct`, `zlib`, `utf8`, `os`, `ospath`, `io`, `sys`, `testing`. More builtins: `round`,
`divmod`, `any`, `all`, more text methods, f-string format specs (D75a-d). `Cache[K1, ..., Kn, R]` takes multi-part
keys and `memoize` handles functions of several arguments. The builtin names moved from `std/builtin.tom` into
`std/builtin/`.

`sys.run(args, ...)` starts a program (no shell) and returns its exit status and what it wrote to standard output and
error (D98a). It takes `capture`, `cwd`, `env`, `stdin`, `check` and `timeout`, raises `ProcessError` and
`ProcessTimeout`, and works natively only (the browser playground raises `RuntimeError`).
The program it starts gets only its standard streams (every other open file and socket of the parent is closed in it).
`await sys.run_async(args, ...)` is `run` that lets the other tasks go on while the program runs, and `sys.spawn(args, ...)` starts a
program and returns a `Process` with `write`, `close_stdin`, `wait`, `done`, `kill` and `stdout` / `stderr` readers (`read_line`,
`read`, `read_available`) (D98b). The debug link no longer fails on a program whose strings contain text such as `@tomato_retain(`.

`terminal` (D86a, native only): raw keys, window size and resize, colors and styles, and the width of characters, for programs that
draw on a terminal; the first part of the repl line editor. See `docs/terminal-api.md`.

`lineedit` (D88a): a line and block editor for terminal programs, with history, the keys of Python's repl and readline, and hooks
for when Enter submits, the indent of a new line and colors (`Validator`, `Indenter`, `Highlighter`). See `docs/lineedit-api.md`.

### Runtime and async

- The scheduler waits on descriptors with epoll (Linux) or kqueue (macOS), with `poll` as a fallback.
- Other tasks keep running while a program waits for input.
- Async exception and scheduling fixes; cancelling a task reaches into the call it awaits (D76b).
- Failed text-file writes are reported; clearer E318 unsupported-type errors.

### Tools

- `tomato build` and `tomato run` have a fast non-LTO debug build path, and the compiled C runtime is cached
  (`~/.cache/tomato`, `TOMATO_CACHE_DIR`, `TOMATO_CACHE=off`).
- `tomato update` (and `install-native.sh`) builds the new install beside the old one and swaps it in with one rename:
  a failure or Ctrl-C part way leaves the old install as it was, and a `tomato run` at that moment sees one whole
  install. Ctrl-C no longer leaves temporary folders behind.
- `tomato config` shows the settings in effect and the files they come from.
- `~/.tomato/config.toml` may hold `[build] mode = "release"` (or `"debug"`), the default of every build on the machine; a project's
  `[build]` and the `--mode` flag win (D99a). `tomato seed check` warns about a `[build.ENTRY]` that names no entry (`[build.mian]`).
- Clearer compile errors for unpacking a value that is not a tuple, a `Cache` key class without `@str`, a union as a
  type argument, and a byte order mark at the start of a file.
- The repl accepts a function, class or interface that is defined again (it was E120 "defined twice"): the new one replaces the old
  everywhere in the session, so earlier lines and the objects they made use it; it is refused, and the old one kept, when an earlier
  line no longer works with it. A recalled and edited `def`, or `:load` of a changed file, now just works.
- A variable declared again in the repl (`x: int = 2`) replaces the earlier declaration where it stood, as a redefined function does, so
  an earlier line that used it (`print(x)`) uses the new one (it was moved to the end, and that line failed). It may have another type;
  it is refused, and the old variable kept, when an earlier line no longer works with it (D104a).
- The parts of `datetime.replace` (`year` ... `microsecond`) are `int | None = None` (they were `int | bool = False`); leave a part
  out or pass `None` to keep it. `False` is a compile error now (D104a).
- The repl reports precise import errors; the site editor, repl and VS Code auto-indent after a colon line.
- The repl edits whole blocks (D88a, replacing D59a's `[Enter] run  [e] edit`): Up and Down recall a block as its real lines, the
  arrows move between them, Enter runs a complete piece and continues on an open bracket (`x = (1,`), paste and resize work,
  Ctrl-C cancels the input. The history file keeps its format. The installer builds the editor (`tomato-repl-edit`); without it
  the repl says so and uses plain input.
- The repl colors the code as you type it and in recalled blocks (D90a): keywords red, texts green (the brand colors), numbers, comments
  (dim), built-ins and decorators, and what is wrong underlined; 24-bit, 256, 16 or 8 colors by the terminal; `--color=auto|always|never`,
  `TOMATO_COLOR` and `NO_COLOR` decide, and with no color the repl looks as before. It is built on a tolerant mode of the compiler's own
  lexer (`lex_spans`), which also shares its scanners with `lex`.
- The repl completes names with Tab (D91a): keywords, built-ins, the names your session uses, standard modules after `import`, and
  `:commands`; several candidates are listed under the line. (Tab after other text no longer inserts four spaces; it still indents at the start of a line.)
- `std/lineedit` is finished for other programs (D91a): a single-line mode and `lineedit.read_line`, a `Completer` hook with Tab completion,
  an optional kill ring (Alt-Y), and a worked example, `examples/todo_shell.tom`.
- The bootstrap IR is compiled in parallel, so installs and builds are quicker.
- Project layout and `tomato init` (D94b, `docs/manifest.md`): code in `src/` (the program is `src/main.tom`), tests in `tests/`, what a
  build writes in `builds/` (never part of a build, left out of git by `tomato init`'s `.gitignore`, left out of a seed's hash).
  `tomato init [NAME] [--seed]` makes it; `tomato run` with no word runs `src/main.tom`; `tomato build` with no word builds it; a test in
  `tests/` imports the modules of `src/` by name. Entry inputs are raw (`*args: tuple[str]`), and an entry parameter typed `File`
  is opened for reading from its word (`-` is standard input) before the entry runs, with a message that names the input when it cannot be.
  A seed's modules may use `!name(...)` foreign declarations (nothing rejects them; `tomato seed add` lists them and asks to accept them).
- `tomato.toml` is a manifest (D95a, `docs/manifest.md`): `[project]` or `[seed]` with `name`, `version` and `tomato` (the oldest
  compiler that builds it, checked against `tomato version`), `[seeds]` and `[test-seeds]`, `[build]` and
  `[build.ENTRY]` (`mode`, `output`), `[limits]`. Unknown tables and keys are errors, so a typo is caught; a project's
  `tomato.toml` is now checked by every command. `[build]` gives `--mode` and `-o` their defaults (the flags win).
- Local seeds: `tomato seed install` locks `{ path = "../folder" }` seeds into `tomato.lock` with a sha256 content hash, and a program
  can import their modules (found between the program's folder and `std/`); `tomato seed check` and `tomato seed hash` check a seed
  and print its hash. Version seeds (a registry) are not built yet and say so.
- Seeds from git and the seed commands (D101a, `docs/manifest.md`): `{ git = "URL", rev = "COMMIT" }` seeds are fetched into a
  content-addressed store (`~/.tomato/seeds`) and locked with their hash; `tomato seed add --path DIR | --git URL --rev COMMIT [--test]`
  lists a seed and locks it, `tomato seed remove NAME` drops it, `tomato seed vendor` copies the locked seeds into `vendor/`, and
  `install`, `add` and `vendor` take `--offline` (never run git). `seed add` lists the `!name(...)` foreign symbols a seed declares
  and asks to accept them (`--yes` does not ask).

### Performance

Generated code and the runtime are faster on floats, fields, text indexing, list loops and function values; for loops
borrow their item when the body cannot change the list; float loop nests get a fast copy. 15 more benchmark programs
and eight more comparison languages; Linux x86-64 results are published next to the Mac ones (see
`docs/performance.md`).

### Fixes

- `@str` is found through the object's own class: a subclass's `@str` under another name is used when the value is typed as the
  parent (`class Own(Error)` with `@str def show`, then `catch Error as e: print(e)` printed the message alone, not `own:x`), as
  `print`, `str()`, f-strings and printed lists all do now (D111a).
- `(t * 2) + o.n * 3` with `o: Box | None` was the error "the class 'Box?' does not exist"; it compiles, and a `None` stops the
  program with "None where a value is needed", as `t + o.n` does (D111a).
- Clearer errors for optionals and unions: a field that can be None in `+` says fields are not narrowed and to copy it to a variable;
  `[1, None]` says how to write `list[int | None]`; the errors for `int | str | None`, `int | None | None` (new E610) and `x: None` point at
  the type; `module.f()` for a function that is not `export`ed says so (E225) instead of "not defined" (D111a).
- In release mode, a loop nest that narrowed a union with `x in T` (`if k in str: continue` between the loops, then a use of `k`
  as an `int`, `float`, text or object) could read an empty slot for the member after the fast copy handed over to the general
  copy: a 0 for a number, a wrong float, a null text. Debug mode was right. The slot is filled again where the other copy comes
  in, as it already was for narrowed optionals (D106a).
- `t += a` (and `-=`, `*=`, and `t = a + t`, `t = 2 * t + a`, ...) with a big `t` and an `a` of type `int | None` that is `None`
  inside a `try` freed `t`'s number while `t` still held it (a use after free). A statement hands the old number of the variable
  to the operation only when every other variable it reads is an `int` or a fixed-width integer (D106a).
- `tomato init 'a\b'` writes the name as `a\\b` in tomato.toml (the backslash was lost, and `\b` read as a backspace). `tomato config` with a wrong settings
  file prints only the error. `tomato seed install --locked` says when the files of a path seed changed since the lock (the seed and both hashes).
  `--mode ""` is an error (E282) in `run`, `build` and `compile`.
- Fetching a seed from git keeps a bare clone for each repository in `~/.tomato/seeds/git/` (a cache, safe to delete): a second fetch adds only new
  objects, and a commit already there needs no network (D104a).
- Converting an `int` to `int[length=64]` used to give a wrong number (`int[length=64](5)` printed `11`, and a value
  beyond the range was not caught); it now checks the range and raises `OverflowError`, and passing an `int` where an
  `int[length=64]` is expected is a compile error, as it already was for the narrower widths. `int[length=64]` mixed
  with `int` is now `int` arithmetic (`x + 10 ** 20` is exact).
- `%` of a fixed-width integer's least value by `-1` (`int[length=8]`: `-128 % -1`) gave garbage; it is `0`.
- `tomato build FILE` of a file without the `.tom` suffix (or with `-o` naming the source) overwrote the source with
  the program; it now refuses.
- The repl links its pieces with `-pthread` (and `-ldl` on Linux) like `tomato run`, so it works with older glibc.
- `sin`, `cos` and `tan` of a radian angle lost digits: `sin(rad(10.0))` was 14 units in the last place off and
  `sin(rad(1e10))` right to only 6 digits; they are now the C library's answer (D83a).
- `sin`, `cos` and `tan` of a large angle in degrees, turns or gradians lost digits (`sin(deg(1e22))` was `0.0`, it is now
  `sin(deg(280))`; next to a quarter turn `cos(deg(89.99999999999999))` was 30% off), and of a radian angle beyond a double's range gave a made-up `0.0`; that is now an `OverflowError`.
- Unpacking a dict or a set (`a, b = d`) compiled and read `d[0]` and `d[1]`; it is a compile error now. A class with two
  methods marked with the same operator marker (two `@add`) is a compile error (the second was silently ignored).
- A program that leaves a terminal in raw mode and then fails prints its error after the terminal is restored; two
  `Terminal`s on one device no longer leave it raw, whichever is left first.
- `tomato build a.tom x -o` (an option with its value missing at the end) took an earlier word as the value and wrote `x`;
  it is a usage error. `tomato update` refuses to run from a source checkout.
- `set.discard(x)` compiled wrongly; async exceptions and scheduling had several bugs; `wasi.js` `path_rename`
  lost file times under renamed folders; regex `{m,n}` repeats around empty-matching groups now match Python.
- `progress_bar` opened `/dev/stderr` for each redraw and ended the program with `could not open '/dev/stderr'` where that path
  is not there (in the repl on macOS, with standard error closed); it writes through the standard error stream now (D105a).
- `tomato.toml` and `config.toml` mistakes (E555 to E560, E565, E568, E590, E562) name the line of the key (`tomato.toml:6: build.mode must be ...`); a bad
  `[build] mode` in your own `config.toml` is reported even when `--mode` or the project's `[build]` decides the mode. An option with its value missing
  at the end (`tomato build -o`, `tomato test --filter`, `tomato seed remove`) is a one-line usage error (status 2), not the whole help.
  `tomato test` with no word finds the project's `tests/` from a folder below it, as `run` and `build` find `src/main.tom`. `tomato init ../x` is
  refused and `tomato init -- -x` makes a project named `-x`. `[seed-store] vendor` of `.`, `src`, `tests`, `builds` or `""` is refused (E604), and a file
  there is an error that says so. A `!name(...)` symbol added to a locked path seed is asked about by the next build (E602, accepted by `tomato seed
  install`); a module `src/X.tom` (or next to the program) with the name of a seed's module is a compile error (E607), as a clash with `std/` is (E581).
  `tomato seed check` warns about the `TODO:` placeholders and the `yourdomain.example` owner of `tomato init --seed`, and `tomato seed install` fetches a
  seed again when its store copy was damaged (a build still says E601, and the message now says to run `install`) (D107a).
- `itertools`: `combinations`, `combinations_with_replacement`, `product_repeat` and `repeat` with a negative count, and `permutations` with an `r`
  below -1 (-1 still means all), raise `ValueError` (E39), as `batched` does; a `break` or `return` out of `for x in progress_bar(...)` ends the bar's line
  on a terminal; `sys.run` of a script whose `#!` interpreter is missing says `its interpreter '/x/y' was not found` (D107a).
- A big number as an `int | None` or `float | None` dict key, set element or `hash()` argument (`d[10 ** 40] = 1` on a
  `dict[int | None, int]`) was freed twice and crashed the program; it works now.
- `await p.wait()` on a `sys.spawn` program that wrote more than a pipe holds (about 64 KB) before anything read it waited
  forever; `wait()` (and `done()`) now take what the program wrote as they wait.
- `tomato test --timeout` stopped a test that ran too long but not the programs it had started with `sys.run` or `sys.spawn`;
  they are stopped too. A test reads no input: its standard input is empty, with or without `--timeout` (before, without it a test
  that asked for input waited on the terminal).
- A big number given to an entry input that has a default (`tomato run f.tom main 99999999999999999999999` for `main(n: int = 3)`)
  printed `warning: 1 big number(s) were never freed`.
- `@greet . loud` (spaces around the dot) was taken as `@greet.loud`; a dotted entry marker is one word (E335 otherwise).

### Known issues

See `TODO.md`, and `docs/language-design-review.md` for the language questions still open before 1.0.
