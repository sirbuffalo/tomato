"""Float literals, mixed whole/float arithmetic, `//` and `**` (P55-P58): the interpreter and the compiled program agree."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))
os.environ["PYTHONPATH"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python")
from test_codegen import CLANG, interpreted, native  # noqa: E402
from test_tomato import fails, run  # noqa: E402

CASES = [
    ("print(1.5)", "1.5\n"),
    ("print(2e3, 2.5e-1, 1E2)", "2000.0 0.25 100.0\n"),
    ("print(1.5 + 2, 2 + 1.5, 3 - 0.5, 4 * 0.5)", "3.5 3.5 2.5 2.0\n"),
    ("print(10 / 4, 10 / 4.0, 10.0 / 4, 1.5 / 0.5)", "2.5 2.5 2.5 3.0\n"),
    ("print(-1.5, -(1.5 + 1))", "-1.5 -2.5\n"),
    ("print(7 // 2, -7 // 2, 7 // -2, -7 // -2, 0 // 5)", "3 -4 -4 3 0\n"),
    ("print(7.5 // 2, -7.5 // 2, 7 // 2.0)", "3.0 -4.0 3.0\n"),
    ("print(7.5 % 2, -7.5 % 2, 7 % 2.5, 7.5 % -2)", "1.5 0.5 2.0 -0.5\n"),
    ("print(2 ** 10, 2 ** 0, 0 ** 0, (-2) ** 3, 3 ** 4)", "1024 1 1 -8 81\n"),
    ("print(2 ** 3 ** 2, -2 ** 2)", "512 -4\n"),
    ("print(2.0 ** -2, 2 ** 0.5 > 1.41, 4 ** 0.5, 9.0 ** 2)", "0.25 True 2.0 81.0\n"),
    ("print(1 == 1.0, 1 < 1.5, 2.5 > 2, 1.0 != 1, 3 <= 3.0)", "True True True False True\n"),
    ("a: int[length=8] = 3\nprint(a ** 4, 17 // a, a + 0.5)", "81 5 3.5\n"),
    ("y = 3\nprint(float(y) / 2, int(7.9), int(-7.9), float(2) + 1)", "1.5 7 -7 3.0\n"),
    ("print(str(1.5) + '!', len(str(2.0)))", "1.5! 3\n"),
]


class Numbers(unittest.TestCase):
    def test_interpreter(self):
        for body, want in CASES:
            self.assertEqual(run(body), want, body)

    @unittest.skipUnless(CLANG, "clang is not installed")
    def test_compiled_matches(self):
        for body, want in CASES:
            src = "@main\ndef main():\n" + "".join("    " + line + "\n" for line in body.split("\n"))
            code, out, err = native(src)
            self.assertEqual((code, out), (0, want), (body, err))
            self.assertEqual(interpreted(src), want, body)

    def test_failures_in_both(self):
        for body, text in [("z: int = 0\nprint(1 // z)", "division by zero"),
                           ("z: float = 0.0\nprint(1.5 / z)", "division by zero"),
                           ("z: float = 0.0\nprint(1.5 // z)", "division by zero"),
                           ("z: float = 0.0\nprint(1.5 % z)", "modulo by zero"),
                           ("n: int = -1\nprint(2 ** n)", "negative power"),
                           ("a: int[length=8] = 3\nn: int = 6\nprint(a ** n)", "does not fit"),
                           ("z: float = 0.0\nn: int = -1\nprint(z ** n)", "division by zero"),
                           ("big: float = 1e200\nprint(big * big)", "float result")]:
            with self.subTest(body):
                if CLANG:
                    src = "@main\ndef main():\n" + "".join("    " + line + "\n" for line in body.split("\n"))
                    code, out, err = native(src)
                    self.assertNotEqual(code, 0)
                    self.assertIn("error", err, body)
                fails(self, body, text.split()[0] if "negative" not in text else "negative")

    @unittest.skipUnless(CLANG, "clang is not installed")
    def test_whole_power_overflow_compiled(self):
        # compiled whole numbers are 64-bit for now (P36), so 2 ** 70 stops where the interpreter would not
        code, out, err = native("@main\ndef main():\n    n: int = 70\n    print(2 ** n)\n")
        self.assertNotEqual(code, 0)
        self.assertIn("overflow", err)

    def test_static_errors(self):
        fails(self, "if False:\n    print(1 // 0)", "division by zero")
        fails(self, "if False:\n    print(2 ** -1)", "negative power")
        fails(self, "if False:\n    x: int = 1.5", "does not fit")
        fails(self, "if False:\n    x: float = 'a'", "does not fit")


if __name__ == "__main__":
    unittest.main()
