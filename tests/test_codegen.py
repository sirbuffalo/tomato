"""Tests for the LLVM compiler (D30a): compile, link with clang, run natively, and compare with the interpreter."""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from tomato import errcodes  # noqa: E402
from tomato.codegen import compile_to_ir  # noqa: E402
from tomato.errors import NotDecided, TomatoError  # noqa: E402
from tomato.interp import run_source  # noqa: E402

CLANG = shutil.which("clang")
RUNTIME = os.path.join(os.path.dirname(__file__), "..", "tomato", "runtime", "tomato_rt.c")
ROOT = os.path.join(os.path.dirname(__file__), "..")


def native(src, args=(), mode="debug", entry="main"):
    """Compile `src`, link it, run it; returns (exit code, stdout, stderr)."""
    ir = compile_to_ir(src, entry=entry, mode=mode)
    with tempfile.TemporaryDirectory() as d:
        ll, exe = os.path.join(d, "p.ll"), os.path.join(d, "p")
        with open(ll, "w") as f:
            f.write(ir)
        r = subprocess.run([CLANG, "-O1", "-Wno-override-module", "-x", "ir", ll, "-x", "c", RUNTIME, "-lm", "-o", exe],
                           capture_output=True, text=True)
        if r.returncode:
            raise AssertionError("clang failed:\n" + r.stderr + "\n" + ir)
        r = subprocess.run([exe] + list(args), capture_output=True, text=True)
        return r.returncode, r.stdout, r.stderr


def interpreted(src, args=(), entry="main"):
    out = io.StringIO()
    run_source(src, out, entry=entry, inputs=list(args), warn_out=io.StringIO())
    return out.getvalue()


def interpreted_with_ir(src, ir):
    try:
        import llvmlite  # noqa: F401
    except ImportError:
        return None
    out = io.StringIO()
    run_source(src, out, llvm_ir=[("lib.ll", ir)], warn_out=io.StringIO())
    return out.getvalue()


def prog(body, params="", pre=""):
    return pre + "\n@main\ndef main(%s):\n" % params + "".join("    %s\n" % l for l in body.split("\n"))


needs_clang = unittest.skipUnless(CLANG, "clang is not installed")


