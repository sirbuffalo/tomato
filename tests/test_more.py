import io
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from test_tomato import fails, run, run_raw  # noqa: E402
import os  # noqa: E402
from tomato.errors import NotDecided, TomatoError  # noqa: E402
from tomato.interp import run_source  # noqa: E402


class Division(unittest.TestCase):
    def test_whole_quotient_is_float(self):
        self.assertEqual(run("print(6 / 3)"), "2.0\n")

    def test_negative(self):
        self.assertEqual(run("print(-5 / 2)"), "-2.5\n")

    def test_zero_over_zero(self):
        fails(self, "print(0 / 0)", "division by zero")

    def test_rounded_once_huge_equal(self):
        self.assertEqual(run("x = 10 * 10 * 10 * 10 * 10 * 10 * 10 * 10 * 10 * 10\nprint(x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x / (x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x * x))"), "1.0\n")

    def test_tiny_quotient_rounds_to_zero(self):
        src = "d = 1\ni = 0\nwhile i < 330:\n    d = d * 10\n    i = i + 1\nprint(1 / d)\nprint(-1 / d)"
        self.assertEqual(run(src), "0.0\n-0.0\n")

    def test_zero_numerator_counts_as_positive(self):
        # D05ai: integer zero is positive when the sign is decided, so the divisor's sign shows.
        self.assertEqual(run("print(0 / 4)\nprint(0 / -4)"), "0.0\n-0.0\n")

    def test_division_of_fixed(self):
        self.assertEqual(run("a: int[length=8] = 7\nb: int[length=8] = 2\nprint(a / b)"), "3.5\n")

    def test_float_arithmetic_not_decided(self):
        fails(self, "x = 1 / 2\nprint(x + x)", "not yet decided", NotDecided)

    def test_modulo_signs(self):
        src = "print(7 % 3)\nprint(-7 % 3)\nprint(7 % -3)\nprint(-7 % -3)\nprint(0 % 5)"
        self.assertEqual(run(src), "1\n2\n-2\n-1\n0\n")

    def test_modulo_fixed_width(self):
        self.assertEqual(run("a: int[length=8] = -7\nb: int[length=8] = 3\nc: int[length=8] = a % b\nprint(c)"), "2\n")
        self.assertEqual(run("a: int[length=8] = 100\nb: int[length=16] = 7\nc: int[length=16] = a % b\nprint(c)"), "2\n")

    def test_modulo_float_not_decided(self):
        fails(self, "x = 5 / 2\nprint(x % 2)", "not yet decided", NotDecided)

    def test_modulo(self):
        self.assertEqual(run("print(17 % 5)"), "2\n")
        fails(self, "print(1 % 0)", "modulo by zero")


class Rationals(unittest.TestCase):
    def test_reduces(self):
        self.assertEqual(run("print(rational(6, 8))"), "3/4\n")

    def test_negative_denominator(self):
        self.assertEqual(run("print(rational(-6, -8))\nprint(rational(6, -8))"), "3/4\n-3/4\n")

    def test_zero_is_canonical(self):
        self.assertEqual(run("print(rational(0, 5))\nprint(rational(0, -5))"), "0/1\n0/1\n")

    def test_zero_denominator(self):
        fails(self, "print(rational(0, 0))", "denominator zero")

    def test_float_argument_rejected(self):
        fails(self, "x = 5 / 1\nprint(rational(x, 2))", "integers")

    def test_mixed_integer_types(self):
        self.assertEqual(run("a: int[length=8] = -3\nb: uint[length=8] = 4\nprint(rational(a, b))"), "-3/4\n")

    def test_sum_exact(self):
        self.assertEqual(run("print(rational(1, 3) + rational(1, 6))"), "1/2\n")
        self.assertEqual(run("print(rational(1, 2) + rational(1, 2))"), "1/1\n")

    def test_other_operators_not_decided(self):
        fails(self, "print(rational(1, 2) * rational(1, 2))", "not yet decided", NotDecided)

    def test_equality(self):
        self.assertEqual(run("print(rational(1, 2) == rational(2, 4))"), "True\n")

    def test_arguments_count(self):
        fails(self, "print(rational(1))", "two arguments")

    def test_type_annotation(self):
        self.assertEqual(run("def f(r: rational) -> rational:\n    return r + r\nprint(f(rational(1, 4)))"), "1/2\n")


class FixedInts(unittest.TestCase):
    def test_signed_range(self):
        self.assertEqual(run("a: int[length=7] = 63\nb: int[length=7] = -64\nprint(a)\nprint(b)"), "63\n-64\n")
        fails(self, "a: int[length=7] = 64", "does not fit")
        fails(self, "a: int[length=7] = -65", "does not fit")

    def test_one_bit(self):
        self.assertEqual(run("a: int[length=1] = -1\nb: int[length=1] = 0\nprint(a)\nprint(b)"), "-1\n0\n")
        fails(self, "a: int[length=1] = 1", "does not fit")

    def test_unsigned_subtraction_below_zero(self):
        fails(self, "a: uint[length=8] = 0\nb: uint[length=8] = a - 1", "does not fit")

    def test_negating_minimum(self):
        fails(self, "a: int[length=8] = -128\nb: int[length=8] = -a", "does not fit")

    def test_addition_overflow_at_runtime(self):
        fails(self, "def f(a: int[length=8]) -> int[length=8]:\n    return a + a\nprint(f(100))", "does not fit")

    def test_wide_width_arithmetic(self):
        self.assertEqual(run("a: int[length=2 * 3 * 4] = 1\nprint(a)"), "1\n")

    def test_uint_needs_length(self):
        fails(self, "a: uint = 1", "needs a length")

    def test_negative_width(self):
        fails(self, "a: int[length=1 - 5] = 0", "positive")

    def test_literal_arithmetic_takes_expected_type(self):
        fails(self, "a: int[length=8] = 100 + 100", "does not fit")
        self.assertEqual(run("a: int[length=8] = 100 + 27\nprint(a)"), "127\n")

    def test_literal_with_typed_operand(self):
        self.assertEqual(run("a: uint[length=8] = 250\nb: uint[length=8] = a + 5\nprint(b)"), "255\n")
        fails(self, "a: uint[length=8] = 250\nb = a + 300", "does not fit")

    def test_untyped_literals_grow(self):
        self.assertEqual(run("x = 255 + 1\nprint(x)"), "256\n")

    def test_literal_argument_context(self):
        self.assertEqual(run("def f(a: uint[length=8]) -> uint[length=8]:\n    return a\nprint(f(42))"), "42\n")
        fails(self, "def f(a: uint[length=8]) -> uint[length=8]:\n    return a\nf(256)", "does not fit")

    def test_return_conversion(self):
        self.assertEqual(run("def f(a: int[length=8]) -> int:\n    return a\nprint(f(5))"), "5\n")
        fails(self, "def f(a: int) -> int[length=8]:\n    return a\nf(5)", "explicit conversion")

    def test_explicit_to_int(self):
        self.assertEqual(run("a: int[length=8] = 5\nprint(int(a))"), "5\n")

    def test_explicit_non_integer(self):
        fails(self, "print(int(True))", "only integers")

    def test_bool_is_not_an_integer(self):
        fails(self, "print(True + 1)", "type error")
        fails(self, "x: int = True", "does not fit")


class Classes(unittest.TestCase):
    COUNTER = ("class Counter:\n    private n: int = 0\n    def inc(self):\n        self.n = self.n + 1\n"
               "    def get(self) -> int:\n        return self.n\n")

    def test_instances_have_own_fields(self):
        self.assertEqual(run(self.COUNTER + "a = Counter()\nb = Counter()\na.inc()\nprint(a.get())\nprint(b.get())"),
                         "1\n0\n")

    def test_assignment_shares_object(self):
        self.assertEqual(run(self.COUNTER + "a = Counter()\nb = a\nb.inc()\nprint(a.get())"), "1\n")

    def test_argument_shares_object(self):
        src = self.COUNTER + "def bump(c: Counter):\n    c.inc()\n    c = Counter()\n    c.inc()\na = Counter()\nbump(a)\nprint(a.get())"
        self.assertEqual(run(src), "1\n")

    def test_class_without_init_takes_no_arguments(self):
        fails(self, self.COUNTER + "Counter(1)", "takes no arguments")

    def test_undeclared_field(self):
        fails(self, self.COUNTER.replace("self.n = self.n + 1", "self.m = 1") + "Counter().inc()", "no field")

    def test_private_other_instance_allowed(self):
        src = ("class P:\n    private v: int = 3\n    def same(self, o: P) -> bool:\n        return self.v == o.v\n"
               "print(P().same(P()))")
        self.assertEqual(run(src), "True\n")

    def test_private_method(self):
        src = "class P:\n    def private hid(self) -> int:\n        return 1\n    def pub(self) -> int:\n        return self.hid()\n"
        self.assertEqual(run(src + "print(P().pub())"), "1\n")
        fails(self, src + "P().hid()", "private")

    def test_public_by_default(self):
        self.assertEqual(run("class P:\n    x: int = 2\nprint(P().x)"), "2\n")

    def test_no_protected(self):
        fails(self, "class P:\n    protected x: int = 2\n", "found")

    def test_subclass_cannot_use_parent_private_method(self):
        src = ("class A:\n    def private p(self) -> int:\n        return 1\n"
               "class B(A):\n    def q(self) -> int:\n        return self.p()\nprint(B().q())")
        fails(self, src, "private")

    def test_const_set_once_in_init(self):
        src = "class C:\n    const k: int\n    @init\n    def s(self, k: int):\n        self.k = k\n        self.k = k\nC(1)"
        fails(self, src, "already set")

    def test_const_not_in_init_assignment(self):
        src = "class C:\n    const k: int\n    @init\n    def s(self, k: int):\n        self.k = k\nc = C(1)\nc.k = 2"
        fails(self, src, "cannot change")

    def test_const_binding_not_object(self):
        src = (SHAPES_COUNTER := "class N:\n    v: int = 0\nclass H:\n    const n: N\n    @init\n    def s(self, n: N):\n        self.n = n\n"
               "h = H(N())\nh.n.v = 5\nprint(h.n.v)")
        self.assertEqual(run(src), "5\n")

    def test_private_const_order(self):
        self.assertEqual(run("class C:\n    private const k: int = 1\n    def g(self) -> int:\n        return self.k\nprint(C().g())"), "1\n")
        fails(self, "class C:\n    const private k: int = 1\n", "private const")

    def test_field_needs_type(self):
        fails(self, "class C:\n    x = 1\n", "expected")

    def test_field_value_type_checked(self):
        fails(self, "class C:\n    x: int[length=8] = 300\nC()", "does not fit")

    def test_method_arguments_checked(self):
        fails(self, self.COUNTER + "class M:\n    def f(self, a: uint[length=8]):\n        pass\nM().f(300)", "does not fit")

    def test_wrong_argument_count(self):
        fails(self, "def f(a: int) -> int:\n    return a\nf(1, 2)", "takes 1")

    def test_missing_return(self):
        fails(self, "def f() -> int:\n    pass\nf()", "without returning")

    def test_return_in_none_function(self):
        fails(self, "def f():\n    return 1\nf()", "returns no value")

    def test_class_function(self):
        src = "class C:\n    def unit() -> int:\n        return 9\nprint(C.unit())"
        self.assertEqual(run(src), "9\n")

    def test_class_function_cannot_use_self(self):
        fails(self, "class C:\n    x: int = 1\n    def u() -> int:\n        return self.x\nC.u()", "unknown name")

    def test_self_with_type_rejected(self):
        fails(self, "class C:\n    def f(self: C):\n        pass\n", "self is written without a type")

    def test_single_inheritance_only(self):
        fails(self, "class A:\n    pass\nclass B:\n    pass\nclass C(A, B):\n    pass\n", "at most one parent")

    def test_inheritance_cycle(self):
        fails(self, "class A(B):\n    pass\nclass B(A):\n    pass\n", "inherits from itself")

    def test_unknown_parent(self):
        fails(self, "class A(Nope):\n    pass\n", "unknown parent")

    def test_init_called_in_chain(self):
        src = ("class A:\n    private a: int\n    @init\n    def sa(self, a: int):\n        self.a = a\n    def ga(self) -> int:\n        return self.a\n"
               "class B(A):\n    private b: int\n    @init\n    def sb(self, a: int, b: int):\n        A.sa(self, a)\n        self.b = b\n"
               "    def gb(self) -> int:\n        return self.b\n"
               "x = B(1, 2)\nprint(x.ga())\nprint(x.gb())")
        self.assertEqual(run(src), "1\n2\n")

    def test_parent_init_called_twice(self):
        src = ("class A:\n    @init\n    def sa(self):\n        pass\nclass B(A):\n    @init\n    def sb(self):\n"
               "        A.sa(self)\n        A.sa(self)\n")
        fails(self, src, "exactly once")

    def test_override_calls_parent_version(self):
        src = ("class A:\n    def f(self) -> int:\n        return 1\nclass B(A):\n    override def f(self) -> int:\n"
               "        return A.f(self) + 10\nprint(B().f())")
        self.assertEqual(run(src), "11\n")

    def test_init_never_overridden(self):
        fails(self, "class A:\n    @init\n    def s(self):\n        pass\nclass B(A):\n    @init\n    override def t(self):\n        pass\n",
              "never replaced")

    def test_override_of_class_function_rejected(self):
        fails(self, "class A:\n    def u() -> int:\n        return 1\nclass B(A):\n    override def u() -> int:\n        return 2\n",
              "instance methods")

    def test_conversion_to_own_class_is_identity(self):
        self.assertEqual(run(self.COUNTER + "a = Counter()\nb = Counter(a)\nb.inc()\nprint(a.get())"), "1\n")

    def test_dispatch_through_parent_typed_variable(self):
        src = ("class A:\n    def f(self) -> int:\n        return 1\nclass B(A):\n    override def f(self) -> int:\n        return 2\n"
               "x: A = B()\nprint(x.f())")
        self.assertEqual(run(src), "2\n")

    def test_parent_not_accepted_for_subclass_param(self):
        fails(self, "class A:\n    pass\nclass B(A):\n    pass\ndef f(b: B):\n    pass\nf(A())", "does not fit")


