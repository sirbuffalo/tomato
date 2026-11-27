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
- A parameter that only needs to be looped over is `Iterable[int]` (add `& Sized` if it also needs `len()`), not
  `list[int]`, so a range or your own class fits too.
- A generator (`@iter` method with `yield`) when a class is a sequence, instead of building a list just to loop over it.
- A variable has one type in the whole function, loop variables included, so give loops over different kinds of
  values different names (`for fld in c.fields:` and `for f in infos:`, not `f` for both).
- `for i, x in enumerate(items):` needs `items` to be a variable or a field; assign a call's result to a variable first.
- `for k, v in d.items():` and `for a, b in pairs:` take the pairs apart; the targets are plain names.
- A `while` whose list grows inside the loop (a worklist) is fine; say so in a comment.

## Values

- `-x`, not `0 - x`; `x += 1`, not `x = x + 1` (and `//=`, `**=`, `&=`, `|=`, `^=`). One exception: on a float
  that may be zero, `0.0 - x` gives 0.0 where `-x` gives -0.0, which prints as `-0.0`; keep `0.0 - x` there and say why.
- Negative indexes and slices: `items[-1]`, `text[-2:]`, `text[:i]`, not `items[len(items) - 1]`.
- List literals and operators: `[a, b]`, `xs + [y]`, `[False] * n`, instead of appending item by item.
- Built-ins before hand-written loops: `min`, `max`, `sum`, `sorted`, `reversed`, `list(range(n))`, `len`, `in`, `abs`,
  `chr`, `ord`, `int(text)`, `str.join`, `split`, `find`, `rfind`, `count`, `replace`, `startswith`, `endswith`,
  `strip`, `isdigit`, `isalpha`, `isspace`. `find`, `rfind` and `count` take a start and an end (`s.find(',', i)`), and
  `strip`, `lstrip` and `rstrip` take the characters to remove (`digits.rstrip('0')`).
- List methods change a list in place: `xs.pop()` (or `xs.pop(i)`) to take an item out, not `xs[-1]` followed by
  `xs = xs[:-1]`; `xs.insert(i, x)`, `xs.extend(ys)`, `xs.sort()` and `xs.reverse()` instead of rebuilding the list.
- Functions as values for the small decisions: `sorted(xs, key=p -> p.age)`, `map(f, xs)`, `filter(f, xs)`, instead of
  a hand-written sort or a loop that only applies one call.
- `x not in items`, not `not (x in items)`; `counts.get(word, 0) + 1`, not an `if word in counts` branch; `d.get(key)`
  gives `None` for a missing key when the value is text, a list, a dict, a set or an object.
- f-strings to build text: `f'{name} has {count} items'`, not a chain of `+` and `str()`. `{{` and `}}` are literal braces.
- `a if cond else b` for a choice between two values; an `if` statement when each branch does more than produce a value.
- `[f(x) for x in items if cond]` to build a list from another sequence; a loop when the body does more than add one item.
- A class with fields instead of parallel lists or a list used as a record (`[prime, exponent]` pairs are acceptable only
  where they are a documented result type). Fields with defaults (`count: int = 0`) instead of setting each in `@init`.
- `dict[str, V]` to find things by name, instead of a search through a list (or two lists kept side by side).
- `tuple[T]` for a fixed group of values of one type that will not change. A pair or group of different types is a mixed tuple, `tuple[str, int]` (a fixed length, indexed by a written number such as `p[1]`; `a, b = p` takes it apart).
- `a, b = b, a` to swap and `low, high = bounds(xs)` to take a tuple apart, not a pile of temporaries or indexes.
- Test a type with `x is T` (and `x is not T`); `in` is only membership. Narrow a union with `if x is T:`; after `if x is T: return` the rest of the function sees the other members, and after `if x is not T: return` it sees `T`. `a is b` on two objects, lists, dicts or sets asks whether they are the same one; compare numbers and text with `==`. `a is Dog` on an `Animal` looks at the object (true for a `Dog` or a subclass) and makes `a` a `Dog` inside the branch.
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
