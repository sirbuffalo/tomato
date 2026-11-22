# Tomato open questions

Every question still to decide. Nothing here is decided or assumed; Davis decides all semantics. Accepted answers move to `decisions.md` and `specification.md`. New questions are added here as they come up.

Last updated after D12bg. The question currently asked is marked **asking**.

## Priorities and scope

1. Other priorities beyond simplicity and performance (D02a–D02b): correctness, build time, distribution.
2. Release scope: what the first usable version must include.
3. Web-app host integration: how Tomato programs are hosted and called from a web app.
4. Detailed type inference: where types can be left out and what is inferred.

## Interfaces

5. ~~Overlapping method requirements~~ settled by D12bd.
6. ~~Interface inheritance cycles~~ settled by D12be (an error).
7. Duplicate declarations: what happens when the same relationship or interface is declared twice?
8. Exact import and export syntax for declarations (D12i).
9. Re-exports: can a module re-export something it imported?
10. Processing phase: when are interface requirements checked relative to other declarations?
11. ~~Inherited conformance~~ settled by D12bf (yes).
12. ~~Member compatibility~~ settled by D12bg (exact types, names need not match).
13. **asking** Interface-to-class conversion: can an interface-typed value be converted back to a class, and how does failure show?
14. Generic or container interface types (for example a list of an interface).
15. Other interface member kinds (fields, class functions, operators).

## Classes

16. Initialization values and defaults for fields: value syntax, evaluation order, whether any expression is allowed.
17. `@init` write checking: paths, branches, loops, reads before setting; const fields that also have a declared value.
18. Shared (class-level) field syntax.
19. Other modifiers and their placement; other visibility modifiers beyond `private`.
20. Nested or related classes.
21. `@init` details: receiver spelling, signature, return value, argument defaults or overloading, instance versus factory, allocation.
22. Construction call syntax (`Counter()` is illustrative only).
23. Parent `@init` call: errors, and calls through longer parent chains.
24. Calling a method the parent itself inherited, and whether any instance method may be called through a parent class.
25. Class functions: inherited or replaced by subclasses, how a call through a subclass name resolves, whether `@init` can be one.
26. `override`: whether it is reserved everywhere, whether it combines with `@add` or `@init`, and whether parameter names take part in matching.
27. Method grammar: receiver, parameter and return syntax, how `self` is typed in an inherited method, parentheses and punctuation, method bodies.
28. Shadowing rules for locals; what counts as a statement; argument expression limits.
29. Containers of subclass instances (for example a list of a parent type).
30. Which parameter types a parent-to-subclass conversion rejects, and the failure error's form.
31. Conversions between unrelated classes.
32. Default mutability of fields; inheritance of field rules.
33. Class-qualified call rules for longer parent chains.

## Operators (`@add`)

34. Operand and result types, mixed-type selection, and right-side fallback.
35. Mutation, dispatch and inheritance for operator methods.
36. Other operator markers beyond `@add`.
37. Receiver source spelling and declaration grammar.

## Numbers

38. Detailed width-expression rules; representation; overflow error handling.
39. Contextual typing beyond the literal-only arithmetic rules (D05s–w).
40. Remaining arithmetic rules; division (D05y); an integer-quotient operator; `%` on floats and rationals and compile-time zero divisors.
41. Resource-exhaustion behavior and constant-evaluation limits.
42. Rationals: physical storage, printed syntax, other construction and conversion forms, remaining operators beyond exact `+` (D05at), error representation and handling, optional alternative rational types.
43. Mixed operands between integers and rationals, and literal context.
44. Imports and availability of the rational type; named arguments and defaults; general call grammar.

## Errors

45. Error wording for every rule above. Decide once whether wording is specified in the language definition or left to implementations.

## Syntax the (retired) Python prototype needed (see `docs/provisional.md`)

46. Function and class header syntax, `if` and `while` forms, scoping, and local declaration. (`for name in x:` is settled by D18a.)
46a. ~~The iteration protocol~~ is settled by D48a (`@iter` and `yield`); `range` is a class in `std/builtin.tom`. Open: iterators as values (a generator you store or pass), `yield` inside `try`, recursive generators, and a run-time choice of a subclass's `@iter`.
46b. `range` forms and bounds, the loop variable's scope and type, `break` and `continue`, and loops over collections.
47. Boolean operators, truthiness, comparison rules between types, and the `%` result type for fixed-width integers (P9; the sign rule is settled by D05au).
48. String operations and syntax (D17c settles character units), whether a character means code point or grapheme, escapes, multi-line literals, float literals, `print` and other standard-library I/O.
49. How the final compiler should treat the prototype's partly-static checks (P19).

## Entry points (D16a)

50. Entry-point arguments come from the command line (D28a). Open: web-request arguments, returning a value or exit status, collection-valued inputs, standard input.
51. Can two functions carry the same marker? Can one function have several?
52. What happens to a program with no `@main`, such as a library?
53. ~~Choosing a non-default entry~~: `tomato run FILE ENTRY INPUTS...` (D28a). Open: how the compiled program chooses one.
54. Module-level constants and variables: they are code, so are they allowed, and when do they run?