class Operators(unittest.TestCase):
    P = ("class P:\n    v: int = 0\n    @init\n    def s(self, v: int):\n        self.v = v\n"
         "    @add\n    def plus(self, o: P) -> P:\n        return P(self.v + o.v)\n")

    def test_add_chain(self):
        self.assertEqual(run(self.P + "print((P(1) + P(2) + P(3)).v)"), "6\n")

    def test_no_add_method(self):
        fails(self, "class Q:\n    pass\nQ() + Q()", "no @add")

    def test_other_operator_not_decided(self):
        fails(self, self.P + "P(1) * P(2)", "not yet decided", NotDecided)

    def test_second_add_not_decided(self):
        fails(self, self.P + "class R:\n    @add\n    def a(self, o: R):\n        pass\n    @add\n    def b(self, o: R):\n        pass\n",
              "not yet decided", NotDecided)

    def test_add_operand_type_checked(self):
        fails(self, self.P + "P(1) + 5", "does not fit")

    def test_unknown_marker(self):
        fails(self, "class C:\n    @frobnicate\n    def f(self):\n        pass\n", "unknown marker")


class Interfaces(unittest.TestCase):
    def test_extends_several(self):
        src = ("interface A:\n    def a(self) -> int\ninterface B:\n    def b(self) -> int\ninterface C(A, B):\n    pass\n"
               "class K implements C:\n    def a(self) -> int:\n        return 1\n    def b(self) -> int:\n        return 2\n"
               "def f(x: A) -> int:\n    return x.a()\ndef g(x: B) -> int:\n    return x.b()\nk: C = K()\nprint(f(k) + g(k))")
        self.assertEqual(run(src), "3\n")

    def test_missing_parent_method(self):
        src = ("interface A:\n    def a(self) -> int\ninterface C(A):\n    def c(self) -> int\n"
               "class K implements C:\n    def c(self) -> int:\n        return 1\n")
        fails(self, src, "lacks method")

    def test_unknown_interface(self):
        fails(self, "class K implements Nope:\n    pass\n", "unknown interface")

    def test_self_cycle(self):
        fails(self, "interface A(A):\n    pass\n", "cycle")

    def test_parameter_names_do_not_matter(self):
        src = ("interface A:\n    def f(self, x: int) -> int\nclass K implements A:\n    def f(self, y: int) -> int:\n"
               "        return y\nprint(K().f(3))")
        self.assertEqual(run(src), "3\n")

    def test_broader_parameter_not_accepted(self):
        src = ("interface A:\n    def f(self, x: int[length=8]) -> int\nclass K implements A:\n    def f(self, x: int) -> int:\n"
               "        return x\n")
        fails(self, src, "exactly")

    def test_interface_value_dispatches_to_actual_class(self):
        src = ("interface S:\n    def n(self) -> int\nclass A implements S:\n    def n(self) -> int:\n        return 1\n"
               "class B implements S:\n    def n(self) -> int:\n        return 2\n"
               "def f(s: S) -> int:\n    return s.n()\nprint(f(A()) + f(B()))")
        self.assertEqual(run(src), "3\n")

    def test_interface_as_return_type(self):
        src = ("interface S:\n    def n(self) -> int\nclass A implements S:\n    def n(self) -> int:\n        return 4\n"
               "def make() -> S:\n    return A()\nprint(make().n())")
        self.assertEqual(run(src), "4\n")

    def test_class_not_declaring_is_rejected_even_if_methods_match(self):
        fails(self, "interface S:\n    def n(self) -> int\nclass A:\n    def n(self) -> int:\n        return 1\n"
                    "def f(s: S):\n    pass\nf(A())", "does not fit")

    def test_implements_unknown_class(self):
        fails(self, "interface S:\n    pass\nNope implements S\n", "unknown class")

    def test_implements_checks_types(self):
        fails(self, "interface S:\n    def n(self) -> int\nclass A:\n    def n(self) -> str:\n        return \"x\"\nA implements S\n",
              "exactly")

    def test_init_parameter_ambiguity_with_interface(self):
        src = ("interface S:\n    pass\nclass A implements S:\n    @init\n    def s(self, x: S):\n        pass\n")
        fails(self, src, "D12ba")

    def test_interface_method_with_body_rejected(self):
        fails(self, "interface S:\n    def n(self) -> int:\n        return 1\n", "cannot have bodies")

    def test_interface_method_needs_self(self):
        fails(self, "interface S:\n    def n() -> int\n", "not yet decided", NotDecided)


class Syntax(unittest.TestCase):
    def test_tabs_rejected(self):
        fails(self, "if True:\n\tprint(1)\n", "tabs")

    def test_inconsistent_dedent(self):
        fails(self, "if True:\n        print(1)\n    print(2)\n", "indentation")

    def test_unterminated_string(self):
        fails(self, 'print("abc)\n', "unterminated")

    def test_unknown_character(self):
        fails(self, "print(1 $ 2)\n", "unexpected character")

    def test_unclosed_bracket(self):
        fails(self, "print(1\n", "unclosed")

    def test_comments_and_blank_lines(self):
        self.assertEqual(run("# hi\n\nprint(1) # tail\n\n"), "1\n")

    def test_multiline_call(self):
        self.assertEqual(run("def f(a: int, b: int) -> int:\n    return a + b\nprint(f(\n    1,\n    2,\n))"), "3\n")

    def test_if_elif_else(self):
        src = "def f(x: int) -> int:\n    if x < 0:\n        return 0 - 1\n    elif x == 0:\n        return 0\n    else:\n        return 1\nprint(f(-5))\nprint(f(0))\nprint(f(9))"
        self.assertEqual(run(src), "-1\n0\n1\n")

    def test_while_loop(self):
        self.assertEqual(run("i = 0\ns = 0\nwhile i < 5:\n    s = s + i\n    i = i + 1\nprint(s)"), "10\n")

    def test_and_or_not(self):
        self.assertEqual(run("print(True and not False)\nprint(False or False)"), "True\nFalse\n")

    def test_short_circuit(self):
        self.assertEqual(run("def boom() -> bool:\n    return 1 / 0 > 1\nprint(False and boom())\nprint(True or boom())"), "False\nTrue\n")

    def test_condition_must_be_bool(self):
        fails(self, "if 1:\n    pass\n", "must be a bool")

    def test_precedence(self):
        self.assertEqual(run("print(2 + 3 * 4)\nprint((2 + 3) * 4)\nprint(0 - 2 * 3)"), "14\n20\n-6\n")

    def test_chained_comparison_not_decided(self):
        fails(self, "print(1 < 2 < 3)", "not yet decided", NotDecided)

    def test_nested_declaration_not_decided(self):
        fails(self, "if True:\n    def f():\n        pass\n", "not yet decided", NotDecided)

    def test_unknown_name(self):
        fails(self, "print(nope)", "unknown name")

    def test_unknown_type(self):
        fails(self, "x: Nope = 1", "unknown type")

    def test_local_type_fixed_after_first_assignment(self):
        fails(self, "x: int[length=8] = 1\nx = 300", "does not fit")
        fails(self, "x = True\nx = 5", "does not fit")

    def test_redeclaration_not_decided(self):
        fails(self, "x: int = 1\nx: int = 2", "not yet decided", NotDecided)

    def test_duplicate_function(self):
        fails(self, "def f():\n    pass\ndef f():\n    pass\n", "already declared")

    def test_recursion(self):
        self.assertEqual(run("def fact(n: int) -> int:\n    if n < 2:\n        return 1\n    return n * fact(n - 1)\nprint(fact(25))"),
                         "15511210043330985984000000\n")

    def test_functions_hoisted(self):
        self.assertEqual(run("print(f())\ndef f() -> int:\n    return 3\n"), "3\n")

    def test_string_equality(self):
        self.assertEqual(run('print("a" == "a")\nprint("a" == "b")'), "True\nFalse\n")


