"""Run-time types and values."""
from fractions import Fraction

from .errors import RunFailure, TomatoError


class Type:
    pass


class IntT(Type):
    def __eq__(self, o):
        return isinstance(o, IntT)

    def __hash__(self):
        return 1

    def __repr__(self):
        return "int"

    def range(self):
        return None, None


class FixedT(Type):
    def __init__(self, signed, bits):
        self.signed, self.bits = signed, bits

    def __eq__(self, o):
        return isinstance(o, FixedT) and (self.signed, self.bits) == (o.signed, o.bits)

    def __hash__(self):
        return hash((self.signed, self.bits))

    def __repr__(self):
        return "%s[length=%d]" % ("int" if self.signed else "uint", self.bits)

    def range(self):
        if self.signed:
            return -(1 << (self.bits - 1)), (1 << (self.bits - 1)) - 1
        return 0, (1 << self.bits) - 1


class SimpleT(Type):
    def __init__(self, name):
        self.name = name

    def __eq__(self, o):
        return isinstance(o, SimpleT) and o.name == self.name

    def __hash__(self):
        return hash(self.name)

    def __repr__(self):
        return self.name


FloatT = SimpleT("float")
RationalT = SimpleT("rational")
BoolT = SimpleT("bool")
StrT = SimpleT("str")
NoneT = SimpleT("None")
RangeT = SimpleT("range")
FileT = SimpleT("File")
INT = IntT()


class OptT(Type):
    """`T | None` (D23b): a T or None."""

    def __init__(self, inner):
        self.inner = inner

    def __eq__(self, o):
        return isinstance(o, OptT) and o.inner == self.inner

    def __hash__(self):
        return hash(("opt", self.inner))

    def __repr__(self):
        return "%r | None" % (self.inner,)


class UnionT(Type):
    """`A | B | ...` (D23g): a value of any one of the member types. `T | None` with one other member is OptT."""

    def __init__(self, members):
        self.members = tuple(members)

    def __eq__(self, o):
        return isinstance(o, UnionT) and set(o.members) == set(self.members)

    def __hash__(self):
        return hash(("union", frozenset(self.members)))

    def __repr__(self):
        return " | ".join(repr(m) for m in self.members)


class InterT(Type):
    """`A & B` (D23h): a value that is every member type (interfaces, and at most one class)."""

    def __init__(self, members):
        self.members = tuple(members)

    def __eq__(self, o):
        return isinstance(o, InterT) and set(o.members) == set(self.members)

    def __hash__(self):
        return hash(("inter", frozenset(self.members)))

    def __repr__(self):
        return " & ".join(repr(m) for m in self.members)


class ListT(Type):
    def __init__(self, elem):
        self.elem = elem

    def __eq__(self, o):
        return isinstance(o, ListT) and o.elem == self.elem

    def __hash__(self):
        return hash(("list", self.elem))

    def __repr__(self):
        return "list[%r]" % (self.elem,)


class TupleT(Type):
    """`tuple[T]` (D39a): an immutable sequence whose items all have type T."""

    def __init__(self, elem):
        self.elem = elem

    def __eq__(self, o):
        return isinstance(o, TupleT) and o.elem == self.elem

    def __hash__(self):
        return hash(("tuple", self.elem))

    def __repr__(self):
        return "tuple[%r]" % (self.elem,)


class TList:
    """A growable list (D20a): items all have type `elem`; assignment shares the list."""

    def __init__(self, elem, items):
        self.elem, self.items = elem, items


class TTuple(TList):
    """A tuple value (D39a): a list that cannot be changed."""


class MapT(Type):
    def __init__(self, key, value):
        self.key, self.value = key, value

    def __eq__(self, o):
        return isinstance(o, MapT) and (o.key, o.value) == (self.key, self.value)

    def __hash__(self):
        return hash(("dict", self.key, self.value))

    def __repr__(self):
        return "dict[%r, %r]" % (self.key, self.value)


class SetT(Type):
    def __init__(self, elem):
        self.elem = elem

    def __eq__(self, o):
        return isinstance(o, SetT) and o.elem == self.elem

    def __hash__(self):
        return hash(("set", self.elem))

    def __repr__(self):
        return "set[%r]" % (self.elem,)


def key_of(v):
    """Hashable form of a map key or set element: integers by value, text, and bools (PROVISIONAL key kinds)."""
    if isinstance(v, bool):
        return ("b", v)
    if isinstance(v, FixedInt):
        return ("i", v.n)
    if isinstance(v, int):
        return ("i", v)
    if isinstance(v, str):
        return ("s", v)
    return None


