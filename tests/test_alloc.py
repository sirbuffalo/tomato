"""Tests for compiled heap values: reference counting, strings, lists and classes (D29a, D35a)."""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from tomato.codegen import compile_to_ir  # noqa: E402
from tomato.errors import NotDecided, TomatoError  # noqa: E402
from tomato.interp import run_source  # noqa: E402

CLANG = shutil.which("clang")
ROOT = os.path.join(os.path.dirname(__file__), "..")
RUNTIME = os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c")
needs_clang = unittest.skipUnless(CLANG, "clang is not installed")


def native(src, args=(), mode="debug", entry="main", asan=False, env=None):
    """Compile, link and run; with asan=True the program runs under AddressSanitizer, which catches a double
    release or a use after free in the reference counting."""
    ir = compile_to_ir(src, entry=entry, mode=mode)
    with tempfile.TemporaryDirectory() as d:
        ll, exe = os.path.join(d, "p.ll"), os.path.join(d, "p")
        with open(ll, "w") as f:
            f.write(ir)
        flags = ["-fsanitize=address", "-g"] if (asan or os.environ.get("TOMATO_ASAN")) else []
        r = subprocess.run([CLANG, "-O1", "-Wno-override-module"] + flags + ["-x", "ir", ll, "-x", "c", RUNTIME, "-lm", "-o", exe],
                           capture_output=True, text=True)
        if r.returncode:
            raise AssertionError("clang failed:\n" + r.stderr + "\n" + ir)
        run_env = dict(os.environ, **(env or {}))
        r = subprocess.run([exe] + list(args), capture_output=True, text=True, env=run_env)
        return r.returncode, r.stdout, r.stderr


def interpreted(src, args=()):
    out = io.StringIO()
    run_source(src, out, inputs=list(args), warn_out=io.StringIO())
    return out.getvalue()


def prog(body, pre="", params=""):
    return pre + "\n@main\ndef main(%s):\n" % params + "".join("    %s\n" % l for l in body.split("\n"))


@needs_clang
class HeapPrograms(unittest.TestCase):
    """The compiled program prints what the interpreter prints, and frees everything (no leak warning)."""

    def same(self, src, args=()):
        code, out, err = native(src, args)
        self.assertEqual(code, 0, err)
        self.assertEqual(err, "", "leak or warning: " + err)
        self.assertEqual(out, interpreted(src, args))
        return out

    # ---- strings
    def test_concatenation_and_length(self):
        self.same(prog("a = 'ab'\nb = a + 'cd' + a\nprint(b, len(b), len(''))"))

    def test_characters_not_bytes(self):
        self.same(prog("s = 'h\\u{e9}llo \\u{1F345}'\nprint(len(s), s[1], s[6], s[1:3], s[:2], s[5:])"))

    def test_string_comparison(self):
        self.same(prog("print('a' < 'b', 'b' < 'a', 'ab' < 'abc', 'a' == 'a', 'a' != 'a', 'B' < 'a', 'x' >= 'x')"))

    def test_str_conversion(self):
        self.same(prog("print('n=' + str(5) + ' ' + str(0 - 7) + ' ' + str(True) + ' ' + str(1 / 4) + ' ' + str('x'))"))
        self.same(prog("u: uint[length=8] = 250\nprint(str(u), str(100 / 1))"))

    def test_strings_built_in_a_loop(self):
        self.same(prog("s = ''\nfor i in range(50):\n    s = s + str(i) + ','\nprint(len(s), s[0:12])"))

    def test_string_parameters_and_returns(self):
        self.same(prog("print(shout('hey', 3))", pre="def shout(s: str, n: int) -> str:\n    out = s\n    for i in range(n):\n        out = out + '!'\n    return out"))

    def test_string_swap_and_reassign(self):
        self.same(prog("a = 'x'\nb = 'y'\nt = a\na = b\nb = t\nprint(a, b)"))

    def test_string_entry_input(self):
        src = prog("print(s + '!', len(s))", params="s: str")
        code, out, err = native(src, ["h\u00e9llo"])
        self.assertEqual((code, out, err), (0, "h\u00e9llo! 5\n", ""))

    # ---- lists
    def test_list_basics(self):
        self.same(prog("xs = [10, 20, 30]\nxs.append(40)\nxs[1] = 21\nprint(len(xs), xs[0], xs[1], xs[3])"))

    def test_list_of_strings(self):
        self.same(prog("ws: list[str] = ['a', 'b']\nws.append('c' + 'd')\nws[0] = ws[0] + ws[1]\nprint(len(ws), ws[0], ws[2])"))

    def test_for_over_list_and_growth(self):
        self.same(prog("xs: list[int] = []\nfor i in range(100):\n    xs.append(i * i)\nt = 0\nfor x in xs:\n    t = t + x\nprint(len(xs), t)"))

    def test_loop_sees_items_appended_during_it(self):
        self.same(prog("xs = [1]\nn = 0\nfor x in xs:\n    n = n + 1\n    if n < 5:\n        xs.append(x)\nprint(n, len(xs))"))

    def test_nested_lists(self):
        self.same(prog("grid: list[list[int]] = [[1, 2], [3]]\ngrid[1].append(4)\nrow = grid[1]\nprint(len(grid), len(row), grid[1][1])"))

    def test_lists_are_shared(self):
        self.same(prog("a = [1]\nb = a\nb.append(2)\nprint(len(a))"))

    def test_list_parameter_and_return(self):
        self.same(prog("print(len(evens(10)), evens(10)[2])", pre="def evens(n: int) -> list[int]:\n    r: list[int] = []\n    for i in range(n):\n        if i % 2 == 0:\n            r.append(i)\n    return r"))

    def test_fixed_width_items(self):
        self.same(prog("xs: list[uint[length=8]] = [1, 255]\nxs.append(7)\nprint(xs[1], xs[2], len(xs))"))

    def test_list_of_floats_and_bools(self):
        self.same(prog("fs: list[float] = [1 / 2, 1 / 4]\nbs = [True, False]\nprint(fs[1], bs[0], bs[1])"))

    # ---- classes
    COUNTER = ("class Counter:\n    n: int = 0\n    name: str = 'c'\n    def inc(self):\n        self.n = self.n + 1\n"
               "    def label(self) -> str:\n        return self.name + '#' + str(self.n)\n")

    def test_fields_methods_and_defaults(self):
        self.same(prog("c = Counter()\nc.inc()\nc.inc()\nprint(c.label(), c.n, c.name)", pre=self.COUNTER))

    def test_init_and_private_fields(self):
        pre = ("class P:\n    private x: int\n    private who: str\n    @init\n    def start(self, x: int, who: str):\n"
               "        self.x = x\n        self.who = who\n    def show(self) -> str:\n        return self.who + str(self.x)\n"
               "    def same(self, o: P) -> bool:\n        return self.x == o.x\n")
        self.same(prog("a = P(3, 'a')\nb = P(3, 'b')\nprint(a.show(), b.show(), a.same(b))", pre=pre))

    def test_objects_in_fields_and_lists(self):
        pre = ("class Item:\n    v: int = 1\nclass Box:\n    items: list[Item] = []\n    first: Item = Item()\n"
               "    def add(self, v: int):\n        i = Item()\n        i.v = v\n        self.items.append(i)\n"
               "    def total(self) -> int:\n        t = self.first.v\n        for it in self.items:\n            t = t + it.v\n        return t\n")
        self.same(prog("b = Box()\nfor k in range(5):\n    b.add(k)\nprint(b.total(), len(b.items))", pre=pre))

    def test_inheritance_and_dispatch(self):
        pre = ("class Animal:\n    name: str = 'x'\n    def sound(self) -> str:\n        return '...'\n"
               "    def speak(self) -> str:\n        return self.name + ': ' + self.sound()\n"
               "class Dog(Animal):\n    override def sound(self) -> str:\n        return 'woof'\n"
               "class Puppy(Dog):\n    override def sound(self) -> str:\n        return 'yip ' + Dog.sound(self)\n"
               "def talk(a: Animal) -> str:\n    return a.speak()\n")
        self.same(prog("print(talk(Animal()), talk(Dog()), talk(Puppy()))", pre=pre))

    def test_parent_init_chain(self):
        pre = ("class A:\n    private a: int\n    @init\n    def sa(self, a: int):\n        self.a = a\n    def ga(self) -> int:\n        return self.a\n"
               "class B(A):\n    private b: str\n    @init\n    def sb(self, a: int, b: str):\n        A.sa(self, a)\n        self.b = b\n"
               "    def gb(self) -> str:\n        return self.b + str(self.ga())\n")
        self.same(prog("x = B(4, 'b')\nprint(x.gb(), x.ga())", pre=pre))

    def test_class_functions(self):
        pre = "class M:\n    def twice(n: int) -> int:\n        return n * 2\n"
        self.same(prog("print(M.twice(21))", pre=pre))

    def test_object_identity_and_assignment_sharing(self):
        pre = "class C:\n    v: int = 0\n"
        self.same(prog("a = C()\nb = a\nb.v = 5\nc = C()\nprint(a.v, a == b, a == c, a != c)", pre=pre))

    def test_object_passed_and_mutated(self):
        pre = "class C:\n    v: int = 0\ndef bump(c: C):\n    c.v = c.v + 1\n    c = C()\n    c.v = 100\n"
        self.same(prog("a = C()\nbump(a)\nbump(a)\nprint(a.v)", pre=pre))

    def test_many_short_lived_objects(self):
        pre = "class N:\n    v: int = 0\n    s: str = 'x'\ndef make(i: int) -> N:\n    n = N()\n    n.v = i\n    n.s = 'n' + str(i)\n    return n\n"
        self.same(prog("t = 0\nfor i in range(2000):\n    n = make(i)\n    t = t + n.v + len(n.s)\nprint(t)", pre=pre))

    def test_early_return_releases_locals(self):
        pre = ("class C:\n    s: str = 'abc'\ndef f(n: int) -> int:\n    a = C()\n    b = 'x' + str(n)\n"
               "    if n > 2:\n        return len(b) + len(a.s)\n    for i in range(5):\n        c = C()\n        if i == n:\n"
               "            return i\n    return 0 - 1\n")
        self.same(prog("print(f(1), f(3), f(9), f(0 - 1))", pre=pre))

    def test_return_inside_loop_over_list(self):
        pre = "def find(xs: list[str], w: str) -> int:\n    i = 0\n    for x in xs:\n        if x == w:\n            return i\n        i = i + 1\n    return 0 - 1\n"
        self.same(prog("print(find(['a', 'b', 'c'], 'c'), find(['a'], 'z'))", pre=pre))

    def test_break_and_continue_with_heap_values(self):
        self.same(prog("n = 0\nfor w in ['a', 'bb', 'ccc', 'dd']:\n    if len(w) == 2:\n        continue\n    if len(w) == 3:\n        break\n    n = n + len(w)\nprint(n)"))

    def test_recursive_data(self):
        pre = ("class Node:\n    v: int = 0\n    kids: list[Node] = []\n"
               "def build(d: int) -> Node:\n    n = Node()\n    n.v = d\n    if d > 0:\n        for i in range(2):\n            n.kids.append(build(d - 1))\n    return n\n"
               "def total(n: Node) -> int:\n    t = n.v\n    for k in n.kids:\n        t = t + total(k)\n    return t\n")
        self.same(prog("print(total(build(6)))", pre=pre))

    def test_string_equality_in_conditions(self):
        self.same(prog("s = 'a' + 'b'\nif s == 'ab' and not (s != 'ab'):\n    print('eq')\nelse:\n    print('ne')"))