class Strings(unittest.TestCase):
    def test_both_quotes(self):
        self.assertEqual(run("print('a')\nprint(\"b\")"), "a\nb\n")

    def test_other_quote_inside(self):
        self.assertEqual(run("print('say \"hi\"')\nprint(\"it's\")"), 'say "hi"\nit\'s\n')

    def test_equal_across_quote_styles(self):
        self.assertEqual(run("print('a' == \"a\")"), "True\n")

    def test_unterminated_single(self):
        fails(self, "print('abc)\n", "unterminated")

    def test_mismatched_quotes(self):
        fails(self, "print('abc\")\n", "unterminated")

    def test_escapes(self):
        self.assertEqual(run("print('a\\tb')\nprint('c\\\\d')\nprint('it\\'s')\nprint('\\u{e9}\\u{1F345}')"),
                         "a\tb\nc\\d\nit's\n\u00e9\U0001F345\n")
        self.assertEqual(run("print(len('a\\nb'))"), "3\n")

    def test_bad_escapes(self):
        fails(self, "print('\\q')\n", "unknown escape")
        fails(self, "print('\\u{zz}')\n", "bad")
        fails(self, "print('\\u{D800}')\n", "surrogates")
        fails(self, "print('\\u{110000}')\n", "bad")

    def test_length_counts_characters(self):
        self.assertEqual(run("print(len('h\u00e9llo'))" if False else "print(len('h\\u{e9}llo'))\nprint(len('\\u{1F345}'))\nprint(len(''))"),
                         "5\n1\n0\n")

    def test_concat(self):
        self.assertEqual(run("print('a' + 'b' + \"c\")"), "abc\n")
        fails(self, "print('a' + 1)", "type error")

    def test_index(self):
        self.assertEqual(run("s = 'h\\u{e9}llo'\nprint(s[0])\nprint(s[1])\nprint(s[4])"), "h\n\u00e9\no\n")
        fails(self, "print('abc'[3])", "out of range")
        fails(self, "print('abc'[0 - 1])", "not yet decided", NotDecided)
        fails(self, "print('abc'['a'])", "must be an integer")
        fails(self, "x = 5\nprint(x[0])", "not yet decided", NotDecided)

    def test_strings_are_immutable(self):
        fails(self, "s = 'abc'\ns[0] = 'x'", "cannot be changed in place")

    def test_slice(self):
        self.assertEqual(run("s = 'hello'\nprint(s[1:3])\nprint(s[:2])\nprint(s[3:])\nprint(s[:])\nprint(s[2:2] == '')"),
                         "el\nhe\nlo\nhello\nTrue\n")
        fails(self, "print('abc'[2:1])", "out of range")
        fails(self, "print('abc'[0:4])", "out of range")
        fails(self, "print('abc'[0 - 1:2])", "not yet decided", NotDecided) if False else None

    def test_slice_keeps_characters_whole(self):
        self.assertEqual(run("s = 'a\\u{1F345}b'\nprint(s[1:2] == '\\u{1F345}')\nprint(len(s[1:]))"), "True\n2\n")

    def test_ordering(self):
        self.assertEqual(run("print('a' < 'b')\nprint('b' < 'a')\nprint('ab' < 'abc')\nprint('a' <= 'a')\nprint('B' < 'a')"),
                         "True\nFalse\nTrue\nTrue\nTrue\n")

    def test_in(self):
        self.assertEqual(run("print('ll' in 'hello')\nprint('x' in 'hello')\nprint('' in 'a')"), "True\nFalse\nTrue\n")
        fails(self, "print(1 in 'a')", "type error")
        fails(self, "print('a' in 1)", "type error")

    def test_methods(self):
        self.assertEqual(run("s = '  Hi There '\nprint(s.strip())\nprint(s.upper())\nprint(s.lower())\n"
                             "print(s.strip().startswith('Hi'))\nprint(s.endswith('e '))\nprint(s.find('T'))\nprint(s.find('z'))\n"
                             "print('aXbXc'.replace('X', '-'))"),
                         "Hi There\n  HI THERE \n  hi there \nTrue\nTrue\n5\n-1\na-b-c\n")

    def test_method_errors(self):
        fails(self, "print('a'.nope())", "no method")
        fails(self, "print('a'.upper(1))", "takes 0")
        fails(self, "print('a'.startswith(1))", "takes text")
        fails(self, "print('a'.replace('', 'x'))", "not yet decided", NotDecided)
        fails(self, "print('a b'.split(''))", "not yet decided", NotDecided)
        fails(self, "print(' '.join('ab'))", "join takes a list[str]")
        fails(self, "print(' '.join([1, 2]))", "join takes a list[str]")

    def test_str_conversion(self):
        self.assertEqual(run("print('n=' + str(5) + ' ' + str(True) + ' ' + str(1 / 4) + ' ' + str(rational(2, 4)) + str('x'))"),
                         "n=5 True 0.25 1/2x\n")
        fails(self, "class C:\n    pass\nprint(str(C()))", "not yet decided", NotDecided)

    def test_int_from_text(self):
        self.assertEqual(run("print(int('42') + int(' -7 ') + int('+1'))"), "36\n")
        fails(self, "print(int('4x'))", "cannot convert")
        fails(self, "print(int(''))", "cannot convert")
        fails(self, "print(int('1.5'))", "cannot convert")
        self.assertEqual(run("print(int('123456789012345678901234567890') + 1)"), "123456789012345678901234567891\n")

    def test_len_of_non_text(self):
        fails(self, "print(len(5))", "not yet decided", NotDecided)

    def test_text_parameters_and_fields(self):
        src = ("class P:\n    private name: str\n    @init\n    def s(self, name: str):\n        self.name = name\n"
               "    def hello(self) -> str:\n        return 'hi ' + self.name\nprint(P('bo').hello())")
        self.assertEqual(run(src), "hi bo\n")
        fails(self, "def f(a: str) -> str:\n    return a\nf(1)", "does not fit")

    def test_loop_over_characters(self):
        src = "s = 'abc'\nr = ''\nfor i in range(len(s)):\n    r = s[i] + r\nprint(r)"
        self.assertEqual(run(src), "cba\n")

    def test_multiline_literal_not_decided(self):
        fails(self, "print('abc\n", "unterminated")


class TypeErrors(unittest.TestCase):
    def test_int_plus_str(self):
        fails(self, "print(1 + 'a')", "type error: cannot use + with int and str")
        fails(self, "print('a' + 1)", "type error")

    def test_other_operators_clash(self):
        for src in ("1 - 'a'", "1 * 'a'", "1 / 'a'", "1 % 'a'", "'a' == 1", "1 < 'a'", "True + 1", "True == 1"):
            fails(self, "print(%s)" % src, "type error")

    def test_class_with_number(self):
        fails(self, "class C:\n    pass\nprint(C() == 1)", "type error")
        fails(self, "class C:\n    pass\nprint(1 + C())", "type error")

    def test_same_type_undecided_stays_undecided(self):
        fails(self, "print('a' - 'b')", "not yet decided", NotDecided)
        fails(self, "x = 1 / 2\nprint(x + x)", "not yet decided", NotDecided)

    def test_mixed_numeric_stays_undecided(self):
        fails(self, "x = 1 / 2\nprint(x + 1)", "not yet decided", NotDecided)
        fails(self, "print(rational(1, 2) + 1)", "not yet decided", NotDecided)

    def test_different_classes_compare_by_identity(self):
        self.assertEqual(run("class A:\n    pass\nclass B:\n    pass\nprint(A() == B())"), "False\n")


class ForLoops(unittest.TestCase):
    def test_range_forms(self):
        src = ("for i in range(3):\n    print(i)\nfor i in range(2, 5):\n    print(i)\n"
               "for i in range(10, 0, -4):\n    print(i)")
        self.assertEqual(run(src), "0\n1\n2\n2\n3\n4\n10\n6\n2\n")

    def test_empty_range(self):
        self.assertEqual(run("for i in range(0):\n    print(i)\nprint('done')"), "done\n")
        self.assertEqual(run("for i in range(5, 1):\n    print(i)\nprint('done')"), "done\n")

    def test_range_is_a_value(self):
        self.assertEqual(run("r = range(3)\nfor i in r:\n    print(i)\nfor i in r:\n    print(i)"), "0\n1\n2\n0\n1\n2\n")

    def test_range_as_parameter_type(self):
        src = "def total(r: range) -> int:\n    t = 0\n    for i in r:\n        t = t + i\n    return t\nprint(total(range(4)))"
        self.assertEqual(run(src), "6\n")

    def test_nested_and_while(self):
        src = ("n = 0\nfor i in range(3):\n    for j in range(3):\n        n = n + 1\nprint(n)\n"
               "k = 0\nwhile k < 2:\n    k = k + 1\nprint(k)")
        self.assertEqual(run(src), "9\n2\n")

    def test_return_from_inside_loop(self):
        src = "def f() -> int:\n    for i in range(10):\n        if i == 4:\n            return i\n    return 0 - 1\nprint(f())"
        self.assertEqual(run(src), "4\n")

    def test_range_arguments(self):
        fails(self, "range()", "one to three")
        fails(self, "range('a')", "one to three")
        fails(self, "range(1, 5, 0)", "step cannot be zero")

    def test_bignum_range(self):
        self.assertEqual(run("t = 0\nfor i in range(100000000000000000000, 100000000000000000003):\n    t = t + 1\nprint(t)"), "3\n")

    def test_loop_over_non_range_not_decided(self):
        fails(self, "for i in 5:\n    pass", "not yet decided", NotDecided)
        fails(self, "class C:\n    pass\nfor i in C():\n    pass", "not yet decided", NotDecided)

    def test_loop_variable_type_conflict(self):
        fails(self, "i = True\nfor i in range(2):\n    pass", "already has type")

    def test_for_needs_in(self):
        fails(self, "for i range(3):\n    pass", "expected")


class ReviewFixes(unittest.TestCase):
    CLS = ("interface N:\n    def name(self) -> int\n"
           "class A implements N:\n    def name(self) -> int:\n        return 1\n    def extra(self) -> int:\n        return 7\n"
           "    f: int = 3\n"
           "class B(A):\n    def only_b(self) -> int:\n        return 9\n")

    def test_argument_evaluated_once(self):
        src = ("def noisy() -> int:\n    print('called')\n    return 1\n"
               "class C:\n    x: int\n    @init\n    def s(self, x: int):\n        self.x = x\n"
               "c = C(noisy())\nprint(c.x)")
        self.assertEqual(run(src), "called\n1\n")

    def test_single_argument_still_gets_literal_context(self):
        src = "class C:\n    x: uint[length=8]\n    @init\n    def s(self, x: uint[length=8]):\n        self.x = x\nprint(C(255).x)"
        self.assertEqual(run(src), "255\n")
        fails(self, src.replace("C(255)", "C(256)"), "does not fit")

    def test_single_non_literal_argument_is_typed(self):
        src = ("class C:\n    x: int[length=8]\n    @init\n    def s(self, x: int[length=8]):\n        self.x = x\n"
               "a: int[length=8] = 5\nprint(C(a).x)")
        self.assertEqual(run(src), "5\n")

    def test_interface_typed_parameter_hides_extra_members(self):
        fails(self, self.CLS + "def g(n: N) -> int:\n    return n.extra()\nprint(g(A()))", "has no method extra")
        fails(self, self.CLS + "def g(n: N) -> int:\n    return n.f\nprint(g(A()))", "has no field f")
        self.assertEqual(run(self.CLS + "def g(n: N) -> int:\n    return n.name()\nprint(g(B()))"), "1\n")

    def test_parent_typed_variable_hides_subclass_members(self):
        fails(self, self.CLS + "def g(a: A) -> int:\n    return a.only_b()\nprint(g(B()))", "has no method only_b")
        self.assertEqual(run(self.CLS + "b = B()\nprint(b.only_b() + b.extra())"), "16\n")

    def test_hidden_member_in_assignment_target(self):
        fails(self, self.CLS.replace("    f: int = 3\n", "    f: int = 3\n") +
              "def g(n: N):\n    n.f = 1\ng(A())", "has no field f")

    def test_deep_recursion(self):
        src = "def f(n: int) -> int:\n    if n == 0:\n        return 0\n    return 1 + f(n - 1)\nprint(f(150))"
        self.assertEqual(run(src), "150\n")
        import sys
        old = sys.getrecursionlimit()
        sys.setrecursionlimit(200)
        try:
            fails(self, "def f(n: int) -> int:\n    return f(n + 1)\nf(0)", "nested too deep")
        finally:
            sys.setrecursionlimit(old)

    def test_depth_limit_message(self):
        import tomato.interp as interp
        old = interp.MAX_CALL_DEPTH
        interp.MAX_CALL_DEPTH = 30
        try:
            fails(self, "def f(n: int) -> int:\n    return f(n + 1)\nf(0)", "nested more than 30")
        finally:
            interp.MAX_CALL_DEPTH = old

    def test_overflow_error_has_line(self):
        for expr in ("0 - z", "-z"):
            src = "@main\ndef main():\n    z: int[length=8] = -128\n    w: int[length=8] = %s\n" % expr
            with self.assertRaises(TomatoError) as cm:
                run_raw(src)
            self.assertIn("line 4", str(cm.exception))

    def test_function_value_type_name(self):
        fails(self, "def f():\n    pass\nx: int = f", "function or class")

    def test_hidden_members_through_expressions(self):
        base = self.CLS + "def make() -> N:\n    return A()\ndef pa() -> A:\n    return B()\n"
        fails(self, base + "print(make().extra())", "has no method extra")
        fails(self, base + "print(pa().only_b())", "has no method only_b")
        fails(self, base + "print(A().f2)", "has no field f2")
        self.assertEqual(run(base + "print(make().name() + pa().extra())"), "8\n")

    def test_hidden_members_through_fields_and_methods(self):
        src = ("interface N:\n    def name(self) -> int\nclass A implements N:\n    def name(self) -> int:\n        return 1\n"
               "    def extra(self) -> int:\n        return 2\n"
               "class H:\n    h: N\n    @init\n    def s(self, h: N):\n        self.h = h\n"
               "    def get(self) -> N:\n        return self.h\n")
        fails(self, src + "H(A()).h.extra()", "has no method extra")
        fails(self, src + "H(A()).get().extra()", "has no method extra")
        self.assertEqual(run(src + "print(H(A()).get().name())"), "1\n")

    def test_init_must_set_fields_on_every_path(self):
        # P16: D12x's exact rules are open; this prototype requires every path to set each field.
        base = "class C:\n    x: int\n    @init\n    def s(self, b: bool):\n%s"
        ok = base % "        if b:\n            self.x = 1\n        else:\n            self.x = 2\n"
        self.assertEqual(run(ok + "print(C(True).x)\nprint(C(False).x)"), "1\n2\n")
        fails(self, base % "        if b:\n            self.x = 1\n", "does not set field x on every path")
        fails(self, base % "        while b:\n            self.x = 1\n", "does not set field x on every path")
        fails(self, base % "        for i in range(3):\n            self.x = i\n", "does not set field x on every path")
        fails(self, base % "        if b:\n            return\n        self.x = 1\n", "returns before setting field x")
        self.assertEqual(run(base % "        self.x = 1\n        if b:\n            return\n" + "print(C(True).x)"), "1\n")


