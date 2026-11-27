# Changelog

What changed in each release, for people who use Tomato. The GitHub release page also lists every merged commit
(`release/release.sh` creates it with `--generate-notes`); this file is the short, readable version. Decision numbers
(D78a and so on) point into `docs/decisions.md`.

From 1.0.0 on, all releases of one minor version (1.0.0, 1.0.1, ...) are compatible with each other: a program that
works on one works the same on the others (except the placeholders in `docs/provisional.md`). A new minor version
(1.1.0) may change behaviour, and its section lists each such change under **Breaking changes**; a patch release has
none. `tomato update` installs patch releases at once and a new minor version only with `tomato update --minor`.

## 1.0.0 (draft, not released yet)

Everything since v0.51 (2026-11-23). From this release on, versions are MAJOR.MINOR.PATCH (the releases before were
numbered 0.1 to 0.51), with pre-releases such as 1.1.0-rc.1 that only `tomato update --pre` installs; `tomato update`
on an older install moves to 1.0.0 as usual.

### Breaking changes

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

### Language

- **Error classes are easier to write** (D93b): a class that declares no fields inherits its parent's `@init`, so `class NotFound(Error): pass` takes `NotFound('message')` (and an optional id), and `print(e)`, `str(e)` and `f'{e}'` give an error's message alone. An uncaught error still prints its class name (`error: NotFound: message (raised on line N)`).
- **Floats of any size** (D77a-e): `float` keeps a 53-bit significand but its exponent has no limit, so nothing
  overflows or underflows (`1e300 * 1e300` is `1.0000000000000001e+600`, `float(10 ** 400)` is `1e+400`). `int` and
  `float` compare exactly. `std/math`, `round`, f-strings and the `f`/`e`/`g` formats take them. Results whose
  exponent needs more than 2^16 bits (`exp`, `expm1`, `sinh`, `cosh`, `**`) and `f` formats with more than 100,000
  digits before the point are an `OverflowError` (E528, E529; D77f); a `[limits]` table in `tomato.toml` or
  `~/.tomato/config.toml` sets both numbers (`exp_bits`, `format_digits`), and `tomato config` shows what is in effect
  (D77g). `float[length=64]` is not a type (D77c).
- **Dict keys and set elements of any hashable type** (D78a): `int`, `bool`, `float`, `str`, tuples of those,
  optionals, unions, and objects of classes with an `@hash` method; the builtin `hash(x)`.
- **Bitwise `&`, `|`, `^`, `~` on integers of any size** with Python's two's-complement rules; shifts, `2 ** n` and
  single-limb division of big integers are now linear time.
- **A `File` opened in a `for` loop header is closed when the loop is left** (D82a).
- **`assert` and `@test`** with `tomato test` (D81a).
- **`@neg` and `@rmul`** (D85a): `-x` and `number * x` on objects of any class. `math.Angle` uses them (`-deg(30)` is
  `-30 deg`, `3 * deg(30)` is `90 deg`) and has an `@hash`, so angles are dict keys and set elements.
- `sum`, `min`, `max`, `sorted` and `list.sort()` take a list of objects whose class has `@add` (`sum`) or `@lt` (the
  others), so they work on lists of angles (D85b).
- `tuple[A, B]` parses in expression position; mixed tuples, lists and objects inside unions print properly.
- `set.discard(x)` compiles correctly.

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
- Clearer compile errors for unpacking a value that is not a tuple, a `Cache` key class without `@str`, a union as a
  type argument, and a byte order mark at the start of a file.
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

### Performance

Generated code and the runtime are faster on floats, fields, text indexing, list loops and function values; for loops
borrow their item when the body cannot change the list; float loop nests get a fast copy. 15 more benchmark programs
and eight more comparison languages; Linux x86-64 results are published next to the Mac ones (see
`docs/performance.md`).

### Fixes

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

### Known issues

See `TODO.md`, and `docs/language-design-review.md` for the language questions still open before 1.0.
