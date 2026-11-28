# Fourth pre-1.0 audit: the work since the third audit

Date: 2026-11-27. Base: `main` at `0b88de9d`, merged again with `333b6c15` (bytearray, D128a) and `bf6dbb59` (the deprecation and U5/U6 warnings) during the
audit; every finding below was reproduced again by the lead on `bf6dbb59`. The bar is Davis's for 1.0: "polished and good". The earlier audits are
`docs/language-design-review.md`, the second audit (`6f94caa6`, `2cd11515`) and `docs/third-audit.md`. This one looks only at what
landed after the third audit (`e3dff677`): 30 commits, about 14,000 lines, and repeats nothing those audits already covered.

## How it was done

Eight auditors, one area each, with the same brief: install `tomato` from `main` with `./install-native.sh` into a temporary
`TOMATO_HOME`, **write and run real programs** (small tools in the area's domain, not code reading), in debug, `--mode release`, an
AddressSanitizer build (`tomato compile` then `clang -fsanitize=address` with `runtime/tomato_rt.c`) and the WebAssembly path the
website runs (`native/tomato-jsc.js` under node), and report only what they reproduced, each with a minimal repro. They edited no
files. The lead re-ran every reported repro on current `main` before recording it, merged findings with one cause, and dropped what
the earlier audits already record. The lead also installed `tomato` on Davis's Mac in `/tmp/tomato-audit4` (its `/bin/sh` is bash
3.2) and ran the first-hour flow, a path seed, `tomato test --timeout` and the repl's pty tests there; nothing else on the Mac was
touched.

| Area | What was run |
| --- | --- |
| A: `bytes` and the binary std | a BMP writer and parser, a hexdump, sha256 against `sha256sum`, base64/hex/`fromhex` over all 256 values, length-prefixed records, a 512 KB TCP echo, UDP, `requests` against a local server, msgpack, uuid, secrets; 300 invalid UTF-8 vectors and 120 random method cases against Python 3 |
| B: errors, `@str`, type tests, narrowing | an error hierarchy with fields and `@init`, a retry loop with bare `raise`, bare `raise` across `await`/`gather`/`wait_for`, a shape hierarchy with an interface, an expression evaluator over a union AST, `x is T`/`x is Class`, `elif` narrowing (D127a), optional interfaces (D118a) |
| C: names, std freeze, `value` | `import x as y`, `from x import a as b`, reserved module names, shadowing builtins (D108a, D125a), reserved markers, `!tomato_*`, `math.abs` and friends, a JSON+TOML config merger over `value` with about 70 malformed inputs, the unstable warning |
| D: the first hour, manifest, seeds, shell | README and guide steps as written, `init/run/build/test/config/explain`, `[build]`, a path seed (`seed add/install/check/hash/verify/vendor/remove`), host shortcuts and their bad forms (no network), the `# seeds:` line, ShellCheck and bash-4 constructs in `native/` and `install-native.sh` |
| E: every docs example | an extractor over README, `site/guide.html`, the specification, `docs/testing.md`, `docs/manifest.md`, `docs/errors.md`, `docs/binary-helpers.md` and `site/examples.json`: 33 programs and 30 command blocks, native and wasm; `site/docs` and `site/wasm/std` against their sources |
| F: repl and playground | piped and pty repl sessions (definitions, redefinitions, errors mid-session, imports, top-level `await`, `:load`/`:save`/`:program`, Ctrl-C, Ctrl-D), the 13 playground examples and two larger programs through the wasm path against native, the page repl's session logic |
| G: OS tools | grep/wc/log-rotator tools with `File` inputs, `sys.run`/`run_async`/`spawn` (2 MB stdin, 3 MB output, timeouts, signals), async with tasks and cancellation, a multi-entry CLI built with `tomato build` |
| H: `bytearray` (merged mid-audit) | a binary file writer read back with `struct`, a ring buffer, an XOR cipher, framing, a 20,000-step random differential test against `list[int]`, aliasing through fields, dicts and generics, 10 MB of appends |

## Blockers for 1.0

