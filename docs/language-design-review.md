# Language design review before 1.0.0

Status: recommendations only, written by the second pre-release audit (2026-11-26, on the tree after commit `b6de3d67` plus
that audit's fixes). Nothing here is decided: every language and API choice is Davis's. Each item gives the problem with
evidence from this repository (a program that was run, or a file and line), the proposed change, what it costs, and a
priority:

- **Blocks 1.0**: once 1.0.0 is out, D84a promises that a program working on one 1.0.x release works the same on all of
  them, so this has to be settled first or the fix waits for 1.1 (with a "Breaking changes" entry) or 2.0.
- **Do soon**: a gap users will hit early, but closing it later only adds things (a program that compiled before still
  does), so it does not have to wait for 1.0 or block it.
- **Maybe**: worth a decision, not urgent.

Comparisons with other languages are from general knowledge, not from anything in this repository, and are marked
*(general knowledge)*.

The evidence programs were run with the `tomato` built from this tree; each fits in a few lines and is quoted where it
matters. The short version is at the end: [Decisions to make, ranked](#decisions-to-make-ranked).

## What is good and should stay

To keep this honest: much of the design is sound and nothing below argues against it. Static types with local inference,
unlimited `int` with exact `int`/`float` comparison, `/` giving a float and `//`/`%` as in Python, UTF-8 text counted in
code points, Python's full Unicode case mapping (checked against Python 3.14 on all 1,114,112 code points in this audit),
reference counting plus a cycle collector (deterministic and simple), `try`/`catch`/`finally`, no top-level code, typed
entry points that read their inputs from the command line, errors with stable ids and `tomato explain`, and a
compiler written in the language itself. The markers (`@add`, `@lt`, `@init`) are a reasonable alternative to Python's
dunder names (section 2.1). The bigint and float work is careful: this audit fuzzed it against Python and exact
fractions and found no wrong results in `*`, `//`, `%`, `str`, `int(text)` or the bitwise operators.

## 1. The compatibility promise itself

### 1.1 The exemption for `docs/provisional.md` is too large (Blocks 1.0)

**Problem.** `docs/releasing.md` (Compatibility) promises that 1.0.x releases are compatible "except for the placeholders
in `docs/provisional.md`". That file has 91 placeholder rows (`grep -c '^| P[0-9]' docs/provisional.md`), 25 of them
marked superseded. Those still in force include the core syntax and semantics: P1 (indentation, comments), P5 (`if`,
`while`, `break`, `return`), P6 (local inference), P7 (block scope), P8 (`and`/`or`/`not`, bool conditions), P10
(comparisons), P11 (string escapes), P20 ("error wording is the prototype's own"), P22 (operators on mixed kinds) and
P24 (text operations). Read literally, the promise exempts nearly every program, so it promises little. Read loosely, it
promises things the documents still call undecided.

**Proposal.** Before 1.0, go through the table once and give each row one of three outcomes:

- promoted to decided (most of them: they have been the behaviour for 50 releases);
- kept on a short, named list of features outside the promise;
- removed as superseded.

For the short list, consider a compiler warning when a program uses one of those features, the way Rust gates unstable
features *(general knowledge)*. Then the promise can say "except the N features listed in section X".

**Cost.** Two or three hours of reading and a table edit. It changes no code. Without it, the promise means little.

### 1.2 Say what is promised about errors: ids, classes, message text (Blocks 1.0) — adopted as proposed by Davis, 2026-11-27 (D117a); written in `docs/releasing.md`

**Problem.** An error id is the line number of its template in `std/errors.txt` (`e.id` is `E04` for line 4, P88). A
program can test `e.id` in a `catch`. Ids are therefore append-only for ever, which commit `e82d1ec2` already practises:
retired lines say "the id stays so that later ids do not move". The promise does not say three things:

- whether ids are part of it;
- whether an error's class can change (a `RuntimeError` becoming a `ValueError` breaks a `catch RuntimeError`);
- whether message text can change (P20 says wording is undecided, yet tests and users match on it).

**Proposal.** State it in `docs/releasing.md`:

- an id never changes its meaning;
- the class of the error an operation raises does not change within a minor version;
- message text may be reworded in a patch release, but the first line keeps its id.

This also means the `std/errors.txt` line-number scheme must survive two branches that each add a line. Today the
second branch to merge must renumber its ids, and so must any open task (the repl editor task may be one). Write that
down in `docs/errors.md`.

**Cost.** Documentation. Without it, every reworded message is arguably a breaking change.

### 1.3 Release mode throws away the program's own error message (Blocks 1.0) — settled and built 2026-11-27 (D34c): release prints `error[E11]: ValueError: config file missing key port (line 3)`

**Problem.** `--mode release` is the optimised build, the one a server runs. Given

```
@main
def main():
    raise ValueError("config file missing key port")
```

`tomato run f.tom --mode release` prints only `error E11:3`. Debug prints `error: ValueError: config file missing key
port (raised on line 3)` and the call trace. Ids that the runtime raises can be decoded with `tomato explain`. For E11
(an error the program raised) the message is the only information, and it is lost. Text written to standard error is
the kind of output D84a's "prints something else" covers, so changing this after 1.0 would be a breaking change.

**Proposal.** In release mode print one line with the class and the message for every uncaught error, for example
`error[E11]: ValueError: config file missing key port (line 3)`, and keep only the call trace out of release builds.
If the reason for short ids was binary size, keep the short form only for the runtime's own messages: their text is in
`std/errors.txt`.

**Cost.** Small: `print_uncaught` in `runtime/tomato_rt.c` already has the message (`mode == 2` drops it). The tests of
release-mode output change.

### 1.4 Defining a builtin's name is silently ignored (Blocks 1.0; decided and built, D108a)

> **Status (2026-11-27).** Davis decided: a module's own definitions shadow the builtins (Python's rule, the first option
> of the proposal). It is built as D108a in `docs/decisions.md`: a function, class, interface or constant a module defines,
> and a name it brings in with `from m import name`, wins over a builtin of that name inside that module only; the code
> the compiler writes for f-strings, `assert`, unpacking, `enumerate`/`zip` loops and comprehensions keeps the builtins;
> the standard library is unaffected; the names of the built-in types (`int`, `uint`, `float`, `bool`, `str`, `File`,
> `list`, `dict`, `set`, `tuple`) stay reserved, and defining one is a compile error (E608). A local variable or parameter shadows a builtin too, in calls as well (Davis, the same day; D125a), and a variable named like a built-in type is E623. The text below is the
> original problem statement; the "today" in it is before D108a.

**Problem.** A program can define its own top-level function `len`, and the builtin still wins. Nothing warns about it:

```
def len(x: int) -> int:
    return 5

@main
def main():
    print(len(3))      # error[E324]: the argument of len has type int, but str is expected
```

Today that is only confusing. After 1.0 it becomes a compatibility hazard: every builtin added in 1.x (say `zip` as a
value, `enumerate`, `bytes`, `isinstance`) silently takes over the user functions of that name that compiled
before.

**Proposal.** Pick one rule now. Either a module's own definitions shadow builtins (Python's rule, and the one that
makes new builtins safe to add), or defining a builtin's name is a compile error (then a new builtin must be checked
against published code, and the error at least shows the clash). Shadowing is the safer one for a language that will
keep growing builtins.