@needs_clang
class SameAsTheInterpreter(unittest.TestCase):
    """Differential tests: the compiled program prints exactly what the interpreter prints."""

    def same(self, src, args=()):
        code, out, err = native(src, args)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, interpreted(src, args))

    def test_arithmetic_and_precedence(self):
        self.same(prog("print(2 + 3 * 4, (2 + 3) * 4, 0 - 7, 10 - 3 - 2, 100 * 100 * 100)"))

    def test_division_gives_float(self):
        self.same(prog("print(5 / 2, 6 / 3, 1 / 3, -5 / 2, 1 / 8)"))

    def test_division_by_negative_keeps_the_sign_of_zero(self):
        self.same(prog("print(0 / 5, 0 / (0 - 5))"))

    def test_modulo_follows_the_divisor_sign(self):
        self.same(prog("print(7 % 3, (0 - 7) % 3, 7 % (0 - 3), (0 - 7) % (0 - 3), 0 % 5, 5 % 5)"))

    def test_modulo_by_minus_one(self):
        self.same(prog("a: int[length=8] = -128\nprint(a % -1)"))

    def test_comparisons(self):
        self.same(prog("print(1 < 2, 2 < 1, 2 <= 2, 3 > 2, 3 >= 4, 5 == 5, 5 != 5, True == False, True != False)"))

    def test_logic_short_circuits(self):
        src = prog("print(False and boom(), True or boom(), True and not False, False or False)",
                   pre="def boom() -> bool:\n    print('boom')\n    return True")
        self.same(src)

    def test_if_elif_else(self):
        src = prog("for i in range(5):\n    if i < 1:\n        print('zero')\n    elif i < 3:\n        print('small')\n"
                   "    else:\n        print('big')")
        self.same(src)

    def test_while_break_continue(self):
        src = prog("i = 0\ntotal = 0\nwhile True:\n    i = i + 1\n    if i % 2 == 0:\n        continue\n"
                   "    if i > 9:\n        break\n    total = total + i\nprint(total, i)")
        self.same(src)

    def test_for_range_forms(self):
        self.same(prog("for i in range(3):\n    print(i)\nfor i in range(2, 5):\n    print(i)\n"
                       "for i in range(10, 0, 0 - 4):\n    print(i)\nfor i in range(5, 1):\n    print(i)"))

    def test_nested_loops_and_break(self):
        self.same(prog("n = 0\nfor i in range(4):\n    for j in range(4):\n        if j == 2:\n            break\n"
                       "        n = n + 1\nprint(n)"))

    def test_recursion(self):
        src = prog("print(fib(20), fact(20))", pre="def fib(n: int) -> int:\n    if n < 2:\n        return n\n"
                   "    return fib(n - 1) + fib(n - 2)\ndef fact(n: int) -> int:\n    if n < 2:\n        return 1\n"
                   "    return n * fact(n - 1)")
        self.same(src)

    def test_primes_and_fibonacci_mod(self):
        src = prog("print(is_prime(97), is_prime(100), fib_mod(90, 1000000007))",
                   pre="def is_prime(n: int) -> bool:\n    if n < 2:\n        return False\n    d = 2\n"
                       "    while d * d <= n:\n        if n % d == 0:\n            return False\n        d = d + 1\n"
                       "    return True\ndef fib_mod(n: int, m: int) -> int:\n    a = 0\n    b = 1\n    for i in range(n):\n"
                       "        t = (a + b) % m\n        a = b\n        b = t\n    return a")
        self.same(src)

    def test_fixed_width_integers(self):
        self.same(prog("a: int[length=8] = 100\nb: int[length=8] = 27\nc: int[length=16] = a + b\nu: uint[length=8] = 250\n"
                       "print(a + b, c, u + 5, a - b, 0 - a)"))

    def test_common_type_widening(self):
        self.same(prog("a: int[length=8] = 100\nb: int[length=16] = 1000\nc: int[length=16] = a + b\nd: int[length=16] = a\nprint(c, d * 2, a - 100)"))

    def test_literals_take_the_expected_type(self):
        self.same(prog("a: uint[length=8] = 100 + 155\nb: int[length=7] = -64\nprint(a, b)"))

    def test_explicit_conversions(self):
        self.same(prog("x = 200\nprint(uint[length=8](x), int[length=16](x), int(uint[length=8](x)))"))

    def test_odd_widths(self):
        self.same(prog("a: int[length=7] = 63\nb: uint[length=19] = 524287\nc: int[length=1] = -1\nprint(a, b, c)"))

    def test_wide_unsigned(self):
        self.same(prog("a: uint[length=64] = 5\nb: uint[length=64] = 3\nprint(a - b, b * a, a % b)"))

    def test_strings_print(self):
        self.same(prog("print('hello', 'wörld \U0001F345', 1, True)\nprint()"))

    def test_print_of_floats(self):
        self.same(prog("print(1 / 3, 2 / 3, 1 / 8, 100 / 1, 1 / 1000000000000, 123456789 / 1000)"))

    def test_functions_with_every_supported_type(self):
        src = prog("print(f(3, True, 2 / 1, 'x'))", pre="def f(a: int, b: bool, c: float, d: str) -> float:\n    print(a, b, c, d)\n    return c")
        self.same(src)

    def test_no_return_value_function(self):
        self.same(prog("hello(3)", pre="def hello(n: int):\n    print('n is', n)"))

    def test_locals_inferred_and_reassigned(self):
        self.same(prog("x = 5\nx = x + 1\ny: int[length=16] = 7\ny = y + 1\nprint(x, y)"))

    def test_entry_inputs(self):
        src = prog("print(n, small, f, b, s)", "n: int, small: uint[length=8], f: float, b: bool, s: str")
        code, out, err = native(src, ["-4", "200", "2.5", "true", "hi there"])
        self.assertEqual((code, out), (0, "-4 200 2.5 True hi there\n"))
        self.assertEqual(out, interpreted(src, ["-4", "200", "2.5", "true", "hi there"]))

    def test_chosen_entry(self):
        src = "@main\ndef a():\n    print(1)\n@other\ndef b(n: int):\n    print(n * 2)\n"
        self.assertEqual(native(src, ["21"], entry="other")[:2], (0, "42\n"))

    def test_deep_recursion(self):
        src = prog("print(depth(100000))", pre="def depth(n: int) -> int:\n    if n == 0:\n        return 0\n    return 1 + depth(n - 1)")
        self.assertEqual(native(src)[:2], (0, "100000\n"))


