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

### Language

- **Floats of any size** (D77a-e): `float` keeps a 53-bit significand but its exponent has no limit, so nothing
  overflows or underflows (`1e300 * 1e300` is `1.0000000000000001e+600`, `float(10 ** 400)` is `1e+400`). `int` and
  `float` compare exactly. `std/math`, `round`, f-strings and the `f`/`e`/`g` formats take them. Results whose
  exponent needs more than 2^16 bits (`exp`, `expm1`, `sinh`, `cosh`, `**`) and `f` formats with more than 100,000
  digits before the point are an `OverflowError` (E528, E529; D77f). `float[length=64]` is not a type (D77c).
- **Dict keys and set elements of any hashable type** (D78a): `int`, `bool`, `float`, `str`, tuples of those,
  optionals, unions, and objects of classes with an `@hash` method; the builtin `hash(x)`.
- **Bitwise `&`, `|`, `^`, `~` on integers of any size** with Python's two's-complement rules; shifts, `2 ** n` and
  single-limb division of big integers are now linear time.
- **A `File` opened in a `for` loop header is closed when the loop is left** (D82a).
- **`assert` and `@test`** with `tomato test` (D81a).
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

### Runtime and async

- The scheduler waits on descriptors with epoll (Linux) or kqueue (macOS), with `poll` as a fallback.
- Other tasks keep running while a program waits for input.
- Async exception and scheduling fixes; cancelling a task reaches into the call it awaits (D76b).
- Failed text-file writes are reported; clearer E318 unsupported-type errors.

### Tools

- `tomato build` and `tomato run` have a fast non-LTO debug build path, and the compiled C runtime is cached
  (`~/.cache/tomato`, `TOMATO_CACHE_DIR`, `TOMATO_CACHE=off`).
- The repl reports precise import errors; the site editor, repl and VS Code auto-indent after a colon line.
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
- `set.discard(x)` compiled wrongly; async exceptions and scheduling had several bugs; `wasi.js` `path_rename`
  lost file times under renamed folders; regex `{m,n}` repeats around empty-matching groups now match Python.

### Known issues

See `TODO.md`: float `//` and `%` differ from Python in rare cases; a few compile errors point at the wrong place.