**1. On macOS `tomato repl` cannot touch files, the environment or processes (repl, L1).** On a Mac `native/tomato-repl` runs
every session through JavaScriptCore and the website's WebAssembly build (`fast=2`, line 44, chosen whenever `jsc` exists), which has
only an in-memory file system and no processes. Repro (piped or typed, on the Mac):

```
f = open('/tmp/x.txt', 'w')        error[E25]: could not open '/tmp/x.txt': No such file or directory
import os
os.listdir('/tmp')                 error[E505]: FileNotFoundError: could not list the directory '/tmp'
os.getenv('HOME')                  None
import sys
sys.run(['echo', 'x'])             error[E514]: RuntimeError: run is not available in the browser playground (it cannot start a process)
```

Expected: the same as on Linux (the file written, the listing, `/Users/...`, `x`); with `TOMATO_JSC=/nonexistent tomato repl` (the
native path) `sys.run` works on the Mac. A `progress_bar` never draws in the Mac repl either, so
`tests/repl_progress.exp` fails on macOS (`FAIL: timed out waiting for the finished bar on the terminal`; it passes on Linux, where
there is no `jsc`). macOS is the main platform, and a user's first repl session there hits this as soon as it reads a file.

**2. Using the value of a function that returns nothing gives a raw clang error (compiler, D1).**

```
def nothing(xs: list[int]):
    xs.append(1)

@main
def main():
    print(nothing([1, 2]))
```

Observed: `.../program.ll:12055:38: error: expected value token` / `call void @tomato_print_strobj(ptr )`. `str(f())` and `f"{f()}"`
fail the same way (`trunc i64  to i32`); `f() + 1` is `E190: cannot use '+' with  and int` (an empty type name). `x = f()` and
`[f()]` are rejected properly. Expected: a Tomato error with a caret, such as "'nothing' returns no value".

**3. Printing an interface-typed value prints nothing, or gives a raw clang error (`@str` dispatch, optional interfaces; B1).**

```
interface Named:
    def name(self) -> str
class Tag implements Named:
    def name(self) -> str:
        return 'tag'
    @str
    def s(self) -> str:
        return 'TAG'
def shown(n: Named):
    print(n)                 # prints an empty line
@main
def main():
    shown(Tag())
    m: Named | None = Tag()
    print(f'[{m}]')          # program.ll: error: '%l.7' defined with type 'ptr' but expected 'i64'
```

`print(n)` with `n: Named | int` prints `<object>`. The wasm path fails with a BigInt error. Expected: the object's `@str` (`TAG`),
as D111a does for a class-typed value, or the class's default text.

**4. A `catch` variable read after its `try` is a segmentation fault (errors, B3).**

```
@main
def main():
    try:
        print('no error here')
    catch ValueError as e:
        pass
    print(e.message)
```

