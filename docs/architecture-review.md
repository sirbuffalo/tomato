# Tomato architecture review and roadmap (v0.51, November 2026)

An outside look at the language and its implementation, and a proposal for what to build next. Nothing here is a
decision: the roadmap is a ranked suggestion, and section 5 lists the questions only Davis can answer.

**What was reviewed.** The source at `812244d` (just before the v0.51 release commit); all file and line references are
to that commit. While the review ran, `main` moved to `bf8eb2ce`: v0.51 was released, integer range analysis landed,
wasm builds became byte-identical across hosts, and unions print their members. Where that changes a conclusion, this
document says so. `docs/next-features.md` landed in the same period and covers the standard library in detail, so this
document keeps to the compiler, runtime and language and points there for library items.

**How to read the evidence tags.** **[V]** read in the source or run, by me or by a helper agent
(Appendix B says which claims I re-checked myself); **[M]** measured on the Linux x86-64 build box (128 cores, clang
21.1.8, load average 70 to 80 from other work, so wall times swing by a factor of 2 to 4 and only instruction counts are
exact); **[I]** inferred, not checked.

## Summary

Tomato has gone from a Python prototype to a self-hosting compiler with an LLVM backend, a reference-counted runtime
with a cycle collector, unlimited integers, async tasks, a browser playground and a signed macOS release in under three
weeks of commits (2026-11-05 to 2026-11-23, 137 commits). The engineering discipline is unusually good for that pace:
the compiler is a byte-identical fixed point, every release gate re-runs the whole suite, every performance change in
`docs/performance.md` is measured before it is kept, and the error table gives every diagnostic a stable id.

Three conclusions:

1. **On the Mac the speed goal (R11, D02b: about half of Go) is met on nine of the ten benchmarks** in the v0.51 snapshot;
   only matmul (2.35 times Go) is over. On the Linux x86-64 column the published numbers are wrong for a mechanical reason:
   **that build silently lost link-time optimisation** (section 3.3). It is the first thing to fix, because it also affects
   any Linux user whose clang cannot load the LTO plugin.
2. **The compiler's internal design is now the limit on the language** (my judgement). Types are strings, syntax-tree
   fields are numbered slots, and type checking happens while LLVM text is being written. The open holes sit on that
   design: `int | None`, `dict[int, V]`, closures, compile-time checking of optionals, more than one error per compile,
   and editor support beyond a grammar.
3. **The browser path is about 1,500 times slower than native** on a recursive `fib` [M], much slower than the docs
   suggest. That matters for R10 and for what people see first.

Recommended order: fix the silent LTO fallback; make the compiler build its output with a join (an 11-line experiment cut
the self-compile from 24.0 s to 9.9 s) and cache the compiled runtime; make the documents and `known_gaps` honest;
then a **typed front end** in slices, followed by optionals and dict keys on top of it. Run the library waves of
`docs/next-features.md` beside that, since they mostly do not touch the compiler. The big bets after that are sum
types with `match`, closures, a language server and a real wasm target.

## 1. Architecture as it is

### 1.1 The whole system

```
                      compiler/src/*.tom  (lexer, parser, lint, diag, compiler: ~10,100 lines of Tomato)
                                   |
                     compiled by the previous compiler (fixed point)
                                   v
                    compiler/bootstrap/tomatoc.ll  (11.4 MB LLVM IR, checked in)
                     |                                         |
     clang + runtime/tomato_rt.c                  WASI SDK clang + tomato_rt.c
                     v                                         v
           native `tomatoc` binary                 site/wasm/tomatoc.wasm (2.3 MB)
                     |                                         |
   program.tom + std/*.tom -> tomatoc -> program.ll    program.tom -> tomatoc.wasm -> program.ll (in the browser)
                     |                                         |
   clang -O1|-O2 -flto program.ll tomato_rt.c          llvm.js interprets program.ll; heap and runtime
                     v                                 calls live in runtime.wasm (tomato_rt.c, -DTOMATO_WASM)
             native executable                                 v
                                                       output in the playground / repl
```

One compiler and one C runtime file serve both targets [V]: the native compiler and the browser compiler are built
from the same `tomatoc.ll`, and `runtime/tomato_rt.c` is compiled twice, with about 20 `#ifdef TOMATO_WASM / __wasi__`
blocks cutting out signals, the stack guard, colour, `dlopen`ed libcurl, real sleeping and the C callback sort. What
differs is the last step: natively clang turns the program's IR into machine code; in the browser a 575-line LLVM IR
interpreter in JavaScript (`site/wasm/llvm.js`) runs it, calling into `runtime.wasm` for every runtime function.

### 1.2 The compiler pipeline

`lexer.tom` → `parser.tom` → `lint.tom` (warnings) → `compiler.tom` → LLVM IR text [V].

- **Syntax tree.** Every node is one `Node` class (`parser.tom:72-86`) with a `kind` string and a list of tagged
  `Val` fields in the order the retired Python prototype used. Consumers read `n.fields[6]` by position: 471 such reads
  in `compiler.tom` [V]. The lexer drops comments and lowers f-strings to `'text' + str(expr)` tokens
  (`lexer.tom:149`) [V], so nothing downstream can see either.
- **Types are short strings** (`compiler.tom:4-8`, helpers at `:31-415`) [V]: `list[int]`, `@Class`, `%Iface`,
  `U:a;b` for a union, `str?` for `str | None`, `tup[A,B]`, `fn[A,B>R]`, `i8`/`u32` for fixed-width integers. A dict
  is `dict[V]`: **the key type is not stored at all** (`dict_value` at `:88` is just the bracket contents), which is
  why only `dict[str, V]` exists. About 276 calls to `is_list`/`is_dict`/`is_union`/... and about 170 comparisons
  against `'int'`, `'str'`, `'float'` spread the type grammar through the file [V].
