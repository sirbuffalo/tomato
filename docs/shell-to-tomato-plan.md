# Replacing the shell scripts with Tomato entries

Status: a plan, written 2026-11-27 against main at `bfe99746` (VERSION 0.51, 1.0.0 not tagged). No code is changed by it.
Davis's decision: "no more shell scripts". The `tomato` command and the project's build, install, test and release steps become
entries written in Tomato. Three tasks run beside this one and are read here as they stand in their worktrees: `sys.run` in std
(not started: no changes yet), "Project layout and CLI" (`init`, `run`, `build` over `tomato.toml`) and "Test library 1.0"
(`tomato test` discovery). Numbers marked *estimate* are guesses to size the work, not measurements.

**Davis's answers of 2026-11-27 are applied below** (D130a): all six stages ship before the 1.0.0 tag (decision 1), one IR
(2), std and the runtime source embedded in the binary (4), Linux x86-64 and arm64 binaries plus a one-command build from
`tomato.ll` elsewhere (5), gzip and tar written in std (7). Decisions 3, 6, 8, 9 and 10 were not answered and stay marked
*recommended (open)*. Where the text below says "1.0" it means the 1.0.0 that these six stages gate; where it names a plan
number or a size it is an estimate, not a promise of a date.

## 1. Premises (decided by Davis)

1. **The shipped `tomato` is one precompiled program** (the CLI entries and the compiler together). Users never compile it, and
   there is no shell launcher in a package. `tomato build` compiles a user's project, and the release pipeline uses it to build
   the shipped binary.
2. **Users still need a system C compiler and linker** (`clang` or `cc`) to compile their own programs, in 1.0. The shipped
   `tomato` checks for a working one at first use and in `tomato doctor`, and says exactly what is missing and how to get it.
   Bundling LLVM or clang is not planned for 1.0; "ship our own backend" is a post-1.0 option only (decision 10).
3. No new shell. Both sibling tasks add shell to `native/tomato` (429 lines on main; 555 with the test library, 598 with the
   project layout, both written in shell). Stage 0 below says what to do about that.

## 2. What the numbers say (loaded host)

Measured on biggie (this host), Linux x86-64, clang 21.1.8, **load average 67 to 96 on 128 threads (loaded host, not quiet)**,
current `native/tomato` from this tree, an install in a scratch folder, median of 10 to 20 runs (min / max in brackets):

| What | Time |
| --- | --- |
| `sh -c true` (the floor for any script) | 6 ms (5 / 9) |
| `tomato version` (shell script start, `cat`, `echo`) | 33 ms (28 / 106) |
| a built hello-world binary, run | 15 ms (13 / 18) |
| `tomato compile hello.tom` (tomatoc alone, IR out) | 311 ms (267 / 591) |
| `tomato build hello.tom` debug, runtime cached | 668 ms (644 / 886) |
| `tomato run hello.tom` debug, runtime cached | 645 ms (592 / 3018) |
| `tomato run hello.tom --mode release`, runtime cached | 2006 ms (1775 / 3201) |
| first `tomato run`, runtime cache empty (debug / release) | 3847 ms / 3405 ms (one run each) |
| `clang --version` | 56 ms (50 / 63) |
| install from `compiler/bootstrap/tomatoc.ll` (`install-native.sh`, 8-part split build, includes the repl editor) | 23 s |
| the compiler compiles its own sources to IR (`ctool.tom`; the output equals the checked-in IR) | 13.5 s |
| one `clang -O1 -c` of the whole 18.3 MB IR (no split) | 41.6 s |
| `build-object.sh` (8-part split of the same IR) | 16.0 s (76 s of CPU) |

What follows from them:

- A compile and run of hello is 645 ms and the compiled program is 15 ms, so **the cost of a command is the compile and the
  link, not the script**. The shell script's own cost is about 27 ms (33 ms against 6 ms for `sh`). A compiled `tomato` starts
  like any compiled Tomato program: about 15 ms on this host, so the rewrite does not need to be faster than the script to be
  a win; it must not be slower.
- **Startup budget for the Tomato `tomato`** (loaded-host numbers; the quiet-host numbers are lower, and the release check
  must record the load it ran at):
  - commands that do no build (`version`, `help`, `config`, `explain`, `seed hash`, `doctor` without a compile): **at most
    33 ms**, today's figure. It must not read `std/`, the runtime or the cache folder to print its version.
  - `run`, `build`, `compile`: **within 5% of today's 645 ms** for a debug hello, in-process compile included. Compiling in
    the same process removes one process start (about 15 ms) and the IR pipe; the awk pass `inline_merge` over the IR is better
    moved into the compiler than ported (to check: the compiler writes every `@tomato_` call itself).
  - `test` over N files: at most 20 ms per file on top of compile, link and run.
  - The budgets are a timing check in `tests/` that reports, and fails only above twice the budget, so a loaded host does not
    fail the suite.
- **macOS first run.** `native/tomato-jsc.js` records that macOS checks every freshly built executable the first time it
  runs (0.7 s or more). A shipped, signed `tomato` pays that once after an install or update. It could not be measured on
  this Linux host; the first macOS release check must time it.
- The last four rows are only a contributor's cost (section 7).

## 3. Inventory: every shell script (26 files, 6,037 lines)

Found with `git ls-files | grep -E '\.sh$|^native/'`, plus the scripts embedded in other scripts. "User" means it is part of
what a user's installed `tomato` does on the user's machine; "dev" means contributor, CI or release only.

### 3.1 The `tomato` command (user)