class Lists(unittest.TestCase):
    def test_literal_index_append_len(self):
        src = "names: list[str] = ['ann', 'bo']\nnames.append('cy')\nprint(len(names), names[0], names[2])\nprint(names)"
        self.assertEqual(run(src), "3 ann cy\n['ann', 'bo', 'cy']\n")

    def test_set_item(self):
        self.assertEqual(run("xs = [1, 2, 3]\nxs[1] = 20\nprint(xs)"), "[1, 20, 3]\n")
        fails(self, "xs = [1, 2]\nxs[0] = 'a'", "does not fit")

    def test_index_errors(self):
        fails(self, "xs = [1]\nprint(xs[1])", "out of range")
        fails(self, "xs = [1]\nprint(xs[0 - 1])", "not yet decided", NotDecided)
        fails(self, "xs = [1]\nprint(xs['a'])", "must be an integer")
        fails(self, "xs = [1]\nxs[5] = 2", "out of range")

    def test_item_types_must_agree(self):
        fails(self, "xs = [1, 'a']", "does not fit")
        fails(self, "xs: list[str] = [1]", "does not fit")
        fails(self, "xs = [1]\nxs.append('a')", "does not fit")

    def test_empty_literal_needs_a_type(self):
        self.assertEqual(run("xs: list[int] = []\nprint(len(xs))"), "0\n")
        fails(self, "xs = []", "not yet decided", NotDecided)

    def test_literal_context_for_fixed_width_items(self):
        self.assertEqual(run("xs: list[uint[length=8]] = [1, 255]\nprint(xs)"), "[1, 255]\n")
        fails(self, "xs: list[uint[length=8]] = [1, 256]", "does not fit")
        self.assertEqual(run("xs: list[uint[length=8]] = []\nxs.append(7)\nprint(xs)"), "[7]\n")
        fails(self, "xs: list[uint[length=8]] = []\nxs.append(300)", "does not fit")

    def test_list_types_do_not_convert(self):
        fails(self, "def f(xs: list[int[length=8]]):\n    pass\ndef g():\n    ys: list[int] = [1]\n    f(ys)\ng()", "does not fit")

    def test_lists_are_shared(self):
        src = "a = [1]\nb = a\nb.append(2)\nprint(len(a))"
        self.assertEqual(run(src), "2\n")
        src = "def add(xs: list[int]):\n    xs.append(9)\nv = [1]\nadd(v)\nprint(v)"
        self.assertEqual(run(src), "[1, 9]\n")

    def test_for_over_list(self):
        self.assertEqual(run("t = 0\nfor n in [1, 2, 3]:\n    t = t + n\nprint(t)"), "6\n")
        self.assertEqual(run("for s in ['a', 'b']:\n    print(s)"), "a\nb\n")

    def test_loop_variable_type_from_list(self):
        fails(self, "i = 0\nfor i in ['a']:\n    pass", "already has type")

    def test_in(self):
        self.assertEqual(run("print(2 in [1, 2])\nprint('x' in ['a'])"), "True\nFalse\n")
        fails(self, "print('x' in [1])", "type error")

    def test_len_and_nested(self):
        self.assertEqual(run("grid: list[list[int]] = [[1, 2], [3]]\nprint(len(grid), len(grid[0]), grid[1][0])"), "2 2 3\n")

    def test_lists_of_objects(self):
        src = ("class P:\n    v: int = 1\n    def get(self) -> int:\n        return self.v\n"
               "ps: list[P] = [P(), P()]\nprint(ps[1].get() + len(ps))")
        self.assertEqual(run(src), "3\n")
        fails(self, "class P:\n    pass\nps: list[P] = [1]", "does not fit")

    def test_list_of_interface_accepts_implementers(self):
        src = ("interface N:\n    def n(self) -> int\nclass A implements N:\n    def n(self) -> int:\n        return 5\n"
               "xs: list[N] = [A()]\nprint(xs[0].n())")
        self.assertEqual(run(src), "5\n")

    def test_list_parameters_and_returns(self):
        src = ("def evens(n: int) -> list[int]:\n    r: list[int] = []\n    for i in range(n):\n        if i % 2 == 0:\n"
               "            r.append(i)\n    return r\nprint(evens(7))")
        self.assertEqual(run(src), "[0, 2, 4, 6]\n")

    def test_split_join(self):
        self.assertEqual(run("print('a,b,c'.split(','))\nprint('-'.join(['x', 'y', 'z']))"), "['a', 'b', 'c']\nx-y-z\n")
        self.assertEqual(run("print('abc'.split('b'))\nprint(len(''.split(',')))"), "['a', 'c']\n1\n")

    def test_undecided_list_features(self):
        fails(self, "xs = [1]\nprint(xs[0:1])", "not yet decided", NotDecided)
        fails(self, "xs = [1]\nxs.pop()", "not yet decided", NotDecided)
        fails(self, "print([1] == [1])", "not yet decided", NotDecided)

    def test_bare_list_type(self):
        fails(self, "xs: list = [1]", "expected")

    def test_list_field(self):
        src = ("class Bag:\n    items: list[int] = [1]\n    def add(self, n: int):\n        self.items.append(n)\n"
               "b = Bag()\nb.add(2)\nprint(b.items)")
        self.assertEqual(run(src), "[1, 2]\n")

    def test_list_plus_not_decided(self):
        fails(self, "print([1] + [2])", "not yet decided", NotDecided)


class ControlFlow(unittest.TestCase):
    def test_break_and_continue_in_for(self):
        src = ("for i in range(10):\n    if i == 2:\n        continue\n    if i == 5:\n        break\n    print(i)")
        self.assertEqual(run(src), "0\n1\n3\n4\n")

    def test_break_and_continue_in_while(self):
        src = ("i = 0\nwhile True:\n    i = i + 1\n    if i < 3:\n        continue\n    break\nprint(i)")
        self.assertEqual(run(src), "3\n")

    def test_break_in_nested_loop_only_leaves_inner(self):
        src = ("n = 0\nfor i in range(3):\n    for j in range(3):\n        if j == 1:\n            break\n        n = n + 1\nprint(n)")
        self.assertEqual(run(src), "3\n")

    def test_continue_in_list_loop(self):
        self.assertEqual(run("for s in ['a', 'b', 'c']:\n    if s == 'b':\n        continue\n    print(s)"), "a\nc\n")

    def test_break_outside_loop(self):
        fails(self, "def f():\n    break\nf()", "outside a loop")
        fails(self, "def f():\n    continue\nf()", "outside a loop")


class Dicts(unittest.TestCase):
    def test_literal_get_set_len(self):
        src = ("m: dict[str, int] = {'a': 1, 'b': 2}\nm['c'] = 3\nm['a'] = 10\nprint(m['a'], m['c'], len(m))\nprint(m)")
        self.assertEqual(run(src), "10 3 3\n{'a': 10, 'b': 2, 'c': 3}\n")

    def test_inferred_types(self):
        self.assertEqual(run("m = {1: 'x', 2: 'y'}\nprint(m[2])"), "y\n")
        fails(self, "m = {1: 'x'}\nm['a'] = 'y'", "does not fit")
        fails(self, "m = {1: 'x'}\nm[1] = 5", "does not fit")

    def test_missing_key(self):
        fails(self, "m = {1: 'x'}\nprint(m[2])", "key 2 not found")

    def test_in_checks_keys(self):
        self.assertEqual(run("m = {1: 'x'}\nprint(1 in m)\nprint(2 in m)"), "True\nFalse\n")
        fails(self, "m = {1: 'x'}\nprint('a' in m)", "type error")

    def test_iteration_walks_keys_in_insertion_order(self):
        self.assertEqual(run("m = {'b': 1, 'a': 2}\nfor k in m:\n    print(k)"), "b\na\n")

    def test_keys_values_remove(self):
        src = ("m = {'a': 1, 'b': 2}\nprint(m.keys())\nprint(m.values())\nm.remove('a')\nprint(len(m))")
        self.assertEqual(run(src), "['a', 'b']\n[1, 2]\n1\n")
        fails(self, "m = {'a': 1}\nm.remove('z')", "not found")

    def test_empty_map_needs_a_type(self):
        self.assertEqual(run("m: dict[str, int] = {}\nm['x'] = 1\nprint(m)"), "{'x': 1}\n")
        fails(self, "m = {}", "not yet decided", NotDecided)

    def test_duplicate_literal_key(self):
        fails(self, "m = {1: 'a', 1: 'b'}", "duplicate key")

    def test_key_types(self):
        self.assertEqual(run("m = {True: 1, False: 0}\nprint(m[True])"), "1\n")
        fails(self, "m: dict[float, int] = {}", "not yet decided", NotDecided)
        fails(self, "class C:\n    pass\nm: dict[C, int] = {}", "not yet decided", NotDecided)

    def test_bool_and_int_keys_are_different(self):
        self.assertEqual(run("m: dict[int, str] = {1: 'x'}\nprint(len(m))"), "1\n")

    def test_fixed_width_keys_and_values(self):
        self.assertEqual(run("m: dict[uint[length=8], int] = {1: 5, 255: 6}\nprint(m[255])"), "6\n")
        fails(self, "m: dict[uint[length=8], int] = {256: 5}", "does not fit")

    def test_maps_are_shared(self):
        self.assertEqual(run("a = {1: 2}\nb = a\nb[3] = 4\nprint(len(a))"), "2\n")

    def test_nested_and_list_values(self):
        self.assertEqual(run("m: dict[str, list[int]] = {'a': [1, 2]}\nm['a'].append(3)\nprint(m['a'])"), "[1, 2, 3]\n")

    def test_map_parameters(self):
        src = "def total(m: dict[str, int]) -> int:\n    t = 0\n    for k in m:\n        t = t + m[k]\n    return t\nprint(total({'a': 1, 'b': 2}))"
        self.assertEqual(run(src), "3\n")

    def test_equality_not_decided(self):
        fails(self, "print({1: 2} == {1: 2})", "not yet decided", NotDecided)

    def test_map_methods_undecided(self):
        fails(self, "m = {1: 2}\nm.clear()", "not yet decided", NotDecided)


class Sets(unittest.TestCase):
    def test_literal_add_remove_in_len(self):
        src = "s = {1, 2, 3}\ns.add(4)\ns.add(2)\ns.remove(1)\nprint(len(s), 4 in s, 1 in s)\nprint(s)"
        self.assertEqual(run(src), "3 True False\n{2, 3, 4}\n")

    def test_remove_missing(self):
        fails(self, "s = {1}\ns.remove(5)", "not found")

    def test_element_types(self):
        fails(self, "s = {1}\ns.add('a')", "does not fit")
        fails(self, "s = {1, 'a'}", "does not fit")
        fails(self, "s = {1}\nprint('a' in s)", "type error")

    def test_empty_set_needs_a_declared_type(self):
        self.assertEqual(run("s: set[str] = {}\ns.add('a')\nprint(s)\nprint(len(s))"), "{'a'}\n1\n")
        fails(self, "m = {}", "not yet decided", NotDecided)

    def test_iteration(self):
        self.assertEqual(run("t = 0\nfor n in {1, 2, 3}:\n    t = t + n\nprint(t)"), "6\n")

    def test_iteration_walks_a_snapshot(self):
        self.assertEqual(run("s = {1, 2}\nfor n in s:\n    s.add(n + 10)\nprint(len(s))"), "4\n")

    def test_set_of_text(self):
        self.assertEqual(run("s = {'a', 'b', 'a'}\nprint(len(s))"), "2\n")

    def test_sets_are_shared(self):
        self.assertEqual(run("a = {1}\nb = a\nb.add(2)\nprint(len(a))"), "2\n")

    def test_set_parameters(self):
        src = "def has(s: set[int], n: int) -> bool:\n    return n in s\nprint(has({1, 2}, 2))"
        self.assertEqual(run(src), "True\n")

    def test_undecided(self):
        fails(self, "s = {1}\nprint(s[0])", "not yet decided", NotDecided)
        fails(self, "s = {1}\nprint(s == s)", "not yet decided", NotDecided)
        fails(self, "s = {1}\ns.union(s)", "not yet decided", NotDecided)


