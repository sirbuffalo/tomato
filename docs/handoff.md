# Handoff (for a fresh agent)

**Project:** Tomato, a statically typed, reference-counted language with indentation syntax, compiled through LLVM. Owner: Davis McDowell (`davis@fc.run`). He decides all language semantics; his messages are short and typo-ridden, so state your reading back and flag uncertain ones "reading to confirm". Where syntax is undecided use a placeholder and log it in `docs/provisional.md`.

**State (v0.16, repo `sirbuffalo/tomato`, public):**
- The compiler written in Tomato (`compiler/src`) is the **only** implementation; it compiles itself (fixed point). `compiler/bootstrap/tomatoc.ll` is its own IR (regenerate with `compiler/bootstrap/refresh.sh`). The Python prototype was **deleted on Davis's order** (still at git tag `v0.5`, e.g. `git show v0.5:tests/test_more.py`). Do not add Python.
- `runtime/` is the C runtime, `std/` the standard library, `native/` the `tomato` command and repl (shell), `site/` the website (tomato.davismcd.com, GitHub Pages; compiles and runs in the browser with WebAssembly: `site/wasm`, an LLVM IR interpreter in `site/wasm/llvm.js`), `editors/vscode` the grammar, `release/build.sh` builds release archives, `tests/run.sh` is the whole test suite (clang only; macOS jsc for the wasm path), `tests/known_gaps/` holds a program per decided rule not built yet.
- Releases are GitHub releases `v0.N` with `tomato-N.tar.gz` and `latest.json`; `tomato update` reads it. DNS CNAME is set in Cloudflare; "Enforce HTTPS" on the Pages settings is pending certificate issuance.
- `int` is 64-bit and stops on overflow (D05c wants unlimited). Not built: float literals, mixed arithmetic, `//`, `**`, `rational`, bitwise operators, UTF-8 literals, top-level code, unions, `x in Type`, tuples, `*args`/`**kwargs`, keyword arguments, `@add`, constant-error rejection, the pre-run type pass, `bundle`, `explain`. The status table in `docs/specification.md` is authoritative.

**How to work here:**
- Run `tests/run.sh` (set `WASI_SDK` to a WASI SDK folder to also rebuild the wasm files). After changing `compiler/src`, run `sh compiler/bootstrap/refresh.sh`; after changing the compiler or runtime, rebuild `site/wasm` with `site/wasm/build.sh`; bump `VERSION` and `site/config.js` together, run `release/build.sh` and `sh site/build.sh`.
- Git: commit with byre's snapshot tool; **never push this branch's history** (two old commit subjects mention chat passwords). Push one squashed commit onto `origin/main`: `git fetch origin; T=$(git write-tree); C=$(git commit-tree $T -p origin/main -m "..."); git push origin ${C}:refs/heads/main`, then `gh release create vN release/out/tomato-N.tar.gz release/out/latest.json`.
- Davis's MacBook is client `cli6qNVzVPIybU` (when connected); update it with `tomato update`. Never touch Ian's or John's devices.
- Docs: add each decision to `docs/decisions.md` (before "Pending discussion"), a numbered line in `docs/decision-inventory.md`, a bullet in `docs/specification.md`; D46a retired Python.

**Open follow-ups, in order:** unlimited-size `int`; float literals and mixed arithmetic, `//`, `**`; top-level code; constant errors in dead code and the pre-run type pass; UTF-8 literals; `rational`, bitwise operators, unions, tuples, varargs, keyword arguments, `@add`; sign release archives; Enforce HTTPS; check the repl's arrow-key history in a live terminal.

**To save usage:** the reviewer keeps finding ~5 issues per round about the deleted Python tests and docs; most are already recorded. Prefer real feature work over more review rounds.
