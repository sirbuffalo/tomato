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
    "text_methods_in_and_files": """def words(s: str) -> list[str]:
    return s.replace(',', ' ').split(' ')

def count_in(xs: list[str], w: str) -> int:
    n = 0
    for x in xs:
        if x == w:
            n = n + 1
    return n

@main
def main():
    ws = words('a,b c,a')
    print(len(ws), count_in(ws, 'a'), 'b' in ws, 'z' in ws, 3 in [1, 2, 3], 'bc' in 'abcd')
    print(' | '.join(ws), 'hello'.find('ll'), 'hello'.startswith('he'), 'hello'.endswith('x'))
    f = open('/etc/hosts')
    txt = f.read()
    f.close()
    print(len(txt.split('\\n')) > 1)
""",
    "classes": """class Item:
    name: str = 'none'
    qty: int = 0
    tags: list[str] = []

class Inventory:
    items: list[Item] = []
    owner: str = ''

    @init
    def make(self, owner: str):
        self.owner = owner

    def add(self, name: str, qty: int):
        item = Item()
        item.name = name
        item.qty = qty
        item.tags.append(name + '!')
        self.items.append(item)

    def total(self) -> int:
        t = 0
        for item in self.items:
            t = t + item.qty
        return t

    def describe(self) -> str:
        s = self.owner + ':'
        for item in self.items:
            s = s + ' ' + item.name + 'x' + str(item.qty) + item.tags[0]
        return s

def best(inv: Inventory) -> Item:
    top = inv.items[0]
    for item in inv.items:
        if item.qty > top.qty:
            top = item
    return top

@main
def main():
    inv = Inventory('shop')
    inv.add('nut', 3)
    inv.add('bolt', 9)
    inv.add('gear', 5)
    print(inv.total(), len(inv.items), inv.describe())
    print(best(inv).name, best(inv).qty, inv.items[0].name)
    inv.items[0].qty = 100
    print(inv.total())
""",
    "lists": """def total(xs: list[int]) -> int:
    t = 0
    for x in xs:
        t = t + x
    return t

def join_all(ws: list[str]) -> str:
    out = ''
    for w in ws:
        out = out + w + ','
    return out

def squares(n: int) -> list[int]:
    out: list[int] = []
    for i in range(n):
        out.append(i * i)
    return out

@main
def main():
    xs = [3, 1, 4, 1, 5]
    xs[1] = 9
    print(total(xs), len(xs), xs[2], total(squares(5)))
    ws = ['a', 'bc']
    ws.append('d' + 'e')
    ws[0] = 'z'
    print(join_all(ws), len(ws), ws[2])
    bs: list[bool] = [True, False]
    print(bs[0], bs[1], len(bs))
""",
    "text": """
def greet(name: str, times: int) -> str:
    out = ''
    for i in range(times):
        out = out + name + str(i) + ' '
    return out

def shout(s: str) -> str:
    return s + '!'

def first_word(s: str) -> str:
    i = 0
    while i < len(s):
        if s[i] == ' ':
            return s[0:i]
        i = i + 1
    return s

@main
def main():
    g = greet('ab', 3)
    print(g, len(g))
    print(shout(g[0:4]), g[1], 'abc' < 'abd', 'x' == 'x', 5 > 3, 'b' != 'b')
    words = shout('hi') + shout('yo')
    print(words)
    t: str = 'q'
    t = t + t
    print(t, str(42) + str(True))
    print(first_word('alpha beta'), first_word('single'), 'tab\\there', "say \\"hi\\"")
    print(first_word(greet('z', 2))[0:1] + '-' + g[2:])
""",
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
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll, os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c"), "-lm"],
                       check=True, capture_output=True)
        run = subprocess.run([exe], check=True, capture_output=True, text=True)
        self.assertEqual(run.stderr, "", "the program reported a leak or an error")      # debug mode warns about leaks
        return run.stdout

    def test_programs_behave_like_the_interpreter(self):
        if self.native is None:
            self.skipTest("clang is not installed")
        for name, src in PROGRAMS.items():
            with self.subTest(program=name):
                path = self.write(name, src)
                expected = interpreted(src)
                ir = self.ir_by_interpreter(path)
                self.assertEqual(self.run_ir(name + "_i", ir), expected)
                # stage 1: the same compiler, built natively by the Python compiler, writes the same IR
                self.assertEqual(self.ir_by_native(path), ir)

    def test_errors_and_inheritance(self):
        if self.native is None:
            self.skipTest("clang is not installed")
        src = """class NegativeError(Error):
    @init
    def make(self, message: str, value: int):
        Error.start(self, message)
        self.value = value

    value: int = 0

class Base:
    n: int = 1

    def show(self) -> int:
        return self.n

class Derived(Base):
    extra: str = 'x'

def root(n: int) -> int:
    if n < 0:
        raise NegativeError('negative', n)
    r = 0
    while (r + 1) * (r + 1) <= n:
        r = r + 1
    return r

def take(b: Base) -> int:
    return b.show() + b.n

@main
def main():
    d = Derived()
    d.n = 5
    print(take(d), d.show(), d.extra, root(17))
    print(root(0 - 4))
    print('not reached')
"""
        path = self.write("errors", src)
        out = io.StringIO()
        with self.assertRaises(TomatoError) as cm:
            run_source(src, out)
        ir = self.ir_by_interpreter(path)
        self.assertEqual(self.ir_by_native(path), ir)
        ll = os.path.join(self.dir, "errors.ll")
        with open(ll, "w") as f:
            f.write(ir)
        exe = os.path.join(self.dir, "errors")
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll, os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c"), "-lm"],
                       check=True, capture_output=True)
        run = subprocess.run([exe], capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout, out.getvalue())
        self.assertIn("uncaught error NegativeError: negative", run.stderr)
        self.assertIn("uncaught error NegativeError: negative", str(cm.exception))

    def test_unsupported_programs_say_so(self):
        for src, text in (("interface I:\n    def f(self)\n@main\ndef main():\n    print(1)\n", "does not support InterfaceDef"),
                          ("@main\ndef main():\n    print([1])\n", "does not print lists"),
                          ("@main\ndef main():\n    xs: list[int] = []\n    xs.append('a')\n", "type error"),
                          ("@main\ndef main():\n    xs = []\n", "empty list needs a declaration"),
                          ("@main\ndef main():\n    x: str = 1\n", "type error"),
                          ("class A:\n    x: int = 0\n@main\ndef main():\n    a = A()\n    a.y = 1\n", "has no field y"),
                          ("class A:\n    def f(self):\n        pass\nclass B(A):\n    override def f(self):\n        pass\n@main\ndef main():\n    pass\n", "does not support override"),
                          ("@main\ndef main():\n    print('a' + 1)\n", "type error"),
                          ("def f():\n    pass\n", "no function marked @main"),
                          ("@main\ndef main():\n    x = 1 / 2\n", "operator /")):
            with self.subTest(src=src):
                path = self.write("bad", src)
                with self.assertRaises(TomatoError) as cm:
                    self.ir_by_interpreter(path)
                self.assertIn(text, str(cm.exception))


if __name__ == "__main__":
    unittest.main()
