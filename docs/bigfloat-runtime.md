# Floats of any size: the runtime API

Stage 2 of `docs/bigfloat-design.md`: the C functions (`runtime/tomato_rt.c`, the sections from "floats of any size" to the end) that
stage 3 of the compiler will call. **Nothing calls them yet**: a Tomato `float` is still a double. Tests: `tests/bigfloat.c`.

## The word

A float is one 64-bit word, `i64` in LLVM IR.

- **Plain**: the bits of a finite double.
- **Boxed**: `0x7FF8000000000000 | address` of a heap object `{ double m; int64_t e; }`, the value `m * 2^e`, with `1 <= |m| < 2` and `e`
  an `int` word of any size (it may own a big number).

The form is **canonical**: a value that is exactly a double (subnormals included) is always plain. There is no infinity and no NaN. A plain
word can be used as a `double` after a bitcast; a boxed word is a NaN, so `fcmp uno x, x` says "boxed".

Canonical has one consequence that is easy to miss: **the result of a hardware `*`, `/` or `pow` is final only when its size is above
`2^-1022` (the smallest normal double), strictly**. A subnormal, zero or exactly `2^-1022` result may have been rounded to too few digits, or up
to `2^-1022`, so it must go to the slow function, unless an operand is zero. A hardware `+` or `-` is final when it is finite.

## Ownership

A box has **one owner**. It is copied, never shared, exactly like a big `int`. In debug builds boxes are counted with the big numbers
(`N big number(s) were never freed`).

| function | |
| --- | --- |
| `i64 tomato_bf_dup(i64 x)` | a copy (a plain word is its own copy) |
| `void tomato_bf_free(i64 x)` | frees a box; nothing for a plain word |
| `i32 tomato_bf_is_boxed(i64 x)` | |

Operations **borrow** their operands and return a fresh word that the caller owns. Those with an `i32 m` also free operands the caller gives up:
bit 0 is `x`, bit 1 is `y` (the `_c` convention of the int functions). `m` 0 borrows both. An `int` operand is given up the same way.

## Functions

Results are the exact value rounded once, to nearest, ties to even (D05ae), except where "C library" is written.

| function | |
| --- | --- |
| **conversions** | |
| `i64 tomato_bf_from_f64(double d)` | a finite double (the same as a bitcast) |
| `i64 tomato_bf_from_int(i64 n, i32 m)` | any `int`, rounded once |
| `i64 tomato_bf_to_int(i64 x, i32 m)` | the whole part towards zero, exact |
| `i32 tomato_bf_fits_f64(i64 x)` | 1 when `to_f64` gives a finite double. A `float[length=64](x)` conversion raises OverflowError on 0 |
| `double tomato_bf_to_f64(i64 x)` | the nearest double; a tiny value becomes a subnormal or a signed zero |
| `i64 tomato_bf_int_div(i64 x, i64 y, i32 m)` | `int / int` of any size; `y` is not zero |
| **comparison** | -1, 0 or 1, always exact |
| `i32 tomato_bf_cmp(i64 x, i64 y, i32 m)` | two floats |
| `i32 tomato_bf_cmp_int(i64 x, i64 n, i32 m)` | a float `x` and an `int` `n` |
| `i32 tomato_bf_sign(i64 x)` | -1, 0 or 1 |
| **arithmetic** | |
| `i64 tomato_bf_add / _sub / _mul / _div(i64 x, i64 y, i32 m)` | `/`: `y` is not zero (the compiler tests it, as today) |
| `i64 tomato_bf_floordiv(i64 x, i64 y, i32 m)` | the floor of the *rounded* quotient, as a float: what `//` on doubles gives today |
| `i64 tomato_bf_mod(i64 x, i64 y, i32 m)` | the exact remainder with the sign of `y`, as `%` on doubles gives today |
| `i32 tomato_bf_pow_check(i64 x, i64 y)` | 0 when `x ** y` has a value, 1 for zero to a negative power (ZeroDivisionError), 2 for a negative number to a power that is not whole (ValueError) |
| `i64 tomato_bf_pow(i64 x, i64 y, i32 m)` | call the check first |
| `i64 tomato_bf_neg / _abs(i64 x, i32 m)` | use these, not `fneg`, which would break a box |
| **text** | |
| `void *tomato_bf_str(i64 x)`, `void tomato_bf_print(i64 x)` | as `str()` and `print` show it (below) |
| `i64 tomato_bf_text(void *text)` | `float(text)`; the word `0x7FF0000000000000` (no float) when it is not a number |
| `i64 tomato_bf_literal(const char *s)` | a literal of the program (valid decimal text) |
| `i64 tomato_bf_parse_cstr(const char *s, int position)` | an input of the entry point; stops with E351 |
| `i64 tomato_bf_round(i64 x, i64 ndigits, i32 m)` | `round(x, ndigits)` |
| `void *tomato_bf_format(i64 x, i64 prec, i64 kind)` | f-string formats `f`, `e`, `g` (`kind` is the letter) |
| **math** | |
| `i64 tomato_bf_math1(i64 op, i64 x, i32 m)` | the `op` numbers of `tomato_math1` |
| `i64 tomato_bf_math2(i64 op, i64 x, i64 y, i32 m)` | the `op` numbers of `tomato_math2`: 0 is `atan2(y, x)`, 1 is `hypot` |

