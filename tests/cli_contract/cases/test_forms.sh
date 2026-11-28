# tier: full
# `tomato test` and its words: FILE..., a folder, FILE ENTRY INPUTS... (as in tomato run), @test functions and the entry test, -v, --filter,
# --timeout, --mode, and the summary and status. (links a program per file; test_all.sh runs a whole folder)
. "$CONTRACT_DIR/lib.sh"

mkdir -p tests
printf '@main\ndef main():\n    pass\n' > tests/ok.tom
printf '@test.one\ndef one():\n    assert True\n\n@test.two\ndef two():\n    assert 1 + 1 == 2\n' > tests/fn.tom
printf '@main\ndef main(a: str = "d"):\n    print("got", a)\n' > tests/inp.tom
printf '@test.p1\ndef p():\n    pass\n@test.f1\ndef f():\n    assert False\n' > tests/mixed.tom
printf '@main\ndef main():\n    while True:\n        pass\n' > tests/hang.tom
printf '@test.slow_one\ndef slow_one():\n    pass\n' > tests/withmain.tom; printf '\n@main\ndef main():\n    print("main ran")\n' >> tests/withmain.tom

try "test FILE: one line and the summary" 0 "ok   tests/ok.tom
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test tests/ok.tom
try "test FILE FILE: in the order given; a file with @test functions says how many passed" 0 "ok   tests/fn.tom  (2 passed)
ok   tests/ok.tom
tomato test: 2 files, 2 passed, 0 failed, 0 skipped: ok" "" test tests/fn.tom tests/ok.tom
mkdir -p fold; cp tests/ok.tom tests/fn.tom tests/inp.tom fold/; printf 'def h():\n    pass\n' > fold/_helper.tom
try "test a folder: its *.tom files, in name order, a name starting with _ left out" 0 "ok   fold/fn.tom  (2 passed)
ok   fold/inp.tom
ok   fold/ok.tom
tomato test: 3 files, 3 passed, 0 failed, 0 skipped: ok" "" test fold
try "test a folder with a trailing slash is the same" 0 "ok   fold/fn.tom  (2 passed)
ok   fold/inp.tom
ok   fold/ok.tom
tomato test: 3 files, 3 passed, 0 failed, 0 skipped: ok" "" test fold/
try "test FILE ENTRY INPUTS: the entry and its inputs, as for tomato run (-v shows what the program printed)" 0 "ok   tests/inp.tom
    got hello
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test -v tests/inp.tom main hello
try "test FILE test.NAME: one @test function" 0 "ok   tests/fn.tom  (1 passed)
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test tests/fn.tom test.one
try "test FILE test: the entry test runs them all" 0 "ok   tests/fn.tom  (2 passed)
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test tests/fn.tom test
try "test FILE test INPUT: the entry test takes no inputs" 1 "FAIL tests/fn.tom  (the entry test (the functions marked @test) takes no inputs)
tomato test: 1 file, 0 passed, 1 failed, 0 skipped: FAILED" "" test tests/fn.tom test x
try "test: a failure in a file with @test functions lists each test (the function's name) and says how many failed" 1 "FAIL tests/mixed.tom  (1 of 2 tests failed)
    ok   p
    FAIL f
         assertion failed  (raised at tests/mixed.tom:6)
    1 passed, 1 failed, 0 skipped
tomato test: 1 file, 0 passed, 1 failed, 0 skipped: FAILED" "" test tests/mixed.tom
try "test --mode release: the same files, the error text without the line" 1 "FAIL tests/mixed.tom  (1 of 2 tests failed)
    ok   p
    FAIL f
         assertion failed
    1 passed, 1 failed, 0 skipped
tomato test: 1 file, 0 passed, 1 failed, 0 skipped: FAILED" "" test --mode release tests/mixed.tom
try "test: a file with @test functions and a @main runs the functions" 0 "ok   tests/withmain.tom  (1 passed)
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test tests/withmain.tom
try "test --timeout stops a file that runs too long, and says so" 1 "FAIL tests/hang.tom  (timed out after 1 seconds)
tomato test: 1 file, 0 passed, 1 failed, 0 skipped: FAILED" "" test --timeout 1 tests/hang.tom
# the options are read only before the first file: after a file or its entry a word that starts with - is an input of the entry
try "test FILE ENTRY -v: after the entry -v is an input, not the option" 0 "ok   tests/inp.tom
tomato test: 1 file, 1 passed, 0 failed, 0 skipped: ok" "" test tests/inp.tom main -v
try "test: --filter after a file is refused" 1 "" "~comes after a file, so it is not an option" test tests/ok.tom --filter ok