- **No separate type checker.** `Gen.expr` returns an `Ex` (register, type string, ownership flags) and emits IR text
  in the same step; the 251 `CompileError(` sites raise from inside emission code, and the first error ends the
  compile [V]. There is no typed tree and no intermediate representation between the syntax tree and LLVM text.
- **Generics** are monomorphised: each set of type arguments gets its own copy (`instance_class`, `:1069`). When a
  copy is discovered after code that needed to see it was already compiled, the compiler throws `NeedsEarlyCopy` and
  **restarts the whole compile**, up to 40 times (`compile_module`, `:7975-7995`) [V].
- **Standard-library helpers** such as list `show`, `sorted(cmp=)`, `sum`, `max` are generated as Tomato source text
  (`helper_source`, `:7536`), parsed and compiled like user code [V].
- **Optimisations in the compiler** are targeted and measured (`docs/performance.md`): borrowed reads and lent
  parameters skip reference counts, `flat` releases for types that cannot be in a cycle, a fast copy of small-int
  `while` loops (`small_loop`, `:6200`), deferred float finite checks, fused string concatenation, power-of-two
  division, inlined generators [V]. There is no general constant folder, inliner or escape analysis;
  LLVM with LTO does the rest. Since the review, `bf8eb2ce` added interval facts for int locals (`Gen.range_of`,
  `Gen.loop_facts`), kept as mutable state during emission.
- **Organisation.** `compiler.tom` is one module of 8,000 lines: ~70 free functions over type strings, a `Mod` class
  (symbol tables, ~735 lines), and a `Gen` class with ~300 methods in ~5,340 lines [V]. Function lookups are linear scans
  over `mod.infos` [V].
- **Driver.** `native/tomato` (211 lines of shell) runs `tomatoc FILE ENTRY STD MODE > program.ll`, then
  `clang -O1 -flto` (debug) or `clang -O2 -flto -DTOMATO_RELEASE` (release) on the IR **plus the runtime's C source**
  (`native/tomato:187-209`) [V]. Warnings travel as `;! ` comment lines at the end of the IR.

### 1.3 Bootstrap

`compiler/bootstrap/tomatoc.ll` is the compiler's own IR, in debug mode (it has 10,267 trace calls) [V]. A machine
with clang alone builds `tomatoc` from it; `refresh.sh` regenerates it by compiling until two passes agree, and
`tests/run.sh` re-checks the fixed point (`c0 → ir1 → c1 → ir2`, `ir1 == ir2 == tomatoc.ll`) on every run [V].

Costs [M, wall times vary by 2x here with load]: building `tomatoc` from the IR took 46 to 70 s of clang; the self-compile
took 12 to 25 s, about half of it system time (section 3.3). A no-op `refresh.sh` needs about two of each. On `main` the
file has been rewritten in 58 of 145 commits and is now 11.9 MB; `.gitattributes` marks it `-diff`, so git cannot
show a diff of it [V].

### 1.4 The runtime (`runtime/tomato_rt.c`, 5,038 lines)

- **Values** [V]. Every heap object starts with a 16-byte header `{int64 rc; int64 type}`; the low 32 bits of `type`
  index generated `tomato_kinds`/`tomato_offsets` tables, and the upper bits hold the collector colour, buffered/dead
  flags, async flags and the allocator's size class. A negative count marks an immortal object (literals, the 128
  one-character ASCII strings). `int` is one 64-bit word: odd (or 0) is a small number in −2^62..2^62−1, even is a
  pointer to a `Big` (sign, 32-bit limbs) which has **no header and a single owner**, copied on store (D05av).
  `float` is a raw `double`; `bool` is `i1`. `T | None` is a nullable pointer, so only heap types can be optional.
  Unions are a heap box `{hdr, payload, kind}`. This is *not* D35a's 128-bit type-code/data pair; P39 records the
  substitution, but D35a has not been revisited.
- **Strings** are UTF-8 with byte and character counts; long non-ASCII strings get a chunked index (every 64th
  character) kept in a 4-entry side cache [V].
- **Lists** have 8-byte slots, except `bool` and fixed-width items, which are stored compactly (1/2/4 bytes) [V].
- **Dicts and sets** are one insertion-ordered entry array plus an open-addressing `int32` index, load ≤ 0.5, FNV-1a
  for strings with no seed [V]. The runtime already supports integer, bool and big-integer keys (`key_kind`,
  `:2794-2815`); only the compiler limits keys to `str`.
- **Reference counting** is `tomato_retain`/`tomato_release`/`tomato_release_flat`, `always_inline` C functions that
  LTO inlines into the program [V]. No atomics; the whole runtime is single-threaded global state.
- **Cycle collector** [V]: synchronous Bacon–Rajan trial deletion. A release that leaves a candidate type above zero
  buffers it as a possible root; at 10,000 roots (threshold scales with the traced graph) the collector marks, scans
  and frees with explicit stacks. Types that can never be in a cycle are never buffered. It runs inside whichever
  `release` crosses the threshold, so a collection is a pause with no incremental mode [I].
- **Allocation** [V]: 16 size classes up to 256 bytes on free lists carved from 64 KB chunks (never returned to the
  OS), `malloc` above that; ASan builds and `-DTOMATO_NO_POOL` use `malloc` for exact checking.
- **Big integers** [V]: schoolbook multiplication (no Karatsuba), Knuth division, O(n²) decimal conversion and parsing,
  and shifts implemented as `pow(2, n)` followed by a multiply or floor division (`:4103-4125`). *Since then:* shifts and
  `2**n` are linear, and multiplication is Karatsuba above 48 limbs with its own squaring path (`docs/performance.md`,
  "big-integer multiplication") and a number-theoretic transform above 6000, division by a long divisor is
  Burnikel-Ziegler over it ("big-integer division"), and decimal conversion and parsing are divide and conquer on it
  ("decimal text of long integers").