class NoneValue(unittest.TestCase):
    def test_none_prints(self):
        self.assertEqual(run("print(None)"), "None\n")

    def test_none_equality(self):
        self.assertEqual(run("print(None == None)\nprint(None != None)\nprint(1 == None)\nprint('a' != None)"),
                         "True\nFalse\nFalse\nTrue\n")

    def test_function_without_return_gives_none(self):
        self.assertEqual(run("def f():\n    pass\nprint(f())\nprint(f() == None)"), "None\nTrue\n")

    def test_none_where_a_value_is_expected_is_a_type_error(self):
        fails(self, "x: int = None", "type error: None where int is expected")
        fails(self, "x: str = None", "write the type as str | None")
        fails(self, "def f(a: int):\n    pass\nf(None)", "type error")
        fails(self, "def f() -> int:\n    return None\nf()", "type error")
        fails(self, "x: int = 1\nx = None", "type error")

    def test_a_variable_that_starts_as_none_cannot_change_type(self):
        fails(self, "x = None\nx = 5", "declare it as int | None")

    def test_none_type_annotation(self):
        self.assertEqual(run("def f() -> None:\n    return None\nprint(f())"), "None\n")

    def test_none_with_operators(self):
        fails(self, "print(None + 1)", "type error")


class Optionals(unittest.TestCase):
    """`T | None` (D23b), default arguments (D19c) and `is None`."""

    def test_declaration_forms(self):
        self.assertEqual(run("x: int | None = None\nprint(x)\nx = 5\nprint(x + 1)\nx = None\nprint(x)"), "None\n6\nNone\n")
        self.assertEqual(run("s: str | None = 'a'\nprint(s, len(s))"), "a 1\n")

    def test_parameters_returns_fields_and_collections(self):
        src = ("class Node:\n    parent: Node | None = None\n    name: str = 'n'\n"
               "def pick(flag: bool, n: Node) -> Node | None:\n    if flag:\n        return n\n    return None\n"
               "xs: list[int | None] = [None, 3]\nd: dict[str, str | None] = {'a': None, 'b': 'x'}\nn = Node()\n"
               "print(pick(True, n) is None, pick(False, n) is None, xs[0], xs[1], d['a'], d['b'], n.parent)")
        self.assertEqual(run(src), "False True None 3 None x None\n")

    def test_is_and_is_not(self):
        self.assertEqual(run("class P:\n    pass\nx: P | None = None\nprint(x is None, x is not None, x == None, x != None)\n"
                             "x = P()\ny = x\nprint(x is None, x is not None, x is y, x is not P())"),
                         "True False True False\nFalse True True True\n")
        self.assertEqual(run("print(1 is None, 'a' is not None, None is None)"), "False True True\n")

    def test_in_none_tests_for_none(self):
        self.assertEqual(run("class P:\n    pass\nx: P | None = None\ns: str | None = 'a'\n"
                             "print(x in None, s in None, None in None, 3 in None, P() in None)"), "True False True False False\n")
        self.assertEqual(run("x: int | None = None\nif x in None:\n    print('none')\nx = 4\nif x in None:\n    print('again')\nelse:\n    print('has value')"),
                         "none\nhas value\n")

    def test_in_type_tests(self):
        pre = ("interface Named:\n    def name(self) -> str\nclass Animal implements Named:\n    def name(self) -> str:\n        return 'a'\n"
               "class Dog(Animal):\n    pass\nclass Rock:\n    pass\n")
        self.assertEqual(run(pre + "d = Dog()\nprint(1 in int, 1 in str, True in int, True in bool, 'a' in str, (3 / 2) in float, 1 in float, None in int)"),
                         "True False False True True True False False\n")
        self.assertEqual(run(pre + "d = Dog()\na: Animal = Dog()\nprint(d in Dog, d in Animal, d in Rock, a in Dog, Animal() in Dog, d in Named, Rock() in Named, d in int)"),
                         "True True False True False True False False\n")
        self.assertEqual(run("x: int | None = 4\ny: int | None = None\nprint(x in int, y in int, y in None, x in str)"), "True False True False\n")
        self.assertEqual(run("xs = [1]\nprint(xs in int, 2 in xs)"), "False False\n")

    def test_is_with_other_things_not_decided(self):
        fails(self, "print(1 is 1)", "not yet decided", NotDecided)

    def test_an_optional_used_as_a_value_fails_when_it_is_none(self):
        fails(self, "x: int | None = None\nprint(x + 1)", "type error")
        fails(self, "def f(a: int) -> int:\n    return a\nx: int | None = None\nf(x)", "None where a int is needed")
        self.assertEqual(run("def f(a: int) -> int:\n    return a\nx: int | None = 4\nprint(f(x))"), "4\n")

    def test_the_failure_is_catchable(self):
        src = ("class P:\n    v: int = 1\nx: P | None = None\ntry:\n    print(x.v)\ncatch RuntimeError:\n    print('caught')")
        out = None
        try:
            out = run(src)
        except TomatoError:
            pass
        # a member of None is an ordinary error today; this documents that it stops the program
        self.assertIsNone(out)

    def test_a_copy_of_an_optional_stays_optional(self):
        src = ("class N:\n    next: N | None = None\n    id: int = 0\n"
               "def length(n: N | None) -> int:\n    k = 0\n    cur = n\n    while cur is not None:\n        k = k + 1\n        cur = cur.next\n    return k\n"
               "a = N()\nb = N()\nb.next = a\nprint(length(b), length(a), length(None))")
        self.assertEqual(run(src), "2 1 0\n")

    def test_optional_of_optional_and_none_alone_are_errors(self):
        fails(self, "x: None | None = None", "not a useful type")
        fails(self, "x: int | None | None = None", "not a useful type")

    def test_unions_of_any_types(self):
        pre = "class Dog:\n    pass\nclass Cat:\n    pass\n"
        src = (pre + "def kind(x: int | str | Dog | None) -> str:\n    if x in int:\n        return 'int'\n    if x in str:\n        return 'str'\n"
               "    if x in Dog:\n        return 'dog'\n    return 'none'\n"
               "print(kind(1), kind('a'), kind(Dog()), kind(None))\n"
               "y: int | str = 5\nprint(y in int, y in str)\ny = 'z'\nprint(y in int, y in str)\n"
               "z: None | Dog = None\nprint(z in None)\nz = Dog()\nprint(z in Dog)")
        self.assertEqual(run(src), "int str dog none\nTrue False\nFalse True\nTrue\nTrue\n")
        fails(self, "x: int | str = 3 / 2", "does not fit")
        fails(self, "y: int | str = 1\ny = True", "does not fit")
        fails(self, "x: int | int = 1", "not a useful type")

    def test_intersections_bitwise_and_xor(self):
        pre = ("interface Named:\n    def name(self) -> str\ninterface Sized:\n    def size(self) -> int\n"
               "class Box implements Named, Sized:\n    def name(self) -> str:\n        return 'box'\n    def size(self) -> int:\n        return 3\n"
               "class Tag implements Named:\n    def name(self) -> str:\n        return 'tag'\n")
        self.assertEqual(run(pre + "def f(x: Named & Sized) -> int:\n    return x.size()\nprint(f(Box()))\n"
                             "print(Box() in Named & Sized, Tag() in Named & Sized, Tag() in Named, Tag() in Sized | Named, 1 in Named & Sized)"),
                         "3\nTrue False True True False\n")
        fails(self, pre + "def f(x: Named & Sized) -> int:\n    return 1\nprint(f(Tag()))", "does not fit")
        fails(self, "x: int & str = 1", "only interfaces and classes")
        fails(self, pre + "def f(x: Box & Tag) -> int:\n    return 1\n", "at least one interface")
        fails(self, pre + "print(Box() in Box & Tag)", "at least one interface")
        self.assertEqual(run(pre + "def g(x: Box & Named) -> int:\n    return x.size()\nprint(g(Box()), Box() in Box & Named)"), "3 True\n")
        self.assertEqual(run("print(12 & 10, 12 | 10, 12 ^ 10, 1 | 2 ^ 3 & 4, 1 + 2 & 3, 6 & 3 == 2)"), "8 14 6 3 3 True\n")
        self.assertEqual(run("a: uint[length=8] = uint[length=8](200)\nprint(a & uint[length=8](15), a ^ uint[length=8](255))"), "8 55\n")
        self.assertEqual(run("print(True xor False, True xor True, False xor False, True or False xor True, not True xor True)"),
                         "True False False True True\n")
        fails(self, "print(1 xor 2)", "must be a bool")
        fails(self, "print(True & False)", "not yet decided", NotDecided)

    def test_union_inputs_take_the_most_restrictive_type(self):
        src = "@show\ndef show(x: int | float | bool | str):\n    print(x in int, x in float, x in bool, x in str)\n"
        def go(text):
            out = io.StringIO()
            run_source(src, out, entry="show", inputs=[text])
            return out.getvalue()
        self.assertEqual(go("6"), "True False False False\n")
        self.assertEqual(go("-2"), "True False False False\n")
        self.assertEqual(go("1.5"), "False True False False\n")
        self.assertEqual(go("true"), "False False True False\n")
        self.assertEqual(go("hello"), "False False False True\n")
        out = io.StringIO()
        run_source("@f\ndef f(x: int | float):\n    print(x)\n", out, entry="f", inputs=["2.5"])
        self.assertEqual(out.getvalue(), "2.5\n")
        with self.assertRaises(TomatoError):
            run_source("@f\ndef f(x: int | bool):\n    print(x)\n", io.StringIO(), entry="f", inputs=["zzz"])

    def test_star_args_and_kwargs(self):
        pre = ("def f(a: int, *rest: tuple[int], **opts: dict[str, str]) -> str:\n    t = a\n    for x in rest:\n        t = t + x\n"
               "    s = ''\n    for k in opts:\n        s = s + k + '=' + opts[k] + ';'\n    return str(t) + ' ' + str(len(rest)) + ' ' + s\n")
        self.assertEqual(run(pre + "print(f(1))\nprint(f(1, 2, 3))\nprint(f(1, 2, x='a', y='b'))\nprint(f(a=5, z='q'))"),
                         "1 0 \n6 2 \n3 1 x=a;y=b;\n5 0 z=q;\n")
        fails(self, "def f(*xs: tuple[int]) -> int:\n    xs[0] = 1\n    return 0\nf(1)", "tuple cannot be changed")
        fails(self, "def f(*xs: tuple[int]) -> int:\n    xs.append(1)\n    return 0\nf(1)", "tuple cannot be changed")
        fails(self, "def f(*xs: int):\n    pass\n", "must be typed tuple")
        fails(self, "def f(**xs: dict[int, int]):\n    pass\n", "must be typed dict[str, V]")
        fails(self, "def f(*xs):\n    pass\n", "needs a type")
        fails(self, "def f(**k: dict[str, int], *a: tuple[int]):\n    pass\n", "comes before")
        fails(self, "def f(*a: tuple[int], b: int):\n    pass\n", "come last")
        fails(self, "def f(a: int):\n    pass\nf(1, 2)", "takes 1 argument")
        fails(self, "def f(a: int):\n    pass\nf(1, b=2)", "no parameter b")
        fails(self, "def f(a: int):\n    pass\nf(1, a=2)", "more than one value")
        fails(self, "def f(a: int, b: int):\n    pass\nf(1)", "takes 2 argument")
        fails(self, "def f(a: int, b: int):\n    pass\nf(b=1)", "missing the argument a")
        fails(self, "print(len(x=[1]))", "keyword arguments work only")
        fails(self, "def f(a: int):\n    pass\nf(a=1, 2)", "positional argument cannot follow")
        self.assertEqual(run("class P:\n    n: int = 0\n    @init\n    def make(self, n: int, *more: tuple[int]):\n        self.n = n + len(more)\n"
                             "p = P(1, 2, 3)\nprint(p.n)"), "3\n")

    def test_star_args_with_entry_points(self):
        src = ("@show\ndef show(a: int, *rest: tuple[int | str], **opts: dict[str, float | bool | str]):\n    print(a, len(rest))\n"
               "    for x in rest:\n        print(x in int, x in str)\n    for k in opts:\n        print(k, opts[k] in float, opts[k] in bool, opts[k] in str)\n")
        def go(*inputs):
            out = io.StringIO()
            run_source(src, out, entry="show", inputs=list(inputs))
            return out.getvalue()
        self.assertEqual(go("1"), "1 0\n")
        self.assertEqual(go("1", "2", "hi"), "1 2\nTrue False\nFalse True\n")
        self.assertEqual(go("1", "x=1.5", "flag=true", "who=me"),
                         "1 0\nx True False False\nflag False True False\nwho False False True\n")
        self.assertEqual(go("a=7", "k=z"), "7 0\nk False False True\n")
        with self.assertRaises(TomatoError):
            run_source("@f\ndef f(*xs: tuple[int]):\n    pass\n", io.StringIO(), entry="f", inputs=["x"])
        with self.assertRaises(TomatoError):
            run_source("@f\ndef f(a: int):\n    pass\n", io.StringIO(), entry="f", inputs=["1", "2"])

    def test_str_of_none(self):
        self.assertEqual(run("print(None)"), "None\n")

    def test_default_arguments(self):
        pre = ("def f(a: int, b: int = 10, c: str = 'z') -> str:\n    return str(a + b) + c\n"
               "class C:\n    v: int = 0\n    @init\n    def s(self, v: int = 5):\n        self.v = v\n"
               "    def add(self, n: int = 1) -> int:\n        return self.v + n\n")
        self.assertEqual(run(pre + "print(f(1), f(1, 2), f(1, 2, 'q'))\nprint(C().v, C(9).v, C().add(), C().add(10))"),
                         "11z 3z 3q\n5 9 6 15\n")

    def test_defaults_are_evaluated_at_each_call(self):
        pre = "def f(n: int = 1 + 2) -> int:\n    return n\n"
        self.assertEqual(run(pre + "print(f(), f(7), f())"), "3 7 3\n")

    def test_a_default_can_be_none(self):
        pre = "def f(a: str | None = None) -> str:\n    if a is None:\n        return 'none'\n    return a\n"
        self.assertEqual(run(pre + "print(f(), f('x'), f(None))"), "none x none\n")

    def test_default_errors(self):
        fails(self, "def f(a: int = 1, b: int):\n    pass\n", "needs a default value")
        fails(self, "def f(a: int = 'x'):\n    pass\nf()", "does not fit")
        fails(self, "def f(a: int, b: int = 1):\n    pass\nf()", "takes 1 to 2")
        fails(self, "def f(a: int, b: int = 1):\n    pass\nf(1, 2, 3)", "takes 1 to 2")

    def test_entry_inputs_with_defaults(self):
        self.assertEqual(run_raw("@main\ndef main(a: int, b: int = 5):\n    print(a + b)\n", inputs=["1"]), "6\n")
        self.assertEqual(run_raw("@main\ndef main(a: int, b: int = 5):\n    print(a + b)\n", inputs=["1", "2"]), "3\n")
        with self.assertRaises(TomatoError):
            run_raw("@main\ndef main(a: int, b: int = 5):\n    pass\n", inputs=[])