@needs_clang
class ConversionsOperatorsInterfaces(unittest.TestCase):
    def same(self, src, args=()):
        code, out, err = native(src, args)
        self.assertEqual(code, 0, err)
        self.assertEqual(err, "", "leak or warning: " + err)
        self.assertEqual(out, interpreted(src, args))
        return out

    ANIMALS = ("class Animal:\n    name: str = 'a'\nclass Dog(Animal):\n    tricks: int = 3\n"
               "    def count(self) -> int:\n        return self.tricks\n")

    def test_class_conversion_succeeds_when_the_object_is_one(self):
        self.same(prog("a: Animal = Dog()\nd = Dog(a)\nprint(d.count())", pre=self.ANIMALS))

    def test_converting_to_a_parent_or_the_same_class_needs_no_check(self):
        self.same(prog("d = Dog()\na = Animal(d)\nb = Dog(d)\nprint(a.name, b.tricks, a == b)", pre=self.ANIMALS))

    def test_a_failed_conversion_is_a_run_time_error(self):
        src = prog("a = Animal()\nd = Dog(a)\nprint('no')", pre=self.ANIMALS)
        code, out, err = native(src)
        self.assertEqual((code, out), (1, ""))
        self.assertIn("line 11: the object is not an instance of that class", err)
        code, out, err = native(src, mode="normal")
        self.assertEqual(err, "error E08:11\n")

    def test_conversion_in_a_function(self):
        pre = self.ANIMALS + "def tricks(a: Animal) -> int:\n    return Dog(a).count()\n"
        self.same(prog("print(tricks(Dog()))", pre=pre))
        code, out, err = native(prog("print(tricks(Animal()))", pre=pre))
        self.assertEqual(code, 1)

    V = ("class V:\n    x: int = 0\n    y: int = 0\n    @add\n    def plus(self, o: V) -> V:\n        r = V()\n"
         "        r.x = self.x + o.x\n        r.y = self.y + o.y\n        return r\n")

    def test_add_operator(self):
        self.same(prog("a = V()\na.x = 1\nb = V()\nb.x = 2\nb.y = 5\nc = a + b + b\nprint(c.x, c.y)", pre=self.V))

    def test_add_with_a_non_instance_operand(self):
        pre = ("class Money:\n    cents: int = 0\n    @add\n    def plus(self, n: int) -> Money:\n        m = Money()\n"
               "        m.cents = self.cents + n\n        return m\n")
        self.same(prog("m = Money() + 5 + 7\nprint(m.cents)", pre=pre))

    def test_add_is_dispatched_by_the_objects_class(self):
        pre = ("class A:\n    v: int = 1\n    @add\n    def plus(self, o: A) -> A:\n        r = A()\n        r.v = self.v + o.v\n        return r\n"
               "class B(A):\n    pass\n")
        self.same(prog("x: A = B()\ny = x + x\nprint(y.v)", pre=pre))

    def test_add_errors(self):
        self.assertRaises(TomatoError, compile_to_ir, prog("print(C() + C())", pre="class C:\n    pass\n"))
        with self.assertRaises(TomatoError) as cm:
            compile_to_ir(prog("print(1 + V())", pre=self.V))
        self.assertIn("type error", str(cm.exception))
        with self.assertRaises(NotDecided):
            compile_to_ir(prog("print(V() * V())", pre=self.V))

    SHAPES = ("interface Named:\n    def name(self) -> str\ninterface Shape(Named):\n    def area(self) -> int\n"
              "class Sq implements Shape:\n    s: int = 2\n    def name(self) -> str:\n        return 'sq'\n"
              "    def area(self) -> int:\n        return self.s * self.s\n"
              "class Rect implements Shape:\n    w: int = 2\n    h: int = 5\n    def name(self) -> str:\n        return 'rect'\n"
              "    def area(self) -> int:\n        return self.w * self.h\n"
              "class Big(Sq):\n    override def area(self) -> int:\n        return 1000\n"
              "def describe(s: Shape) -> str:\n    return s.name() + str(s.area())\n"
              "def label(n: Named) -> str:\n    return n.name()\n")

    def test_interface_values_dispatch_to_the_real_class(self):
        self.same(prog("shapes: list[Shape] = [Sq(), Rect(), Big()]\nfor s in shapes:\n    print(describe(s), label(s))", pre=self.SHAPES))

    def test_subclasses_inherit_the_interface(self):
        self.same(prog("print(describe(Big()))", pre=self.SHAPES))

    def test_interface_to_class_conversion(self):
        self.same(prog("s: Shape = Rect()\nr = Rect(s)\nprint(r.h)", pre=self.SHAPES))
        code, out, err = native(prog("s: Shape = Rect()\nq = Sq(s)\nprint(q.s)", pre=self.SHAPES))
        self.assertEqual(code, 1)
        self.assertIn("not an instance of that class", err)

    def test_interface_identity(self):
        self.same(prog("a: Shape = Sq()\nb: Shape = Rect()\nprint(a == a, a == b, a != b)", pre=self.SHAPES))

    def test_interface_as_return_and_field_types(self):
        pre = self.SHAPES + ("def make(n: int) -> Shape:\n    if n == 0:\n        return Sq()\n    return Rect()\n"
                             "class Holder:\n    held: Shape = Sq()\n    def area(self) -> int:\n        return self.held.area()\n")
        self.same(prog("h = Holder()\nprint(make(0).name(), make(1).area(), h.area())\nh.held = make(1)\nprint(h.area())", pre=pre))

    def test_an_interface_with_no_implementer_still_compiles_when_unused(self):
        src = "interface I:\n    def f(self) -> int\n" + prog("print(1)")
        self.assertIn("@tomato.main", compile_to_ir(src))

    def test_interface_errors_are_found_when_compiling(self):
        for body, text in (("s: Shape = Sq()\nprint(s.s)", "has no field s"),
                           ("s: Shape = Sq()\nprint(s.nope())", "has no method nope"),
                           ("n: Named = Sq()\nprint(n.area())", "has no method area"),
                           ("x: Shape = 5", "does not fit"), ("s: Shape = Sq()\ns.zzz = 1", "has no field zzz")):
            with self.assertRaises(TomatoError, msg=body) as cm:
                compile_to_ir(prog(body, pre=self.SHAPES))
            self.assertIn(text, str(cm.exception), body)

    def test_a_class_that_does_not_implement_the_interface_does_not_fit(self):
        pre = self.SHAPES + "class Plain:\n    pass\n"
        with self.assertRaises(TomatoError) as cm:
            compile_to_ir(prog("s: Shape = Plain()", pre=pre))
        self.assertIn("does not fit", str(cm.exception))

    def test_implements_declared_after_the_class(self):
        pre = ("interface N:\n    def n(self) -> int\nclass C:\n    def n(self) -> int:\n        return 7\nC implements N\n"
               "def f(x: N) -> int:\n    return x.n()\n")
        self.same(prog("print(f(C()))", pre=pre))