| File | Lines | Job | What Tomato's std lacks today | Stage |
| --- | --- | --- | --- | --- |
| `native/tomato` | 429 (555 / 598 in the siblings) | dispatch, option reading, `run`/`build`/`compile` (calls `tomatoc`, then `clang` with LTO and fallbacks, `inline_merge`), `test`, `explain`, `config`, `seed`, `update`, `paint` (awk colors), `semver_cmp` (awk) | process start (`tomatoc`, `clang`, the built program, with exit status and signal death passed through), `which`, temp folders, cleanup on INT/TERM/HUP, `isatty` (exists: `terminal.is_tty`), timeouts, download, sha256 of a file, tar | 2 (`update`: 3) |
| `native/rtcache.sh` | 44 | the compiled-runtime cache: key = hash of flags, `clang --version`, runtime source; write to a temp name, rename; sweep files older than 30 days | process start (`clang --version`, the clang compile), `mkstemp`, `utime` (touch), directory walk with mtimes, `cache_dir()` (macOS `~/Library/Caches`, else XDG) | 2 |
| `native/tomato-repl` | 362 (bash) | the repl driver: session files, awk split into declarations and statements, compile and run the whole session each line, show only new output, `:load`/`:save`, jsc/wasm fast path on macOS, runs the line editor helper | process start with the terminal inherited (the editor needs the real tty), text splitting (str and `re` exist), temp folder, signals | 3b |
| `install-native.sh` | 98 | build the compiler from the IR, copy std, runtime, examples, wasm into a staged folder, swap it in atomically, link `~/.local/bin/tomato`; run by `tomato update` | process start, copy, copytree, chmod, symlink, atomic exchange of two folders, signals, parallel jobs, sha256 | 3 |
| `compiler/bootstrap/build-object.sh` + `split.awk` | 34 + 43 | compile the IR in 8 parallel parts and link them as one object (used by install, refresh and tests) | parallel jobs, temp folder; the awk is text work over an 18 MB file | 6 |

The shipped binary replaces `native/tomato`, `rtcache.sh` and `install-native.sh` on the user's machine (`tomato-repl` stays
until 3b, section 9). The macOS package also embeds a `preinstall` and a `postinstall` (in `release/pkg.sh`, a few lines each:
keep a foreign `tomato` as `tomato.old`, give the install folder to the console user). Package scripts can be any executable
on macOS (to verify on a Mac), so they become a small Tomato binary in stage 5.

### 3.2 Tests (dev and CI)

| File | Lines | Job | What std lacks | Stage |
| --- | --- | --- | --- | --- |
| `tests/run.sh` | 2,496 (94 `t_` functions, about 1,000 checks) | the suite: builds the compiler from the IR, checks the fixed point, runs every example, program, error text, negative test, memory (AddressSanitizer), wasm via jsc/node, CLI, install, update, release files; job pool with `-j`, output kept in order, longest first, load-aware; tiers `--fast`/full; `--times` | `sys.spawn` with timeouts and kill, process pool, `os.cpu_count`, `os.loadavg`, directory walk, copytree/rmtree, diff of two texts, `tar`, pty (the `.exp` files), PATH shims for failure injection | 4 |
| `tests/release_resume.sh` | 475 (141 checks) | sandbox tests of `release.sh --resume/--from/--restart`: a bare git repo as "GitHub", fake `gh`, `codesign`, `xcrun`, `pkgutil`, ssh; failures injected by files; signals sent to the script | `sys.run` with env and PATH, a signal to a child, `git` through `sys.run`, temp trees; the fakes become one multi-call Tomato program (see 10.2) | 5 |
| `tests/ci_report.sh` | 31 | turns FAIL lines of the log into GitHub annotations | text processing and printing only | 4 |
| `tests/error_templates.sh` | 35 | prints every compiler error template (awk) so `std/errors.txt` stays complete | text processing over `compiler/src/*.tom` (`re`, exists) | 4 |
| `tests/highlighter_lists.sh` | 56 | checks the lexer's keywords against the website highlighter and the VS Code grammar | text processing, `json` (exists) | 4 |

Also in the suite, and not shell: three `expect` (Tcl) scripts for the terminal and repl (`tests/*.exp`, 633 lines), five
Node/jsc helpers (`tests/*.js`, `native/jsc-on-node.js`, `native/tomato-jsc.js`: the WebAssembly path, which is JavaScript
because the browser is), and C helpers (`tests/*.c`). `run.sh` also writes three small `clang`/`curl`/`mv` shim scripts for the
update tests (it injects failures through PATH). The JS and C stay: they are not shell, and the browser path needs JS.

### 3.3 Release, site, benchmarks, tools (dev)