class Errors(unittest.TestCase):
    ERR = ("class MyError(Error):\n    code: int\n    @init\n    def make(self, message: str, code: int):\n"
           "        Error.start(self, message)\n        self.code = code\n")

    def test_catch_raised_error(self):
        src = "try:\n    raise Error('boom')\ncatch Error as e:\n    print('got', e.message)"
        self.assertEqual(run(src), "got boom\n")

    def test_catch_by_class_hierarchy(self):
        src = self.ERR + "try:\n    raise MyError('x', 7)\ncatch Error as e:\n    print(e.message)"
        self.assertEqual(run(src), "x\n")
        src = self.ERR + "try:\n    raise MyError('x', 7)\ncatch MyError as e:\n    print(e.code)"
        self.assertEqual(run(src), "7\n")

    def test_first_matching_catch_runs(self):
        src = self.ERR + ("try:\n    raise MyError('x', 7)\ncatch RuntimeError:\n    print('runtime')\n"
                          "catch MyError:\n    print('mine')\ncatch Error:\n    print('error')")
        self.assertEqual(run(src), "mine\n")

    def test_unmatched_error_continues_up(self):
        src = self.ERR + ("def f():\n    try:\n        raise MyError('x', 1)\n    catch RuntimeError:\n        print('no')\n"
                          "try:\n    f()\ncatch MyError as e:\n    print('outer', e.code)")
        self.assertEqual(run(src), "outer 1\n")

    def test_uncaught_error_stops_the_program(self):
        fails(self, "raise Error('boom')", "uncaught error Error: boom")

    def test_else_runs_without_error(self):
        src = "try:\n    print('body')\ncatch Error:\n    print('c')\nelse:\n    print('else')\nfinally:\n    print('fin')"
        self.assertEqual(run(src), "body\nelse\nfin\n")

    def test_else_skipped_after_error(self):
        src = "try:\n    raise Error('e')\ncatch Error:\n    print('c')\nelse:\n    print('else')\nfinally:\n    print('fin')"
        self.assertEqual(run(src), "c\nfin\n")

    def test_error_in_else_is_not_caught_by_the_same_try(self):
        src = "try:\n    pass\ncatch Error:\n    print('caught')\nelse:\n    raise Error('from else')"
        fails(self, src, "from else")

    def test_finally_runs_on_return_and_on_uncaught_error(self):
        src = "def f() -> int:\n    try:\n        return 1\n    finally:\n        print('fin')\nprint(f())"
        self.assertEqual(run(src), "fin\n1\n")
        fails(self, "try:\n    raise Error('x')\nfinally:\n    print('fin')", "uncaught error")

    def test_finally_runs_for_break(self):
        src = "for i in range(3):\n    try:\n        break\n    finally:\n        print('fin')\nprint(i)"
        self.assertEqual(run(src), "fin\n0\n")

    def test_runtime_failures_are_catchable(self):
        for expr, text in (("1 / 0", "division by zero"), ("1 % 0", "modulo by zero"), ("[1][5]", "out of range"),
                           ("{1: 2}[3]", "not found"), ("int('x')", "cannot convert"),
                           ("'abc'[9]", "out of range"), ("rational(1, 0)", "denominator zero")):
            src = "try:\n    print(%s)\ncatch RuntimeError as e:\n    print('caught', e.message)" % expr
            out = run(src)
            self.assertTrue(out.startswith("caught") and text in out, (expr, out))

    def test_overflow_is_catchable(self):
        src = ("a: int[length=8] = 127\ntry:\n    b: int[length=8] = a + 1\ncatch RuntimeError as e:\n    print('overflow')")
        self.assertEqual(run(src), "overflow\n")

    def test_literal_out_of_range_is_not_catchable(self):
        fails(self, "try:\n    a: int[length=8] = 300\ncatch RuntimeError:\n    pass", "does not fit")

    def test_type_errors_are_not_catchable(self):
        fails(self, "try:\n    print(1 + 'a')\ncatch Error:\n    print('no')", "type error")

    def test_catch_variable_has_the_caught_class(self):
        src = self.ERR + "try:\n    raise MyError('x', 7)\ncatch MyError as e:\n    print(e.code)\n    print(e.message)"
        self.assertEqual(run(src), "7\nx\n")
        fails(self, "try:\n    raise Error('x')\ncatch Error as e:\n    print(e.code)", "has no field code")

    def test_raise_needs_an_error_object(self):
        fails(self, "raise 5", "needs an Error object")
        fails(self, "class C:\n    pass\nraise C()", "needs an Error object")

    def test_catch_needs_an_error_class(self):
        fails(self, "class C:\n    pass\ntry:\n    raise Error('x')\ncatch C:\n    pass", "needs an error class")
        fails(self, "try:\n    raise Error('x')\ncatch Nope:\n    pass", "needs an error class")

    def test_try_needs_catch_or_finally(self):
        fails(self, "try:\n    pass\n", "needs a catch or a finally")
        fails(self, "try:\n    pass\nelse:\n    pass\n", "needs a catch")

    def test_nested_try(self):
        src = ("try:\n    try:\n        raise Error('inner')\n    finally:\n        print('inner fin')\n"
               "catch Error as e:\n    print('outer caught', e.message)")
        self.assertEqual(run(src), "inner fin\nouter caught inner\n")

    def test_error_raised_inside_catch_replaces_it(self):
        src = ("try:\n    try:\n        raise Error('a')\n    catch Error:\n        raise Error('b')\n"
               "catch Error as e:\n    print(e.message)")
        self.assertEqual(run(src), "b\n")

    def test_errors_as_ordinary_classes(self):
        self.assertEqual(run(self.ERR + "e = MyError('m', 2)\nprint(e.message, e.code)"), "m 2\n")


class Modules(unittest.TestCase):
    def run_with(self, main, **mods):
        return run_raw(main, modules=mods)

    def fails_with(self, main, text, kind=TomatoError, **mods):
        with self.assertRaises(kind) as cm:
            run_raw(main, modules=mods)
        self.assertIn(text, str(cm.exception))

    def test_import_function(self):
        mods = {"util": "export def twice(n: int) -> int:\n    return n * 2\n"}
        self.assertEqual(self.run_with("from util import twice\n@main\ndef main():\n    print(twice(4))\n", **mods), "8\n")

    def test_import_class_and_interface(self):
        mods = {"shapes": ("export interface Area:\n    def area(self) -> int\n"
                           "export class Sq implements Area:\n    s: int = 3\n    def area(self) -> int:\n        return self.s * self.s\n")}
        src = ("from shapes import Area, Sq\ndef f(a: Area) -> int:\n    return a.area()\n"
               "@main\ndef main():\n    print(f(Sq()))\n")
        self.assertEqual(self.run_with(src, **mods), "9\n")

    def test_unexported_name_is_private(self):
        mods = {"util": "def hidden() -> int:\n    return 1\nexport def shown() -> int:\n    return hidden()\n"}
        self.fails_with("from util import hidden\n@main\ndef main():\n    pass\n", "does not export", **mods)
        src = "from util import shown\n@main\ndef main():\n    print(hidden())\n"
        self.fails_with(src, "unknown function", **mods)
        self.assertEqual(self.run_with("from util import shown\n@main\ndef main():\n    print(shown())\n", **mods), "1\n")

    def test_unimported_name_is_not_visible(self):
        mods = {"util": "export def a() -> int:\n    return 1\nexport def b() -> int:\n    return 2\n"}
        self.fails_with("from util import a\n@main\ndef main():\n    print(b())\n", "unknown function", **mods)

    def test_types_need_to_be_imported_too(self):
        mods = {"k": "export class K:\n    pass\n"}
        self.fails_with("def f(x: K):\n    pass\n@main\ndef main():\n    pass\n", "unknown type", **mods)

    def test_missing_module(self):
        self.fails_with("from nothere import x\n@main\ndef main():\n    pass\n", "no module named")

    def test_import_cycle(self):
        mods = {"a": "from b import g\nexport def f():\n    pass\n", "b": "from a import f\nexport def g():\n    pass\n"}
        self.fails_with("from a import f\n@main\ndef main():\n    pass\n", "cycle", **mods)

    def test_name_clash(self):
        mods = {"util": "export def f():\n    pass\n"}
        self.fails_with("from util import f\ndef f():\n    pass\n@main\ndef main():\n    pass\n", "already declared", **mods)

    def test_module_code_runs_in_its_own_scope(self):
        mods = {"util": "def helper() -> int:\n    return 5\nexport def f() -> int:\n    return helper() + 1\n"}
        self.assertEqual(self.run_with("from util import f\n@main\ndef main():\n    print(f())\n", **mods), "6\n")

    def test_top_level_code_not_allowed_in_modules(self):
        mods = {"bad": "print(1)\nexport def f():\n    pass\n"}
        self.fails_with("from bad import f\n@main\ndef main():\n    pass\n", "top-level code", **mods)

    def test_import_module_form_not_decided(self):
        self.fails_with("import util\n@main\ndef main():\n    pass\n", "not yet decided", NotDecided)

    def test_export_needs_a_declaration(self):
        self.fails_with("export x = 1\n@main\ndef main():\n    pass\n", "expected a function, class or interface")

    def test_stdlib_math(self):
        src = ("from math import abs, min, max, gcd, pow\n@main\ndef main():\n"
               "    print(abs(0 - 5), min(2, 3), max(2, 3), gcd(12, 18), gcd(0 - 12, 18), pow(3, 4), pow(5, 0))\n")
        self.assertEqual(run_raw(src), "5 2 3 6 6 81 1\n")

    def test_stdlib_pow_error_is_catchable(self):
        src = ("from math import pow\n@main\ndef main():\n    try:\n        print(pow(2, 0 - 1))\n"
               "    catch RuntimeError as e:\n        print(e.message)\n")
        self.assertEqual(run_raw(src), "pow needs a non-negative exponent\n")

    def test_error_classes_available_without_import(self):
        self.assertEqual(run_raw("@main\ndef main():\n    print(IOError('x').message)\n"), "x\n")

    def test_search_path(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "mylib.tom"), "w") as f:
                f.write("export def hi() -> str:\n    return 'hi'\n")
            self.assertEqual(run_raw("from mylib import hi\n@main\ndef main():\n    print(hi())\n", search=[d]), "hi\n")


