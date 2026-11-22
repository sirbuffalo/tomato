# Idiomatic Tomato

How Tomato code in this repository is written: the compiler (`compiler/src`), the standard library (`std/`), the examples
and the test programs. The aim is the readability of good Python, using only what the language has today (see the status
table in `docs/specification.md`). When a rule here and the language disagree, the language wins; fix this file.

## Names

- `snake_case` for functions, methods, variables and fields; `CapWords` for classes (`Token`, `Diagnostic`, `Angle`). The
  built-in value types keep their lower-case names (`range`, `rational`, `progress_bar`), as in Python.
- A name says what the value is: `tokens`, not `toks`; `line`, not `ln`; `start`, not `s0`. One-letter names only for a
  loop counter (`i`, `j`), a character (`c`) or a number in a formula (`x`, `n`).
- A leading underscore marks a helper that the module does not export and that callers should not reach for (`_quote`).
- Operator and protocol methods (`@add`, `@iter`, `@len`, ...) get a short descriptive name (`plus`, `each`, `count`).

## Functions

- Small functions that do one thing, with a comment above saying *what* it gives when the name alone does not.
- Return early: check the special cases first and `return`, so the main path is not nested.
- Type every parameter and every return (`def f(x: int) -> str:`); leave local types to inference, and annotate a local
  only when inference cannot see it (`out: list[int] = []`).
- Default and keyword arguments instead of near-identical variants: `def make(self, n: int, d: int = 1)`.
- Write a helper once and import it; never paste a second copy into another module.

## Loops

- `for x in items:` to visit a list, text, dict, set, range or anything with an `@iter` method.
- `for i in range(n):` / `range(a, b)` / `range(a, b, step)` for counted loops; never a `while` with a counter you step by
  hand. `for i, x in enumerate(items):` when you need the position too.
- `while` is for loops whose end is not a count: scanning until a condition, Euclid's algorithm, a worklist.
- A generator (`@iter` method with `yield`) when a class is a sequence, instead of building a list just to loop over it.
- A variable has one type in the whole function, loop variables included, so give loops over different kinds of
  values different names (`for fld in c.fields:` and `for f in infos:`, not `f` for both).
- `for i, x in enumerate(items):` needs `items` to be a variable or a field; assign a call's result to a variable first.
- A `while` whose list grows inside the loop (a worklist) is fine; say so in a comment.

## Values

- `-x`, not `0 - x`; `x += 1`, not `x = x + 1` (there is no `//=` yet). One exception: on a float that may be zero,
  `0.0 - x` gives 0.0 where `-x` gives -0.0, which prints as `-0.0`; keep `0.0 - x` there and say why.
- Negative indexes and slices: `items[-1]`, `text[-2:]`, `text[:i]`, not `items[len(items) - 1]`.
- List literals and operators: `[a, b]`, `xs + [y]`, `[False] * n`, instead of appending item by item.
- Built-ins before hand-written loops: `min`, `max`, `sum`, `sorted`, `reversed`, `list(range(n))`, `len`, `in`,
  `str.join`, `str.split`, `str.find`, `str.replace`, `str.startswith`, `str.endswith`, `str.strip`.
- A class with fields instead of parallel lists or a list used as a record (`[prime, exponent]` pairs are acceptable only
  where they are a documented result type). Fields with defaults (`count: int = 0`) instead of setting each in `@init`.
- `dict[str, V]` to find things by name, instead of a search through a list (or two lists kept side by side).
- `tuple[T]` for a fixed group of values of one type that will not change.
- `T | None` and `is None` / `is not None` for "no value", not a sentinel like `-1` or `''` or a list of zero or one items.
  `and`/`or` stop early, so `x is None or x.size == 0` is safe.

## Comments and layout

- A comment says why, or what a block gives, not what each line does. A file starts with one comment saying what it is.
- Four spaces per level, one blank line between methods and between top-level definitions, lines up to 120 characters.
- Text in single quotes (`'abc'`), double quotes when the text holds a single quote.

## Errors

- Raise `RuntimeError` (or a subclass) with a message in the style of `docs/errors.md`: lower case, plain words, says what
  was wrong and, where it helps, what was expected.
- Check arguments at the top of a function and raise before doing work.
