# What Tomato should build next: standard library and user-facing features

Status: a research and planning document, written against `main` at `812244d` (the v0.51 release commit; `VERSION` still says 0.50). Nothing in it is decided: Davis decides every API and language rule, so each item below is a proposal that needs his answer on its API before a builder starts. The last section lists the decisions that unblock the most work.

**How to read the evidence marks.** `[V]` means I read it in this repo (file and line are given where it matters). `[I]` means I inferred it from what I read, or from general knowledge of Python or of C, LLVM and WebAssembly. **I could not run anything**: this box has no `clang`, `tomato` or `node`, so no program, test or benchmark was executed for this document. Every `[V]` is a statement about source text, not about observed behavior.

Scope: practical features and standard-library gaps. Compiler internals and language design are the subject of `docs/architecture-review.md` (another agent); I touch the compiler only where a library feature needs it. At the time of writing neither sibling branch (`byre/tskCEya4wv7eaq`, `byre/tskp06ef0bADM6`) has a commit beyond `main` `[V]`, so I could not check for overlap; items 1, 3 and 14 involve compiler work and are the likeliest to overlap.

---

## 1. Summary

- Tomato's standard library is small and well made: `math`, `rational`, `itertools` (eager, list-based), `cache`, `bitarray`, `json` (+ MessagePack), `toml`, `time`, `requests` (11 files in `std/`, about 4,650 lines) `[V]`. The runtime has **no** environment, argv, exit, random, file-system, process or socket access beyond `open(path).read()/write()/close()` and one libcurl-based HTTP client `[V]`.
- The biggest practical gaps for someone who knows Python are, in order: everyday built-ins (`round`, `divmod`, `any`, `all`, f-string format specs, `ljust`, `splitlines`, `floor`), operating-system access (`os`/`sys`/`pathlib`), a way to write tests, `random`, `re`, and anything that listens on a socket.
- **Networking is worth doing, but as a staged chain, not one task.** Davis's founding requirement R09 is "support web servers" `[V]` (`docs/specification.md`), and today a Tomato program cannot accept a connection at all `[V]`. The chain is: URL and encoding helpers (S) → async toolkit with timeouts (M) → a scheduler hook that waits on file descriptors plus a socket module (L, runtime) → an HTTP server (L). Only the first link is cheap, and the middle two should not be given to a Sonnet agent alone (section 6).
- Cheapest wins are pure-Tomato modules: no runtime change, so they work in the browser playground for free and do not force a WebAssembly rebuild, which only the release Mac can do reproducibly `[V]` (`TODO.md`, last item; `docs/releasing.md`; commit `812244d`).
- Five language-level facts shape every standard-library API here (section 3): no `bytes` type, ~~dict keys are text only~~ (dict keys can be any hashable type since D78a), no module-level mutable state, no closures, no `with`. Several decisions below (section 8) are really about those.

---

## 2. Inventory: what exists today

### 2.1 Standard library modules (`std/`) `[V]`

| Module | Lines | What it gives | Notes |
| --- | --- | --- | --- |
| `builtin/` (folder) | 718 in 7 files | `Error` and subclasses (`RuntimeError`, `IndexError`, `KeyError`, `ValueError`, `ZeroDivisionError`, `OverflowError`, `IOError`, `EOFError`, `CancelledError`), the `range` class, the stable merge sort behind `sorted`, `map`, `filter`, text helpers | imported by every program (D22a); `errors`, `range`, `numbers`, `text`, `sorting`, `lists`, `format` (see D24a) |
| `math` | 591 | integer helpers (`gcd`, `lcm`, `pow`, `is_prime`, `next_prime`, `prev_prime`, `primes_up_to`, `nth_prime`, `prime_factors`, `factorize`, `totient`, `is_coprime`), constants `pi`, `tau`, `e`, an `Angle` type with `Degrees`/`Radians`/`Turns`/`Gradians`, `sin cos tan asin acos atan atan2 sqrt cbrt hypot exp expm1 log log_base log2 log10 log1p sinh cosh tanh asinh acosh atanh` | Deliberately not Python's API: trig takes an `Angle`. **Missing**: `floor`, `ceil`, `trunc`, `round`, `isnan`, `isinf`, `isfinite`, `copysign`, `fmod`, `factorial`, `comb`, `perm`, `isqrt`, `fsum`, `prod`, `dist`, `lgamma`, `erf` |
| `rational` | 63 | exact fractions (`rational(n, d)`), `+ - * /`, comparisons | thin: `to_float()` is the only conversion; no construction from a float or text, no `limit_denominator`, floor/round, `**`, or mixed arithmetic with `int` (every operator takes a `rational`) |
| `itertools` | 156 | `permutations`, `combinations`, `combinations_with_replacement`, `product`, `product_repeat`, `accumulate`, `chain` (two lists), `pairwise`, `batched`, `repeat`, `progress_bar` | **eager and list-based**: every function builds and returns a full list. No `count`, `cycle`, `islice`, `takewhile`, `dropwhile`, `groupby`, `zip_longest`, `starmap`, `tee`, `chain.from_iterable` |
| `cache` | 652 | `Cache[K1, ..., R]` (LRU, one to four key parts and the result; optional TTL and an injectable clock), `Memo`, `memoize(f, capacity)` for functions of one to four parameters | `memoize` returns a `Memo` object used as `m.call(x, y)` "because there are no closures to return a function" (D62a); the cache is hand-written once per number of key parts because there are no variadic type parameters (D62b) |
| `bitarray` | 551 | `bitarray`, `frozenbitarray` (D64a) | `std/builtin/bitarray.tom`, loaded when used |
| `json` | 598 | JSON (strict RFC 8259) and MessagePack, as a `Json` class hierarchy; `loads/dumps/load/dump` plus `*_msgpack` | typed access (`j['a'][0].as_int()`), no automatic conversion to plain dicts/lists |
| `toml` | 1110 | TOML v1.0.0 read and write, as a `Toml` value, with its own `Moment` date/time type | `inf`/`nan` kept as text; Python's `tomllib` is read-only, so this is a superset |
| `time` | 307 | `time`, `time_ns`, `monotonic`, `monotonic_ns`, `Time` (struct_time), `gmtime`, `mktime`, `timegm`, `strftime`, `asctime`, `ctime`, `isoformat`, `format_duration`, `Stopwatch` | UTC only, no `strptime`, no `localtime`, no `sleep` (use `await sleep()`). `TODO.md` still lists "Add a `time` module" even though `std/time.tom` and `tests/programs/time_module.tom` exist (commit `bbb9cd3`): its TODO entry was removed with this document |
| `requests` | 259 | async `get/post/put/patch/delete/head/request`, `Response` (`status`, `ok`, `url`, `text`, `headers`, `content`, `json()`, `raise_for_status()`), a `RequestError` family, `quote` | native only: the runtime `dlopen`s **libcurl** at the first request (`runtime/tomato_rt.c:2212-2271`); in the browser every call raises `ConnectionError`. `Response.content` is copied one byte per runtime call (comment in `requests.tom`), so large downloads are slow. No sessions, cookies, auth helpers, streaming, uploads of bytes |
| `errors.txt` | 389 | the numbered error-message table (E01...) | every new library error needs a line here |