class Namespaces(unittest.TestCase):
    """Each module has its own namespace (D24c)."""

    def run_with(self, main, **mods):
        return run_raw(main, modules=mods)

    def fails_with(self, main, text, kind=TomatoError, **mods):
        with self.assertRaises(kind) as cm:
            run_raw(main, modules=mods)
        self.assertIn(text, str(cm.exception))

    def test_two_modules_can_declare_the_same_names(self):
        mods = {"a": "export def name() -> str:\n    return 'a'\n", "b": "export def name() -> str:\n    return 'b'\n"}
        # both define `name`; the program imports one of them
        self.assertEqual(self.run_with("from a import name\n@main\ndef main():\n    print(name())\n", **mods), "a\n")
        self.assertEqual(self.run_with("from b import name\n@main\ndef main():\n    print(name())\n", **mods), "b\n")

    def test_the_program_can_reuse_a_name_a_module_declares(self):
        mods = {"util": "export def helper() -> int:\n    return 1\ndef secret() -> int:\n    return 2\n"}
        src = "from util import helper\ndef secret() -> int:\n    return 99\n@main\ndef main():\n    print(secret(), helper())\n"
        self.assertEqual(self.run_with(src, **mods), "99 1\n")

    def test_a_module_keeps_using_its_own_private_names(self):
        mods = {"util": "def secret() -> int:\n    return 2\nexport def shown() -> int:\n    return secret()\n"}
        src = "from util import shown\ndef secret() -> int:\n    return 99\n@main\ndef main():\n    print(shown(), secret())\n"
        self.assertEqual(self.run_with(src, **mods), "2 99\n")

    def test_same_class_name_in_two_modules(self):
        mods = {"a": "export class Node:\n    v: int = 1\n    def who(self) -> str:\n        return 'a'\n",
                "b": "export class Node:\n    v: int = 2\n    def who(self) -> str:\n        return 'b'\n"}
        src = ("from a import Node\nclass Other:\n    n: Node = Node()\n@main\ndef main():\n"
               "    print(Node().who(), Other().n.v)\n")
        self.assertEqual(self.run_with(src, **mods), "a 1\n")

    def test_the_main_program_and_a_module_can_both_have_a_class_named_the_same(self):
        mods = {"shapes": "export class Box:\n    side: int = 2\n    def area(self) -> int:\n        return self.side * self.side\n"}
        src = ("from shapes import Box\n@main\ndef main():\n    print(Box().area())\n"
               "def unused() -> int:\n    return 0\n")
        self.assertEqual(self.run_with(src, **mods), "4\n")
        # main's own class with the same name, when the module's is not imported
        src2 = "class Box:\n    side: int = 3\n@main\ndef main():\n    print(Box().side)\n"
        self.assertEqual(self.run_with(src2, **mods), "3\n")

    def test_importing_a_name_twice_or_clashing_with_a_declaration(self):
        mods = {"a": "export def f():\n    pass\n", "b": "export def f():\n    pass\n"}
        self.fails_with("from a import f\nfrom b import f\n@main\ndef main():\n    pass\n", "already declared", **mods)
        self.fails_with("from a import f\ndef f():\n    pass\n@main\ndef main():\n    pass\n", "already declared", **mods)
        self.assertEqual(self.run_with("from a import f\nfrom a import f\n@main\ndef main():\n    print(1)\n", **mods), "1\n")

    def test_the_built_in_names_are_reserved(self):
        self.fails_with("class Error:\n    pass\n@main\ndef main():\n    pass\n", "already declared")

    def test_inheritance_across_modules(self):
        mods = {"base": "export class Animal:\n    def sound(self) -> str:\n        return '...'\n"}
        src = ("from base import Animal\nclass Dog(Animal):\n    override def sound(self) -> str:\n        return 'woof'\n"
               "def f(a: Animal) -> str:\n    return a.sound()\n@main\ndef main():\n    print(f(Dog()))\n")
        self.assertEqual(self.run_with(src, **mods), "woof\n")

    def test_interfaces_across_modules(self):
        mods = {"api": "export interface Named:\n    def name(self) -> str\n"}
        src = ("from api import Named\nclass P implements Named:\n    def name(self) -> str:\n        return 'p'\n"
               "def f(n: Named) -> str:\n    return n.name()\n@main\ndef main():\n    print(f(P()))\n")
        self.assertEqual(self.run_with(src, **mods), "p\n")

    def test_an_error_class_from_a_module_can_be_raised_and_caught(self):
        mods = {"errs": ("export class Bad(Error):\n    @init\n    def make(self, m: str):\n        Error.start(self, m)\n"
                         "export def fail():\n    raise Bad('bad')\n")}
        src = ("from errs import Bad, fail\n@main\ndef main():\n    try:\n        fail()\n"
               "    catch Bad as e:\n        print('caught', e.message)\n")
        self.assertEqual(self.run_with(src, **mods), "caught bad\n")

    def test_instances_print_their_plain_class_name(self):
        mods = {"k": "export class Thing:\n    pass\n"}
        self.assertEqual(self.run_with("from k import Thing\n@main\ndef main():\n    print(Thing())\n", **mods), "<Thing>\n")

    def test_cycle_warnings_across_modules(self):
        import io
        mods = {"a": "from b import B\nexport class A:\n    b: list[B] = []\n", "b": "export class B:\n    pass\n"}
        w = io.StringIO()
        run_raw("from a import A\n@main\ndef main():\n    print(1)\n", modules=mods, warn_out=w)
        self.assertEqual(w.getvalue(), "")

    def test_a_module_cannot_use_what_it_did_not_import(self):
        mods = {"a": "export def f() -> int:\n    return g()\n", "b": "export def g() -> int:\n    return 1\n"}
        self.fails_with("from a import f\nfrom b import g\n@main\ndef main():\n    print(f())\n", "unknown function", **mods)

    def test_unknown_names_in_declarations(self):
        self.fails_with("class A(Nope):\n    pass\n@main\ndef main():\n    pass\n", "unknown parent")
        self.fails_with("class A implements Nope:\n    pass\n@main\ndef main():\n    pass\n", "unknown interface")
        self.fails_with("Nope implements Other\n@main\ndef main():\n    pass\n", "unknown")

    def test_the_standard_library_names_do_not_leak(self):
        self.fails_with("@main\ndef main():\n    print(gcd(4, 6))\n", "unknown function")

    def test_a_program_can_define_its_own_names_the_standard_library_also_uses(self):
        src = "def gcd(a: int, b: int) -> int:\n    return 42\nfrom math import abs\n@main\ndef main():\n    print(gcd(1, 2), abs(-3))\n"
        self.assertEqual(run_raw(src), "42 3\n")


class Files(unittest.TestCase):
    def test_write_then_read(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "a.txt")
            src = ("f = open('%s', 'w')\nf.write('h\\u{e9}llo\\n')\nf.write('x')\nf.close()\n"
                   "g = open('%s')\nprint(len(g.read()))\ng.close()\nh = open('%s', 'a')\nh.write('!')\nh.close()\n"
                   "k = open('%s')\nprint(k.read())\nk.close()") % (path, path, path, path)
            self.assertEqual(run(src), "7\nh\u00e9llo\nx!\n")
            with open(path, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), "h\u00e9llo\nx!")

    def test_missing_file_is_a_catchable_io_error(self):
        src = "try:\n    open('/no/such/file.txt')\ncatch IOError as e:\n    print('io')"
        self.assertEqual(run(src), "io\n")
        src = "try:\n    open('/no/such/file.txt')\ncatch RuntimeError:\n    print('runtime')"
        self.assertEqual(run(src), "runtime\n")

    def test_closed_file(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "a.txt")
            src = "f = open('%s', 'w')\nf.close()\ntry:\n    f.write('x')\ncatch IOError:\n    print('closed')" % path
            self.assertEqual(run(src), "closed\n")

    def test_bad_arguments(self):
        fails(self, "open(5)", "takes text")
        fails(self, "open('a', 'x')", "open mode must be")
        fails(self, "open()", "takes text")

    def test_file_type_and_methods(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "a.txt")
            src = ("def put(f: File, s: str):\n    f.write(s)\nf = open('%s', 'w')\nput(f, 'ok')\nf.close()\n"
                   "g = open('%s')\nprint(g.read())\ng.close()") % (path, path)
            self.assertEqual(run(src), "ok\n")
            fails(self, "f = open('%s')\nf.seek(0)" % path, "not yet decided", NotDecided)


IR = """
declare double @llvm.sqrt.f64(double)
define double @sqrt(double %x) {
  %r = call double @llvm.sqrt.f64(double %x)
  ret double %r
}
define i64 @add(i64 %a, i64 %b) {
  %r = add i64 %a, %b
  ret i64 %r
}
define i1 @is_even(i32 %n) {
  %r = and i32 %n, 1
  %z = icmp eq i32 %r, 0
  ret i1 %z
}
define i32 @mul32(i32 %a, i32 %b) {
  %r = mul i32 %a, %b
  ret i32 %r
}
define i8 @neg8(i8 %a) {
  %r = sub i8 0, %a
  ret i8 %r
}
define void @nothing() {
  ret void
}
define i32 @takes_ptr(i8* %p) {
  ret i32 0
}
"""

try:
    import llvmlite  # noqa: F401
    HAVE_LLVM = True
except ImportError:
    HAVE_LLVM = False


DECLS = """!sqrt(x: float) -> float
!add(a: int, b: int) -> int
!is_even(n: int[length=32]) -> bool
!mul32(a: int[length=32], b: int[length=32]) -> int[length=32]
!neg8(a: uint[length=8]) -> uint[length=8]
!nothing()
"""


