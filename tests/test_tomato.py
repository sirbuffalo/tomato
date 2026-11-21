import io
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.setrecursionlimit(20000)  # each Tomato call uses several Python frames
from tomato.errors import NotDecided, TomatoError  # noqa: E402
from tomato.interp import run_source  # noqa: E402


def run_raw(src, **kw):
    out = io.StringIO()
    kw.setdefault("warn_out", io.StringIO())   # warnings are not part of a program's output
    run_source(src, out, **kw)
    return out.getvalue()


def with_main(src):
    """Move top-level statements into an @main function, since programs have no top-level code (D16a)."""
    if "@main" in src:
        return src
    decl, body, cur = [], [], None
    lines = src.split("\n")
    k = 0
    while k < len(lines):
        ln = lines[k]
        if not ln.strip() or ln.startswith("#") or ln.startswith((" ", "\t")):
            (cur if cur is not None else decl).append(ln)
        else:
            first = ln.split()[0].split("(")[0]
            is_decl = first in ("def", "class", "interface") or ln.startswith("@") or \
                re.match(r"^\w+ implements ", ln)
            cur = decl if is_decl else body
            cur.append(ln)
            if ln.startswith("@") and k + 1 < len(lines):
                k += 1
                cur.append(lines[k])
        k += 1
    return "\n".join(decl) + "\n@main\ndef main():\n" + "\n".join("    " + b if b.strip() else b for b in body) + \
        ("\n" if body else "    pass\n")


def run(src):
    return run_raw(with_main(src))


def fails(tc, src, text, kind=TomatoError):
    with tc.assertRaises(kind) as cm:
        run(src)
    tc.assertIn(text, str(cm.exception))


SHAPES = """
interface Named:
    def name(self) -> str
interface Shape(Named):
    def area(self) -> int
class Rect implements Shape:
    private w: int
    @init
    def start(self, w: int):
        self.w = w
    def name(self) -> str:
        return "rect"
    def area(self) -> int:
        return self.w * self.w
class Sq(Rect):
    @init
    def make(self, s: int):
        Rect.start(self, s)
    override def name(self) -> str:
        return "sq"
def show(s: Shape) -> str:
    return s.name()
"""


class Integers(unittest.TestCase):
    def test_growing_int(self):
        self.assertEqual(run("print(9223372036854775807 + 1)"), "9223372036854775808\n")

    def test_division(self):
        self.assertEqual(run("print(5 / 2)\nprint(1 / 3)"), "2.5\n0.3333333333333333\n")
        fails(self, "print(5 / 0)", "division by zero")
        self.assertEqual(run("print(0 / 0 - 0)" if False else "print(0 / 7)"), "0.0\n")

    def test_division_overflow(self):
        fails(self, "x = 10 * 10 * 10 * 10 * 10\nprint(x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * "
                    "x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * "
                    "x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * "
                    "x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * "
                    "x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x "
                    "/ 1)", "overflows")

    def test_fixed_overflow(self):
        fails(self, "a: int[length=8] = 127\nb: int[length=8] = a + 1", "does not fit")

    def test_fixed_literal_context(self):
        self.assertEqual(run("a: int[length=8] = 100 + 27\nprint(a)"), "127\n")
        fails(self, "a: int[length=8] = 200", "does not fit")

    def test_widening_and_narrowing(self):
        self.assertEqual(run("a: int[length=8] = 5\nb: int[length=16] = a\nprint(b)"), "5\n")
        fails(self, "a: int[length=16] = 5\nb: int[length=8] = a", "does not fit")
        fails(self, "a: int = 5\nb: int[length=8] = a", "explicit conversion")

    def test_explicit_conversion(self):
        self.assertEqual(run("x = 200\nprint(uint[length=8](x))"), "200\n")
        fails(self, "x = 300\nprint(uint[length=8](x))", "out of range")
        fails(self, "x = -1\nprint(uint[length=8](x))", "out of range")

    def test_common_type(self):
        self.assertEqual(run("a: int[length=8] = 1\nb: int[length=16] = 2\nc: int[length=16] = a + b\nprint(c)"), "3\n")
        fails(self, "a: int[length=8] = 1\nb: uint[length=8] = 2\nprint(a + b)", "common integer type")

    def test_bad_length(self):
        fails(self, "a: int[length=0] = 0", "positive")

    def test_rational(self):
        self.assertEqual(run("print(rational(6, 8))\nprint(rational(1, 3) + rational(1, 6))\nprint(rational(6, -8))"),
                         "3/4\n1/2\n-3/4\n")
        fails(self, "print(rational(1, 0))", "denominator zero")

    def test_modulo_primes_fib(self):
        with open(os.path.join(os.path.dirname(__file__), "..", "examples", "primes.tom")) as f:
            out = run(f.read())
        a, b = 0, 1
        for _ in range(90):
            a, b = b, (a + b)
        self.assertEqual(out.split("\n")[2], str(a % 1000000007))


