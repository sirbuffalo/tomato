# tier: full
# `tomato test` with no word over a tests/ folder of every kind of file: passes, a failed assert, @test functions, a file that exits with a
# status, a skip, a compile error, a helper (a name starting with _), a main with inputs. One line per file, the summary line, the status.
# (links a program per file; test_forms.sh has the forms of the words)
. "$CONTRACT_DIR/lib.sh"

mkdir -p tests
printf '@main\ndef main():\n    pass\n' > tests/a_ok.tom
printf '@main\ndef main():\n    assert 1 == 2\n' > tests/b_bad.tom
printf '@test.one\ndef one():\n    assert True\n@test.two\ndef two():\n    assert 1 + 1 == 2\n' > tests/c_fn.tom
printf 'import sys\n\n@main\ndef main():\n    sys.exit(3)\n' > tests/d_exit3.tom
printf 'from testing import skip\n\n@main\ndef main():\n    skip("not today")\n' > tests/e_skip.tom
printf '@main\ndef main():\n    print(zz)\n' > tests/f_compile.tom
printf 'def helper():\n    pass\n' > tests/_helper.tom
printf '@main\ndef main(a: str = "d"):\n    print("got", a)\n' > tests/g_inp.tom
printf '@test.p1\ndef p():\n    pass\n@test.f1\ndef f():\n    assert False\n' > tests/h_mixed.tom
printf '@main\ndef main(n: int):\n    pass\n' > tests/i_needs_input.tom
try "test: every tests/*.tom, in name order, a helper left out; the status is 1 when any failed" 1 @test_all.txt "" test
try "test --filter keeps the files whose name contains the text" 0 "ok   tests/a_ok.tom
tomato test: 1 files, 1 passed, 0 failed, 0 skipped: ok" "" test --filter a_ok
try "test: a pass prints nothing of the program's output, a failure prints its error text" 1 "~    error[E519]: AssertionError: assertion failed (raised at tests/b_bad.tom line 3)" "" test tests/b_bad.tom
