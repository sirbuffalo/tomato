# Testing in Tomato: `tomato test` and the `testing` module

The sheet for 1.0 (D81a built the first version, D92a gave the markers their dotted names, D97a made files the unit of a test and added the rest). The code is `std/testing.tom` (the assertions and the runner for `@test` functions, pure Tomato, so it also runs in the playground) and the `test` command in `native/tomato`.

## The way to write tests: one file, one test

A test is a file in a `tests/` folder. It is an ordinary program, a function marked `@main`, and it uses `assert` and the checks of `testing`:

```
# tests/parse_numbers.tom
from testing import assert_equal, assert_raises
import numbers_lib

def bad():
    _x = numbers_lib.parse('x')

@main
def main():
    assert_equal(numbers_lib.parse('42'), 42)
    assert_equal(numbers_lib.parse_all(['1', '2']), [1, 2])
    assert_raises(bad, 'ValueError')
```

(`numbers_lib` is `src/numbers_lib.tom`, whose functions are marked `export def`.) `tomato test` runs every `tests/*.tom`, each as a process of its own:

- the file **passes** when it ends with status 0, which means that nothing was raised (a failed `assert`, a failed check, any uncaught error) and nothing called `sys.exit` with another status;
- it **fails** otherwise: an error, an exit status that is not 0, a crash, a stack overflow, a hang past the time limit, a file that does not compile or has no `@main`;
- it is **skipped** when it ends by calling `skip('reason')` (nothing catches it).

Because each file is its own process, a `sys.exit`, a crash or a hang in one test ends that test only; the others still run and are reported. Set-up and clean-up are code in the file: statements at the start of `main`, `try`/`finally` around what must be undone, helper functions for what several tests need. A module that several test files import goes in `tests/` too, with a name that starts with `_` (`tests/_helpers.tom`): `tomato test` does not run it (a file you name yourself is always run).

## The command

```
tomato test [OPTIONS]                              every tests/*.tom
tomato test [OPTIONS] FILE...                      these files
tomato test [OPTIONS] FILE ENTRY [INPUTS...]       one file, an entry of it, and the inputs of that entry's function
```

**Options go first.** `tomato test` reads its options (below, and `--color`, `--no-warnings`) only **before the first file**; the first word that is not an option ends them, and everything after the file or its entry is read as it is, even a word that starts with `--`: `tomato test a.tom check --filter` runs `check` with the input `--filter`. An option after a file (`tomato test a.tom --filter x`) is an error that says so (it could only be an input, which needs an entry first). `--` ends the options earlier, and the next word is the first file. This is the rule of `tomato run FILE ENTRY INPUTS...` and of a built program (D94b item 6).

How the words are read: a word that ends in `.tom` or contains a `/` is a file (a folder stands for its `*.tom` files, except those whose name starts with `_`). A word that is not a file is accepted only **right after a file**, as its `ENTRY`; every word after the entry is an input, as in `tomato run FILE ENTRY INPUTS...` (the same compile and the same way of passing the words). A bare word anywhere else is an error that suggests the file: `tomato test parse` says `write tomato test parse.tom (or tests/parse.tom)`; nothing is looked up in `tests/` by name.

| Form | Runs |
| --- | --- |
| `tomato test` | every `tests/*.tom` (not those that start with `_`); no `tests/` folder, or none with a test, is an error |
| `tomato test a.tom b.tom` | `a.tom`, then `b.tom` |
| `tomato test tests/parser` | the test files in that folder |
| `tomato test a.tom check 4 hi` | the entry `check` of `a.tom` (a function marked `@check`) with the inputs `4` and `hi` |
| `tomato test a.tom main` | the entry `main` of `a.tom` |
| `tomato test a.tom test` | the functions marked `@test` or `@test.*` in `a.tom` (below) |
| `tomato test a.tom test.parse` | only the functions marked `@test.parse` and `@test.parse.*` |

With no `ENTRY` the file runs as a whole: its `@test` functions through the driver if it has any (even beside a `@main`, which stays for `tomato run`), else its `@main`. **No inputs can be given then, so a test's `main` may take inputs only if every one has a default** (`def main(n: int = 3)`); a `main` with an input that has none fails with the runtime's message (`main takes 1 input (n), but got 0` and its usage line), and `tomato test` with no word can then not run that file. Inputs are for the entry form, to run one file with chosen values.

