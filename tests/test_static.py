"""Checks made before a program runs (D04a, D05x, D05ac, D05ap): errors are found even in code that never executes."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))
os.environ["PYTHONPATH"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python")
from test_tomato import fails, run  # noqa: E402


class Constants(unittest.TestCase):
    def test_constant_division_by_zero_in_dead_code(self):
        fails(self, "if False:\n    print(5 / 0)", "division by zero")
        fails(self, "def f() -> float:\n    return 0 / 0\nprint(1)", "division by zero")

    def test_constant_out_of_range_in_dead_code(self):
        fails(self, "if False:\n    x: uint[length=8] = 300\n    print(x)", "does not fit")
        fails(self, "if False:\n    print(int[length=8](200))", "does not fit")

    def test_constant_rational_zero_denominator_in_dead_code(self):
        fails(self, "if False:\n    print(rational(1, 0))", "denominator zero")

    def test_runtime_zero_still_fails_at_run_time(self):
        fails(self, "z: int = 0\nprint(1)\nprint(5 / z)", "division by zero")

    def test_valid_constants_still_run(self):
        self.assertEqual(run("x: uint[length=8] = 100 + 155\nprint(x)"), "255\n")


class Types(unittest.TestCase):
    def test_wrong_assignment_in_unreachable_code(self):
        fails(self, "x: int = 3\nif False:\n    x = 's'\nprint(x)", "does not fit")

    def test_wrong_declaration(self):
        fails(self, "if False:\n    x: str = 3", "does not fit")

    def test_wrong_return_type(self):
        fails(self, "def f() -> int:\n    return 'a'\nprint(1)", "does not fit")

    def test_wrong_argument_type(self):
        fails(self, "def f(a: int) -> int:\n    return a\nif False:\n    print(f('x'))", "does not fit")

    def test_mixed_operator_types(self):
        fails(self, "if False:\n    print(1 + 'a')", "cannot use +")

    def test_non_bool_condition(self):
        fails(self, "if False:\n    if 3:\n        print(1)", "must be a bool")

    def test_no_output_before_a_static_error(self):
        fails(self, "print('before')\nif False:\n    x: int = 's'", "does not fit")

    def test_valid_programs_are_untouched(self):
        self.assertEqual(run("x: int = 3\nx = x + 1\ny: str = 'a' + 'b'\nprint(x, y)"), "4 ab\n")
        self.assertEqual(run("def f(a: int, b: int = 2) -> int:\n    return a * b\nprint(f(4))"), "8\n")


if __name__ == "__main__":
    unittest.main()
