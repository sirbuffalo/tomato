"""Checks made before a program runs (D04a, D05x, D05ac, D05ap): type errors and constant failures are found in
every function body, wherever written, including code that never executes.

The checker is deliberately partial (P54). It infers a type for an expression only where that is certain; anything it
does not model (collection literals, most method calls, narrowing, ...) has no known type and is let through, so it
never rejects a program the interpreter would accept. Where it does find a mismatch it reports the same message the
interpreter would give at run time."""
from . import nodes as N
from .errors import TomatoError
from .values import (BoolT, ClassT, FixedT, FloatT, IfaceT, IntT, INT, InterT, ListT, NoneT, OptT, RationalT, StrT,
                     UnionT, contains)

COMPARE = ("==", "!=", "<", "<=", ">", ">=", "is", "is not", "in")


class Const:
    """An integer known at check time, written with integer literals only (D05t-w, D05x)."""

    def __init__(self, n):
        self.n = n

    def __repr__(self):
        return "int"


def is_const(t):
    return isinstance(t, Const)


class Checker:
    def __init__(self, interp):
        self.i = interp

    # ------------------------------------------------------------------ entry
    def run(self):
        for fi in list(self.i.funcs.values()):
            self.function(fi)
        for c in list(self.i.classes.values()):
            for m in c.methods.values():
                self.function(m)

    def function(self, fi):
        saved = self.i.cur_mod
        self.i.cur_mod = fi.module
        try:
            env = {}
            params = [p for p in fi.node.params if p.name != "self"]
            for p, t in zip(params, fi.ptypes):
                env[p.name] = (t, True)
            self.fi = fi
            self.block(fi.node.body, env)
        finally:
            self.i.cur_mod = saved

    # ------------------------------------------------------------- statements
    def block(self, stmts, env):
        for s in stmts:
            self.stmt(s, env)

    def stmt(self, s, env):
        if isinstance(s, N.Declare):
            t = self.i.resolve(s.type) if s.type is not None else None
            vt = self.expr(s.value, env, t) if s.value is not None else None
            if t is None:
                env[s.name] = (self.widen(vt), False)
            else:
                if vt is not None:
                    self.fit(vt, t, s.value, s.line, "value")
                env[s.name] = (t, True)
        elif isinstance(s, N.Assign):
            if isinstance(s.target, N.Name):
                cur = env.get(s.target.name)
                vt = self.expr(s.value, env, cur[0] if cur and cur[1] else None)
                if cur is None:
                    env[s.target.name] = (self.widen(vt), False)
                elif cur[1]:
                    if vt is not None:
                        self.fit(vt, cur[0], s.value, s.line, "assigned value")
                elif vt is None or self.widen(vt) != cur[0]:
                    env[s.target.name] = (None, False)          # an inferred variable that changes: stop tracking it
            else:
                self.expr(s.target, env)
                self.expr(s.value, env)
        elif isinstance(s, N.Return):
            if s.value is not None:
                vt = self.expr(s.value, env, self.fi.ret)
                if vt is not None:
                    self.fit(vt, self.fi.ret, s.value, s.line, "returned value")
        elif isinstance(s, N.If):
            for cond, body in s.branches:
                self.condition(cond, env)
                self.block(body, env)
            self.block(s.orelse or [], env)
        elif isinstance(s, N.While):
            self.condition(s.cond, env)
            self.block(s.body, env)
        elif isinstance(s, N.For):
            it = self.expr(s.iter, env)
            env[s.var] = (self.loop_var(it), False)
            self.block(s.body, env)
        elif isinstance(s, N.ExprStmt):
            self.expr(s.expr, env)
        elif isinstance(s, N.Raise):
            self.expr(s.value, env)
        elif isinstance(s, N.Try):
            self.block(s.body, env)
            for _cls, var, body in s.handlers:
                if var:
                    env[var] = (None, False)
                self.block(body, env)
            self.block(s.orelse or [], env)
            self.block(s.final or [], env)

    def loop_var(self, it):
        if isinstance(it, ListT):
            return it.elem
        return None

    def condition(self, e, env):
        t = self.expr(e, env)
        if t is not None and self.concrete(t) and t != BoolT:
            raise TomatoError("a condition must be a bool, found %r (truthiness is not yet decided)" % self.widen(t),
                              e.line)

    @staticmethod
    def concrete(t):
        return isinstance(t, (Const, IntT, FixedT)) or t in (StrT, FloatT, BoolT, RationalT)

    @staticmethod
    def widen(t):
        return INT if isinstance(t, Const) else t

    # ------------------------------------------------------------ expressions
    def expr(self, e, env, expected=None):
        """The type of `e`, or None when it is not known without running. Visits every sub-expression."""
        if isinstance(e, N.IntLit):
            return Const(e.value)
        if isinstance(e, N.StrLit):
            return StrT
        if isinstance(e, N.FloatLit):
            return FloatT
        if isinstance(e, N.BoolLit):
            return BoolT
        if isinstance(e, N.Name):
            return env[e.name][0] if e.name in env else None
        if isinstance(e, N.UnOp):
            t = self.expr(e.operand, env)
            if e.op == "-" and isinstance(t, Const):
                return Const(-t.n)
            if e.op == "not":
                return BoolT
            return self.widen(t) if t in (INT, FloatT) or isinstance(t, (FixedT, Const)) else None
        if isinstance(e, N.BinOp):
            return self.binop(e, env)
        if isinstance(e, N.TypeCall):
            t = self.i.resolve(e.type)
            for a in e.args:
                at = self.expr(a, env)
                if isinstance(at, Const) and isinstance(t, FixedT):
                    self.range_check(at.n, t, e.line)
            return t
        if isinstance(e, N.Call):
            return self.call(e, env)
        for child in self.children(e):
            self.expr(child, env)
        return None

    @staticmethod
    def children(e):
        out = []
        for f in e._fields:
            v = getattr(e, f)
            if isinstance(v, N.Node):
                out.append(v)
            elif isinstance(v, (list, tuple)):
                for x in v:
                    if isinstance(x, N.Node):
                        out.append(x)
                    elif isinstance(x, (list, tuple)):
                        out.extend(y for y in x if isinstance(y, N.Node))
        return out

    def binop(self, e, env):
        op = e.op
        a, b = self.expr(e.left, env), self.expr(e.right, env)
        if op in ("and", "or", "xor") or op in COMPARE:
            return BoolT
        number = lambda t: self.integer(t) or t == FloatT                        # noqa: E731
        if op in ("/", "//") and isinstance(b, Const) and b.n == 0 and self.integer(a):
            raise TomatoError("division by zero (D05ab, D05ac): the divisor is the constant 0", e.line)
        if op == "/":
            if isinstance(a, Const) and isinstance(b, Const):
                try:
                    a.n / b.n
                except OverflowError:
                    raise TomatoError("division result overflows float (D05af, D05ag)", e.line)
            return FloatT if number(a) and number(b) else None
        if op in ("+", "-", "*", "%", "//", "**") and number(a) and number(b) and FloatT in (a, b):
            return FloatT                                                       # a whole number with a float (P58)
        if op == "**" and self.integer(a) and self.integer(b):
            if isinstance(b, Const) and b.n < 0:
                raise TomatoError("a whole number to a negative power: write the base as a float, like 2.0 ** -2 (P57)", e.line)
            return self.widen(a) if isinstance(a, Const) else a
        if op in ("+", "-", "*") and isinstance(a, Const) and isinstance(b, Const):
            return Const(a.n + b.n if op == "+" else a.n - b.n if op == "-" else a.n * b.n)
        if op in ("+", "-", "*", "%", "//", "&", "|", "^") and self.integer(a) and self.integer(b):
            ta, tb = self.widen(a), self.widen(b)
            if op == "//" and (isinstance(a, Const) or isinstance(b, Const)):
                return ta if isinstance(b, Const) and not isinstance(a, Const) else tb if isinstance(a, Const) and not isinstance(b, Const) else INT
            if ta == tb or isinstance(a, Const):
                return tb
            if isinstance(b, Const):
                return ta
            if contains(ta, tb):
                return ta
            if contains(tb, ta):
                return tb
            return None
        if op == "+" and a == StrT and b == StrT:
            return StrT
        self.clash(op, a, b, e.line)
        return None

    @staticmethod
    def integer(t):
        return isinstance(t, (Const, IntT, FixedT))

    def clash(self, op, a, b, line):
        """Two known, different, non-numeric types cannot be combined by an arithmetic operator (D04a)."""
        if op not in ("+", "-", "*", "/", "//", "**", "%", "&", "|", "^") or a is None or b is None:
            return
        if not (self.concrete(a) and self.concrete(b)):
            return
        numeric = lambda t: self.integer(t) or t in (FloatT, RationalT)          # noqa: E731
        if self.widen(a) == self.widen(b) or (numeric(a) and numeric(b)):
            return
        raise TomatoError("type error: cannot use %s with %r and %r" % (op, self.widen(a), self.widen(b)), line)

    def call(self, e, env):
        f = e.func
        arg_types = [self.expr(a, env) for a in e.args]
        for _k, v in (e.kwargs or []):
            self.expr(v, env)
        if isinstance(f, N.Attr):
            self.expr(f.obj, env)
            return None
        if not isinstance(f, N.Name) or f.name in env:
            return None
        if f.name == "rational" and len(arg_types) == 2 and isinstance(arg_types[1], Const) and arg_types[1].n == 0 \
                and self.integer(arg_types[0]):
            raise TomatoError("rational with denominator zero (D05ao, D05ap)", e.line)
        key = self.i.scope_get(f.name)
        fi = self.i.funcs.get(key)
        if fi is not None:
            if not e.kwargs and not any(isinstance(a, N.Name) and False for a in e.args):
                plain = fi.star is None and fi.kwstar is None
                if plain and len(e.args) <= len(fi.ptypes):
                    for a, at, pt in zip(e.args, arg_types, fi.ptypes):
                        if at is not None:
                            self.fit(at, pt, a, e.line, "argument")
            return fi.ret
        if key in self.i.classes:
            return ClassT(key)
        if f.name == "len":
            return INT
        if f.name == "str":
            return StrT
        if f.name == "float":
            return FloatT
        return None

    # ---------------------------------------------------------------- fitting
    def range_check(self, n, t, line):
        lo, hi = t.range()
        if not lo <= n <= hi:
            raise TomatoError("%d does not fit %r (D05r, D05x)" % (n, t), line)

    def fit(self, vt, t, node, line, what):
        """Report when a value of static type `vt` can never be used as `t`; stay silent when unsure."""
        if not self.certain_mismatch(vt, t, line):
            return
        raise TomatoError("%s of type %r does not fit %r" % (what, self.widen(vt), t), line)

    def certain_mismatch(self, vt, t, line):
        if isinstance(t, OptT):
            return vt != NoneT and self.certain_mismatch(vt, t.inner, line)
        if isinstance(t, UnionT):
            return all(self.certain_mismatch(vt, m, line) for m in t.members)
        if isinstance(t, InterT):
            return False
        if vt == NoneT:
            return t != NoneT and t is not None and not isinstance(t, (UnionT, InterT)) and self.concrete(t)
        if isinstance(t, FixedT):
            if isinstance(vt, Const):
                self.range_check(vt.n, t, line)
                return False
            if isinstance(vt, FixedT):
                return not contains(t, vt)
            if isinstance(vt, IntT):
                raise TomatoError("%r cannot be used as %r without an explicit conversion (D05o)" % ("value", t), line)
            return self.concrete(vt)
        if isinstance(t, IntT):
            if self.integer(vt):
                return False
            return self.concrete(vt)
        if t in (StrT, BoolT, FloatT, RationalT):
            return self.concrete(vt) and self.widen(vt) != t
        if isinstance(t, (ClassT, IfaceT)):
            return self.concrete(vt)
        if isinstance(t, ListT):
            return self.concrete(vt)
        return False


def check(interp):
    Checker(interp).run()