@needs_clang
class DictsAndSets(unittest.TestCase):
    def same(self, src, args=()):
        code, out, err = native(src, args)
        self.assertEqual(code, 0, err)
        self.assertEqual(err, "", "leak or warning: " + err)
        self.assertEqual(out, interpreted(src, args))
        return out

    def test_word_counts(self):
        self.same(prog("counts: dict[str, int] = {}\nfor w in ['the', 'cat', 'the', 'and', 'the']:\n    if w in counts:\n"
                       "        counts[w] = counts[w] + 1\n    else:\n        counts[w] = 1\nprint(counts['the'], counts['cat'], len(counts))"))

    def test_literals_and_inferred_types(self):
        self.same(prog("m = {1: 'x', 2: 'y'}\ns = {'a', 'b', 'a'}\nprint(m[2], len(m), len(s), 'a' in s, 'z' in s)"))

    def test_int_bool_and_string_keys(self):
        self.same(prog("a = {1: 10, 0 - 5: 20}\nb = {True: 1, False: 0}\nc = {'k': 'v'}\nprint(a[1], a[0 - 5], b[True], b[False], c['k'])"))

    def test_fixed_width_keys_and_values(self):
        self.same(prog("m: dict[uint[length=8], int[length=16]] = {1: 5, 255: 6}\nm[7] = 300\nprint(m[255], m[7], len(m), 255 in m, 256 in m)"
                       .replace("256 in m", "3 in m")))

    def test_overwrite_remove_and_reinsert(self):
        self.same(prog("m: dict[str, int] = {'a': 1}\nm['a'] = 2\nm['b'] = 3\nm.remove('a')\nm['a'] = 9\nprint(len(m), m['a'], m['b'], 'a' in m)"))

    def test_keys_and_values_in_insertion_order(self):
        self.same(prog("m = {'b': 1, 'a': 2, 'c': 3}\nk = m.keys()\nv = m.values()\nprint(k[0], k[1], k[2], v[0], v[1], v[2])"))

    def test_iteration_walks_a_snapshot_of_the_keys(self):
        self.same(prog("m = {'a': 1, 'b': 2}\nn = 0\nfor k in m:\n    m[k + k] = 5\n    n = n + 1\nprint(n, len(m))"))
        self.same(prog("s = {1, 2}\nfor n in s:\n    s.add(n + 10)\nprint(len(s))"))

    def test_sets(self):
        self.same(prog("s: set[int] = {}\nfor i in range(20):\n    s.add(i % 7)\ns.remove(3)\nprint(len(s), 3 in s, 4 in s)"))

    def test_heap_values_in_dicts(self):
        pre = "class P:\n    v: int = 0\n"
        self.same(prog("m: dict[str, P] = {}\nfor i in range(5):\n    p = P()\n    p.v = i\n    m['k' + str(i)] = p\n"
                       "t = 0\nfor k in m:\n    t = t + m[k].v\nm.remove('k2')\nprint(t, len(m))", pre=pre))

    def test_lists_as_values(self):
        self.same(prog("m: dict[int, list[str]] = {1: ['a'], 2: ['b', 'c']}\nm[3] = ['d']\nm[1].append('z')\nprint(len(m[1]), len(m[2]), len(m))"))

    def test_nested_dicts(self):
        self.same(prog("m: dict[str, dict[str, int]] = {}\nm['a'] = {'x': 1}\nm['a']['y'] = 2\nprint(len(m['a']), m['a']['y'])"))

    def test_dicts_are_shared(self):
        self.same(prog("a = {1: 2}\nb = a\nb[3] = 4\nprint(len(a))"))

    def test_parameters_and_fields(self):
        pre = ("def total(m: dict[str, int]) -> int:\n    t = 0\n    for k in m:\n        t = t + m[k]\n    return t\n"
               "class Reg:\n    names: dict[str, int] = {}\n    seen: set[str] = {}\n    def add(self, n: str):\n        self.names[n] = len(n)\n        self.seen.add(n)\n")
        self.same(prog("print(total({'a': 1, 'b': 2}))\nr = Reg()\nr.add('abc')\nr.add('de')\nprint(total(r.names), len(r.seen))", pre=pre))

    def test_many_entries_with_growth_and_deletes(self):
        self.same(prog("m: dict[int, int] = {}\nfor i in range(3000):\n    m[i * 7] = i\nfor i in range(0, 3000, 2):\n    m.remove(i * 7)\n"
                       "t = 0\nfor k in m:\n    t = t + m[k]\nprint(len(m), t, 7 in m, 14 in m)"))

    def test_churn_compacts_the_table(self):
        self.same(prog("m: dict[int, str] = {}\nfor r in range(200):\n    for i in range(10):\n        m[i] = 'v' + str(r)\n"
                       "    for i in range(10):\n        m.remove(i)\nprint(len(m))\nm[1] = 'z'\nprint(m[1], len(m))"))

    def test_string_keys_made_at_run_time(self):
        self.same(prog("m: dict[str, int] = {}\nfor i in range(50):\n    m['key' + str(i % 10)] = i\nprint(len(m), m['key3'], 'key' + str(7) in m)"))

    def test_str_contains(self):
        self.same(prog("print('ll' in 'hello', 'x' in 'hello', '' in 'a', 'hello' in 'he')"))

    def test_dict_failures_are_run_time_errors(self):
        for body, text in (("m = {1: 2}\nprint(m[k])", "the key or element is not there"),
                           ("m = {1: 2}\nm.remove(k)", "the key or element is not there"),
                           ("s = {1}\ns.remove(k)", "the key or element is not there")):
            code, out, err = native(prog(body, params="k: int"), ["9"])
            self.assertEqual(code, 1, body)
            self.assertIn(text, err)
        self.assertIn("error E10:", native(prog("m = {1: 2}\nprint(m[k])", params="k: int"), ["9"], "normal")[2])

    def test_a_duplicate_literal_key_fails(self):
        code, out, err = native(prog("m = {1: 2, k: 3}", params="k: int"), ["1"])
        self.assertEqual(code, 1)
        self.assertIn("duplicate key in a dict literal", err)

    def test_dict_cycles_are_collected(self):
        src = ("class A:\n    others: dict[str, A] = {}\n@main\ndef main():\n    a = A()\n    a.others['me'] = a\n")
        code, out, err = native(src, env={"TOMATO_GC_STATS": "1"}, asan=True)
        self.assertEqual(code, 0)
        self.assertIn("2 object(s) freed in cycles", err)