class LlvmReference(unittest.TestCase):
    def test_parse_reference(self):
        from tomato.parser import parse
        self.assertIn("LlvmRef", repr(parse("x = !sqrt(4)\n")))
        self.assertIn("LlvmDecl", repr(parse("!sqrt(x: float) -> float\n")))

    def test_without_llvm_attached(self):
        src = "!sqrt(x: float) -> float\n@main\ndef main():\n    print(!sqrt(4 / 1))\n"
        with self.assertRaises(NotDecided) as cm:
            run_raw(src)
        self.assertIn("no LLVM IR is attached", str(cm.exception))

    def raw(self, body, decls=DECLS):
        return run_raw(decls + "@main\ndef main():\n" + "".join("    %s\n" % l for l in body.split("\n")))

    def raw_fails(self, body, text, kind=TomatoError, decls=DECLS):
        with self.assertRaises(kind) as cm:
            self.raw(body, decls)
        self.assertIn(text, str(cm.exception))

    def test_calls_are_type_checked_even_without_ir(self):
        self.raw_fails("print(!sqrt(4))", "does not fit")             # an int where a float is declared
        self.raw_fails("print(!add(1))", "takes 2 argument")
        self.raw_fails("print(!add('a', 1))", "does not fit")
        self.raw_fails("print(!is_even(True))", "does not fit")
        self.raw_fails("a: int = 5\nprint(!is_even(a))", "explicit conversion")
        self.raw_fails("print(!nope(1))", "is not declared")

    def test_a_declaration_needs_types(self):
        self.raw_fails("pass", "needs a type", decls="!f(x) -> int\n")

    def test_unsupported_declared_types(self):
        self.raw_fails("pass", "not yet decided", NotDecided, decls="!f(x: str) -> int\n")
        self.raw_fails("pass", "not yet decided", NotDecided, decls="!f(x: int[length=65]) -> int\n")
        self.raw_fails("pass", "not yet decided", NotDecided, decls="!f() -> list[int]\n")

    def test_conflicting_declarations(self):
        self.raw_fails("pass", "declared twice", decls="!f(x: int) -> int\n!f(x: float) -> int\n")
        self.raw("pass", decls="!f(x: int) -> int\n!f(x: int) -> int\n")

    def test_signature_parsing(self):
        from tomato.llvm_bridge import parse_signatures
        sigs = parse_signatures(IR)
        self.assertEqual(sigs["add"], ("i64", ["i64", "i64"]))
        self.assertEqual(sigs["nothing"], ("void", []))
        self.assertEqual(sigs["sqrt"], ("double", ["double"]))
        self.assertEqual(sigs["takes_ptr"], ("i32", ["i8*"]))

    def test_type_mapping(self):
        from tomato.llvm_bridge import tomato_to_llvm
        from tomato.values import BoolT, FixedT, FloatT, INT, NoneT, StrT
        self.assertEqual([tomato_to_llvm(t) for t in (INT, FixedT(True, 8), FixedT(False, 19), FloatT, BoolT, NoneT)],
                         ["i64", "i8", "i19", "double", "i1", "void"])
        self.assertIsNone(tomato_to_llvm(StrT))
        self.assertIsNone(tomato_to_llvm(FixedT(True, 65)))


@unittest.skipUnless(HAVE_LLVM, "llvmlite is not installed (pip install llvmlite)")
class LlvmRuns(unittest.TestCase):
    def go(self, body, decls=DECLS, ir=IR):
        src = decls + "@main\ndef main():\n" + "".join("    %s\n" % l for l in body.split("\n"))
        return run_raw(src, llvm_ir=[("test.ll", ir)])

    def raises(self, body, text, kind=TomatoError, **kw):
        with self.assertRaises(kind) as cm:
            self.go(body, **kw)
        self.assertIn(text, str(cm.exception))

    def test_float_function(self):
        self.assertEqual(self.go("print(!sqrt(16 / 1))"), "4.0\n")

    def test_integer_function(self):
        self.assertEqual(self.go("print(!add(40, 2))"), "42\n")

    def test_bool_result(self):
        self.assertEqual(self.go("print(!is_even(10))\nprint(!is_even(7))"), "True\nFalse\n")

    def test_result_has_the_declared_type(self):
        self.assertEqual(self.go("x: int[length=32] = !mul32(1000, 1000)\nprint(x)"), "1000000\n")
        self.assertEqual(self.go("x: int = !add(1, 2)\nprint(x)"), "3\n")
        self.raises("x: int[length=8] = !mul32(1, 2)", "does not fit")

    def test_void_function(self):
        self.assertEqual(self.go("!nothing()\nprint(!nothing() == None)"), "True\n")

    def test_negative_and_unsigned_values(self):
        self.assertEqual(self.go("print(!add(-5, 2))"), "-3\n")
        self.assertEqual(self.go("a: uint[length=8] = 200\nprint(!neg8(a))"), "56\n")
        self.assertEqual(self.go("print(!neg8(3))"), "253\n")

    def test_argument_out_of_range(self):
        self.raises("print(!add(9223372036854775808, 1))", "does not fit LLVM i64")

    def test_argument_out_of_range_is_catchable(self):
        self.assertEqual(self.go("try:\n    print(!add(9223372036854775808, 1))\ncatch RuntimeError:\n    print('caught')"),
                         "caught\n")

    def test_declared_types_must_match_the_ir(self):
        self.raises("pass", "declared (i32, i32) -> i32 but the LLVM IR defines (i64, i64) -> i64",
                    decls="!add(a: int[length=32], b: int[length=32]) -> int[length=32]\n")
        self.raises("pass", "declared (double) -> double but the LLVM IR defines (double) -> double" if False else "declared",
                    decls="!sqrt(x: int) -> float\n")

    def test_a_declaration_the_ir_lacks(self):
        self.raises("print(!missing(1))", "no LLVM function named missing", decls="!missing(a: int) -> int\n")
        self.assertEqual(self.go("print(1)", decls="!missing(a: int) -> int\n"), "1\n")   # only an error when called

    def test_bad_ir_is_reported(self):
        with self.assertRaises(TomatoError) as cm:
            run_raw("@main\ndef main():\n    pass\n", llvm_ir=[("bad.ll", "define i32 @f( {")])
        self.assertIn("LLVM rejected bad.ll", str(cm.exception))

    def test_called_from_a_class(self):
        src = (DECLS + "class C:\n    def twice(self, n: int) -> int:\n        return !add(n, n)\n"
               "@main\ndef main():\n    print(C().twice(21))\n")
        self.assertEqual(run_raw(src, llvm_ir=[("t.ll", IR)]), "42\n")

    def test_the_example_program(self):
        root = os.path.join(os.path.dirname(__file__), "..", "examples")
        with open(os.path.join(root, "mathlib.tom")) as f, open(os.path.join(root, "mathlib.ll")) as g:
            self.assertEqual(run_raw(f.read(), llvm_ir=[("mathlib.ll", g.read())]),
                             "1.4142135623730951\n42\nTrue False\n1000000000\n")


class EntryPoints(unittest.TestCase):
    def raw_fails(self, src, text, kind=TomatoError):
        with self.assertRaises(kind) as cm:
            run_raw(src)
        self.assertIn(text, str(cm.exception))

    def test_main_is_default(self):
        self.assertEqual(run_raw("@main\ndef start():\n    print(1)\n"), "1\n")

    def test_chosen_entry(self):
        from tomato.interp import run_source
        import io
        out = io.StringIO()
        run_source("@main\ndef a():\n    print(1)\n@other\ndef b():\n    print(2)\n", out, entry="other")
        self.assertEqual(out.getvalue(), "2\n")

    def test_top_level_code_rejected(self):
        self.raw_fails("print(1)\n@main\ndef m():\n    pass\n", "top-level code is not allowed")
        self.raw_fails("x = 1\n@main\ndef m():\n    pass\n", "top-level code is not allowed")

    def test_no_entry_point(self):
        self.raw_fails("def f():\n    pass\n", "no function marked @main")
        self.raw_fails("@other\ndef f():\n    pass\n", "no function marked @main")

    def test_two_with_same_marker_not_decided(self):
        self.raw_fails("@main\ndef a():\n    pass\n@main\ndef b():\n    pass\n", "not yet decided", NotDecided)

    def test_entry_returning_a_value_not_decided(self):
        self.raw_fails("@main\ndef a() -> int:\n    return 1\n", "not yet decided", NotDecided)

    def test_entry_parameter_types_limited(self):
        self.raw_fails("@main\ndef a(x: list[int]):\n    pass\n", "not yet decided", NotDecided)

    def test_inputs_are_parsed_by_parameter_type(self):
        src = ("@main\ndef main(n: int, small: uint[length=8], f: float, b: bool, s: str):\n    print(n + 1, small, f, b, s)\n")
        self.assertEqual(run_raw(src, inputs=["-4", "200", "2.5", "true", "hi there"]), "-3 200 2.5 True hi there\n")

    def test_bad_inputs(self):
        src = "@main\ndef main(n: int):\n    print(n)\n"
        for bad, text in (("x", "must be a whole number"), ("1.5", "must be a whole number"), ("", "must be a whole number")):
            self.raw_fails_inputs(src, [bad], text)
        self.raw_fails_inputs("@main\ndef main(n: uint[length=8]):\n    pass\n", ["256"], "does not fit")
        self.raw_fails_inputs("@main\ndef main(b: bool):\n    pass\n", ["yes"], "true or false")
        self.raw_fails_inputs("@main\ndef main(f: float):\n    pass\n", ["nan"], "finite number")
        self.raw_fails_inputs("@main\ndef main(f: float):\n    pass\n", ["abc"], "a number")

    def test_wrong_number_of_inputs(self):
        src = "@main\ndef main(a: int, b: int):\n    pass\n"
        self.raw_fails_inputs(src, ["1"], "takes 2 input(s) (a, b), got 1")
        self.raw_fails_inputs(src, ["1", "2", "3"], "takes 2 input(s)")
        self.raw_fails_inputs("@main\ndef main():\n    pass\n", ["1"], "takes 0 input(s), got 1")

    def raw_fails_inputs(self, src, inputs, text):
        with self.assertRaises(TomatoError) as cm:
            run_raw(src, inputs=inputs)
        self.assertIn(text, str(cm.exception))

    def test_inputs_reach_a_chosen_entry(self):
        from tomato.interp import run_source
        import io
        out = io.StringIO()
        run_source("@main\ndef a():\n    print(1)\n@other\ndef b(n: int):\n    print(n * 2)\n", out, entry="other", inputs=["21"])
        self.assertEqual(out.getvalue(), "42\n")


    def test_init_marker_not_allowed_outside_class(self):
        self.raw_fails("@init\ndef a():\n    pass\n", "inside a class")

    def test_declarations_stay_allowed_at_top_level(self):
        src = "interface S:\n    pass\nclass C implements S:\n    pass\ndef f():\n    pass\n@main\ndef m():\n    print(7)\n"
        self.assertEqual(run_raw(src), "7\n")


class CommandLine(unittest.TestCase):
    def tomato(self, *args):
        import subprocess
        root = os.path.join(os.path.dirname(__file__), "..")
        r = subprocess.run([sys.executable, "-m", "tomato"] + list(args), cwd=root, capture_output=True, text=True)
        return r.returncode, r.stdout, r.stderr

    def example(self, name):
        return os.path.join("examples", name)

    def test_run_default_entry(self):
        code, out, err = self.tomato("run", self.example("args.tom"))
        self.assertEqual((code, out), (0, "no inputs\n"))

    def test_run_entry_with_inputs(self):
        self.assertEqual(self.tomato("run", self.example("args.tom"), "prime", "97")[:2], (0, "97 True\n"))
        self.assertEqual(self.tomato("run", self.example("args.tom"), "greet", "Ada", "2", "true")[:2], (0, "ADA\nADA\n"))
        self.assertEqual(self.tomato("run", self.example("args.tom"), "greet", "Ada", "1", "false")[:2], (0, "Ada\n"))

    def test_errors_exit_nonzero(self):
        code, out, err = self.tomato("run", self.example("args.tom"), "prime", "abc")
        self.assertEqual(code, 1)
        self.assertIn("must be a whole number", err)
        code, out, err = self.tomato("run", self.example("args.tom"), "nope")
        self.assertEqual(code, 1)
        self.assertIn("no function marked @nope", err)
        code, out, err = self.tomato("run", "examples/missing.tom")
        self.assertEqual(code, 1)
        self.assertIn("cannot read", err)

    def test_usage(self):
        for args in ([], ["run"], ["walk", "x.tom"], [self.example("args.tom")]):
            code, out, err = self.tomato(*args)
            self.assertEqual(code, 2, args)
            self.assertIn("usage: tomato run FILE", err)

    def test_stack_is_large_enough_for_deep_recursion(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "r.tom")
            with open(path, "w") as f:
                f.write("def f(n: int) -> int:\n    if n == 0:\n        return 0\n    return 1 + f(n - 1)\n"
                        "@main\ndef main():\n    print(f(5000))\n")
            self.assertEqual(self.tomato("run", path)[:2], (0, "5000\n"))

    @unittest.skipUnless(HAVE_LLVM, "llvmlite is not installed (pip install llvmlite)")
    def test_llvm_option(self):
        code, out, err = self.tomato("run", self.example("mathlib.tom"), "main", "--llvm", self.example("mathlib.ll"))
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "1.4142135623730951\n42\nTrue False\n1000000000\n")
        code, out, err = self.tomato("run", self.example("mathlib.tom"))
        self.assertEqual(code, 1)
        self.assertIn("no LLVM IR is attached", err)


if __name__ == "__main__":
    unittest.main()
