# Arbitrary-size floats: design

Status: **approved by Davis with all recommended answers** (the eight questions at the end). Built: stage 0 (the rounding
fixes), stage 1 (`float[length=64]` as a name, removed again in D77c), stage 2 (the C runtime, `docs/bigfloat-runtime.md`), stage 3 (the compiler: D77b
in `docs/decisions.md`), stage 4 (the library and the formats: D77d) and stage 5 (the fast loop copy: D77e, and "Stage 5 as built" at the end). One answer changed from the text below:
floats stay valid dict keys, set members and `hash()` arguments (D78a), which this design had assumed away (Davis, in the stage 3 task). The decision
entries are D77a, D77b, D77c, D77d (stage 4: JSON and TOML reading cap an exponent at 4,300 digits, Davis) and D77e (stage 5). **D77c: Davis removed `float[length=64]`, so wherever this document says `float[length=64]` there is none: one float type, and a program cannot ask for the plain double.**

## The requirement

Davis: converting a huge `int` to `float` must not be able to overflow, and **float exponents are arbitrary size** (a
big-int exponent plus a mantissa). That is fixed. This document settles how, and what it costs.

It replaces part of D05aj ("unlike growing `int`, `float` has fixed precision and range": the precision can stay fixed,
the range cannot) and of D05z and D05af (`int / int` gives a binary64 `float` and reports an error when the result is
too large for one). Those need a new decision entry when this is accepted.

## Recommendation in short

1. **`float` itself changes** (no new `bigfloat` type). A float is `sign x 1.mmm (53 bits) x 2^E` where `E` is an `int`
   of any size. Precision stays 53 bits: the same digits as today, and no limit on range.
2. **Stored as an ordinary double whenever it fits in one**, and as a pointer to a small heap object only when it does
   not. Tomato floats are never infinite or NaN by design, so NaN bit patterns are free to mark the pointer. The finite
   check the compiler already emits becomes the test for leaving the fast path, instead of the test for raising an
   error.
3. **`float[length=64]` is today's plain double**, for hot loops, LLVM calls and file formats. It is to `float` what
   `int[length=64]` is to `int`: fixed size, and it can overflow with an error.
4. In C prototypes of the mandelbrot loop this costs **nothing measurable for overflow alone and about 11% when tiny
   numbers get unlimited exponents too**, if loops get a fast copy. Without the fast copy, 1.4 to 1.6 times. The
   alternatives that always carry an exponent cost 3 to 4 times (pair) or 13 to 19 times (heap objects).

The expensive part is not arithmetic. It is **ownership**: a float that may be a pointer has to be copied and freed like
a big `int`, where today a float is plain data.

> **Stage 0 is done** (`tests/programs/int_to_float.tom`): `tomato_int_to_f64` rounds once; `float(10**400)`, `sqrt(10**400)` and every other implicit conversion of an `int` too big for a `float` raise OverflowError E436 "an int is too large to be a float"; `int / int` divides the exact values (`tomato_int_div_f64`), so `10**400 / 10**399` is 10.0. The table below describes the state before it, except that `2**53 + 1 == float(2**53)` is still `True` (exact comparison waits for question 6).

## What happens today

Checked by building the current compiler from `compiler/bootstrap/tomatoc.ll` (commit bf8eb2ce) and running programs:

| program | result today | comment |
| --- | --- | --- |
| `float(10**400)` | **`inf`, no error** | the conversion does not check. P58 says a float is never infinite |
| `1.0 / float(10**400)` | `0.0`, no error | a wrong answer, silently |
| `float(10**400) == 10**500` | `True` | both sides became `inf` |
| `sqrt(10**400)` | `inf`, no error | `std/math.tom` converts, then does not check `sqrt` |
| `10**400 * 1.0` | OverflowError E13, `the float result is infinite or not a number` | caught one operation later |
| `10**400 / 10**399` | OverflowError E13 | **D05ad says 10.0**: round the exact quotient once |
| `10**400 / 10**400` | OverflowError E13 | D05ad's own example, 1.0 |
| `1e308 * 10.0`, `2.0 ** 2000.0` | OverflowError E13 | by design (P58) |
| `exp(1000)` | OverflowError E44 | by design |
| `1e400`, `1e-400` in source | compile error E312 | |
| `float('1e400')` | ValueError E18, `the text is not a number` | |
| JSON `[1e400]` | `JSONDecodeError: Number out of range` | |
| `1e-300 * 1e-300`, `float('1e-400')` | `0.0`, no error | silent underflow |
| `2**53 + 1 == float(2**53)` | `True` | comparison rounds the int first |
| `float(7014465087773491448540667509)` | `7.014465087773491e+27` | the nearest float is `...492e+27`. `tomato_int_to_f64` rounds once per 32-bit limb; 2,435 of 1,000,000 random three-limb values were wrong |