@needs_clang
class RuntimeFailures(unittest.TestCase):
    def fails(self, src, text, args=(), mode="debug"):
        code, out, err = native(src, args, mode)
        self.assertEqual(code, 1, (out, err))
        self.assertIn(text, err)

    def test_overflow_of_the_64_bit_int(self):
        self.fails(prog("print(big(9223372036854775807))", pre="def big(n: int) -> int:\n    return n + 1"), "integer overflow")

    def test_fixed_width_overflow(self):
        self.fails(prog("a: int[length=8] = 127\nb: int[length=8] = a + 1"), "integer overflow")
        self.fails(prog("a: uint[length=8] = 0\nb: uint[length=8] = a - 1"), "integer overflow")
        self.fails(prog("a: int[length=8] = -128\nb: int[length=8] = 0 - a"), "integer overflow")

    def test_division_by_zero(self):
        self.fails(prog("print(1 / z)", "z: int"), "division by zero", ["0"])
        self.fails(prog("print(1 % z)", "z: int"), "modulo by zero", ["0"])

    def test_range_step_zero(self):
        self.fails(prog("for i in range(1, 5, z):\n    print(i)", "z: int"), "range step cannot be zero", ["0"])

    def test_conversion_out_of_range(self):
        self.fails(prog("x = 300\nprint(uint[length=8](x))"), "integer conversion out of range")
        self.fails(prog("x = 0 - 1\nprint(uint[length=8](x))"), "integer conversion out of range")

    def test_missing_return(self):
        src = prog("print(f(1))", pre="def f(n: int) -> int:\n    if n > 5:\n        return 1")
        self.fails(src, "ended without returning")

    def test_output_before_a_failure_is_kept(self):
        code, out, err = native(prog("print('before')\nprint(1 / z)", "z: int"), ["0"])
        self.assertEqual((code, out), (1, "before\n"))

    def test_bad_inputs(self):
        src = prog("print(n)", "n: int")
        self.fails(src, "input 1 must be a whole number", ["abc"])
        self.fails(src, "takes 1 input(s), got 0", [])
        self.fails(src, "takes 1 input(s), got 2", ["1", "2"])
        self.fails(prog("print(n)", "n: uint[length=8]"), "does not fit uint[length=8]", ["256"])
        self.fails(prog("print(n)", "n: int[length=8]"), "does not fit int[length=8]", ["-129"])
        self.fails(prog("print(b)", "b: bool"), "true or false", ["yes"])
        self.fails(prog("print(f)", "f: float"), "finite number", ["nan"])

    def test_error_line_numbers_are_reported(self):
        self.fails(prog("print(1)\nprint(2)\nprint(1 / z)", "z: int"), "line 6: division by zero", ["0"])