They are all total on what they accept, so a call never raises a catchable error. A zero divisor, a power without a value and a math argument
outside its domain stop the program (E01, E13): the caller tests them first, as it does now. What cannot be allocated is E349 "out of memory".

**Plain operands with a plain result give exactly what they give today**: the hardware's `+ - * /`, `fmod`, `floor(x / y)`, the C library's `pow`
and math functions. So the functions can be called with any operands, not only boxed ones.

For the rest: a boxed `sqrt`, `cbrt`, `exp`, `expm1`, `log`, `log2`, `log10`, `log1p`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, and `**` with a boxed
operand or result, are correctly rounded (tiny arguments of `sin`, `tan`, `asin`, `atan` and the like give themselves). `hypot` and `atan2` of a box are
the C library's, on scaled operands. `sin`, `cos` and `tan` of a box above `2^1023` stop the program: `std/math.tom` reduces the angle first.

## Text

- A box prints like a large double: the shortest digits that read back as the same float (the first of its roundings to 1, 2, 3 ... digits that
  does), then the exponent in full: `1.5e+1000000`, `-3e-12345678901234567890`.
- When the **binary exponent has more than 4096 bits**: the exact `0x1.8p+E`, with `E` in decimal.
- **A subnormal double prints more digits than today** when it is a `float`: `2^-1074` is `4.9406564584124654e-324`, because `5e-324` is now a different
  float. (`float[length=64]` keeps printing `5e-324`.) Every normal double prints as today.
- `tomato_bf_text` reads both forms, any number of digits and any exponent. `inf`, `nan`, and hex without a `p` exponent are not numbers, as today.

## How it works

- **`+ - * /` and `sqrt`** of boxes work on the significands as doubles in [1, 2): the hardware rounds them exactly as the whole result has to be
  rounded, and the exponent is an `int` addition (20 to 30 ns, mostly the allocation).
- **`%`** with far-apart exponents takes the power of two modulo the divisor's significand.
- **`**`, `exp`, `log`, text**: fixed-point numbers held in `int`s (`fx_log`, `fx_exp`, `fx_logs`), with about 128 bits beyond what the exponent
  needs. `bf_round_near` gives a result only when every value within the error bound rounds the same way; otherwise the work is repeated with twice the
  precision. Cases that really are halfway between two floats, which no precision settles, are done exactly (the comments say why there are no others).
- Costs measured on Linux x86-64: printing or reading a box about 40 us with a 62-bit exponent, 0.1 ms with 512 bits, 2 ms with 4096 bits.

## Limits

- `exp` and `**` need as many bits of log 2 as the result's exponent has, in quadratic time: an exponent of 100,000 bits takes about a second. A
  result whose exponent would need more than 2^31 bits (or a whole part, a digit string or a power of ten of more than 2^31 bits) is "out of memory". Powers of two to a whole power (`2.0 ** y`) are exact and quick.
- `int(x)`, `round` and the `f` format of a box build every digit, so they need memory in proportion to the exponent's value.

## Testing

```
clang -O1 -g -fsanitize=address,undefined -o bigfloat tests/bigfloat.c -lm && ./bigfloat [rounds] [seed]
```

`tests/run.sh` runs 1,500 rounds. The reference is a schoolbook whole-number implementation inside the test that shares no code with the runtime.
Correct rounding is checked for `+ - * / // %`, int conversions, int division, comparison, reading, printing (reads back, nearest, no shorter one),
whole and root powers and `sqrt`. `exp`, `log`, general `**`, the formats and `round` are checked against recorded results of Python's `decimal` and
`fractions`. `./bigfloat --eval` reads operations from standard input, so that the whole can be compared with any other implementation; Python
itself is not needed.