So the smell is worse than an exception: **converting a huge `int` silently gives infinity**, and the error appears at
some later operation, or never. An `int` can only be *passed* as a float by an explicit `float(x)` (a parameter typed
`float` rejects an `int`), but mixed arithmetic (`n * 1.0`, `n < 1.5`) and `int / int` convert implicitly.

Where it lives now:

- **Compiler** (`compiler/src/compiler.tom`): `float` is LLVM `double`. `float_op` does arithmetic and comparison,
  `check_finite` (a `fsub r, r` and a compare) raises E13, `float_chain`/`float_pure` let one check at the end of a `+ -
  *` chain cover the whole chain (infinity and NaN never become finite again under `+ - *`), `to_double` converts an int
  (a shift and `sitofp` when it is known small), `num_divide` is `fdiv` of two converted ints.
- **Runtime** (`runtime/tomato_rt.c`): an `int` is one 64-bit word, odd for a small number (62 bits and sign), otherwise
  the address of a `Big`. Each big number has exactly one owner; copies are made with `tomato_int_dup` and freed with
  `tomato_int_free`. A float has no owner, no copy and no free anywhere.
- **Lists**: `list[float]` is raw 8-byte doubles (`elem_rc` 0); `list[int]` is 8-byte words with flag 2 (copy and free).
- **Browser**: user programs run in an interpreter of the LLVM IR (`site/wasm/llvm.js`), where a `double` is a
  JavaScript number and an `i64` is a BigInt; the runtime is WebAssembly.

## The value

A float is zero (`0.0` or `-0.0`) or `s x m x 2^E`, with `s` a sign, `m` a 53-bit significand (`1 <= m < 2`), and `E`
any `int`. There is no infinity and no NaN. Operations round the exact result to 53 bits, nearest, ties to even (D05ae),
and **no operation can overflow or underflow**. The only limit is memory, as for `int` (D05c).

Two consequences to be clear about:

- **It does not make conversion exact.** `float(10**400 + 1) == float(10**400)`, exactly as `float(2**53 + 1) ==
  float(2**53)` today. The range is unlimited, the precision is not. Exact fractions remain `rational`'s job.
- **A calculation that stays inside the normal double range gives the same double as today**, with the same printed
  text. What changes: anything that used to be an error, `inf`, or (question 2) subnormal or rounded to zero, at the end
  or on the way; and the rounding fixes of stage 0 (big `int` to `float`, `int / int`, `int` against `float`).

### Why 53 bits and not an arbitrary mantissa

