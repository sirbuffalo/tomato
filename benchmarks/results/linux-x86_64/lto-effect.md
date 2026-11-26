# What link-time optimisation does to the Linux instruction counts (2026-11-25)

Tomato's own instructions executed (callgrind, release mode, counting inputs from `benchmarks/sizes.txt`, one run: Tomato's count does not vary), in
millions, on the Linux x86-64 box with the fixed toolchain. The benchmark programs and inputs are the same everywhere; only the compiler, runtime and
`native/tomato` change. Instruction counts are not time: they say nothing about cache or branch behaviour.

Three ways of linking a program exist on the current tree (`native/tomato`):

- **LTO**: the working toolchain (the linker's LLVM plugin or `lld`).
- **merge**: a clang whose linker has no LLVM plugin, the case this task makes visible: clang merges the runtime's bitcode into the program (`-mlink-bitcode-file`) and warns.
- **plain**: even the merge fails; the runtime is linked as an object, with no cross-module optimisation (what v0.51 did on the biggie toolchain, silently).

## At the v0.51 tree (`14b191e3`)

The v0.51 tree had no merge path, so a clang without the plugin gave the plain link: the published v0.51 Linux counts (`instructions-v0.51-no-lto.md`).
The same tree, rebuilt with the working toolchain:

| benchmark | v0.51 plain (published) | v0.51 LTO | LTO effect |
| --- | ---: | ---: | ---: |
| fib | 342.05 | 183.45 | 1.86× |
| sieve | 98.31 | 49.04 | 2.00× |
| matmul | 387.34 | 138.64 | 2.79× |
| mandelbrot | 102.55 | 79.67 | 1.29× |
| collatz | 70.77 | 70.33 | 1.01× |
| strings | 127.67 | 106.59 | 1.20× |
| sort | 71.10 | 50.83 | 1.40× |
| wordcount | 185.51 | 155.53 | 1.19× |
| bigint | 100.44 | 100.27 | 1.00× |
| objects | 147.90 | 106.01 | 1.40× |

This confirms `docs/architecture-review.md` section 3.3 (fib 183.46 M with LTO against 342.05 M without, reproduced as 183.45 M): at v0.51 the lost
LTO made fib, sieve and matmul 1.9 to 2.8 times too slow.

## At `d83f43b0` (v0.51 plus 25 later runtime and compiler changes; the tree of `instructions-d83f43b0.md`)

| benchmark | v0.51 LTO | plain | merge | LTO | plain ÷ LTO | merge ÷ LTO |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 183.45 | 112.96 | 123.54 | 123.53 | 0.91× | 1.00× |
| sieve | 49.04 | 33.63 | 30.63 | 30.31 | 1.11× | 1.01× |
| matmul | 138.64 | 84.49 | 83.90 | 83.85 | 1.01× | 1.00× |
| mandelbrot | 79.67 | 33.69 | 33.56 | 35.52 | 0.95× | 0.94× |
| collatz | 70.33 | 82.43 | 87.15 | 82.12 | 1.00× | 1.06× |
| strings | 106.59 | 84.76 | 78.65 | 69.51 | 1.22× | 1.13× |
| sort | 50.83 | 22.98 | 22.67 | 22.67 | 1.01× | 1.00× |
| wordcount | 155.53 | 175.49 | 157.79 | 149.84 | 1.17× | 1.05× |
| bigint | 100.27 | 72.27 | 72.25 | 71.86 | 1.01× | 1.01× |
| objects | 106.01 | 80.64 | 61.84 | 60.34 | 1.34× | 1.02× |
| nbody | 279.26 | 152.89 | 114.18 | 115.30 | 1.33× | 0.99× |
| spectral_norm | 178.57 | 76.93 | 76.86 | 75.87 | 1.01× | 1.01× |
| fannkuch | 846.44 | 307.92 | 268.37 | 278.05 | 1.11× | 0.97× |
| nqueens | 24.10 | 18.25 | 15.15 | 15.06 | 1.21× | 1.01× |
| binary_trees | 112.61 | 145.31 | 110.94 | 112.05 | 1.30× | 0.99× |
| levenshtein | 206.73 | 85.46 | 74.16 | 72.91 | 1.17× | 1.02× |
| knapsack | 184.89 | 66.81 | 66.82 | 66.81 | 1.00× | 1.00× |
| life | 167.63 | 87.78 | 76.71 | 78.72 | 1.12× | 0.97× |
| dijkstra | 54.28 | 30.02 | 22.30 | 24.55 | 1.22× | 0.91× |
| quicksort | 134.92 | 51.01 | 48.98 | 48.97 | 1.04× | 1.00× |
| kmers | 147.83 | 182.64 | 157.25 | 139.90 | 1.31× | 1.12× |
| revcomp | 19.04 | 20.31 | 19.13 | 16.37 | 1.24× | 1.17× |
| tokenize | 44.96 | 58.80 | 46.77 | 37.38 | 1.57× | 1.25× |
| crc32 | 72.74 | 31.46 | 31.45 | 31.45 | 1.00× | 1.00× |
| hof | 55.68 | 54.69 | 39.77 | 38.61 | 1.42× | 1.03× |

Reading it. Later work (the fast paths now emitted into the IR, range analysis and others) has taken most of the LTO gain into the compiler: for the
arithmetic programs the three links differ by a few percent (matmul, sort, crc32, knapsack, bigint) and the cost of a lost LTO is now below 1.1 times.
Programs that call across the runtime still gain (objects 1.34, tokenize 1.57, kmers 1.31, wordcount 1.17 for plain against LTO), and **the merge fallback
recovers nearly all of that** (objects 1.02, nbody 0.99, binary_trees 0.99, hof 1.03 against LTO; tokenize 1.25 and kmers 1.12 are what it does not
recover). Two programs go the other way: fib needs 9% more instructions with the merge or LTO than with a plain link (123.5 M against 113.0 M), the same
for both, so it is the inlining of the runtime into the program, not the LTO linker, and it is a code-generation effect in one function, not a bad inlining
decision (the next section); time does not follow it consistently. collatz needs 17% (plain, LTO) to 24% (merge) more instructions than at v0.51: a change since v0.51, not a link effect.

**Why collatz executes more instructions (found 2026-11-25).** It is a deliberate trade, made by commit `12f64cb4` ("Speed up generated code and runtime"):
instructions went up and the time went down. Building the compiler at `12f64cb4~1` and at `12f64cb4` gives exactly 70,331,052 and 82,122,779
instructions (50000 input, LTO), so that commit is the whole 17%. The loop body `if x % 2 == 0: x //= 2 else: x = 3 * x + 1` has two short arms that assign the
same variable, which `fast_choice` in `compiler/src/compiler.tom` now emits as a `select`: both arms are worked out every step and one is chosen, with one
range check on `3 * x` that covers the odd arm. At v0.51 the loop branched: an even step ran 13 instructions and an odd step 15 (the checked multiply and add), 13.96 on average
over the 5,024,987 steps of this input. Now every step runs the same 16 instructions (`lea`, `cmp`, `jb` for the range
check, `lea`, `mov`, `sar`, `or`, `test`, `mov`, `cmovne`, the counter's `add` and `jo`, `mov`, `cmp`, `jne`) with no data-dependent branch, 2.0 more per step.
Whether a number is even is as unpredictable as a coin toss, so v0.51 paid a branch misprediction on about half the steps, which valgrind does not count.
The Linux timings show the trade paying off: collatz at 1,000,000 takes 0.166 s now (`results.md`) against 0.296 s at v0.51 with LTO
(`v0.51-lto/results.md`); a pinned back-to-back rerun of the two binaries gave 0.292 s and 0.170 s (median of 25, the host loaded). Nothing to fix.
The extra 7 percentage points of the merge link (87.15 M) are one instruction per step, and **not an inlining effect** (traced 2026-11-25, same clang 21.1.8, collatz at 50000
reproduced exactly: merge 87,153,618, LTO 82,122,815). The multiply by 3 comes out as `lea rax,[2*r13]` plus `add rax,r13` in the merge link and as one `lea rax,[rbx+2*rbx]` with LTO.
The chain:

- `tomato.main` is *not* inlined into `main` in the merge link, and the inliner says why: `cost=3225, threshold=225`. The program's functions keep external linkage when the runtime is
  merged with `-mlink-bitcode-file` (clang only links the bitcode in; nothing is internalized), so the inliner gets neither the last-call-to-a-local-function bonus nor a chance to delete the callee. With LTO the linker
  internalizes everything but `main`, so `tomato.main` has one caller and is inlined (cost -11775 once it is internal).
- That is **not** what costs the instruction: with `tomato.main` made `internal` in the IR, the merge link does inline it into `main` and still executes 87,153,662 instructions.
- The instruction comes from register allocation plus LLVM's *slow 3-operand LEA* tuning (on in the generic x86-64 tuning). The loop-carried `x` lives in `r13` in the merge build (`rbp` when `tomato.main` is
  inlined) and in `rbx` with LTO. `lea rax,[r13+2*r13]` (like `rbp`) has no short encoding, since a base of `rbp` or `r13` needs an explicit zero displacement, so it is a three-component LEA, and the `X86FixupLEAs`
  pass turns it into `lea` + `add`. With `rbx` it is a two-component LEA and stays one instruction. Which of the callee-saved registers `x` gets depends on the rest of the (differently inlined) function, so it
  is allocation luck, not a property of the merge link. Building the merge link with `-Xclang -target-feature -Xclang -slow-3ops-lea` gives 82,128,667, within 6 thousand instructions of the LTO build.
- Not a regression in time to chase: on the Intel cores that have the slow-LEA tuning a three-component `lea` has 3 cycles of latency, so `lea`+`add` (2 cycles) is no slower; the instruction count rises, the
  dependent-chain length does not. No change to the compiler, runtime or link was made.

(The same external linkage limits the merge link generally, since every program function has a threshold of 225 instead of the single-caller bonus: that may be part of what the merge does not recover on tokenize 1.25 and kmers 1.12. Not measured here.)

## Why fib executes more instructions when the runtime is inlined (checked 2026-11-25 on `da596c95`; same counts as at `d83f43b0`)

Every call of `tomato.fib.small` (the all-small-integer copy of `fib`; about 7.05 M calls, half of them leaves) is the whole program. Callgrind: plain
112.96 M (`tomato.fib.small` 84.6 M plus the out-of-line `tomato_int_add_c` 28.2 M), LTO 123.53 M, merge 123.54 M (all in `tomato.fib.small`).

The inliner did what it should: it put the 8-instruction small-number path of `tomato_int_add_c` into `fib.small` (the slow path stays a call to
`tomato_int_add_slow`). The extra instructions come from what that does to the register allocator's frame:

- **Plain.** The last thing `fib.small` does is `tail call tomato_int_add_c`, so it ends in `jmp tomato_int_add_c`, and the leaf (`n < 2`) has a
  return of its own. LLVM shrink-wraps the frame: a leaf call executes `cmp; jg; mov; ret`, 4 instructions, with no pushes.
- **Inlined.** The add's fast path, its slow-path tail call and the leaf all end in one shared `ret` block (`common.ret`), and that block is where the
  frame is torn down. The frame can no longer be shrink-wrapped away from the leaf: it executes `push r14; push rbx; push rax` before the compare and
  `add rsp; pop; pop; ret` after it, 10 instructions (+6 for each of the 3.52 M leaves). An internal call is 3 instructions cheaper (the add costs
  7 inline against 8 plus the `jmp`, and `add_c`'s `mov edx, 3` and the call overhead go): 28 plain, 25 inlined.
  3.52 M × (+6 − 3) = +10.6 M, which is the 123.53 M against 112.96 M difference.

To see it: `opt -O2` on the program's and runtime's bitcode gives the `common.ret` block with three predecessors (leaf, fast add, slow add) for the
inlined build, and a block with two (leaf, the tail call) for the plain build; `llvm-objdump -d` on the binaries shows the two prologues.

**Timing.** Not a consistent loss. `fib 38`, `taskset` to one CPU, interleaved plain / LTO / merge runs, minimum of 15 to 40 runs of CPU seconds, on the
Threadripper 3990X while the box was at a load of about 70 (so these are indicative; each CPU's own plain-against-LTO ordering was stable):

| CPU | plain (s) | LTO (s) | merge (s) | LTO ÷ plain |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 0.225 | 0.210 | | 0.93× |
| 30 | 0.227 | 0.209 | | 0.92× |
| 45 | 0.225 | 0.209 | | 0.93× |
| 60 | 0.226 | 0.208 | 0.203 | 0.92× |
| 75 | 0.278 | 0.283 | | 1.02× |
| 90 | 0.271 | 0.278 | | 1.03× |
| 100 | 0.265 | 0.274 | 0.276 | 1.03× |
| 110 | 0.268 | 0.275 | | 1.02× |
| 120 | 0.293 | 0.332 | | 1.13× |

On CPUs 10 to 60 the inlined build is about 7% faster despite executing 9% more instructions (the pushes and pops are cheap stores and loads that
overlap, while the plain build pays a `jmp` into a separate function on every internal call); on CPUs 75 to 120 (slower, probably busier: the same
program takes 20% longer there) it is 2 to 3% slower, 13% on CPU 120. The published fib time (0.225 s, LTO) is on the fast side of this. So the 9% in
the instruction count does not say that fib is slower with the runtime inlined, and nothing here suggests a change to the inliner, the runtime or
the compiler: LLVM's shrink-wrapping is the only thing that differs, and it would need a different IR shape (for instance a leaf test in a
function of its own) to change.