- **Errors** [V]: a pending error lives in IR globals (`@tomato_exc`, line, kind); the compiler emits a load and branch
  after every call that can raise, freeing the expression's held temporaries on the way to the nearest `catch`,
  `finally` or the function epilogue. `finally` bodies are compiled once per exit path. There is no LLVM unwinding.
  Some failures are fatal and uncatchable (`tomato_fail_id`: out of memory, stack overflow, huge exponents), exiting
  without cleanup. Debug builds record a 24-entry call trace and run a leak check at exit, which **stays silent about
  objects once any error has been raised** (`:395-415`).
- **Async** [V]: `async def` compiles to a heap frame (13 fixed fields, then one per local) and a `resume` function
  that switches on the await site. The scheduler loop is generated IR, not C, so the browser interpreter can run it;
  the runtime keeps the ready, input, sleeper and HTTP queues. The frame layout is hard-coded on both sides (byte
  offsets 32..88 in C, `FRAME_FIXED = 13` in `compiler.tom:289`). Input in the browser and repl works by **replay**:
  at the end of input the program exits with status 75, the host asks for a line, and the whole program runs again
  with one more answer.
- **Size** [V]: about 1,260 lines are generated Unicode tables, 570 JSON and MessagePack, 315 libcurl HTTP, 650 big
  integers, 350 collector and destruction, 270 sorting.

### 1.5 Standard library (`std/`, ~4,300 lines of Tomato)

`builtin` (errors, `range`, helper sorts), `math` (number theory, typed `Angle` trigonometry, libm functions),
`rational`, `itertools` (eager lists), `cache` (LRU, memoize), `time` (UTC), `json` (+ MessagePack, with a C scanner),
`toml` (pure Tomato), `bitarray`, `requests` (async HTTP client over `dlopen`ed libcurl; fails in the browser) [V]. The
library is strong on formats and number theory and almost empty on the operating-system layer: no file system beyond
`open`, no environment or `argv` access, no processes, no regex, no random numbers, no hashing, no deque/heap/counter,
no format specs in f-strings, no `bytes` type (MessagePack uses `list[int]`) [V]. The full comparison with Python's
built-in modules is in `docs/next-features.md`, section 4.

### 1.6 Tooling

- `tomato run/build/compile/explain/repl/update/version/help` are shell scripts (`native/tomato`, `tomato-repl`) [V].
- **Diagnostics**: one rustc-like format everywhere (`docs/errors.md`); ids are line numbers in `std/errors.txt`
  (389 lines, 269 of them compile errors), matched from message text by the most specific template, and checked by
  `tests/error_templates.sh` [V]. `tomato explain E04:12 prog.tom` is an awk lookup, mainly to decode release-mode
  short codes [V]. Colour is implemented three times (awk, C, `site.js`) [V].
- **Lint** is part of the compiler: unused, unreachable, unassigned, shadow, loop-change, silenced with
  `# allow: KIND` [V].
- **Repl**: replays the whole session as one program per line, so side effects repeat and functions cannot see session
  variables; three speed tiers (jsc + wasm, a pre-compiled runtime object, plain) [V]. The fast wasm tier needs macOS
  `jsc`, so Linux gets tier 1 [V].
- **Editor**: VS Code TextMate grammar, snippets and language configuration; no language server [V].
- **Tests**: `tests/run.sh` (479 lines) builds the fixed point, then about 119 programs with expected output, 56
  rejected programs, 72 error-message checks, 35 runtime-error checks, 66 memory checks (AddressSanitizer), 58 checks
  through the wasm path, 81 command-line checks, the examples and a benchmark smoke run. A full run here gave **530 passed,
  1 failed in 34 min 25 s** [M, details in Appendix A].
  `tests/known_gaps/` holds **no programs** today, only its README [V]. CI is one GitHub job on `macos-latest`
  (`.github/workflows/pages.yml`) [V]; Linux is checked by the release script over ssh.
- **Release** (`release/release.sh`, 686 lines, Mac only): tests with a byte-for-byte wasm rebuild, a Linux gate over
  ssh, benchmarks, a universal signed and notarised `.pkg` and `.dmg`, a `.tar.gz` and `latest.json`, upload and
  re-download verification [V]. `tomato update` trusts HTTPS plus the checksum in `latest.json` and re-runs
  `install-native.sh`, which builds `tomatoc` locally with clang, so an updated `.pkg` install no longer runs the signed
  binary [V for the script; I for the consequence on a `.pkg` install].

### 1.7 How native and wasm differ at run time

```
   native                                         browser / repl fast path
   ------                                         ------------------------
   program.ll + tomato_rt.c --clang -flto-->      program.ll --llvm.js--> JavaScript per function (made at its first call)
   one optimised executable                        |  every i64 is a JS BigInt, registers are local variables
   runtime fast paths inlined                      |  unknown callees -> exports of runtime.wasm
   C callback sort, libcurl, real sleep            |  no callbacks into the program (Tomato merge sort instead)
   SIGSEGV guard -> E350                           |  JS RangeError -> E350, 5 s deadline every 4096 instructions
                                                   v  input by replay (exit 75), logical clock for sleep
```

No browser-versus-native timing exists in the repo; `docs/decisions.md:1228` calls the interpreter "meant for demos" [V].
Measured here with Node through `native/jsc-on-node.js` [M]: going from `fib(22)` (0.89 s) to `fib(26)` (4.20 s) costs
about 9.9 microseconds per call, against about 6 nanoseconds per call for a native debug build of `fib(36)` (0.30 s). That
is **roughly 1,500 times slower**. A program that needs half a millisecond natively takes about a second in the playground
and hits the 5-second limit at about 3 ms of native work. The timings are one or three runs on a loaded machine; the order
of magnitude is not in doubt. Safari's engine was not measured.