## What a full programming language still needs (added 2026-11-21)

Davis asked to grow the prototype toward a real, full language. These are not designed yet. Asked in roughly this order, one at a time.

55. ~~Lists~~ settled by D20a. Still open: empty literal typing, negative indexes, slicing, removal and insertion, equality, printing.
56. ~~Dicts and sets~~ exist (D20b; the dict is called `dict`, D20c). Open: syntax, key rules, ordering, iteration while changing, operations, equality.
57. Tuples or multiple return values.
58. Generics: how `list[int]` and user-written generic classes and functions work (D04b leaves generics open).
59. ~~Missing values~~: `None` exists (D23a) and an optional is `T | None` (D23b). Open: general unions, narrowing, and operators on optionals.
60. ~~Errors~~ exist with try/catch/finally/else (D22a). Open: how to raise, what an error is, which failures are catchable, rethrow, and the final error class tree.
61. ~~Modules~~: import and export exist (D24a). Open: `import module` form, defaults, namespaces and name clashes, re-exports (items 8-9), search paths.
62. ~~A standard library~~ exists (D24a). Open: its contents, its names, and where `range` lives (D18a).
63. Input and output: `open` exists (D26a). Open: reading input, command line, environment, line-by-line reading, file modes.
64. Web servers: how a Tomato program listens, routes and answers requests (R09); and concurrency, which web servers need.
65. Functions as values: lambdas, closures, passing functions. Function values, named functions and non-capturing lambdas are decided (D63a). Open: closures (capturing variables), bound methods as values, generic functions as values, optional function values, comparing functions.
66. ~~Other data kinds~~: classes model data (D21a). Open: enums and variants later if wanted, type aliases.
67. String formatting and interpolation; multi-line string literals.
68. ~~`break`, `continue`~~ exist (D25a). Open: `match`/`switch`, the `if` expression form, loop `else`.
69. Constants and module-level values (item 54).
70. Testing and tooling: a test syntax, a formatter, and how `tomato` is run and built.
71. Foreign calls: `!x` refers to an LLVM function (D27a). Open: how its types are declared, call form, dotted names, and how Tomato calls C or the browser (R10).

## Compiling (added 2026-11-21)

72. ~~First compile target~~: the compiler emits LLVM IR (D30a). Open: LLVM version, linking and running per target, the runtime.
73. Reference counting (D29a): weak references exist and debug mode reports leaks (D29c), plus best-effort compile-time cycle detection (D29b). Open: weak-reference syntax, the leak check's details, warning versus error, atomic counts for threads, release timing, cleanup actions.
74. ~~Plain `int` in compiled code~~: it chooses its own size, staying unlimited (D32a, reading to confirm). Open: the analysis, spilling to big numbers, guarantees.
75. The static type checker (D33a: types are checked at compile time). Open: inference rules, `None` and optional types, generics, monomorphization.
76. Errors in compiled code: unwinding or result codes (D22a).
77. Memory layout (a first slice is built: heap objects with a {count, type code} header, D36a): a value is a 64-bit type code plus 64-bit data (D35a, reading to confirm). Open: code assignments, inline types, reference-count placement, strings (chunked, D17c), lists, dicts, sets and objects.
78. Modules have separate namespaces (D24c). Open: qualified names and aliases, the plain `import module` form (D24b) and the end of Davis's sentence, re-exports, and a build layout.
79. Concurrency: async only for now, tentatively (D31b); the threading library (D31a) is deferred. Open: how async is written, interaction with reference counting, web-server model.
80. ~~Types of `!x` LLVM functions~~: declared with `!name(a: T) -> R` (D27b, my design). Open: pointers, aggregates, where the IR comes from.
81. ~~The self-hosting plan~~: done. The compiler written in Tomato compiles itself; the Python prototype that ran it first was retired in v0.6 (D46a).
82. ~~Whether `tomato compile` should keep the Python-bundle mode~~: moot, the Python implementation and `bundle` are gone (D46a).

83. Error modes (D34a, settled in outline): the code format, how a mode is selected, location details, and what release mode prints, if anything.

84. Weak references: not language syntax; the runtime frees cycles automatically (D29d, reading to confirm), and a weak reference may exist in the standard library (D29e). Open: that library type's design and runtime support, when the collector runs, its cost, and its use with threads.

85. Checking before running (D40a, reading to confirm): the prototype's check pass is partial (P54). Open: narrowing after `x in Type` or a `None` check, types of collection literals and methods in the pass, and whether the interpreter should also stop on code it cannot type.

86. Floats and the new operators (D41a, reading to confirm): float literal grammar (`1.` and `.5` are not literals), mixing `rational` with `float`, typing fixed-width results of `//` and `**` from literals, and the compiler written in Tomato, which has decimal float literals, `//`, `**` and mixed arithmetic since v0.17 but not exponent notation, `float(x)` or the infinite/NaN stop.

## Out of scope

Merging or pushing this task, until Davis says so. Superseded: the LLVM compiler, self-hosting, the website and releases were all later authorized by Davis; the Python prototype was retired (D46a).
