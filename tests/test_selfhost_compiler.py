"""The compiler slice in selfhost/compiler.tom (D38a): its LLVM IR, built with clang, must behave like the interpreter."""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))
from tomato.errors import TomatoError  # noqa: E402
from tomato.interp import run_source  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SELF = os.path.join(ROOT, "selfhost")

PROGRAMS = {
    "sets": """def distinct(words: list[str]) -> int:
    seen: set[str] = {}
    for w in words:
        seen.add(w)
    return len(seen)

@main
def main():
    ws = ['a', 'b', 'a', 'c', 'b']
    print(distinct(ws))
    nums: set[int] = {3, 1, 2}
    nums.add(5)
    nums.add(3)
    nums.remove(1)
    total = 0
    for n in nums:
        total = total + n
    print(len(nums), 5 in nums, 1 in nums, total)
    t = {'x', 'y'}
    print('x' in t, 'z' in t, len(t))
    ages: dict[str, int] = {'ann': 3, 'bob': 5}
    for name in ages:
        print(name, ages[name])
    flags: set[bool] = {True}
    print(True in flags, False in flags)
""",
    "interfaces_and_override": """interface Shape:
    def area(self) -> int
    def name(self) -> str

interface Solid(Shape):
    def volume(self) -> int

class Square:
    side: int = 2

    def area(self) -> int:
        return self.side * self.side

    def name(self) -> str:
        return 'square'

class Cube(Square):
    def volume(self) -> int:
        return self.side * self.area()

    override def name(self) -> str:
        return 'cube'

class Rect implements Shape:
    w: int = 2
    h: int = 3

    def area(self) -> int:
        return self.w * self.h

    def name(self) -> str:
        return 'rect'

Square implements Shape
Cube implements Solid

def describe(s: Shape) -> str:
    return s.name() + str(s.area())

def volumes(xs: list[Solid]) -> int:
    t = 0
    for x in xs:
        t = t + x.volume()
    return t

def show(sq: Square) -> str:
    return sq.name()

@main
def main():
    shapes: list[Shape] = [Square(), Rect(), Cube()]
    for s in shapes:
        print(describe(s))
    c = Cube()
    c.side = 3
    print(c.volume(), show(c), show(Square()), volumes([c, Cube()]))
""",
    "floats": """def half(n: int) -> float:
    return n / 2

def average(a: int, b: int) -> float:
    return (a + b) / 2

class Stat:
    mean: float = 0 / 1

@main
def main():
    x = half(7)
    s = Stat()
    s.mean = average(3, 4)
    print(x, half(10), s.mean, 1 / 3, str(x) + '!')
    y: float = 22 / 7
    print(y)
""",
    "dicts": """class Table:
    names: dict[str, int] = {}
    labels: dict[str, str] = {}

    def add(self, k: str, v: int):
        self.names[k] = v
        self.labels[k] = 'L' + str(v)

def lookup(t: Table, k: str) -> int:
    if k in t.names:
        return t.names[k]
    return 0 - 1

@main
def main():
    t = Table()
    t.add('a', 1)
    t.add('bb', 22)
    t.add('a', 3)
    print(len(t.names), lookup(t, 'a'), lookup(t, 'bb'), lookup(t, 'z'), t.labels['a'], 'bb' in t.labels, 'q' in t.labels)
    m: dict[str, str] = {'x': 'y', 'z': 'w'}
    print(m['x'] + m['z'], len(m))
""",
    "defaults": """def greet(name: str, times: int = 2, loud: bool = False) -> str:
    out = ''
    for i in range(times):
        out = out + name + ' '
    if loud:
        return out + '!'
    return out

class Box:
    v: str = ''

    @init
    def make(self, v: str, w: str = 'w'):
        self.v = v + w

@main
def main():
    who = 'bob'
    n = 3
    print(greet(who), greet(who, n), greet(who, 1, True), Box('a').v, Box('a', 'b').v)
""",
    "optionals": """class Node:
    value: int = 0
    next: Node | None = None

def push(head: Node | None, v: int) -> Node:
    n = Node()
    n.value = v
    n.next = head
    return n

def length(head: Node | None) -> int:
    k = 0
    cur = head
    while cur is not None:
        k = k + 1
        cur = cur.next
    return k

def first(head: Node | None) -> int:
    return head.value

def name_of(s: str | None) -> str:
    if s is None:
        return 'none'
    return s + '!'

@main
def main():
    h = push(push(push(None, 1), 2), 3)
    print(length(h), length(None), h.value, h.next.value, name_of('a'), name_of(None))
    x: Node | None = None
    print(x is None, x == None, h.next is not None)
    x = h
    print(x is None, first(x))
""",
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

    def ir_by_interpreter(self, path, entry="main"):
        src = open(os.path.join(SELF, "ctool.tom")).read()
        out = io.StringIO()
        run_source(src, out, entry="compile", inputs=[path, entry], search=[SELF])
        return out.getvalue()

    def ir_by_native(self, path, entry="main"):
        return subprocess.run([self.native, path, entry], check=True, capture_output=True, text=True).stdout

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

    def test_the_lexer_built_by_the_tomato_compiler(self):
        """Milestone: the Tomato compiler compiles the Tomato lexer (with its imports), and the result lexes like Python's."""
        if self.native is None:
            self.skipTest("clang is not installed")
        from test_selfhost import python_tokens
        path = os.path.join(SELF, "lextool.tom")
        ir = self.ir_by_interpreter(path, "show")
        self.assertEqual(self.ir_by_native(path, "show"), ir)
        ll = os.path.join(self.dir, "lextool.ll")
        with open(ll, "w") as f:
            f.write(ir)
        exe = os.path.join(self.dir, "lextool")
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll, os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c"), "-lm"],
                       check=True, capture_output=True)
        import glob
        for f in sorted(glob.glob(os.path.join(ROOT, "examples", "*.tom")) + glob.glob(os.path.join(SELF, "*.tom"))):
            with self.subTest(file=os.path.basename(f)):
                run = subprocess.run([exe, f], check=True, capture_output=True, text=True)
                self.assertEqual(run.stderr, "")
                self.assertEqual(run.stdout.split("\n")[:-1], python_tokens(open(f).read()))

    def test_the_parser_built_by_the_tomato_compiler(self):
        """Milestone: the Tomato compiler compiles the Tomato parser; the result builds the Python parser's trees."""
        if self.native is None:
            self.skipTest("clang is not installed")
        from test_selfhost_parser import dump
        from tomato.parser import parse
        path = os.path.join(SELF, "parsetool.tom")
        ir = self.ir_by_interpreter(path, "show")
        self.assertEqual(self.ir_by_native(path, "show"), ir)
        ll = os.path.join(self.dir, "parsetool.ll")
        with open(ll, "w") as f:
            f.write(ir)
        exe = os.path.join(self.dir, "parsetool")
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll, os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c"), "-lm"],
                       check=True, capture_output=True)
        import glob
        for f in sorted(glob.glob(os.path.join(ROOT, "examples", "*.tom")) + glob.glob(os.path.join(SELF, "*.tom"))):
            with self.subTest(file=os.path.basename(f)):
                run = subprocess.run([exe, f], check=True, capture_output=True, text=True)
                self.assertEqual(run.stderr, "")
                self.assertEqual(run.stdout.rstrip("\n"), dump(parse(open(f).read())))

    def test_try_catch(self):
        if self.native is None:
            self.skipTest("clang is not installed")
        src = """class MyError(Error):
    @init
    def make(self, message: str, code: int):
        Error.start(self, message)
        self.code = code

    code: int = 0

def risky(n: int) -> int:
    if n < 0:
        raise MyError('negative', n)
    if n == 0:
        raise RuntimeError('zero')
    return n * 2

def guarded(n: int) -> str:
    try:
        v = risky(n)
        return 'ok ' + str(v)
    catch MyError as e:
        return 'mine ' + e.message + str(e.code)
    catch RuntimeError as e:
        return 'runtime ' + e.message
    finally:
        print('finally', n)

def loop() -> int:
    total = 0
    for i in range(5):
        try:
            if i == 1:
                continue
            if i == 3:
                break
            total = total + i
        finally:
            total = total + 100
    return total

def nested() -> str:
    try:
        try:
            risky(0)
        catch MyError:
            return 'wrong'
        finally:
            print('inner finally')
    catch Error as e:
        return 'outer ' + e.message
    return 'none'

def with_else(n: int) -> str:
    out = ''
    try:
        v = risky(n)
        out = 'v' + str(v)
    catch Error:
        out = 'err'
    else:
        out = out + ' else'
    return out

@main
def main():
    print(guarded(4))
    print(guarded(0 - 2))
    print(guarded(0))
    print(loop())
    print(nested())
    print(with_else(3), with_else(0))
    try:
        risky(0 - 1)
    catch MyError as e:
        print('caught', e.code)
    risky(0)
    print('not reached')
"""
        path = self.write("trycatch", src)
        out = io.StringIO()
        with self.assertRaises(TomatoError):
            run_source(src, out)
        ir = self.ir_by_interpreter(path)
        self.assertEqual(self.ir_by_native(path), ir)
        ll = os.path.join(self.dir, "trycatch.ll")
        with open(ll, "w") as f:
            f.write(ir)
        exe = os.path.join(self.dir, "trycatch")
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll, os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c"), "-lm"],
                       check=True, capture_output=True)
        run = subprocess.run([exe], capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout, out.getvalue())
        self.assertIn("uncaught error RuntimeError: zero", run.stderr)

    def test_unsupported_programs_say_so(self):
        for src, text in (("@main\ndef main():\n    x: tuple[int] = [1]\n", "only declares"),
                          ("@main\ndef main():\n    print([1])\n", "does not print lists"),
                          ("@main\ndef main():\n    xs: list[int] = []\n    xs.append('a')\n", "type error"),
                          ("@main\ndef main():\n    xs = []\n", "empty list needs a declaration"),
                          ("@main\ndef main():\n    x: str = 1\n", "type error"),
                          ("class A:\n    x: int = 0\n@main\ndef main():\n    a = A()\n    a.y = 1\n", "has no field y"),
                          ("class A:\n    def f(self):\n        pass\nclass B(A):\n    def f(self):\n        pass\n@main\ndef main():\n    pass\n", "write `override def`"),
                          ("class A:\n    def f(self):\n        pass\nclass B(A):\n    override def g(self):\n        pass\n@main\ndef main():\n    pass\n", "the parent has no such method"),
                          ("interface I:\n    def f(self) -> int\nclass A implements I:\n    pass\n@main\ndef main():\n    pass\n", "lacks method f required by I"),
                          ("@main\ndef main():\n    print('a' + 1)\n", "type error"),
                          ("def f():\n    pass\n", "no function marked @main"),
                          ("@main\ndef main():\n    x = 1 / 2\n    print(x + x)\n", "type error")):
            with self.subTest(src=src):
                path = self.write("bad", src)
                with self.assertRaises(TomatoError) as cm:
                    self.ir_by_interpreter(path)
                self.assertIn(text, str(cm.exception))


if __name__ == "__main__":
    unittest.main()