## 2. Strengths

1. **Self-hosting at a fixed point, checked on every test run.** The compiler is the largest Tomato program (~10,100
   lines) and the best test of the language [V].
2. **Measured performance work.** Every optimisation in `docs/performance.md` has a before/after profile, and changes
   that did not help were dropped. On the M1, Tomato went from 0.49-4.19 times
   Go in v0.50 to 0.45-2.35 in v0.51 (Section 3.2).
3. **Error experience.** Stable ids, one format for compiler, runtime, repl and website, `did you mean`, call traces,
   and a test that every message template has an id [V].
4. **Memory safety as the default.** Bounds checks, overflow-to-bigint, checked fixed-width integers, 66 memory checks
   under AddressSanitizer, a debug leak check [V].
5. **One runtime for two targets** and a zero-install playground [V].
6. **A written decision record.** Every semantic choice is in `docs/decisions.md` with Davis's words and the reading,
   and placeholders are labelled in `docs/provisional.md` [V].
7. **A careful release process** with signing, notarisation, a Linux gate and post-upload hash verification [V].

## 3. Weaknesses and structural risks

### 3.1 Correctness hazards

- **Optionals are checked at run time, not compile time.** `s: str | None` can be passed to `len(s)`; the program
  compiles and stops with `error[E10]: None where a value is needed` [V, probe `r1`]. So does `a.v` on an `A | None`
  [V, probe `u2`]. This is P30's documented
  placeholder, but it sits badly with D04a/D33a ("reject known type mismatches before running") and is the biggest gap I
  found in static checking. Narrowing exists only for unions via `x in T` (D55a), not for `is None` (since then D102a narrows optionals and D23i spells the union test `x is T`).
- **Wrong output from a range near the small-int edge.** `for i in range(n + 5, n + 2, -1)` with n = 2^62 - 4 prints
  -4611686018427387903 as its first value, with no error [V, probe `s3`]. It is in `TODO.md` now (`tag_small` wraps). Few
  programs reach it, but a language whose promise is unlimited integers should not print a wrong one silently.
- **Error-path cleanup is manual.** Temporaries waiting in an expression are tracked by hand (`held`, `live` lists in
  `Gen`), and borrowed registers are recognised by a `%bl.` name prefix (`compiler.tom:1572`) [V]. The two known
  leaks (`TODO.md`: class-object slicing and big-int range bounds) are this class of bug; any new expression form can
  add another. After an error the debug leak check still counts big numbers but goes quiet about objects
  [V], so it misses leaked objects on these paths, and LeakSanitizer is not in CI (TODO.md; a Linux-CI task is in progress).
- **Hand-synchronised layouts between compiler and C.** Async frame offsets, the union box, the `Error` fields (a C
  struct mirroring `std/builtin.tom`, `tomato_rt.c:3013-3019`), the `items()` pair layout and the kind bits are written
  out twice with no shared header [V]. Pointer width differs on wasm (32-bit), which the C side handles with
  `sizeof(void *)` and the compiler with pointer-sized GEPs [V]; a drift on either side fails silently [I].
- **Fatal errors skip cleanup**: out of memory, stack overflow and oversized shifts/exponents exit at once without
  flushing the unread-task queue or running `finally` [V].
- **Smaller items** [V unless marked]: no overflow checks on string concatenation and list growth sizes [I: not
  exercised]; `File` is not reference counted, so an unclosed file leaks;
  a release of an object whose count is already ≤ 0 is silently ignored, hiding double-release bugs in release builds;
  string hashing is unseeded FNV-1a, which matters once Tomato serves untrusted requests (R09).
- **Most tests link without LTO** (`tests/run.sh:33,47`), while users build with it [V]. The exceptions are the
  command-line section (including ten programs run in release mode, `tests/run.sh:154`) and the benchmarks, and those
  fall back to no LTO without saying so when the plugin is missing.
- **Text file writes drop errors**: `tomato_file_write` and `tomato_file_close` ignore the results of
  `fwrite` and `fclose` (`tomato_rt.c:2060-2061`) [V], so a full disk loses data silently for text files.

### 3.2 Performance ceilings

v0.51 on the M1 (`benchmarks/results/results.md` on `main`), Tomato's time divided by Go's: fib 1.12, sieve 1.18, matmul
**2.35**, mandelbrot 1.08, collatz 1.07, strings 1.35, sort 0.45, wordcount 0.89, bigint 1.56, objects 1.17. Against
Rust: 0.64 to 2.23. I did not re-run the benchmarks: at this machine's load the wall times would add noise.

What is left, and why:

- **matmul** is the one outlier: each `b[k][j]` pays two bounds checks, a tag test on each item and checked arithmetic
  (`docs/performance.md` counts about 28 instructions per inner iteration, none of them reference counting). The new
  interval facts cover int locals, not list lengths or list items.
- **Range facts stop at `try` bodies, generator loops and async functions** (`docs/performance.md`, "integer ranges").
  They live in mutable emitter state, so a second kind of fact (list lengths, floats, "this list is not aliased") means a second hand-written walker. A typed tree
  would give them one place to live [I].
- **`for x in xs` retains every item** (13 of 35 instructions per item in `objects`): dropping it needs proof that the
  body cannot shrink the list.
- **String append in a loop is quadratic.** `s += t` allocates, zeroes and copies the whole string every time. Section 3.3
  shows the compiler paying for it. CPython avoids this by growing in place when nobody else holds the string; Tomato's
  counts make the same trick possible (`rc == 1`) [I].
- **The collector rescans live data**: 17% of the self-compile's instructions went to 94 collections [M]. Long-lived
  trees of class objects are the worst case, and every compiler-like program is one.