@needs_clang
class ErrorModes(unittest.TestCase):
    SRC = "def divide(a: int, b: int) -> float:\n    return a / b\n\n@main\ndef main(a: int, b: int):\n    print(divide(a, b))\n"

    def test_debug_prints_the_full_message(self):
        code, out, err = native(self.SRC, ["6", "0"], "debug")
        self.assertEqual((code, err), (1, "error: line 2: division by zero (D05ab)\n"))

    def test_normal_prints_a_code(self):
        code, out, err = native(self.SRC, ["6", "0"], "normal")
        self.assertEqual((code, err), (1, "error E02:2\n"))

    def test_release_prints_nothing(self):
        code, out, err = native(self.SRC, ["6", "0"], "release")
        self.assertEqual((code, out, err), (1, "", ""))

    def test_a_normal_code_decodes_to_the_debug_message(self):
        code, out, err = native(self.SRC, ["6", "0"], "normal")
        text = errcodes.explain(err.split()[1], self.SRC)
        self.assertIn("division by zero (D05ab)", text)
        self.assertIn("  --> line 2", text)
        self.assertIn("   2 |     return a / b", text)

    def test_all_modes_succeed_the_same_way(self):
        outs = {m: native(self.SRC, ["6", "3"], m)[:2] for m in ("debug", "normal", "release")}
        self.assertEqual(set(outs.values()), {(0, "2.0\n")})

    def test_bad_mode(self):
        with self.assertRaises(TomatoError):
            compile_to_ir(self.SRC, mode="loud")


class Explain(unittest.TestCase):
    SRC = "a\nb\n    c\n"

    def test_decoding(self):
        text = errcodes.explain("E01:3", self.SRC)
        self.assertIn("error E01:3: integer overflow", text)
        self.assertIn("   3 |     c", text)
        self.assertTrue(text.splitlines()[-1].endswith("    ^"))

    def test_every_kind_has_text(self):
        for code in errcodes.KINDS:
            self.assertIn("error E%02d:1" % code, errcodes.explain("E%02d:1" % code, self.SRC))

    def test_bad_codes(self):
        for bad in ("", "E1:1", "E99:1", "overflow", "E01", "E01:x"):
            with self.assertRaises(ValueError):
                errcodes.explain(bad, self.SRC)

    def test_line_not_in_the_file(self):
        with self.assertRaises(ValueError):
            errcodes.explain("E01:99", self.SRC)
        with self.assertRaises(ValueError):
            errcodes.explain("E01:0", self.SRC)


@needs_clang
class LlvmDeclarations(unittest.TestCase):
    IR = """
define i64 @add(i64 %a, i64 %b) {
  %r = add i64 %a, %b
  ret i64 %r
}
define double @half(double %x) {
  %r = fdiv double %x, 2.0
  ret double %r
}
define i1 @is_even(i32 %n) {
  %r = and i32 %n, 1
  %z = icmp eq i32 %r, 0
  ret i1 %z
}
define i8 @neg8(i8 %a) {
  %r = sub i8 0, %a
  ret i8 %r
}
"""
    DECLS = ("!add(a: int, b: int) -> int\n!half(x: float) -> float\n!is_even(n: int[length=32]) -> bool\n"
             "!neg8(a: uint[length=8]) -> uint[length=8]\n")

    def run_with_ir(self, body, args=()):
        src = self.DECLS + prog(body)
        ir = compile_to_ir(src)
        with tempfile.TemporaryDirectory() as d:
            files = {"p.ll": ir, "lib.ll": self.IR}
            for k, v in files.items():
                with open(os.path.join(d, k), "w") as f:
                    f.write(v)
            exe = os.path.join(d, "p")
            r = subprocess.run([CLANG, "-O1", "-Wno-override-module", "-x", "ir", os.path.join(d, "p.ll"),
                                os.path.join(d, "lib.ll"), "-x", "c", RUNTIME, "-lm", "-o", exe], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr + ir)
            r = subprocess.run([exe] + list(args), capture_output=True, text=True)
            return r.stdout, interpreted_with_ir(src, self.IR)

    def test_calls_match_the_interpreter(self):
        out, expected = self.run_with_ir("print(!add(40, 2), !half(5 / 1), !is_even(10), !is_even(7), !neg8(3))")
        self.assertEqual(out, "42 2.5 True False 253\n")
        if expected is not None:
            self.assertEqual(out, expected)

    def test_literals_take_the_declared_type(self):
        out, _ = self.run_with_ir("x: uint[length=8] = !neg8(1)\nprint(x)")
        self.assertEqual(out, "255\n")

    def test_declared_calls_are_type_checked_when_compiling(self):
        for body, text in (("print(!add(1))", "takes 2 argument"), ("print(!half(1))", "does not fit"),
                           ("print(!nope(1))", "is not declared"), ("print(!add('a', 1))", "does not fit")):
            with self.assertRaises(TomatoError) as cm:
                compile_to_ir(self.DECLS + prog(body))
            self.assertIn(text, str(cm.exception))

    def test_unsupported_declared_types(self):
        with self.assertRaises(NotDecided):
            compile_to_ir("!f(x: str) -> int\n" + prog("pass"))