### 2.2 Built-ins in the compiler/runtime `[V]`

- Callable built-ins: `print`, `len`, `str`, `int`, `float`, `open`, `input` (async, one line), `sleep` (async), `clock`, `range`, `list(x)`, `sorted`, `reversed`, `sum`, `min`, `max`, `abs`, `chr`, `ord`, `map`, `filter` (`compiler.tom:3812-3875`). `enumerate` and `zip` are recognized only as the iterable of a `for` loop (`parser.tom:32, 700`). `compiler.tom:5594` lists names the compiler answers with "is not built in": `round`, `pow`, `divmod`, `any`, `all`, `dict()`, `set()`, `tuple()`, `bool()` as calls, `type`, `isinstance`, `hash`, `format`; `reduce` is refused with "use a for loop instead".
- Text methods: `find rfind count startswith endswith replace split join upper lower strip lstrip rstrip isdigit isalpha isspace` only (`compiler.tom:5605`). **Missing** versus Python: `splitlines`, `partition`, `rpartition`, `rsplit`, `zfill`, `ljust`, `rjust`, `center`, `title`, `capitalize`, `swapcase`, `isalnum`, `isupper`, `islower`, `removeprefix`, `removesuffix`, `expandtabs`, `encode`, `format`.
- Containers: `list` (`append pop insert extend sort reverse`), `dict` (`get remove keys values items`), `set` (`add remove discard`), `tuple`, `range`, slicing, list comprehensions with one `for` clause.
- Files: `open(path, mode)` returns a `File` with only `read()` (whole file as text), `write(text)` and `close()`; `/dev/stdout` and `/dev/stderr` can be opened (`tests/programs/std_streams.tom`). `std/json.tom` reads and writes byte files through two internal runtime helpers; there is no user-facing bytes API ("A user-facing bytes file API ... is not built", `docs/decisions.md:1546`).
- Language features library authors use: generics (`class Box[T]`, `def f[T]`), interfaces, operator methods (`@add`, `@eq`, `@lt`...), `@iter` generators with `yield`, `async`/`start`/`await`, `try/catch/finally`, unions (`int | str`) with narrowing, mixed tuples, keyword and default arguments, lambdas (non-capturing), function values `fn(int) -> int`.
- Runtime: reference counting with a cycle collector, a cooperative single-thread scheduler (`tomato_sched_idle`, `runtime/tomato_rt.c:2491`), 189 distinct `tomato_*` runtime entry points.

### 2.3 Tests, examples, tools `[V]`

- `tests/run.sh` (needs clang; also runs WebAssembly checks through `jsc` or `node` when present), 125 programs in `tests/programs/` with expected-output files, 56 negative programs, 38 runtime-failure programs, `tests/known_gaps/`. `tests/http_server.c` is a tiny C HTTP server the `requests` tests start on a free port, so the requests tests need no internet.
- Examples (`examples/`, 16 files): `args`, `ask`, `compiled`, `config` (TOML), `features`, `http_get` (requests + `start` for overlap), `iteration`, `json_tool`, `lru_cache`, `mathlib` (+ LLVM IR), `objects`, `primes`, `shapes`, `tasks`, `trig`.
- Benchmarks: `fib`, `sieve`, `matmul`, `mandelbrot`, `collatz`, `strings`, `sort`, `wordcount`, `bigint`, `objects`, each also in Go, Rust and Python; `jsonbench` for JSON.
- The `tomato` command: `run`, `build`, `compile`, `explain`, `repl`, `update`, `version`, `help`. No `test`, `fmt`, `doc` or package command. Entry points (`@main`, `@greet`...) take typed inputs from the command line (`examples/args.tom`), which gives a lightweight argparse for free.
- Distribution: a std module is "installed" by existing in `std/`: `release/build.sh` and `install-native.sh` copy `std/*.tom`; the browser build has a hardcoded module list in `site/wasm/tomato.js:17` that must also be edited `[V]`.

---

## 3. Facts that shape every library API (all `[V]` unless marked)

1. **No `bytes` type.** Binary data is `list[int]` (`loads_msgpack(data: list[int])`, `Response.content: list[int]`). `open` is text only. Hashing, compression, sockets and binary files all need a decision here (D3 below). Lists have compact typed storage (`docs/performance.md` "compact list storage"), so `list[int]` is not as wasteful as it sounds, but it is still not a distinct type with its own literals, slicing semantics or `encode`/`decode`.
2. **Dict keys were text only (built since D78a: any hashable type).** The text below describes the compiler before D78a. The compiler checks every dict key with `self.want(..., 'str', ..., 'a dict key')` (`compiler.tom:3130, 3147, 3281, 4577, 4634, 5872`) and prints dict types as `dict[str, V]` (`compiler.tom:387`). Sets can hold `str`, `int` and `bool` (`compiler.tom:3100`). This blocks `Counter` of ints or tuples, `defaultdict(int)` keyed by number, graph algorithms keyed by node ids, caches keyed by tuples, and a general `collections` module.
3. **No module-level state.** "No top-level code" (D47a), and `std/time.tom` says "the language has no top-level values" (the month names are split out of a text on each call). Only `export const x = literal` exists. So Python's idiom of a hidden module-level object (`random.random()`, `logging.info()`, `sys.argv`, a root logger, a shared `Random()`) has no direct home. Options in D2.
4. **No closures.** Lambdas are non-capturing; bound methods and generic functions cannot be values (`docs/decisions.md:1518`). This rules out `functools.partial`, `lru_cache` as a decorator, decorator-style routers (`@app.route`), `re.sub` with a capturing callback, `contextlib.contextmanager`. Callbacks must be named functions or objects implementing an interface; class-based handlers (an `interface` with an `async` method) work.
5. **No `with` statement** (the keyword list in `compiler/src/lexer.tom:44-47` has no `with`, `assert`, `del`, `global`, `match`, `lambda`; lambdas use `x -> expr`). Resource cleanup is `try/finally`. It is unknown whether a dropped `File` is closed by reference counting `[I]`.
6. **Concurrency is cooperative and single-threaded** (tasks switch only at `await`). `tomato_sched_idle` handles sleepers, queued `input()` lines (native: polling stdin in the same wait), sockets and libcurl transfers (via `curl_multi_poll`) and nothing else. Anything that waits on a socket, a pipe or a child process needs a new kind of waiter in that function, in the cancellation code (`tomato_task_cancel` removes a task from whatever it waits in) and in the WebAssembly runtime.
7. **Integers**: small ints are one tagged machine word, larger ones heap numbers (README). Algorithms with 32-bit words (SHA-256, MD5, CRC32, Adler) fit in a small int if masked with `& 0xFFFFFFFF` after each step `[I]`. 64-bit algorithms (xoshiro, SHA-512, FNV-64) overflow into heap numbers or hit fixed-width overflow errors, so they are slow or need C `[I]`.
8. **Two targets.** The browser playground runs the same C runtime compiled to WebAssembly (`site/wasm/build.sh`) plus an IR interpreter in JS. Files there live in the page's memory (`docs/decisions.md:1546`). Sockets, subprocesses and libcurl do not exist there; the precedent for such features (`requests`) is to raise a clear runtime error `[V]`.
9. **Every runtime C change requires re-building `site/wasm/*.wasm`**, and the release gate compares those files byte for byte with the macOS WASI SDK 24 build (`TODO.md` last item; `docs/releasing.md`). A pure-Tomato std module needs only the copy of `std/*.tom` and the `STD` list line. This is the main reason pure-Tomato modules rank above runtime-backed ones at equal value.
10. **The project's own working method**: "He decides all language semantics" (`docs/handoff.md`); the `time` module was held back for an API decision before it was built (the old TODO entry). Every item below therefore has an API-decision step before a builder starts. Each new module also needs: tests in `tests/programs` with `tests/expected/NAME.main.out` and a line in `tests/programs.txt`, error lines in `std/errors.txt`, a bullet in `docs/specification.md`, an entry in `docs/decisions.md`, and the `site/wasm/tomato.js` list `[V]` (`docs/handoff.md`, `tests/run.sh`).

