# tier: full
# What `tomato test` shows for a failed file: the file and line of the check (debug) or a note (release), the text diffs, the class of an
# error in an @test function, what assert_raises says, a long output cut, a file whose tests were all skipped, and what a missing
# entry or a misplaced `export` says. (links a program per file; test_forms.sh and test_all.sh have the forms and the folder)
. "$CONTRACT_DIR/lib.sh"

mkdir -p tests
printf 'from testing import assert_equal\n\ndef check(xs: list[int]):\n    assert_equal(xs, [1, 3])\n\n@main\ndef main():\n    check([1, 2])\n' > tests/helper.tom
printf 'from testing import assert_equal\n\n@test.spaces\ndef spaces():\n    assert_equal("a ", "a")\n' > tests/spaces.tom
printf 'from testing import assert_raises\n\ndef bad():\n    raise ValueError("bad")\n\n@test.wrong\ndef wrong():\n    assert_raises(bad, "KeyError")\n\n@test.bogus\ndef bogus():\n    assert_raises(bad, "Bogus")\n\n@test.uncaught\ndef uncaught():\n    raise KeyError("k")\n' > tests/errors.tom
printf 'from testing import skip\n\n@test.one\ndef one():\n    skip("no network")\n\n@test.two\ndef two():\n    skip("later")\n' > tests/allskip.tom
printf '@main\ndef main():\n    for i in range(500):\n        print("line", i)\n    assert False, "after the lines"\n' > tests/long.tom
printf '@check\ndef check():\n    pass\n\n@test.a\ndef a():\n    pass\n' > entries.tom
printf '@test.x\nexport def x():\n    pass\n' > misplaced.tom

# (the lines of std/testing.tom in the trace are not pinned here: only the lines that name the test)
try "test: a failed check: the first message names the file and the line of the test's own call" 1 "~      actual:   [1, 2] (raised at tests/helper.tom line 4)" "" test tests/helper.tom
try "test: a failed check: the frames of the framework are testing.NAME, the test's own frame has its file" 1 "~      at check (tests/helper.tom line 4)" "" test tests/helper.tom
try "test: a failed check: the caller's line stays a plain line" 1 "~      at main (line 8)" "" test tests/helper.tom
try "test --mode release: a failed check says that there is no trace" 1 "~    (release mode keeps no call trace, and this line is in the program or in std/testing.tom; run it in debug mode, tomato test --mode debug tests/helper.tom, to see the line of the check)" "" test --mode release tests/helper.tom
try "test: @test functions: the test's file and line, short text that differs only in a space, an error told by its class, assert_raises naming the class" 1 "FAIL tests/spaces.tom  (1 of 1 tests failed)
    FAIL spaces
         values differ at character 2 (expected 1 character, got 2)  (raised at tests/spaces.tom:5)
           expected: 'a'
           actual:   'a '
                       ^
    0 passed, 1 failed, 0 skipped
FAIL tests/errors.tom  (3 of 3 tests failed)
    FAIL wrong
         expected KeyError, but ValueError was raised: bad  (raised at tests/errors.tom:8)
    FAIL bogus
         expected Bogus, but ValueError was raised: bad  (raised at tests/errors.tom:12)
           (is 'Bogus' the name of an error class? it is not one of the standard ones; a class of your own is matched by its name)
    FAIL uncaught
         KeyError: k  (raised at tests/errors.tom:16)
    0 passed, 3 failed, 0 skipped
tomato test: 2 files, 0 passed, 2 failed, 0 skipped: FAILED" "" test tests/spaces.tom tests/errors.tom
try "test: a file whose tests were all skipped is skipped, not passed" 0 "skip tests/allskip.tom  (all 2 skipped)
tomato test: 1 files, 0 passed, 0 failed, 1 skipped: ok" "" test tests/allskip.tom
try "test: a long output keeps its first lines and says how many were left out" 1 "~    ... 402 lines left out ..." "" test tests/long.tom
try "test: a long output keeps its last lines, with the error" 1 "~    error[E519]: AssertionError: after the lines (raised at tests/long.tom line 5)" "" test tests/long.tom
try "run: an entry that no function is marked with lists the entries" 1 "" "error[E228]: no function is marked @nope
  = help: write @nope on the line above the function that should start the program; the entries of this program are: check, test.a, test" run entries.tom nope
try "test FILE ENTRY: the same list" 1 "FAIL entries.tom  (did not compile)
    error[E228]: no function is marked @test.nope
      = help: write @test.nope on the line above the function that should start the program; the entries of this program are: check, test.a, test
tomato test: 1 files, 0 passed, 1 failed, 0 skipped: FAILED" "" test entries.tom test.nope
try "run: @test.x before export def says that export goes first" 1 "" "~error[E335]: expected a function after @test.x (write export before the marker: export @test.x), but found the word 'export'" run misplaced.tom
