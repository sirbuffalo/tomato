# Documentation review (the v0.51 tree)

What this review covered, what it fixed, and the judgment calls it left for the maintainer. Everything below was checked by
building the compiler from `compiler/bootstrap/tomatoc.ll` with clang 21 on Linux x86-64 and running the code, not by
reading alone: every code block of the website guide, the examples, the README commands (`install-native.sh`,
`tomato run/build/compile/explain/version/help`), `release/release.sh --help`, error and exit behaviour in `docs/errors.md`,
and the claims in the status table.

## Fixed in this review

- **README:** Linux (x86-64) and from-source install steps, the DMG, a quick-start block with real output, and a layout table
  that listed only part of `std/`, `release/`, `docs/` and none of `benchmarks/`, `tools/`.
- **docs/errors.md:** the first example now shows the `error[E227]` label the compiler prints; the stale "Tomato has no
  function values yet" example is replaced (`reduce` is the unavailable name now); the two runtime-error paragraphs that
  disagreed (`error: ...` or `error[E01]: ...`) are one account; library error classes listed; `tomato explain CODE [FILE]`.
- **Website guide (`site/guide.html`):** a Getting started section; a new "Lists, dicts, tuples and text" section (list
  methods, dict and text built-ins, dict literal inference, mixed tuples, tuple `for` targets, compact lists); a Files
  section (`open`, `read`, `write`, `close`, `IOError`); runtime error classes; `memoize`; a commands table that matches
  `tomato help` (`--entry`, `--llvm`, `explain [FILE]`, repl `:load` `:reset` `:quit`, `help`, `--color`, `--no-warnings`);
  the generics example no longer uses an undefined `Stack`.
- **Download page:** Linux, tarball and source install, libcurl/bash/curl needs.
- **Specification, provisional choices, decision inventory, open questions:** the status table said `dict.get(key)` and
  `str.strip(chars)` were "not yet", omitted most standard-library modules, list methods, error classes and tuple targets;
  P-entries and open questions that were settled are marked; broken table rows fixed; duplicate numbering fixed (see the
  commit for the full list).
- **site/index.html:** the speed paragraph disagreed with the committed results (Tomato beats Python on all ten, not nine).
- **docs/handoff.md, docs/style.md:** release process (`release/release.sh`, pkg and dmg), mixed tuples.
- **examples/**, **editors/vscode**, **benchmarks/README.md**, **docs/performance.md** (prose only), **site/benchmarks.html**:
  headers, grammar gaps (`yields`, `task[...]`, `Iterable[...]`), run options, stale "what the numbers suggest" list.
- **std/itertools.tom, std/math.tom:** stale header comments (same line counts, so no diagnostics move); the copies in
  `site/wasm/std/` were refreshed with the same `cp` that `site/wasm/build.sh` does (no wasm rebuilt).
- Generated copies refreshed with `site/build.sh` and `site/examples.sh`.

## Judgment calls (not done)

1. **`docs/releasing.md` contradicts itself** about which Mac holds the signing keys ("Davis's iMac" in the one-command
   section and in `release.sh --help`, "Davis's MacBook Pro" and "the build Mac has none of them" in the by-hand section) and
   names a byre client id for the MacBook that differs from `docs/handoff.md`. `docs/handoff.md` also names other people's
   devices. Needs the owner to say which is current.
2. **The website's Reference tab shows six documents** and leaves out `style.md`, `performance.md` and `releasing.md` (and
   the new `next-features.md`). Whether any of them belongs on the site is a call. `site/docs/PROVISIONAL.md` is the only
   upper-case copy (`docs/provisional.md`); renaming needs `site/build.sh`, `docs.html` and a test change together.
3. **`tests/run.sh` checks the site copies of four documents and PROVISIONAL, but not `errors.md`**, although
   `site/build.sh` copies it. Adding it to the sync loop is a one-line test change.
4. **There is no tutorial, and no standard-library reference.** The guide is one long page of dense paragraphs; each std
   module is documented only in the guide and in its header comment. A shorter "first hour" tutorial and one reference page
   per module (generated from the header comments) would help new users most. Also the guide has no troubleshooting section
   (what "clang not found" looks like, PATH, WSL on Windows).
5. **Supported platforms and clang versions are not stated anywhere.** Linux release tests use clang 21; macOS needs the
   command line tools; Linux aarch64, older clang and Windows (WSL) are untested or unknown. Someone should say what is
   supported and write it in the README and the Download page.
6. **Linux benchmark results are not shown on the site** (`benchmarks/results/linux-x86_64/` exists since v0.51; the Benchmarks
   page draws only the Mac numbers). `docs/performance.md`: the sections for text indexing, compact lists, refcount bookkeeping and the native cmp sort
   were relabelled v0.51 (checked with `git tag --contains`); "mandelbrot" and "integer ranges" still say "unreleased"
   because the loop-bounded range analysis (`bf8eb2ce`) is after v0.51, but the mandelbrot section mixes both and should be
   split by someone who knows what shipped. The old instruction-count table was refreshed from `instructions.md`. `benchmarks/run.sh` on Linux still writes an empty memory and
   OS in `results.md` (`128 cores, ,`: it uses `sysctl` and `sw_vers`).
7. **Decision numbering.** `docs/decisions.md` uses `D62a` for four different decisions (clock and cache, toml, requests, the
   `import m` note), and D17d has no heading (its text is inside D67a). Renumbering is a decision, not a typo fix.
8. **`tests/known_gaps/` holds only its README now**, so nothing enforces the spec's "Not yet" column any more (the spec says
   so since this review). Decide whether to restore one program per unbuilt rule.
9. **Historical text.** Large parts of `docs/provisional.md` (P35, P36, P47-P54...) and many decisions describe the retired
    Python prototype. An archive pass would make both files shorter and more honest.
10. **Import aliases** (`from toml import loads as tl`) are a parse error. If that is intended, say so in the spec; it is not
    mentioned anywhere.

## Suspected compiler and runtime bugs found while checking (not fixed; compiler source is out of scope)

- `set.discard(x)` is rejected (`set has no method 'discard'`) although the error lists `discard` among the set's methods
  (`no_method` in `compiler/src/compiler.tom`); `set_method` implements only `add` and `remove`. The lint's loop-change
  warning also lists `discard`.
- `c: list[int[length=8]] = []` fails with E318 "this variable cannot be given a type automatically, write its type such as
  name: Type = value" although a type is written; as a parameter type it gives E313. The message is wrong, and P86 documents
  compact lists of fixed-width ints.
- `uint[length=8](300)` is a run-time error (E09), not a compile error (D05x names it); dead code is not rejected;
  `rational(1, 0)` and `10 ** 400 / 1` in dead code are accepted (D05ap, D05ag).
- `@init` flow analysis (D12x, P16) is not implemented: a field set only inside an `if` is accepted. The docs now say so.
- `tomato explain E227` prints the raw template (`name '{}' is not defined{}`) for compile errors, which is correct
  but looks odd; the docs only promise class and message.
- The entry-input error (E157) says "int, bool or str" but floats and fixed-width integers work as inputs.
- `from toml import loads as tl` gives "expected the end of the line, but found 'as'" (see 11).
