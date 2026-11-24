# Known gaps

Each program is a rule the decisions settle but the compiler written in Tomato does not meet yet. `tests/run.sh` passes
while the gap exists and fails when it closes; then move the program to `tests/negative` (must be rejected) or
`tests/programs` (must work, with its expected output in `tests/expected`).

- `should_reject_*`: the compiler accepts the program; the decisions say compilation must fail (D05ac, D05ag, D05ap, D40a).
- `should_work_*`: the compiler rejects or mis-runs the program; the decisions say it works.

Today's programs:

| Program | Rule | What happens now |
| --- | --- | --- |
| `should_reject_dead_conversion_overflow` | D05x, D40a | `uint[length=8](300)` in a dead branch is accepted |
| `should_reject_dead_division_overflow` | D05ag, D40a | `10 ** 400 / 1` in a dead branch is accepted |
| `should_reject_dead_rational_zero` | D05ap, D40a | `rational(1, 0)` in a dead branch is accepted |
| `should_reject_init_unset_field` | D12x | a field `@init` sets on only some paths is accepted |
| `should_work_union_entry_input` | D28b | E157: entry inputs must be `int`, `bool` or `str` |
| `should_work_optional_int` | D23g | `int \| None` gives E318 |
| `should_work_interface_intersection` | D23h | `Named & Sized` as a parameter type gives E313 |
| `should_work_int_keyed_dict` | D20b | `dict[int, str]` gives E318 |
| `should_work_compact_list_declared` | P86 | `list[int[length=8]]` gives E318 |

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