class CompileErrors(unittest.TestCase):
    def fails(self, src, text, kind=TomatoError):
        with self.assertRaises(kind) as cm:
            compile_to_ir(src)
        self.assertIn(text, str(cm.exception))

    def test_unsupported_features_say_so(self):
        for body, what in (("x = 'a'.lower()", "lower"), ("x = None", "None"),
                           ("x = 'a'.upper()", "upper")):
            with self.assertRaises(TomatoError) as cm:
                compile_to_ir(prog(body))
            self.assertIn("the compiler does not support", str(cm.exception), body)

    def test_an_unreachable_unsupported_function_is_left_out(self):
        src = "def f():\n    xs = None\n@main\ndef main():\n    print(1)\n"
        self.assertIn("@tomato.main", compile_to_ir(src))
        self.assertNotIn("@tomato.f", compile_to_ir(src))
        self.fails("def f():\n    xs = None\n@main\ndef main():\n    f()\n", "does not support")

    def test_an_unreachable_function_is_still_type_checked(self):
        self.fails("def f():\n    print(1 + 'a')\n@main\ndef main():\n    print(1)\n", "type error")

    def test_classes_and_imports_not_compiled_yet(self):
        self.fails("from math import abs\n@main\ndef main():\n    print(abs(1))\n", "does not support imported modules")

    def test_type_errors_are_caught_at_compile_time(self):
        self.fails(prog("print(1 + 'a')"), "type error")
        self.fails(prog("x: int[length=8] = 300"), "does not fit")
        self.fails(prog("a: int = 5\nb: int[length=8] = a"), "explicit conversion")
        self.fails(prog("if 1:\n    pass"), "must be a bool")
        self.fails(prog("print(nope)"), "unknown name")
        self.fails("def f(n: int) -> int:\n    return n\n@main\ndef main():\n    print(f('a'))\n", "does not fit")
        self.fails("def f(n: int) -> int:\n    return n\n@main\ndef main():\n    print(f(1, 2))\n", "takes 1 argument")
        self.fails("def f() -> int:\n    return 'a'\n@main\ndef main():\n    pass\n", "does not fit")

    def test_type_errors_in_code_that_never_runs_are_still_found(self):
        self.fails(prog("if False:\n    print(1 + 'a')"), "type error")

    def test_undecided_rules_stay_undecided(self):
        self.fails(prog("x = 1 / 2\nprint(x + x)"), "not yet decided", NotDecided)
        self.fails(prog("print(1 < True)"), "type error")

    def test_break_outside_a_loop(self):
        self.fails(prog("break"), "outside a loop")

    def test_missing_entry(self):
        with self.assertRaises(TomatoError):
            compile_to_ir("def f():\n    pass\n")
        with self.assertRaises(TomatoError):
            compile_to_ir(prog("pass"), entry="nope")

    def test_entry_parameter_types(self):
        with self.assertRaises(TomatoError):
            compile_to_ir(prog("pass", "xs: list[int]"))

    def test_declaration_checks_still_run(self):
        self.fails("class A:\n    @init\n    def a(self):\n        pass\n    @init\n    def b(self):\n        pass\n@main\ndef main():\n    pass\n", "more than one")

    def test_ir_is_text_with_the_expected_pieces(self):
        ir = compile_to_ir(prog("print(1)"))
        self.assertIn("define i32 @main(i32 %argc, ptr %argv)", ir)
        self.assertIn("define void @tomato.main()", ir)
        self.assertIn("debug mode", ir)

    def test_literal_out_of_range_for_the_64_bit_int(self):
        self.fails(prog("print(9223372036854775808)"), "64-bit int")