| Option | Meaning |
| --- | --- |
| `--filter TEXT` | only the files whose name contains `TEXT` (a filter that keeps no file is an error, `error: no test file name contains 'TEXT'`, with status 1: a typo must not pass) |
| `--timeout N` | stop a file that has run for more than `N` seconds (a whole number; the compile is not counted) and fail it |
| `-v`, `--verbose` | also show what the files that pass printed |
| `--mode debug\|release` | as for `tomato run` |

**Output.** One line for each file, then one line for CI:

```
ok   tests/parse_numbers.tom
FAIL tests/render.tom  (exit status 1)
    error[E519]: AssertionError: lists differ at [1]: expected 3, got 2
      expected: [1, 3]
      actual:   [1, 2] (raised at tests/render.tom line 5)
      at testing._fail (line 307)
      at testing.assert_equal (line 376)
      at main (tests/render.tom line 5)
skip tests/network.tom  (no network)
FAIL tests/slow.tom  (timed out after 10 seconds)
tomato test: 4 files, 1 passed, 2 failed, 1 skipped: FAILED
```

A failed file shows what it printed (its output and its error, with the trace in debug mode) under its line, indented; a file that passes shows nothing but its line unless `-v` is given. A trace line names no file of its own, so `tomato test` marks them: a function of `std/testing.tom` (a check raises inside it) is written `testing.NAME`, and the first function of the test file in the trace is given the file, as in `at main (tests/render.tom line 5)`; the same file and line replace the `(raised on line 306)` of the first line, which is a line of `testing.tom`, so the report starts at the assertion. In `--mode release` there is no trace and the error is only `error E519:307`, so a note says that the number is not the test's line and to run the file in debug mode. A long output is cut: the first 40 lines and the last 60 are shown, with `... N lines left out ...` between them (the end is where the error is). A file that does not compile shows the compiler's message. The last line ends with `: ok` or `: FAILED`; a CI job is `tomato test`, and nothing else. In release mode there is no trace: the failure is the one line `error[Exx]: Class: message (line N)` (N is in the program or in `std/testing.tom`), and `tomato test` adds a note saying so and naming the debug-mode command that shows the line of the check.

**Exit status.** 0 when every file passed or was skipped, 1 when any failed or the command line could not be used (an unreadable file, an unknown option, a bare word), 2 for the usage message (an option with no value).

## Several tests in one file: `@test` functions

A file that has plain functions (no parameters, no result, not `async`) marked `@test` (or `@test.NAME`, D92a) is run through a driver instead of as a program (even if it also has a `@main`, which stays for `tomato run`; the table `[build.test]` and the seeds of `[test-seeds]` apply to it, as the entry is `test`): the entry `test` runs every one of them, in the order written, in one process, and `test.parse` runs those marked `@test.parse` or below it. The file counts as one test and passes when all of them do:

```
from testing import assert_equal, skip

@test.adds
def adds():
    assert_equal(1 + 1, 2)

@test.lookup
def lookup():
    skip('no network')
```

```
ok   tests/arith.tom  (1 passed, 1 skipped)
```

A file whose functions were all skipped is itself skipped (`skip tests/arith.tom  (all 2 skipped)`), not passed: it tested nothing. A function passes when it returns, fails when it raises any `Error`, and is skipped by `skip`. On a failure the file's line is `FAIL tests/arith.tom  (1 of 2 tests failed)` followed by one `ok NAME`, `skip NAME  (reason)` or `FAIL NAME` line for each function, with the message and `(raised at FILE:N)`, the line of the function that failed (of the call, if a helper raised); an error that is not a failed check shows its class first (`KeyError: k`). The functions share the process: a `sys.exit` inside one ends the file at that function (`the program ended in NAME with status 0`), and the rest are not run. With `tomato test FILE test` the entry is given by hand; `tomato run FILE test` prints the same lines. The file-per-test form above is the main way. To run part of such a file use the entry form (`tomato test FILE test.NAME`); `tomato run FILE test --filter TEXT` filters by function name.

## Assertions

Each raises `AssertionError` (E519) with the text below; a `message` argument is added to the **first** line as `text: message`. The statement `assert condition, 'message'` is always on and fails a test in the same way.