**Cost.** A name-resolution change in `compiler/src/compiler.tom`, plus tests. It decides how std grows after 1.0.

### 1.5 The Unicode version is part of the behaviour (Do soon)

**Problem.** `upper()`, `lower()`, `title()`, `isalpha()` and `isdigit()` follow Unicode 16.0 tables in the runtime
(D17d, P89). The terminal width table was Unicode 15.1 until it was regenerated for 16.0 (`tools/gen_width_table.py`). A new Unicode
version changes results: U+2630-2637 and U+4DC0-4DFF are wide in 16 and were narrow in 15.1, for example.

**Proposal.** Say in the promise that the Unicode version changes only in minor releases and is named in the changelog
(Python changes it in minor releases too *(general knowledge)*). Keep all tables on one version.

**Cost.** One sentence, and a rule for whoever regenerates `tools/gen_case_table.py`'s or `tools/gen_width_table.py`'s output (both need Python 3.14, and the suite's "generated tables" check runs them with `--check`, and `tools/check_ctype_table.py` checks the isalpha/isdigit tables against Python).

### 1.6 Calling C from any program (`!name`) makes the runtime's internals public (Blocks 1.0; decided and built, D112a)

> **Status (2026-11-27).** Davis decided: `!name(...)` stays open for any symbol (libc, the program's own compiled C, any LLVM
> function the program links, in seeds too), except the runtime's private `tomato_*` functions. Declaring or calling one with
> `!` from outside `std/` is a compile error (E611) with the hint "tomato_* functions belong to the runtime and are not part of the
> language; use the std module that wraps it"; a seed that declares one is refused (E612), not offered for consent. The standard
> library, which ships with the toolchain, keeps using them. It is built as D112a in `docs/decisions.md`. The text below is the
> problem as it was written; no opt-in flag (`--allow-llvm`) is needed.

**Problem.** Any program can declare and call any C symbol, including the runtime's private functions:

```
!abs(x: int[length=32]) -> int[length=32]
!tomato_env_has(name: str) -> int

@main
def main():
    print(!abs(-5), !tomato_env_has("HOME"))     # 5 1
```

Two consequences follow:

- Every `tomato_*` function and its argument types become something a 1.0 program may rely on, so renaming one is a
  breaking change.
- D27b maps `float` to C `double`, but since D77a a `float` can be beyond a double's range.

The seed registry design also says a seed must be Tomato source only (`docs/package-registry-design.md`, section 5:
"Reject `!name(...)` declarations in any module that is not `std` ... I did not find such a check").

**Proposal.** Before 1.0, either allow `!` only in `std/`, or keep it for programs behind an explicit opt-in marked
outside the compatibility promise. Something like `--allow-llvm` for `tomato build` would do, in the spirit of Rust's
`unsafe` or Go's `import "C"` *(general knowledge)*.

**Cost.** One check in the compiler. `examples/mathlib.tom` with `mathlib.ll` shows the feature, so it needs the opt-in
or a std-only note.

## 2. Surface syntax

### 2.1 Operator markers versus dunders or interfaces (keep the markers; fix the `@` namespace) — problem 1 decided and built (D107a, 2026-11-27)

**Decided (problem 1).** Davis decided on 2026-11-27: marker names stay unique within a program (one function per marker, E583), and a short reserved list of built-in marker names (`main`, `test`, `bench`, `example`, `setup`, `teardown`, `deprecated`, `init` and every operator and protocol marker) may not be used as a program's own top-level entry name; a dotted entry under a reserved root is allowed only where the language defines it (`@test.NAME`), and `@` is never a user-defined decorator. This replaces Proposal 1's `@entry` form. Built as D113a (compile error E613); problem 2 (structural interfaces) is not decided. The text below is the audit's original.

**Assessment.** `@add` above `def plus(self, o)` (D12k) compares well with the alternatives:

- Python's `__add__` *(general knowledge)*: the method keeps a descriptive name and can be called as `a.plus(b)`;
- Kotlin's `operator fun plus` *(general knowledge)*: close to the same idea;
- Swift's `static func +` *(general knowledge)*: fewer special names to learn;
- Rust's `impl Add for T` *(general knowledge)*: much less machinery.

The cost is a closed list of markers that the compiler knows, which is fine for operators. Two things do need a
decision.

**Problem 1: one `@name` namespace serves three roles.**

- A top-level `@anything` makes an entry point (D16a): `@bench def b():` runs with `tomato run f.tom bench`.
- On methods, `@add`, `@hash` and the others are operator and protocol markers. At the top level they are refused:
  `@hash def h():` gives E96, "marks a method".
- `@test` (D81a) is a top-level marker with its own meaning; since D96a it is written `@test.NAME`, one marker per function, and any marker may be dotted.

So every new top-level marker takes a name some program may already use for an entry point. D81a's `@test` already did
that before 1.0. After 1.0, adding `@bench`, `@example` or `@setup` would be a breaking change.

**Proposal 1.** Reserve the namespace now: entry points other than `main` are written in one form that cannot clash.
`@entry def serve():`, run as `tomato run f.tom serve`, is the smallest change. Also decide now that `@` will never
mean a user-defined decorator, or reserve a form for that (`@@name`), so readers coming from Python are not misled.

**Problem 2: generic code cannot say "has `@lt`".** The TODO item "make `sum()`, `min()`, `max()` and `sorted()` work on
a list of angles" exists because a generic function cannot require an operator. Today `min(xs[0], xs[1])` on angles says
"needs a list of numbers or text" (compiler audit).

**Proposal 2.** Add built-in structural interfaces in the style of D57a's `Iterable[T]` and `Sized`, satisfied by
markers: `Comparable` (`@lt`, or `@lt` and `@eq`), `Addable[T]` (`@add`), `Hashable` (`@hash`). Then allow them as
bounds, `def max_of[T: Comparable](xs: list[T]) -> T`, which is how Swift and Rust do it *(general knowledge)*. The
builtins can then accept angles without special cases.

**Cost.** Proposal 1 is small (the parser and the entry-point lookup) and breaks programs that use other entry names
(in this repository only `examples/args.tom`, with `@greet` and `@prime`). Proposal 2 is a medium compiler change and only adds; *Do soon*.

### 2.2 `x in Type` for type tests (Blocks 1.0) — decided and built (D23i, 2026-11-27)

**Decided.** Davis chose the proposal below on 2026-11-27: the type test is `x is T` (and `x is not T`), replacing `x in T`. He added the meaning: `is` checks equivalence at the pointer (identity) level and also checks whether something is a type, so `a is b` on two reference values is identity, `x is T` with a type name is the type test, and `x is None` is the type test for `None`. Built as D23i: identity works on objects, interface values, lists, dicts, sets and their optionals (numbers, text and tuples are a compile error that points at `==`); the narrowing of D55a, D102a and D102b is the same for `is`, with `is not T` added for unions; `x in T` still works in 1.0.x with a warning (`# allow: type-test`; the transition is a default, not yet decided by Davis). A class or interface value is tested by the object's own class (D112a, decided by Davis the same day: `x is Animal` is true for a subclass instance, as `isinstance`), and `x is Dog` narrows a base-typed variable to a `Dog`. The text below is the audit's original problem and proposal.

**Problem.** `if x in int:`, `if shape in Circle:` (D23f) use the same word as membership (`if a in angles:`), and the
two read alike. For example `if v in Angle:` is a type test, while `if v in angles:` searches a list. A type name that
someone mistakes for a variable (or the reverse) gives a confusing error instead of a clear one. The language already
has `x is None` (D23c), and `None` is a type (D23d).

**Proposal.** Make the type test `x is T`, generalising `is None`, as Kotlin and Swift spell it *(general
knowledge)*. Keep `x in T` for 1.0.x only if programs need a transition, with a warning. Membership stays `in`.

**Cost.** The parser and the narrowing code (D55a) learn the new spelling. Every test and example that uses `in Type`
changes. Doing it after 1.0 means supporting both for a whole major version.

### 2.3 `@static` methods, and the std API that avoids them (Blocks 1.0 for the std names)

**Decided 2026-11-27 and built (D122a):** the std names stay free functions, `date_fromisoformat`, `time_fromisoformat`, `datetime_fromisoformat`, `datetime_strptime`, `date_today`, `datetime_now` and `datetime_combine`, and no method of the same job is added; one documented style. A program that writes `date.fromisoformat(...)` gets E115 with a help line naming the free functions. A real `@static` stays a separate language question (the proposal below).

**Problem.** `@static` exists, but it is built as a call on a fresh object made by the class's `@init` with no
arguments (`compiler/src/compiler.tom`, the `info.op == 'static'` branch near line 7727). So:

- a class whose `@init` takes arguments cannot have a static method;
- every call allocates an object.

Perhaps for that reason std does not use it. `datetime` exports `date_fromisoformat`, `time_fromisoformat`,
`datetime_fromisoformat`, `datetime_strptime`, `date_today`, `datetime_combine` and `datetime_now` as free functions,
where Python has `date.fromisoformat`, `datetime.now` and so on.

**Proposal.** Make `@static` a real function attached to the class name (no object). Then decide the std names before
1.0: either move these to `date.fromisoformat(...)` or keep the free functions as the final API. Renaming a std
function after 1.0 is a breaking change.

**Cost.** Medium for the compiler. The std renames are mechanical, but they touch every test that uses them.

### 2.4 Keyword arguments when creating objects (Do soon)

**Problem.** Functions take keyword arguments (D39a), but `P(x=2)` is E219, "keyword arguments are not supported when
creating an object". `terminal.Style` takes its fields positionally for this reason (D86a). For a class with several
fields of the same type this invites swapped arguments.

**Proposal.** Pass keywords through to the `@init` method. Only adds.

## 3. Types

### 3.1 `int | None`, `float | None` and `bool | None` (Do soon, high)

**Done (D94a, 2026-11-26).** The three optionals and `d.get(k)` for every value type are built, as a pointer to the union's box; the text below is the problem as found in the audit. Narrowing by `is None` / `is not None`, which the audit also asked for, is D102a (2026-11-27).

**Problem.** The most common optional value is a missing number, and it cannot be written:

- `x: int | None = None` is E459, "only str, lists, dicts, sets, classes and tuples can be None", with the help "use
  int with a flag or a default value, such as -1 or 0".
- The same rule makes `d.get(k)` a compile error when the values are `int` (E380), and fine when they are `str`.

General unions already box their members (`int | str` works, P62), so `int | None` needs no new representation, only
the union path where the optional path is refused today.

**Proposal.** Allow them through the existing union boxing. `d.get(k)` then has one rule for every value type.

**Cost.** A compiler change in an area that is already built. It only adds: programs that compile today do not change.
It is the gap most likely to make a Python user give up early.

### 3.2 Closures and bound methods (Do soon; decide the capture rule before building)

**Problem.** A lambda cannot use a variable of the function around it (`f: fn(int) -> int = x -> x + k` is E151).
There are no bound methods (`obj.method` as a value) and no generic functions as values (D63a). Callbacks therefore
take their context as extra parameters, or need a class with an interface, as the repl editor's hooks do (D86a).

**Proposal.** Decide the capture rule now, even if it is built later. Python and Go capture variables by reference;
Swift copies unless told otherwise *(general knowledge)*. Given D05a (objects are shared, numbers are values), the
least surprising rule is capture by reference of the variable. A capture that forms a reference cycle is then left to
the collector (D29d).

**Cost.** Large: closure environments in the compiler and the runtime. It only adds.

### 3.3 Error classes do not inherit `@init`, and errors cannot be printed (Do soon, high)

**Status (2026-11-26): done (D93b).** A class that declares no fields inherits its parent's `@init`, and `Error` has an `@str` giving the message alone. The text below is the problem as found.

**Problem.** The first error class a user writes does not work:

```
class MyErr(ValueError):
    pass
...
raise MyErr("neg")       # error[E128]: 'MyErr' takes 0 arguments, but 1 given
```

So every error class in std repeats an `@init` that only forwards its arguments (`std/json.tom` lines 55-64:
`def make_encode(self, message: str, id: str = ''): RuntimeError.make(self, message, id)`). And `print(e)` on a caught
error is a compile error (E375, "objects cannot be printed"). Users write `print(e.message)` once they find the field.

**Proposal.**

- A subclass that declares no fields and no `@init` inherits its parent's `@init`, as in Python and Kotlin *(general
  knowledge)*.