class DictCompileErrors(unittest.TestCase):
    def fails(self, body, text, kind=TomatoError):
        with self.assertRaises(kind) as cm:
            compile_to_ir(prog(body))
        self.assertIn(text, str(cm.exception))

    def test_type_errors(self):
        self.fails("m = {1: 'x'}\nm['a'] = 'y'", "does not fit")
        self.fails("m = {1: 'x'}\nm[1] = 5", "does not fit")
        self.fails("m = {1: 'x'}\nprint('a' in m)", "type error")
        self.fails("s = {1}\ns.add('a')", "does not fit")

    def test_unsupported_or_undecided(self):
        self.fails("m = {}", "not yet decided", NotDecided)
        self.fails("m: dict[float, int] = {}", "not yet decided", NotDecided)
        self.fails("m = {1: 2}\nm.clear()", "not yet decided", NotDecided)
        self.fails("s = {1}\nprint(s[0])", "not yet decided", NotDecided)
        self.fails("print({1: 2})", "does not support")
        self.fails("m = {1: 2}\nprint(m == m)", "not yet decided", NotDecided)


ERRS = ("class MyError(Error):\n    code: int = 0\n    @init\n    def make(self, message: str, code: int):\n"
        "        Error.start(self, message)\n        self.code = code\n"
        "class SubError(MyError):\n    @init\n    def make2(self, message: str):\n        MyError.make(self, message, 99)\n")