@needs_clang
class CommandLine(unittest.TestCase):
    def tomato(self, *args):
        r = subprocess.run([sys.executable, "-m", "tomato"] + list(args), cwd=ROOT, capture_output=True, text=True)
        return r.returncode, r.stdout, r.stderr

    def test_compile_writes_ir(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "p.ll")
            code, so, se = self.tomato("compile", "examples/args.tom", "-o", out, "--entry", "prime")
            self.assertEqual(code, 0, se)
            with open(out) as f:
                self.assertIn("@tomato.prime", f.read())

    def test_build_and_run(self):
        with tempfile.TemporaryDirectory() as d:
            exe = os.path.join(d, "p")
            code, so, se = self.tomato("build", "examples/compiled.tom", "-o", exe)
            self.assertEqual(code, 0, se)
            r = subprocess.run([exe, "30"], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0)
            expected = interpreted(open(os.path.join(ROOT, "examples", "compiled.tom")).read(), ["30"])
            self.assertEqual(r.stdout, expected)

    def test_build_modes(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "e.tom")
            with open(src, "w") as f:
                f.write(ErrorModes.SRC)
            exe = os.path.join(d, "e")
            self.assertEqual(self.tomato("build", src, "-o", exe, "--mode", "normal")[0], 0)
            r = subprocess.run([exe, "1", "0"], capture_output=True, text=True)
            self.assertEqual(r.stderr, "error E02:2\n")
            code, so, se = self.tomato("explain", "E02:2", src)
            self.assertEqual(code, 0)
            self.assertIn("division by zero (D05ab)", so)
            self.assertIn("return a / b", so)

    def test_explain_errors(self):
        code, so, se = self.tomato("explain", "nonsense", "examples/args.tom")
        self.assertEqual(code, 1)
        self.assertIn("not a Tomato error code", se)
        self.assertEqual(self.tomato("explain", "E01:1")[0], 2)
        self.assertEqual(self.tomato("explain", "E01:1", "examples/missing.tom")[0], 1)

    def test_compile_reports_unsupported_code(self):
        code, so, se = self.tomato("compile", "examples/features.tom", "-o", "/dev/null")
        self.assertEqual(code, 1)
        self.assertIn("the compiler does not support", se)

    def test_usage(self):
        self.assertEqual(self.tomato("compile")[0], 2)
        self.assertEqual(self.tomato("compile", "examples/args.tom", "--llvm", "examples/mathlib.ll")[0], 2)

    def test_build_links_declared_llvm_functions(self):
        with tempfile.TemporaryDirectory() as d:
            exe = os.path.join(d, "m")
            code, so, se = self.tomato("build", "examples/mathlib.tom", "-o", exe, "--llvm", "examples/mathlib.ll")
            self.assertEqual(code, 0, se)
            r = subprocess.run([exe], capture_output=True, text=True)
            self.assertEqual((r.returncode, r.stdout), (0, "1.4142135623730951\n42\nTrue False\n1000000000\n"))

    def test_bundle_keeps_working(self):
        with tempfile.TemporaryDirectory() as d:
            exe = os.path.join(d, "b")
            self.assertEqual(self.tomato("bundle", "examples/args.tom", "-o", exe)[0], 0)
            r = subprocess.run([exe, "prime", "97"], capture_output=True, text=True)
            self.assertEqual((r.returncode, r.stdout), (0, "97 True\n"))


if __name__ == "__main__":
    unittest.main()