An arbitrary mantissa needs a rule for when to stop. `+` and `*` are exact if the mantissa may grow, but then every
multiplication doubles the length: after 40 passes of the mandelbrot loop the exact value has over 10^13 bits. `1/3`,
`sqrt` and `exp` have no exact mantissa at all. So "arbitrary" really means "a precision someone chooses" (as in MPFR or
Python's `decimal`), which is either a global setting, which makes the same expression mean different things in
different places, or part of the type. It also ends the hardware fast path, because a double holds 53 bits and no more.
If more digits are wanted later, they fit the same notation as a fixed type (`float[precision=200]`) beside this one;
nothing here blocks that.

## Representation: three options

All three have an arbitrary-size exponent and a 53-bit mantissa.

### Option A (recommended): `float` changes, a double until it does not fit

One 8-byte word:

- **plain**: the bits of a double, when the value is exactly representable as a finite double (subnormals included);
- **boxed**: a quiet NaN pattern whose low bits are the address of `{ double m; int64_t e; }`, where `m` is in [1, 2)
  with the sign and `e` is an ordinary Tomato `int` word (small, or a pointer to a `Big`). A plain double never gets
  boxed, so each value has one form, and a boxed float is never equal to a plain one.

The form is *canonical*: the slow path turns a result back into a plain double whenever it fits (`1e400 / 1e399` is a
plain `10.0`).

**The fast path is the code the compiler emits now.** A boxed operand is a NaN, so `+ - * /` on it gives NaN, and the
existing check catches it along with overflow. The difference is the failing branch: instead of raising E13 it calls a
cold runtime function that recomputes the chain from its operands and joins. The operands of a postponed chain are pure
reads (`float_pure`), so recomputing them is safe.

Details that need care:

- **Comparisons.** `fcmp` with a boxed operand is unordered, so each comparison needs one more branch (`fcmp uno`, then
  the slow compare), unless an operand check or a fact already shows both are plain.
- **Division.** `x / inf` would be 0 and slip past, but infinity is never stored: a boxed divisor is NaN, so the result
  is NaN and is caught. The zero-divisor test is unchanged.
- **Operations that do not turn a NaN into a NaN** must test their operands first: C's `pow(NaN, 0)` and `pow(1, NaN)`
  are 1, and unary minus (`fneg`) flips the sign bit of the word instead of the number, so it would corrupt a box.
- **Tiny results are not caught by the finite check.** `1e-300 * 1e-300` is `0.0` in hardware, finite. See "Tiny
  numbers".
- **At rest the LLVM type is `i64`, in computation it is `double`** (a `bitcast`). This is deliberate: LLVM does not
  promise which NaN payload arithmetic produces, and a JavaScript engine may rewrite a NaN's payload whenever a value
  passes through a number (in V8 here quiet payloads survived and a signaling one was changed; JavaScriptCore, which
  `native/tomato-jsc.js` uses, was not tested). As an `i64` the word is never touched as a number. `mem2reg` and
  InstCombine turn the bitcasts into registers; whether they do so in every loop has to be measured on the M1 too.
- **Addresses** fit: 47 or 48 bits natively, 32 bits in WebAssembly, 51 payload bits available.

**Ownership.** A boxed float has one owner and is copied, not shared, like a big `int`. So a float variable needs a "is
the old value boxed? free it" on assignment, a copy when it is stored elsewhere, frees on every unwind path, flag 3 for
`list[float]` (and tuples, dict values, class fields, unions, async frames, yields). The compiler has all of this for
`int` (`Ex.fresh`, `elem_rc`, the unwind lists); floats join it. This is the largest part of the work and the most
likely place for leaks and double frees.

**Keeping loops fast** needs the same trick as `small_loop` has for ints: compile an eligible float loop twice. The fast
copy holds plain doubles, has no ownership tests, and leaves to the general copy at the start of the same statement if a
result does not fit. `small_loop` already does this for int loops, so the mechanism exists, but it handles only `+ - *`,
`//` and `%` by powers of two, and `if` on comparisons; floats need `/`, mixed int and float, and indexed reads to be
useful.

### Option B: `float` changes, always a (mantissa, exponent) pair

Every float is 16 bytes: a double mantissa and an `int` exponent word. No NaN tricks, the same code for every value, and
no tiny-number problem, because the exponent is always there. But every `+` compares exponents and scales, every `*`
adds them and renormalises, and nothing vectorises. `list[float]` doubles in size, and floats stop fitting in a list,
dict or union slot (all 8 bytes today). Measured at **3 to 4 times** today's loops, with a 64-bit exponent that only
traps on overflow; with a real `int` exponent it would be slower. It also needs the ownership rules (the exponent may be
a `Big`).

### Option C: `float` stays IEEE, add a `bigfloat` type

The cheapest: no cost for existing code, and it could start as a library class like `rational`. But **plain `float` does
not get an arbitrary exponent, so this does not meet the requirement as stated**, and the smell only moves. `int / int`
and `n * 1.0` have to produce one of the two types: if `float`, they still overflow; if `bigfloat`, ordinary arithmetic
becomes the slow type everywhere. Users also have to know in advance which one they need. It is listed as the fallback
if the work in A turns out too large. The `bigfloat` core (parsing, printing, arithmetic) is the same code as A's slow
path, so A's stage 2 is not wasted either way.

### Comparison

| | A: double until it does not fit | B: pair | C: separate `bigfloat` |
| --- | --- | --- | --- |
| `float` exponent arbitrary | yes | yes | no, only `bigfloat` |
| `float(n)` can overflow | never | never | yes |
| results that fit a double today | identical | identical | identical |
| size of a float in a list | 8 bytes | 16 bytes | 8 (`float`), boxed (`bigfloat`) |
| mandelbrot prototype | 1.0 to 1.4 (below) | 4.0 | 1.0 |
| ownership for floats | yes | yes | no |
| compiler work | large | large (every slot changes size) | small |
| what a user must learn | `float[length=64]` if it must be fast | nothing | two float types |

## Cost, measured

C prototypes of the inner loop of `benchmarks/mandelbrot` (n = 1000) and of a dot product over `list[float]` (4096
items, 10,000 times), clang 21 `-O2`, Linux x86-64, pinned to one core, median of 15 runs. The machine is shared (load
average about 80 on 128 cores), so treat differences under about 10% as noise (a second session gave 1.13 for the row
that says 1.11). Instructions are callgrind's count for mandelbrot at n = 250. The "today" prototype is 0.20 s against
0.21 s for the real compiled benchmark, so the model is close. They are throwaway programs, not part of the repository,
and they model the fast paths only: a result that must be boxed in a fast copy ends the program instead of switching
copies. **Nothing was measured on the M1 or in the browser.**

| mandelbrot | seconds | relative to today | instructions (M) |
| --- | ---: | ---: | ---: |
| no checks at all (the floor) | 0.140 | 0.69 | 33.6 |
| **today**: 3 finite checks per pass | 0.203 | 1.00 | 60.4 |
| A, large exponents only, fast loop copy | 0.203 | 1.00 | 64.5 |
| A, large and tiny, fast loop copy | 0.225 | 1.11 | 93.5 |
| A, large exponents only, no fast copy | 0.281 | 1.39 | 82.1 |
| B, pair | 0.814 | 4.0 | 325.5 |
| every float a heap object | 3.93 | 19 | 2291 |

| dot product | seconds | relative to today |
| --- | ---: | ---: |
| no checks | 0.075 | 0.59 |
| **today** | 0.128 | 1.00 |
| A, large exponents only, no fast copy | 0.202 | 1.57 |
| A, large and tiny, no fast copy (a simpler tiny test than the rule below) | 0.183 | 1.43 |
| B, pair | 0.381 | 3.0 |
| every float a heap object | 1.79 | 13 |

(The heap-object rows come from a separate session; their ratios use that session's own "today" row.)

An operation that really is on a boxed float costs roughly one of the heap-object operations: 13 to 22 ns in these
prototypes, against about 1 ns or less. A program that stays above 1e308 runs like that throughout. That is the price of
an answer instead of an error.

### Range analysis and the mandelbrot finite checks

The task "Range analysis follow-ups" (in progress while this was written) is removing finite checks by float interval
reasoning. That work stays useful under A, with three changes:

- "cannot be infinite" becomes "cannot need boxing on the large side": the same proof, the same removed check.
- **An unknown float may now be boxed.** A variable needs a known finite interval, or a check, before its comparison can
  use a bare `fcmp`. A fact such as `zr*zr + zi*zi <= 4.0` gives that interval.
- A fast loop copy needs "every float local is plain" at entry, which is a test of each variable, as `small_loop` does
  for small ints; loops whose facts already prove it skip the test.

With tiny numbers covered too, intervals cannot remove the low-side check, because nothing bounds `zr` away from zero.
In the prototype, removing the large-side half of every check and keeping the low side saved no time (0.235 s against
0.225 s, noise). So **full interval reasoning could bring mandelbrot from 0.20 to 0.14 s if only large exponents are
covered, and leaves it near 0.22 s if tiny ones are covered as well**. That is the real price of question 2, and
`float[length=64]` is the way out of it for a program that needs the speed.

## Tiny numbers

An arbitrary exponent read literally goes both ways: `1e-300 * 1e-300` should be `1e-600`, as `1e300 * 1e300` is
`1e+600`. D05ah says small results become subnormals and then zero; that was decided for `int / int` when `float` was
binary64.

Detecting it is the hard part, because the hardware result is finite (0, or a subnormal with few digits). The rules:

- `+` and `-` of doubles never lose digits to underflow, so they need nothing for tiny numbers.
- A product (or quotient) needs a check that its result is above the smallest normal double, or that an operand is zero.
  A product by a power of two that is at least 1 (as in `2.0 * zr`) is always exact and needs none.
- **Two-term rule.** For `p + c` or `p - c`, where `p` is a product and `c` a variable, a constant or another product,
  one check `|result| >= 2^-960` covers it: if `p` lost digits then `|p| <= 2^-1022`, so `|c|` is about as large as the
  result, and `p` is under a quarter of `c`'s last place, so both the true and the hardware product leave `c` unchanged.
  (Checked on random cases near the boundary against exact arithmetic: 238,720 results above the threshold, none wrong.)
- **It does not extend to longer chains.** For `(a*b + c) + d` the final check is not enough. With `a = 1 + 2^-35`, `b =
  2^-1041`, `c = 2^-988`, `d = 2^-935` the result is far above `2^-960` and still one unit off in the last place,
  because the tiny error decides a tie twice. So a chain needs the check after the first `+` that has a product in it,
  and only then a finite check at the end. Mandelbrot needs four checks instead of three.
- Nothing may be postponed through a `*`: `(1e-200 * 1e-200) * 1e300` would lose everything.

A wrong rule here is a silent wrong answer, so the slow path must be fuzzed against exact `rational` arithmetic.

The alternative is one-sided: large exponents only. Then `1 / float(10**400)` is `0.0`, `1e-300 * 1e-300` is `0.0`, and
the rules above disappear. It is simpler, faster, and asymmetric: `x * y` never fails but quietly turns into zero.

## Semantics

- **`+ - *`**: the exact result rounded to 53 bits. Total: they never raise.
- **`/`**: as now a zero divisor raises ZeroDivisionError (D05ab); otherwise the rounded exact quotient, never out of
  range. `int / int` rounds the exact quotient once (D05ad), whatever the size of the operands.
- **`//` and `%`**: floor division and a remainder with the divisor's sign, as now, on any size. `%` of hugely different
  exponents uses modular exponentiation of two, not a shift by the difference. `//` gives a rounded float.
- **`**`**: a whole-number power uses repeated squaring with guard bits; otherwise `exp(y * log x)` with extra
  precision. `2.0 ** 10.0**18` is fine (the exponent is a small `int`); `10.0 ** 10.0**100` is fine (its exponent has
  about 335 bits). A tower that needs an exponent too big for memory raises the existing "out of memory" error. A
  negative base with a fractional power, or zero to a negative power, is now a range error (E13); it becomes ValueError
  and ZeroDivisionError.
- **Infinity and NaN do not exist.** No operation makes one. E13 disappears for `float`, and stays for
  `float[length=64]`.
- **Comparison** is by value. Comparing an `int` with a `float` should be exact (question 6): `2**53 + 1 ==
  float(2**53)` is `True` now and wrong.
- **Zero** keeps its sign rules (D05ai). An underflow to zero can no longer happen, so the only zeros are exact.
- **Sorting, `min`, `max`, `sum`**: `sorted(list[float])` maps the bits to a sortable integer; it needs a "does any item
  have a box" scan first, with a comparison sort otherwise, as the int sort already does.
- **Equality and hashing**: floats stay dict keys and set items (D78a; Davis, in the stage 3 task). Equal floats hash alike, `0.0` and `-0.0` are one key, and a whole float hashes as the equal `int`; a box is hashed from its significand and exponent.

## Conversions

| from | to | result |
| --- | --- | --- |
| `int`, any fixed-width int | `float` | always works. Nearest float, ties to even (fixes the rounding bug above) |
| `float` | `int` | the whole part towards zero, exact, any size. `int(1e1000000)` is a 3.3-million-bit int; a size that cannot be allocated is "out of memory". E14 disappears |
| text, literal | `float` | any exponent |
| `float[length=64]` | `float` | implicit and lossless (D05o's rule) |
| `float` | `float[length=64]` | explicit `float[length=64](x)`. OverflowError if it is too large. Too small becomes a subnormal or zero, as in IEEE (D05ah) |
| `int` | `float[length=64]` | explicit, with the same OverflowError |
| `float` | `rational` | not needed for this; `rational.to_float()` gets a float of any size, through D05ad's `/` |

There is deliberately no way to get infinity out of a conversion: D05af chose an error over infinity, and the same
argument holds. A program that wants a float or nothing can use `try`, or a helper returning `float[length=64] | None`
(question 5).

## Literals and printing

- **Literals**: `1e400`, `1e-400` and `1e1000000` become legal (today's E310 and E312 disappear); the number of digits
  becomes unlimited with correct rounding (E311 disappears). The lexer holds the digits and the exponent as big ints and
  passes text for a value that is not a plain double to the runtime, as it does for big int literals. A literal that has
  to be `float[length=64]` and does not fit is a compile error, as `300` is for `uint[length=8]` (D05r).
- **Printing** does not change for a plain double: shortest text that reads back as the same float, fixed notation from
  1e-4 to below 1e16, otherwise `1e+400`. A boxed float prints the same way with the exponent as a full decimal int:
  `1.5e+1000000`. The shortest digits need 10^k to `64 + bits(E)` bits of precision, by repeated squaring: microseconds
  for an exponent of 64 bits, about a second for an exponent of 10,000 bits (an estimate, not measured). Above 4096 bits
  of exponent (beyond about 10^(10^1233)) print the exact `0x1.8p+E` form instead, which is immediate (question 7).
- **Reading** `float(text)` takes any exponent, plus that form. The 200-character limit on text in `text_float` goes.

## Standard library and other surfaces

- **`math`**: the libm functions keep their libm path while the argument and result are plain. The rest: `sqrt` and
  `cbrt` split off the exponent, `log`, `log2`, `log10` add `E * log 2`, `exp`, `sinh`, `cosh`, `expm1` split off `E`,
  `hypot` scales, `pow` as above. `exp(x)` for large `x` needs log 2 to about `bits(E)` extra digits. E44 and E52
  disappear. The functions that take an angle are unchanged: above 2^53 turns a float has no fraction, so `sin` is 0.0
  there, as today (a huge angle used to be `inf` or an error). Errors for a bad domain (`sqrt(-1)`, `log(0)`) stay.
- **JSON**: reading a number outside the double range works (`Number out of range` goes); writing one gives `1e+400`,
  which is legal JSON but few other readers hold it. **MessagePack** has only 64-bit floats, so a boxed value is an
  encode error. **TOML** `inf` and `nan` stay in `special`.
- **`time`, `sleep`, `requests` timeouts**, `clock()`: use `float[length=64]` inside; a boxed argument is a ValueError. **Built differently (D77b, stage 3):** every `!` declaration that takes a `float` converts it to the nearest double at the call and stops with an `OverflowError` ("a float is too large for a float[length=64]", or "too small" for a tiny one that would come out as zero), not a `ValueError`; Davis confirmed the `OverflowError` for both messages in the stage 3 task; stage 4 replaces most of these paths.
- **LLVM `!f(x: float)`** (D27b maps `float` to `double`): the declaration should say `float[length=64]`; a plain
  `float` would need a conversion that can raise. Breaking for existing `!` declarations (`std/math.tom`,
  `std/json.tom`, `std/time.tom`, `examples/mathlib.tom`, and user code).
- **Browser**: `llvm.js` needs a real `bitcast` between `i64` and `double` (it passes the value through today); the rest
  is in the WebAssembly runtime. The interpreter is slow already, and a bitcast per operation will make it somewhat
  slower.
- **Entry inputs**: a `float` input accepts any size.
- **Memory tools**: the leak check and AddressSanitizer runs get float cases; the alloc counter counts boxes.

## Migration

What an existing program can notice:

- Programs that got OverflowError E13 (or E14, E44, E52, E312) now get a result. A `catch` for them never runs. The
  tests that fix those messages change: `float_chains`, `error_classes`, `toml_invalid`, `runtime/float_overflow`,
  `runtime/exp_overflow` and their outputs.
- Programs that got `inf` (by accident) get a number.
- Underflowed zeros and subnormals become exact tiny numbers (if question 2 is yes).
- Mixed `int`/`float` comparisons near 2^53 and above can change (if question 6 is yes).
- Code that used `float` as "a machine double" for `!` calls needs `float[length=64]`.
- Speed: hot loops outside the fast copy get slower by 1.4 to 1.6 times (estimated from the prototypes). Annotating
  `float[length=64]` restores today's code exactly.

Nothing else needs editing: source that does not depend on overflow compiles and prints the same. No automatic rewriting
tool is needed.

## Alternatives considered

Looked for something clearly better and **did not find one that meets the requirement**. The short comparison:

| design | int to float overflow | why not (or why partly) |
| --- | --- | --- |
| Raise at the conversion (`float(10**400)` raises OverflowError) | still possible, but reported at the right line | no new representation, about 10 lines. It does not remove the overflow, so it is not the answer, but it fixes the worst of today's behavior and is worth doing first (stage 0) |
| Checked form, `float.try(n) -> float \| None` | pushed to the caller | adds a step to code that nearly never overflows |
| Saturate, or infinity | never raises | wrong numbers instead of an error, or NaN later; contradicts D05af and P58 |
| Explicit-only conversion (no `int * float`) | still at `float(n)` | breaks `2 * x`, the common case, and does not remove it |
| Exact `rational` as the result of `/` | never | exact, but numbers grow without bound in a loop, and Davis chose binary64 over it (D05z). It exists as a library |
| Decimal floats | depends on the exponent | the radix does not remove the overflow. With a big-int exponent it is this same design without the hardware fast path |
| A whole part (`int`) plus a fraction part (`double`) | never, and conversion is exact | closest to Davis's first wording. It has no exponent, so `1e1000000` is a 415 KB number, small numbers still underflow, and multiplying needs big-int times fraction. The exponent design dominates it except for exactness |
| A wider hardware-style type (quad, double-double) | not below 2^16384 or 2^1024 | only moves the limit |

If the work is too big, the sensible fallback is C plus the stage 0 fix.

## Plan

Nothing starts before Davis answers the questions. Each stage is one reviewable change with the full suite green; the
compiler stages regenerate `compiler/bootstrap/tomatoc.ll` and the site's wasm files. Sizes are estimates of
hand-written lines, based on comparable past changes (the range analysis was about 720 lines of compiler; unlimited
`int` in v0.21 was about 600 lines across all files).

| stage | content | size (lines) | risk |
| --- | --- | ---: | --- |
| 0 | **Done.** Independent of everything: round `int` to `float` correctly; make `int / int` follow D05ad; make `float(huge)` raise until stage 3 lands; check `sqrt` of a huge int. Not included: exact `int` against `float` comparison (question 6) | 150 | low |
| 1 | `float[length=64]` as a type, with today's code generation unchanged underneath (**done**: an alias of `float`, so far) | 300 | low |
| 2 | Runtime core in C: box, conversions, `+ - * / // % **`, comparison, parse, print, math slow paths; tested by fuzzing against `rational` | 1,000 + 400 test | medium |
| 3 | Compiler: `float` as a word at rest, slow arms for checks, chain rules, comparisons, literals, ownership in locals, fields, containers, unions, async frames, unwinding | 900 + 400 test | **high** |
| 4 | std and formats (math, json, toml, time, requests), `!` calls, `llvm.js`, error list, docs, decision entry | 400 | medium |
| 5 | Fast loop copy for floats; float facts; measurements on the M1, Linux and the browser | 600 | medium |

Total about 4,000 lines. Stage 3 is the risk: leaks and double frees in paths that have never owned a float. Stages 0 to
2 are useful whatever is decided later. After stage 0, every stage keeps the rule that a calculation inside the normal
double range gives bit-identical results, checked by running the existing tests and a differential fuzz against the
previous compiler.

Open risks, stated plainly: the M1 and browser costs are unknown; LLVM may keep some bitcasts in general registers and
cost more than the prototype; and the fast copy must cover enough loops (with indexing, mixed ints and calls) or the 1.4
to 1.6 times applies to most float code until it does.

## Questions for Davis

1. **Does `float` itself change** (option A), or is it a separate `bigfloat` (option C)? *Recommended: `float` itself,
   stored as a double whenever it fits.*
2. **Do tiny numbers get unlimited exponents too** (`1e-300 * 1e-300` is `1e-600`), or only large ones? The measured
   price is about 11% in mandelbrot and giving up the 30% the finite-check removal could still win there. *Recommended:
   both ways. It is what "arbitrary-size exponent" says, and `float[length=64]` is there for the loops that must be
   fastest.*
3. **Is a fixed 53-bit mantissa right** (so `float(10**400 + 1)` still rounds), with more digits possible later as
   another type? *Recommended: yes.*
4. **Is `float[length=64]` the name for the plain double**, with an overflow error as now, matching `int[length=N]`?
   Should `float[length=32]` exist too? *Recommended: yes; not `32` yet.*
5. **Should there be an optional-returning conversion** to `float[length=64]` (`None` when it does not fit), or is
   OverflowError with `try` enough? *Recommended: the error is enough for now.*
6. **Should `int` and `float` compare exactly** (`2**53 + 1 == float(2**53)` becomes `False`)? *Recommended: yes. It is
   the same smell: the comparison rounds silently.*
7. **How should a float with an enormous exponent print?** Decimal up to an exponent of 4096 bits, then `0x1.8p+E`.
   *Recommended: that, because decimal digits stop being worth the time beyond it.*
8. **Is stage 0 worth doing now**, before any of this? It fixes the silent `inf`, the wrong rounding and `10**400 /
   10**399`. *Recommended: yes, as its own task. It needs no new type, but it makes `float(10**400)` raise until stage
   3.*

## Stage 5 as built

**Where the fast copy is.** Release mode already compiled a loop nest twice (`Gen.nest_loop`): a fast copy that assumes every
int variable is small and, when one is not, jumps to the start of the same statement in the general copy, which does it again.
Stage 5 puts floats into that copy instead of building a second mechanism. Every float variable of the nest is a finite double
all through the fast copy: the entry test at each loop head of the general copy checks it (the exponent bits of a box, an
infinity and a NaN are all set), and a statement the fast copy compiles the ordinary way (a call that is not pure, a print) is
followed by the same test for the variables it assigned. So in the fast copy a float operation has no slow path and no
ownership code: a result that is not final, a box read from a field, a list or a call, or an error, leaves for the general
copy. The int-only `small_loop` (both modes) is unchanged, so **debug mode and the browser, which compiles in debug mode, get
no float fast copy**.

**What the fast copy does with floats:**

- Each float variable of the nest lives in a slot of type `double` of its own (its shadow) inside the fast copy, filled where
  the fast copy is entered and written back wherever it leaves. Without it LLVM carried a loop's floats as `i64` and moved them
  between the integer and the floating-point registers on every pass: mandelbrot's loop had only four tests left and still ran
  at 0.17 to 0.20 s, against 0.10 s with the shadows. (This is the risk the design named: "LLVM may keep some bitcasts in
  general registers".)
- `+ - *` chains use the two-term rule of "Tiny numbers": `p + c` and `p - c`, with `p` a product and `c` a leaf or another
  product, need one test, that the result is at least 2^-960 and finite; any other product is tested on its own (above 2^-1022);
  the chain's result must be finite. In the fast copy any float or int expression can be a leaf of a chain (the general copy
  needs leaves it can read twice), so even a single operation is a chain.
- When the tests fail, the exact tests are made before giving up: each product is above 2^-1022 or has a factor 0 (then it is
  an exact 0), and the result is finite. Mandelbrot starts every point at 0.0, and a zero product would otherwise send the first
  pass of every point to the general copy. Both copies use the two-term rule and this re-check.
- A field or list item that is only a leaf of a chain is read without its own box test: a box is a NaN and an infinity stays one
  under `+ - *`, so either fails the chain's last test. In `b.x = b.x + ...` the old value is then known to be a double, so the
  store needs no box test either.
- Comparisons of two finite doubles are a bare `fcmp`; a float against an int compares exactly as before, through a double when
  the int is at most 2^53 in size, else in the general copy.
- `math.sqrt` is the hardware square root (a negative argument leaves for the general copy, which raises).
- A float literal of at least 1e-281 divided by a whole number below 2^64 needs no test in either copy (the quotient lies between
  1e-281 / 2^64 and the literal): `1.0 / n` in spectral_norm.

**Float facts.** The idle float interval code is used again, with a new meaning: an interval bounds a float's value whatever its
form, a box included (the rules only use that rounding keeps order). The stage 3 compiler had stopped recording intervals for
floats; they are recorded again for every float local. They cannot remove a test in the general copy, where a leaf may be a box,
but in the fast copy, where every float is a double, a result whose interval is bounded (the cap is 2^256) cannot overflow: a
`+` or `-` needs no test at all and a product or a two-term sum only the lower half of its test (a floating-point compare of the
magnitude). Nothing bounds a value away from 0, so the lower half stays, as the design expected. In mandelbrot the three tests
left per pass are those lower halves.

**Measurements** (median wall-clock seconds, release builds made the way `tomato build --mode release` makes them; "before" is
the parent of the stage 3 commit, "stage 3" is the tree this started from):

| | Linux x86-64: before | stage 3 | stage 5 | Apple M3 Pro: before | stage 3 | stage 5 | C (M3 Pro) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| mandelbrot 1000 | 0.10 | 0.28 | **0.10** | 0.108 | 0.293 | **0.126** | 0.095 |
| nbody 1500000 | 0.21 | 0.70 | **0.33** | 0.112 | 0.398 | **0.211** | 0.081 |
| spectral_norm 1000 | 0.11 | 0.23 | **0.16** | 0.103 | 0.205 | **0.128** | 0.070 |

Linux: AMD Threadripper 3990X, clang 21, one core pinned on a machine with a load of about 70, 3 to 5 runs. Instructions executed
(callgrind, at the inputs of `benchmarks/count.sh`): mandelbrot 33.6 M / 272.8 M / 76.0 M, nbody 113.8 M / 412.3 M / 244.8 M,
spectral_norm 76.9 M / 134.2 M / 102.2 M. Mac: Davis's MacBook Pro (Apple M3 Pro, Apple clang 21, on battery power, load about
5), four runs after a first one that macOS slows by checking the new program; no M1 was available. The M3 Pro gains less on
mandelbrot than the x86 core (1.17 times the time before stage 3 against 1.0): its loop-carried chain is shorter, so the three
tests left show.

What is left in nbody (about 1.9 times before stage 3 on the M3 Pro, 1.6 times on Linux): its arithmetic is on fields, which have
no intervals, so every chain in the inner loop keeps a whole test, as it did with the plain double, and the products add tests the
plain double did not need (a tiny test for `dx * c.mass` in each of the six velocity updates, a two-term test for each update).
spectral_norm (1.2 to 1.5 times): the result of `a(i, j)`, a function call, is tested for a box, and `s + a(i, j) * v[j]` has its
two-term test.

**The browser** runs the IR of debug mode in an interpreter (`site/wasm/llvm.js`), so it has no fast copy; it gains only from the
two-term rule and the zero re-check. Seconds under Node 22 (`native/tomato-jsc.js`, compile included; mandelbrot 100, nbody 3000,
spectral_norm 80; median of three, on the loaded Linux machine, so about ±20%):

| | before | stage 3 | stage 5 | stage 5 compiled in release mode |
| --- | ---: | ---: | ---: | ---: |
| mandelbrot | 2.0 | 6.8 | 5.8 | 4.4 |
| nbody | 4.1 | 6.6 | 6.4 | 5.0 |
| spectral_norm | 7.8 | 9.1 | 8.9 | 16.8 |

Compiling for the browser in release mode would help the first two and hurt spectral_norm (release mode was already slower there
in the interpreter before this change); the website still compiles in debug mode. `llvm.js` now knows `llvm.fabs.f64` and
`llvm.sqrt.f64`, which only release-mode IR uses.

**Checks.** `tests/programs/float_loops.tom` (debug mode, release mode under AddressSanitizer with the leak check, and the
browser) crosses the edges of the double range inside loops, keeps boxes and tiny numbers in fields and list items, raises from
the middle of a loop, and compares 4,000 chains of tiny products with the same operations done one at a time. It found one leak:
a field assignment did not free the object it wrote into (`ps[i].x = ...`, where `ps[i]` is retained) when its value raised or
left the fast copy. All test programs print the same with the stage 3 compiler and this one in both modes, and 978 random float
loop nests (literals near 2^-960, 2^-1022 and beyond the double range, fields, list items, int and float mixed, division by zero)
print the same under the stage 3 compiler in debug mode and this one in release mode.

