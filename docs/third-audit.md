# Third pre-1.0 audit: the work since the second audit

Date: 2026-11-27. Base: `main` at `61350155` (merged again with `5c714873`, the CLI contract tests, before finishing). The bar is
Davis's for 1.0: "polished and good". The earlier audits are `docs/language-design-review.md` and the second audit (`6f94caa6`,
`2cd11515`). This one looks only at what landed after `2cd11515`: 25 commits, about 11,800 lines.

## How it was done

Five auditors, one per area, each with the same brief: build `tomato` from `main` with `./install-native.sh` into a temporary
`TOMATO_HOME`, write real programs and commands, and report only what they reproduced, each with a minimal repro. They did not edit
files. The lead checked each report, reproduced what it fixed, fixed the findings that matter in small themes, and recorded the rest in
`TODO.md` with their repros. The release scripts' signal traps were checked by the lead.

| Area | What was checked |
| --- | --- |
| M: manifest, layout, CLI, seeds | `tomato init/run/build/test/config`, `[project]`, `[seed]`, `[seeds]`, `[test-seeds]`, `[build]`, `[build.ENTRY]`, the user's `config.toml`, strictness (unknown keys, types, duplicates, bad TOML), raw and `File` inputs, `--`, path and git seeds, `seed install/add/remove/vendor/check/hash`, `--locked`, `--offline`, `--yes`, the lock's stability, the store, hash checks, the foreign-symbol prompt |
| T: entry markers, testing | dotted `@x.y` markers and their errors (E583, E584, E520 to E522), `tomato test` (discovery, options before the file, `--filter`, `--timeout`, `--mode`, `-v`, crashes, exit statuses, `FILE ENTRY INPUTS`), `std/testing` and its diffs, every example of `docs/testing.md` |
| S: std | `sys.run`, `run_async`, `spawn` and `Process` (arguments, errors, signals, large output on both pipes, file descriptors, zombies), `File` after `close()`, `Error` `@init`/`@str`, `itertools`, `terminal`, `progress_bar`, `datetime` offsets, the Unicode 16 width table (all 1,114,112 code points against Python 3.14), huge float powers, the docs' examples |
| O: optionals, narrowing, repl | `int`/`float`/`bool` `| None` everywhere a value can go, `d.get`, release mode, AddressSanitizer runs, about 40 narrowing cases looking for a program that compiles and uses `None` as a value, the compile errors and `tomato explain`, repl redefinition and the completer |
| D: docs | `site/docs` copies, decision ids, E-codes (every code in `docs/errors.md` through `tomato explain`), `README.md`, `tomato help`, `docs/manifest.md`, `docs/testing.md`, `site/guide.html`, `TODO.md` |

## Fixed in this task

**Bugs**

1. **A big number in an optional key was freed twice (crash).** `x: int | None = 10 ** 40` then `hash(x)`, a `dict[int | None, int]`
   key, a `set[int | None]` element or `in` aborted with `double free detected` (also `float | None` with `10.0 ** 400`). The
   compiler's key helper calls `_cast(x, 'int')` after `if x is None: return`, where D102a has already narrowed `x` to a borrowed `int`,
   and `_cast` marked it as owned, so `hash()` freed it and so did the function's end. Fix: `_cast` of a value that already has the
   type returns it unchanged (`compiler/src/compiler.tom`). Test: `tests/programs/optional_values.tom` (also in the ASan list).
2. **`Process.wait()` hung on a program that wrote more than a pipe holds.** `p = sys.spawn([...])`, `await p.wait()` before reading:
   the child blocked on its full pipe and never ended. `wait()` and `done()` now pull both pipes into the streams each time they look
   (`std/sys.tom`). Test: `tests/programs/sys_async.tom` (300 KB and 200 KB on the two streams, then `wait()` first).
3. **A timed-out test left the programs it started running.** `tomato test --timeout 2` on a test that runs `sys.run(['sleep', '97'])`
   failed the test but left `sleep 97`. The runner now lists the test's whole process tree (`pgrep -P`) and stops all of it
   (`native/tomato`).
4. **A test's input depended on `--timeout`.** Without it a test inherited the terminal (and one that read input waited forever);
   with it the test read `/dev/null`. Now a test always reads `/dev/null`.
5. **A big-number entry input with a default leaked.** `def main(n: int = 3)` run with `99999999999999999999999` printed
   `warning: 1 big number(s) were never freed` (also in built programs). The entry glue frees the parsed number (but never the
   default). Test: `t_cli_explain` in `tests/run.sh`.