@needs_clang
class Errors(unittest.TestCase):
    """raise, try, catch, else and finally (D22a): same output as the interpreter, and no memory errors."""

    def same(self, src, args=()):
        code, out, err = native(src, args, asan=True)
        self.assertEqual(code, 0, err)
        self.assertEqual(err, "", err)
        self.assertEqual(out, interpreted(src, args))
        return out

    def test_raise_and_catch(self):
        self.same(prog("try:\n    raise Error('boom')\ncatch Error as e:\n    print('got', e.message)"))

    def test_catch_by_hierarchy_and_in_order(self):
        self.same(prog("for k in range(3):\n    try:\n        if k == 0:\n            raise SubError('s')\n        if k == 1:\n"
                       "            raise MyError('m', 5)\n        raise Error('e')\n    catch SubError as e:\n        print('sub', e.code)\n"
                       "    catch MyError as e:\n        print('my', e.code)\n    catch Error as e:\n        print('error', e.message)", pre=ERRS))

    def test_an_error_travels_up_through_calls(self):
        pre = ERRS + ("def c(n: int) -> int:\n    if n == 0:\n        raise MyError('deep', 7)\n    return n\n"
                      "def b(n: int) -> int:\n    return c(n) + 1\ndef a(n: int) -> int:\n    return b(n) * 2\n")
        self.same(prog("print(a(3))\ntry:\n    print(a(0))\ncatch MyError as e:\n    print(e.message, e.code)\nprint(a(1))", pre=pre))

    def test_else_runs_only_without_an_error(self):
        self.same(prog("for k in range(2):\n    try:\n        if k == 1:\n            raise Error('x')\n        print('body', k)\n"
                       "    catch Error:\n        print('caught', k)\n    else:\n        print('else', k)"))

    def test_an_error_in_else_is_not_caught_by_the_same_try(self):
        self.same(prog("try:\n    try:\n        pass\n    catch Error:\n        print('inner')\n    else:\n        raise Error('from else')\n"
                       "catch Error as e:\n    print('outer', e.message)"))

    def test_finally_runs_on_every_path(self):
        self.same(prog("for k in range(3):\n    try:\n        if k == 1:\n            raise Error('x')\n        print('ok', k)\n"
                       "    catch Error:\n        print('caught')\n    finally:\n        print('finally', k)"))

    def test_finally_runs_while_an_error_propagates(self):
        pre = "def f():\n    try:\n        raise Error('up')\n    finally:\n        print('cleanup')\n"
        self.same(prog("try:\n    f()\ncatch Error as e:\n    print('outer', e.message)", pre=pre))

    def test_finally_runs_on_return(self):
        pre = ("def f(n: int) -> int:\n    try:\n        if n > 0:\n            return n * 2\n        print('no return')\n    finally:\n"
               "        print('finally', n)\n    return 0 - 1\n")
        self.same(prog("print(f(3))\nprint(f(0))", pre=pre))

    def test_return_inside_nested_finallies_runs_both(self):
        pre = ("def f() -> int:\n    try:\n        try:\n            return 1\n        finally:\n            print('inner')\n"
               "    finally:\n        print('outer')\n    return 2\n")
        self.same(prog("print(f())", pre=pre))

    def test_finally_runs_on_break_and_continue(self):
        self.same(prog("for i in range(4):\n    try:\n        if i == 1:\n            continue\n        if i == 3:\n            break\n"
                       "        print('body', i)\n    finally:\n        print('finally', i)\nprint('done')"))

    def test_break_inside_try_outside_the_loop_only_runs_inner_finallies(self):
        self.same(prog("try:\n    for i in range(3):\n        try:\n            if i == 1:\n                break\n        finally:\n"
                       "            print('inner', i)\n    print('after loop')\nfinally:\n    print('outer')"))

    def test_rethrow_from_a_catch(self):
        self.same(prog("try:\n    try:\n        raise Error('a')\n    catch Error as e:\n        raise MyError('b' + e.message, 2)\n"
                       "catch MyError as e:\n    print(e.message, e.code)", pre=ERRS))

    def test_unmatched_catch_keeps_propagating(self):
        self.same(prog("try:\n    try:\n        raise Error('plain')\n    catch MyError:\n        print('no')\n"
                       "catch Error as e:\n    print('outer', e.message)", pre=ERRS))

    def test_runtime_failures_are_catchable(self):
        for body in ("print(1 / z)", "print(1 % z)", "xs = [1]\nprint(xs[z + 5])", "print('abc'[z + 9])", "print('abc'[2:z])",
                     "m = {1: 2}\nprint(m[z + 5])", "a: int[length=8] = 100\nb: int[length=8] = a + a",
                     "print(uint[length=8](z - 1))", "m = {1: 2}\nm.remove(z + 7)"):
            src = prog("try:\n" + "".join("    %s\n" % l for l in body.split("\n")) +
                       "catch RuntimeError:\n    print('caught')\nprint('after')", params="z: int")
            code, out, err = native(src, ["0"], asan=True)
            self.assertEqual((code, out, err), (0, "caught\nafter\n", ""), body)

    def test_runtime_errors_are_ordinary_error_objects(self):
        out = self.same(prog("try:\n    print(1 / z)\ncatch Error as e:\n    print(len(e.message) > 0)", params="z: int"), ["0"])
        self.assertEqual(out, "True\n")

    def test_errors_in_constructors_and_methods(self):
        pre = ERRS + ("class Thing:\n    n: int = 0\n    @init\n    def start(self, n: int):\n        if n < 0:\n            raise MyError('bad', n)\n"
                      "        self.n = n\n    def check(self):\n        if self.n > 5:\n            raise Error('big')\n")
        self.same(prog("t = Thing(3)\nt.check()\ntry:\n    u = Thing(0 - 4)\ncatch MyError as e:\n    print('ctor', e.code)\n"
                       "t.n = 9\ntry:\n    t.check()\ncatch Error as e:\n    print('method', e.message)", pre=pre))

    def test_errors_with_heap_values_in_flight(self):
        pre = ERRS + ("def build(n: int) -> list[str]:\n    xs: list[str] = []\n    for i in range(n):\n        xs.append('s' + str(i))\n"
                      "        if i == 3:\n            raise MyError('at ' + str(i), i)\n    return xs\n")
        self.same(prog("for n in range(6):\n    try:\n        print(len(build(n)))\n    catch MyError as e:\n        print(e.message)", pre=pre))

    def test_a_loop_that_catches_many_errors(self):
        self.same(prog("n = 0\nfor i in range(500):\n    try:\n        if i % 3 == 0:\n            raise Error('e' + str(i))\n    catch Error as e:\n"
                       "        n = n + len(e.message)\nprint(n)"))

    def test_errors_through_interfaces_and_dicts(self):
        pre = ERRS + ("interface Job:\n    def run(self) -> int\nclass Bad implements Job:\n    def run(self) -> int:\n        raise Error('bad job')\n"
                      "class Good implements Job:\n    def run(self) -> int:\n        return 7\n")
        self.same(prog("jobs: dict[str, Job] = {'g': Good(), 'b': Bad()}\nfor k in jobs:\n    try:\n        print(k, jobs[k].run())\n"
                       "    catch Error as e:\n        print(k, 'failed', e.message)", pre=pre))

    def test_catch_variable_reused_with_another_type(self):
        self.same(prog("try:\n    raise MyError('a', 1)\ncatch MyError as e:\n    print(e.code)\ntry:\n    raise Error('b')\ncatch Error as e:\n    print(e.message)", pre=ERRS))

    def test_catch_without_a_name(self):
        self.same(prog("try:\n    raise Error('x')\ncatch Error:\n    print('ignored')"))

    def test_an_error_raised_in_finally_replaces_the_pending_one(self):
        self.same(prog("try:\n    try:\n        raise Error('first')\n    finally:\n        raise Error('second')\ncatch Error as e:\n    print(e.message)"))

    def test_cycles_are_collected_whether_or_not_an_error_was_raised(self):
        src = ("class A:\n    o: list[A] = []\n@main\ndef main():\n    a = A()\n    a.o.append(a)\n    try:\n        raise Error('x')\n    catch Error:\n        pass\n")
        self.assertEqual(native(src, asan=True)[2], "")


@needs_clang
class UncaughtErrors(unittest.TestCase):
    SRC = ERRS + "def boom(n: int):\n    raise MyError('boom ' + str(n), n)\n\n@main\ndef main(n: int):\n    print('start')\n    boom(n)\n    print('unreachable')\n"

    def test_debug_mode_prints_the_class_and_message(self):
        code, out, err = native(self.SRC, ["4"])
        self.assertEqual((code, out), (1, "start\n"))
        self.assertEqual(err, "error: line 12: uncaught error MyError: boom 4\n")

    def test_the_interpreter_says_the_same(self):
        with self.assertRaises(TomatoError) as cm:
            interpreted(self.SRC, ["4"])
        self.assertIn("uncaught error MyError: boom 4", str(cm.exception))

    def test_normal_mode_prints_a_code_and_release_nothing(self):
        self.assertEqual(native(self.SRC, ["4"], mode="normal")[2], "error E11:12\n")
        self.assertEqual(native(self.SRC, ["4"], mode="release")[1:], ("start\n", ""))

    def test_the_code_decodes(self):
        from tomato import errcodes
        text = errcodes.explain("E11:12", self.SRC)
        self.assertIn("never caught", text)
        self.assertIn("raise MyError('boom ' + str(n), n)", text)

    def test_uncaught_runtime_errors_keep_their_old_wording_in_every_mode(self):
        src = prog("print(1 / z)", params="z: int")
        self.assertEqual(native(src, ["0"])[2], "error: line 4: division by zero (D05ab)\n")
        self.assertEqual(native(src, ["0"], mode="normal")[2], "error E02:4\n")
        self.assertEqual(native(src, ["0"], mode="release")[1:], ("", ""))

    def test_an_error_stops_the_program_after_earlier_output(self):
        code, out, err = native(prog("print('a')\nxs = [1]\nprint(xs[3])\nprint('b')"))
        self.assertEqual((code, out), (1, "a\n"))
        self.assertIn("index out of range", err)


class ErrorCompileTime(unittest.TestCase):
    def fails(self, body, text, pre="", kind=TomatoError):
        with self.assertRaises(kind) as cm:
            compile_to_ir(prog(body, pre=pre))
        self.assertIn(text, str(cm.exception))

    def test_raise_needs_an_error_object(self):
        self.fails("raise 5", "raise needs an Error object")
        self.fails("raise C()", "raise needs an Error object", pre="class C:\n    pass\n")

    def test_catch_needs_an_error_class(self):
        self.fails("try:\n    pass\ncatch C:\n    pass", "catch needs an error class", pre="class C:\n    pass\n")
        self.fails("try:\n    pass\ncatch Nope:\n    pass", "catch needs an error class")

    def test_user_errors_still_follow_the_init_rules(self):
        self.fails("raise Bad('x')", "has no @init of its own", pre="class Bad(Error):\n    pass\n")