| Call | Fails with |
| --- | --- |
| `fail(message='')` | the message (`test failed`) |
| `assert_true(v)`, `assert_false(v)` | `expected True` / `expected False` |
| `assert_equal(actual, expected)` | `expected X, got Y`; for long text, text with a space at either end, lists and dicts a diff (below) |
| `assert_not_equal(actual, expected)` | `values are equal: X` |
| `assert_less`, `assert_less_equal`, `assert_greater`, `assert_greater_equal` `(actual, limit)` | `expected 5 to be less than 3`, `... to be at most ...`, `... greater than ...`, `... at least ...` |
| `assert_in(item, items)`, `assert_not_in` | `'a' is not in ['b', 'c']` / `'a' is in [...]` |
| `assert_none[T](v)`, `assert_not_none[T](v)` | `expected None, got X` / `expected a value, got None` (write the type: `assert_none[str](name)`) |
| `assert_close(actual, expected, rel_tol=1e-9, abs_tol=0.0)` | `expected X, got Y` (Python's `math.isclose` rule) |
| `assert_raises(f, 'ValueError')` | returns the error `f()` raised; fails if nothing was raised or an error of another class was (`'Error'` matches any); the message names the class it got (`expected KeyError, but ValueError was raised: bad`), and says so when the name is not a class of the standard library |
| `assert_raises_with(f, arg, 'ValueError')` | the same for a function of one argument |
| `skip(reason)` | ends the test as skipped |

`assert_equal` and `assert_not_equal` take any type with `==` (a class needs `@eq`), and two dicts through a second overload of the same name (two dicts are equal when they have the same keys and equal values, in any order; the values need `==`). Sets and tuples have no `==` in the language, so they cannot be compared directly: compare `sorted(list(s))` or the items. `assert_less` and the others take numbers and text, or a class with `@lt` and `@gt`. A value that may be `None` can be compared (`assert_equal(find(x), 'tom')` is `expected tom, got None` when `find` gives `None`, not an error). The callbacks of `assert_raises` are named functions that cannot see the test's variables (D63a): put the call in a small function, or pass the argument with `assert_raises_with`.

### What a failed `assert_equal` shows

The text and where it differs, from the first line on. The values are written as `str()` writes them, so a text is not in quotes at the top; inside a list or dict, items are written the way a list shows them (`'a'`).

```
# a short text, a number or an object: one line
     expected 3, got 2

# a text of more than 12 characters, or with a newline: both, with the first difference marked (the position counts the
# characters as written, so a newline is two)
     values differ at character 8
       expected: 'hello wurld and more'
       actual:   'hello world and more'
                         ^

# a list: its first differing item, going down into nested lists and dicts
     lists differ at [1][2]: expected 5, got 4
       expected: [[1, 2, 3], [3, 4, 5]]
       actual:   [[1, 2, 3], [3, 4, 4]]
# (a list of another length: `lists differ: expected 3 items, got 4 (the first extra item is [3]: 9)`)

# a dict: every key that is missing, unexpected or has another value (up to 6)
     dicts differ: key 'port' is missing (expected 80)
       expected: {'host': 1, 'port': 80}
       actual:   {'host': 1, 'debug': 1}
       and key 'debug' is unexpected (got 1)
```

The whole values are left out when one is more than 60 characters (the lines about the first difference are still there), and any item or value in a line is cut at 60 characters with `...`.

## What is left out, on purpose

- **No async tests** (E520 for a function marked `@test`): an `async def` is not a function value (D63a). **No parameterized tests, fixtures or mocks**: a loop inside one test, and helper functions. **No `@setup`/`@teardown`**: set-up and clean-up are code in the file.
- **No selector option**: one function (or a group) of a file with `@test.NAME` markers is the entry form `tomato test FILE test.NAME`, the same selection as `tomato run FILE test.NAME` (D96a).
- **The layout, `tomato init` and `[test-seeds]`** are D94b (`docs/manifest.md`): `tomato init` writes `tests/example.tom`, a test in `tests/` imports the modules of `src/` by name, and `tomato test` builds each file with the option `--test-seeds`, so the seeds of `[test-seeds]` (and `[seeds]`) are found; a seed's own `[test-seeds]` is read only by `tomato test` in that seed. `tomato test` still reads the current folder's `tests/` only (not a project folder above it).
- **No parallel runs and no report formats** (JUnit, TAP). The files' lines and the last line are the interface.

## The playground

`assert`, the `testing` module and the driver run in the browser (the entry name `test`); `tomato test`, discovery, process isolation and `--timeout` are the native command only.