- **Big integers**: schoolbook multiplication, O(n^2) printing, shifts through `pow` [V]. Fine at today's sizes. (Since then: Karatsuba and number-theoretic-transform multiplication, linear shifts, divide-and-conquer printing and parsing, Burnikel-Ziegler division.)

### 3.3 Compile time, build and reproducibility

- **Link-time optimisation can be lost without a word, and the published Linux numbers show it.** `native/tomato:209` is
  `link "$ltoflags" 2>/dev/null || link "$nolto"`. The release toolchain that `release/linux-setup.sh` installs cannot
  do LTO on biggie: plain `-flto` fails with `LLVMgold.so: cannot open shared object file`, and its `lld` fails because
  `libxml2.so.2` is missing [V]. Release instruction counts at the counting inputs [M]:

  | benchmark | published Linux v0.51 | my build, no LTO | my build, LTO | Tomato ÷ Go published | with LTO |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | fib 32 | 342.05 M | 342.07 M | 183.46 M | 3.32 | 1.78 |
  | sieve 1,000,000 | 98.31 M | 98.33 M | 49.04 M | 4.25 | 2.12 |
  | matmul 150 | 387.34 M | 387.36 M | 138.65 M | 6.91 | 2.47 |

  (The last column divides by the published Go counts.) The match is close enough to call it the cause. The Mac column is
  not affected. `docs/performance.md` on `main` still prints the wrong Linux column; the website's `benchmarks.json` has no
  Linux numbers. The Linux gate passed because no test checks that LTO happened. Any user whose clang lacks the plugin gets
  the same slowdown of 1.9 to 2.8 times, with no message.
  *Update (Linux LTO task).* `native/tomato` now warns when the LTO link fails (and which fallback it uses), `release/check-lto.sh`
  proves that the toolchain does cross-module LTO and `release/release.sh` runs it before the Linux tests, which also require
  an LTO link (`TOMATO_TEST_REQUIRE_LTO`). `release/linux-setup.sh` builds libxml2 locally for `lld` and installs a `clang` wrapper
  that uses it. Release counts on Linux with LTO, built from `d83f43b0` (v0.51 plus 25 later runtime and compiler changes, so the drop from the figures above is LTO plus those changes; `benchmarks/results/linux-x86_64/lto-effect.md` isolates LTO: at the v0.51 tree it is 1.86 times fewer instructions on fib, 2.00 on sieve and 2.79 on matmul, which confirms the figures above, while at `d83f43b0` the compiler's own fast paths leave LTO little to do): fib 123.5 M, sieve 30.3 M, matmul 83.9 M (`benchmarks/results/linux-x86_64/instructions.md`;
  the non-LTO counts are kept in `instructions-v0.51-no-lto.md`).