@needs_clang
class OptionalsAndDefaults(unittest.TestCase):
    """`T | None` (D23b) and default arguments (D19c) in compiled code: heap optionals are nullable pointers."""

    def same(self, src, args=()):
        code, out, err = native(src, args, asan=True)
        self.assertEqual(code, 0, err)
        self.assertEqual(err, "", err)
        self.assertEqual(out, interpreted(src, args))
        return out

    NODE = "class Node:\n    name: str = 'n'\n    parent: Node | None = None\n"

    def test_none_tests(self):
        self.same(prog("x: Node | None = None\nprint(x is None, x is not None, x == None, x != None)\ny = Node()\nx = y\n"
                       "print(x is None, x is not None, x == None, x != None, x is y, x is not y)", pre=self.NODE))

    def test_an_optional_field_and_a_linked_chain(self):
        pre = self.NODE + ("def depth(n: Node | None) -> int:\n    d = 0\n    cur = n\n    while cur is not None:\n        d = d + 1\n"
                           "        cur = cur.parent\n    return d\n")
        self.same(prog("a = Node()\nb = Node()\nb.parent = a\nc = Node()\nc.parent = b\nprint(depth(c), depth(a), depth(None))", pre=pre))

    def test_optional_strings(self):
        pre = "def describe(label: str, extra: str | None = None) -> str:\n    if extra == None:\n        return label\n    return label + '+' + extra\n"
        self.same(prog("print(describe('a'), describe('a', 'b'), describe('c', None))\ns: str | None = 'hi'\nprint(s, len(s))\ns = None\nprint(s, s is None)", pre=pre))

    def test_optional_string_equality_follows_the_interpreter(self):
        self.same(prog("a: str | None = None\nb: str | None = 'x'\nprint(a == b, a != b, b == 'x', b == 'y', a == None, a == a, b == b)"))

    def test_optional_collections_and_elements(self):
        self.same(prog("xs: list[str | None] = [None, 'a']\nxs.append(None)\nxs.append('b')\nn = 0\nfor x in xs:\n    if x is not None:\n"
                       "        n = n + len(x)\nprint(len(xs), n, xs[0], xs[1])"))
        self.same(prog("d: dict[str, Node | None] = {'a': None, 'b': Node()}\nprint(d['a'] is None, d['b'] is None, d['b'].name)", pre=self.NODE))

    def test_in_none(self):
        self.same(prog("x: Node | None = None\ns: str | None = 'a'\nprint(x in None, s in None, None in None, 3 in None, Node() in None)\n"
                       "if x in None:\n    print('none')", pre=self.NODE))

    def test_in_list(self):
        self.same(prog("xs = [1, 2, 3]\nss = ['a', 'bc']\nw = 'b' + 'c'\n"
                       "print(2 in xs, 5 in xs, 'a' in ss, w in ss, 'z' in ss, 1 in [4, 1], 'x' in ['x'])\n"
                       "if 3 in xs:\n    print('yes')"))

    def test_text_methods(self):
        self.same(prog("s = 'a,b,,c'\nparts = s.split(',')\nprint(len(parts), parts[0], parts[2] == '', parts[3])\n"
                       "print('a-b-c'.replace('-', '+'), 'abc'.replace('x', 'y'), 'héllo'.find('l'), 'hello'.find('z'))\n"
                       "print('hello'.startswith('he'), 'hello'.endswith('lo'), 'hello'.endswith('x'), ''.split(',')[0] == '')\n"
                       "t = 'x' + 'y'\nprint(t.replace('y', 'zz'), (t + t).split('y')[1])"))

    def test_files(self):
        path = os.path.join(tempfile.mkdtemp(), "f.txt")
        self.same(prog("f = open('%s', 'w')\nf.write('one\\ntwo\\n')\nf.close()\ng = open('%s')\ns = g.read()\ng.close()\n"
                       "print(len(s.split('\\n')), s.split('\\n')[1])" % (path, path)))

    def test_xor(self):
        self.same(prog("a = True\nb = False\nprint(a xor b, a xor a, b xor b, a or b xor a, not a xor a)"))

    def test_in_type(self):
        pre = self.NODE + "class Leaf(Node):\n    pass\nclass Rock:\n    pass\n"
        self.same(prog("n: Node = Leaf()\nm: Node = Node()\nk: Node | None = Leaf()\nz: Node | None = None\n"
                       "print(n in Leaf, m in Leaf, n in Node, n in Rock, k in Leaf, z in Leaf, k in Node, z in Node, 1 in int, 'a' in str, 'a' in int, True in bool)",
                       pre=pre))

    def test_returning_an_optional(self):
        pre = self.NODE + "def pick(flag: bool, n: Node) -> Node | None:\n    if flag:\n        return n\n    return None\n"
        self.same(prog("n = Node()\nprint(pick(True, n) is None, pick(False, n) is None, pick(True, n).name)", pre=pre))

    def test_an_optional_used_as_a_value_raises_when_it_is_none(self):
        src = prog("x: Node | None = None\ntry:\n    print(x.name)\ncatch RuntimeError:\n    print('caught')", pre=self.NODE)
        code, out, err = native(src, asan=True)
        self.assertEqual((code, out, err), (0, "caught\n", ""))
        src = prog("s: str | None = None\ntry:\n    print(len(s))\ncatch RuntimeError:\n    print('caught')")
        self.assertEqual(native(src, asan=True)[1], "caught\n")
        src = prog("x: Node | None = None\nprint(x.name)", pre=self.NODE)
        code, out, err = native(src)
        self.assertEqual(code, 1)
        self.assertIn("None where a value is needed", err)
        self.assertEqual(native(src, mode="normal")[2], "error E12:8\n")

    def test_passing_an_optional_where_a_plain_value_is_needed(self):
        pre = self.NODE + "def name_of(n: Node) -> str:\n    return n.name\n"
        self.same(prog("x: Node | None = Node()\nprint(name_of(x))", pre=pre))
        code, out, err = native(prog("x: Node | None = None\nprint(name_of(x))", pre=pre))
        self.assertEqual(code, 1)
        self.assertIn("None where a value is needed", err)

    def test_defaults(self):
        pre = ("def f(a: int, b: int = 10, c: str = 'z') -> str:\n    return str(a + b) + c\n"
               "class C:\n    v: int = 0\n    @init\n    def s(self, v: int = 5):\n        self.v = v\n"
               "    def add(self, n: int = 1) -> int:\n        return self.v + n\n"
               "class D(C):\n    @init\n    def t(self, v: int = 7):\n        C.s(self, v)\n")
        self.same(prog("print(f(1), f(1, 2), f(1, 2, 'q'))\nprint(C().v, C(9).v, C().add(), C().add(10), D().v, D(3).v)", pre=pre))

    def test_a_default_is_evaluated_at_each_call(self):
        pre = "def f(n: int = 1 + 2, s: str = 'a' + 'b') -> str:\n    return s + str(n)\n"
        self.same(prog("print(f(), f(7), f(7, 'x'), f())", pre=pre))

    def test_a_default_of_none_and_defaults_for_heap_types(self):
        pre = ("def f(a: str | None = None, xs: list[int] = [1, 2]) -> int:\n    n = len(xs)\n    if a is not None:\n        n = n + len(a)\n    return n\n")
        self.same(prog("print(f(), f('abc'), f(None, [1]))", pre=pre))

    def test_default_arity_errors(self):
        pre = "def f(a: int, b: int = 1):\n    pass\n"
        for body in ("f()", "f(1, 2, 3)"):
            with self.assertRaises(TomatoError, msg=body):
                compile_to_ir(prog(body, pre=pre))

    def test_none_where_a_value_is_expected_is_a_compile_time_error(self):
        for body in ("x: int = None", "x: str = None", "x: Node = None"):
            with self.assertRaises(TomatoError, msg=body) as cm:
                compile_to_ir(prog(body, pre=self.NODE))
            self.assertIn("None where", str(cm.exception))

    def test_optional_numbers_are_not_compiled_yet(self):
        for body in ("x: int | None = None", "x: float | None = None", "x: bool | None = None"):
            with self.assertRaises(TomatoError, msg=body) as cm:
                compile_to_ir(prog(body))
            self.assertIn("does not support", str(cm.exception))

    def test_is_with_unsupported_operands(self):
        with self.assertRaises(NotDecided):
            compile_to_ir(prog("print(1 is 1)"))

    def test_optional_cycles_are_collected(self):
        src = (self.NODE.replace("parent: Node | None = None", "parent: Node | None = None\n    kid: Node | None = None") +
               "@main\ndef main():\n    for i in range(30000):\n        a = Node()\n        b = Node()\n        a.kid = b\n        b.parent = a\n    print('ok')\n")
        code, out, err = native(src, asan=True, env={"TOMATO_GC_STATS": "1"})
        self.assertEqual((code, out), (0, "ok\n"))
        self.assertIn("freed in cycles", err)

    def test_compiled_entry_with_an_optional_input_is_not_compiled_yet(self):
        with self.assertRaises(TomatoError):
            compile_to_ir(prog("pass", params="x: str | None"))


