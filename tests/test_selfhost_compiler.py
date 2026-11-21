"""The compiler slice in selfhost/compiler.tom (D38a): its LLVM IR, built with clang, must behave like the interpreter."""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from tomato.errors import TomatoError  # noqa: E402
from tomato.interp import run_source  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SELF = os.path.join(ROOT, "selfhost")

PROGRAMS = {
    "fib_and_primes": """
def fib(n: int) -> int:
    a = 0
    b = 1
    for i in range(n):
        t = a + b
        a = b
        b = t
    return a

def is_prime(n: int) -> bool:
    if n < 2:
        return False
    d = 2
    while d * d <= n:
        if n % d == 0:
            return False
        d = d + 1
    return True

@main
def main():
    print(fib(10), fib(20))
    count = 0
    for k in range(100):
        if is_prime(k):
            count = count + 1
    print(count)
    print(-7 % 3, 7 % -3, 0 - 5, 6 % 3)
""",
    "control_flow": """
def classify(n: int) -> int:
    if n < 0:
        return 0 - 1
    elif n == 0:
        return 0
    elif n < 10:
        return 1
    else:
        return 2

def gcd(a: int, b: int) -> int:
    while b != 0:
        t = a % b
        a = b
        b = t
    return a

def show(n: int):
    print(n, n * n)

@main
def main():
    print(classify(-5), classify(0), classify(7), classify(100))
    print(gcd(84, 36), gcd(17, 5))
    total = 0
    for i in range(3, 8):
        if i == 5:
            continue
        if i == 7:
            break
        total = total + i
    print(total)
    show(6)
    x: int = 4
    flag = x > 3 and x < 10
    print(flag, not flag, 1 == 1 or 2 == 3)
    print()
""",
}


def interpreted(src):
    out = io.StringIO()
    run_source(src, out)
    return out.getvalue()


class SelfhostCompiler(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp()
        cls.native = None
        if shutil.which("clang"):
            cls.native = os.path.join(cls.dir, "ctool")
            subprocess.run([sys.executable, "-m", "tomato", "build", os.path.join(SELF, "ctool.tom"), "--entry", "compile",
                            "-o", cls.native], cwd=ROOT, check=True, capture_output=True)

    def write(self, name, src):
        path = os.path.join(self.dir, name + ".tom")
        with open(path, "w") as f:
            f.write(src)
        return path

    def ir_by_interpreter(self, path):
        src = open(os.path.join(SELF, "ctool.tom")).read()
        out = io.StringIO()
        run_source(src, out, entry="compile", inputs=[path], search=[SELF])
        return out.getvalue()

    def ir_by_native(self, path):
        return subprocess.run([self.native, path], check=True, capture_output=True, text=True).stdout

    def run_ir(self, name, ir):
        ll = os.path.join(self.dir, name + ".ll")
        with open(ll, "w") as f:
            f.write(ir)
        exe = os.path.join(self.dir, name)
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll], check=True, capture_output=True)
        return subprocess.run([exe], check=True, capture_output=True, text=True).stdout

    def test_programs_behave_like_the_interpreter(self):
        if self.native is None:
            self.skipTest("clang is not installed")
        for name, src in PROGRAMS.items():
            with self.subTest(program=name):
                path = self.write(name, src)
                expected = interpreted(src)
                ir = self.ir_by_interpreter(path)
                self.assertEqual(self.run_ir(name + "_i", ir), expected.replace("True", "1").replace("False", "0"))
                # stage 1: the same compiler, built natively by the Python compiler, writes the same IR
                self.assertEqual(self.ir_by_native(path), ir)

    def test_unsupported_programs_say_so(self):
        for src, text in (("class A:\n    pass\n@main\ndef main():\n    print(1)\n", "does not support ClassDef"),
                          ("@main\ndef main():\n    print('a')\n", "does not support StrLit"),
                          ("def f():\n    pass\n", "no function marked @main"),
                          ("@main\ndef main():\n    x = 1 / 2\n", "operator /")):
            with self.subTest(src=src):
                path = self.write("bad", src)
                with self.assertRaises(TomatoError) as cm:
                    self.ir_by_interpreter(path)
                self.assertIn(text, str(cm.exception))


if __name__ == "__main__":
    unittest.main()