- **`tomato run` recompiles the runtime every time** [M]. For a 6-line program the front end takes 0.05 s. The LTO link
  with `tomato_rt.c` took 1.5 to 1.75 s in most runs, up to 6.5 s under load. Linking a runtime compiled once
  (`clang -O1 -flto -c`) took 0.4 to 0.6 s, up to 1.4 s, and gave a **byte-identical binary**. The repl already compiles the
  runtime once per session (`tomato-repl:26`).
  *Update (runtime cache task).* `native/tomato` now keeps the compiled runtime, as LLVM bitcode, in the user cache folder
  (`native/rtcache.sh`; `tests/run.sh` shares it). With link-time optimisation the saving is smaller than the figure above, which
  was a plain non-LTO object link: clang still optimises and generates code for the whole merged module on every link, so only
  the C compile of the runtime goes away (about 0.5 s of CPU on the Linux build box; measurements in the task's merge card).
- **The compiler spends much of its time appending to one string** [M]. `compile_with` builds the output with
  `bodies += f'{compile_function(...)}'` (`compiler.tom:7933-7951`) on a string that reaches about 10 MB. Callgrind puts
  35% of all instructions in `tomato_str_concat`, and the kernel another large share (628,000 page faults). In a scratch
  copy I collected the pieces in a list and joined once, an 11-line change:

  | self-compile, 5 alternating runs | wall, median (range) | system time | page faults | output |
  | --- | ---: | ---: | ---: | --- |
  | today | 24.0 s (13.1 to 24.7) | 6.1 to 11.2 s | 628,000 | 11.4 MB IR |
  | list and join | 9.9 s (3.9 to 10.3) | 0.2 to 0.5 s | 24,000 | byte-identical |

  Instructions, which do not depend on load, fell from 13.1 G to 8.6 G.

  Building `tomatoc` itself with `-O2 -flto` made no clear difference to wall time (13.1 G instructions to 11.4 G for
  `-O2 -flto`, unchanged for `-O1 -flto`), so that is not worth its 156 s build. Linear function lookups, which I expected
  to matter, are about 3% of instructions.
- **The bootstrap IR is a merge hotspot.** It is 11.9 MB, rewritten in 58 of 145 commits, and compiler tasks run in
  parallel, so two compiler branches normally conflict in it and one must run `refresh.sh` again [I].
- **Wasm reproducibility is fixed** on `main` (`f8b0d178`, `--strip-debug` plus fixed build paths): the Linux and Mac builds
  now agree, and `runtime.wasm` fell from 542 KB to 231 KB [V, `docs/releasing.md`; not rebuilt here]. `SOURCE.sha256` still does not cover
  `site/wasm/std` or the JavaScript files [V].

### 3.4 Test coverage and portability

- Strong end-to-end coverage (Section 1.6), but **no unit tests** of compiler pieces: a codegen bug shows up as a
  changed program output or a bootstrap diff, which is hard to localise [V].
- **One wasm test depends on machine speed.** `wasm sort_stable` failed in the suite and in a re-run on this box
  (E369, the 5 s limit); the other 57 wasm checks passed [M]. It is a limit on the test, not a wrong result.
- **`tests/known_gaps/` was empty** (nine programs have been added since) although the spec still says "see tests/known_gaps" for D23g, D23h, D28b, D39a and
  D40a, and the probes below find several decided-but-unbuilt rules [V]. The mechanism that keeps the status table
  honest is not in use.
- **CI is macOS only**; Linux runs only in the release gate; no Linux arm64, no Windows (no Windows support at all:
  shell driver, POSIX runtime, `/dev/std*`) [V].
- **The suite takes over half an hour here** (34 min 25 s wall, 31 min 38 s user). Each program compiles the runtime C
  source again (`tests/run.sh:33,47`) [V]; that this is most of the time is [I].

### 3.5 Maintainability of the self-hosted compiler

The compiler's design follows from what the compiler could compile when it was written: no unions or tuples, hence
one `Node` class with tagged `Val` fields (`parser.tom:3-4` says so) [V]. The language has grown since, but the
compiler has not been restructured. The consequences:

1. **Types as strings.** A new type form must be threaded through `is_rc`, `llvm_type`, `shown`, `zero_of`,
   `flat_type`, `box_kind`, `unify`, `assignable`, the runtime tables and more, with nothing checking that every case
   is covered. I take this to be the main reason `dict[int, V]` and `int | None` are hard [I].
2. **Positional syntax tree.** Inserting a field in a node shifts every `fields[k]` reader silently.
3. **Check and emit are one pass.** No second error, no typed tree for a language server or a formatter, no natural
   place for an analysis (the new range facts are kept in emitter state), and the `NeedsEarlyCopy` whole-compile restart.
4. **Ownership by convention and patching.** `%bl.` prefixes, `held`/`live` lists, and `compile_function` turning
   already-emitted lines into comments by index (`:6818-6833`) [V].
5. **Duplicated paths.** `compile_async_function` re-implements slots and epilogues; list/dict/set/text methods,
   `slice` vs `object_slice` [V].
6. **The bootstrap couples every change to an 11 MB artifact** (3.3).

None of this is a crisis: the end-to-end tests catch regressions and the code is consistently commented. But every
feature now costs more than it would with a typed front end, and the cost grows with each feature.

### 3.6 Language design inconsistencies

Probed with small programs against the installed compiler [V]:

| Program | Result | Note |
| --- | --- | --- |
| `d: dict[int, str] = {1: 'a'}` | E318 "this variable cannot be given a type automatically … write its type" | The type *is* written; the message is a fallback. Runtime supports int keys. |
| `def f(x: int \| None)` | E313 "this parameter type is not supported" | Optional value types are missing (P43); `d.get(k)` therefore errors (E380) for `dict[str, int]`. |
| `xs: list[int \| None]`, `x: int \| str \| None` | E318 (same misleading text) | Unions cannot include `None` with other members (P62). |
| `s: str \| None`, then `len(s)` | compiles; stops at run time with E10 | Not checked statically (3.1). |
| `return y -> y + n` | E151 a lambda cannot use `n` | No closures; function values are bare pointers (`llvm_type`, `:397`). |
| `g = (a, b) -> a * b` | E152 needs parameter types | No inference of lambda types from use later in the body. |
| `a == b` on a class without `@eq` | E190 cannot use `==` | P65 says such classes compare by identity. Doc and compiler disagree. |
| `set()` | E368 not built in | Empty set needs `s: set[str] = {}`. |
| `f'{x:.2f}'` | E159 no format options | f-strings are lowered to `+ str()` in the lexer. |
| `x = 1` then `x = 'a'` | E324 type mismatch | Consistent with P6 (first assignment fixes the type). |

Other inconsistencies from the docs and code:

- **Two tuple types share one spelling.** `tuple[int]` is any-length, one item type; `tuple[int, int]` and
  `tuple[int, str]` are fixed-length. A bare `(1, 2)` is a `tuple[int]`, but `t: tuple[int, int] = (1, 2)` also works, and
  a fixed one cannot be looped over even when its items match (E140) [V, probes `s1`, `s7`].
- **Two optional representations.** `T | None` is a nullable pointer for heap types; any other union is a heap box.
  So `int | None` cannot be a nullable pointer and `str | int | None` has no representation [V].
- **Fixed-width integers** are allowed in inferred lists (`[int[length=8](1)]`) but `list[int[length=8]]` cannot be
  declared (P53, `docs/performance.md`).
- **Generics**: at most five type parameters (two when this was written; D62b), no bounds, no generic methods or interfaces (D60a).
- **Placeholders that read as decisions.** D35a (128-bit value pairs) and D32a ("int auto-detects its size") describe a design the implementation replaced
  with tagged 64-bit words and an ownership rule; the decisions were never revisited.
- **Resource cleanup**: `File` must be closed by hand, there is no `with`/`defer`, and R03's "resource cleanup" is open.

### 3.7 Provisional features and documentation drift

`docs/provisional.md` has 90 placeholders; many are now the language in all but name (P27 lists, P28 dicts, P29
errors, P81/P82 Python positions and printing, P83/P86/P87 built-ins, P85 async). Several entries contradict the code
[V]: P26 promises a 10,000-call depth limit that no longer exists (the native runtime uses a guard-page handler); P85
says sleep, cancel and unawaited-error reporting are "not built" but the runtime has all three; P65 (identity `==`)
above; P83 says list methods beyond `append` are not provided, superseded by P86. `docs/open-questions.md` still
marks item 13 as **asking** though D12bh settled it. The specification's status table lists `dict.get(key)` giving
None as "not yet" while P87 describes it as built. For a fresh agent the docs are the main source of truth, so the
drift costs real time.

## 4. Roadmap

Sizes are for one capable agent: **S** up to a day, **M** 2 to 5 days, **L** 1 to 3 weeks, **XL** more. They are my
estimates. Items are in ranked order within each group. "Parallel" means it can run beside the other listed work without
editing the same files.

Library modules are ranked in `docs/next-features.md`; they are not repeated here except where language work blocks them.

### (a) Quick wins

| # | Item | Why it matters | Size | Risks and dependencies | Parallel |
| --- | --- | --- | --- | --- | --- |
| Q1 | **Make lost LTO visible and fix the Linux toolchain**: warn once when falling back, add a test that LTO happened, install `lld` (with its libraries) or the plugin in `release/linux-setup.sh`, then re-measure the Linux column | The published Linux numbers are 1.9 to 2.8 times too slow on the three programs checked (3.3) | S | Coordinate with the Linux CI task. Without a linker plugin, `-Xclang -mlink-bitcode-file` gave 222 M instructions on fib against 183 M with LTO and 342 M without, so it is a usable second fallback | yes |
| Q2 | **Join instead of append in `compile_with`** | Self-compile 24.0 s to 9.9 s median here, identical output (3.3). Every compiler task runs it several times | S | `compiler.tom`, about 11 lines, plus a refresh of `tomatoc.ll` | short compiler slot |
| Q3 | **Cache the compiled runtime** per mode, clang version and runtime hash; use it in `run`, `build` and `tests/run.sh` | About 1.2 s off every `tomato run` (3.3), and it should shorten the 34-minute suite [I] | S | Stale cache: key it on the hash of the C file and of clang's version. After Q1, same lines | after Q1 |
| Q4 | **Range loops past 2^62** (in `TODO.md`) | Prints wrong numbers silently (3.1) | S | Compiler | short compiler slot |
| Q5 | **Honest errors for types that are written but not built**, instead of E318 "write its type" | Seven of my probes got advice to do what they had just done (3.6) | S | `compiler.tom` messages plus new ids | short compiler slot |
| Q6 | **Report write and close failures on text files** | Data loss on a full disk is silent (3.1) | S | Runtime only | yes |
| Q7 | **Refill `tests/known_gaps/` and fix the drifted docs** (3.7) | Agents treat those docs as the truth | S | Docs and test programs; needs question 6 | yes |
| Q8 | **Grow strings in place when the count is 1** | Makes `s += t` loops linear for every user, not only the compiler | S to M | Runtime; the hash or index cache must not see a changed string | yes |
| Q9 | **Bootstrap refresh policy**: refresh `tomatoc.ll` only when landing, not in every branch | Removes the merge hotspot (3.3) | S | `tests/run.sh` must accept a stale IR on branches but not on `main`. Question 7 | agree first |

### (b) Medium projects

| # | Item | Why it matters | Size | Risks and dependencies | Parallel |
| --- | --- | --- | --- | --- | --- |
| M1 | **Typed front end, first slice**: a `Type` class in place of type strings, named accessors for syntax-tree fields, the dict key kept in the type | M2 to M4 and B1 to B3 all get cheaper (3.5) | L | Touches most of `compiler.tom`. Require byte-identical IR after each slice, which is a strong safety check this project already has | no, one owner |
| M2 | **Optionals**: `int`, `float`, `bool` and tuples as optionals; narrowing by `is None`; compile-time checks if Davis wants them | Biggest gap in static checking (3.1) | M to L | Representation choice; checking may break existing programs. Question 1. Before M1 is possible but costs more | after M1 |
| M3 | **Dict keys beyond text**: int and bool first, tuples later; `set()`; set and dict comprehensions | `next-features` item 14 waits on it. The runtime hashes ints already (`tomato_rt.c:2794`) | M | Compiler mostly; tuple keys need hashing | after M1's dict slice |
| M4 | **Check pass that produces a typed tree**, then emission; several errors per compile | Basis for the language server and for new analyses | L | Generics restart (`NeedsEarlyCopy`) has to be redesigned. After M1 | no, one owner |
| M5 | **Resource cleanup** (`with`, or closing on last release) | Open files leak until exit; sockets and locks will need it | M | Question 5. `File` becoming reference counted is the cheap half | yes, runtime first |
| M6 | **Collector cost**: skip objects that survived, or count allocations instead of roots | 17% of the self-compile (3.2) | M | Correctness-critical; needs a fuzzer against the current collector | yes |
| M7 | **Formatter and `tomato test`** | Daily tooling; the test half is `next-features` item 3 | M | Formatter needs comments kept by the lexer, which drops them [V] | yes |
| M8 | **DWARF line info** (`!dbg`) | `lldb`, `gdb` and `perf` would show Tomato lines | M | `llvm.js` must skip the metadata | after M4, or a short slot |
| M9 | **Prebuilt Linux tarballs, and signed archives** | Linux install takes a 46 to 70 s compiler build and needs clang; `tomato update` has no signature | M | Programs still need clang to compile. Key handling is a decision | yes |
| M10 | **One generated header for shared layouts** (frame, box, error, pair) | The compiler and C keep them in step by hand (3.1) | M | Touches compiler and runtime | after M1 |
| M11 | **Bounds and item facts for lists** | matmul, the one benchmark over the target | M | Needs list-length and alias reasoning; better after M4 | after M4 |

### (c) Big bets

| # | Item | Why it matters | Size | Risks and dependencies | Parallel |
| --- | --- | --- | --- | --- | --- |
| B1 | **Sum types and `match`** | The compiler's `Node`/`Val` tags and the `Json` and `Toml` trees are hand-made sum types | L | Reopens D21a; syntax, exhaustiveness, relation to unions. Question 2 | design now, build after M4 |
| B2 | **Closures and bound methods** | Blocks callbacks, routers, `partial`, decorators (`next-features` section 8, item 5) | L | Function values are bare pointers today (`compiler.tom:397`); they need counting and collector tables. Question 3 | design now, build after M1 |
| B3 | **Real wasm**: `tomato build --target wasm`, and compiling IR to wasm in the playground instead of interpreting it | R10, and the 1,500-times gap (1.7) | L each | JavaScript interop is undecided. The compiler emits a small IR subset, which `llvm.js` already parses. Question 4 | yes, `site/wasm` only |
| B4 | **Language server** (errors, hover, go to definition, completion) | The first thing editor users miss | L | Needs M4; parser must recover from errors | after M4 |
| B5 | **Web server chain**: async toolkit, sockets, HTTP | R09. Order and sizes are in `next-features` items 8 to 10 | L to XL | Scheduler and frames are hand-written C. Add seeded string hashing first | yes, one strong agent |
| B6 | **Packages**: finish `import`, project file, lock file, git sources | Sharing code beyond `std/` | L | D24b is unfinished | after decisions |
| B7 | **C FFI** with pointers, text and structs | SQLite, zlib and system libraries without runtime patches | M to L | Safety boundary; no browser | yes |
| B8 | **Parallelism** by isolated heaps with messages | Many-core servers | XL | Runtime globals become per thread. Shared objects would need atomic counts and a concurrent collector, which I would not do | decision only |
| B9 | **New value representation, escape analysis or arenas** | Would remove allocation in `objects`-like code | XL | I rank it last: nine of ten benchmarks meet the target, and it touches every layer. Revisit after M4, when escape analysis has a tree to work on | no |

### How to run it across agents

1. **Now, in parallel**: Q1 then Q3 (one agent, `native/tomato` and release tools); Q6 and Q8 (one runtime agent); Q7
   (docs); Wave 1 of `next-features`; B3's design; M9.
2. **Short compiler slots, one after another**: Q2 first (it speeds up everything after it), then Q4 and Q5, together
   with the comma-tuple and slicing-leak tasks already running. Agree Q9 before this starts.
3. **One owner of `compiler.tom`**: M1 in slices, then M3 and M2, then M4. Library, runtime and website agents continue.
4. **Meanwhile, design with Davis**: B1 and B2. B5 runs on its own with a strong agent.

What I would leave alone: shared-memory threads, the 128-bit value pairs of D35a, and more tuning of single benchmarks
while their Linux numbers are wrong.

## 5. Questions for Davis

1. **Optionals.** Should using a `T | None` where a `T` is needed be a compile error unless the program tested it first
   (it is a run-time stop today)? I recommend yes, with narrowing by `is None`, and `int | None` working like `str | None`.
2. **Enums and `match`.** D21a put them off. Reopen it? I recommend yes, as a design task now.
3. **Closures.** Should a lambda see later changes to a captured variable (as in Python), or keep the value from when it
   was made? Capturing the value is simpler and makes fewer reference cycles.
4. **Browser.** Is the website a demo, or is R10 (web apps partly in Tomato) wanted soon? B3 depends on this.
5. **Cleanup.** A `with` block, or files that close themselves when the last reference goes? Both are possible.
6. **Placeholders.** May the placeholders that have become the language (lists, dicts, errors, Python positions, printing)
   be promoted to decisions? And for a class without `@eq`: P65 says `==` compares identity, the compiler rejects it.
   Which one is right?
7. **Bootstrap file.** May compiler branches leave `tomatoc.ll` stale, with one refresh when they land?
8. **Tuples.** Keep `tuple[T]` (any length) and `tuple[A, B]` (fixed) under one name, or rename the any-length form?
9. **D35a and D32a.** May they be restated as what is built: small ints are tagged words, large ones heap numbers with one
   owner?

Library questions (order of tracks, `bytes`, module-level state, native-only modules) are in `docs/next-features.md`
section 8.

## Appendix A. Measurements

All on the Linux box described at the top, at `812244d`, with clang 21.1.8 from the home directory [M].

| Step | Result |
| --- | --- |
| `install-native.sh` | 70.5 s |
| clang on `tomatoc.ll` plus runtime, no LTO (helper run) | 46.1 s, 195 MB peak |
| self-compile, today | 12.4 to 26.1 s over 11 runs, about half system time; 75 MB peak; output identical to `tomatoc.ll` |
| front end on a 6-line program | 0.05 s |
| `clang -O1 -flto program.ll tomato_rt.c` | 1.5 to 1.75 s in most runs, 6.3 to 6.5 s in two |
| the same with the runtime compiled once | 0.4 to 0.6 s in most runs, 1.1 to 1.4 s in three; identical binary |
| interpreter, `fib(22)` / `fib(26)` in Node | 0.89 s / 4.20 s; `print(1)` takes 0.6 to 1.0 s |
| native debug, `fib(36)` | 0.27 to 0.31 s |

**Test suite.** `tests/run.sh` in a copy of `812244d`, Node 22, no `WASI_SDK`: 530 passed, 1 failed, 34 min 25 s wall,
31 min 38 s user, finished 16:18 PST on 2026-11-23. The log has its closing summary, so a machine-wide `pkill` of test
runs at 17:17 that evening did not touch it. The failure, `wasm sort_stable`, hit the 5 s limit of the browser path and did
so again when re-run. The benchmarks in the suite are the tiny smoke inputs only.

**Not done.** The full benchmark run and `perf` profiling (`perf` is not permitted here). The helper agent that was to
do it was cut off by a server restart. I used the v0.51 results committed on `main` and Callgrind instead. No fuzzing was
done, and Safari, macOS and arm64 were not tested.

## Appendix B. Evidence that came from helpers

Three helper agents (runtime, compiler, wasm and tooling) read the code for this review. I re-read the sources behind the
claims that carry the conclusions: value representation, hashing, shifts, the release path, leak check, file writes,
type strings, borrowed registers, the compile restart, the link fallback, dict keys and function values. I recounted 471
positional field reads, 251 error sites, 276 type-predicate calls and 170 comparisons with type names. The rest of sections 1.4
to 1.7 and 3.1 (async frames, allocator, collector internals, duplicated paths) rests on the helpers' reading.