@needs_clang
class ExampleProgram(unittest.TestCase):
    def test_objects_example_runs_the_same_natively_and_in_the_interpreter(self):
        with open(os.path.join(ROOT, "examples", "objects.tom")) as f:
            src = f.read()
        code, out, err = native(src, ["6"])
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, interpreted(src, ["6"]))
        self.assertIn("total 30", out)


@needs_clang
class CycleCollector(unittest.TestCase):
    """Reference counting alone never frees a cycle, so the runtime collects them itself (D29d)."""

    STATS = {"TOMATO_GC_STATS": "1"}

    def run_gc(self, src, args=()):
        code, out, err = native(src, args, asan=True, env=self.STATS)
        self.assertEqual(code, 0, err)
        return out, err

    CYCLE = ("class A:\n    other: list[B] = []\nclass B:\n    other: list[A] = []\n"
             "@main\ndef main():\n    a = A()\n    b = B()\n    a.other.append(b)\n    b.other.append(a)\n    print('done')\n")

    def test_a_cycle_is_freed_and_nothing_is_reported(self):
        out, err = self.run_gc(self.CYCLE)
        self.assertEqual(out, "done\n")
        self.assertEqual(err, "gc: 4 object(s) freed in cycles\n")       # two objects and their two lists
        self.assertEqual(native(self.CYCLE)[2], "")                      # no leak warning without the stats

    def test_it_runs_in_every_mode(self):
        for mode in ("debug", "normal", "release"):
            code, out, err = native(self.CYCLE, mode=mode)
            self.assertEqual((code, out, err), (0, "done\n", ""), mode)

    def test_self_reference(self):
        out, err = self.run_gc("class A:\n    me: list[A] = []\n@main\ndef main():\n    a = A()\n    a.me.append(a)\n")
        self.assertIn("2 object(s) freed in cycles", err)

    def test_cycles_through_dicts_and_interfaces(self):
        src = ("interface Owner:\n    def name(self) -> str\nclass Boss implements Owner:\n    staff: dict[str, Worker] = {}\n"
               "    def name(self) -> str:\n        return 'boss'\nclass Worker:\n    boss: Owner\n    @init\n    def s(self, b: Owner):\n"
               "        self.boss = b\n@main\ndef main():\n    b = Boss()\n    b.staff['w'] = Worker(b)\n    print(b.staff['w'].boss.name())\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "boss\n")
        self.assertIn("freed in cycles", err)

    def test_a_cycle_through_a_field_of_the_same_class(self):
        src = ("class Node:\n    next: list[Node] = []\n    tag: str = 'n'\n@main\ndef main():\n    a = Node()\n    b = Node()\n"
               "    c = Node()\n    a.next.append(b)\n    b.next.append(c)\n    c.next.append(a)\n    print(a.tag + b.tag + c.tag)\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "nnn\n")
        self.assertIn("freed in cycles", err)

    def test_many_cycles_are_collected_as_the_program_runs(self):
        src = ("class A:\n    other: list[A] = []\n    pad: str = 'padding'\n"
               "@main\ndef main():\n    n = 0\n    for i in range(60000):\n        a = A()\n        b = A()\n        a.other.append(b)\n"
               "        b.other.append(a)\n        n = n + len(a.other)\n    print(n)\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "60000\n")
        self.assertIn("freed in cycles", err)
        freed = int(err.strip().splitlines()[-1].split()[1])      # the counter is cumulative: the last line is the total
        self.assertEqual(freed, 60000 * 4)         # two objects and two lists per round, all freed

    def test_memory_stays_bounded_while_cycles_pile_up(self):
        src = ("class A:\n    other: list[A] = []\n    pad: str = 'padding'\n"
               "@main\ndef main():\n    for i in range(300000):\n        a = A()\n        a.other.append(a)\n    print('ok')\n")
        ir = compile_to_ir(src)
        with tempfile.TemporaryDirectory() as d:
            ll, exe = os.path.join(d, "p.ll"), os.path.join(d, "p")
            with open(ll, "w") as f:
                f.write(ir)
            subprocess.run([CLANG, "-O1", "-Wno-override-module", "-x", "ir", ll, "-x", "c", RUNTIME, "-lm", "-o", exe],
                           check=True, capture_output=True)
            r = subprocess.run(["/usr/bin/time", "-l", exe], capture_output=True, text=True)
        self.assertEqual(r.stdout, "ok\n")
        rss = [int(l.split()[0]) for l in r.stderr.splitlines() if "maximum resident set size" in l]
        if rss:                       # 600,000 leaked objects would be many tens of megabytes
            self.assertLess(rss[0], 60 * 1024 * 1024)

    def test_a_live_object_is_never_collected(self):
        src = ("class A:\n    other: list[A] = []\n    name: str = 'keeper'\n"
               "@main\ndef main():\n    keep = A()\n    keep2 = A()\n    keep.other.append(keep2)\n    keep2.other.append(keep)\n"
               "    for i in range(30000):\n        a = A()\n        a.other.append(a)\n"
               "    print(keep.name, keep.other[0].other[0].name, len(keep.other))\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "keeper keeper 1\n")

    def test_garbage_pointing_at_a_live_object_leaves_it_intact(self):
        src = ("class Live:\n    v: int = 7\nclass G:\n    other: list[G] = []\n    target: Live\n    @init\n    def s(self, t: Live):\n        self.target = t\n"
               "@main\ndef main():\n    live = Live()\n    for i in range(30000):\n        g = G(live)\n        g.other.append(g)\n"
               "    print(live.v)\n    live.v = 8\n    print(live.v)\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "7\n8\n")

    def test_a_cycle_reachable_from_a_list_survives_until_dropped(self):
        src = ("class N:\n    other: list[N] = []\n    id: int = 0\n"
               "@main\ndef main():\n    keep: list[N] = []\n    for i in range(20000):\n        a = N()\n        a.id = i\n"
               "        a.other.append(a)\n        if i % 1000 == 0:\n            keep.append(a)\n"
               "    t = 0\n    for k in keep:\n        t = t + k.id + len(k.other[0].other)\n    print(len(keep), t)\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "20 %d\n" % (sum(i * 1 for i in range(0, 20000, 1000)) + 20))

    def test_a_ring_of_many_objects_is_collected_without_deep_recursion(self):
        src = ("class R:\n    next: list[R] = []\n@main\ndef main():\n    first = R()\n    prev = first\n    for i in range(200000):\n"
               "        n = R()\n        prev.next.append(n)\n        prev = n\n    prev.next.append(first)\n    print('ring built')\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "ring built\n")
        self.assertIn("freed in cycles", err)

    def test_a_long_chain_is_freed_without_deep_recursion(self):
        src = ("class L:\n    next: list[L] = []\n@main\ndef main():\n    head = L()\n    cur = head\n    for i in range(500000):\n"
               "        n = L()\n        cur.next.append(n)\n        cur = n\n    print('chain built')\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "chain built\n")
        self.assertNotIn("never freed", err)

    def test_collection_after_errors_and_in_loops_with_exceptions(self):
        src = ("class C:\n    other: list[C] = []\n@main\ndef main():\n    n = 0\n    for i in range(25000):\n        try:\n"
               "            a = C()\n            a.other.append(a)\n            if i % 5 == 0:\n                raise Error('x')\n"
               "        catch Error:\n            n = n + 1\n    print(n)\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "5000\n")

    def test_strings_and_dicts_inside_cycles(self):
        src = ("class Reg:\n    names: dict[str, Reg] = {}\n    label: str = ''\n"
               "@main\ndef main():\n    t = 0\n    for i in range(20000):\n        r = Reg()\n        r.label = 'r' + str(i)\n"
               "        r.names[r.label] = r\n        t = t + len(r.label)\n    print(t)\n")
        out, err = self.run_gc(src)
        self.assertEqual(out, "%d\n" % sum(len("r" + str(i)) for i in range(20000)))
        self.assertIn("freed in cycles", err)

    def test_chains_without_cycles_are_not_counted_as_cycles(self):
        src = "class A:\n    next: list[A] = []\n@main\ndef main():\n    a = A()\n    b = A()\n    a.next.append(b)\n"
        out, err = self.run_gc(src)
        self.assertEqual(err, "")

    def test_static_strings_are_never_counted(self):
        self.assertEqual(native(prog("s = 'x'\nt = s\nprint(s, t)"))[1:], ("x x\n", ""))

    def test_a_failure_exits_without_a_leak_report(self):
        code, out, err = native(prog("s = 'a' + 'b'\nprint(1 / z)", params="z: int"), ["0"])
        self.assertEqual(code, 1)
        self.assertNotIn("never freed", err)


@needs_clang
class Failures(unittest.TestCase):
    def fails(self, src, text, args=(), mode="debug"):
        code, out, err = native(src, args, mode)
        self.assertEqual(code, 1, (out, err))
        self.assertIn(text, err)

    def test_index_out_of_range(self):
        self.fails(prog("xs = [1]\nprint(xs[i])", params="i: int"), "line 5: index out of range", ["1"])
        self.fails(prog("xs = [1]\nprint(xs[i])", params="i: int"), "index out of range", ["-1"])
        self.fails(prog("print('abc'[i])", params="i: int"), "index out of range", ["3"])
        self.fails(prog("xs = [1]\nxs[i] = 2", params="i: int"), "index out of range", ["5"])

    def test_slice_out_of_range(self):
        self.fails(prog("print('abc'[a:b])", params="a: int, b: int"), "index out of range", ["2", "1"])
        self.fails(prog("print('abc'[0:b])", params="b: int"), "index out of range", ["4"])

    def test_error_modes_for_index_failures(self):
        src = prog("xs = [1]\nprint(xs[i])", params="i: int")
        self.fails(src, "error E07:5", ["9"], "normal")
        code, out, err = native(src, ["9"], "release")
        self.assertEqual((code, err), (1, ""))

    def test_the_code_decodes(self):
        from tomato import errcodes
        src = prog("xs = [1]\nprint(xs[i])", params="i: int")
        text = errcodes.explain("E07:5", src)
        self.assertIn("index out of range", text)
        self.assertIn("print(xs[i])", text)


class CompileTime(unittest.TestCase):
    def fails(self, src, text, kind=TomatoError):
        with self.assertRaises(kind) as cm:
            compile_to_ir(src)
        self.assertIn(text, str(cm.exception))

    def test_private_access_is_checked_when_compiling(self):
        pre = "class P:\n    private x: int = 1\n    def private hid(self) -> int:\n        return 1\n"
        self.fails(prog("print(P().x)", pre=pre), "private to class")
        self.fails(prog("print(P().hid())", pre=pre), "private to class")

    def test_subclass_cannot_read_parent_private_fields(self):
        pre = "class A:\n    private x: int = 1\nclass B(A):\n    def peek(self) -> int:\n        return self.x\n"
        self.fails(prog("print(B().peek())", pre=pre), "private to class")

    def test_const_fields(self):
        pre = "class C:\n    const k: int\n    @init\n    def s(self, k: int):\n        self.k = k\n    def bump(self):\n        self.k = 2\n"
        self.fails(prog("C(1).bump()", pre=pre), "cannot change after initialization")
        ok = "class C:\n    const k: int\n    @init\n    def s(self, k: int):\n        self.k = k\n"
        self.assertIn("@tomato.new", compile_to_ir(prog("C(1)", pre=ok)))

    def test_member_checks_use_the_static_type(self):
        pre = "class A:\n    pass\nclass B(A):\n    def only_b(self) -> int:\n        return 1\ndef f(a: A) -> int:\n    return a.only_b()\n"
        self.fails(prog("print(f(B()))", pre=pre), "has no method only_b")
        self.fails(prog("print(A().nope)", pre="class A:\n    pass\n"), "has no field nope")

    def test_type_errors_with_heap_values(self):
        self.fails(prog("print('a' + 1)"), "type error")
        self.fails(prog("xs = [1]\nxs.append('a')"), "does not fit")
        self.fails(prog("xs: list[str] = [1]"), "does not fit")
        self.fails(prog("a: int = 'x'"), "does not fit")
        self.fails("def f(s: str) -> str:\n    return 1\n@main\ndef main():\n    pass\n", "does not fit")
        self.fails(prog("print(P() == 1)", pre="class P:\n    pass\n"), "type error")
        self.fails(prog("xs = [1]\nprint(xs['a'])"), "must be an integer")

    def test_a_parent_object_is_not_a_subclass(self):
        pre = "class A:\n    pass\nclass B(A):\n    pass\ndef f(b: B):\n    pass\n"
        self.fails(prog("f(A())", pre=pre), "does not fit")

    def test_init_rules_are_still_checked(self):
        self.fails(prog("A(1)", pre="class A:\n    pass\n"), "takes no arguments")
        self.fails(prog("A()", pre="class A:\n    @init\n    def s(self, n: int):\n        pass\n"), "takes 1 argument")

    def test_strings_are_immutable(self):
        self.fails(prog("s = 'abc'\ns[0] = 'x'"), "cannot be changed in place")

    def test_unsupported_heap_features_say_so(self):
        for body, pre in (("x = 'a'.upper()", ""), ("print([1])", ""),
                          ("xs = [1]\nprint(xs[0:1])", "")):
            with self.assertRaises(TomatoError, msg=body) as cm:
                compile_to_ir(prog(body.replace("print(len(d))", "d = {1: 2}\nprint(len(d))"), pre=pre) if False else prog(body, pre=pre))
            self.assertTrue("does not support" in str(cm.exception) or "unknown name" in str(cm.exception)
                            or "not yet decided" in str(cm.exception), (body, str(cm.exception)))

    def test_empty_list_needs_a_type(self):
        self.fails(prog("xs = []"), "not yet decided", NotDecided)

    def test_ir_uses_the_header_layout(self):
        ir = compile_to_ir(prog("c = C()", pre="class C:\n    v: int = 0\n"))
        self.assertIn("%class.2 = type { i64, i64, i64 }", ir)
        self.assertIn("@tomato_kinds", ir)
        self.assertIn("@tomato_offsets", ir)
        self.assertIn("@tomato_vtables", ir)
        self.assertIn("call ptr @tomato_alloc", ir)


if __name__ == "__main__":
    unittest.main()