| File | Lines | Job | What std lacks | Stage |
| --- | --- | --- | --- | --- |
| `release/release.sh` | 858 | the 13-step release on the signing Mac (preflight, version, test, bump, linux, bench, snapshot, build, sign, commit, publish, push, summary) with state file, `--resume/--from/--restart`, ssh streaming, signal handling, load gates; embeds the Linux remote script | `sys.run` with streamed output and `tee` to a log, git, ssh, gh, load average, sleep, state file (key=value text, easy), semver (port of the awk), signals | 5 |
| `release/pkg.sh` | 73 | universal macOS package: arm64 + x86_64 `tomatoc` and repl editor, `lipo`, `pkgbuild`, `productbuild`, embeds the installer scripts | `sys.run` of Apple tools (macOS only), temp tree, file copy and symlink, sha256 | 5 |
| `release/sign-pkg.sh` | 69 | `codesign` every Mach-O, sign the package, notarize, staple | `sys.run`, polling | 5 |
| `release/dmg.sh` | 79 | disk image, signed and notarized | `sys.run` (`hdiutil`) | 5 |
| `release/build.sh` | 28 | tarball and `latest.json` | tar, copytree, sha256, text output | 5 |
| `release/perf-snapshot.sh` | 91 | the `docs/performance.md` section from benchmark results (awk) | text and `json` (exist) | 5 |
| `release/linux-setup.sh` | 91 | download clang, Go, Rust, Valgrind into a folder on the Linux machine | download, tar (xz, bzip2), `sys.run` (make, cmake), sha256 | 5 |
| `release/check-lto.sh` | 17 | does this clang's linker really do LTO (compile, `nm`) | `sys.run`, temp folder | 3 (in `doctor`) |
| `benchmarks/run.sh` | 296 | build and time every benchmark in up to 11 languages, median, JSON and a Markdown table | `sys.spawn`, `/usr/bin/time`-style memory (`rusage`), timing (`time.monotonic` exists), seeded shuffle (`random` exists), `json` (exists) | 5 |
| `benchmarks/count.sh` | 143 | instruction counts under Valgrind in a Lima VM | `sys.run` (`limactl`, `valgrind`), text | 5 |
| `site/build.sh`, `check.sh`, `examples.sh` | 17, 30, 14 | assemble the website, check it, write `examples.json` | copytree, `json` dump, text checks | 5 |
| `site/wasm/build.sh`, `sections.sh` | 56, 77 | build the wasm files with the WASI SDK; compare wasm sections (`od`, `cksum`) | `sys.run`, binary reads (`os.read_bytes` exists), CRC (`zlib.crc32` exists) | 5 |
| `tools/gen_case_table.py`, `gen_width_table.py` | 163, 102 | generate tables inside `runtime/tomato_rt.c` | Python, not shell; needs the Unicode data files (download) and text work | 5 (Davis's call, decision 8) |
| `compiler/bootstrap/refresh.sh` | 38 | rebuild the checked-in IR with the compiler it holds and check the fixed point | `sys.run`, temp folder, byte compare (`read_bytes`) | 6 |
| `.github/workflows/*.yml` | 3 files | call `tests/run.sh`, `tests/ci_report.sh`, `site/check.sh`, `site/build.sh` | change the call with each stage | 4 and 5 |

## 4. What the package holds, and what a user's machine needs

Today's Linux tarball builds the compiler on the user's machine (23 s here, 46 to 70 s unloaded) with `install-native.sh`; the macOS
package already ships a universal `tomatoc` and repl editor. Under the premise, **both ship a built binary**; the Linux build is
new work (`docs/architecture-review.md` M9 asks for it).

| In the package, next to `bin/tomato` | Why |
| --- | --- |
| `std/*.tom`, `errors.txt`, `builtin/` | read at compile time of the user's program |
| `runtime/tomato_rt.c`, `runtime/tomato_inline.ll` | linked into every user program (compiled once into the cache) |
| `examples/`, `VERSION` | the guide and `tomato version` |
| `wasm/` (five files and `tomato-jsc.js`) | the repl fast path on macOS only |

Replaced by the binary: `bin/tomatoc`, `bin/tomato` (script), `bin/tomato-repl`, `bin/rtcache.sh`, and (optionally, decision 3)
`bin/tomato-repl-edit` folded in as an entry.

**What a user's machine still needs:** a C compiler and linker, `clang` or `cc`, for every `tomato run` and `tomato build`; libc,
libm, pthread (and `dl` on Linux); `libcurl` only for programs that use `requests` (the runtime opens it with `dlopen`).
`tomato update` needs HTTPS (libcurl; today it needs the `curl` program); gzip and tar are in std (item I), so it needs no `tar` program.
**`tomato doctor`** (new) and the first `run`/`build` print what is missing, not a raw clang error. The logic is one module,
`cli/toolchain.tom`, shared by `doctor`, the first-run check, `install` and `update` (stage 3 has all of it; the binary of stage 2
only finds a compiler and prints the same fix text when none is found):
- `clang` or `cc` found and able to compile and link a one-line C file (so a missing linker is found too);
- LTO (what `release/check-lto.sh` probes) for `--mode release`, a warning, as the link fallback is today;
- `~/.tomato` and the cache folder writable; `libcurl` present (a note only);
- the message for a missing compiler names the fix and the exact line: macOS `xcode-select --install`; Debian and Ubuntu
  `sudo apt install clang`; Fedora `sudo dnf install clang`; Arch `sudo pacman -S clang`; Alpine `apk add clang musl-dev`.

**Linux binary portability (decided: Davis, 2026-11-27, decision 5; the floor is the writer's choice, not Davis's).** This host
has glibc 2.43, so a binary built here will not run on an older distribution. The release ships **two Linux binaries,
x86-64 and arm64, both dynamically linked against glibc and built on the oldest glibc we support** (in a container or a
toolchain folder, as `linux-setup.sh` does today), so each runs on that glibc and every later one. **The floor is glibc 2.34**:
it is what Red Hat Enterprise Linux 9 and its rebuilds (Rocky, Alma) ship, supported to 2032; Debian 12 ships 2.36 and Ubuntu
22.04 2.35, so both run it. Davis named Debian 12 as the floor or "whichever oldest you can justify"; 2.34 is the oldest
that is still a current enterprise release and it is also the glibc that merged `libpthread` and `libdl` into `libc`, so the
binary needs no separate library for them. Debian 11 (glibc 2.31) and Ubuntu 20.04 are out of support and are not targeted.
This is to be checked when the build container exists (that it has a clang new enough for the compiler's LTO checks and
that the binary runs on a Debian 12 and a Rocky 9 container); if 2.34 turns out not to be buildable, Debian 12's 2.36 is the fallback.
How each architecture is built and tested is open: x86-64 stays on biggie; for arm64 an arm64 Linux VM under Lima on the
signing Mac (Apple silicon; `benchmarks/count.sh` already uses Lima), or an arm64 CI runner, would run the whole suite.
musl and static linking are not shipped.

**Other systems** (Alpine and other musl Linux, the BSDs, other architectures) are not release targets: they build from the
checked-in `compiler/bootstrap/tomato.ll` with the one clang command of section 7, which is documented on the website
(download page) and in the bootstrap README. **Windows is not a 1.0 target** (section 11).

## 5. What std must gain (named and sized)

Sizes are *estimates*: Tomato lines plus C runtime lines. "Platform" means the C runtime has a POSIX path and the browser build
raises "not in the browser", the pattern `os` already follows (`_not_in_browser`).

| # | Addition | Used by | Size |
| --- | --- | --- | --- |
| A | `sys.run(argv, cwd, env, input, check, capture, timeout)` (sibling task): no shell, stdout/stderr captured or inherited, exit status, died-by-signal | everything | S-M, about 150 C + 120 T |
| B | `sys.spawn(...) -> Process` with `poll()`, `wait()`, `kill(sig)`, a line-streaming stdout, `tee` to a file, and an `async` form that works with `asyncio` | parallel tests and benchmarks, timeouts, release log streaming | M, 200 C + 150 T |
| C | files: `os.copy` (keeps mode), `chmod`, `symlink`, `readlink`, `realpath`, `utime`, `mkdtemp`, `mkstemp`, `walk` and `glob`, `rmtree`, `copytree`, `which`, `exchange(a, b)` (atomic swap of two paths: Linux `renameat2` with `RENAME_EXCHANGE`; macOS `renamex_np` with `RENAME_SWAP` on APFS; to verify on a Mac; where missing, two renames with undo, as `install-native.sh` does) | install, update, cache, tests, release | M, 150 C + 300 T |
| D | `signal`: `on(INT\|TERM\|HUP, handler)` that runs `finally` blocks and temp-folder cleanup, then exits 128+n; a way to send a signal to a child | every temp-folder user, release interrupt tests | S-M, 100 C + 40 T |
| E | `os.cpu_count`, `os.loadavg`, `os.cache_dir`, `sys.arch`, `os.uname` | cache, test pool, release load gates | S, 60 C + 40 T |
| F | `requests.download(url, path, https_only, max_bytes, timeout)`: stream to a file, `--proto =https` and redirect rule of `curl_safe`, `file://` only behind the test override | update, release, linux-setup | S, 40 C + 60 T (libcurl is already loaded by `dlopen`) |
| G | `hashlib.sha256_file(path)`: stream a file without a `list[int]` of its bytes | cache key, update, seeds, release | S, 40 T |
| H | pty for `sys.spawn(pty=True)` so the terminal tests need no `expect` | `tests/*.exp` | M, 150 C + 80 T (optional) |
| I | **gzip (deflate and inflate) and tar (ustar, with long names), written in Tomato** (`gzip`, `tarfile` modules; decided: Davis, 2026-11-27, decision 7, not the system `tar`). Reading and writing `.tar.gz` and plain `.tar`; entry modes, symlinks and times kept; a path that leaves the folder (`..`, absolute, a link out) refused when extracting; streaming, so a 15 MB archive is never one `bytes` in memory twice | update, install, `release/build.sh`, linux-setup, tests | **M-L, about 900 T (*estimate*) plus a C fast path for the deflate inner loop if the Tomato one is too slow (measure first)**; unsized by any review time, see below |

**Item I is sized by its parts, not by a duration.** Davis questioned the earlier plan's "a month of review", which was a guess
with nothing behind it, and it is removed. The work is: inflate (about 250 lines), deflate with LZ77 and Huffman coding
(about 350), gzip framing with its CRC (`zlib.crc32` exists; about 60), tar read and write (about 200) and `extract` with the path
rules (about 60), roughly 900 lines of Tomato, *estimate*. It is bigger than one more `os` function because correctness has
to be checked against two independent implementations: the acceptance of stage 1 below does that (round trips against the
system `gzip`, `tar` and `bsdtar` in both directions, a corpus of odd archives, truncated and hostile input, and the memory
and leak checks), and nothing in the plan assumes how long that takes. Item I is on the path of stages 3 and 5 (the update archive and
the release tarball), so it is built with stage 1, and the deflate speed is measured before the C fast path is decided.

What is already there and enough: `os.getenv/environ/putenv`, `getcwd`, `listdir`, `mkdir/makedirs`, `remove`, `rmdir`, `rename`
(atomic), `stat`, `read_text/write_text/read_bytes/write_bytes`, `ospath`, `time.monotonic`, `time.format_duration`, `hashlib`
(sha256 and others, streaming `update`), `zlib.crc32`, `re`, `json`, `toml`, `random`, `requests` (get, post, head), `socket`,
`asyncio` (Lock, Semaphore, Queue, Event), `terminal.is_tty`, `sys.argv/exit/platform/write_stderr`, `try/finally`. awk and sed
work in these scripts is string splitting, `re` and the existing `toml` and `json`; nothing new is needed for it.

## 6. The target: one program, entries, two folders

One compiled program, `cli/tomato.tom`, whose `@main` reads the first word and calls the entry of that name. Each command is a
function with its own entry marker, in its own file, so it is run and tested alone with the existing mechanism (D28a, D96a):

    tomato run cli/tomato.tom build src/main.tom -o x        # the same as: tomato build src/main.tom -o x

| Folder | Holds | Shipped |
| --- | --- | --- |
| `cli/` | `tomato.tom` (dispatch), `build.tom`, `run.tom`, `test.tom`, `init.tom`, `seed.tom`, `config.tom`, `explain.tom`, `update.tom`, `install.tom`, `doctor.tom`, `repl.tom`, `toolchain.tom`, `rtcache.tom`, `term.tom` (colors, `paint`, `semver`) | in the binary |
| `dev/` | `test.tom` (the suite), `release.tom` and its steps, `pkg.tom`, `bench.tom`, `site.tom`, `tables.tom` | no (the repository only) |

Size *estimate*: `cli/` about 1,200 lines of Tomato (for 430 to 600 lines of dense shell, the 44-line cache and the 98-line
installer), `dev/` about 4,000. `compiler/src` is 17.9 K lines, so a combined program is about +7% on the IR.

**One binary, not two.** `tomatoc` and `tomato` become one program, so a compile is a function call. The bootstrap file is then
the whole CLI: `compiler/bootstrap/tomatoc.ll` becomes `tomato.ll` and one clang command gives a working `tomato` (section 7).
The wasm build (`site/wasm/build.sh`) needs the compiler without the process code: the process, signal and archive functions
raise "not in the browser", and the WASI runtime stubs them. **Decided (Davis, 2026-11-27): one IR**, the compiler and the CLI
are one program, `tomato.ll`; the two-IR alternative (a smaller wasm, two 18 MB files in git) is dropped.

**Compatibility, 1.0.x.** D84a promises that 1.0.x releases behave alike and a minor may change behaviour. The CLI is part of
what scripts depend on: flags, exit statuses (0, 1, 2, 130, 143), what goes to standard output and error, the error texts and
colors, and the environment variables (`TOMATO_HOME`, `TOMATO_BIN`, `TOMATO_CACHE_DIR`, `TOMATO_CACHE`, `TOMATO_COLOR`,
`NO_COLOR`, `TOMATO_WARNINGS`, `TOMATO_UPDATE_*`). So **the contract is written down as tests before the rewrite**: the CLI
section of `tests/run.sh` (about 25 `t_cli_*` functions, plus `t_atomic_*` and `t_release_*`) is kept as it is and added to with golden files
for `tomato help`, `explain`, `config` and the error texts (`tests/cli_contract/`). A rewrite passes them unchanged. A deliberate
change goes in the changelog; in a 1.0.x patch there is none. **All six stages ship before 1.0.0** (Davis,
2026-11-27, decision 1; the earlier recommendation, 1.0.0 with the shell CLI and the rewrite as 1.1.0, is overruled), so the
1.x promise is made once, on the Tomato CLI, and no release under it ever shipped the shell one. The contract tests are
therefore the only thing that holds the rewrite to the behaviour of the 0.51 shell script, and they must be complete before stage 2 starts.

**A compiler bug that breaks the shipped CLI** is the new failure mode (today a miscompile breaks `tomatoc`, and the same
exposure exists, but the script around it still works). Defences, in order:
1. the release gate builds the CLI with the new compiler, checks that it reproduces itself (stage 2 of the suite, extended to the
   CLI), and runs the whole CLI contract and `doctor` against the built and signed binary on both systems before publish;
2. `tomato update` runs the staged binary (`version`, `doctor`, build and run hello, one `tomato test`) before the swap; a failure
   leaves the old install alone;
3. the update keeps the previous install as `$TOMATO_HOME/previous` (one generation, about 15 MB). A broken CLI cannot run
   `--rollback`, so the way back is one documented line, `mv ~/.tomato/previous ~/.tomato/native`, and the website says it;
4. the manual route needs no CLI at all: the bootstrap command of section 7 and, from any working `tomato`,
   `tomato compile x.tom > x.ll && clang x.ll runtime/tomato_rt.c -pthread -lm`.

## 7. The bootstrap, honestly

A machine with no `tomato` still has to turn something into the first compiler, and the only thing it can read is LLVM IR.
After stage 6, what is left that is not Tomato is **one documented command**, in `compiler/bootstrap/README.md`, and a
contributor's `tomato build`:

    clang -O1 -Wno-override-module -o tomato compiler/bootstrap/tomato.ll runtime/tomato_rt.c -pthread -lm   # add -ldl on Linux

- It needs clang, nothing else (no awk, no sh), as the README says today. It is the single-clang build: 41.6 s on this loaded
  host for the IR alone (6.6 to 7.1 s quiet on the Mac per the README), against 16 s with today's 8-part split.
- The split build is a speed-up, not a need. In stage 6 it moves into the compiler: `tomato build --jobs N` writes N modules
  directly and compiles them with `sys.spawn`, so `split.awk` and `build-object.sh` go (decision 9).
- **Once any `tomato` exists, `tomato build cli/tomato.tom -o tomato --mode release` builds the CLI from source** (this is what
  `refresh.sh` does today with the compiler it holds: it compiled the whole compiler in 13.5 s here, then clang). The shipped
  binary, a contributor's checkout build and the refresh all use it.
- `refresh.sh` becomes `tomato run dev/refresh.tom`: compile the sources with the compiler in hand, repeat until two IRs
  agree, write `tomato.ll`. The checked-in 18 MB IR, the fixed-point test and the "IR is current" test stay; they are what makes
  the one-command bootstrap safe.
- A fresh checkout on a bare machine: install clang, run the one command, then `./tomato install` (section 8).

## 8. Install and update

**Install.** The package is the install (macOS: the signed `.pkg`; Linux: the tarball, which holds the folder as it will lie).
For the tarball and for contributors, `tomato install [--prefix DIR]` is an entry of the binary itself: it copies the running
binary and the folders next to it into a staged folder `$TOMATO_HOME/.native.new.PID`, runs the new binary
(`version`, `doctor`), swaps, links `~/.local/bin/tomato`, and tells the user to add the folder to `PATH`, as `install-native.sh`
does. No installer script is shipped. `std/` and the runtime source are **embedded in the binary** (decided, Davis,
2026-11-27, decision 4; built after stage 3, step 3c of section 12): the install is one file plus `examples/` and `VERSION`,
no mixed-version errors are possible, an update is one rename, and a first run writes the runtime source to the cache keyed
by its hash (the cache is keyed that way already). The cost is that users cannot read or patch `std/` in place; they can
still compile a copy. Until 3c the package holds the folders of section 4.

**Update, and what it must keep** (rules in `docs/releasing.md` "How an update installs" and D43a, D84a; the atomic install has
no D-number of its own: decision 10, not yet answered, recommends recording one with stage 3): HTTPS only, including after redirects (`curl_safe`); the manifest
carries a valid 64-hex sha256 and an official URL; only an upgrade (SemVer precedence); a minor or major only with `--minor`; a
pre-release only with `--pre` or from a pre-release; the install is never changed in place; any failure or signal leaves the old
install as it was; leftovers of a killed update are cleaned up on the next one.

**Replacing the running binary.** On Linux and macOS a running program keeps its file, so the swap of the whole folder (or a
rename over the binary) does not disturb the running `tomato update`. Two cases need care and are tests:
1. the running process must read nothing from the install after the swap (it reads std and the runtime lazily today; the
   same hazard exists for a `tomato run` in flight, and a binary with std embedded, which is decided (decision 4), removes it);
2. a `tomato run` that starts during the swap must see a whole install. `os.exchange` (C in section 5) gives that on both systems
   where the file system supports it; the two-rename fallback is not atomic for a moment, as today.
A package install's `/usr/local/lib/tomato` stays writable for the console user (the `postinstall` of 3.1), so no `sudo`.

**macOS signing.** The package ships a signed `tomatoc`, but `tomato update` runs `install-native.sh`, which builds an unsigned
one on the user's machine (`docs/architecture-review.md`, line 195). With the binary in the update archive, an update
installs the **signed** binary. Files fetched by the program itself carry no quarantine mark, so Gatekeeper does not re-check
them; arm64 still needs at least an ad hoc signature (the signing step covers every Mach-O). To check on a Mac.

## 9. The repl

`native/tomato-repl` (362 lines of bash) is the hardest user-side script because it holds the terminal and a session. It stays
shell through stages 2 and 3 as a file in the package, which the binary runs with `bash` (a documented exception, ended in 3b),
because moving it does not change what users get and it needs rework, not translation. Stage 3b is "the driver in Tomato" that
`docs/decisions.md` D91a already lists as not done ("needs `subprocess`"): the session as a list in memory, a compile as a
function call (no `tomatoc` start per line, the cost today), the line editor run in the same process (decision 3), and the
macOS jsc path kept behind `sys.run` while it is wanted. Acceptance: the three `expect` scripts (`repl_history.exp`,
`terminal_pty.exp`, `todo_shell_pty.exp`) and the repl cases of `t_cli_repl` pass unchanged, and a repl line is not slower than
today (budget: at most the per-line time of today's script on the same host).

## 10. Tests and release

### 10.1 Running the suite in parallel

`tests/run.sh` is a job pool. It runs tests in parallel (`-j`, half the cores, fewer on a busy machine), starts the longest first,
prints each test's lines in the order they were registered, keeps a shared compiler and a shared runtime cache, and has two tiers.
In Tomato: `dev/test.tom` holds a table of tests (name, kind, estimated cost, expected output), a pool on `sys.spawn` (B) with a
`Semaphore`, and the same ordered printing, `--times`, tiers and the final count. Most tests are data (examples, programs,
errors, negative, input, known gaps, runtime errors: most of the checks): a loop over files that compiles, runs and
compares. They move first. The odd tests (memory under AddressSanitizer, wasm, packages, update, repl) move with the thing they
test; until then `dev/test.tom` can call the old `run.sh` functions (as one sub-process per old test), so stage 4 can ship
in pieces. Output is compared with the old runner's, line for line, before the old one is deleted.

### 10.2 The 141 release-resume checks

They are kept as checks, not rewritten as new tests. `tests/release_resume.sh` becomes `dev/release_resume.tom`, which builds the same sandbox
(bare repository, `url.insteadOf`, injected failure files, `TOMATO_RELEASE_TEST_BIN` first on PATH) and runs `dev/release.tom`
through `sys.run`. The fakes (`gh`, `codesign`, `xcrun`, `pkgutil`, ssh, and the three shims of `run.sh`) are executables on PATH, so
they cannot be std stubs. They become **one multi-call Tomato program** (`dev/fakebin.tom`, built once, then linked or copied under
each name; it dispatches on `argv[0]` like busybox) so no shell is left in the fixtures either. The signal tests need D (send a signal
to a child). Acceptance: the old script and the new one run side by side on the old release script and report the same `ok`/`FAIL`
names (141 and 141) before the release script itself is replaced; only then is `release.sh` ported, and the new suite must pass
again unchanged on the port. The release script's state file, steps and `--resume/--from/--restart` rules are specified by those
checks, and they are the acceptance test.

## 11. macOS, Linux, Windows

Differences the Tomato code must own (today each is a line of shell): `shasum` against `sha256sum` (gone: `hashlib`);
`sysctl vm.loadavg` against `/proc/loadavg` and the cache folder (E); `mv --exchange` against two renames (C); `-ldl` on
Linux; `stat -f %Su` for the console user; BSD against GNU `sed`, `awk`, `tar`, `mktemp` (gone with the tools);
`caffeinate` while releasing; a case-insensitive Mac file system (the `os_files` failure the bootstrap README names). The suite
runs on both (`tests.yml` on macOS, `linux.yml`), so each std addition needs a test that runs on both.

**Windows is out of scope for 1.0.** No installer, no `sys.run`, no signals, no `os.exchange`, the C runtime is POSIX, and the
tests and the release run on a Mac and on Linux. The plan keeps the door open by putting every platform fact in `sys`/`os`
(never in `cli/`), but it makes no Windows promise. Davis's answer to decision 5 confirms it: Windows is not a 1.0 target, and the website's download page says so. (Decision 6 itself stays open, *recommended*, for after 1.0.)

## 12. Stages

Each stage leaves the repository with fewer shell lines than it found and a green suite. **All six ship before the 1.0.0 tag**
(Davis, 2026-11-27): the tag is gated on the acceptance of stage 6 (the repository holds no `.sh` file, the release is made
by the Tomato tools), and on the dry run of stage 5. Stages 1 to 3 can still be released as 0.NN versions as they land, so users
get the std additions and the binary early; stages 4 to 6 are for the project itself and are not visible to users.

**Stage 0: freeze (no code; now).**
- Land the two sibling tasks as they are; no further command logic goes into `native/tomato`.
- Write the CLI contract tests of section 6 against main after both land.
- Acceptance: `tests/cli_contract/` passes on the shell `tomato`, and the current numbers of section 2 are in `docs/performance.md`.

**Stage 1: processes, files and archives in std (A to G, and I).** Additive.
- Std: A (sibling), B, C, D, E, F, G, and I (gzip and tar in Tomato). About 700 C lines and 1,650 Tomato lines in all
  (*estimate*, 900 of the Tomato being I); `H` is optional.
- Acceptance, per function: a test program in `tests/programs` that runs on macOS and Linux under the leak check; `sys.run`
  of `true`, `false`, a missing program, a killed child, large output on both streams (no deadlock), env and cwd, `check=True`;
  `os.exchange` while another process reads either name; `signal` cleans a temp folder on INT, TERM and HUP; `requests.download`
  refuses `http://` and an `http` redirect; `sha256_file` of a 100 MB file in under 2 s (to check) and the right sum; walk of a
  tree with a symlink loop; and the browser build raising the "not in the browser" error for each. For I: an archive made
  by std is read by the system `tar` (GNU and BSD) and `gzip -t`, and an archive made by them is read by std (long names, a symlink,
  an empty file, a sparse or pax header it does not support refused with a clear error); extraction
  refuses `..`, absolute paths and links that leave the folder; a truncated or corrupt `.gz` fails with an error, never a crash;
  the leak check passes; the deflate speed on a 15 MB tarball is measured and written down.

**Stage 2: the CLI as entries, shipped as a binary.**
- `cli/` for `init`, `build`, `run`, `compile`, `test`, `explain`, `config`, `seed`, `version`, `help`, the runtime cache, and the compiler-presence message; the
  program, built by `tomato build` in the release pipeline, replaces `bin/tomatoc` and the script in the Mac package and in
  new Linux tarballs for x86-64 and arm64 (the release scripts get a small edit for this; they are replaced in stage 5).
- `native/tomato` stays in the checkout for contributors until the contract tests pass on the binary, then it is deleted;
  `tomato update` from an existing 0.51 shell install to the first binary release uses the old script's update, which extracts
  the archive with the system `tar` and runs `install-native.sh` from it: so the archive of that one release carries a
  copy-only `install-native.sh` that release tooling writes into it (it is not a file in the repository, so stage 6's "no `.sh`
  in the repository" holds), and the next release drops it. The hop is a test; the archive must unpack with GNU and BSD `tar`.
- Acceptance: all CLI contract tests and the whole current suite pass with the binary; the startup budget of section 2 on both
  systems; a PATH with no compiler gives the fix text; the binary reproduces itself; the same program through the old and the new
  `tomato` gives the same IR; signals during `run`, `build` and `test` leave no temp folder or cache file.

**Stage 3: install, update, `doctor` (3) and the repl (3b).**
- `cli/install.tom`, `cli/update.tom`, `cli/doctor.tom` with the full `toolchain.tom`, `install-native.sh` deleted; `previous`
  kept and `tomato update --rollback`; the update unpacks its archive with std (item I). 3b moves the repl driver (section 9).
  **3c: embed `std/` and the runtime source in the binary** (decision 4), after 3 and 3b work: the install holds the
  binary, `examples/` and `VERSION`; the runtime is written to the cache by hash on first use; a test runs `tomato` with the folders
  of std moved away.
- Acceptance: `doctor` and the first run with no compiler, a compiler that cannot link and one without LTO, on both systems,
  with the exact fix line for macOS and each named distro; the update and install tests of `run.sh` (`t_atomic_*` and the `t_cli*` update cases: interrupt at each point,
  full disk, an unwritable `/usr/local`, a stale manifest, a bad checksum, an `http` URL, a foreign `tomato` kept as
  `tomato.old`) pass unchanged; a new update test swaps while a `tomato run` is in flight and while `update` itself runs; the
  staged binary that fails its smoke test is refused; `--rollback` works from a working `tomato`, and the documented `mv` works
  from a broken one.

**Stage 4: the test runner.**
- `dev/test.tom` as in 10.1, `ci_report`, `error_templates`, `highlighter_lists` as entries; the three workflow files call it.
- Acceptance: for the same tree, the Tomato runner and `run.sh` print the same results (names and verdicts) on macOS and
  Linux, in the fast and the full tier; wall time within 10% of the old runner at the same `-j` (loaded-host numbers labelled);
  an interrupted run leaves nothing behind; `--times` matches.
- Status (first slice, 2026-11-27): `dev/test.tom` runs the scheduler, ordering, tiers, `-j`, `--times`, the count and the exit status; the
  tests not yet ported are run one process each by `tests/run.sh` through `TOMATO_TEST_BRIDGE` (the plan, prep and job modes of that
  script), the ported ones (examples, programs, AddressSanitizer builds, rejected programs, error texts, runtime errors, known gaps,
  WebAssembly programs, error templates, highlighter lists) in Tomato; `ci_report`, `error_templates` and `highlighter_lists` are entries.
  Every process and file call is in `dev/host.tom`, to be swapped for stage 1's std. Not yet: the workflows still call `run.sh` (they
  switch with the last slice, when the acceptance above is met on both systems); an interrupt removes no folder until `signal` is
  in std (a run killed any way is swept by the next run); most of the ~100 other tests are still shell.

**Stage 5: the release tools.**
- `dev/release.tom` (the 13 steps, state, resume), `pkg`, `sign`, `dmg`, `build`, `site`, `perf-snapshot`, `bench`, `linux-setup`, the
  Python table generators (decision 8), the package's installer steps, `.github` calls. `fakebin.tom` first.
- Acceptance: the 141 checks of `release_resume`, run through the port, name for name; a `--dry-run` of the whole release on the
  signing Mac and on Linux with a real notarization (the TODO.md item "Run `release/release.sh --dry-run`" is its precondition,
  not a substitute); the produced `.pkg`, `.dmg`, tarball and `latest.json` are byte-compared with the old pipeline's, except the
  files that name times and paths.

**Stage 6: the bootstrap (last).**
- `tomatoc.ll` becomes `tomato.ll` (one IR, decision 2); `bootstrap/README.md` and the download page carry the one command; `refresh` is an entry; the split build is
  `tomato build --jobs`; `build-object.sh`, `split.awk`, `refresh.sh` are deleted.
- Acceptance: on a machine with only clang and a checkout, the one command gives a `tomato` that passes the CLI contract; the
  fixed point holds; `tomato build cli/tomato.tom` from that binary gives the same binary; a checkout with no `sh` on PATH
  builds and tests. The repository then holds no `.sh` file (`git ls-files | grep -E '\.sh$'` is empty, and a test says so).
- **This acceptance, with the dry run of stage 5, is the gate of the 1.0.0 tag** (`docs/releasing.md`).

## 13. Davis's decisions

Answered on 2026-11-27 (recorded as D130a; the sentence after each is what the plan did with it):

1. **Before or after 1.0.0? Answered: all six stages before the 1.0.0 tag**, not 1.1. The recommendation (tag 1.0.0 with the shell
   CLI) is overruled. 1.0.0 is gated on stage 6 and the dry run of stage 5; sections 6 and 12 and `docs/releasing.md` say so.
2. **One IR or two? Answered: one**, the compiler and the CLI are one program, `tomato.ll`; process code is stubbed in the browser.
4. **Embed std and the runtime source in the binary? Answered: yes**, after stage 3 (step 3c). `examples/` and docs stay as files.
5. **The Linux floor. Answered: prebuilt binaries for Linux x86-64 and arm64, glibc, built on the oldest glibc justified; Mac as
   today; every other system builds from `tomato.ll` with one clang command; Windows is not a 1.0 target.** Davis offered Debian 12
   or the oldest justifiable floor: the plan names glibc 2.34 (RHEL 9, which Debian 12 and Ubuntu 22.04 exceed), as the writer's
   choice to confirm (section 4). The earlier "arm64 after 1.0" is overruled.
7. **Archives. Answered: write gzip and tar in std**, not the system `tar`. Davis questioned the "a month of review" estimate;
   it was a guess and is gone, and item I of section 5 is sized by its parts and acceptance instead.

**Not answered yet; the recommendation stands and the item stays open:**

3. **Fold the repl editor into the binary** as an entry (one file, no second universal build) or keep `tomato-repl-edit`.
   *Recommended (open):* fold it in, in stage 3b; it is a Tomato program already.
6. **Windows.** *Recommended (open):* out of scope for 1.0, stated on the website and in this plan; reconsider after 1.0 when `sys` is
   proven on two systems. (Davis's answer to 5 already says Windows is not a 1.0 target and asked that the site and this plan
   say so; the site's download page and section 11 do. The decision stays open for what comes after 1.0.)
8. **The Python table generators in `tools/`** (`gen_case_table.py`, `gen_width_table.py`) break "no Python" (D46a).
   *Recommended (open):* port to Tomato in stage 5 (they need Unicode data files downloaded and checked; 265 lines of Python);
   keep `gen_ctype_table.c`. Stage 6's "no `.sh`" gate does not cover Python, so this does not gate 1.0.0 unless Davis says so.
9. **The bootstrap split build.** *Recommended (open):* the one `clang` command in the README, and the fast build through
   `tomato build --jobs` once a `tomato` exists. Do not keep an awk split for a bare machine; 41 s (loaded) once per fresh
   checkout is acceptable.
10. **Record the atomic install as a D-number** (D43a and D84a cover the update rules; the atomic swap is only in
    `docs/releasing.md` and comments)? *Recommended (open):* yes, with stage 3, with the previous-install rule. Post-1.0, not decided
    now: our own backend so no `clang` is needed, and signed update archives (`docs/language-design-review.md` 11.3).

## 14. Risks that remain

- A miscompile of the CLI by the compiler that builds it: reduced by the four defences of section 6, not removed.
- Stages 4 and 5 are large (about 5,000 lines) and give users nothing visible, and with decision 1 they are on the path to the
  1.0.0 tag: the date of 1.0.0 is set by the slowest stage and the plan gives no duration for any of them. The stages are still
  independent in what they need (4, 5 and 6 need stages 1 to 3, not each other), so they can run in parallel and a stage can be
  reviewed alone; if Davis wants to ship earlier, the decision to move a stage after 1.0.0 is his to reopen.
- Two architectures and two Mac sides mean four binaries to build, sign and test per release; the arm64 Linux host is not chosen.
- gzip and tar written here are new code on the update path: a bug in them could refuse or corrupt an update. The defences are the
  checksum of the archive, the staged smoke test of section 6, and the cross-tests against the system tools in stage 1.
- `sys.run` is on every critical path, and the 1.0.x CLI promise holds only as far as the contract tests reach.