---

## 4. Python standard library mapped to Tomato

Source: `python3 -I -c 'import sys; print(sorted(sys.stdlib_module_names))'` on this box, Python 3.14.4: 194 public (non-underscore) module names. Every one appears below. Legend: **present** = Tomato has it; **partial** = some of it; **WANT(#n)** = missing but valuable, with its rank in section 5; **later** = valuable but outside the first 15; **skip** = missing and not worth building. Statuses `[V]` for "present/partial" (read from `std/`), `[I]` for value judgments.

### 4.1 Networking and the web

| Python module(s) | Status | Notes |
| --- | --- | --- |
| `socket`, `select`, `selectors` | **WANT(#9)** | TCP and UDP client/server sockets; needs a file-descriptor waiter in the scheduler. Native only |
| `socketserver` | skip | superseded by async sockets |
| `http` (`http.client`, `http.server`, `http.cookies`, `http.cookiejar`) | partial: client via `requests`; **WANT(#10)** server | `requests` covers the client side well enough; cookies/sessions are a gap (later). The server is the R09 requirement |
| `urllib` (`parse`, `request`, `error`, `robotparser`) | **WANT(#5)** `urllib.parse` (`urlparse`, `urlencode`, `quote`, `unquote`, `parse_qs`, `urljoin`); `urllib.request` covered by `requests`; skip the rest | `requests.quote` and a private `_form` already exist and would move here |
| `ssl` | skip | TLS for clients comes from libcurl. Server-side TLS: put a reverse proxy in front [I] |
| `asyncio` | partial: `async`/`start`/`await`, `sleep`, `cancel`, `done`; **WANT(#8)** `gather`, timeouts (`wait_for`), `Queue`, `Event`, `Lock`, `cancelled()`; streams come with #9 | spec: timeouts and `t.cancelled()` are "not yet" |
| `ipaddress` | later | small, pure; useful with sockets |
| `email`, `smtplib`, `imaplib`, `poplib`, `ftplib`, `xmlrpc`, `mailbox`, `netrc`, `wsgiref`, `webbrowser` | skip | |
| `html` | **WANT(#5)** `escape`/`unescape` only (needed for any server that renders HTML); `html.parser` later | |
| `mimetypes` | later | needed for static files in #10 |
| `json` | present (`json`) | no automatic mapping to dict/list; `dumps`/`loads` OK |
| `xml` (`xml.etree`, `xml.dom`, `xml.sax`, `pyexpat`) | later | an XML parser is M/L, valuable mainly for feeds and config; not before the web chain |

### 4.2 System: `os`, files, processes

| Python module(s) | Status | Notes |
| --- | --- | --- |
| `os`, `posix`, `nt`, `posixpath`, `ntpath`, `nturl2path`, `genericpath`, `sys`, `errno`, `stat`, `platform`, `getpass`, `pwd`, `grp`, `resource`, `fcntl`, `winreg`, `msvcrt`, `winsound` | **WANT(#2)** `os`/`sys` basics: `argv`, `environ`/`getenv`, `exit`, `getcwd`, `listdir`, `mkdir`, `remove`, `rename`, `stat`, `exists`, `isfile`, `isdir`, `getpid`; the rest skip | Tomato has **none** of these today `[V]`; only file `read`/`write`/`close` exist |
| `pathlib` | **WANT(#2)** as functions (`join`, `basename`, `dirname`, `splitext`, `exists`) or a small `Path` class | decision: functions vs class |
| `shutil`, `tempfile`, `glob`, `fnmatch`, `filecmp`, `fileinput`, `linecache` | `shutil.copy`/`rmtree`, `tempfile`, `glob`, `fnmatch`: **later** (after #2); the rest skip | tests currently use `mktemp -d` in the shell |
| `io` | **WANT(#2)** line iteration and `readline`, append and binary modes, `StringIO`; `BytesIO` with a bytes decision | |
| `subprocess`, `pty`, `tty`, `termios`, `signal`, `atexit` | **WANT(#15)** `subprocess.run`/`Popen` basics; `signal` (Ctrl-C for servers) later; others skip | native only |
| `shlex` | later | small, with subprocess |
| `curses`, `readline`, `rlcompleter`, `cmd`, `code`, `codeop` | skip | |
| `threading`, `multiprocessing`, `concurrent`, `queue`, `sched`, `contextvars` | skip (`queue` as an async `Queue` is in #8) | the concurrency model is cooperative tasks (D13/D51); threads are a language decision, not a library one |
| `ctypes`, `mmap`, `faulthandler`, `gc` | skip | FFI exists as `!name(...)` declarations in std modules only (D27b) |

### 4.3 Text and data formats

| Python module(s) | Status | Notes |
| --- | --- | --- |
| `re`, `sre_compile`, `sre_constants`, `sre_parse` | **WANT(#6)** `re` | the largest "I cannot write my scripts without it" gap after OS access |
| `string` | partial (built-in str methods) / **WANT(#1,#7)**: character-class constants (`ascii_letters`, `digits`, `punctuation`...) are `export const` and trivial; `Template` skip | |
| `textwrap`, `pprint`, `reprlib`, `difflib`, `stringprep`, `unicodedata`, `codecs`, `encodings`, `locale`, `gettext` | `textwrap` **WANT(#7)**; `pprint` later (printing nested lists is possible but ugly); `difflib` later; `unicodedata`: partial (full-Unicode `isalpha`/`isdigit`/case mapping in the runtime, D17d); others skip (text is UTF-8 only by D17b) | |
| `csv` | **WANT(#7)** | pure Tomato, small |
| `json` | present | |
| `tomllib` | present (`toml`, read and write) | |
| `configparser`, `plistlib` | skip | TOML and JSON cover configuration |
| `pickle`, `pickletools`, `copyreg`, `shelve`, `dbm`, `marshal` | skip: MessagePack (present) is the safe serialization; `pickle` loads arbitrary code | `copy` (see 4.5) is separate |
| `struct`, `array`, `binascii`, `quopri` | `struct`, `binascii.hexlify`/`unhexlify`: **WANT(#5, #12)**; `array` partial via typed `list`/`bitarray`; `quopri` skip | needs the bytes decision |
| `base64` | **WANT(#5)** | |
| `sqlite3` | **WANT(#13)** | `dlopen` libsqlite3 like libcurl; native only |
| `xml`, `pyexpat` | later (see 4.1) | |

### 4.4 Numbers and math

| Python module(s) | Status | Notes |
| --- | --- | --- |
| `math` | partial `[V]` | add `floor ceil trunc isnan isinf isfinite copysign factorial comb perm isqrt fsum prod` (#1). Trig on `Angle` is a deliberate difference |
| `cmath`, `numbers` | skip | |
| `fractions` | present as `rational` (thin) | |
| `decimal` | later | `int` is unlimited and `rational` exists; fixed-point money works as integer cents. A `Decimal` with context rounding is M/L |
| `statistics` | **WANT(#7)** `mean`, `median`, `mode`, `stdev`, `variance`, `quantiles` on `list[float]` | pure Tomato, small |
| `random` | **WANT(#4)** | |
| `secrets`, `uuid` | **WANT(#4)** | |
| `operator` | skip | no closures, so rarely needed |
| `bisect`, `heapq` | **WANT(#14)** | pure Tomato generic code, S, limited by `<` on generic `T` `[I]` |
| `graphlib` | later | topological sort, small |
| `array` | see 4.3 | |

### 4.5 Data structures and language-support modules

| Python module(s) | Status | Notes |
| --- | --- | --- |
| `collections` | partial: `cache.Cache` (LRU), `bitarray`; **WANT(#14)** `deque`, `Counter` (text keys), `OrderedDict` n/a (check whether `dict` keeps order `[I]` yes for JSON objects), `defaultdict` via a named factory; `namedtuple`/`ChainMap` skip | general `Counter`/`defaultdict` needed non-text dict keys (D5; built with D78a) |
| `itertools` | partial `[V]` (eager lists) | add lazy `count`, `cycle`, `islice`, `takewhile`, `dropwhile`, `groupby`, `zip_longest`, `starmap` as `@iter` generators; part of #14 |
| `functools` | partial: `memoize`/`Memo`; `reduce` refused by design | `partial`, `wraps`, `cached_property`, `singledispatch` need closures: skip |
| `dataclasses`, `enum` | **missing; language-level** | classes need hand-written `@init`, `@str`, `@eq` (see `std/builtin/range.tom`); enums/variants are an open design area (D08). High user value, but a design task for Davis, not a library task; listed in D5 below |
| `typing`, `types`, `abc`, `annotationlib`, `numbers` | skip / built in | Tomato is statically typed: generics, unions, `T | None` and interfaces are language features (`abc`≈`interface`, `Protocol`≈`interface`, `Optional[T]`≈`T | None`) |
| `copy` | later | classes are shared by reference (D05a); explicit cloning is an open design item |
| `weakref`, `gc`, `tracemalloc`, `inspect`, `dis`, `ast`, `symtable`, `tokenize`, `token`, `keyword`, `opcode`, `pyclbr`, `py_compile`, `compileall`, `modulefinder`, `runpy`, `importlib`, `pkgutil`, `zipimport`, `zipapp`, `site`, `sysconfig`, `venv`, `ensurepip`, `idlelib`, `builtins`, `__future__` | skip | Python-implementation details |

### 4.6 Time, hashing, compression, testing, tooling

| Python module(s) | Status | Notes |
| --- | --- | --- |
| `time` | present (`time`, UTC only) `[V]` | |
| `datetime`, `calendar`, `zoneinfo` | **WANT(#11)** `datetime` (`date`, `datetime`, `timedelta`, `fromisoformat`, `strptime`); `calendar` later; `zoneinfo` later (needs a decision on the "no time zones" rule) | the `time` module explicitly has no zones. `toml.Moment` is a second, separate date/time type to reconcile |
| `timeit` | later | `Stopwatch` already covers 90 percent |
| `hashlib`, `hmac` | **WANT(#12)** `sha256`, `sha1`, `md5`, `hmac`; `sha512`/`sha3`/`blake2` need 64-bit math (C) | needs the bytes decision |
| `zlib`, `gzip`, `bz2`, `lzma`, `compression`, `zipfile`, `tarfile` | `gzip`/`zlib` decode and `crc32`, `tarfile`: **later** (a pure-Tomato inflate is M); `bz2`, `lzma`, `compression.zstd` skip | no existing consumer in `requests` (libcurl decodes transparently `[I]`) |
| `unittest`, `doctest`, `test`-style tools | **WANT(#3)** testing support | see item 3; `doctest` skip |
| `logging`, `syslog`, `warnings`, `traceback` | `logging` **WANT(#7)** as explicit `Logger` objects (see D2); `syslog` skip; `warnings` skip (compiler has warnings); `traceback` skip (runtime errors already print a call trace, `docs/errors.md`) | |
| `argparse`, `optparse`, `getopt` | partial by design `[V]`: typed entry points give positional/keyword arguments and a usage message (`examples/args.tom`, `tomato_usage`). Missing: raw `argv`, flags, `--help` text per argument | covered by #2 (`argv`) |
| `pdb`, `bdb`, `trace`, `cProfile`, `profile`, `pstats`, `pydoc`, `pydoc_data`, `doctest`, `tabnanny`, `this`, `antigravity`, `turtle`, `turtledemo`, `tkinter`, `colorsys`, `wave`, `sched` | skip | |

---

## 5. What the examples, benchmarks and TODO.md imply

- **`TODO.md` (8 items) is all internals and release hygiene**: tag move, mandelbrot loop cost, tuple type parsing in expressions, printing mixed tuples in unions, LeakSanitizer CI, two error-path leaks, a `time` module (already built: stale), byte-identical wasm builds `[V]`. It says nothing about library needs, so library direction has to come from elsewhere. The stale `time` entry was removed when this document landed.
- **`examples/http_get.tom` and `tests/http_server.c`**: the project already built a test HTTP server, in C, and a client, in Tomato. That says HTTP is on the critical path and the next step is the mirror image (a server written in Tomato) `[I]`.
- **`examples/config.tom`, `json_tool.tom`**: configuration and JSON tooling are the demonstrated use. The missing companions are `csv`, regex and file/directory access `[I]`.
- **`benchmarks/wordcount`, `strings`**: text processing is a performance target; real word-count programs need `splitlines`, `readline` and `re`, none of which exist `[I]`.
- **Every benchmark has a Python twin and R11 says "faster than Python"**: Davis uses Python as the reference point `[V]`, so Python-shaped names should be the default unless D4's compat question goes the other way. The `math` module's `Angle` shows he will deviate when he has a better design `[V]`.
- **`std/requests.tom` header, `time.tom` header, spec status table "Not yet" column**: the spec lists the near-term known unbuilt rules: `float(x)` on text (P58), `dict.get(key)` returning None, f-string format options, set and dict comprehensions, several `for` clauses in comprehensions, async timeouts, `t.cancelled()`, `import toml` with `toml.loads(...)`; closures (spec table, "Function values" row) `[V]`. Those are language items that feed #1 and #8.
- **R09 and R10** (web servers; web apps with parts in WebAssembly) are the two requirements that no library item yet satisfies on the server side `[V]`.

---

## 6. Ranked next features

Ordering rule: value to a Python-literate user first, then "unblocks other items", then cost; pure-Tomato before runtime-backed at similar value. Sizes: **S** = under ~400 lines and a day or two for an agent; **M** = 400 to 1,500 lines, several days, may touch the runtime or compiler lightly; **L** = multi-part, scheduler/compiler/runtime work or a large new language area. "Sonnet alone" means a Sonnet agent can finish it from a written API once Davis approves, without help from a stronger agent.

Common to all items: an API decision step with Davis before building; tests in `tests/programs`; `std/errors.txt` lines; `docs/specification.md` and `docs/decisions.md` entries; an update to `site/wasm/tomato.js` STD list when a new std file appears; and, if the C runtime changes, a wasm rebuild on the release Mac.

### 1. Everyday built-ins and text/number polish: S to M

- **What**: `round(x, n)`, `divmod`, `any`, `all`, `hash`; text methods `splitlines`, `partition`, `rpartition`, `rsplit`, `zfill`, `ljust`, `rjust`, `center`, `title`, `capitalize`, `isalnum`, `removeprefix`, `removesuffix`; `math.floor ceil trunc isnan isinf isfinite copysign factorial comb perm isqrt fsum prod`; **f-string format specs** (`f'{x:.2f}'`, `f'{n:>5}'`, `f'{n:05d}'`, `f'{n:,}'`), which the spec lists as "not yet" `[V]`.
- **Why**: Every script that prints a number or aligns a column hits these within the first hour; they are the most visible "this is not Python" friction `[I]`. Nothing else in the list can be written comfortably without them (for example `csv` output, tables, `logging` formats).
- **Size**: text methods and `math` additions S (helper in `std/builtin/` (`text.tom`, `numbers.tom`) plus a dispatch line in the compiler, the way `isspace` is done `[V]`: `_str_isspace` in `builtin/text.tom`, listed in `compiler.tom:5605`); format specs M (parser and compiler).
- **Dependencies**: compiler (name table, method dispatch, f-string parse), `std/builtin/`; bootstrap IR must be regenerated (`compiler/bootstrap/refresh.sh`, needs clang). Works the same in wasm. No runtime change except possibly `round`/`floor` on floats (`libm`, already linked `[V]`: `<math.h>` included).
- **Risk**: low for methods and math; medium for format specs (grammar is a language decision: how much of Python's mini-language, and `round` half-even vs half-up).
- **Sonnet alone**: yes for the methods and the `math` additions; format specs yes once Davis fixes the grammar, but the self-hosting compiler is a place where mistakes are costly, so a review pass is advised.

### 2. `os`/`sys` and files v2: M

- **What**: `argv`, `environ`/`getenv`, `exit(code)`, `getcwd`, `listdir`, `mkdir`/`makedirs`, `remove`, `rename`, `exists`/`isfile`/`isdir`, `stat` (size, mtime), `getpid`; path helpers (`join`, `basename`, `dirname`, `splitext`) as functions or a `Path` class; file objects with `readline`, iteration (`for line in f`), `readlines`, append and binary modes, `StringIO`.
- **Why**: Today a Tomato program cannot read its environment, list a directory, exit with a status, or read a big file line by line `[V]`. This is the largest gap between "language demo" and "write real tools". It also gates `tempfile`, `shutil`, `glob`, `logging` to a file and `subprocess`.
- **Size**: M (mostly small C functions in the runtime, each declared with `!tomato_...` as `requests` does).
- **Dependencies**: runtime C (POSIX `stat`, `opendir`, `getenv`, `exit`); wasm: `argv`/`getenv`/`exit` need a story (WASI provides them), directory operations work on the page's in-memory files only `[I]`. Needs the bytes decision (D3) for binary mode.
- **Risk**: medium. Decisions about `exit` inside tasks, `finally` blocks, buffered stdout flushing; unclear whether dropping a `File` closes it `[I]`; the `with` question (D5).
- **Sonnet alone**: yes for a first batch (env, argv, exit, exists, listdir, readline), using the `requests`/`json` runtime pattern as a template; the wasm rebuild must be done on the Mac.

### 3. Testing support: `assert`, `@test`, `std/testing`: M

- **What**: an `assert` statement (or function), a `testing` module (`assert_equal`, `assert_raises` via an interface-based callback, approximate float compare), and a `@test` marker with a `tomato test FILE` command that runs every `@test` function and prints a summary. The language already has `@main`/`@greet` entry markers, so `@test` is a natural extension `[V]` (D47a).
- **Why**: Tomato has no way for a user to test their own code, and the repo's own tests are expected-output files compared by shell `[V]`. Python's `unittest`/`pytest` is a basic expectation, and a testing story makes every later library item cheaper to verify.
- **Size**: M (`assert` keyword S; `tomato test` command in the shell script `native/tomato` M; library S).
- **Dependencies**: compiler (new keyword, `@test` collection), `native/tomato`, wasm path for the playground (optional). No runtime change.
- **Risk**: medium (design: failure output format, whether tests share a process, how `assert_raises` works without closures, i.e. via a named function value `fn() -> None`).
- **Sonnet alone**: yes once Davis picks the syntax. It touches the compiler, so plan a review.

### 4. `random`, `secrets`, `uuid`: S

- **What**: `random()`, `randint`, `randrange`, `choice`, `shuffle`, `sample`, `seed`, `uniform`, `gauss`; an explicit `Random(seed)` class; `secrets.token_hex`/`token_bytes`/`randbelow`; `uuid4()`/`uuid5`/parse/format.
- **Why**: Used constantly in scripts, simulations, tests and games; entirely absent `[V]` (there is no entropy or PRNG function in the runtime). `uuid` is needed by any web service.
- **Size**: S.
- **Dependencies**: a small runtime addition for entropy (`getentropy` or `/dev/urandom`; note `open('/dev/urandom')` with `tomato_file_read_bytes` might already be usable without any runtime change `[I]`); WASI `random_get` or a host import in the browser `[I]`. For the PRNG itself prefer C (xoshiro256** needs 64-bit wraparound that Tomato ints do not give cheaply `[I]`) or a 32-bit design in Tomato. Module-level `random.random()` needs the global-state decision (D2); an explicit `Random` class does not.
- **Risk**: low technically; the decision is whether module-level functions exist (D2) and reproducibility across native and wasm (same seed, same sequence: only if the algorithm is in Tomato or in the same C used for both).
- **Sonnet alone**: yes (C helper plus Tomato wrapper), reproducibility test between native and wasm included.

### 5. Web basics: `urllib.parse`, `html.escape`, `base64`, hex: S

- **What**: `urlparse`/`urlunparse`/`urljoin`, `urlencode`, `quote`/`unquote`, `parse_qs`, `html.escape`/`unescape`, `base64` (standard, urlsafe) and hex encode/decode.
- **Why**: Prerequisites for any HTTP server and useful for `requests` users (`requests.quote` and a private `_form` already exist and are the seed). Pure Tomato, cheap, immediately demonstrable in the browser playground.
- **Size**: S.
- **Dependencies**: none beyond the bytes decision for `base64` (can ship text-to-text and `list[int]` forms now).
- **Risk**: low.
- **Sonnet alone**: yes. Strong test vectors (RFC 3986, RFC 4648) make it verifiable.

### 6. `re`: L (the biggest pure-Tomato module)

- **What**: a backtracking regular-expression engine written in Tomato with Python's syntax subset: literals, `.`, classes and escapes (`\d \w \s \b`, Unicode-aware `\w`), anchors, groups, non-capturing and named groups, alternation, greedy and lazy quantifiers, `{m,n}`, backreferences, lookahead; flags `IGNORECASE`, `MULTILINE`, `DOTALL`; API `compile`, `match`, `search`, `fullmatch`, `findall`, `finditer`, `sub` (replacement text and a named function), `split`, a `Match` class with `group`, `groups`, `start`, `end`, `span`.
- **Why**: after OS access it is the most common reason a Python user cannot port a script. Needed by log processing, validation, parsing, tokenizers (including the Tomato lexer itself, which is hand-written `[I]`).
- **Size**: L (1,500 to 3,000 lines plus a large test list).
- **Dependencies**: none in the runtime; works natively and in wasm. Uses `str` indexing (fast for ASCII per `docs/performance.md`).
- **Risk**: medium to high: catastrophic backtracking, Unicode categories, correctness at the edges; performance of a Tomato-written engine versus C (inferred 10 to 50 times slower than Python's `re` `[I]`). A compile-to-closures design is blocked by "no closures", so use a compiled node array interpreted by a loop.
- **Sonnet alone**: yes if the syntax subset is fixed up front and tested against a few hundred cases generated from Python's `re` (this box has Python 3.14, usable as an oracle for generating expected outputs, not as a dependency; the repo's convention is "Do not add Python" `[V]` in `docs/handoff.md`, so only commit the generated expected files).

### 7. Data-scripting pack: `csv`, `textwrap`, `statistics`, `string` constants, `logging`: S to M each

- **What**: `csv.reader`/`writer`/`DictReader` (RFC 4180, quoting, custom delimiter); `textwrap.wrap/fill/dedent/indent/shorten`; `statistics.mean/median/mode/stdev/variance/quantiles`; `string.ascii_letters` etc. as `export const`; `logging` with explicit `Logger` objects, levels, a stderr handler and a file handler, and `time`-based timestamps.
- **Why**: each is small, pure Tomato, common in everyday scripts, and works in the playground. `logging` is the only one needing a design decision (D2).
- **Size**: S each (`logging` M).
- **Dependencies**: `csv` benefits from #2 (`readline`) but can start with strings; `logging` to files needs #2.
- **Risk**: low.
- **Sonnet alone**: yes, four or five independent subtasks.

### 8. Async toolkit: `gather`, timeouts, `Queue`, `Event`, `Lock`, `cancelled()`: M

- **What**: await several tasks and collect results; `wait_for(task, seconds)` raising a `TimeoutError`; an async `Queue` (what Python's `asyncio.Queue` is); `Event`; `Lock`; `t.cancelled()`; `await sleep` already exists. The spec lists "timeouts, `t.cancelled()`" as unbuilt `[V]`.
- **Why**: any networked program needs timeouts (a server must close idle connections; a client must give up), and the web chain depends on this. `requests` has its own `timeout=` via curl, but nothing else does.
- **Size**: M. `gather` is a library function if tasks are first-class values (`start` gives `task[T]`); `wait_for`, `Queue`, `Event`, `Lock` need a new waiter kind in the scheduler (a queue of waiting frames) and cancellation integration.
- **Dependencies**: runtime scheduler (`tomato_sched_idle`, `tomato_task_cancel`, the waiter lists, `runtime/tomato_rt.c:2184-2540`), possibly the compiler for typing `gather` over a list of `task[T]`. Works in wasm too, since the scheduler is shared `[I]`.
- **Risk**: medium to high: the cooperative scheduler with reference-counted frames is subtle; leaks and double-resumes are the failure mode (the project already fixed task-waiter leaks, `TODO.md`).
- **Sonnet alone**: not without review. Better: Opus or Davis-reviewed. The library surface on top (`Queue` and friends in pure Tomato using a `sleep(0)` yield loop) could be a Sonnet starter that avoids touching the scheduler, at the price of polling `[I]`.

### 9. Sockets and a descriptor waiter in the scheduler: L

- **What**: a `socket` module (async TCP client `connect`/`send`/`recv`/`close`; server `listen`/`accept`; UDP; `getaddrinfo`) built on non-blocking sockets and a new scheduler wait kind "this task waits until fd X is readable/writable". the runtime already calls `curl_multi_poll(multi, NULL, 0, ms, &n)` `[V]` (`tomato_rt.c:2358`), whose real signature takes extra descriptors in those two `NULL, 0` arguments `[I]`, so the same call can wait for sockets and curl at once; with no curl transfer active, plain `poll`.
- **Why**: the foundation of every server and every protocol client other than HTTP (Redis, SMTP, a game server, a chat demo). R09.
- **Size**: L (about 600 lines of C plus a Tomato wrapper; most of the effort is scheduler integration and tests).
- **Dependencies**: runtime C; native only (no sockets in the browser, so every call raises a clear error as `requests` does `[V]`). Needs the bytes decision (D3) to be pleasant. `tests/http_server.c` shows the project already builds and tests against local sockets, so the harness idea exists `[V]`.
- **Risk**: high: scheduler change, cancellation, partial reads/writes, `SIGPIPE`, IPv6, DNS blocking (use `getaddrinfo` in a helper or accept blocking resolution at first), Linux vs macOS differences.
- **Sonnet alone**: no. The scheduler and C parts want Opus or Davis review. The Tomato-side API on top of an agreed C interface could be Sonnet work.

### 10. HTTP server: L

- **What**: an async HTTP/1.1 server library: request parser (request line, headers, `Content-Length` and chunked bodies, keep-alive), `Request` and `Response` classes mirroring `requests.Response`, a router with path parameters and method checks, JSON responses (`json` module), static file serving, graceful shutdown, concurrency through `start` per connection.
- **Why**: R09. It makes Tomato a "language for web servers" in practice, gives a real demo (a small API with JSON and a cache) combining `json`, `cache`, `requests`, `toml` config, and is the strongest marketing example.
- **Size**: L, once #5, #8 and #9 exist.
- **Dependencies**: #9 sockets (or a runtime-native HTTP listener on libuv-style C, which I do not recommend), #5 (`urllib.parse`, `html`), #8 (timeouts), `mimetypes`-lite, `datetime` for `Date` headers (#11). Handlers cannot be decorated closures: an `interface Handler` with an `async def handle(self, req: Request) -> Response` method, or a `fn(Request) -> Response` named function, fits the current language `[V]`.
- **Risk**: medium: protocol corner cases (pipelining, `Expect: 100-continue`, slow clients), security (request size limits, header injection, path traversal in static files). Production TLS is out of scope.
- **Sonnet alone**: the Tomato side yes, once sockets exist and the API is agreed, with the C test server as the interoperability check and `requests` as the client for end-to-end tests.

### 11. `datetime`: M

- **What**: `date`, `time` of day, `datetime` (naive and fixed-offset UTC), `timedelta` with `@add`/`@sub`/`@lt`, `fromisoformat`, `isoformat`, `strftime`, **`strptime`**, `weekday`, date arithmetic, `date.today()`, `datetime.now()`.
- **Why**: Dates appear in logs, APIs, config and every business script. The new `time` module deliberately stops at UTC `struct_time` with no `strptime` `[V]`; `toml.Moment` is a second date type. `datetime` is where users will expect arithmetic like `d + timedelta(days=30)`.
- **Size**: M, pure Tomato, wasm-safe; reuses `time._days_from_civil` and `strftime`.
- **Dependencies**: operator methods (present). Time zones stay out of the first version: the `time` module's "no time zones" rule stands until Davis revisits it.
- **Risk**: low to medium (calendar edge cases, parse formats).
- **Sonnet alone**: yes, with a table of expected values generated from Python's `datetime` as the oracle (committed as expected files only).

### 12. Hashing and binary helpers: `hashlib`, `hmac`, `zlib.crc32`, `struct`: M

- **What**: `sha256`, `sha1`, `md5`, `hmac`, `crc32`/`adler32`, `struct.pack`/`unpack` (a format string subset), hex digest. Pure Tomato with 32-bit math in small ints `[I]`.
- **Why**: checksums, content addressing, signing API requests, password-derivation basics (not `scrypt`), verifying downloads (`tomato update` trusts HTTPS plus a checksum in `site/latest.json`, README). Needed for any serious server (cookies, JWT).
- **Size**: M; each algorithm is 100 to 200 lines with published test vectors.
- **Dependencies**: bytes decision (D3): until then `list[int]` in and out (same as `msgpack`). Performance of pure Tomato may be tens of MB/s `[I]`; acceptable for small inputs; C later if needed.
- **Risk**: low (easy to verify against vectors); do not offer weak primitives (`md5`) without a warning in docs.
- **Sonnet alone**: yes, an ideal agent task because correctness is mechanically checkable.

### 13. `sqlite3`: M to L

- **What**: `connect(path)`, `execute(sql, params)`, `fetchone`/`fetchall`, `executemany`, `commit`, transactions, row access by name; binding via `dlopen`ed `libsqlite3` exactly like libcurl (`cu_sym` pattern in `tomato_rt.c:2251-2271`).
- **Why**: the natural pair of a web server for persistent state, and the standard answer to "where do I put my data" in Python scripts; no database access of any kind exists today `[V]`.
- **Size**: M to L (value marshalling for typed columns: text, integer, float, blob, NULL; error mapping; async or blocking? sqlite calls block the single scheduler thread).
- **Dependencies**: runtime C; native only (macOS ships `libsqlite3`; Linux needs the package, mirroring the libcurl note in `examples/http_get.tom`); wasm: none (or a later sqlite-wasm bridge `[I]`). Bytes decision for blobs.
- **Risk**: medium (typing: rows are heterogeneous; likely a `Json`-style value class; blocking calls; threading model).
- **Sonnet alone**: plausible with a Davis-approved API and the libcurl code as a template, with a review of the C.

### 14. Collections pack and what blocks it: S now, L for general dict keys

- **What (S, now)**: `heapq`, `bisect`, `collections.deque` (generic class), `Counter` with text keys, lazy `itertools` (`count`, `cycle`, `islice`, `takewhile`, `dropwhile`, `groupby`, `zip_longest`, `starmap` as `@iter` generators), `copy` helpers.
- **What (L, language)**: *(built: D78a)* dict keys beyond text (at least `int`, and ideally tuples and user types with `@hash`/`@eq`), which unlocks `Counter[int]`, `defaultdict`, graph code and general memo tables.
- **Why**: "a language with real data structures" is the other half of everyday Python after strings; `set[int]` exists but `dict[int, V]` does not, which is the most surprising missing combination `[V]`.
- **Size**: S for the pure modules; L for dict keys (compiler type checks, runtime hashing for ints and tuples, wasm).
- **Dependencies**: generic `<` on `T` for `heapq` and `bisect` is unverified `[I]`; keys need runtime hashing.
- **Risk**: dict keys: high and architectural; coordinate with `docs/architecture-review.md`.
- **Sonnet alone**: the S part yes; the dict-keys part no (Opus or Davis).

### 15. `subprocess`: M

- **What**: `run(args, capture_output, input, timeout, check)` returning a result with `returncode`, `stdout`, `stderr`; async `Popen` with pipes; `shlex.split`.
- **Why**: shell-script replacement is a core "between Python and Go" use `[I]`; also lets tests and release scripts be written in Tomato.
- **Built so far (D98a, 2026-11-27)**: the blocking `sys.run(args, capture, cwd, env, stdin, check, timeout)` in `std/sys.tom` (fork/exec and `poll` in C, no shell); D98b added `await sys.run_async(...)`, `sys.spawn(...)` with a `Process` and pipes (`write`, `wait`, `kill`, readers with `read_line` and `read`), and the closing of inherited descriptors in the child; what is not built is `shlex`, `communicate`, a `timeout` for `Process.wait()`, `pidfd` on Linux to wait for the end of a program without looking, and `bytes` output.
- **Size**: M (fork/exec/pipes in C, scheduler waiters for the pipes and the child).
- **Dependencies**: #9's descriptor waiter and #2; native only.
- **Risk**: medium to high (zombies, `SIGCHLD`, escaping, timeouts, cancellation).
- **Sonnet alone**: not the runtime part.

### Not in the top 15 (later, with reason)

`decimal`; `zlib`/`gzip` decode, `tarfile`, `zipfile`; `xml.etree`; `pprint`; `calendar`; `zoneinfo`; `mimetypes`, `ipaddress`, `graphlib`, `shlex`, `fnmatch`/`glob`, `tempfile`, `shutil`; `requests` sessions and cookies; `requests` in the browser via `fetch` (R10: today every call raises `ConnectionError` in the playground `[V]`; a bridge needs a host import in `site/wasm`); `argparse` flags beyond typed entry points; signal handling; `dataclasses`/`enum` (language design, D5); `copy.deepcopy`; `typing` equivalents (not needed).

### Suggested order and parallelism

- **Wave 1 (parallel, all Sonnet-sized, no scheduler work)**: #1 methods and math, #4 random/uuid, #5 web basics, #7 csv/textwrap/statistics/string, #11 datetime. Decision gates only (API sheets).
- **Wave 2**: #2 os/sys/files v2, #3 testing, #6 `re`, #12 hashing.
- **Wave 3 (a stronger agent or Davis reviewing)**: #8 async toolkit, then #9 sockets, then #10 HTTP server, #15 subprocess.
- **Anytime**: #13 `sqlite3` after #2; #14 the pure part right away, dict keys when the architecture review decides.
- Batch the runtime changes of #2, #4, #8, #9 into as few wasm rebuilds as possible.

---

## 7. Where to put checking effort (verified vs inferred)

What I verified in the repo: the module list and exports of every `std/*.tom`; the built-in names and method names in the compiler (`lint.tom:27`, `compiler.tom:5594-5612`); dict keys being text only (before D78a; `compiler.tom` lines above); the keyword list; the runtime's entry points and the absence of any socket, env, argv, exit, random or file-system function; the scheduler's wait kinds (sleepers, input, libcurl); `requests` being native only and `dlopen`-based; `site/wasm/tomato.js` having a hardcoded STD list; `TODO.md` and the stale `time` entry; the wasm rebuild constraint.

What is inferred and worth a five-minute check by whoever builds it: whether `heapq`/`bisect` can compare a generic `T` with `<`; whether a dropped `File` is closed; whether `open('/dev/urandom')` plus `tomato_file_read_bytes` already gives entropy; whether `curl_multi_poll` can carry extra descriptors on the minimum libcurl version supported; per-algorithm performance in pure Tomato for 32-bit hashing; whether `dict` keeps insertion order in the runtime; and WASI support for `random_get`/`environ` in `runtime.wasm`.

---

## 8. Decisions for Davis

1. **Which track goes first?** Two defensible plans: (A) *scripting batteries first*: items 1, 2, 3, 4, 5, 6 (everyday friction), then the web chain; or (B) *web server first*: 5, 8, 9, 10 in sequence, with 1 and 2 in parallel. My recommendation: **A and the cheap half of B in parallel**: start Wave 1 now (all Sonnet-sized), and put one stronger agent on item 8 then 9 (scheduler) so the server can follow. If R09 has a date, B should lead.
2. **Module-level state.** Python's `random.random()`, `logging.info()`, `sys.argv` assume hidden module-level values; Tomato has none (D47a, `time.tom` comment). Options: (i) allow module-level mutable values or lazily initialized singletons (a language change); (ii) keep state in the C runtime behind functions, which suits `random`, `argv`, `environ`; (iii) explicit objects everywhere (`Random(seed)`, `Logger('name')`), no module-level functions. Recommendation: (ii) for `random`/`argv`/`environ` plus (iii) for `logging`, no language change now.
3. **A `bytes` type or keep `list[int]`?** Hashing, sockets, binary files, compression, `struct`, `base64` and `requests.content` all need binary data. `list[int]` works but gives no `b'...'` literals, no `.decode()`/`.encode()`, no distinct printing, and it conflates numbers with bytes. A real `bytes`/`bytearray` is a compiler and runtime item (L) but should precede #9 and #12 if Davis wants those APIs to feel final. Recommendation: decide before sockets; ship #5 and #12 with `list[int]` and a documented migration if the decision is "yes".
4. **Native-only libraries: acceptable?** Sockets, subprocess, `sqlite3` and the filesystem cannot work in the browser playground. The precedent is `requests` raising a clear error there. Choices: (i) accept "native only, clear error in the browser" and keep the playground to pure-Tomato modules; (ii) invest in browser bridges (a `fetch`-based `requests`, an in-memory sqlite) for R10. Also: keep the `dlopen` model (no link flags, a missing library only fails programs that use it) for `sqlite3`, or bundle? Recommendation: (i) now, `fetch` for `requests` as the first bridge later, `dlopen` for `sqlite3`.
5. **Which language-level gaps join the plan, and who decides them?** The library items above are limited by: dict keys beyond text (blocks `Counter`/`defaultdict`/graphs), no `with` (resource cleanup for files, sockets and locks), no closures (blocks `partial`, decorators, routers, `re.sub` callbacks), no dataclass/enum equivalent (every record needs hand-written `@init`/`@str`/`@eq`), f-string format specs. Recommendation: schedule f-string format specs and `assert` inside this plan (items 1 and 3) and take dict keys, `with` and records/enums to the architecture review's agenda, since they change language rules; I would put dict keys first, because three items (14 and any real data code) wait on it.