- `Error` gets an `@str` giving the message (Python's `str(e)`). Decide the exact text before 1.0: the message alone,
  as Python's `str(e)` gives, is the conventional choice.

**Cost.** Small to medium. Inheriting `@init` only adds; the text of `str(e)` should be fixed before 1.0, since
changing it later changes output.

### 3.4 Fixed-width integers: the spelling and the literal rule (Maybe)

**Problem.** The spelling `int[length=32]` is long compared with `i32`/`u8` in Rust and Zig or `int32`/`uint8` in Go
*(general knowledge)*.

The literal rule D05t ("arithmetic literals use the typed operand's type") gives one surprise:

```
x: int[length=32] = 5
print(x * 1000000000)    # error[E03]: integer overflow, at run time
```

Rust and Go give the literal the operand's type too *(general knowledge)*. Go then wraps silently; Rust panics in a
debug build. Here, though, the default `int` never overflows, so a reader does not expect the literal to be narrowed.

**Proposal.** Optional aliases `int32`, `uint8` and so on, which only add. Consider a compile-time warning when a
constant operand times a fixed-width value can overflow its range.

**Cost.** Small. No compatibility risk.

### 3.5 `==` on unions, dicts and sets; `x is Type` on generic and fixed-width types (Do soon)

Listed as "not yet" in the specification's status table. They only add, but `==` on unions is basic enough to come
before most new std modules.

## 4. Errors

### 4.1 Keep exceptions; fix the hierarchy before 1.0 (Blocks 1.0 for the class names; decided and built, D114a)

> **Status (2026-11-27).** Davis decided: one tree, as proposed. Built as D114a in `docs/decisions.md`: the built-in classes
> `TimeoutError` and `ConnectionError` are under `IOError` (the name `IOError` is kept, there is no `OSError`); `asyncio` and
> `requests` timeouts and `requests`' connection error extend them, and the `socket` family moves under `ConnectionError`;
> `json`, `toml` and `re` errors are `ValueError`s and `CacheMiss` a `KeyError`; the file errors stay `IOError`s (D80a). A
> bare `raise` in a `catch` raises the innermost caught error again with its line and trace, and is the compile error E614
> anywhere else (outside a `catch`, in the `try` body or `finally`, in a function a `catch` calls). The text below is the
> problem as found.

**Assessment.** Exceptions (`raise`, `try`/`catch`) suit a Python-like language. Go-style result types would fight
the syntax, and Rust's `Result` with `?` needs sum types the language does not have (D21a: no enums or variants). Keep
them.

**Problem.** The class tree is not one design yet (open question 60, "the final error class tree"):

- `asyncio.TimeoutError` and `requests.TimeoutError` are two unrelated classes.
- `requests` has its own `ConnectionError`, while `socket` has a `SocketError` family with `ConnectionRefusedError`
  and `ConnectionResetError`.
- File errors are `IOError` with subclasses such as `FileNotFoundError` (D80a). Python 3 merged `IOError` into
  `OSError` *(general knowledge)*.

A `catch` clause names classes, so renaming or re-parenting one after 1.0 is a breaking change.

**Proposal.** One tree before 1.0:

- builtin `TimeoutError` and `ConnectionError` under `IOError` (or under an `OSError`, if Davis prefers Python's
  name);
- modules raise subclasses of those (`asyncio.TimeoutError(TimeoutError)`), so `catch TimeoutError` catches both
  timeouts;
- decide rethrow (a bare `raise` inside `catch`), open in the specification's Errors row.

**Cost.** Small code changes in `std/`; the decision is the work.

## 5. Memory and resources

### 5.1 A `File` is a bare C stream: closing it twice reads freed memory (Blocks 1.0; default built, see D93a)

> **Status (2026-11-26).** Davis has not decided this one. The implementer built the proposal below as a default (D93a in
> `docs/decisions.md`, "default chosen by the implementer, easy to change"): `File` is a counted object holding the stream
> and a closed state, `close()` twice does nothing, any other operation on a closed file raises `ValueError` E547,
> `f.closed()` says which, and the file is closed when its last reference goes away. `with` is not built. The text below
> is the original problem statement; the "today" in it is before D93a.

**Problem.** Since D82a, `for line in open(p):` closes its file. Otherwise a `File` is "a bare C stream" (D82a's own
words), and using or closing it after `close()` is "still undefined". In practice that means memory unsafety reachable
from ordinary code:

```
f = open(path, "w")
f.write("hi")
f.close()
f.close()       # passes a freed FILE * to fclose: printed error[E382] ... Bad file descriptor here; a use after free
```

Reference counting does not close a file whose last reference goes away either. The only cleanup is an explicit
`close()`: there is no `with` (deferred in D80a) and no destructor.

**Proposal.**

- Make `File` a small object: the stream, plus a closed flag.
- `close()` twice does nothing.
- Reading or writing a closed file raises `ValueError` (Python's behaviour *(general knowledge)*).
- The file is closed when its reference count reaches zero.

Then, soon after, add the `with` statement for files and locks.

**Cost.** Medium: the `File` representation is used by the compiler (`file_check` calls) and the runtime
(`tomato_file_*`). One flag test per call is negligible next to stdio. A safe language should not leave this
undefined at 1.0.

### 5.2 Reference counting, cycles and threads (Maybe)

Reference counting with a synchronous trial-deletion collector (D29a, D29d, P42) is a good fit: it is deterministic
and needs no tuning. Two decisions remain open and deserve one sentence each in the specification before 1.0:

- **Threads.** The runtime's counts are not atomic, and there are no threads (D31a is open). Saying "a Tomato program
  runs on one thread; parallelism, if it comes, will be processes or isolated workers" keeps that option without a
  promise.
- **When the collector runs.** Destructor order does not matter today, since there are no user destructors. It will
  matter if 5.1 closes files on release.

## 6. Concurrency

### 6.1 The logical clock of `await sleep` (Blocks 1.0: decide)

**Problem.** D58c makes time logical: a sleeper wakes on a clock that moves only when every task is waiting. Natively,
the process also really waits until real time catches up. That gives the same output order on every machine, which
is excellent for tests and for the browser. For a server it means:

- the scheduler's clock and `time.monotonic()` disagree;
- a task computing for two seconds does not move the clock, so `asyncio.wait_for(t, 5)` (D76a, "the scheduler's
  clock") measures something other than wall time;
- the order of wake-ups is a promise that real I/O (sockets, D76c) cannot keep.

This is observable behaviour, so it falls under the promise.

**Proposal.** Pick one:

- **(a)** Keep the logical clock as the documented rule, and say explicitly that timeouts are in scheduler time.
- **(b)** Use real time natively, and make the deterministic clock an opt-in for tests (`tomato test` and the browser
  use it by default), as Trio's `MockClock` and tokio's `time::pause` do *(general knowledge)*.

(b) is the conventional choice for a language aimed at web servers (D01a).

**Cost.** (a) is documentation. (b) is a scheduler change and a test-mode switch, and changes some async test
expectations.

### 6.2 Structured concurrency (Maybe)

`start f()` makes a free-standing `task[T]`; `asyncio.gather` and `wait_all` collect results. A task group (Python
3.11's `TaskGroup`, Trio's nursery *(general knowledge)*) makes it hard to lose a task's error. It only adds; consider
it with 6.1.

## 7. Numbers

### 7.1 Floats of any size, and limits that depend on a config file (Blocks 1.0: confirm D77g)

**Problem.** `float` has an exponent of any size (D77a). That is unusual, and it is carefully built: the audit
checked `//`, `%`, the formats and the library against exact fractions. Three consequences belong in the promise.

1. **The limits depend on a file.** `exp`, `**` and the `f` format stop with E528/E529 at limits set in a
   `tomato.toml` or in `~/.tomato/config.toml` (D77g). Those limits are written into the program when it is built. So
   the same source can behave differently on two machines, and a project's `tomato.toml` that only has `[project]`
   hides the user's `[limits]`. D77g is marked "defaults chosen by the task; to be confirmed by Davis".
2. **Interoperability.** JSON writes `1e+400`, which other parsers read as infinity or reject. MessagePack refuses it.
   The C interface maps `float` to `double` (1.6).
3. **Python agreement.** Python raises `OverflowError` where Tomato gives an exact huge value
   (`1e308 // 1e-308`, `float(10 ** 400)`). This is deliberate and documented; it is worth one line in the
   introduction for Python users.

**Proposal.**

- Confirm D77g, or make the limits fixed constants. Fixed constants are the simpler promise: settings that change
  results are usually per-program options, not per-user files.
- If they stay settings, read only the project's `tomato.toml`, not `~/.tomato/config.toml`, so a build does not
  depend on whose machine it is.

**Cost.** A decision; little code either way.

### 7.2 Edges that differ from Python (Maybe)

- `1 ** 2**62`, `(-1) ** (2**62 + 1)` and `0 ** 2**70` raise "the exponent is too big", where Python gives 1, -1 and 0.
- `5 >> 2**31` raises "the shift count is too big", where Python gives 0.

These are cheap special cases if agreement with Python matters (bigint audit, `tomato_int_pow` and `int_shift_count`
in `runtime/tomato_rt.c`).

## 8. Text and bytes

### 8.1 There is no `bytes` type: binary data is `list[int]` (Blocks 1.0)

**Problem.** Every binary API takes or returns `list[int]`:

- `base64.b64encode(data: list[int])`, `hashlib.sha256(data: list[int])`;
- `hmac.digest(key: list[int], msg: list[int], ...) -> list[int]`;
- `os.read_bytes(path) -> list[int]`, `utf8.encode(text) -> list[int]`, `hex.encode(data: list[int])`;
- `socket.send(list[int])`.

An item can be any integer (`[1, 2, 300, -5]` is a valid "byte list"), so every API must check its input or misbehave.
A `list[int]` keeps 8 bytes per byte or more. And every one of these signatures changes the day a `bytes` type
arrives.

**Proposal.** Add an immutable `bytes` (literal `b'...'`, indexing gives `int`, slicing gives `bytes`) and perhaps a
mutable `bytearray`, as Python does *(general knowledge)*, and change the std signatures before 1.0. If that is too much
for 1.0, use `list[uint[length=8]]` in the signatures now. Fixed-width lists are already compact ("lists of bool and of
fixed-width integers keep 1, 2 or 4 bytes per item"), and that type at least rejects 300.

**Cost.** A new builtin type is medium to large. Switching the signatures to `list[uint[length=8]]` is small and keeps
the door open. Either is cheap compared with changing a dozen std modules after 1.0.

### 8.2 Smaller text points (Do soon)

- `"\x00"` is E315 (unknown escape `\x`); only `\u{...}` exists (P11). Accepting `\xHH` as Python does only adds.
- `print` takes no keywords (`print(1, 2, sep="-")` is E111). `sep` and `end` are basic and only add.

## 9. Modules and seeds

### 9.1 One flat module namespace, with std shadowed silently (Blocks 1.0: reserve the names; decided and built, D115a)

> **Status (2026-11-27).** Davis decided all three points of the proposal, and they are built as D115a in
> `docs/decisions.md`: std's module names are reserved by a published list, `std/reserved.txt` (every std module and 55
> names it may add; the compiler's copy is `compiler/src/modnames.tom`, checked by the suite); a seed may not provide a
> reserved name (the manifest reader and `tomato seed check` refuse it); a project file that shadows an existing std module
> still wins but gives a warning, once for each name, naming both (`# allow: module-shadow`); a file with a reserved but
> not yet existing name is allowed and silent, and keeps shadowing the module with the warning once std adds it; and
> `import x as y`, `from x import a as b` exist (the original name is not bound). A list was chosen over a `std.` prefix.
> What stays open: re-exports, folders of modules, and Davis's trimming of the list. The text below is the original problem
> statement; the "today" in it is before D115a.

**Problem.**

- A file `json.tom` next to a program replaces `std/json.tom` for that program, silently. The seed design keeps that
  on purpose: "a project can still shadow anything (as it can shadow `std` today)".
- There is no `import x as y` (`import math as m` is E335).
- There are no folders of modules.
- The seed design (`docs/package-registry-design.md` section 5) rests on this flat namespace: a seed `owner/json5` must
  provide `json5.tom`. A std module added later under the same name as a seed is "a compile error naming both".

After 1.0, every new std module (an `http`, a `bytes`, a `log`) is then a potential breaking change for programs that
have a file or a seed of that name.

**Proposal.** Before 1.0:

- reserve std's future names, either a list (the common Python module names) or a prefix (`std.http` alongside the
  bare names);
- make shadowing a std module a warning;
- add `import x as y` and `from x import a as b`, which the seed design also needs to resolve its two collision cases
  without renaming files.

Answer the five open questions of the seed design (already a TODO item) with this in mind.

**Cost.** Small in the compiler (`read_module` and the import parser). The reserved-name decision is the important
part.

## 10. The standard library's shape (Blocks 1.0 for renames)

**Decided 2026-11-27 and built (D122a):** `math.abs`, `math.min`, `math.max` and `math.pow` are gone (the first three are built in; there is no built-in `pow`, so `**` is the way); `testing._run_all` is not exported, and the test driver the compiler writes reaches it; `json` and `toml` read into and write from one `Value` type in the new std module `value`. The bullets below are the findings the decision answers.

What is in std is broad and mostly modelled on Python, which is a good default. Before names freeze:

- **`math.abs`, `math.min`, `math.max`, `math.pow`** are int-only functions (`std/math.tom` lines 4-28) with the same
  names as builtins. `math.pow(2, -1)` raises E41, where Python's `math.pow` gives `0.5` *(general knowledge)*. Remove
  them, or rename them (`ipow`) so `from math import pow` does not quietly give the integer version.
- **Two dynamic value types.** `json` has `Json` with `JsonInt`, `JsonStr` and the rest, and `loads`/`dumps`. `toml`
  has `Toml` with `integer()`, `real()` and `moment()`, and `dumps_value`. Similar jobs, different shapes. Pick one
  pattern (accessor names, how a missing key behaves) before third-party seeds copy both.
- **Exported internals.** `testing._run_all` is exported. Decide whether a leading underscore means private (and
  enforce it) or rename the function.
- **`datetime` free functions.** See 2.3.
- **Error classes.** See 4.1.
- **Missing basics worth having before seeds fill the gap:** `bytes` (8.1), `with` (5.1), `enumerate` and `zip` as
  values (only in `for` today), set and dict comprehensions, `print(sep=, end=)`.

## 11. Tooling

### 11.1 `tomato run FILE ENTRY INPUTS` needs the entry name to pass any input (Blocks 1.0: decide)

**Problem.** `tomato run prog.tom 5` gives `error[E228]: no function is marked @5`. To pass an input, a program must be
run as `tomato run prog.tom main 5`, and every shell script that runs a Tomato program carries the extra `main`. `tomato
build` already has `--entry NAME`.

**Proposal.** Make `run` the same as `build`: inputs are positional and the entry is `--entry NAME` (default `main`).
If both forms must work, decide which wins when the first word names an entry point. The command line is used by
scripts, so this is as hard to change after 1.0 as the language.

**Cost.** Small in `native/tomato`, but every test and document that writes `run f.tom main ...` changes.

### 11.2 Configuration typos are silent (Do soon)

`[Limits]` or `[limit]` in `tomato.toml` is ignored without a word (floats audit), because unknown tables are skipped
so that `[project]`, `[seed]` and the other manifest tables can live in the same file. Reject unknown tables (an error, as
section 2 of `docs/package-registry-design.md` says), except the known list of the file in question (a project's `tomato.toml`: `project`, `seed`, `seeds` (with its sub-tables `seeds.ENTRY`, D92b),
`seed-store`, `limits`, `build` (with `build.ENTRY`, D92c, whose only keys are `mode` and `output`); the user's `config.toml` also has `registry`, `registries` and `aliases`, section 13).

### 11.3 `tomato update` trusts HTTPS and a checksum in the same manifest (Do soon)

README: "archives are not signed yet". The macOS package is notarized; the Linux tarball that `tomato update` runs
`install-native.sh` from is checked only against `latest.json` on the same site. A signature with a key pinned in the
install (minisign or signify style *(general knowledge)*) closes that before the user base grows. The atomic install of
commit `a95070c5` is good: this audit found no way to lose the old install.

## Decisions to make, ranked

In the order I would take them, with my recommendation for each. The first eight are the ones 1.0 locks in.

1. **The compatibility promise's exceptions (1.1, 1.2).** Promote most `docs/provisional.md` rows to decided, keep a
   short named unstable list, and state that error ids and classes are stable while message text is not.
2. **Release-mode error output (1.3).** Print the class and message of every uncaught error in release mode.
3. **Builtins versus user names (1.4).** A module's own definitions shadow builtins. *Decided by Davis on 2026-11-27 and built (D108a).*
4. **The `@` namespace and the type test (2.1, 2.2).** Entry points other than `main` as `@entry`; type tests as
   `x is T` (2.2 decided and built, D23i).
5. **`bytes` (8.1).** A `bytes` type before 1.0, or at least `list[uint[length=8]]` in every binary std signature.
6. **`File` safety (5.1).** A closed flag, an idempotent `close()`, close on the last reference (built as a default, D93a, for Davis to confirm or change); `with` soon after.
7. **Module names (9.1).** Reserve std's future names, warn when a project file shadows std, add `import ... as`. *Decided by Davis on 2026-11-27 and built (D115a).*
8. **The `!` C interface (1.6).** Decided and built (D112a): open for any symbol except `tomato_*`, which only `std/` may use.
9. **The error class tree (4.1; decided and built, D114a).** One `TimeoutError` and `ConnectionError` that module errors subclass; bare `raise`
   rethrows.
10. **The sleep clock (6.1).** Real time natively, with the logical clock as the test and browser mode.
11. **`tomato run` inputs (11.1).** `--entry NAME` as `build` has, inputs positional.
12. **D77g's limits (7.1).** Fixed constants, or project-file-only settings.
13. **std names that would freeze (2.3, 10).** *Decided 2026-11-27, built: D122a.* Free functions confirmed; `math.pow` and
    friends removed; `testing._run_all` unexported; one value type for `json` and `toml`.

Not ranked because they only add and can come in 1.x: `int | None` (3.1, the most valuable of them), error classes
that inherit `@init` and print (3.3), closures (3.2), operator interfaces as generic bounds (2.1), keyword arguments for
constructors (2.4), `print(sep=, end=)` and `\xHH` (8.2).