6. **`@a . b` was accepted as `@a.b`.** A dotted marker is now one word; spaces around a dot are E335 with a hint. Test:
   `tests/errors/marker_spaced.tom`.
7. **`progress_bar.update(-n)` drew `-167%|`.** The count shown is clamped at 0.
8. **The seed commands' temporary file was left behind on Ctrl-C** (at the symbol prompt or during a git fetch): it now has the
   same traps as the rest of `native/tomato`.

**Messages**

9. `tomato test f.tom --entry x` said to move `--entry` before the file, but `tomato test` has no `--entry`. The hint now names only
   real options.

**Docs**

10. The entry-marker errors were documented as E587/E588 (those are `sys.run`'s timeout and `ProcessError`); the compiler gives
    **E583/E584**. Fixed in the changelog, the specification, `provisional.md`, D96a and the inventory.
11. **D101a was used twice** (`progress_bar` and the git seeds). The `progress_bar` entry is now **D105a** (D103a and D104a went to work that landed meanwhile), placed after D102a, with an
    inventory line; P68 points to it. (D62a and D76d are older duplicates, left alone.)
12. `tomato test FILE --entry test.NAME` (D96a's form, replaced by D97a's `tomato test FILE test.NAME`) was still in the specification,
    the inventory and the wave 2 sheet; D96a now says what changed.
13. The changelog said `seed add` and git seeds were not built; it now has their entry and the fixes above. `site/guide.html`'s
    command table lists the seed commands. `docs/package-registry-design.md` no longer says "nothing is built".
14. `[seeds.test]` (gone since D94b) in `docs/testing.md` and a comment of `native/tomato`; `std/errors.txt` E570 cited D99a for git
    seeds (D101a).
15. `docs/manifest.md`: E582, E583, E584, E593 and E594 were in no doc; a `float` input cannot have a default; the user config is
    `$TOMATO_HOME/config.toml` when that is set; a module shares what it marks `export` (the examples failed without it).
16. `docs/testing.md` showed a failure with `(raised on line 5)`; the real output starts in `std/testing.tom` (line 306). The doc now
    shows the real text and says where the test's own line is; the output was made better afterwards (see below).
17. `progress_bar`'s comment and D105a said plain output starts at 0%; it starts at the first update.

The bootstrap IR (`compiler/bootstrap/refresh.sh`), the wasm files (`site/wasm/build.sh` with WASI SDK 24; only `tomatoc.wasm`
changed) and the `site/docs` copies were regenerated, not edited.

## Open (recorded in `TODO.md`)

The rows marked fixed were done afterwards (D107a: the manifest and seed commands, `itertools`, `progress_bar` and `sys.run`; `progress_bar([])` stays E184 for the literal `[]`, whose type nothing gives, and the comment now says so).

| Id | Kind | What | TODO item |
| --- | --- | --- | --- |
| S2 | bug (fixed) | A subclass's `@str` under another method name is ignored when the static type is the parent (`catch Error as e: print(e)`) | Make `@str` dispatch by the object's class |
| M2 | rough (fixed) | Manifest key errors name the file but not the line | fixed (D107a) |
| M3 | rough (fixed) | A bad user `[build] mode` is reported only when nothing overrides it | fixed (D107a) |
| M4 | rough (fixed) | An option with no value prints the 26-line help (the CLI contract pins it, so the fix changes golden files) | fixed (D107a) |
| M5 | rough (fixed) | `tomato test` in `src/` does not find the project's `tests/` | fixed (D107a) |
| M6 | rough (fixed) | `[seed-store] vendor = "."`, `"src"` or `""` accepted; a file gives a raw E509 trace | fixed (D107a) |
| M7, M8 | rough (fixed) | A symbol added to a locked path seed is not asked about by a build; `src/X.tom` shadows a seed's `X` silently | fixed (D107a) |
| M9 | rough | `--locked` on a changed path seed says the manifest does not match | (already in `TODO.md` from the CLI contract task) |
| M10, M13, M14 | rough (fixed) | `tomato init '../x'` accepted; `seed check` passes `TODO:` placeholders; a damaged store copy is not refetched | fixed (D107a) |
| O2 | rough | repl: a redeclaration after an assignment gave a wrong E292. Main's D104a (merged during the audit) removes the error, but the replay now runs the old `x = 3` after the new declaration: `x: int \| None = None`, `x = 3`, `x: int \| None = 7`, `print(x)` prints 3 | not in `TODO.md` (offered as a follow-up, not picked) |
| O3 to O5, D9 | rough (fixed) | No hint that fields are not narrowed; `[1, None]` has no hint; E458/E313 point at the `def`; E340 for a function that is not `export`ed | Smooth the optional and union compile errors |
| S3 to S5 | rough (fixed) | `itertools` accepts negative `r`; `break` out of a terminal `progress_bar` leaves the line open; `progress_bar([])` is E184; a missing `#!` interpreter reads as a missing script | fixed (D107a) |

**Resolved after the audit** (the `tomato test` items, T4 to T9, T11 and T12): a failed check names the file and the line of the test, in
the first line and in the trace (`at main (tests/a.tom line 6)`, the framework's frames written `testing.NAME`; release mode says that
it keeps no trace); text with a space at either end is shown in quotes with a caret; an uncaught error in an `@test` function shows its
class and `assert_raises` names the class it got (and says when the name is no standard class); a long output keeps its first 40 and its
last 60 lines; a file whose tests were all skipped is skipped; "no function is marked @x" lists the entries of the program; and
`@test.x` before `export def` says that `export` goes first.

Repros for the table, in brief (the TODO items have the rest):

```
# S2
class Own(Error):
    @str
    def show(self) -> str:
        return 'own:' + self.message
# try: raise Own('x') / catch Error as e: print(e)   prints x, not own:x

# T5 / T9: assert_equal('a ', 'a')  ->  expected a, got a
#   a file whose only @test calls skip('x')  ->  counted as 1 passed

# M5: tomato init p && cd p/src && tomato test   ->  error: no tests folder here
# M6: [seed-store] vendor = "tomato.toml" then tomato seed vendor  ->  error[E509]: NotADirectoryError ... at makedirs (line 163)
# O2 (repl, piped): x: int | None = None / x = 3 / x: int | None = 7 / print(x)  ->  3 (was E292 before D104a)
# S4: permutations([1, 2], -2) gives every permutation; combinations([1, 2], -1) gives []
```

Not counted as findings: `1e308 * 10.0` prints `1e+309` and `float('inf')` is E18 (floats have any exponent, D77a and
`docs/bigfloat-design.md`); `a + 1` on an un-narrowed `int | None` is a run-time E10, not a compile error (D94a; a warning there
would be a design change); `sys.run` with no timeout waits for a backgrounded grandchild that holds the pipe (as Python does).

## What held up

- **Narrowing is sound.** About 40 programs looked for one that compiles and then uses `None` as a value (early exits, `and`/`or`/`not`,
  `while`, `elif`, assignments in loops, `try` and nested ifs, tuple assignment, conditions that must not narrow); none did, in debug
  and release, and the ASan runs were clean apart from the crash fixed above.
- **The manifest reader is strict and clear.** No crash or silent acceptance among the bad manifests tried; the lock is sorted and
  identical on every re-install; hash mismatches in the store and vendor copies are caught on every build; consent works at a
  terminal and refuses without one.
- **`sys.run` and `Process`** pass arguments exactly, classify start-up failures, handle 300 KB on both pipes and 2 MB of input with no
  deadlock, and leak no descriptors or zombies over 300 runs (`/proc/self/fd`).
- **`File` after `close()`** follows D93a, and a `for` loop over a file that is left early closes it (D82a).
- **The width table** matches Python's Unicode 16 data everywhere except U+00AD and U+110BD/U+110CD (format characters drawn one
  column wide, as `wcwidth` implementations do).
- **The release scripts** trap INT, TERM and HUP and remove their temporary folders on every exit (`release.sh`, `pkg.sh`,
  `sign-pkg.sh`, `dmg.sh`, `check-lto.sh`, `perf-snapshot.sh`); `release_resume.sh` covers it. `linux-setup.sh`'s LTO probe folder is
  not trapped, which leaks one small folder only if the setup is interrupted at that point (not worth a change).
- **Docs:** the `site/docs` copies were in sync; every code in `docs/errors.md` explains; `tomato help` lists every flag and every flag
  works; README's commands run as shown.

## Verification

- Each fix was reproduced before and checked after on a fresh install from this branch (`install-native.sh` into a temporary
  `TOMATO_HOME`); the old install still crashes on the new `optional_values` lines and hangs on the new `sys_async` lines.
- `tests/cli_contract/run.sh` (merged from `main` during the task): 440 checks, all passing on this branch. A change that made a
  missing option value print one line instead of the help was taken out again because the contract pins the help; it is a TODO.
- The full suite (`tests/run.sh`) was run once at the end; its result is on the task's merge card.