class TMap:
    """A map (D20b): insertion-ordered; `items` maps a key's hashable form to [key, value]. Assignment shares it."""

    def __init__(self, ktype, vtype):
        self.ktype, self.vtype, self.items = ktype, vtype, {}


class TSet:
    def __init__(self, etype):
        self.etype, self.items = etype, {}   # hashable form -> element


class TFile:
    """An open file (D26a). PROVISIONAL: text in UTF-8, modes r, w and a."""

    def __init__(self, handle, path):
        self.handle, self.path, self.closed = handle, path, False


class ClassT(Type):
    def __init__(self, name):
        self.name = name

    def __eq__(self, o):
        return isinstance(o, ClassT) and o.name == self.name

    def __hash__(self):
        return hash(("c", self.name))

    def __repr__(self):
        return self.name


class IfaceT(Type):
    def __init__(self, name):
        self.name = name

    def __eq__(self, o):
        return isinstance(o, IfaceT) and o.name == self.name

    def __hash__(self):
        return hash(("i", self.name))

    def __repr__(self):
        return self.name


def is_int_type(t):
    return isinstance(t, (IntT, FixedT))


def contains(outer, inner):
    """True when every value of integer type `inner` is a value of `outer`."""
    olo, ohi = outer.range()
    ilo, ihi = inner.range()
    if olo is not None and (ilo is None or ilo < olo):
        return False
    if ohi is not None and (ihi is None or ihi > ohi):
        return False
    return True


class FixedInt:
    """A value of a fixed-width integer type."""
    __slots__ = ("n", "t")

    def __init__(self, n, t):
        lo, hi = t.range()
        if not (lo <= n <= hi):
            raise RunFailure("overflow: %d does not fit %r" % (n, t))
        self.n, self.t = n, t

    def __repr__(self):
        return str(self.n)


class Rational:
    __slots__ = ("f",)

    def __init__(self, num, den):
        if den == 0:
            raise RunFailure("rational with denominator zero")
        self.f = Fraction(num, den)  # reduced, positive denominator, canonical zero

    def __repr__(self):
        return "%d/%d" % (self.f.numerator, self.f.denominator)


class Instance:
    def __init__(self, cls):
        self.cls = cls
        self.fields = {}
        self.const_set = set()


def value_type(v):
    if isinstance(v, bool):
        return BoolT
    if isinstance(v, int):
        return INT
    if isinstance(v, FixedInt):
        return v.t
    if isinstance(v, float):
        return FloatT
    if isinstance(v, Rational):
        return RationalT
    if isinstance(v, str):
        return StrT
    if v is None:
        return NoneT
    if isinstance(v, Instance):
        return ClassT(v.cls.name)
    if isinstance(v, TTuple):
        return TupleT(v.elem)
    if isinstance(v, TList):
        return ListT(v.elem)
    if isinstance(v, TMap):
        return MapT(v.ktype, v.vtype)
    if isinstance(v, TSet):
        return SetT(v.etype)
    if isinstance(v, TFile):
        return FileT
    if isinstance(v, RangeObj):
        return RangeT
    if isinstance(v, tuple) and v and v[0] == "ref":
        return SimpleT("function or class")
    return SimpleT(type(v).__name__)


def int_value(v):
    return v.n if isinstance(v, FixedInt) else v


def is_int_value(v):
    return isinstance(v, FixedInt) or (isinstance(v, int) and not isinstance(v, bool))


def show(v):
    if isinstance(v, bool):
        return "True" if v else "False"
    if v is None:
        return "None"
    if isinstance(v, Instance):
        return "<%s>" % v.cls.node.name
    if isinstance(v, TMap):
        return "{" + ", ".join("%s: %s" % (show_item(k), show_item(x)) for k, x in v.items.values()) + "}"
    if isinstance(v, TSet):
        return "{" + ", ".join(show_item(x) for x in v.items.values()) + "}" if v.items else "{}"
    if isinstance(v, TList):  # PROVISIONAL (printing is open): text items are shown in single quotes
        return "[" + ", ".join(("'%s'" % x) if isinstance(x, str) else show(x) for x in v.items) + "]"
    return str(v)


class RangeObj:
    """The standard-library `range` class (D18a): integers from start up to, not including, stop."""

    def __init__(self, start, stop, step):
        self.start, self.stop, self.step = start, stop, step

    def __iter__(self):
        return iter(range(self.start, self.stop, self.step))

    def __repr__(self):
        return "range(%d, %d, %d)" % (self.start, self.stop, self.step)


def show_item(v):
    return ("'%s'" % v) if isinstance(v, str) else show(v)
