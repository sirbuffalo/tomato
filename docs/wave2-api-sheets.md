# Wave 2 API sheets — proposals for approval

Status: **proposals only; nothing here is built, decided or merged.** Davis approves each pack's sheet (and answers the questions at its end) before a builder starts. Written against `main` at `ab02c9c`, in the format of `docs/wave1-api-sheets.md` (the Wave 1 sheets), with more detail per sheet: names and signatures, error behavior, native versus browser availability, runtime and compiler changes, tests, size, dependencies, module state and closures.

**Evidence marks.** `[V]` = I read it in this repo (file given). `[I]` = inferred, or not checked. **Nothing was run**: this box has no `clang`, `tomato` or `node`, so every `[V]` is a statement about source text.

**Scope.** The four Wave 2 packs of `docs/next-features.md` (section 6): **A** `os`/`sys`/path and files v2 (#2), **B** testing support (#3), **C** `re` (#6), **D** hashing and binary helpers (#12). Wave 3 (async toolkit, sockets, HTTP server, subprocess) is out of scope except where a Wave 2 API must not block it.

---

## 0. Ground rules

### 0.1 Decisions Davis already made (the sheets build on these; they are not re-asked)

| Decision | Where it was made | What it means for Wave 2 |
| --- | --- | --- |
| **Binary data is `list[int]` (values 0–255), plus text helpers; no `bytes` type for now** | The async/sockets task asked whether sockets should carry binary as `list[int]` or wait for a `bytes` type; Davis chose `list[int]` now, plus text helpers (answered 24 Nov, 00:40 UTC) | Hashing, `struct`, `hmac`, file byte helpers and `crc32` all take and return `list[int]`. Every API that takes bytes rejects values outside 0–255 with `ValueError`, as `loads_msgpack` and `base64` (Wave 1) do. Where a `bytes` type would change an API, the sheet says so |
| Cancellation reaches the awaited call (`await f()`), D76b amending D58d | same task | Blocking file and system calls in pack A are synchronous C calls, so they are not cancellation points; tests in pack B must not assume `cancel` can interrupt a running test |
| `asyncio.wait_all`; module is `import asyncio`; `Queue[T](maxsize)` takes the size by position | same task (D76a), `std/asyncio.tom` on branch `byre/tsk8FAODjszAO8` | Pack B's async tests would use these; see B-Q6 |
| TCP sockets first, no UDP | same task | Nothing in Wave 2 depends on sockets |
| Wave 1: five sheets approved as written. They fix these conventions: Python behavior unless stated; **explicit objects, no module-level state or hidden singletons** (`random.Random(seed)`, no `random.random()`); **flat module names where nested packages are unconfirmed** (`urlparse`, not `urllib.parse`); eager `list` results instead of iterators (`csv.reader`); text-to-text and `list[int]` forms for binary (`base64`, `hex`, `secrets.token_bytes`) | `docs/wave1-api-sheets.md` (branch `byre/tskaPyLzZX3lho`) | Wave 2 follows all four conventions. A new decision below is only flagged when Wave 2 cannot follow them |
| No top-level code (D47a); `export const name = literal` is the only module-level value (D49b) | `docs/decisions.md` | No lookup tables or caches at module level: tables are rebuilt per call or held in an object (see D, C) |
| Function values are plain code pointers: non-capturing; not async, not generic, not methods, not `*args` functions (D63a) | `docs/decisions.md:1511-1517` | `assert_raises` and `sub` callbacks take a **named** `fn(...)`; an async function cannot be a test callback (B-Q6) |
| Entry points: `@name` marks one, `tomato run FILE ENTRY INPUTS` passes typed inputs (D16a, D28a, D28b); `*args`/`**kwargs` exist (D39a) | `docs/decisions.md` | Pack A's `argv`, pack B's `@test` build on this (A-Q3, B-Q2) |
| Errors are classes in `std/builtin/errors.tom`, each with a line in `std/errors.txt` (the line number is the id `E##`) (D22a, `docs/errors.md`) | repo | Every new error kind needs a line there; parallel branches adding lines collide (section 0.4) |
| Native-only features raise a clear runtime error in the browser (the `requests` precedent, D62a) | `std/requests.tom`, `tests/programs/requests_browser.tom` | Used for the few pack A calls the playground cannot serve (A-Q8) |
| "He decides all language semantics" (`docs/handoff.md`) | repo | Everything marked **Davis** below waits for an answer |

### 0.2 Conventions used in every sheet

Unless a sheet says otherwise: match Python 3 for the listed operations, including Unicode character indexing (UTF-8 text counted in characters, D17b-c), exception conditions and defaults, subject to Tomato's static types; new modules work natively and in the playground (or say why not); each new module adds `export`ed names only, a `site/wasm/tomato.js` `STD` list entry (`site/wasm/tomato.js:17` `[V]`), an `std/errors.txt` line per new error kind, a bullet in `docs/specification.md`, a `docs/decisions.md` entry, tests in `tests/programs` (with `tests/expected/NAME.main.out` and a line in `tests/programs.txt`) and, for anything touching memory, a name in the ASan list in `tests/run.sh` `[V]`. Anything marked *runtime change* edits `runtime/tomato_rt.c` and so needs the committed `site/wasm/*.wasm` rebuilt on the release Mac; anything marked *compiler change* edits `compiler/src/*.tom`, needs `compiler/bootstrap/refresh.sh` (needs clang) and also changes `tomatoc.wasm` `[V]` (`site/wasm/build.sh`, `docs/releasing.md`).

### 0.3 The shared item: text ⇄ bytes (X1) — Davis, needed by packs A, D and the sockets task

Davis chose "`list[int]` plus text helpers" for sockets. **I could not find the helpers defined anywhere**: `git grep` across every `byre/*` branch finds no `utf8`, `encode_utf8` or `send_text` in code or docs, only the question that proposed `send_text`/`recv` `[V]`, so the async task has not built them yet. Hashing (`sha256` of a `str`), `struct` text fields, `hmac` and Wave 1's `uuid5` (UTF-8 name) all need `str -> list[int]` and back. Proposal, one tiny flat module `utf8`:

- `utf8.encode(text: str) -> list[int]` — UTF-8 bytes of `text` (text is always valid UTF-8, or kept as given bytes if invalid, D17 `[V]` `tests/programs/utf8_invalid.tom`); never raises.
- `utf8.decode(data: list[int], errors: str = 'strict') -> str` — `'strict'` raises `ValueError` on invalid UTF-8 or a value outside 0–255; `'replace'` substitutes U+FFFD per Python; any other `errors` raises `ValueError`.
- Pure Tomato with `ord`/`chr` is correct but slow for large inputs; two small C helpers (`tomato_str_to_bytes`, `tomato_bytes_to_str`) make it fast and share one copy with sockets. Size S.

Whoever lands first owns it; the others import it. **Davis: name and home** (A: `utf8` module; B: methods `s.encode()`/`data.decode()` — needs compiler support for methods on `list[int]`, which is not a distinct type, so I do not recommend it; C: functions in an existing module).

### 0.4 Cross-pack dependencies and build order

```
      D (hashing/binary)  — pure Tomato, no runtime change (floats in struct optionally need 2 C helpers)
      C (re)              — pure Tomato, no runtime or compiler change
      A (os/sys/files)    — runtime C + a small compiler change for File methods
      B (testing)         — compiler change (assert, @test) + native/tomato `test` command
      B uses A: sys.exit gives the process exit status after a failing run
      D uses A (optional): hashlib.file_hexdigest reads a file through os.read_bytes
      D uses X1; Wave 1 uuid5 needs sha1 from D
```

- **Start in parallel now (no shared C or compiler files): C and D.** Both are pure Tomato, work in the browser, and need no wasm rebuild beyond copying `std/*.tom`.
- **A before B.** A adds `sys.exit` and the runtime-side error helper B reuses; both change `native/tomato`/`tests/run.sh` lists. B and the Wave 1 builtins/format-spec subtask both edit `compiler/src/compiler.tom`, `parser.tom`, `lexer.tom`, `lint.tom`: **do not run them concurrently**; B starts after Wave 1's compiler work lands (or is rebased onto it).
- **Batch one wasm rebuild** for the whole wave: A's runtime C, D's optional float helpers and X1's helpers, plus B's compiler change (`tomatoc.wasm`).
- **Hot shared files** that every pack edits: `std/errors.txt` (ids are line numbers, so two branches appending collide on merge; each builder rebases and renumbers only its own lines), `tests/programs.txt`, `tests/run.sh` (the ASan list, the `arg=` case for programs that take a work directory), `site/wasm/tomato.js` `STD`, `docs/decisions.md`, `docs/specification.md`. Each pack adds at the end of the list and rebases before merge.
- **Wave 1 uuid5 needs SHA-1.** The approved Wave 1 sheet has `uuid.uuid5` hashing "the namespace bytes and UTF-8 name per RFC 9562", i.e. SHA-1. Pack D's `hashlib.sha1` is the natural source. **Davis (D-Q7):** either the Wave 1 uuid builder keeps a private `_sha1` (about 60 lines, duplicated) and dedupes later, or uuid5 waits for pack D. I recommend the private copy so Wave 1 is not blocked.

### 0.5 Sizes

**S** under about 400 lines and a day or two for an agent; **M** 400–1,500 lines, may touch runtime or compiler lightly; **L** 1,500+ lines or deep runtime/compiler work. "Sonnet alone" means a Sonnet agent can finish it from this sheet once approved; compiler changes always get a review pass.

---

## 1. Pack A — `os`, `sys`, paths and files v2 (roadmap #2). Size M (A1 S–M, A2 S–M)

Why: today a Tomato program cannot read its environment, list a directory, exit with a status or read a file line by line `[V]` (`File` has only `read`, `write`, `close`: `compiler.tom:4826-4840`). Everything here is native; the playground gets a subset (1.5).

### 1.1 Modules and names (**Davis A-Q1**)

Three flat modules, Python names where the languages agree:

- `sys` — process interface: `argv`, `exit`, stderr/stdout writes, `platform`, `version`.
- `os` — environment, working directory, directories, removal and renaming, `stat`, one-shot file helpers.
- `ospath` — path text functions (Python's `os.path`; a nested `os.path` is not assumed to import `[I]`: package imports are unconfirmed, the same reason Wave 1 used `urlparse`). A module named `path` is not proposed because `path` is the most common parameter name.
- **Not proposed:** a `pathlib.Path` class. It needs `/` overloading (an operator marker that may not exist) and every method re-exports the functions below; add it later on top of `ospath`/`os` once Davis wants it.

### 1.2 `sys`

| Name | Signature | Behavior and errors |
| --- | --- | --- |
| `argv` | `argv() -> list[str]` | All command-line words: `argv()[0]` is the program as invoked (the compiled executable's path), then the inputs. A function, not an attribute: no module-level values (D49b) |
| `exit` | `exit(code: int = 0) -> None` | Flushes standard output and error and every open `File` (C `exit()`), then ends the process with status `code`. **`finally` blocks and other tasks do not run** (see A-Q2). `code` outside 0–255 raises `ValueError`. Never returns |
| `write_stderr` | `write_stderr(text: str) -> None` | Writes to file descriptor 2 through the same stdio stream `/dev/stderr` opens `[V]` (`std_stream_fd`, `tomato_rt.c:2015`); no newline added |
| `write_stdout` | `write_stdout(text: str) -> None` | Same for standard output; interleaves correctly with `print` because both use stdio |
| `flush` | `flush() -> None` | Flushes standard output and error |
| `platform` | `platform() -> str` | `'linux'`, `'darwin'` or `'wasi'` (browser build) |
| `version` | `version() -> str` | The Tomato version text, e.g. `'0.52'`, from the same source as `tomato version` |

**Raw `argv` versus typed entry points (Davis A-Q3).** `tomato run FILE ENTRY INPUTS` parses each input into the entry's parameter type, and a wrong count stops with E352 (`tomato_usage`, `tomato_rt.c:216`) `[V]`; the native entry wrapper (`compiler.tom:7348-7425`) handles only `int`, `bool`, `str`, `float` and fixed-width parameters and has **no branch for `*args`/`**kwargs`** `[V]` even though D39a decided them for entries `[I: not tested]`. So `sys.argv()` can only see words the entry point accepted. Options: (1) *recommended*: implement `*args: tuple[str]` for entry points (D39a, compiler S) and have `argv()` return everything regardless; a program that wants flags takes `*args` and reads them. (2) `argv()` only, and relax the arity check for entries marked `@main(raw)` — new syntax. (3) Do nothing: `argv()` is then only useful for `argv()[0]`.

### 1.3 `os`

All paths and names are `str`; text that is not valid UTF-8 is carried as given (D17). A NUL in a path or name raises `ValueError`.

| Name | Signature | Behavior and errors |
| --- | --- | --- |
| `getenv` | `getenv(name: str, default: str \| None = None) -> str \| None` | Value or `default`. Empty or `=`-containing `name` raises `ValueError` (Python returns the default; Tomato rejects so a typo is visible — Davis may prefer Python's) |
| `environ` | `environ() -> dict[str, str]` | A **snapshot copy**. Changing the dict does not change the process; use `putenv` (A-Q9) |
| `putenv` | `putenv(name: str, value: str) -> None` | Sets in the process environment (inherited by children, later `subprocess`). Bad `name` raises `ValueError`. `os.environ` mutation syntax is not provided |
| `unsetenv` | `unsetenv(name: str) -> None` | Removes; absent is not an error |
| `getcwd` | `getcwd() -> str` | `OSError` -> `IOError` if the directory vanished |
| `chdir` | `chdir(path: str) -> None` | Process-wide: affects every task and relative path afterwards. `FileNotFoundError`-family errors (see 1.7) |
| `getpid` | `getpid() -> int` | |
| `listdir` | `listdir(path: str = '.') -> list[str]` | Entry names without `.` and `..`, **sorted by bytes** so output is the same on every platform and in tests (Python: arbitrary order; **Davis A-Q5**) |
| `mkdir` | `mkdir(path: str) -> None` | Mode `0o777` & umask (no octal literals in Tomato `[V]` D67a "not built"). Exists -> `FileExistsError`, parent missing -> `FileNotFoundError` |
| `makedirs` | `makedirs(path: str, exist_ok: bool = False) -> None` | Creates parents; existing directory with `exist_ok=False` raises `FileExistsError` |
| `remove` | `remove(path: str) -> None` | A file or symlink (a directory: `IsADirectoryError`) |
| `rmdir` | `rmdir(path: str) -> None` | Empty directory only |
| `rename` | `rename(src: str, dst: str) -> None` | POSIX `rename`: replaces an existing file |
| `stat` | `stat(path: str) -> StatResult` | `class StatResult` with fields `size: int`, `mtime: float` (seconds, UTC epoch), `mode: int`, `is_file: bool`, `is_dir: bool`, `is_symlink: bool` (the last from `lstat`) |
| `read_text` | `read_text(path: str) -> str` | `open` + `read` + `close` in a `try/finally` (so it never leaks a `File`, see A-Q7) |
| `write_text` | `write_text(path: str, text: str, append: bool = False) -> None` | Replaces, or appends; creates the file |
| `read_bytes` | `read_bytes(path: str) -> list[int]` | Wraps `tomato_file_read_bytes` `[V]` (`tomato_rt.c:4943`), which already exists |
| `write_bytes` | `write_bytes(path: str, data: list[int], append: bool = False) -> None` | Wraps `tomato_file_write_bytes` `[V]`; a value outside 0–255 raises `ValueError` and **the file is not touched** (the check runs before opening, as in `dump_msgpack` `[V]`) |

`ospath` (Python's `os.path`; pure Tomato except `abspath`, which calls `getcwd`; POSIX only, `/` separator, the Windows rules of `ntpath` are out of scope):

| Name | Signature | Behavior |
| --- | --- | --- |
| `sep` | `export const sep = '/'` | |
| `join` | `join(first: str, *rest: tuple[str]) -> str` | Python: a later absolute part restarts the path; an empty part is skipped; no doubled separators added. If `*args` does not work in library functions (an unchecked `[I]` against D39a), the builder falls back to `join(a, b)` plus `join_all(parts: list[str])` and reports it |
| `split` / `splitext` | `-> tuple[str, str]` | Python's results for `/`, trailing `/`, dotfiles (`.bashrc` has no extension), `a.b.c` |
| `basename` / `dirname` | `-> str` | Python's |
| `normpath` | `normpath(path: str) -> str` | Collapses `.`, `..` and repeats; `''` -> `'.'` |
| `isabs` | `isabs(path: str) -> bool` | |
| `abspath` | `abspath(path: str) -> str` | `normpath(join(getcwd(), path))` |
| `relpath` | `relpath(path: str, start: str = '.') -> str` | Pure text after `abspath`; no filesystem access |
| `expanduser` | `expanduser(path: str) -> str` | Leading `~` or `~/` from `HOME`; unchanged if `HOME` unset; `~user` unchanged (no `getpwnam`) |
| `exists`, `isfile`, `isdir`, `islink` | `(path: str) -> bool` | Follow symlinks except `islink`; **never raise**, false on any error (Python) |
| `getsize` | `getsize(path: str) -> int` | `FileNotFoundError` if absent |
| `getmtime` | `getmtime(path: str) -> float` | same |
| not in v1 | `realpath`, `commonpath`, `samefile`, `walk`, `glob`, `fnmatch`, `shutil` | `realpath` needs a C call; `walk` needs a lazy or nested result type; rest are "later, after #2" in the roadmap |

### 1.4 Files v2 — the `File` built-in (**the compiler part**)

`File` is a compiler primitive with a fixed method set, not a Tomato class `[V]` (`compiler.tom:32, 4426, 4826`). Extending it is a **compiler change** (`file_method`, plus iteration in `for`).

| Addition | Signature | Behavior |
| --- | --- | --- |
| `readline` | `f.readline() -> str` | Next line **including** its `\n`; `''` at end of file (Python). A final line without `\n` is returned as is |
| `readlines` | `f.readlines() -> list[str]` | All remaining lines, each with its `\n` |
| iteration | `for line in f:` | Same lines as `readline`, lazily, so a large file is not loaded whole. Needs the `for` lowering to loop on a runtime `tomato_file_readline` |
| `write` return | unchanged (`-> None`) | Python returns the count; not worth a type change |
| `writelines` | `f.writelines(lines: list[str]) -> None` | Writes each item, no separator |
| `flush` | `f.flush() -> None` | |
| modes | `open(path, mode)` | Today `mode` goes straight to `fopen` `[V]` (`tomato_rt.c:2024`), so `r`, `w`, `a`, `r+`, `w+`, `a+` already work by accident. Proposal: document and test `r w a x` with an optional `+`, and make any other string (including any containing `b`) raise `ValueError('open() text modes only: use os.read_bytes/os.write_bytes for bytes')` before calling `fopen` |
| `StringIO` | pure-Tomato `class StringIO` in `os`'s sibling module `io`: `StringIO(initial: str = '')`, `write(text)`, `getvalue() -> str`, `read() -> str`, `readline() -> str`, `readlines() -> list[str]`, `seek(0)`, `close()` | Because `File` is not an interface, a function that takes a `File` cannot take a `StringIO`; this is why `StringIO` is of limited use until `File` becomes a class (**A-Q7**). Optional, S |

Not proposed: `read(n)` (byte or character counts in text mode need a decision about UTF-8 boundaries), `seek`/`tell` on text files, `fileno`, `readinto`, a `with` statement (language decision, `next-features.md` D5), binary `open(path, 'rb')` (needs a type; use `read_bytes`/`write_bytes`).

### 1.5 Native versus browser

The playground's host is `site/wasm/wasi.js`: `args_get`, `environ_get`, `proc_exit`, `random_get`, `path_open`, `path_unlink_file` exist; **no `fd_readdir`, no `path_rename`, no directories** (`path_create_directory` is a no-op returning success, `path_filestat_get` knows regular files only) `[V]` (`wasi.js:45-149`). So:

| Call | Native | Playground (as it is) | Proposal (**A-Q8**) |
| --- | --- | --- | --- |
| `argv`, `getenv`, `environ`, `exit`, `platform`, `version`, `write_*`, `flush`, `ospath` text functions, `read_text/write_text`, `read_bytes/write_bytes`, `remove`, `exists`/`isfile`/`getsize`, `StringIO`, `File` additions | yes | works through existing host calls | works |
| `listdir`, `isdir`, `stat` on directories, `mkdir`, `makedirs`, `rmdir`, `rename` | yes | host lacks them | implement them in `wasi.js` over the in-memory file map (JS only, no wasm rebuild); directories are the path prefixes of the files |
| `chdir`, `getpid`, `putenv`, `unsetenv`, `getcwd` | yes | no process model | `getcwd` returns `'/'`; the rest raise `RuntimeError('not available in the browser playground')` (the `requests` precedent) |

### 1.6 Runtime and compiler support needed

- **Runtime C** (all of it works in the WASI build; `TOMATO_WASM` guards only where a call is not in WASI): `tomato_env_get/set/unset/list`, `tomato_getcwd`, `tomato_chdir`, `tomato_getpid`, `tomato_listdir`, `tomato_stat`, `tomato_mkdir`, `tomato_rmdir`, `tomato_remove`, `tomato_rename`, `tomato_exit`, `tomato_write_fd`, `tomato_file_readline`, `tomato_file_flush`. Each fills a result or returns an `errno` code that Tomato code maps to the error class (1.7); keep the entry-point list short as `tomato_math1/2` do `[V]` (a comment says the browser build must export every name).
- **Compiler** (S): `File` methods `readline`, `readlines`, `writelines`, `flush`; `for line in f`; open-mode check; entry `*args` if A-Q3 option 1.
- **`std/builtin/errors.tom`**: the error subclasses of 1.7, if approved.
- **No change** to the scheduler. File calls block the thread, as `open().read()` does today; async file I/O is not proposed.

### 1.7 Errors (**Davis A-Q4**)

Today every file failure is an `IOError` with the text `could not open 'PATH': REASON` and id E25/E381/E382 `[V]`. Python code catches `FileNotFoundError` and friends; proposal: add subclasses of `IOError` in `std/builtin/errors.tom` — `FileNotFoundError`, `FileExistsError`, `PermissionError`, `IsADirectoryError`, `NotADirectoryError` — chosen from `errno`, and have `open()` raise them too. `catch IOError` keeps working; ids stay (`E25` etc., one new line per subclass). No `errno` field (the message carries `strerror`). Alternative: keep one `IOError` and tell people to read the message — smaller, but un-Pythonic.

### 1.8 Tests to write

`tests/programs/`: `sys_basics` (argv through an entry that takes `*args` or the chosen option, `platform`, `version`, `write_stderr`/`write_stdout` ordering against `print`), `os_env` (`getenv` set and unset via `putenv`; bad names), `os_files` (takes a work directory as input like `json_files` `[V]`: add its name to the `arg=` case in `tests/run.sh`; create, write, append, `listdir` sorted order, `stat`, `rename`, `remove`, `makedirs`, errors for missing, existing, directory, permission), `ospath_text` (a table of 60+ cases generated from Python's `posixpath` and committed as expected output), `file_lines` (readline, readlines, `for line in f`, no trailing newline, empty file, CRLF kept, a 5 MB file iterates without loading it whole, invalid UTF-8 kept), `file_modes` (`x`, `+`, rejected modes), `bytes_files` (round trip of all 256 values; bad value leaves file untouched), `string_io`. `tests/runtime/exit_status` (`sys.exit(3)` gives status 3, flushes pending `write_stdout`, runs no `finally`). ASan list: all file programs. Browser: `read_text`, `ospath`, `getenv`, `exit` run through `jsc native/tomato-jsc.js` like other wasm-listed tests `[V]` (`tests/run.sh:89-119`). A leak test: a `File` that goes out of scope without `close()` (A-Q7).

### 1.9 Size, dependencies, state, closures

Size **M**. A1 (`sys`, `os`, `ospath`, byte/text helpers, exit, errors) S–M; A2 (`File` methods, `for line in f`, modes, `StringIO`) S–M and compiler-touching, so after Wave 1's compiler work. Sonnet alone for A1; A2 with review. Depends on: nothing in the other packs. Feeds: pack B (`sys.exit`), pack D (`read_bytes`), later `tempfile`, `shutil`, `glob`, `logging` to a file, `subprocess`, `csv` file reading. **Module-level state: none** (`environ()` is a snapshot; the process environment is C state behind functions, the option (ii) of `next-features.md` D2). **Closures: none needed**; `walk`/`glob` with callbacks are not proposed.

### 1.10 Questions for Davis (in order)

1. **A-Q1 Names and layout.** `sys`, `os`, `ospath` (flat), `io` for `StringIO`; no `Path` class yet. OK? (alternatives: nested `os.path`, a `Path` class now.)
2. **A-Q2 `sys.exit` semantics.** (a) *recommended*: flush and end the process now; `finally` blocks and other tasks do not run. (b) raise an uncatchable `SystemExit` so `finally` runs (needs a language rule that `catch Error` does not catch it). (c) a normal `Error` subclass that `catch Error` would swallow (not recommended).
3. **A-Q3 Raw command-line words.** `*args: tuple[str]` on entry points (recommended), a special marker, or leave typed inputs only.
4. **A-Q4 File error classes.** Add `FileNotFoundError` & co. as `IOError` subclasses (recommended) or keep one `IOError`.
5. **A-Q5 `listdir` order.** Sorted (recommended: same on every platform) or the OS order.
6. **A-Q6 Binary files.** `read_bytes`/`write_bytes` functions (recommended; wraps runtime code that exists) versus waiting for a `bytes` type to allow `open(path, 'rb')`.
7. **A-Q7 `File` lifetime.** I did not verify that a `File` that is dropped is closed `[I]` (`File` is a raw pointer, not a counted object `[V]` `compiler.tom:397`). Is closing on scope exit, or a `with` statement, to be designed? Until then the new helpers use `try/finally`, and `File` stays a non-interface built-in (so `StringIO` cannot substitute for it).
8. **A-Q8 Playground.** Implement the directory and rename host calls in `wasi.js` (recommended) or raise "not available in the browser".
9. **A-Q9 Environment.** `getenv` raising `ValueError` on a bad name, `environ()` a snapshot, `putenv`/`unsetenv` as functions (recommended) versus a live `environ` object (needs a class with `@get`/`@set` markers and module state).

---

## 2. Pack B — testing: `assert`, `@test`, `testing` (roadmap #3). Size M

Why: a user cannot test their own code; the repo's own tests are expected-output files compared in shell `[V]`. Three layers, each usable without the next.

### 2.1 Layer 1: the `assert` statement (compiler, S) — **Davis B-Q1**

```
assert condition
assert condition, 'message'
```

- A new reserved word `assert` (lexer keyword list `lexer.tom:44`, `lint.tom` `is_keyword`, the VS Code grammar in `editors/vscode`, the website highlighter, `docs/specification.md`). No existing source uses `assert` as a name `[V]` (grep of `std`, `tests`, `examples`, `compiler/src`).
- The condition must be `bool` (rule P8: conditions are `bool`, so `assert (a, b)` is a compile error, not Python's always-true tuple). `message` must be `str`.
- Lowers to `if not condition: raise AssertionError(message)` in the parser (a desugar, no new IR), with the line of the `assert` so the usual `(raised on line N)` suffix and call trace appear `[V]` (`tomato_rt.c:3030`).
- New error class `AssertionError` in `std/builtin/errors.tom`, one new id in `std/errors.txt`. Parent (**B-Q5**): `RuntimeError` like the other runtime kinds, or directly `Error`? Python's is a direct `Exception`; `catch RuntimeError` catching a failed assertion is surprising, so I recommend a direct subclass of `Error`.
- **Always on**, in debug and release mode alike (Python strips asserts under `-O`; Tomato's release mode already means "short error codes", D34b, and silently dropping checks would be a second meaning). **Davis: confirm.**
- Message when none is given: `assertion failed`. Nice-to-have if the parser keeps source spans: append the expression text (`assertion failed: x == 1`); builder checks feasibility, no promise.

### 2.2 Layer 2: the `testing` module (pure Tomato, S)

`from testing import assert_equal, ...`; all raise `AssertionError`; every `message: str = ''` is appended to the failure text.

| Name | Signature | Failure text |
| --- | --- | --- |
| `fail` | `fail(message: str = '') -> None` | the message |
| `assert_true`, `assert_false` | `(value: bool, message: str = '')` | `expected True` / `expected False` |
| `assert_equal` | `assert_equal[T](actual: T, expected: T, message: str = '')` | `expected X, got Y` using `str()` |
| `assert_not_equal` | same shape | `values are equal: X` |
| `assert_in`, `assert_not_in` | `[T](item: T, items: list[T], message: str = '')` | `X is not in [...]` |
| `assert_none`, `assert_not_none` | `[T](value: T \| None, message: str = '')` | `expected None, got X` |
| `assert_close` | `assert_close(actual: float, expected: float, rel_tol: float = 1e-9, abs_tol: float = 0.0, message: str = '')` | Python's `math.isclose` rule (Wave 1 does not add `isclose`; it lives here) |
| `assert_raises` | `assert_raises(f: fn() -> None, kind: str = 'Error') -> Error` | see below |
| `assert_raises_with` | `assert_raises_with[A](f: fn(A) -> None, arg: A, kind: str = 'Error') -> Error` | see below |
| `skip` | `skip(reason: str) -> None` | raises `SkipTest`, counted by the runner, not a failure (optional, S) |

**Feasibility checks the builder must do first** `[I]`: `==` and `str()` on a type parameter `T` (the roadmap already notes `<` on generic `T` is unverified, `next-features.md` section 7). If they do not compile, the fallback is typed functions (`assert_equal_int`, `_str`, `_float`, `_bool`, `_list_int`, `_list_str`) generated from one template; Davis need not choose, but the API then looks different, so the builder reports back before building.

**`assert_raises` without closures.** `f` is a *named* no-argument function (`fn() -> None`, D63a), so it cannot see the test's local variables. Two helpers cover the gap: put the call in a small named function, or pass the argument explicitly with `assert_raises_with(parse, 'x', 'ValueError')`. `kind` is the **class name as text**; it matches the raised error's class or any subclass (the runtime keeps class names and a parent table `[V]`, `tomato_rt.c:2787, 3025`; one small C helper, `tomato_error_is(err, name)`, S) and **fails the test** if nothing is raised or an unrelated class is raised; it returns the caught error so the test can check `.message`. Alternatives (**B-Q3**): (a) *recommended*: by name as above; (b) catch any `Error` and let the test inspect the result (`ValueError(e)` conversions fail catchably, P15), no runtime helper; (c) wait for `with`/closures so `with assert_raises(ValueError):` can exist.

No fixtures, setup/teardown or parametrization in v1: a test that needs shared setup calls a helper function; parametrization is a `for` loop inside one test. No `assert_less`/`_greater` in v1 (needs generic `<`, unverified).

### 2.3 Layer 3: `@test` and `tomato test` (compiler + shell, M) — **Davis B-Q2**

```
from testing import assert_equal

@test
def adds():
    assert_equal(1 + 1, 2)

@test
def divides_by_zero():
    ...
```

- `@test` marks any number of functions with no parameters and no return. Today a repeated entry name stops with "not decided" (P21) `[V]`; **change:** `@test` may repeat, nothing else does. Tests run **in the order defined**, in one process.
- **How the driver is made** (builder to verify `[I]`): when the entry is `test`, the compiler appends generated source — a function `@test_main` that calls `testing._run_all(['adds', 'divides_by_zero'], [adds, divides_by_zero])` with the names as text and the functions as `fn() -> None` values (legal: named functions are first-class, D63a) — so no IR is hand-written. All the running and printing is Tomato code in `std/testing.tom`.
- **Runner**: for each test, `try` the call, `catch Error as e` records a failure with the test name, the message and the raising line; `SkipTest` is recorded as skipped; any other uncaught thing ends the run as it would today. Output (**B-Q4**), in the style the repo's own test runner already uses `[V]` (`tests/run.sh`: `ok   NAME`, `FAIL NAME`):

```
ok   adds
FAIL divides_by_zero
     expected 3, got 2  (raised on line 12)
skip lookup  (no network)
2 passed, 1 failed, 1 skipped
```

  Failures and the summary go to standard output (so they are capturable and testable); exit status is 1 if any test failed, else 0 — via `sys.exit` from pack A (so B follows A).
- **Command**: `tomato test FILE... [--filter TEXT] [--mode MODE]` in `native/tomato` (a `case` branch beside `run`), compiling each file with entry `test` and running it; any failing file makes the command exit 1. No directory discovery in v1 (`tomato test` with no file is an error with a usage line). `tomato help` and `tests/run.sh`'s CLI section list it.
- **What a test can do:** anything a synchronous program can. `await` is **not** available in v1: an `async def` is not a plain function value (D63a), so `@test` on an async function is a compile error saying so (**B-Q6**). Async tests need either async function values or a runner that takes tasks (for example an `asyncio`-based `testing.run_async`); that belongs with the async task's API, not here.
- **Isolation:** tests share a process, so a test that calls `sys.exit`, changes the working directory or the environment affects later ones; documented, not prevented. A runtime failure that is catchable (all of them `[V]`, P29) fails that test only.
- **Playground:** the compile API already takes an entry name `[V]` (`tomato.js` `compile(source, entry, extra)`); running entry `test` works unchanged once the compiler change is in the wasm. No UI is proposed.

### 2.4 Native versus browser

`assert`, the `testing` module and the driver are pure Tomato plus the compiler change: they run natively and in the browser. `tomato test` is native only (a shell command). The exit status needs `sys.exit` (native; in the browser the host's `proc_exit` exists `[V]`).

### 2.5 Runtime and compiler support needed

- **Compiler (S–M):** `assert` keyword (lexer, parser desugar, lint list, editor grammars); repeatable `@test`; generation of the test driver; a clear error for `@test` on async or parameterized functions.
- **Runtime (S, optional):** `tomato_error_is(err, name)` for `assert_raises` option (a). Batched with pack A's wasm rebuild.
- **Tooling:** `native/tomato` `test` command; `docs/specification.md`, `docs/decisions.md`, editor grammar and site highlighter keyword lists. Bootstrap IR regenerated (`compiler/bootstrap/refresh.sh`), `tomatoc.wasm` rebuilt.

### 2.6 Tests to write

`tests/programs/assert_ok` (all forms pass, message with `+` and f-strings), `tests/runtime/assert_failed` (the failing `assert` run: stderr text, line, exit 1, in debug and release code form E##), `tests/negative/assert_not_bool`, `assert_tuple`, `assert_message_not_text`, `test_on_async`, `test_with_parameter`, `duplicate_test_name`; `tests/programs/testing_lib` (each assert passes and fails with the documented text, caught in-process; `assert_close` edge cases including NaN and infinities; `assert_raises` subclass match, wrong class, nothing raised, returns the error); `tests/cli` additions in `tests/run.sh` — a three-test file with one failure checks stdout, summary line and exit status 1, an all-pass file exits 0, `--filter` selects one, a compile error in the file exits nonzero with the usual message; the wasm list gets `assert_ok`. ASan: `testing_lib`.

### 2.7 Size, dependencies, state, closures

Size **M**: layer 1 S, layer 2 S, layer 3 M. Order: layer 1+2 can land together; layer 3 after pack A. Sonnet alone once Davis picks the syntax, with a compiler review (roadmap). **Module-level state: none** — the runner counts in a small `_Report` object it passes around. **Closures: the central limit** (named, non-capturing callbacks; `assert_raises_with` is the workaround; `with assert_raises(...)` is the thing that would remove it).

### 2.8 Questions for Davis (in order)

1. **B-Q1 `assert` statement.** A reserved word with `assert cond, 'message'`, always on, message optional (recommended), versus functions only (`assert_true(...)`) with no language change.
2. **B-Q2 `@test`.** Repeatable `@test` plus a generated driver and `tomato test FILE...` (recommended), versus library-only (`testing.run([...cases])` registered by hand in `@main`, no compiler change beyond `assert`).
3. **B-Q3 `assert_raises`.** Class name as text, returns the error (recommended); catch-any-and-inspect; or wait for `with`.
4. **B-Q4 Output and exit.** The repo-style `ok`/`FAIL` lines with a summary, failures on standard output, status 1 on any failure (recommended); or TAP, or Python `unittest`'s `.F` style.
5. **B-Q5 `AssertionError`.** Direct `Error` subclass (recommended) or under `RuntimeError`.
6. **B-Q6 Async tests.** Out of v1 (recommended; needs async function values or a task-taking runner) — or does this wait for the async task's API?

---

## 3. Pack C — `re` (roadmap #6). Size L (pure Tomato, no runtime or compiler change)

Why: after OS access, the most common reason a Python user cannot port a script. A backtracking engine written in Tomato, the Python syntax subset below. Native and browser identical.

### 3.1 Module and names (**Davis C-Q5**)

Flat module `re`, imported as `import re` (`re.compile(...)`), or `from re import compile, Match`.

- Flags are Python's numeric values so Python habits and `|` work: `export const IGNORECASE = 2`, `MULTILINE = 8`, `DOTALL = 16`, `VERBOSE = 64`, `ASCII = 256` and the one-letter aliases `I M S X A`. v1 builds `IGNORECASE`, `MULTILINE`, `DOTALL`, `ASCII`; `VERBOSE` is stage 2 (below); any other bit raises `ValueError`.
- Error class: `RegexError(RuntimeError)` with `pos: int` (Python calls it `re.error`; Tomato class names are capitalized, as `JSONDecodeError`), one id per kind in `std/errors.txt`.

### 3.2 API

```
compile(pattern: str, flags: int = 0) -> Pattern
match(pattern: str, text: str, flags: int = 0) -> Match | None        # anchored at the start
search(pattern: str, text: str, flags: int = 0) -> Match | None
fullmatch(pattern: str, text: str, flags: int = 0) -> Match | None
findall(pattern: str, text: str, flags: int = 0) -> list[str]         # whole matches only (C-Q2)
findall_groups(pattern: str, text: str, flags: int = 0) -> list[list[str]]
finditer(pattern: str, text: str, flags: int = 0) -> list[Match]      # eager, as csv.reader (Wave 1)
sub(pattern: str, repl: str, text: str, count: int = 0, flags: int = 0) -> str
sub_with(pattern: str, repl: fn(Match) -> str, text: str, count: int = 0, flags: int = 0) -> str
subn(pattern: str, repl: str, text: str, count: int = 0, flags: int = 0) -> tuple[str, int]
split(pattern: str, text: str, maxsplit: int = 0, flags: int = 0) -> list[str]
escape(text: str) -> str
```

`class Pattern` (also `Pattern.match(text, pos=0, endpos=-1)`, `search`, `fullmatch`, `findall`, `findall_groups`, `finditer`, `sub`, `sub_with`, `subn`, `split` with the module functions' arguments minus `pattern`/`flags`) with fields `pattern: str`, `flags: int`, `groups: int` (number of capturing groups), `groupindex: dict[str, int]`, and `step_limit: int`.

`class Match`: fields `string: str`, `pos: int`, `endpos: int`, `re: Pattern`; methods

| Method | Behavior |
| --- | --- |
| `group(key: int \| str = 0) -> str` | the text of that group (int index or name); a group that did not take part gives `''` (**C-Q1**); an index or name that does not exist raises `IndexError` (message names the group) |
| `matched(key: int \| str = 0) -> bool` | whether the group took part (what `group` cannot say) |
| `groups() -> list[str]` | groups 1..n, `''` for non-participating (Python: a tuple, `None` for them) |
| `groupdict() -> dict[str, str]` | named groups |
| `start(key = 0)`, `end(key = 0)` -> `int`; `span(key = 0) -> tuple[int, int]` | positions in **characters**, `-1` if the group did not take part (Python) |
| `expand(template: str) -> str` | the `sub` template rules |

`sub` templates follow Python: `\1`..`\99`, `\g<1>`, `\g<name>`, `\g<0>`, the escapes `\n \t \r \\`; an unmatched group contributes `''` (Python 3.5+); a bad group reference raises `RegexError` at call time; a template with unknown escape letters raises `RegexError` (as Python 3.7+). Empty matches are replaced as in Python 3.7+. `sub_with`'s callback is a **named** `fn(Match) -> str` (no closures: it cannot read the caller's locals).

### 3.3 Syntax supported (version 1) and what raises `RegexError`

Supported, following Python: literal characters and escapes (`\n \t \r \f \v \a \0`, `\xhh`, `\uhhhh`, `\Uhhhhhhhh`, escaped metacharacters; unknown ASCII-letter escapes are errors as in Python 3.7+); `.` (any but `\n`; with `DOTALL` any); classes `[abc] [^abc] [a-z]` with escapes and the shorthand classes inside; `\d \D \w \W \s \S` (**C-Q3**); anchors `^ $ \A \Z \b \B` (`$` also matches before a final `\n`, Python's rule; `MULTILINE` makes `^`/`$` per line); groups `( )`, `(?: )`, `(?P<name> )`, backreferences `\1`..`\99` and `(?P=name)`; alternation `|`; greedy and lazy quantifiers `* + ? {m} {m,} {,n} {m,n}` and `*? +? ?? {m,n}?`; lookahead `(?= ) (?! )`; inline flags `(?i)` (at the start, as Python 3.11 requires) and scoped `(?i: )`; comments `(?# )`.

Stage 2 of the build (same sheet, after stage 1 passes): fixed-width lookbehind `(?<= ) (?<! )`, `VERBOSE`. **Not supported in v1** and raised as `RegexError('... is not supported')` at compile time, never silently ignored: possessive quantifiers `*+`, atomic groups `(?> )`, conditionals `(?(1)a|b)`, `\G`, Unicode property classes (Python has none either), `(?L)`/`(?u)` flag letters, `\N{name}`.

Case-insensitive matching compares with the runtime's Unicode simple case mapping (`upper()`/`lower()` tables, D67a `[V]`), so `é` matches `É`; `ß` still does not match `SS` (one-to-one mapping), a documented difference from Python.

### 3.4 Engine design (builder guidance, so size and risk are visible)

- **Compile once to a program**, an array of ints plus side lists (opcodes: char, any, class, split, jump, save, assert-start/end/word-boundary, backref, lookahead…): no closures, no per-node objects (the roadmap's reason `[V]` "A compile-to-closures design is blocked by no closures"). Classes are sorted range lists searched by bisection.
- **Backtracking with an explicit stack**, not recursion: the call limit is 10,000 (P26 `[V]`), so a recursive matcher would fail on `.*` over a 20,000-character line. The stack is a `list[int]` of choice points.
- **Subject text** is turned into a `list[int]` of code points once per call (O(n)), so no repeated `s[i]` costs; positions are character indexes, as Python.
- **A literal-prefix fast path** uses the built-in `find` to skip to candidate starts. `[I]` performance: tens of times slower than Python's C `re` on heavy patterns; adequate for scripting; the builder records measured numbers on a corpus.
- **Step limit (Davis C-Q4):** each `Pattern` counts matcher steps and raises `RegexError('too many steps (catastrophic backtracking?)')` past `step_limit` (default 20,000,000, changeable per `Pattern`). Python has no limit and can hang forever; a server taking user-supplied patterns or text needs one. Recommendation: on, as stated.
- **No pattern cache.** Python's `re.match(p, s)` caches the compiled pattern in module state; Tomato has none (D47a) and Wave 1 forbade hidden state. Module-level functions therefore compile on every call; documentation says to hold a `Pattern` (**C-Q5**).

### 3.5 Native versus browser

Identical. Pure Tomato, no runtime or compiler change, no wasm rebuild; `re` is added to `site/wasm/tomato.js` `STD` and copied by the release script `[V]`.

### 3.6 Tests to write

Python 3.14 is on the dev box and can *generate* expected results (the repo convention `docs/handoff.md` is "do not add Python": commit only the generated files, never a script that needs Python to run). The data-driven corpus: `tests/regex/cases.txt` (pattern, flags, text, expected group spans/replacement), 400+ cases across every syntax item above, including empty matches, nested quantifiers, backrefs, case-insensitive Unicode, `MULTILINE`/`DOTALL`, `split`/`sub`/`findall` on empty matches; a Tomato test reads the file and prints only mismatches plus a count (`ok 412/412`) — the program takes the repo root as an input like `toml_api` `[V]`. Plus: `re_errors` (every `RegexError` kind with `pos`, every unsupported construct), `re_api` (every method and field on both `Pattern` and the module functions), `re_limits` (catastrophic pattern `(a+)+$` on 30 `a`s then `b` hits the step limit in under 2 s; `.*` on a 200,000-character line does not overflow the call stack; a 1 MB text `findall` finishes), `re_fuzz` (random valid patterns and texts compared **between** `match`, `search` and `fullmatch` for internal consistency, no Python at runtime), the ASan list gets `re_api` and `re_limits`, one browser run (`re_api`) in the wasm list.

### 3.7 Size, dependencies, state, closures

Size **L**, 1,800–2,800 lines of Tomato plus the corpus. Build in four independently reviewable steps: (1) parser to program and matcher for literals, classes, groups, quantifiers, anchors, alternation; (2) backreferences, lookaround, flags, Unicode classes and case folding; (3) `Match`, `Pattern`, `sub`, `split`, `findall`; (4) the corpus and the limits. Sonnet alone if the syntax subset above is approved and the oracle corpus exists, as the roadmap said. **Depends on:** nothing in the other packs; Wave 1's `isalnum` is not needed (the engine uses the runtime's character tables through existing `isalpha`/`isdigit`). **Module state: none** (the no-cache consequence is stated above). **Closures:** `sub_with` takes a named function; documented.

### 3.8 Questions for Davis (in order)

1. **C-Q1 `Match` result types.** `match`/`search`/`fullmatch` return `Match | None` (Python-like); `group()` returns `str` with `''` for a non-participating group and `matched()` tells them apart (recommended). Alternative: `group() -> str | None` exactly like Python, which makes every caller narrow it.
2. **C-Q2 `findall` and `split` shapes.** Python returns `str`s, tuples or lists depending on group count, which a static type cannot express. Proposal: `findall` returns whole matches (`list[str]`), `findall_groups` returns `list[list[str]]`, `split` includes group texts with `''` for non-participating groups. OK?
3. **C-Q3 `\d \w \s` and case rules.** Unicode-aware like Python for `str` patterns, using the runtime's `isdigit`/`isalpha` tables (recommended, documented difference: those tables include some non-decimal digits that Python's `\d` excludes), or ASCII-only unless a flag asks for Unicode. A third option adds an exact decimal-digit table to the runtime (C, wasm rebuild).
4. **C-Q4 Step limit.** A per-`Pattern` limit raising `RegexError` (recommended) or Python's unbounded behavior.
5. **C-Q5 Names and no cache.** `RegexError`; `re.compile` first, module functions recompile each call; flag constants with Python's values and one-letter aliases. OK?
6. **C-Q6 Syntax boundary.** Is the supported list above (stage 1 and 2) right — in particular lookbehind and `VERBOSE` in stage 2, possessive/atomic/conditionals out?

---

## 4. Pack D — hashing and binary helpers: `hashlib`, `hmac`, `zlib` checksums, `struct` (roadmap #12). Size M (pure Tomato; floats in `struct` need two C helpers)

Why: checksums, content addressing, signing requests, JWT and cookies for a future server, verifying downloads. All APIs use `list[int]` bytes (decided) and the X1 text helpers (section 0.3).

### 4.1 Modules (**Davis D-Q1**)

Flat modules with Python names: `hashlib`, `hmac`, `zlib` (only the checksums `crc32` and `adler32` in v1; `compress`/`decompress` are roadmap "later", so the module will grow rather than be renamed), `struct`. Hex output is lowercase text; `hex.encode/decode` from Wave 1 is the same format, but the hash modules produce their hex themselves so they do not depend on it.

### 4.2 `hashlib`

```
class Hash:                       # one class; the algorithm is data, so every function takes any Hash
    name: str                     # 'sha256', 'sha1', 'md5', 'sha224'
    digest_size: int              # 32, 20, 16, 28
    block_size: int               # 64
    update(data: list[int]) -> None
    update_text(text: str) -> None          # utf8.encode(text), then update
    digest() -> list[int]                   # does not change the object; more updates may follow
    hexdigest() -> str
    copy() -> Hash

sha256(data: list[int] = []) -> Hash
sha224(data: list[int] = []) -> Hash
sha1(data: list[int] = []) -> Hash
md5(data: list[int] = []) -> Hash
new(name: str, data: list[int] = []) -> Hash              # ValueError on an unknown name
sha256_hex(data: list[int]) -> str                        # one-shot shortcuts, also sha1_hex, md5_hex
pbkdf2_hmac(hash_name: str, password: list[int], salt: list[int], iterations: int, dklen: int = 0) -> list[int]
file_hexdigest(path: str, algorithm: str = 'sha256') -> str     # optional; needs pack A's os.read_bytes
```

- Python's constructors take the first chunk of data; same here (the `[]` default is a literal default, not an alias; builders verify a list default compiles, otherwise two overloads by name are used and reported).
- `data` values outside 0–255 raise `ValueError` (checked per `update` call). `iterations < 1`, `dklen < 0` raise `ValueError`; `dklen == 0` means the hash's digest size (Python's `None`).
- **Algorithms in v1** (**D-Q4**): SHA-256, SHA-224, SHA-1, MD5, all with published vectors. **Not in v1:** SHA-512/384, SHA-3, BLAKE2: they use 64-bit modular arithmetic, and a Tomato `int` is a tagged word with heap numbers above about 2^62 `[V]` (D67a: `&`, `|`, `^` need word-sized values), so a pure-Tomato version would emulate 64-bit words with 32-bit pairs (slow) or want a C implementation. Add with a C helper when Davis asks. `md5` and `sha1` are weak: the documentation says so; no refusal, no `usedforsecurity` parameter (Davis may want a warning).
- Hash state is `list[int]` of 32-bit words masked with `& 0xFFFFFFFF` after each add (works in tagged small ints `[I]`, `next-features.md` section 3, fact 7). The message-length counter is an ordinary `int` (unlimited).
- **Performance `[I]`:** a few MB/s in pure Tomato, enough for small inputs and tokens, slow for a 100 MB file. Pure Tomato first, **measured by the builder and reported**; a C `tomato_sha256_block` behind the same API is the fix if Davis wants it (**D-Q5**).

### 4.3 `hmac`

```
hmac.digest(key: list[int], msg: list[int], digestmod: str) -> list[int]
hmac.hexdigest(key: list[int], msg: list[int], digestmod: str) -> str
class HMAC: HMAC(key: list[int], digestmod: str); update(data), digest(), hexdigest(), copy()
hmac.compare_digest(a: list[int], b: list[int]) -> bool
```

`digestmod` is the algorithm name text (class values cannot be passed, and Python also accepts names); an unknown name raises `ValueError`. Keys longer than the block size are hashed first; shorter are zero padded (RFC 2104). `compare_digest` has no early exit and compares lengths without leaking position, but Tomato integer operations are not guaranteed constant time `[I]`, and the documentation says so rather than claiming it (**D-Q8**).

### 4.4 `zlib` checksums

```
zlib.crc32(data: list[int], value: int = 0) -> int       # 0 .. 2**32 - 1, Python 3 semantics
zlib.adler32(data: list[int], value: int = 1) -> int
```

`value` carries a running checksum across chunks (`crc32(b, crc32(a)) == crc32(a + b)`). `crc32` is table-driven; with no module-level tables (D47a) the 256-entry table is built per call (about 2,000 operations: negligible above a few KB, noticeable for millions of tiny calls) — the builder may instead hold it in a `class CRC32` object, which would be an additional name.

### 4.5 `struct` and integers (**Davis D-Q3**)

Python's `struct.pack(fmt, *values)` takes a heterogeneous list of values. **Tomato lists are homogeneous and has no heterogeneous varargs** `[V]` (D39a: `*args: tuple[T]` is one type), so the exact Python API cannot be typed. Proposal: three pieces.

1. **Format-string functions for the integer-only case** (the common one: headers, ports, lengths):
   - `struct.pack_ints(fmt: str, values: list[int]) -> list[int]`, `struct.unpack_ints(fmt: str, data: list[int]) -> list[int]`, `struct.calcsize(fmt: str) -> int`.
   - Format: optional byte-order character first (`<` little, `>` big, `!` network = big, `=` and `@` native = little on every supported platform, so the output is platform independent), then codes `x` (pad byte, consumes no value), `b B h H i I l L q Q` with Python's **standard sizes** (1, 1, 2, 2, 4, 4, 4, 4, 8, 8; no native alignment, so `@` equals `=`) and a repeat count (`3H`). Out-of-range values raise `OverflowError` with Python's wording idea ("does not fit"); a wrong value count, a bad code or a too-short buffer raises `ValueError` (Python raises `struct.error`: Tomato adds `class StructError(ValueError)`, **D-Q3**). `unpack_ints` requires exactly `calcsize` bytes (Python's rule).
2. **`Packer` / `Reader` objects** for mixed layouts: `Packer(byteorder: str = '>')` with `u8 u16 u32 u64 i8 i16 i32 i64 (value: int)`, `f32 f64 (value: float)`, `raw(data: list[int])`, `text(value: str)` (UTF-8, no terminator), `bytes() -> list[int]`; `Reader(data: list[int], byteorder: str = '>')` with `read_u8 … read_i64`, `read_f32`, `read_f64`, `read_raw(n: int) -> list[int]`, `read_text(n: int) -> str`, `remaining() -> int`, `pos: int`. Reading past the end raises `ValueError` and does not advance. This is type-safe, needs no new language feature, and is what a binary protocol writer actually wants.
3. **Integer conversion functions** replacing Python's methods (`int` has a fixed method set `[V]`): `struct.int_to_bytes(value: int, length: int, byteorder: str = 'big', signed: bool = False) -> list[int]` and `struct.int_from_bytes(data: list[int], byteorder: str = 'big', signed: bool = False) -> int`. `OverflowError` when the value does not fit; any length works (the `int` is unlimited), so this is also how big integers meet bytes.

**Floats (D-Q5).** `f32`/`f64` need IEEE 754 bit patterns. A Tomato implementation from `math` is slow and fragile (NaN payloads, -0, subnormals); two small C helpers (`tomato_f64_bits(x) -> int` as two 32-bit halves, `tomato_bits_f64`) are exact, and with them `f32` is a conversion. Cost: a *runtime change*, batched with pack A's wasm rebuild. Without Davis's yes, `struct` ships without floats and says so.

### 4.6 Native versus browser

All pure Tomato: identical natively and in the browser, no wasm rebuild, except the optional float helpers (WASI-safe C, no OS calls). `file_hexdigest` uses pack A and has the same availability as `os.read_bytes`.

### 4.7 Tests to write

Official vectors are mechanical: SHA-256/224/1 and MD5 empty, `abc`, the 448-bit and 896-bit NIST messages, `'a' * 1_000_000` (SHA-256 `cdc76e5c…`), plus every length 0–200 against digests generated by Python's `hashlib` and committed as expected output; incremental `update` in every split of a 200-byte message equals the one-shot digest; `copy()` independence; `digest()` can be called twice and does not disturb later `update`; HMAC RFC 2202 (MD5, SHA-1) and RFC 4231 (SHA-224, SHA-256) vectors including keys longer than the block; PBKDF2 RFC 6070 (SHA-1) and the SHA-256 vectors, small iteration counts; `crc32('123456789') == 3421780262` and `adler32('Wikipedia') == 0x11E60398`, chunked equals whole, values 0 and 2**32-1 boundaries; `struct`: every code at its minimum, maximum and out-of-range value in both byte orders (generated from Python), `x` padding, repeat counts, bad format strings, short and long buffers, `Packer`/`Reader` round trip and the error cases, `int_to_bytes`/`int_from_bytes` signed and unsigned, 0, 255, 256, -1, 2**64, lengths 0–16; byte validation (`[256]`, `[-1]`) leaves state unchanged. A timing line is printed (not asserted) so MB/s is on record. ASan list: `hashlib_vectors`, `struct_ints`. Wasm list: `hashlib_vectors`, `hmac_vectors`, `zlib_checksums`.

### 4.8 Size, dependencies, state, closures

Size **M**: about 900 lines of Tomato (each hash 100–200, HMAC and PBKDF2 60, checksums 50, `struct` 300, `utf8` 40) plus tests; every algorithm is mechanically checkable, an ideal Sonnet task. **Depends on:** X1 (`utf8.encode`, for `update_text`), Wave 1's nothing; optionally pack A for `file_hexdigest`. **Wave 1's `uuid5` depends on this pack's SHA-1** (D-Q7). **Module state: none**; tables are rebuilt per call or held in objects. **Closures: none needed.**

### 4.9 Questions for Davis (in order)

1. **D-Q1 Modules.** Four flat Python-named modules with `zlib` holding only `crc32`/`adler32` for now (recommended), or a differently named checksum module?
2. **D-Q2 Hash API shape.** Constructor functions returning one `Hash` class, plus `*_hex` one-shots (recommended).
3. **D-Q3 `struct` design.** Integer format-string functions + `Packer`/`Reader` + `int_to_bytes`/`int_from_bytes` (recommended), versus holding `struct` until heterogeneous varargs exist. Also: add `StructError(ValueError)`?
4. **D-Q4 Algorithms.** SHA-256/224, SHA-1, MD5 now; SHA-512, SHA-3, BLAKE2 later with a C helper (recommended).
5. **D-Q5 Speed and floats.** Pure Tomato first, measure, add a C block function only if too slow; `struct` floats via two C helpers in this wave's one wasm rebuild (recommended), or no floats.
6. **D-Q6 X1 text helpers.** Name and home of `str ⇄ list[int]` (section 0.3).
7. **D-Q7 Wave 1 uuid5.** Private SHA-1 copy in the uuid module until `hashlib` lands (recommended), or wait.
8. **D-Q8 Weak primitives.** Docs-only warning for `md5`/`sha1`; `compare_digest` documented as best-effort constant time (recommended), or refuse/flag them.

---

## 5. Summary table

| Pack | Size | Runtime C | Compiler | Browser | Needs | Davis questions |
| --- | --- | --- | --- | --- | --- | --- |
| A `os`/`sys`/paths/files v2 | M | yes (about 16 entry points) | yes, small (`File` methods, `for line in f`, `*args` entry) | subset (host calls to add, A-Q8) | none | 9 (A-Q1 to A-Q9) |
| B testing | M | optional, 1 helper | yes (`assert`, repeatable `@test`, driver) | library and driver yes, `tomato test` native | A (`sys.exit`), after Wave 1's compiler work | 6 (B-Q1 to B-Q6) |
| C `re` | L | none | none | identical | none | 6 (C-Q1 to C-Q6) |
| D hashing/binary | M | optional (float bits, X1 helpers) | none | identical | X1; A optional | 8 (D-Q1 to D-Q8) |
| X1 `utf8` text helpers | S | optional (2 helpers) | none | identical | shared with sockets | decided inside D-Q6 |

**Suggested order:** start **C and D now** in parallel (pure Tomato, no shared C or compiler files), then **A**, then **B** (after Wave 1's compiler subtasks land), with one batched wasm rebuild at the end covering A's runtime, D's float helpers, X1 and B's compiler change.

## 6. Not in this wave (so nobody builds them by accident)

`pathlib.Path`, `shutil`, `tempfile`, `glob`, `fnmatch`, `os.walk`, `realpath`, `subprocess`, `signal`; async file I/O; `open(path, 'rb')` and a `bytes` type; `zlib.compress/decompress`, `gzip`, `tarfile`; SHA-512/384/3, BLAKE2; `unittest`-style class tests, fixtures, parametrization, mocking, doctest, coverage; regex possessive/atomic/conditional constructs; `hash()` (deferred in Wave 1). The roadmap section 6 lists each as later or skipped, with the reason.