class Classes(unittest.TestCase):
    def test_dispatch_and_interface_values(self):
        self.assertEqual(run(SHAPES + 'print(show(Rect(2)))\nprint(show(Sq(3)))\nprint(Sq(3).area())'), "rect\nsq\n9\n")

    def test_subclass_where_parent_expected(self):
        self.assertEqual(run(SHAPES + "def f(r: Rect) -> int:\n    return r.area()\nprint(f(Sq(2)))"), "4\n")

    def test_conversion(self):
        self.assertEqual(run(SHAPES + "r: Rect = Sq(2)\ns = Sq(r)\nprint(s.area())"), "4\n")
        fails(self, SHAPES + "s = Sq(Rect(2))", "not one")

    def test_override_rules(self):
        fails(self, SHAPES.replace("override def name", "def name"), "needs `override`")
        fails(self, SHAPES.replace("override def name(self) -> str", "override def other(self) -> str"), "replaces nothing")
        fails(self, SHAPES.replace("override def name(self) -> str", "override def name(self) -> int"), "exactly")

    def test_interface_conformance(self):
        fails(self, SHAPES.replace("    def area(self) -> int:\n        return self.w * self.w\n", ""), "lacks method")
        fails(self, SHAPES.replace("def area(self) -> int:\n        return", "def area(self) -> str:\n        return"),
              "exactly")

    def test_interface_cycle(self):
        fails(self, "interface A(B):\n    pass\ninterface B(A):\n    pass\n", "cycle")

    def test_no_default_bodies(self):
        fails(self, "interface A:\n    def f(self) -> int:\n        return 1\n", "cannot have bodies")

    def test_overlap_same_signature_ok(self):
        src = ("interface R:\n    def close(self)\ninterface W:\n    def close(self)\n"
               "class F implements R, W:\n    def close(self):\n        print(1)\nF().close()")
        self.assertEqual(run(src), "1\n")
        src2 = src.replace("interface W:\n    def close(self)", "interface W:\n    def close(self) -> int")
        fails(self, src2, "exactly")
        fails(self, "interface R:\n    def close(self)\ninterface W:\n    def close(self) -> int\n"
                    "interface S(R, W):\n    pass\n", "different signatures")

    def test_implements_after_definition(self):
        src = ("interface N:\n    def n(self) -> int\nclass C:\n    def n(self) -> int:\n        return 7\n"
               "C implements N\ndef f(x: N) -> int:\n    return x.n()\nprint(f(C()))")
        self.assertEqual(run(src), "7\n")
        fails(self, src.replace("def n(self) -> int:\n        return 7", "pass"), "lacks method")

    def test_subclass_inherits_interface(self):
        src = ("interface N:\n    def n(self) -> int\nclass A implements N:\n    def n(self) -> int:\n        return 1\n"
               "class B(A):\n    pass\ndef f(x: N) -> int:\n    return x.n()\nprint(f(B()))")
        self.assertEqual(run(src), "1\n")

    def test_not_conforming_instance_rejected(self):
        fails(self, "interface N:\n    def n(self) -> int\nclass C:\n    def n(self) -> int:\n        return 1\n"
                    "def f(x: N) -> int:\n    return x.n()\nf(C())", "does not fit")

    def test_private_access(self):
        fails(self, SHAPES + "print(Rect(2).w)", "private")
        fails(self, SHAPES.replace("    def area(self) -> int:\n        return self.w * self.w",
                                   "    def area(self) -> int:\n        return self.w * self.w\n"
                                   "class Sub2(Rect):\n    @init\n    def go(self):\n        Rect.start(self, 1)\n"
                                   "    def peek(self) -> int:\n        return self.w"
                                   ).replace("    def area(self) -> int:\n        return self.w * self.w\n"
                                             "class Sub2", "    def area(self) -> int:\n        return self.w * self.w\n"
                                             "class Sub2", 1) + "print(Sub2().peek())", "private")

    def test_const_field(self):
        src = ("class C:\n    private const k: int\n    @init\n    def s(self, k: int):\n        self.k = k\n"
               "    def bump(self):\n        self.k = 2\nC(1).bump()")
        fails(self, src, "cannot change")

    def test_fields_must_be_set(self):
        fails(self, "class C:\n    x: int\n    @init\n    def s(self):\n        pass\n", "does not set field")
        fails(self, "class C:\n    x: int\n", "no value")
        self.assertEqual(run("class C:\n    x: int = 4\nprint(C().x)"), "4\n")

    def test_init_rules(self):
        fails(self, "class C:\n    @init\n    def a(self):\n        pass\n    @init\n    def b(self):\n        pass\n",
              "more than one")
        fails(self, "class A:\n    @init\n    def a(self):\n        pass\nclass B(A):\n    pass\nB()", "own")
        fails(self, "class A:\n    @init\n    def a(self):\n        pass\nclass B(A):\n    x: int = 1\n"
                    "    @init\n    def b(self):\n        self.x = 2\n", "must start by calling")

    def test_ambiguous_init_param(self):
        fails(self, "class A:\n    pass\nclass B(A):\n    @init\n    def b(self, a: A):\n        pass\n", "D12ba")

    def test_add_operator(self):
        src = ("class P:\n    v: int = 0\n    @init\n    def s(self, v: int):\n        self.v = v\n"
               "    @add\n    def plus(self, o: P) -> P:\n        return P(self.v + o.v)\nprint((P(1) + P(2)).v)")
        self.assertEqual(run(src), "3\n")

    def test_typed_params_required(self):
        fails(self, "def f(a) -> int:\n    return 1\n", "needs a type")

    def test_undecided_stops(self):
        fails(self, "print(1.5)", "whole-number", TomatoError)
        fails(self, "x = True\nprint(x < False)", "not yet decided", NotDecided)


if __name__ == "__main__":
    unittest.main()