Observed: `Segmentation fault` in debug and release, no error and no warning. Expected: a compile error (the name is the catch
block's), or at least the "might not have a value" warning that a variable assigned only under an `if` gets. A program in the safe
subset must not crash this way.

**5. `bytearray`'s storage is public, so ordinary code can write past its buffer (bytearray, H2).**

```
@main
def main():
    a = bytearray(b'abc')
    a.n = 100000
    a[99999] = 7
    print(a[99999])
```

Observed: AddressSanitizer `heap-buffer-overflow ... WRITE of size 1`; the plain debug build writes out of bounds silently and only
the read fails (`E04 index out of range at bytearray.at`). `a.n = 99; print(a)` reads past the buffer. `buf`, `n`, `_room`,
`_to_bytes` and an undocumented `text()` are all public in `std/builtin/bytearray.tom`. Expected: they are `private` (D12q), so no
user program can reach them.

## Should fix

**6. Output to a full or failing stdout is lost with exit status 0 (runtime, G7).** A program that prints 1,000 lines, run as
`./prog > /dev/full`, exits 0 and says nothing. Expected: an `IOError` (or at least a message and a non-zero status at exit), as
Python does (`OSError: [Errno 28] No space left on device`). `| head` gives 141 (SIGPIPE), which is fine.

**7. `text.split()` with no argument does not exist, and `split('')` fails at run time (std, G4).** `"a b".split()` is
`E128: 'split' takes 1 argument, but 0 given` with no help; `'a  b'.split('')` is `E15 an empty text cannot be used to split` at run
time; only `rsplit('')` splits on whitespace (D75b). Every Python user's word count or grep writes `line.split()` first. Expected:
`split()` (and `split(None)` or `''`) splits on runs of whitespace, as `rsplit('')` does, or at least a help line naming the spelling.

**8. An import alias named like a built-in type is accepted and ignored (names, C2).** `from math import sqrt as int` then
`print(int(4.0))` prints `4` (the built-in), with no error; `import math as str`, `as int` and `as None` are accepted too. Expected:
the E623/E608 error that a variable or definition with that name gets (D108a, D125a: the names of the built-in types stay reserved).

**9. `toml.dumps` writes documents `toml.loads` rejects (value, C4).** `toml.dumps(json.loads('{"big": 123456789012345678901234567890,
"huge": 1e999}'))` writes `big = 1234...890` and `huge = 1e+999`; reading it back is
`E356 TOMLDecodeError: Integer is out of the 64-bit range: line 1 column 7`. Expected: `dumps` raises `ValueError` for what TOML
cannot hold, as it does for a null (D122a).

**10. Printing a list or dict of optional objects is a compile error with no location (B2).**
`xs: list[Animal | None] = [Animal(), None]` then `print(xs)` is `error[E339]: the class 'Animal?' does not exist` /
`= help: ... import it with 'from module import Animal?'`, with no `-->` line. A `list[int | None]` prints. Expected: `[a, None]`.
(D111a fixed the same `Box?` name only in arithmetic.)

**11. A union type test does not narrow on the right of `and` (narrowing, B4).** `def f(x: int | str)` with
`if x is int and x > 0:` is `E190: cannot use '>' with int | str and int`; `if x is int and y is int: return x + y` fails the same way.
The same shape with optionals and with classes (`a is Dog and b is Dog`) narrows (D102a, D110a). Expected: the same rule for unions.

**12. `bytes` is not `Sized` or `Iterable[int]` (bytes, A4).** `def n(s: Sized) -> int` called with `b'abc'` is
`E324 ... has type bytes, but Sized is expected`; likewise `Iterable[int]`. `str`, `list`, `tuple`, `set` and `dict` are (D57a), and
`len(b)` and `for x in b` work. Expected: accepted (and `bytearray` too), or D17e says why not.

**13. A `bytearray` changed while a `for` loop goes through it reads stale bytes (bytearray, H3).** `for x in a: t += x; a.pop()` over
`bytearray(b'abcd')` visits all four original bytes (`t` is 394); with `a.clear()` in the loop it is `E04 index out of range`, traced
into `std/builtin/bytearray.tom`. `each` loops over `range(self.n)` fixed at the start. Expected: stop at the current length, as a
`list` does (the loop warning already fires).

**14. `ba += x` copies the whole `bytearray` each time (bytearray, H4).** 300,000 `ba += b'a'` take 6 s in release (10 million
`append`s take 0.17 s), and after `alias = ba` the alias stays empty. D128a documents `+=` as `a = a + x`, but it is the first thing a
Python user writes for a buffer. Expected: `+=` extends in place, or a warning or help that points at `extend`.

**15. Text where bytes are wanted gets no hint, which D17e promises (bytes, A2, H1).** `b'a' + 'a'` is
`E190 cannot use '+' with bytes and str` with no help, while D17e says it "is a compile error with a hint" (`==`, `<` and `*` do have
one). `hashlib.sha256_hex('abc')`, `'a' in b'abc'` (E635) and `os.write_bytes(p, ba)` with a bytearray (E324, the type written
`bytearray.bytearray`) have none either; `{ba: 1}` and `hash(ba)` suggest adding an `@hash` method to a type that can change.
Expected: `= help: encode it: s.encode()` / `convert it: bytes(ba)` / "a bytearray can change, so it cannot be a key".

**16. `struct.Reader` and `struct.unpack_ints` raise different classes for the same short input (std, A9).** `struct.unpack_ints('>I', b'\x01')` raises
`StructError`, but `struct.Reader(b'a').read_u32()` raises a plain `ValueError` (E499), so `catch struct.StructError` misses it;
`docs/binary-helpers.md` names `StructError` for `pack`/`unpack` and no class for `Reader`. The error classes are part of the 1.x
promise (D117a), so this freezes. Expected: one class for both, and the docs say which.

**17. The `# seeds:` line is an error in the playground (seeds, D3).** Any program with `# seeds: me/lib` run through the wasm path
gives `E622: /program.tom: the "# seeds:" line names me/lib, but there is no tomato.toml ...` and `~rc 1`. `docs/manifest.md` (line
231) says "the line is a plain comment to the browser". Expected: ignored in the browser, as documented.

**18. Errors raised inside the standard library show std line numbers and no file (errors, G5, A8).** `os.listdir('/nope')`
uncaught prints `(raised on line 48)`, `at _raise (line 48)`, `at listdir (line 130)`, `at main (line 4)`; `bytes([1, 256])` says
`raised on line 130` / `at _bytes_of_list (line 130)`; `toml.loads` shows seven `_Parser` frames. In release only `(line 48)` is
left, a line of `std/os.tom`, so the one location shown is not the user's. Expected: the user's line in the first line (the frame
that called into std), std frames marked with their module (as `tomato test` writes `testing.NAME`) or left out.

**19. Diagnostics of a `catch` clause point at the `try` or `def` line (errors, C1, G9, A10, B9).** `catch ValueError as len` warns
at `3:1 def main():`; `catch ValueError as dict` (E623), `catch ProcessError` without the import and `catch Foo` with a class that is
no error (E98) put the caret on `try:`. The E98 for an unimported name also says "'ProcessError' is not one" instead of "not defined:
write sys.ProcessError or from sys import ProcessError". Expected: the caret on the catch clause, and the not-defined wording.

**20. A wrong argument's caret is on the first call of that function in the line (compiler, C3).** `print(f(3), f([1]))` with
`def f(x: int)` puts the E324 caret at column 11 (the first `f`). Expected: column 17. The same happens for a user-defined `len`, and
`print(1 in [1,2], a in [a])` puts E101 under the first `in` (B9).

**21. Value errors underline the whole statement, trailing comment included (compiler, A1, B5, F8, L3).** `print(1, bytes('abc'))`
underlines all of `print(...)` (E630, E632, E633, E428 too); `y: int = 'a'` underlines the whole line rather than `'a'`;
`return x   # comment` underlines the comment; `print("a", statistics.mean([1, 2, 3, 4]), "b")` and `sorted(d)` of a dict (E331)
underline all of `print(...)` (F8). Expected: the caret under the expression at fault, as call-argument E324 does.

**22. Entry-input errors give no usage (CLI, G2, D6).** For `@stats def stats(count: int, ratio: float, label: str = 'x')` in a built
program: `./g12 stats` is `E352: the entry point takes 3 input(s), got 0` (two are required), `./g12 stats 1 abc` is
`E351: input 2 must be a number, found 'abc'`, and there is no `--help` (`./g12 -h` is E591; `stats 1 2 --help` runs with the label
`--help`). Expected: the parameter's name and a usage line such as `usage: g12 stats COUNT RATIO [LABEL]`, and the count of required
inputs.

**23. E157 has no location and the wrong wording (CLI, G3, A6).** `@wcs def wcs(*files: tuple[File])`, `def main(arg: bytes)` and a
`list[int]` input all give `error[E157]: a program input (a parameter of the @main function) must be an int, bool or str` with no
`-->` line, though the entry is `@wcs` and `float` and `File` inputs are allowed (D94b). Expected: the parameter's location and the
real list. (A rest parameter of `File`s cannot be had at all, so a `wc a b c` tool cannot be written.)

**24. Docs that contradict behaviour (docs, E1, C6, A5, E4).**
- `site/guide.html` lines 245 to 256, the TOML example: `from toml import ... integer` and `doc['server'].put('port', integer(9090))`
  are gone (`E226: module 'toml' has no 'integer'`); the prose above it gives the working spelling
  (`doc['server'].as_dict()['port'] = Int(9090)`, `from value import Int`), which prints `demo 8080 2` and the rest.
- `site/guide.html`, the JSON paragraph: "`1e999` is an error, not infinity", but `json.loads('1e999')` gives a float that prints
  `1e+999` (as `std/json.tom` says); the requests paragraph still says "a `Json` value" and "`r.json()` will come with the JSON
  library" (`Json` is gone, D122a, and `r.json()` exists).
- `docs/specification.md` line 87 (D69a) still says binary data is a `list[int]`; line 391 (D80a) says a `write_bytes` value outside
  0 to 255 is a `ValueError`, which cannot happen with `bytes`. D17e and the TODO say `b'-'.join([])` needs a typed list; it compiles.
- `README.md` lines 32 to 35: right after `tomato init`, `tomato run greet bob` and `builds/hello greet bob`; the new project has
  only `main`, so both are `E228: no function is marked @greet`.

**25. Ctrl-C while a piece runs ends the whole repl session (repl, F3).** Typing `while True:` / `    pass` and then Ctrl-C exits
`tomato repl` (status 130) and the session is lost: `native/tomato-repl` has `trap 'exit 130' INT`. A newcomer's first endless loop
costs them everything typed. Expected: stop only the running piece and return to the prompt (Ctrl-C while typing already cancels the
line, as `:help` says).

**26. The website's repl cannot redefine a function, and its errors point at lines nobody typed (playground, F6).**
`site/play.html` appends every definition to `defs` (line 152) and never replaces one, so a second `def f` is
`E120 'f' is defined twice`, reported at a line of the generated session program; a one-line piece's compile error is reported as
`program.tom:11:9`. The installed repl replaces a redefinition (D104a) and maps errors to the typed piece. Expected: the same
behaviour in both. (Checked by running the page's session logic through node, not by clicking in a browser.)

## Polish

| Id | Area | What | Repro / observed |
| --- | --- | --- | --- |
| P1 (D2) | seeds | `tomato seed remove sd` refuses the short name `import sd` uses and does not list the real names | `E604: ... sd is not in [seeds] or [test-seeds]` (only `yourname/sd` works) |
| P2 (D4) | manifest | `[build.nope]` (no such entry) is accepted silently; `tomato config` does not show `[build.ENTRY]`; a configured output prints an absolute path, the default `builds/NAME` | `printf '[build.nope]\nmode = "release"\n' >> tomato.toml; tomato build` |
| P3 (D5, L2) | seeds | seed messages print long absolute paths; errors about a command-line word are prefixed with `.../tomato.toml:`; E622 for a version below the lock names `tomato.toml` though the line is in `src/h.tom`; `# seeds: me/lib, me/lib` is accepted | `tomato seed add gh:` gives `E621 /abs/tomato.toml: "gh:" is not a host shortcut` |
| P4 (D7) | test | `tomato test --filter nomatch` warns, prints `0 files ... ok` and exits 0 (a typo in CI passes); "1 files" | |
| P5 (D8) | manifest | invalid `tomato.toml` is one E540 line (absolute path, parser text, column) with no source line or caret, repeated once per test file by `tomato test` | `printf '[project\nname=1\n' > tomato.toml; tomato run` |
| P6 (D9, G1) | build | a failed `tomato build` leaves the old `builds/NAME`; `-o nodir/a` with a missing folder is a raw `ld` error | `tomato build a.tom -o nodir/a`: `cannot open output file nodir/a` |
| P7 (G6) | std | `os.write_text` and `open()` failures carry E25 for every class, while `read_bytes` and `listdir` carry E505 to E509 | `catch FileNotFoundError as e: print(e.id)` gives E25 |
| P8 (G8) | std | an `int` where a `float` is wanted has no help (`write 5.0`); `sys.run(timeout=5)` is refused while `asyncio.wait_for` takes `int \| float` | `E324 argument 'timeout' of 'run' has type int, but float \| None is expected` |
| P9 (G10) | docs | the guide has no word on `sys.run`, `run_async`, `spawn` or `Process`; there is no way to capture a child's binary output | |
| P10 (C5) | names | a local that shadows a name, used before its assignment: E227 "name 'value' is not defined" for a module, E340 for `enumerate`, the builtin silently for `len` | `print(value.Str("x"))` then `value = 1` |
| P11 (C7, C8) | value | `j["a"][0] + 1` (E189) and `for x in j` (E377) say nothing about `.as_int()` / `.as_list()`; `ValueTypeError` names no key; `x is Int` without the import suggests `int` | |
| P12 (C9) | CLI | errors in a project module print `lib.tom:2:5`, the entry `src/main.tom:...` | |
| P13 (C10) | names | `from math import sqrt, sqrt` is E120 "defined twice in module 'main'" (caret on the first), `import json` twice is E616 (caret on the second) | |
| P14 (A3) | bytes | `'é'.encode('ascii', 'ignore')`: the help for an unknown error mode speaks of U+FFFD (decode's wording) | `E626: unknown error mode 'ignore' / use 'strict' ... or 'replace' (put U+FFFD ...)` |
| P15 (A7) | bytes | `bytes(range(4))` is E632 with no hint of `bytes(list(range(4)))` | |
| P16 (B5) | errors | an unreachable `catch` (after `catch Error`, or a duplicate) is accepted with no warning | |
| P17 (B6) | errors | `catch A, B as e` and `catch (A, B)` give `E335 expected ':', but found ','` with no help (no multi-catch; one clause each or the parent) | |
| P18 (B7) | errors | an id like `'E1'`, `'MYID'` or `'e77'` given to `Error(...)` is dropped from the uncaught output (and shown as E11 in release) | `raise Error('words', 'MYID')` |
| P19 (B10) | type tests | `y is Named` with `y: Shape` (a class) does not narrow (the D110a default) and E115 says only "'Shape' has no method 'name'" | |
| P20 (B11) | errors | an uncaught error with an empty message prints `error: Silent:  (raised on line 6)` (dangling colon, two spaces) | `class Silent(Error)` / `raise Silent()` |
| P21 (H5) | bytearray | after `import bytearray`, a field `data: bytearray` is `E300 this field type is not supported` (the module name wins, D128a, but the message does not say so) | |
| P22 (L4) | repl | after a class definition that failed, `A(3)` is E340 with `= help: did you mean 'v'?` | |
| P23 (F1) | repl | piped input does not continue an open bracket: `a = [1, 2,` then `3]` is E137 then E335 and `a` is undefined (the pty editor joins them; `:help` says an open bracket goes on) | `printf 'a = [1, 2,\n3]\na\n' \| tomato repl` |
| P24 (F2, F4) | repl | defining `print` re-shows an earlier echo (`1 + 2`, `print("hi")`, `def print(s: str): pass`, `7` gives `3 hi 3 7`); a refused redefinition shows `--> session:1:13` / `_core_print(g(1))`, and `:program` prints `_core_print(...)`, code the user never typed | |
| P25 (F5) | repl | `:save /root/x/y.tom` prints `tomato-repl: line 381: /root/x/y.tom: Permission denied` (raw bash) | |
| P26 (F7) | repl | `x = 4` then `x: str = "now str"` is E292, while `y: int = 1` then `y: str = "s"` replaces `y` (D104a says a variable declared again with any type replaces the old one) | |
| P27 (F9) | runtime | `error[E04]: index out of range` gives neither the index nor the length | `xs = [1, 2, 3]; xs[10]` |

## Not counted

- The built program takes `[ENTRY [INPUTS...]]`, so a one-entry program runs as `./prog main 30` (D94b, deliberate; E591 shows the
  form). `tomato init NAME` writes into the current folder, as its help says.
- `sys.run` reports a timeout when a backgrounded grandchild keeps the pipe open (third audit, "not counted"); the "killed" wording
  of that message is part of it.
- The wasm harness `native/tomato-jsc.js` does not print compiler warnings; the website shows them (`site/wasm/tomato.js` reads the
  `;!` lines), and the repl never shows warnings (`docs/errors.md`).
- `bytearray(2**62)` is an uncatchable E349 (out of memory), as a huge `list` is.
- The open items the third audit and `TODO.md` already carry: the E324 help for `value.Value`, the `# seeds:` line outside a
  project, the repl's O2 replay (it still reproduces). The compile-time deprecation warning and the U5/U6 unstable warnings landed at `fe1df5ce`, during
  the audit, and were not audited.

## What held up

- **`bytes` matches Python.** 300 invalid UTF-8 vectors, 120 random method cases, every hash, HMAC, CRC, base64, hex and struct
  format agreed with Python 3; the binary tools (BMP, hexdump, records, TCP and UDP framing, `requests`) gave the right bytes; no ASan
  report anywhere in areas A and H.
- **`bytearray` is correct where it is used as documented.** A 20,000-step random differential test against `list[int]` found no
  mismatch and ran clean under ASan; every mutating path checks 0..255 (E648); aliasing through fields, dicts, lists and generics
  holds; 10 million `append`s take 0.17 s in release (a `list[int]` 0.60 s). The bytes gaps D128a closed are closed.
- **The error tree and bare `raise`.** Hierarchies with fields, catch by parent, retries that re-raise, bare `raise` across
  `await`/`gather`/`wait_for`, wrapped errors: all right in debug, release, ASan and wasm; bare `raise` outside a catch is E614.
- **`x is T`, `x is Class`, `elif` narrowing and `@str` of class-typed values** behaved in every case tried apart from items 3, 10
  and 11; the old `x in T` warns and `# allow: type-test` silences it.
- **Names.** Aliases, the "imported as 'm', so write m" error, std-module shadowing warnings, E608/E609/E623, E613 for reserved
  markers, E611 for `!tomato_*`, the `math.abs` hints and the `datetime` free functions are as documented.
- **`value`, JSON and TOML** round-trip unicode and surrogate escapes, awkward keys, `-0.0`, `1e300`, the int64 limits and TOML's
  date and time kinds, with line and column in every error, the same in all four builds.
- **The first hour** (`init`, `run`, `build`, `test`, `config`, `explain`, a path seed) reads well and says what to do next, on
  Linux and on the Mac with bash 3.2 as `/bin/sh`. ShellCheck finds only style warnings and there is no bash-4-only construct in
  `native/` or `install-native.sh`. On the Mac `tests/repl_history.exp` and `tests/repl_echo.exp` pass (the arrow-key history
  works in a real pty), and `tomato test --timeout` leaves no process behind.
- **OS tools.** `sys.run` (2 MB in, 3 MB out, timeouts, signals, env, cwd), `Process`, `run_async` three at a time, async
  cancellation, and file tools with `File` inputs ran clean under ASan with no zombies.
- **The repl and the playground (Linux).** Echo survives a user `print`, multi-line definitions and redefinitions work, an error
  mid-session keeps the session with the right caret, top-level `await` and `input()` work; the playground's output matched native
  for every example and for a std-heavy program, browser-only limits give clear errors, and endless loops and recursion stop with
  E369 and E350.
- **Docs.** Every guide and playground example except the TOML one runs and prints what the page says, native and wasm; the
  `site/docs` copies and `site/wasm/std` match their sources (`std/reserved.txt` is not in the wasm copy and is not read there).

## Verification

- Every finding above was reproduced by the lead on `333b6c15` with a fresh install (`install-native.sh` into a temporary
  `TOMATO_HOME`); the Mac findings on the Mac itself. The auditors' repro files are summarized in each item; each `TODO.md` item
  carries its repro.
- The full suite (`tests/run.sh`, with node for the wasm path and expect for the pty tests) was run once at the end on this branch
  (`bf6dbb59` plus this document and `TODO.md`): 2669 passed, 0 failed, at load about 100. It runs on Linux, where the repl has no
  `jsc`, which is why blocker 1 does not show there.
