# Known gaps

Each program is a rule the decisions settle but the compiler written in Tomato does not meet yet. `tests/run.sh` passes
while the gap exists and fails when it closes; then move the program to `tests/negative` (must be rejected) or
`tests/programs` (must work, with its expected output in `tests/expected`).

- `should_reject_*`: the compiler accepts the program; the decisions say compilation must fail (D05ac, D05ag, D05ap, D40a).
- `should_work_*`: the compiler rejects or mis-runs the program; the decisions say it works.

A `NAME.expected` file next to a `should_work_*` program holds the output the decisions call for (a regression oracle for
when the feature is rebuilt; `tests/run.sh` does not compare it while the gap stands).

The ~670 Python unit tests (rational, float and mixed arithmetic, `//`, `**`, unions, `x in Type`, tuples, `*args`/`**kwargs`,
unbounded `int`, the static check pass and more) are in git at the tag `v0.5`: `git show v0.5:tests/test_more.py`.

Cases the deleted Python test suite covered that are not yet expressible here, kept for when the features return
(they remain in git history under `tests/`): constant overflow of fixed-width arithmetic in dead branches and in
nested expressions (D05v-x), `rational` construction and reduction rules (D05am-ar), float rounding, signs of zero and
overflow of `/` (D05ad-aj), integer conversions between widths (D05o-r), union entry-point inputs (D28b), intersection
types (D23h), `x in Type` for classes, interfaces and plain int (D23f), tuple immutability and keyword-argument errors
(D39a), module-private names and import cycles (D24), `@init` flow analysis (D12x), and the compile-time cycle notice.
