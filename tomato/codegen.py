"""Compiles a core subset of Tomato to LLVM IR text (D30a).

PROVISIONAL (P36, P39): the subset is whole numbers (`int` as 64-bit with an overflow check, until a big-number
runtime exists; `int[length=N]`/`uint[length=N]` up to 64 bits), `float`, `bool`, functions, `if`, `while`,
`for ... in range(...)` and `for ... in a_list`, `break`, `continue`, recursion, `print`, and an entry point whose
inputs come from the command line. Heap values are reference counted (D29a): strings, `list[T]` and class
instances (fields, methods, `@init`, single inheritance with `override` through vtables, class functions), each
with a header {reference count, type code} (D35a). Everything else stops with "the compiler does not support ...
yet". The IR uses opaque pointers (`ptr`), so it needs LLVM 15 or newer. It links with tomato/runtime/tomato_rt.c.

Ownership rule: every expression of a heap type yields a reference the caller owns (+1). A consumer either
transfers it (storing it, returning it) or releases it. Locals, including parameters, own their value and are
released in a single epilogue that every return passes through.
"""
from . import nodes as N
from . import errcodes
from .errors import NotDecided, TomatoError
from .interp import Interpreter
from .values import BoolT, ClassT, FileT, FixedT, FloatT, INT, IntT, IfaceT, ListT, MapT, NoneT, OptT, SetT, StrT, contains, is_int_type


class NotCompiled(TomatoError):
    def __init__(self, what, line=None):
        super().__init__("the compiler does not support %s yet" % what, line)


def is_signed(t):
    return isinstance(t, IntT) or t.signed


def bits_of(t):
    return 64 if isinstance(t, IntT) else t.bits


def llvm_type(t):
    if isinstance(t, IntT):
        return "i64"
    if isinstance(t, FixedT):
        if t.bits > 64:
            raise NotCompiled("integers wider than 64 bits")
        return "i%d" % t.bits
    if t == FloatT:
        return "double"
    if t == BoolT:
        return "i1"
    if isinstance(t, OptT):
        if not is_rc(t.inner):
            raise NotCompiled("optional integers, floats and bools (T | None where T is not a heap type)")
        return "ptr"                       # None is the null pointer (D23b)
    if t == StrT or isinstance(t, (ListT, ClassT, IfaceT, MapT, SetT)):
        return "ptr"
    if t == NoneT:
        return "void"
    if t == FileT:
        return "ptr"                       # a FILE* the program closes itself (D38a)
    raise NotCompiled("values of type %r" % (t,))


def is_rc(t):
    """Heap values that are reference counted (D29a)."""
    return t == StrT or isinstance(t, (ListT, ClassT, IfaceT, MapT, SetT)) or (isinstance(t, OptT) and is_rc(t.inner))


def signed_repr(n, t):
    """A decimal LLVM accepts for an N-bit integer constant: unsigned values above the signed range wrap."""
    b = bits_of(t)
    n &= (1 << b) - 1
    return str(n - (1 << b) if n >= (1 << (b - 1)) else n)


def double_repr(x):
    import struct
    return "0x%016X" % struct.unpack(">Q", struct.pack(">d", x))[0]



NODE_NAMES = {"MapLit": "dict literals", "SetLit": "set literals", "Raise": "raise", "Try": "try, catch and finally",
              "LlvmRef": "references to LLVM functions that are not calls"}


class Unit:
    """What a compiled function needs from the compiler: its symbol, parameter types, result type and AST."""

    def __init__(self, symbol, node, ptypes, ret, owner=None, name=None):
        self.symbol, self.node, self.ptypes, self.ret, self.owner = symbol, node, ptypes, ret, owner
        self.name = name or node.name


class FuncCompiler:
    def __init__(self, cg, unit):
        self.cg, self.fn = cg, unit
        self.line = unit.node.line if unit.node is not None else 0
        self.lines, self.allocas = [], []
        self.n = 0
        self.terminated = False
        self.vars = {}            # name -> (alloca register, type)
        self.rc_slots = []        # registers of slots that own a heap value, released in the epilogue
        self.loops = []           # (break label, continue label)
        self.fail_blocks = []     # (label, kind, line): blocks that report an error and stop
        self.callees = set()      # symbols of the Tomato functions this function calls
        self.tries = []           # the try statements being compiled, innermost last (D22a)

    # ---- emission helpers
    def tmp(self, hint="t"):
        self.n += 1
        return "%%%s.%d" % (hint, self.n)

    def label(self, hint="L"):
        self.n += 1
        return "%s.%d" % (hint, self.n)

    def emit(self, text):
        if self.terminated:
            self.lines.append("%s:" % self.label("dead"))
            self.terminated = False
        self.lines.append("  " + text)

    def place(self, label):
        self.lines.append("%s:" % label)
        self.terminated = False

    def br(self, label):
        self.emit("br label %%%s" % label)
        self.terminated = True

    def cond_br(self, c, yes, no):
        self.emit("br i1 %s, label %%%s, label %%%s" % (c, yes, no))
        self.terminated = True

    def fail(self, kind, hint="trap"):
        """Registers a block that reports a failure of this kind (see errcodes) and stops; returns its label."""
        lab = self.label(hint)
        self.fail_blocks.append((lab, kind, self.line, self.unwind_target()))
        rt = self.cg.runtime_error_class()
        self.callees.add(self.cg.ctor_symbol(rt))
        return lab

    def unwind_target(self):
        """Where an error raised here goes: the innermost try's catch (or its finally, once past the body), else
        out of the function, which returns early so that its caller can check (D22a)."""
        if self.tries:
            t = self.tries[-1]
            return t["catch"] if t["state"] == "body" else t["prop"]
        return "epilogue"

    def trap_if(self, cond, kind):
        bad, ok = self.fail(kind), self.label("ok")
        self.cond_br(cond, bad, ok)
        self.place(ok)

    def slot(self, name, t, line):
        if name not in self.vars:
            self.slot_count = getattr(self, "slot_count", 0) + 1
            reg = "%%v.%s.%d" % (name, self.slot_count)
            self.allocas.append("  %s = alloca %s" % (reg, llvm_type(t)))
            if is_rc(t):
                self.allocas.append("  store ptr null, ptr %s" % reg)
                self.rc_slots.append(reg)
            self.vars[name] = (reg, t)
        return self.vars[name]

    def hidden_slot(self, hint, t):
        reg = self.tmp(hint)
        self.allocas.append("  %s = alloca %s" % (reg, llvm_type(t)))
        if is_rc(t):
            self.allocas.append("  store ptr null, ptr %s" % reg)
            self.rc_slots.append(reg)
        return reg

    # ---- reference counting (D29a)
    def retain(self, v, t):
        if is_rc(t):
            self.emit("call void @tomato_retain(ptr %s)" % v)

    def release(self, v, t):
        if is_rc(t) and v is not None:
            self.emit("call void @tomato_release(ptr %s)" % v)

    def store_owned(self, reg, v, t):
        """Store an owned value into a slot, releasing what the slot held (the slot takes over the reference)."""
        if is_rc(t):
            old = self.tmp("old")
            self.emit("%s = load ptr, ptr %s" % (old, reg))
            self.emit("store ptr %s, ptr %s" % (v, reg))
            self.emit("call void @tomato_release(ptr %s)" % old)
        else:
            self.emit("store %s %s, ptr %s" % (llvm_type(t), v, reg))

    # ---- types and conversions
    def subclass(self, sub, sup):
        info = self.cg.interp.classes.get(sub.name)
        return info is not None and self.cg.interp.is_subclass(info, sup.name)

    def unwrap(self, v, t, line):
        """Use an optional where a value is needed: if it is None the program raises an error (D23b)."""
        if not isinstance(t, OptT):
            return v, t
        isnull = self.tmp("isnone")
        self.emit("%s = icmp eq ptr %s, null" % (isnull, v))
        self.trap_if(isnull, "none")
        return v, t.inner

    def coerce(self, v, ft, tt, line, what="value"):
        if ft == tt:
            return v
        if isinstance(tt, OptT):
            if ft == NoneT:
                return "null"
            if isinstance(ft, OptT):
                return self.coerce(v, ft.inner, tt.inner, line, what)
            return self.coerce(v, ft, tt.inner, line, what)
        if ft == NoneT:
            raise TomatoError("type error: None where %r is expected; write the type as %r | None (D23b)" % (tt, tt), line)
        if isinstance(ft, OptT):
            v, ft = self.unwrap(v, ft, line)
            return self.coerce(v, ft, tt, line, what)
        if is_int_type(ft) and is_int_type(tt):
            if not contains(tt, ft):
                raise TomatoError("%s of type %r cannot be used as %r without an explicit conversion (D05o)"
                                  % (what, ft, tt), line)
            return self.resize(v, ft, tt)
        if isinstance(ft, ClassT) and isinstance(tt, ClassT) and self.subclass(ft, tt):
            return v            # a subclass instance is used where its parent is expected: the same pointer (D12ay)
        interp = self.cg.interp
        if isinstance(tt, IfaceT) and isinstance(ft, ClassT) and tt.name in interp.class_ifaces(interp.classes[ft.name]):
            return v            # an instance of a class that implements the interface fits it (D12bb)
        if isinstance(tt, IfaceT) and isinstance(ft, IfaceT) and tt.name in interp.iface_closure(ft.name):
            return v            # an interface fits the interfaces it extends (D12bc)
        raise TomatoError("%s of type %r does not fit %r" % (what, ft, tt), line)

    def resize(self, v, ft, tt):
        fb, tb = bits_of(ft), bits_of(tt)
        if fb == tb:
            return v
        r = self.tmp("ext")
        self.emit("%s = %s %s %s to %s" % (r, "sext" if is_signed(ft) else "zext", llvm_type(ft), v, llvm_type(tt)))
        return r

    def common(self, a, b, line):
        if contains(a, b):
            return a
        if contains(b, a):
            return b
        raise TomatoError("no common integer type for %r and %r (D05s)" % (a, b), line)

    # ---- expressions: each returns (value text, type); a heap value is owned by the caller (+1)
    def literal_only(self, e):
        if isinstance(e, N.IntLit):
            return True
        if isinstance(e, N.UnOp) and e.op == "-":
            return self.literal_only(e.operand)
        return isinstance(e, N.BinOp) and e.op in ("+", "-", "*") and \
            self.literal_only(e.left) and self.literal_only(e.right)

    def const_int(self, n, t, line):
        if isinstance(t, FixedT):
            lo, hi = t.range()
            if not lo <= n <= hi:
                raise TomatoError("%d does not fit %r (D05r, D05x)" % (n, t), line)
        elif not -(1 << 63) <= n < (1 << 63):
            raise TomatoError("%d does not fit the 64-bit int the compiler uses for now (P36)" % n, line)
        return signed_repr(n, t), t

    def expr(self, e, expected=None):
        if e.line:
            self.line = e.line
        if isinstance(e, N.IntLit):
            return self.const_int(e.value, expected if is_int_type(expected) else INT, e.line)
        if isinstance(e, N.BoolLit):
            return ("1" if e.value else "0"), BoolT
        if isinstance(e, N.StrLit):
            return self.cg.strobj(e.value), StrT          # a static object that is never freed
        if isinstance(e, N.Name):
            if e.name == "None" and e.name not in self.vars:
                return "null", NoneT
            if e.name not in self.vars:
                raise TomatoError("unknown name %r" % e.name, e.line)
            reg, t = self.vars[e.name]
            r = self.tmp(e.name)
            self.emit("%s = load %s, ptr %s" % (r, llvm_type(t), reg))
            self.retain(r, t)
            return r, t
        if isinstance(e, N.UnOp):
            return self.unop(e, expected)
        if isinstance(e, N.BinOp):
            return self.binop(e, expected)
        if isinstance(e, N.Call):
            return self.call(e, expected)
        if isinstance(e, N.TypeCall):
            return self.explicit(e)
        if isinstance(e, N.Attr):
            return self.field_read(e)
        if isinstance(e, N.Index):
            return self.index(e)
        if isinstance(e, N.Slice):
            return self.slice(e)
        if isinstance(e, N.ListLit):
            return self.list_literal(e, expected)
        if isinstance(e, N.MapLit):
            return self.dict_literal(e, expected)
        if isinstance(e, N.SetLit):
            return self.set_literal(e, expected)
        raise NotCompiled(NODE_NAMES.get(type(e).__name__, type(e).__name__.lower() + " expressions"), e.line)

    def unop(self, e, expected):
        if e.op == "not":
            v, t = self.expr(e.operand)
            if t != BoolT:
                raise TomatoError("a condition must be a bool, found %r (truthiness is not yet decided)" % (t,), e.line)
            r = self.tmp("not")
            self.emit("%s = xor i1 %s, 1" % (r, v))
            return r, BoolT
        if isinstance(e.operand, N.IntLit) and is_int_type(expected):
            return self.const_int(-e.operand.value, expected, e.line)
        v, t = self.expr(e.operand, expected)
        if not is_int_type(t):
            raise NotDecided("negating %r" % (t,), e.line)
        return self.arith("-", "0", t, v, t, e.line)

    def arith(self, op, a, ta, b, tb, line):
        t = self.common(ta, tb, line)
        a, b = self.resize(a, ta, t), self.resize(b, tb, t)
        kind = {"+": "add", "-": "sub", "*": "mul"}[op]
        intr = "llvm.%s%s.with.overflow.%s" % ("s" if is_signed(t) else "u", kind, llvm_type(t))
        self.cg.declares.add("declare {%s, i1} @%s(%s, %s)" % (llvm_type(t), intr, llvm_type(t), llvm_type(t)))
        pair, r, ov = self.tmp("pair"), self.tmp("r"), self.tmp("ov")
        self.emit("%s = call {%s, i1} @%s(%s %s, %s %s)" % (pair, llvm_type(t), intr, llvm_type(t), a, llvm_type(t), b))
        self.emit("%s = extractvalue {%s, i1} %s, 0" % (r, llvm_type(t), pair))
        self.emit("%s = extractvalue {%s, i1} %s, 1" % (ov, llvm_type(t), pair))
        self.trap_if(ov, "overflow")
        return r, t

    def to_double(self, v, t):
        r = self.tmp("fp")
        self.emit("%s = %s %s %s to double" % (r, "sitofp" if is_signed(t) else "uitofp", llvm_type(t), v))
        return r

    def binop(self, e, expected):
        op = e.op
        if op in ("and", "or"):
            return self.logic(e)
        if op in ("&", "|", "^"):
            raise NotCompiled("bitwise operators", e.line)
        if op == "xor":
            a, ta = self.expr(e.left)
            b, tb = self.expr(e.right)
            if ta != BoolT or tb != BoolT:
                raise TomatoError("a condition must be a bool, found %r and %r (truthiness is not yet decided)" % (ta, tb), e.line)
            r = self.tmp("xor")
            self.emit("%s = xor i1 %s, %s" % (r, a, b))
            return r, BoolT
        if op in ("+", "-", "*"):
            if self.literal_only(e) and is_int_type(expected):
                a, ta = self.expr(e.left, expected)
                b, tb = self.expr(e.right, expected)
                return self.arith(op, a, ta, b, tb, e.line)
            ll, rl = self.literal_only(e.left), self.literal_only(e.right)
            if ll and not rl:
                b, tb = self.expr(e.right)
                a, ta = self.expr(e.left, tb if is_int_type(tb) else None)
            elif rl and not ll:
                a, ta = self.expr(e.left)
                b, tb = self.expr(e.right, ta if is_int_type(ta) else None)
            else:
                a, ta = self.expr(e.left)
                b, tb = self.expr(e.right)
            a, ta = self.unwrap(a, ta, e.line)
            b, tb = self.unwrap(b, tb, e.line)
            if ta == tb == StrT and op == "+":
                return self.concat(a, b)
            if isinstance(ta, ClassT):
                if op != "+":
                    self.release(a, ta)
                    self.release(b, tb)
                    raise NotDecided("operators other than + on instances", e.line)
                return self.add_operator(a, ta, b, tb, e.line)
            if isinstance(tb, ClassT):
                self.release(a, ta)
                self.release(b, tb)
                raise TomatoError("type error: cannot use %s with %r and %r" % (op, ta, tb), e.line)
            if not (is_int_type(ta) and is_int_type(tb)):
                self.clash(op, ta, tb, e.line)
                if ta == tb == StrT:
                    raise NotCompiled("string operations other than +", e.line)
                raise NotDecided("%s on %r and %r (only integer + - * are decided)" % (op, ta, tb), e.line)
            return self.arith(op, a, ta, b, tb, e.line)
        if op == "in" and isinstance(e.right, N.Name) and e.right.name not in self.vars \
                and self.cg.interp.type_named(e.right.name) is not None:
            return self.type_test(e)                         # `x in Type` (D23e, D23f)
        a, ta = self.expr(e.left)
        b, tb = self.expr(e.right)
        if op in ("/", "%"):
            a, ta = self.unwrap(a, ta, e.line)
            b, tb = self.unwrap(b, tb, e.line)
        if op in ("is", "is not"):
            return self.compare(op, a, ta, b, tb, e.line)
        if op == "in":
            return self.contains(a, ta, b, tb, e.line)
        if op == "/":
            self.clash(op, ta, tb, e.line)
            if not (is_int_type(ta) and is_int_type(tb)):
                raise NotDecided("/ on %r and %r (only integer / integer is decided)" % (ta, tb), e.line)
            z = self.tmp("zero")
            self.emit("%s = icmp eq %s %s, 0" % (z, llvm_type(tb), b))
            self.trap_if(z, "division by zero")
            r = self.tmp("div")
            self.emit("%s = fdiv double %s, %s" % (r, self.to_double(a, ta), self.to_double(b, tb)))
            return r, FloatT
        if op == "%":
            self.clash(op, ta, tb, e.line)
            if not (is_int_type(ta) and is_int_type(tb)):
                raise NotDecided("% on non-integers", e.line)
            return self.modulo(a, ta, b, tb, e.line)
        return self.compare(op, a, ta, b, tb, e.line)

    def add_operator(self, a, ta, b, tb, line):
        """`a + b` on an instance runs the left object's @add method with the right operand (D12j-l)."""
        info = self.cg.interp.classes[ta.name]
        m = info.nearest("add")
        if m is None:
            self.release(a, ta)
            self.release(b, tb)
            raise TomatoError("%s has no @add method" % info.node.name, line)
        if m.node.private and self.fn.owner is not m.owner:
            self.release(a, ta)
            self.release(b, tb)
            raise TomatoError("method %s is private to class %s (D12ac, D12r)" % (m.name, m.owner.name), line)
        pt = m.ptypes[0]
        args = [("ptr %s" % a, a, ta), ("%s %s" % (llvm_type(pt), self.coerce(b, tb, pt, line, "operand")), b, tb)]
        for impl in self.cg.implementations(info, m.name):
            self.callees.add(self.cg.func_symbol(impl))
        target = self.cg.dispatch(self, a, m.name) if self.cg.has_subclasses(info) else "@" + self.cg.func_symbol(m)
        return self.finish_call("call %s %s(%s)" % (llvm_type(m.ret), target, ", ".join(x[0] for x in args)), m.ret, args)

    def concat(self, a, b):
        r = self.tmp("cat")
        self.emit("%s = call ptr @tomato_str_concat(ptr %s, ptr %s)" % (r, a, b))
        self.release(a, StrT)
        self.release(b, StrT)
        return r, StrT

    def clash(self, op, ta, tb, line):
        """A known type mismatch is a type error (D04a); mixed numbers stay undecided."""
        numeric = lambda t: is_int_type(t) or t == FloatT  # noqa: E731
        if ta != tb and not (numeric(ta) and numeric(tb)):
            if isinstance(ta, (ClassT, IfaceT)) and isinstance(tb, (ClassT, IfaceT)):
                return
            raise TomatoError("type error: cannot use %s with %r and %r" % (op, ta, tb), line)

    def modulo(self, a, ta, b, tb, line):
        t = self.common(ta, tb, line)
        a, b = self.resize(a, ta, t), self.resize(b, tb, t)
        lt = llvm_type(t)
        z = self.tmp("zero")
        self.emit("%s = icmp eq %s %s, 0" % (z, lt, b))
        self.trap_if(z, "modulo by zero")
        r = self.tmp("rem")
        if not is_signed(t):
            self.emit("%s = urem %s %s, %s" % (r, lt, a, b))
            return r, t
        m1, d, q, nz, sg, neg, adj, out = [self.tmp(x) for x in ("m1", "d", "q", "nz", "sg", "neg", "adj", "mod")]
        self.emit("%s = icmp eq %s %s, -1" % (m1, lt, b))          # x % -1 is 0 (avoids the INT_MIN trap)
        self.emit("%s = select i1 %s, %s 1, %s %s" % (d, m1, lt, lt, b))
        self.emit("%s = srem %s %s, %s" % (q, lt, a, d))
        self.emit("%s = icmp ne %s %s, 0" % (nz, lt, q))
        self.emit("%s = xor %s %s, %s" % (sg, lt, q, b))
        self.emit("%s = icmp slt %s %s, 0" % (neg, lt, sg))
        self.emit("%s = and i1 %s, %s" % (adj, nz, neg))           # remainder takes the divisor's sign (D05au)
        fixed = self.tmp("fix")
        self.emit("%s = add %s %s, %s" % (fixed, lt, q, b))
        self.emit("%s = select i1 %s, %s %s, %s %s" % (out, adj, lt, fixed, lt, q))
        res = self.tmp("res")
        self.emit("%s = select i1 %s, %s 0, %s %s" % (res, m1, lt, lt, out))
        return res, t

    def none_test(self, op, a, ta, b, tb, line):
        """`x is None`, `x == None` and their negations (D23b)."""
        eq = op in ("is", "==")
        other, to = (b, tb) if ta == NoneT else (a, ta)
        r = self.tmp("isnone")
        if is_rc(to) or isinstance(to, OptT):
            self.emit("%s = icmp %s ptr %s, null" % (r, "eq" if eq else "ne", other))
            self.release(other, to) if is_rc(to) else None
            return r, BoolT
        return ("0" if eq else "1"), BoolT          # a plain number, float or bool is never None

    def compare(self, op, a, ta, b, tb, line):
        if ta == NoneT or tb == NoneT:
            if ta == NoneT and tb == NoneT:
                return ("1" if op in ("is", "==") else "0"), BoolT
            return self.none_test(op, a, ta, b, tb, line)
        if op in ("is", "is not"):
            if isinstance(ta, (ClassT, IfaceT, OptT)) and isinstance(tb, (ClassT, IfaceT, OptT)):
                r = self.tmp("same")
                self.emit("%s = icmp %s ptr %s, %s" % (r, "eq" if op == "is" else "ne", a, b))
                self.release(a, ta)
                self.release(b, tb)
                return r, BoolT
            raise NotDecided("`is` with %r and %r (only None and objects are decided)" % (ta, tb), line)
        if isinstance(ta, OptT) or isinstance(tb, OptT):
            ia = ta.inner if isinstance(ta, OptT) else ta
            ib = tb.inner if isinstance(tb, OptT) else tb
            if op in ("==", "!=") and ia == ib == StrT:
                c, r = self.tmp("seq"), self.tmp("cmp")
                self.emit("%s = call i32 @tomato_str_eq_opt(ptr %s, ptr %s)" % (c, a, b))
                self.emit("%s = icmp %s i32 %s, 0" % (r, "ne" if op == "==" else "eq", c))
                self.release(a, ta)
                self.release(b, tb)
                return r, BoolT
            if op in ("==", "!=") and isinstance(ia, (ClassT, IfaceT)) and isinstance(ib, (ClassT, IfaceT)):
                r = self.tmp("cmp")
                self.emit("%s = icmp %s ptr %s, %s" % (r, "eq" if op == "==" else "ne", a, b))
                self.release(a, ta)
                self.release(b, tb)
                return r, BoolT
            if ia != ib and not (is_int_type(ia) and is_int_type(ib)):
                raise TomatoError("type error: cannot use %s with %r and %r" % (op, ta, tb), line)
            raise NotCompiled("comparing optional values other than for equality", line)
        self.clash(op, ta, tb, line)
        if is_int_type(ta) and is_int_type(tb):
            t = self.common(ta, tb, line)
            a, b = self.resize(a, ta, t), self.resize(b, tb, t)
            pred = {"==": "eq", "!=": "ne"}.get(op) or ("s" if is_signed(t) else "u") + {"<": "lt", "<=": "le", ">": "gt", ">=": "ge"}[op]
            r = self.tmp("cmp")
            self.emit("%s = icmp %s %s %s, %s" % (r, pred, llvm_type(t), a, b))
            return r, BoolT
        if ta == tb == FloatT:
            pred = {"==": "oeq", "!=": "une", "<": "olt", "<=": "ole", ">": "ogt", ">=": "oge"}[op]
            r = self.tmp("cmp")
            self.emit("%s = fcmp %s double %s, %s" % (r, pred, a, b))
            return r, BoolT
        if ta == tb == BoolT and op in ("==", "!="):
            r = self.tmp("cmp")
            self.emit("%s = icmp %s i1 %s, %s" % (r, "eq" if op == "==" else "ne", a, b))
            return r, BoolT
        if ta == tb == StrT:
            c, r = self.tmp("scmp"), self.tmp("cmp")
            self.emit("%s = call i32 @tomato_str_cmp(ptr %s, ptr %s)" % (c, a, b))
            pred = {"==": "eq", "!=": "ne", "<": "slt", "<=": "sle", ">": "sgt", ">=": "sge"}[op]
            self.emit("%s = icmp %s i32 %s, 0" % (r, pred, c))
            self.release(a, StrT)
            self.release(b, StrT)
            return r, BoolT
        if isinstance(ta, (ClassT, IfaceT)) and isinstance(tb, (ClassT, IfaceT)) and op in ("==", "!="):
            r = self.tmp("cmp")
            self.emit("%s = icmp %s ptr %s, %s" % (r, "eq" if op == "==" else "ne", a, b))   # identity
            self.release(a, ta)
            self.release(b, tb)
            return r, BoolT
        raise NotDecided("comparing %r with %r" % (ta, tb), line)

    def cond(self, e):
        v, t = self.expr(e)
        if t != BoolT:
            raise TomatoError("a condition must be a bool, found %r (truthiness is not yet decided)" % (t,), e.line)
        return v

    def logic(self, e):
        a = self.cond(e.left)
        here = self.current_label()
        rhs, end = self.label("rhs"), self.label("join")
        if e.op == "and":
            self.cond_br(a, rhs, end)
        else:
            self.cond_br(a, end, rhs)
        self.place(rhs)
        b = self.cond(e.right)
        rhs_end = self.current_label()
        self.br(end)
        self.place(end)
        r = self.tmp("logic")
        short = "0" if e.op == "and" else "1"
        self.emit("%s = phi i1 [ %s, %%%s ], [ %s, %%%s ]" % (r, short, here, b, rhs_end))
        return r, BoolT

    def current_label(self):
        for line in reversed(self.lines):
            if line.endswith(":") and not line.startswith(" "):
                return line[:-1]
        return "entry"

    def explicit(self, e):
        target = self.cg.interp.resolve(e.type)
        v, t = self.expr(e.args[0])
        return self.convert_explicit(v, t, target, e.line)

    def convert_explicit(self, v, t, target, line):
        if not is_int_type(t):
            raise TomatoError("only integers convert this way, found %r" % (t,), line)
        if contains(target, t):
            return self.resize(v, t, target), target
        wide = self.tmp("wide")
        self.emit("%s = %s %s %s to i128" % (wide, "sext" if is_signed(t) else "zext", llvm_type(t), v))
        lo, hi = target.range()
        a, b, bad = self.tmp("lo"), self.tmp("hi"), self.tmp("bad")
        self.emit("%s = icmp slt i128 %s, %d" % (a, wide, lo))
        self.emit("%s = icmp sgt i128 %s, %d" % (b, wide, hi))
        self.emit("%s = or i1 %s, %s" % (bad, a, b))
        self.trap_if(bad, "conversion")
        r = self.tmp("conv")
        self.emit("%s = trunc i128 %s to %s" % (r, wide, llvm_type(target)))
        return r, target

    # ---- calls
    def eval_args(self, args, ptypes, line, fn=None):
        """Evaluate call arguments against the parameter types; returns [(text, owned value, type)]. A parameter the
        caller left out gets its default, compiled here and evaluated at each call (D19c)."""
        out = []
        for a, pt in zip(args, ptypes):
            v, t = self.expr(a, pt)
            out.append(("%s %s" % (llvm_type(pt), self.coerce(v, t, pt, line, "argument")), v, t))
        return self.fill_defaults(out, ptypes, fn, line)

    def fill_defaults(self, out, ptypes, fn, line):
        for k in range(len(out), len(ptypes)):
            default = fn.defaults[k]
            saved, self.vars = self.vars, {}              # a default cannot see the caller's variables
            try:
                v, t = self.expr(default, ptypes[k])
            finally:
                self.vars = saved
            out.append(("%s %s" % (llvm_type(ptypes[k]), self.coerce(v, t, ptypes[k], line, "default argument")), v, t))
        return out

    def arity_ok(self, fn, ptypes, n):
        if getattr(fn, "star", None) is not None or getattr(fn, "kwstar", None) is not None:
            raise NotCompiled("*args and **kwargs parameters")
        return getattr(fn, "min_args", len(ptypes)) <= n <= len(ptypes)

    def finish_call(self, text, ret, args, hint="call", can_raise=True):
        """Emit a call, release the argument temporaries the callee only borrowed, and return the owned result."""
        if llvm_type(ret) == "void":
            self.emit(text)
            r = None
        else:
            r = self.tmp(hint)
            self.emit("%s = %s" % (r, text))
        if can_raise:
            self.check_error(args)
        for _, v, t in args:
            self.release(v, t)
        return r, ret

    def check_error(self, args=()):
        """After a call that may have raised: if an error is pending, drop the argument temporaries the call
        borrowed and go to the nearest handler (D22a)."""
        ex, has = self.tmp("ex"), self.tmp("has")
        self.emit("%s = load ptr, ptr @tomato_exc" % ex)
        self.emit("%s = icmp ne ptr %s, null" % (has, ex))
        bad, ok = self.label("raised"), self.label("fine")
        self.cond_br(has, bad, ok)
        self.place(bad)
        for _, v, t in args:
            self.release(v, t)
        self.br(self.unwind_target())
        self.place(ok)

    def call(self, e, expected=None):
        f = e.func
        if e.kwargs:
            raise NotCompiled("keyword arguments", e.line)
        if isinstance(f, N.Name) and f.name == "print":
            self.print_call(e)
            return None, NoneT
        if isinstance(f, N.LlvmRef):
            return self.llvm_call(e)
        if isinstance(f, N.Name) and f.name == "int":
            if len(e.args) != 1:
                raise TomatoError("int(x) takes one argument", e.line)
            v, t = self.expr(e.args[0])
            return self.convert_explicit(v, t, INT, e.line)
        if isinstance(f, N.Name) and f.name == "len":
            return self.len_call(e)
        if isinstance(f, N.Name) and f.name == "open" and "open" not in self.vars:
            return self.open_call(e)
        if isinstance(f, N.Name) and f.name == "str":
            return self.str_call(e)
        if isinstance(f, N.Name) and f.name not in self.vars:
            fkey = self.cg.interp.scope_get(f.name)
            fn = self.cg.interp.funcs.get(fkey)
            if fn is not None:
                if not self.arity_ok(fn, fn.ptypes, len(e.args)):
                    raise TomatoError("%s takes %d argument(s), got %d" % (fn.name, len(fn.ptypes), len(e.args)), e.line)
                sym = self.cg.func_symbol(fn)
                self.callees.add(sym)
                args = self.eval_args(e.args, fn.ptypes, e.line, fn)
                return self.finish_call("call %s @%s(%s)" % (llvm_type(fn.ret), sym, ", ".join(a[0] for a in args)),
                                        fn.ret, args)
            cls = self.cg.interp.classes.get(fkey)
            if cls is not None:
                return self.construct(cls, e)
        if isinstance(f, N.Attr):
            return self.method_call(e)
        if isinstance(f, N.Name):
            raise NotCompiled("calling %s (dicts, sets, errors, files and most built-ins are not compiled)" % f.name, e.line)
        raise NotCompiled("this kind of call", e.line)

    def llvm_call(self, e):
        """A call to a declared LLVM function (D27b): the declaration gives the types, the linker the body."""
        decl = self.cg.interp.llvm_decls.get(e.func.name)
        if decl is None:
            raise TomatoError("!%s is not declared: add `!%s(a: T) -> R` at the top level (D27b)"
                              % (e.func.name, e.func.name), e.line)
        ptypes, ret = decl
        if len(e.args) != len(ptypes):
            raise TomatoError("!%s takes %d argument(s), got %d" % (e.func.name, len(ptypes), len(e.args)), e.line)
        args = self.eval_args(e.args, ptypes, e.line)
        self.cg.declares.add("declare %s @%s(%s)" % (llvm_type(ret), e.func.name, ", ".join(a[0].split()[0] for a in args)))
        return self.finish_call("call %s @%s(%s)" % (llvm_type(ret), e.func.name, ", ".join(a[0] for a in args)), ret, args,
                                "llvm", can_raise=False)

    def len_call(self, e):
        if len(e.args) != 1:
            raise TomatoError("len(x) takes one argument", e.line)
        v, t = self.expr(e.args[0])
        v, t = self.unwrap(v, t, e.line)
        r = self.tmp("len")
        if t == StrT:
            self.emit("%s = call i64 @tomato_str_len(ptr %s)" % (r, v))
        elif isinstance(t, (ListT, MapT, SetT)):
            p = self.tmp("lenp")
            self.emit("%s = getelementptr { i64, i64, i64, i64, ptr }, ptr %s, i32 0, i32 2" % (p, v))
            self.emit("%s = load i64, ptr %s" % (r, p))
        else:
            raise NotDecided("len of %r (only text, lists, dicts and sets compile so far)" % (t,), e.line)
        self.release(v, t)
        return r, INT

    def open_call(self, e):
        """open(path) or open(path, mode): a file the program closes itself; failing to open raises (D38a)."""
        if not 1 <= len(e.args) <= 2:
            raise TomatoError("open(path) or open(path, mode) takes text", e.line)
        p, pt = self.expr(e.args[0])
        if pt != StrT:
            self.release(p, pt)
            raise TomatoError("open(path) or open(path, mode) takes text", e.line)
        if len(e.args) == 2:
            m, mt = self.expr(e.args[1])
            if mt != StrT:
                self.release(p, pt)
                self.release(m, mt)
                raise TomatoError("open(path) or open(path, mode) takes text", e.line)
        else:
            m, mt = self.cg.strobj("r"), None
        r = self.tmp("file")
        self.emit("%s = call ptr @tomato_file_open(ptr %s, ptr %s)" % (r, p, m))
        bad = self.tmp("nofile")
        self.emit("%s = icmp eq ptr %s, null" % (bad, r))
        self.release(p, pt)
        if mt is not None:
            self.release(m, mt)
        self.trap_if(bad, "file")
        return r, FileT

    def file_method(self, o, name, e):
        if name == "read" and not e.args:
            r = self.tmp("text")
            self.emit("%s = call ptr @tomato_file_read(ptr %s)" % (r, o))
            return r, StrT
        if name == "write" and len(e.args) == 1:
            s, st = self.expr(e.args[0])
            if st != StrT:
                self.release(s, st)
                raise TomatoError("write takes text", e.line)
            self.emit("call void @tomato_file_write(ptr %s, ptr %s)" % (o, s))
            self.release(s, st)
            return None, NoneT
        if name == "close" and not e.args:
            self.emit("call void @tomato_file_close(ptr %s)" % o)
            return None, NoneT
        raise NotCompiled("file method %s" % name, e.line)

    def str_method(self, o, name, e):
        """Text methods find, replace, split, startswith and endswith (D38a); the receiver is an owned temporary."""
        def text_args(n):
            if len(e.args) != n:
                self.release(o, StrT)
                raise TomatoError("%s takes %d argument(s), got %d" % (name, n, len(e.args)), e.line)
            out = []
            for a in e.args:
                v, t = self.expr(a)
                if t != StrT:
                    self.release(v, t)
                    self.release(o, StrT)
                    raise TomatoError("%s takes text, found %r" % (name, t), e.line)
                out.append(("ptr %s" % v, v, StrT))
            return out
        if name in ("find", "startswith", "endswith"):
            args = text_args(1)
            if name == "find":
                r = self.tmp("found")
                self.emit("%s = call i64 @tomato_str_find(ptr %s, ptr %s)" % (r, o, args[0][1]))
                self.release(args[0][1], StrT)
                self.release(o, StrT)
                return r, INT
            c, r = self.tmp("c"), self.tmp("starts")
            self.emit("%s = call i32 @tomato_str_%s(ptr %s, ptr %s)" % (c, name, o, args[0][1]))
            self.emit("%s = icmp ne i32 %s, 0" % (r, c))
            self.release(args[0][1], StrT)
            self.release(o, StrT)
            return r, BoolT
        if name == "replace":
            args = text_args(2)
            empty = self.tmp("empty")
            lenv = self.tmp("alen")
            self.emit("%s = call i64 @tomato_str_len(ptr %s)" % (lenv, args[0][1]))
            self.emit("%s = icmp eq i64 %s, 0" % (empty, lenv))
            self.trap_if(empty, "empty separator")
            r = self.tmp("replaced")
            self.emit("%s = call ptr @tomato_str_replace(ptr %s, ptr %s, ptr %s)" % (r, o, args[0][1], args[1][1]))
            for _, v, t in args:
                self.release(v, t)
            self.release(o, StrT)
            return r, StrT
        if name == "split":
            args = text_args(1)
            empty, lenv = self.tmp("empty"), self.tmp("alen")
            self.emit("%s = call i64 @tomato_str_len(ptr %s)" % (lenv, args[0][1]))
            self.emit("%s = icmp eq i64 %s, 0" % (empty, lenv))
            self.trap_if(empty, "empty separator")
            lt = ListT(StrT)
            r = self.tmp("pieces")
            self.emit("%s = call ptr @tomato_str_split(ptr %s, ptr %s, i64 %d, i64 %s)"
                      % (r, o, args[0][1], self.cg.type_code(lt), self.cg.size_of("ptr")))
            self.release(args[0][1], StrT)
            self.release(o, StrT)
            return r, lt
        if name == "join":
            if len(e.args) != 1:
                self.release(o, StrT)
                raise TomatoError("join takes a list[str]", e.line)
            lst, lt = self.expr(e.args[0])
            if lt != ListT(StrT):
                self.release(o, StrT)
                self.release(lst, lt)
                raise TomatoError("join takes a list[str]", e.line)
            r = self.tmp("joined")
            self.emit("%s = call ptr @tomato_str_join(ptr %s, ptr %s)" % (r, o, lst))
            self.release(lst, lt)
            self.release(o, StrT)
            return r, StrT
        self.release(o, StrT)
        raise NotCompiled("text method %s" % name, e.line)

    def str_call(self, e):
        if len(e.args) != 1:
            raise TomatoError("str(x) takes one argument", e.line)
        v, t = self.expr(e.args[0])
        r = self.tmp("str")
        if t == StrT:
            return v, StrT
        if is_int_type(t):
            if is_signed(t):
                self.emit("%s = call ptr @tomato_str_from_i64(i64 %s)" % (r, self.resize(v, t, INT)))
            else:
                w = v
                if bits_of(t) < 64:
                    w = self.tmp("w")
                    self.emit("%s = zext %s %s to i64" % (w, llvm_type(t), v))
                self.emit("%s = call ptr @tomato_str_from_u64(i64 %s)" % (r, w))
        elif t == FloatT:
            self.emit("%s = call ptr @tomato_str_from_f64(double %s)" % (r, v))
        elif t == BoolT:
            z = self.tmp("b")
            self.emit("%s = zext i1 %s to i32" % (z, v))
            self.emit("%s = call ptr @tomato_str_from_bool(i32 %s)" % (r, z))
        else:
            self.release(v, t)
            raise NotDecided("str() of %r" % (t,), e.line)
        return r, StrT

    def print_call(self, e):
        # Like the interpreter, evaluate every argument before printing anything: an error in a later argument
        # must not leave half a line behind.
        values = [self.expr(a) for a in e.args]
        for k, (v, t) in enumerate(values):
            if k:
                self.emit("call void @tomato_print_space()")
            if is_int_type(t):
                if is_signed(t):
                    self.emit("call void @tomato_print_i64(i64 %s)" % self.resize(v, t, INT))
                else:
                    wide = v
                    if bits_of(t) < 64:
                        wide = self.tmp("w")
                        self.emit("%s = zext %s %s to i64" % (wide, llvm_type(t), v))
                    self.emit("call void @tomato_print_u64(i64 %s)" % wide)
            elif t == FloatT:
                self.emit("call void @tomato_print_f64(double %s)" % v)
            elif t == BoolT:
                z = self.tmp("b")
                self.emit("%s = zext i1 %s to i32" % (z, v))
                self.emit("call void @tomato_print_bool(i32 %s)" % z)
            elif t == StrT:
                self.emit("call void @tomato_print_strobj(ptr %s)" % v)
            elif t == NoneT:
                self.emit("call void @tomato_print_strobj(ptr %s)" % self.cg.strobj("None"))
            elif isinstance(t, OptT) and t.inner == StrT:
                isnull, shown = self.tmp("isnone"), self.tmp("shown")
                self.emit("%s = icmp eq ptr %s, null" % (isnull, v))
                self.emit("%s = select i1 %s, ptr %s, ptr %s" % (shown, isnull, self.cg.strobj("None"), v))
                self.emit("call void @tomato_print_strobj(ptr %s)" % shown)
            else:
                for v2, t2 in values:
                    self.release(v2, t2)
                raise NotCompiled("printing %r" % (t,), e.line)
        for v, t in values:
            self.release(v, t)
        self.emit("call void @tomato_print_newline()")

    # ---- strings and lists
    def index(self, e):
        o, ot = self.expr(e.obj)
        o, ot = self.unwrap(o, ot, e.line)
        if isinstance(ot, MapT):
            return self.dict_read(o, ot, e)
        if isinstance(ot, SetT):
            self.release(o, ot)
            raise NotDecided("indexing a set", e.line)
        i, it = self.expr(e.index)
        if not is_int_type(it):
            raise TomatoError("an index must be an integer, found %r" % (it,), e.line)
        i = self.resize(i, it, INT)
        if ot == StrT:
            r = self.tmp("ch")
            self.emit("%s = call ptr @tomato_str_index(ptr %s, i64 %s)" % (r, o, i))
            bad = self.tmp("oob")
            self.emit("%s = icmp eq ptr %s, null" % (bad, r))
            self.trap_if(bad, "index")
            self.release(o, ot)
            return r, StrT
        if isinstance(ot, ListT):
            addr = self.list_slot(o, ot, i)
            r = self.tmp("item")
            self.emit("%s = load %s, ptr %s" % (r, llvm_type(ot.elem), addr))
            self.retain(r, ot.elem)
            self.release(o, ot)
            return r, ot.elem
        self.release(o, ot)
        raise NotCompiled("indexing %r" % (ot,), e.line)

    def list_slot(self, lst, lt, i):
        """The address of item i of a list, after a bounds check (an out-of-range index is a run-time error)."""
        lenp, ln, bad, datap, data, addr = [self.tmp(x) for x in ("lenp", "len", "oob", "datap", "data", "addr")]
        self.emit("%s = getelementptr { i64, i64, i64, i64, ptr }, ptr %s, i32 0, i32 2" % (lenp, lst))
        self.emit("%s = load i64, ptr %s" % (ln, lenp))
        self.emit("%s = icmp uge i64 %s, %s" % (bad, i, ln))
        self.trap_if(bad, "index")
        self.emit("%s = getelementptr { i64, i64, i64, i64, ptr }, ptr %s, i32 0, i32 4" % (datap, lst))
        self.emit("%s = load ptr, ptr %s" % (data, datap))
        self.emit("%s = getelementptr %s, ptr %s, i64 %s" % (addr, llvm_type(lt.elem), data, i))
        return addr

    def slice(self, e):
        o, ot = self.expr(e.obj)
        if ot != StrT:
            self.release(o, ot)
            raise NotCompiled("slicing %r" % (ot,), e.line)
        parts = []
        for x in (e.lo, e.hi):
            if x is None:
                parts.append(None)
                continue
            v, t = self.expr(x)
            if not is_int_type(t):
                raise TomatoError("a slice bound must be an integer, found %r" % (t,), e.line)
            parts.append(self.resize(v, t, INT))
        lo = parts[0] or "0"
        if parts[1] is None:
            hi = self.tmp("hi")
            self.emit("%s = call i64 @tomato_str_len(ptr %s)" % (hi, o))
        else:
            hi = parts[1]
        r = self.tmp("slice")
        self.emit("%s = call ptr @tomato_str_slice(ptr %s, i64 %s, i64 %s)" % (r, o, lo, hi))
        bad = self.tmp("oob")
        self.emit("%s = icmp eq ptr %s, null" % (bad, r))
        self.trap_if(bad, "index")
        self.release(o, ot)
        return r, StrT

    # ---- dicts and sets (D20b, D20c)
    def key_kind(self, kt, line):
        if kt == StrT:
            return 1
        if is_int_type(kt) or kt == BoolT:
            return 0
        raise NotDecided("dict keys of type %r (only integers, str and bool are decided)" % (kt,), line)

    def key_word(self, v, kt):
        """A key as the 64-bit word the runtime hashes: the integer itself, or the string's address."""
        if kt == StrT:
            r = self.tmp("kw")
            self.emit("%s = ptrtoint ptr %s to i64" % (r, v))
            return r
        if kt == BoolT:
            r = self.tmp("kw")
            self.emit("%s = zext i1 %s to i64" % (r, v))
            return r
        return self.resize(v, kt, INT)

    def new_table(self, t, line):
        kt = t.key if isinstance(t, MapT) else t.elem
        vsize = self.cg.size_of(llvm_type(t.value)) if isinstance(t, MapT) else 0
        r = self.tmp("dict")
        self.emit("%s = call ptr @tomato_dict_new(i64 %d, i64 %d, i32 %d)" % (r, self.cg.type_code(t), vsize, self.key_kind(kt, line)))
        return r

    def keyed(self, node, kt, line, what="key"):
        v, t = self.expr(node, kt)
        return self.coerce(v, t, kt, line, "dict " + what), v, t

    def dict_literal(self, e, expected):
        if isinstance(expected, SetT) and not e.pairs:
            return self.new_table(expected, e.line), expected
        first = None
        if isinstance(expected, MapT):
            dt = expected
        elif not e.pairs:
            raise NotDecided("the type of an empty {} without a declared type (name it: m: dict[str, int] = {})", e.line)
        else:
            kv, kt = self.expr(e.pairs[0][0])
            vv, vt = self.expr(e.pairs[0][1])
            first = (kv, kt, vv, vt)
            dt = MapT(kt, vt)
        d = self.new_table(dt, e.line)
        for n, (k, v) in enumerate(e.pairs):
            if first is not None and n == 0:
                kv, kt, vv, vt = first
            else:
                kv, kt = self.expr(k, dt.key)
                vv, vt = self.expr(v, dt.value)
            kw = self.key_word(self.coerce(kv, kt, dt.key, e.line, "dict key"), dt.key)
            vc = self.coerce(vv, vt, dt.value, e.line, "dict value")
            slot = self.tmp("slot")
            self.emit("%s = call ptr @tomato_dict_insert(ptr %s, i64 %s, i32 1)" % (slot, d, kw))
            dup = self.tmp("dup")
            self.emit("%s = icmp eq ptr %s, null" % (dup, slot))
            self.trap_if(dup, "duplicate key")
            self.emit("store %s %s, ptr %s" % (llvm_type(dt.value), vc, slot))      # the table takes the value's reference
            self.release(kv, kt)                                                  # and retains its own copy of a string key
        return d, dt

    def set_literal(self, e, expected):
        if isinstance(expected, SetT):
            st, first = expected, None
        else:
            kv, kt = self.expr(e.items[0])
            st, first = SetT(kt), (kv, kt)
        d = self.new_table(st, e.line)
        for n, item in enumerate(e.items):
            kv, kt = first if (first is not None and n == 0) else self.expr(item, st.elem)
            kw = self.key_word(self.coerce(kv, kt, st.elem, e.line, "set element"), st.elem)
            self.emit("call ptr @tomato_dict_insert(ptr %s, i64 %s, i32 0)" % (d, kw))
            self.release(kv, kt)
        return d, st

    def dict_read(self, d, dt, e):
        kc, kv, kt = self.keyed(e.index, dt.key, e.line)
        slot = self.tmp("slot")
        self.emit("%s = call ptr @tomato_dict_find(ptr %s, i64 %s)" % (slot, d, self.key_word(kc, dt.key)))
        missing = self.tmp("missing")
        self.emit("%s = icmp eq ptr %s, null" % (missing, slot))
        self.trap_if(missing, "key not found")
        r = self.tmp("val")
        self.emit("%s = load %s, ptr %s" % (r, llvm_type(dt.value), slot))
        self.retain(r, dt.value)
        self.release(kv, kt)
        self.release(d, dt)
        return r, dt.value

    def dict_write(self, d, dt, s):
        tgt = s.target
        kc, kv, kt = self.keyed(tgt.index, dt.key, s.line)
        v, vt = self.expr(s.value, dt.value)
        slot = self.tmp("slot")
        self.emit("%s = call ptr @tomato_dict_insert(ptr %s, i64 %s, i32 0)" % (slot, d, self.key_word(kc, dt.key)))
        self.store_owned(slot, self.coerce(v, vt, dt.value, s.line, "dict value"), dt.value)
        self.release(kv, kt)
        self.release(d, dt)

    def contains(self, a, ta, b, tb, line):
        r = self.tmp("in")
        if ta == StrT and tb == StrT:
            c = self.tmp("c")
            self.emit("%s = call i32 @tomato_str_contains(ptr %s, ptr %s)" % (c, b, a))
            self.emit("%s = icmp ne i32 %s, 0" % (r, c))
        elif isinstance(tb, (MapT, SetT)):
            kt = tb.key if isinstance(tb, MapT) else tb.elem
            if not (ta == kt or (is_int_type(ta) and is_int_type(kt))):
                self.release(a, ta)
                self.release(b, tb)
                raise TomatoError("type error: cannot look for %r in %r" % (ta, tb), line)
            slot = self.tmp("slot")
            self.emit("%s = call ptr @tomato_dict_find(ptr %s, i64 %s)" % (slot, b, self.key_word(a, ta)))   # keys compare by value
            self.emit("%s = icmp ne ptr %s, null" % (r, slot))
        elif isinstance(tb, ListT):
            return self.list_contains(a, ta, b, tb, line)
        else:
            self.release(a, ta)
            self.release(b, tb)
            if ta == StrT or tb == StrT:
                raise TomatoError("type error: cannot use in with %r and %r" % (ta, tb), line)
            raise NotCompiled("the in operator on %r" % (tb,), line)
        self.release(a, ta)
        self.release(b, tb)
        return r, BoolT

    def list_contains(self, a, ta, lst, lt, line):
        """`x in list`: walk the items and compare each with ==, stopping at the first match."""
        found = self.hidden_slot("in.found", INT)
        counter = self.hidden_slot("in.i", INT)
        self.emit("store i64 0, ptr %s" % found)
        self.emit("store i64 0, ptr %s" % counter)
        head, body, step, end = self.label("inhead"), self.label("inbody"), self.label("instep"), self.label("inend")
        self.br(head)
        self.place(head)
        i, ln, go, lenp = [self.tmp(x) for x in ("i", "n", "go", "lenp")]
        self.emit("%s = load i64, ptr %s" % (i, counter))
        self.emit("%s = getelementptr { i64, i64, i64, i64, ptr }, ptr %s, i32 0, i32 2" % (lenp, lst))
        self.emit("%s = load i64, ptr %s" % (ln, lenp))
        self.emit("%s = icmp slt i64 %s, %s" % (go, i, ln))
        self.cond_br(go, body, end)
        self.place(body)
        addr = self.list_slot(lst, lt, i)
        item = self.tmp("item")
        self.emit("%s = load %s, ptr %s" % (item, llvm_type(lt.elem), addr))
        self.retain(item, lt.elem)
        self.retain(a, ta)
        eq, _ = self.compare("==", item, lt.elem, a, ta, line)
        hit = self.label("inhit")
        self.cond_br(eq, hit, step)
        self.place(hit)
        self.emit("store i64 1, ptr %s" % found)
        self.br(end)
        self.place(step)
        cur, nxt = self.tmp("cur"), self.tmp("next")
        self.emit("%s = load i64, ptr %s" % (cur, counter))
        self.emit("%s = add i64 %s, 1" % (nxt, cur))
        self.emit("store i64 %s, ptr %s" % (nxt, counter))
        self.br(head)
        self.place(end)
        f, r = self.tmp("found"), self.tmp("in")
        self.emit("%s = load i64, ptr %s" % (f, found))
        self.emit("%s = icmp ne i64 %s, 0" % (r, f))
        self.release(a, ta)
        self.release(lst, lt)
        return r, BoolT

    def key_list(self, d, t):
        """A new list of the keys of a dict or set, in insertion order (owned); consumes the table temporary."""
        kt = t.key if isinstance(t, MapT) else t.elem
        lt = ListT(kt)
        r = self.tmp("keys")
        self.emit("%s = call ptr @tomato_dict_keys(ptr %s, i64 %d, i64 %d)"
                  % (r, d, self.cg.type_code(lt), self.cg.size_of(llvm_type(kt))))
        self.release(d, t)
        return r, lt

    def dict_method(self, d, dt, name, e):
        if name == "keys" and not e.args:
            return self.key_list(d, dt)
        if name == "values" and not e.args:
            lt = ListT(dt.value)
            r = self.tmp("vals")
            self.emit("%s = call ptr @tomato_dict_values(ptr %s, i64 %d, i64 %d, i32 %d)"
                      % (r, d, self.cg.type_code(lt), self.cg.size_of(llvm_type(dt.value)), 1 if is_rc(dt.value) else 0))
            self.release(d, dt)
            return r, lt
        if name == "remove" and len(e.args) == 1:
            kc, kv, kt = self.keyed(e.args[0], dt.key, e.line)
            kw = self.key_word(kc, dt.key)
            slot = self.tmp("slot")
            self.emit("%s = call ptr @tomato_dict_find(ptr %s, i64 %s)" % (slot, d, kw))
            missing = self.tmp("missing")
            self.emit("%s = icmp eq ptr %s, null" % (missing, slot))
            self.trap_if(missing, "key not found")
            if is_rc(dt.value):
                old = self.tmp("old")
                self.emit("%s = load ptr, ptr %s" % (old, slot))
                self.emit("call void @tomato_release(ptr %s)" % old)
            self.emit("call i32 @tomato_dict_delete(ptr %s, i64 %s)" % (d, kw))
            self.release(kv, kt)
            self.release(d, dt)
            return None, NoneT
        self.release(d, dt)
        raise NotDecided("dict method %s (only keys, values and remove are placeholders)" % name, e.line)

    def set_method(self, st_val, st, name, e):
        if name in ("add", "remove") and len(e.args) == 1:
            kc, kv, kt = self.keyed(e.args[0], st.elem, e.line, "element")
            kw = self.key_word(kc, st.elem)
            if name == "add":
                self.emit("call ptr @tomato_dict_insert(ptr %s, i64 %s, i32 0)" % (st_val, kw))
            else:
                slot = self.tmp("slot")
                self.emit("%s = call ptr @tomato_dict_find(ptr %s, i64 %s)" % (slot, st_val, kw))
                missing = self.tmp("missing")
                self.emit("%s = icmp eq ptr %s, null" % (missing, slot))
                self.trap_if(missing, "key not found")
                self.emit("call i32 @tomato_dict_delete(ptr %s, i64 %s)" % (st_val, kw))
            self.release(kv, kt)
            self.release(st_val, st)
            return None, NoneT
        self.release(st_val, st)
        raise NotDecided("set method %s (only add and remove are placeholders)" % name, e.line)

    def list_push(self, lst, elem_t, value):
        slot = self.tmp("slot")
        self.emit("%s = call ptr @tomato_list_push(ptr %s, i64 %s)" % (slot, lst, self.cg.size_of(llvm_type(elem_t))))
        self.emit("store %s %s, ptr %s" % (llvm_type(elem_t), value, slot))     # the list takes over the reference

    def list_literal(self, e, expected):
        if isinstance(expected, ListT):
            elem = expected.elem
            first = None
        else:
            if not e.items:
                raise NotDecided("the type of an empty list literal without a declared type (name it: xs: list[int] = [])",
                                 e.line)
            first = self.expr(e.items[0])
            elem = first[1]
        lt = ListT(elem)
        lst = self.tmp("list")
        self.emit("%s = call ptr @tomato_list_new(i64 %d)" % (lst, self.cg.type_code(lt)))
        for k, item in enumerate(e.items):
            v, t = first if (first is not None and k == 0) else self.expr(item, elem)
            self.list_push(lst, elem, self.coerce(v, t, elem, e.line, "list item"))
        return lst, lt

    # ---- classes (D12): instances are heap objects {header, fields...}
    def field_info(self, cls_t, name, line):
        info = self.cg.interp.classes[cls_t.name]
        owner, entry = info.find_field(name)
        if entry is None:
            raise TomatoError("%s has no field %s" % (cls_t.name, name), line)
        fdef, ft = entry
        if fdef.private and self.fn.owner is not owner:
            raise TomatoError("field %s is private to class %s (D12ac, D12r)" % (name, owner.name), line)
        return owner, fdef, ft

    def field_addr(self, obj, cls_t, name, line):
        owner, fdef, ft = self.field_info(cls_t, name, line)
        addr = self.tmp("fld")
        self.emit("%s = getelementptr %s, ptr %s, i32 0, i32 %d"
                  % (addr, self.cg.struct_type(cls_t.name), obj, self.cg.field_index(cls_t.name, name)))
        return addr, fdef, ft

    def field_read(self, e):
        if isinstance(e.obj, N.Name) and e.obj.name not in self.vars and self.cg.interp.vis_class(e.obj.name):
            raise TomatoError("%s.%s must be called" % (e.obj.name, e.name), e.line)
        o, ot = self.expr(e.obj)
        o, ot = self.unwrap(o, ot, e.line)
        if isinstance(ot, IfaceT):
            self.release(o, ot)
            raise TomatoError("interface %s has no field %s" % (self.cg.interp.ifaces[ot.name].node.name, e.name), e.line)
        if not isinstance(ot, ClassT):
            self.release(o, ot)
            raise NotCompiled("fields of %r" % (ot,), e.line)
        addr, fdef, ft = self.field_addr(o, ot, e.name, e.line)
        r = self.tmp("val")
        self.emit("%s = load %s, ptr %s" % (r, llvm_type(ft), addr))
        self.retain(r, ft)
        self.release(o, ot)
        return r, ft

    def assign_field(self, s):
        tgt = s.target
        o, ot = self.expr(tgt.obj)
        o, ot = self.unwrap(o, ot, s.line)
        if isinstance(ot, IfaceT):
            self.release(o, ot)
            raise TomatoError("interface %s has no field %s" % (self.cg.interp.ifaces[ot.name].node.name, tgt.name), s.line)
        if not isinstance(ot, ClassT):
            self.release(o, ot)
            raise NotCompiled("assigning fields of %r" % (ot,), s.line)
        addr, fdef, ft = self.field_addr(o, ot, tgt.name, s.line)
        owner, _, _ = self.field_info(ot, tgt.name, s.line)
        if fdef.const and not (self.fn.node is not None and self.fn.node.marker == "init" and self.fn.owner is owner):
            raise TomatoError("const field %s cannot change after initialization (D12o)" % tgt.name, s.line)
        v, vt = self.expr(s.value, ft)
        self.store_owned(addr, self.coerce(v, vt, ft, s.line, "assigned value"), ft)
        self.release(o, ot)

    def construct(self, cls, e):
        t = ClassT(cls.name)
        first = None
        if len(e.args) == 1 and not self.literal_only(e.args[0]):
            first = self.expr(e.args[0])
            conv = self.conversion(cls, t, first, e)
            if conv is not None:
                return conv
        init = cls.nearest("init")
        if init is None:
            if e.args:
                self.release(*first) if first else None
                raise TomatoError("%s takes no arguments (D12af)" % cls.node.name, e.line)
            ptypes = []
        else:
            if cls.own_init() is None:
                raise TomatoError("%s has no @init of its own, so it cannot be called (D12ah)" % cls.node.name, e.line)
            ptypes = init.ptypes
        if init is None and e.args or (init is not None and not self.arity_ok(init, ptypes, len(e.args))):
            self.release(*first) if first else None
            raise TomatoError("%s takes %d argument(s), got %d" % (cls.node.name, len(ptypes), len(e.args)), e.line)
        sym = self.cg.ctor_symbol(cls)
        self.callees.add(sym)
        if first is not None:
            v, vt = first
            args = self.fill_defaults([("%s %s" % (llvm_type(ptypes[0]), self.coerce(v, vt, ptypes[0], e.line, "argument")), v, vt)],
                                      ptypes, init, e.line)
        else:
            args = self.eval_args(e.args, ptypes, e.line, init)
        return self.finish_call("call ptr @%s(%s)" % (sym, ", ".join(a[0] for a in args)), t, args, "obj")

    def type_test(self, e):
        """`x in Type`: whether x's type is Type, counting subclasses and implemented interfaces (D23f)."""
        interp = self.cg.interp
        target = interp.type_named(e.right.name)
        a, ta = self.expr(e.left)
        if target == NoneT:
            return self.none_test("is", a, ta, "null", NoneT, e.line) if ta != NoneT else ("1", BoolT)
        inner = ta.inner if isinstance(ta, OptT) else ta
        optional = isinstance(ta, OptT)
        if isinstance(inner, ClassT) and isinstance(target, ClassT):
            if interp.is_subclass(interp.classes[inner.name], target.name):
                static = True
            elif interp.is_subclass(interp.classes[target.name], inner.name):
                static = None                                  # a value of the parent type may hold a subclass
            else:
                static = False
        elif isinstance(inner, ClassT) and isinstance(target, IfaceT):
            if target.name in interp.class_ifaces(interp.classes[inner.name]):
                static = True
            else:
                raise NotCompiled("`in` with an interface a value's class may only implement in a subclass", e.line)
        elif isinstance(inner, IfaceT) and isinstance(target, (ClassT, IfaceT)):
            raise NotCompiled("`in` on an interface-typed value", e.line)
        else:
            static = inner == target
        if static is None:
            code, raw, r, ok = self.tmp("code"), self.tmp("rawcode"), self.tmp("isa32"), self.tmp("isa")
            if optional:
                nn = self.tmp("nn")
                here = self.current_label()
                yes, done = self.label("tyyes"), self.label("tydone")
                self.emit("%s = icmp ne ptr %s, null" % (nn, a))
                self.cond_br(nn, yes, done)
                self.place(yes)
            self.emit("%s = load i64, ptr %s" % (raw, self.cg.type_field(self, a)))
            self.emit("%s = and i64 %s, 4294967295" % (code, raw))
            self.emit("%s = call i32 @tomato_is_subclass(i64 %s, i64 %d)" % (r, code, self.cg.type_code(target)))
            self.emit("%s = icmp ne i32 %s, 0" % (ok, r))
            if optional:
                yes_end = self.current_label()
                self.br(done)
                self.place(done)
                res = self.tmp("typed")
                self.emit("%s = phi i1 [ %s, %%%s ], [ false, %%%s ]" % (res, ok, yes_end, here))
                ok = res
            self.release(a, ta)
            return ok, BoolT
        if optional and static:
            r = self.tmp("isset")
            self.emit("%s = icmp ne ptr %s, null" % (r, a))
            self.release(a, ta)
            return r, BoolT
        self.release(a, ta) if is_rc(ta) else None
        return ("1" if static else "0"), BoolT

    def conversion(self, cls, t, first, e):
        """`Dog(x)` where x is a parent-typed value is an explicit conversion that can fail (D12az, D12bh)."""
        v, vt = first
        if not isinstance(vt, (ClassT, IfaceT)):
            return None
        interp = self.cg.interp
        if isinstance(vt, ClassT):
            src = interp.classes[vt.name]
            related = interp.is_subclass(cls, src.name) or interp.is_subclass(src, cls.name)
        else:
            related = True            # an interface-typed value may hold any class that implements it
        if not related:
            return None
        if isinstance(vt, ClassT) and interp.is_subclass(interp.classes[vt.name], cls.name):
            return v, t                # already an instance of the class (or a subclass): no check needed
        code, ok, raw = self.tmp("code"), self.tmp("isa"), self.tmp("rawcode")
        self.emit("%s = load i64, ptr %s" % (raw, self.cg.type_field(self, v)))
        self.emit("%s = and i64 %s, 4294967295" % (code, raw))
        r = self.tmp("isa32")
        self.emit("%s = call i32 @tomato_is_subclass(i64 %s, i64 %d)" % (r, code, self.cg.type_code(t)))
        self.emit("%s = icmp eq i32 %s, 0" % (ok, r))
        self.trap_if(ok, "class conversion")
        return v, t

    def static_type_hint(self, node):
        """The class an argument expression names, when it is a plain variable (used to spot conversions)."""
        if isinstance(node, N.Name) and node.name in self.vars:
            return self.vars[node.name][1]
        return None

    def method_call(self, e):
        f = e.func
        # Class.method(...): a class function, or the parent's version of an instance method (D12ao, D12av)
        if isinstance(f.obj, N.Name) and f.obj.name not in self.vars and self.cg.interp.vis_class(f.obj.name):
            return self.class_qualified(self.cg.interp.vis_class(f.obj.name), f, e)
        o, ot = self.expr(f.obj)
        o, ot = self.unwrap(o, ot, e.line)
        if isinstance(ot, ListT):
            return self.list_method(o, ot, f.name, e)
        if isinstance(ot, MapT):
            return self.dict_method(o, ot, f.name, e)
        if isinstance(ot, SetT):
            return self.set_method(o, ot, f.name, e)
        if ot == StrT:
            return self.str_method(o, f.name, e)
        if ot == FileT:
            return self.file_method(o, f.name, e)
        if isinstance(ot, IfaceT):
            return self.iface_call(o, ot, f, e)
        if not isinstance(ot, ClassT):
            self.release(o, ot)
            raise NotCompiled("methods of %r" % (ot,), e.line)
        info = self.cg.interp.classes[ot.name]
        m = info.find_method(f.name)
        if m is None or not m.has_self:
            self.release(o, ot)
            raise TomatoError("%s has no method %s" % (info.node.name, f.name), e.line)
        if m.node.marker == "init":
            self.release(o, ot)
            raise NotDecided("calling @init on an existing instance", e.line)
        if m.node.private and self.fn.owner is not m.owner:
            self.release(o, ot)
            raise TomatoError("method %s is private to class %s (D12ac, D12r)" % (f.name, m.owner.name), e.line)
        if not self.arity_ok(m, m.ptypes, len(e.args)):
            self.release(o, ot)
            raise TomatoError("%s takes %d argument(s), got %d" % (f.name, len(m.ptypes), len(e.args)), e.line)
        args = self.eval_args(e.args, m.ptypes, e.line, m)
        all_args = [("ptr %s" % o, o, ot)] + args
        for impl in self.cg.implementations(info, f.name):
            self.callees.add(self.cg.func_symbol(impl))
        if self.cg.has_subclasses(info):
            target = self.cg.dispatch(self, o, f.name)
        else:
            target = "@" + self.cg.func_symbol(m)
        return self.finish_call("call %s %s(%s)" % (llvm_type(m.ret), target, ", ".join(a[0] for a in all_args)),
                                m.ret, all_args)

    def iface_call(self, o, ot, f, e):
        """A call through an interface type runs the object's own method, found through its type code (D12bb)."""
        interp = self.cg.interp
        req = interp.iface_requirements(ot.name).get(f.name)
        if req is None:
            self.release(o, ot)
            raise TomatoError("interface %s has no method %s" % (interp.ifaces[ot.name].node.name, f.name), e.line)
        if len(e.args) != len(req.ptypes):
            self.release(o, ot)
            raise TomatoError("%s takes %d argument(s), got %d" % (f.name, len(req.ptypes), len(e.args)), e.line)
        args = self.eval_args(e.args, req.ptypes, e.line)
        for c in self.cg.main_classes():
            if ot.name in interp.class_ifaces(c):
                m = c.find_method(f.name)
                if m is not None:
                    self.callees.add(self.cg.func_symbol(m))
        target = self.cg.dispatch(self, o, f.name)
        return self.finish_call("call %s %s(%s)" % (llvm_type(req.ret), target, ", ".join(["ptr " + o] + [a[0] for a in args])),
                                req.ret, [("ptr " + o, o, ot)] + args)

    def class_qualified(self, cls, f, e):
        m = cls.find_method(f.name)
        if m is None:
            raise TomatoError("%s has no method %s" % (cls.node.name, f.name), e.line)
        if m.node.private and self.fn.owner is not m.owner:
            raise TomatoError("method %s is private to class %s (D12ac, D12r)" % (f.name, m.owner.name), e.line)
        sym = self.cg.func_symbol(m)
        self.callees.add(sym)
        if not m.has_self:
            if not self.arity_ok(m, m.ptypes, len(e.args)):
                raise TomatoError("%s takes %d argument(s), got %d" % (f.name, len(m.ptypes), len(e.args)), e.line)
            args = self.eval_args(e.args, m.ptypes, e.line, m)
            return self.finish_call("call %s @%s(%s)" % (llvm_type(m.ret), sym, ", ".join(a[0] for a in args)), m.ret, args)
        if not e.args:
            raise TomatoError("%s.%s needs self as its first argument (D12ao)" % (cls.node.name, f.name), e.line)
        if not (self.fn.owner is not None and self.fn.owner is not cls and self.cg.interp.is_subclass(self.fn.owner, cls.name)):
            raise NotDecided("class-qualified calls other than a subclass calling its parent", e.line)
        so, st = self.expr(e.args[0])
        if not (isinstance(st, ClassT) and self.subclass(st, ClassT(cls.name))):
            raise TomatoError("first argument must be an instance of %s" % cls.node.name, e.line)
        rest = e.args[1:]
        if not self.arity_ok(m, m.ptypes, len(rest)):
            raise TomatoError("%s takes %d argument(s), got %d" % (f.name, len(m.ptypes), len(rest)), e.line)
        args = [("ptr %s" % so, so, st)] + self.eval_args(rest, m.ptypes, e.line, m)
        return self.finish_call("call %s @%s(%s)" % (llvm_type(m.ret), sym, ", ".join(a[0] for a in args)), m.ret, args)

    def list_method(self, lst, lt, name, e):
        if name != "append":
            self.release(lst, lt)
            raise NotDecided("list method %s (only append is decided; removal, insertion and slicing are open)" % name, e.line)
        if len(e.args) != 1:
            raise TomatoError("append takes 1 argument, got %d" % len(e.args), e.line)
        v, t = self.expr(e.args[0], lt.elem)
        self.list_push(lst, lt.elem, self.coerce(v, t, lt.elem, e.line, "appended item"))
        self.release(lst, lt)
        return None, NoneT

    # ---- statements
    def block(self, stmts):
        for s in stmts:
            self.stmt(s)

    def stmt(self, s):
        if s.line:
            self.line = s.line
        if isinstance(s, N.ExprStmt):
            v, t = self.expr(s.expr)
            self.release(v, t)
        elif isinstance(s, N.Pass):
            pass
        elif isinstance(s, N.Declare):
            t = self.cg.interp.resolve(s.type)
            llvm_type(t)
            v, vt = self.expr(s.value, t)
            if s.name in self.vars:
                raise NotDecided("declaring a name twice", s.line)
            reg, _ = self.slot(s.name, t, s.line)
            self.store_owned(reg, self.coerce(v, vt, t, s.line, "initial value"), t)
        elif isinstance(s, N.Assign):
            tgt = s.target
            if isinstance(tgt, N.Attr):
                self.assign_field(s)
            elif isinstance(tgt, N.Index):
                self.assign_item(s)
            else:
                if tgt.name in self.vars:
                    reg, t = self.vars[tgt.name]
                    v, vt = self.expr(s.value, t)
                else:
                    v, vt = self.expr(s.value)
                    if vt == NoneT:
                        raise NotCompiled("storing None", s.line)
                    reg, t = self.slot(tgt.name, vt, s.line)
                self.store_owned(reg, self.coerce(v, vt, t, s.line, "assigned value"), t)
        elif isinstance(s, N.Return):
            ret = self.fn.ret
            if s.value is None:
                if ret != NoneT:
                    raise TomatoError("%s must return a %r" % (self.fn.name, ret), s.line)
            else:
                if ret == NoneT:
                    raise TomatoError("%s returns no value" % self.fn.name, s.line)
                v, vt = self.expr(s.value, ret)
                self.emit("store %s %s, ptr %%retval" % (llvm_type(ret), self.coerce(v, vt, ret, s.line, "return value")))
            self.run_finallies(len(self.tries))
            self.br("epilogue")
        elif isinstance(s, N.If):
            end = self.label("endif")
            for c, body in s.branches:
                yes, no = self.label("then"), self.label("else")
                self.cond_br(self.cond(c), yes, no)
                self.place(yes)
                self.block(body)
                if not self.terminated:
                    self.br(end)
                self.place(no)
            if s.orelse:
                self.block(s.orelse)
            if not self.terminated:
                self.br(end)
            self.place(end)
        elif isinstance(s, N.While):
            head, body, end = self.label("while"), self.label("body"), self.label("endwhile")
            self.br(head)
            self.place(head)
            self.cond_br(self.cond(s.cond), body, end)
            self.place(body)
            self.loops.append((end, head))
            self.block(s.body)
            self.loops.pop()
            if not self.terminated:
                self.br(head)
            self.place(end)
        elif isinstance(s, N.For):
            self.for_loop(s)
        elif isinstance(s, N.Break) or isinstance(s, N.Continue):
            if not self.loops:
                raise TomatoError("break or continue outside a loop", s.line)
            inside = [t for t in self.tries if t["loop_depth"] == len(self.loops)]
            self.run_finallies(len(inside))
            self.br(self.loops[-1][0 if isinstance(s, N.Break) else 1])
        elif isinstance(s, N.Raise):
            self.raise_stmt(s)
        elif isinstance(s, N.Try):
            self.try_stmt(s)
        else:
            raise NotCompiled(NODE_NAMES.get(type(s).__name__, type(s).__name__.lower() + " statements"), s.line)

    def run_finallies(self, n):
        """Run the finally blocks of the `n` innermost try statements, innermost first: a return, break or continue
        is leaving them (D22a). A raise inside one of these blocks goes to the handlers outside its try."""
        saved = self.tries
        for k in range(len(saved) - 1, len(saved) - 1 - n, -1):
            final = saved[k]["final"]
            if final:
                self.tries = saved[:k]
                self.block(final)
        self.tries = saved

    def raise_stmt(self, s):
        v, t = self.expr(s.value)
        interp = self.cg.interp
        if not (isinstance(t, ClassT) and interp.is_subclass(interp.classes[t.name], "Error")):
            self.release(v, t)
            raise TomatoError("raise needs an Error object, found %r" % (t,), s.line)
        self.emit("store ptr %s, ptr @tomato_exc" % v)             # the pending error owns the reference
        self.emit("store i32 %d, ptr @tomato_exc_line" % s.line)
        self.emit("store i32 0, ptr @tomato_exc_rt")
        self.emit("store i32 1, ptr @tomato_exc_seen")
        self.br(self.unwind_target())

    def try_stmt(self, s):
        interp = self.cg.interp
        clauses = []
        for cname, var, body in s.handlers:
            cinfo = interp.vis_class(cname)
            if cinfo is None or not interp.is_subclass(cinfo, "Error"):
                raise TomatoError("catch needs an error class (a subclass of Error), found %r" % cname, s.line)
            clauses.append((cinfo, var, body))
        entry = {"catch": self.label("catch"), "prop": self.label("prop"), "final": s.final,
                 "loop_depth": len(self.loops), "state": "body"}
        else_l, handled_l, end_l = self.label("tryelse"), self.label("tryhandled"), self.label("tryend")
        self.tries.append(entry)
        self.block(s.body)
        if not self.terminated:
            self.br(else_l)
        # an error raised in the body arrives here with the pending error set
        self.place(entry["catch"])
        entry["state"] = "post"
        ex, code, raw = self.tmp("ex"), self.tmp("code"), self.tmp("rawcode")
        self.emit("%s = load ptr, ptr @tomato_exc" % ex)
        self.emit("%s = load i64, ptr %s" % (raw, self.cg.type_field(self, ex)))
        self.emit("%s = and i64 %s, 4294967295" % (code, raw))
        for cinfo, var, body in clauses:
            ct = ClassT(cinfo.name)
            isa, hit = self.tmp("isa"), self.tmp("hit")
            self.emit("%s = call i32 @tomato_is_subclass(i64 %s, i64 %d)" % (isa, code, self.cg.type_code(ct)))
            self.emit("%s = icmp ne i32 %s, 0" % (hit, isa))
            match, nxt = self.label("match"), self.label("nomatch")
            self.cond_br(hit, match, nxt)
            self.place(match)
            self.emit("store ptr null, ptr @tomato_exc")             # handled: the catch variable takes the reference
            if var:
                if var in self.vars and self.vars[var][1] != ct:
                    # the name is bound again, to a new slot of the new type (the old one is still released)
                    fresh = "%s_%d" % (var, len(self.vars))
                    self.slot(fresh, ct, s.line)
                    self.vars[var] = self.vars.pop(fresh)
                reg, _ = self.slot(var, ct, s.line)
                self.store_owned(reg, ex, ct)
            else:
                self.emit("call void @tomato_release(ptr %s)" % ex)
            self.block(body)
            if not self.terminated:
                self.br(handled_l)
            self.place(nxt)
        self.br(entry["prop"])                                        # no clause matched: keep propagating
        self.place(else_l)
        if s.orelse:
            self.block(s.orelse)
        if not self.terminated:
            self.br(handled_l)
        # every normal way out of the statement runs the finally block once
        self.place(handled_l)
        self.tries.pop()
        if s.final:
            self.block(s.final)
        if not self.terminated:
            self.br(end_l)
        # an error is leaving the statement: park it while the finally block runs, then keep propagating
        self.place(entry["prop"])
        if s.final:
            hold = self.tmp("hold")
            self.allocas.append("  %s = alloca ptr" % hold)
            pending = self.tmp("pending")
            self.emit("%s = load ptr, ptr @tomato_exc" % pending)
            self.emit("store ptr %s, ptr %s" % (pending, hold))
            self.emit("store ptr null, ptr @tomato_exc")
            self.block(s.final)
            back = self.tmp("back")
            self.emit("%s = load ptr, ptr %s" % (back, hold))
            self.emit("store ptr %s, ptr @tomato_exc" % back)
        self.br(self.unwind_target())
        self.place(end_l)

    def assign_item(self, s):
        tgt = s.target
        o, ot = self.expr(tgt.obj)
        if isinstance(ot, MapT):
            return self.dict_write(o, ot, s)
        if not isinstance(ot, ListT):
            self.release(o, ot)
            raise TomatoError("only list items can be assigned by index (strings cannot be changed in place)", s.line)
        i, it = self.expr(tgt.index)
        if not is_int_type(it):
            raise TomatoError("an index must be an integer, found %r" % (it,), s.line)
        addr = self.list_slot(o, ot, self.resize(i, it, INT))
        v, vt = self.expr(s.value, ot.elem)
        self.store_owned(addr, self.coerce(v, vt, ot.elem, s.line, "assigned item"), ot.elem)
        self.release(o, ot)

    def for_loop(self, s):
        it = s.iter
        if isinstance(it, N.Call) and isinstance(it.func, N.Name) and it.func.name == "range":
            return self.for_range(s)
        v, t = self.expr(it)
        if isinstance(t, (MapT, SetT)):
            v, t = self.key_list(v, t)           # a loop over a dict or set walks a snapshot of its keys (P28)
        if not isinstance(t, ListT):
            self.release(v, t)
            raise NotCompiled("for over %r" % (t,), s.line)
        holder = self.hidden_slot("for.list", t)
        self.store_owned(holder, v, t)
        counter = self.hidden_slot("for.i", INT)
        self.emit("store i64 0, ptr %s" % counter)
        if s.var in self.vars and self.vars[s.var][1] != t.elem:
            raise TomatoError("loop variable %s already has type %r" % (s.var, self.vars[s.var][1]), s.line)
        reg, _ = self.slot(s.var, t.elem, s.line)
        head, body, step_l, end = self.label("each"), self.label("eachbody"), self.label("eachstep"), self.label("endeach")
        self.br(head)
        self.place(head)
        lst, i, ln, go, lenp = [self.tmp(x) for x in ("lst", "i", "n", "go", "lenp")]
        self.emit("%s = load ptr, ptr %s" % (lst, holder))
        self.emit("%s = load i64, ptr %s" % (i, counter))
        self.emit("%s = getelementptr { i64, i64, i64, i64, ptr }, ptr %s, i32 0, i32 2" % (lenp, lst))
        self.emit("%s = load i64, ptr %s" % (ln, lenp))          # read each pass: items appended in the loop are seen
        self.emit("%s = icmp slt i64 %s, %s" % (go, i, ln))
        self.cond_br(go, body, end)
        self.place(body)
        addr = self.list_slot(lst, t, i)
        item = self.tmp("item")
        self.emit("%s = load %s, ptr %s" % (item, llvm_type(t.elem), addr))
        self.retain(item, t.elem)
        self.store_owned(reg, item, t.elem)
        self.loops.append((end, step_l))
        self.block(s.body)
        self.loops.pop()
        if not self.terminated:
            self.br(step_l)
        self.place(step_l)
        cur, nxt = self.tmp("cur"), self.tmp("next")
        self.emit("%s = load i64, ptr %s" % (cur, counter))
        self.emit("%s = add i64 %s, 1" % (nxt, cur))
        self.emit("store i64 %s, ptr %s" % (nxt, counter))
        self.br(head)
        self.place(end)

    def for_range(self, s):
        it = s.iter
        if not 1 <= len(it.args) <= 3:
            raise TomatoError("range takes one to three integers", s.line)
        vals = []
        for a in it.args:
            v, t = self.expr(a, INT)
            if not is_int_type(t):
                raise TomatoError("range takes one to three integers", s.line)
            vals.append(self.resize(v, t, INT))
        start, stop, step = ("0", vals[0], "1") if len(vals) == 1 else (vals[0], vals[1], vals[2] if len(vals) == 3 else "1")
        counter = self.hidden_slot("ctr", INT)
        self.emit("store i64 %s, ptr %s" % (start, counter))
        z = self.tmp("stepzero")
        self.emit("%s = icmp eq i64 %s, 0" % (z, step))
        self.trap_if(z, "range step")
        if s.var in self.vars and self.vars[s.var][1] != INT:
            raise TomatoError("loop variable %s already has type %r" % (s.var, self.vars[s.var][1]), s.line)
        reg, _ = self.slot(s.var, INT, s.line)
        head, body, step_l, end = self.label("for"), self.label("forbody"), self.label("forstep"), self.label("endfor")
        self.br(head)
        self.place(head)
        cur, pos, lt, gt, c = [self.tmp(x) for x in ("i", "pos", "lt", "gt", "go")]
        self.emit("%s = load i64, ptr %s" % (cur, counter))
        self.emit("%s = icmp sgt i64 %s, 0" % (pos, step))
        self.emit("%s = icmp slt i64 %s, %s" % (lt, cur, stop))
        self.emit("%s = icmp sgt i64 %s, %s" % (gt, cur, stop))
        self.emit("%s = select i1 %s, i1 %s, i1 %s" % (c, pos, lt, gt))
        self.cond_br(c, body, end)
        self.place(body)
        self.emit("store i64 %s, ptr %s" % (cur, reg))
        self.loops.append((end, step_l))
        self.block(s.body)
        self.loops.pop()
        if not self.terminated:
            self.br(step_l)
        self.place(step_l)
        nxt, now = self.tmp("next"), self.tmp("now")
        self.emit("%s = load i64, ptr %s" % (now, counter))
        self.emit("%s = add i64 %s, %s" % (nxt, now, step))      # wraps only past the int range, which ends the loop anyway
        self.emit("store i64 %s, ptr %s" % (nxt, counter))
        self.br(head)
        self.place(end)

    # ---- whole functions
    def prologue(self):
        """Store the parameters in slots that own them (a heap parameter is retained: the caller only lent it)."""
        node = self.fn.node
        names = [p.name for p in node.params]
        sig = []
        for name, t in zip(names, self.fn.ptypes_all):
            sig.append("%s %%p.%s" % (llvm_type(t), name))
        for name, t in zip(names, self.fn.ptypes_all):
            reg, _ = self.slot(name, t, node.line)
            self.emit("store %s %%p.%s, ptr %s" % (llvm_type(t), name, reg))
            self.retain("%%p.%s" % name, t)
        return ", ".join(sig)

    def finish(self, sig):
        fn = self.fn
        tail = []
        for lab, kind, line, target in self.fail_blocks:
            tail += ["%s:" % lab] + ["  " + x for x in self.cg.raise_runtime(kind, line)] + ["  br label %%%s" % target]
        ep = ["epilogue:"]
        for reg in self.rc_slots:
            o = self.tmp("rel")
            ep.append("  %s = load ptr, ptr %s" % (o, reg))
            ep.append("  call void @tomato_release(ptr %s)" % o)
        if fn.ret == NoneT:
            ep.append("  ret void")
        else:
            r = self.tmp("ret")
            ep.append("  %s = load %s, ptr %%retval" % (r, llvm_type(fn.ret)))
            ep.append("  ret %s %s" % (llvm_type(fn.ret), r))
        allocas = list(self.allocas)
        if fn.ret != NoneT:
            zero = "null" if llvm_type(fn.ret) == "ptr" else ("0.0" if llvm_type(fn.ret) == "double" else "0")
            allocas.insert(0, "  %%retval = alloca %s\n  store %s %s, ptr %%retval" % (llvm_type(fn.ret), llvm_type(fn.ret), zero))
        head = "define %s @%s(%s) {\nentry:\n%s" % (llvm_type(fn.ret), fn.symbol, sig, "\n".join(allocas))
        return head + "\n" + "\n".join(self.lines + tail + ep) + "\n}\n"

    def compile(self):
        fn = self.fn
        sig = self.prologue()
        self.block(fn.node.body)
        if not self.terminated:
            if fn.ret == NoneT:
                self.br("epilogue")
            else:
                self.emit("br label %%%s" % self.fail("missing return"))
                self.terminated = True
        return self.finish(sig)


class Codegen:
    def __init__(self, interp, mode="debug"):
        self.interp, self.mode = interp, mode
        self.strings, self.declares, self.string_names = [], set(), {}
        self.cstrings, self.cstring_names = [], {}
        self.codes = {}                       # a heap type's key -> its type code (D35a); 1 is the string
        self.next_code = 2
        self.extra_functions = []             # destructors generated on demand
        self.sizes = {}
        self.symbols = {}

    # ---- error modes (D34a)
    def mode_code(self):
        return {"debug": 1, "normal": 2, "release": 3}[self.mode]

    def runtime_error_class(self):
        return self.interp.classes["RuntimeError"]

    def error_message(self, kind, line):
        if self.mode == "debug":
            return "line %d: %s" % (line, errcodes.KINDS[errcodes.code_for(kind)][1])
        if self.mode == "normal":
            return "E%02d:%d" % (errcodes.code_for(kind), line)
        return ""

    def raise_runtime(self, kind, line):
        """IR lines that raise a RuntimeError for a failure the language itself reports (D22a, D34a)."""
        rt = self.runtime_error_class()
        self.rt_counter = getattr(self, "rt_counter", 0) + 1
        o = "%%rterr.%d" % self.rt_counter
        return ["%s = call ptr @%s(ptr %s)" % (o, self.ctor_symbol(rt), self.strobj(self.error_message(kind, line))),
                "store ptr %s, ptr @tomato_exc" % o, "store i32 %d, ptr @tomato_exc_line" % line,
                "store i32 1, ptr @tomato_exc_rt", "store i32 1, ptr @tomato_exc_seen"]

    def failure(self, kind, line):
        """The IR lines that report a failure and stop, by error mode (D34a): debug prints the full message,
        normal prints a short code that `tomato explain` decodes, release prints nothing."""
        if self.mode == "debug":
            text = "line %d: %s" % (line, errcodes.KINDS[errcodes.code_for(kind)][1])
            return ["call void @tomato_fail(ptr %s)" % self.cstr(text)]
        if self.mode == "normal":
            return ["call void @tomato_fail_code(i32 %d, i32 %d)" % (errcodes.code_for(kind), line)]
        return ["call void @tomato_trap()"]

    # ---- constants
    def cstr(self, text):
        """A plain NUL-terminated C string, for the runtime's error messages."""
        if text in self.cstring_names:
            return self.cstring_names[text]
        data = text.encode("utf-8") + b"\0"
        name = "@.cstr.%d" % len(self.cstrings)
        self.cstring_names[text] = name
        body = "".join(chr(b) if 32 <= b < 127 and b not in (34, 92) else "\\%02X" % b for b in data)
        self.cstrings.append('%s = private unnamed_addr constant [%d x i8] c"%s"' % (name, len(data), body))
        return name

    def strobj(self, text):
        """A static string object that is never freed (reference count 0): {header, bytes, chars, data}."""
        if text in self.string_names:
            return self.string_names[text]
        data = text.encode("utf-8")
        name = "@.str.%d" % len(self.strings)
        self.string_names[text] = name
        body = "".join(chr(b) if 32 <= b < 127 and b not in (34, 92) else "\\%02X" % b for b in data) + "\\00"
        chars = sum(1 for b in data if b & 0xC0 != 0x80)
        self.strings.append('%s = private constant { i64, i64, i64, i64, [%d x i8] } { i64 -1, i64 1, i64 %d, i64 %d, '
                            '[%d x i8] c"%s" }' % (name, len(data) + 1, len(data), chars, len(data) + 1, body))
        return name

    # ---- heap types: type codes, layouts, destructors
    def type_code(self, t):
        if t == StrT:
            return 1
        key = ("class", t.name) if isinstance(t, ClassT) else (type(t).__name__, repr(t))
        if key not in self.codes:
            self.codes[key] = (self.next_code, t)
            self.next_code += 1
        return self.codes[key][0]

    def size_of(self, llt):
        return {"i1": 1, "i8": 1, "i16": 2, "i32": 4, "i64": 8, "double": 8, "ptr": 8}.get(llt) or \
            (((int(llt[1:]) + 7) // 8) if llt.startswith("i") else 8)

    def layout(self, key):
        """The fields of a class, parent first: [(name, owner class, FieldDef, type)]."""
        out = []
        for k in reversed(list(self.interp.classes[key].chain())):
            for name, (fdef, ft) in k.fields.items():
                out.append((name, k, fdef, ft))
        return out

    def struct_type(self, key):
        return "%%class.%d" % self.type_code(ClassT(key))

    def field_index(self, key, name):
        for k, (n, _, _, _) in enumerate(self.layout(key)):
            if n == name:
                return k + 2
        raise KeyError(name)

    def func_symbol(self, fn):
        """The symbol of a function or method; entry points keep a readable name."""
        if id(fn) not in self.symbols:
            if fn.owner is None:
                self.symbols[id(fn)] = "tomato.%s" % fn.key
            else:
                self.symbols[id(fn)] = "tomato.m.%d.%s" % (self.type_code(ClassT(fn.owner.name)), fn.name)
        return self.symbols[id(fn)]

    def ctor_symbol(self, cls):
        return "tomato.new.%d" % self.type_code(ClassT(cls.name))

    def compiled(self, c):
        return True

    def has_subclasses(self, info):
        return any(c is not info and self.interp.is_subclass(c, info.name) for c in self.interp.classes.values()
                   if self.compiled(c))

    def implementations(self, info, name):
        """Every method that a call to `name` on an instance of `info` might run."""
        out = []
        for c in self.interp.classes.values():
            if self.compiled(c) and self.interp.is_subclass(c, info.name):
                m = c.find_method(name)
                if m is not None and m.has_self and m not in out:
                    out.append(m)
        return out

    def main_classes(self):
        return [c for c in self.interp.classes.values() if self.compiled(c)]

    def method_slots(self):
        names = []
        for i in self.interp.ifaces.values():
            for n in self.interp.iface_requirements(i.name):
                if n not in names:
                    names.append(n)
        for c in self.interp.classes.values():
            if self.compiled(c):
                for k in c.chain():
                    for n, m in k.methods.items():
                        if m.has_self and m.node.marker != "init" and n not in names:
                            names.append(n)
        return names

    def dispatch(self, fc, obj, name):
        """Emit a virtual lookup: the object's type code picks a vtable, the method name picks the slot."""
        slot = self.method_slots().index(name)
        code, vts, vt, fp, f = [fc.tmp(x) for x in ("code", "vts", "vt", "fp", "f")]
        raw = fc.tmp("rawcode")
        fc.emit("%s = load i64, ptr %s" % (raw, self._type_field(fc, obj)))
        fc.emit("%s = and i64 %s, 4294967295" % (code, raw))       # the upper bits belong to the cycle collector
        fc.emit("%s = getelementptr ptr, ptr @tomato_vtables, i64 %s" % (vts, code))
        fc.emit("%s = load ptr, ptr %s" % (vt, vts))
        fc.emit("%s = getelementptr ptr, ptr %s, i64 %d" % (fp, vt, slot))
        fc.emit("%s = load ptr, ptr %s" % (f, fp))
        return f

    def type_field(self, fc, obj):
        return self._type_field(fc, obj)

    def _type_field(self, fc, obj):
        p = fc.tmp("tp")
        fc.emit("%s = getelementptr { i64, i64 }, ptr %s, i32 0, i32 1" % (p, obj))
        return p

    def entry_wrapper(self, fn):
        k = len(fn.ptypes)
        out = ["define i32 @main(i32 %argc, ptr %argv) {", "entry:", "  %n = sub i32 %argc, 1",
               "  %ok = icmp eq i32 %n, " + str(k), "  br i1 %ok, label %go, label %bad", "bad:",
               "  call void @tomato_usage(i32 %d, i32 %%n)" % k, "  unreachable", "go:"]
        args, owned = [], []
        for i, (p, t) in enumerate(zip(fn.node.params, fn.ptypes)):
            pos = i + 1
            out.append("  %%a%d.ptr = getelementptr ptr, ptr %%argv, i64 %d" % (i, pos))
            out.append("  %%a%d.s = load ptr, ptr %%a%d.ptr" % (i, i))
            s = "%%a%d.s" % i
            if t == StrT:
                out.append("  %%a%d = call ptr @tomato_str_from_cstr(ptr %s)" % (i, s))
                args.append("ptr %%a%d" % i)
                owned.append("%%a%d" % i)
            elif t == FloatT:
                out.append("  %%a%d = call double @tomato_parse_f64(ptr %s, i32 %d)" % (i, s, pos))
                args.append("double %%a%d" % i)
            elif t == BoolT:
                out.append("  %%a%d.w = call i32 @tomato_parse_bool(ptr %s, i32 %d)" % (i, s, pos))
                out.append("  %%a%d = trunc i32 %%a%d.w to i1" % (i, i))
                args.append("i1 %%a%d" % i)
            elif is_int_type(t):
                b = bits_of(t)
                if is_signed(t):
                    out.append("  %%a%d.v = call i64 @tomato_parse_i64(ptr %s, i32 %d)" % (i, s, pos))
                    if b < 64:
                        out.append("  call void @tomato_fit_signed(i64 %%a%d.v, i32 %d, i32 %d)" % (i, b, pos))
                else:
                    out.append("  %%a%d.v = call i64 @tomato_parse_u64(ptr %s, i32 %d)" % (i, s, pos))
                    if b < 64:
                        out.append("  call void @tomato_fit_unsigned(i64 %%a%d.v, i32 %d, i32 %d)" % (i, b, pos))
                if b < 64:
                    out.append("  %%a%d = trunc i64 %%a%d.v to i%d" % (i, i, b))
                    args.append("i%d %%a%d" % (b, i))
                else:
                    args.append("i64 %%a%d.v" % i)
            else:
                raise NotCompiled("an entry point input of type %r" % (t,), fn.node.line)
        out.append("  call void @%s(%s)" % (self.func_symbol(fn), ", ".join(args)))
        out += ["  %ex = load ptr, ptr @tomato_exc", "  %has = icmp ne ptr %ex, null",
                "  br i1 %has, label %uncaught, label %fine", "uncaught:",
                "  %eline = load i32, ptr @tomato_exc_line", "  %ert = load i32, ptr @tomato_exc_rt",
                "  call void @tomato_report_uncaught(ptr %%ex, i32 %%eline, i32 %%ert, i32 %d)" % self.mode_code(),
                "  unreachable", "fine:"]
        for reg in owned:
            out.append("  call void @tomato_release(ptr %s)" % reg)
        if self.mode == "debug":
            out.append("  call void @tomato_leak_check()")
        out.append("  ret i32 0")
        out.append("}")
        return "\n".join(out) + "\n"


RUNTIME = """declare void @tomato_fail(ptr)
declare void @tomato_fail_code(i32, i32)
declare void @tomato_trap()
declare void @tomato_usage(i32, i32)
declare void @tomato_print_i64(i64)
declare void @tomato_print_u64(i64)
declare void @tomato_print_bool(i32)
declare void @tomato_print_f64(double)
declare void @tomato_print_strobj(ptr)
declare void @tomato_print_space()
declare void @tomato_print_newline()
declare i64 @tomato_parse_i64(ptr, i32)
declare i64 @tomato_parse_u64(ptr, i32)
declare double @tomato_parse_f64(ptr, i32)
declare i32 @tomato_parse_bool(ptr, i32)
declare void @tomato_fit_signed(i64, i32, i32)
declare void @tomato_fit_unsigned(i64, i32, i32)
declare ptr @tomato_alloc(i64, i64)
declare void @tomato_retain(ptr)
declare void @tomato_release(ptr)
declare void @tomato_leak_check()
declare ptr @tomato_str_from_cstr(ptr)
declare ptr @tomato_str_concat(ptr, ptr)
declare i64 @tomato_str_len(ptr)
declare i32 @tomato_str_cmp(ptr, ptr)
declare i32 @tomato_str_eq_opt(ptr, ptr)
declare ptr @tomato_str_index(ptr, i64)
declare ptr @tomato_str_slice(ptr, i64, i64)
declare void @tomato_report_uncaught(ptr, i32, i32, i32)
declare ptr @tomato_str_from_i64(i64)
declare ptr @tomato_str_from_u64(i64)
declare ptr @tomato_str_from_f64(double)
declare ptr @tomato_str_from_bool(i32)
declare ptr @tomato_list_new(i64)
declare ptr @tomato_list_push(ptr, i64)
declare void @tomato_list_free_data(ptr)
declare i32 @tomato_is_subclass(i64, i64)
declare ptr @tomato_dict_new(i64, i64, i32)
declare ptr @tomato_dict_find(ptr, i64)
declare ptr @tomato_dict_insert(ptr, i64, i32)
declare i32 @tomato_dict_delete(ptr, i64)
declare ptr @tomato_dict_keys(ptr, i64, i64)
declare ptr @tomato_dict_values(ptr, i64, i64, i32)
declare void @tomato_dict_destroy(ptr, i32, i32)
declare i32 @tomato_str_contains(ptr, ptr)
declare i64 @tomato_str_find(ptr, ptr)
declare i32 @tomato_str_startswith(ptr, ptr)
declare i32 @tomato_str_endswith(ptr, ptr)
declare ptr @tomato_str_replace(ptr, ptr, ptr)
declare ptr @tomato_str_split(ptr, ptr, i64, i64)
declare ptr @tomato_str_join(ptr, ptr)
declare ptr @tomato_file_open(ptr, ptr)
declare ptr @tomato_file_read(ptr)
declare void @tomato_file_write(ptr, ptr)
declare void @tomato_file_close(ptr)
"""


def compile_to_ir(src, entry="main", search=None, mode="debug"):
    """Check `src` and compile it to LLVM IR text; raises TomatoError for anything outside the subset."""
    interp = Interpreter(search=search, warn_out=_Sink())
    interp.check(src)
    if entry not in interp.entries:
        raise TomatoError("no function marked @%s: a program starts at its entry point, @main unless another is "
                          "chosen (D16a)" % entry)
    if mode not in ("debug", "normal", "release"):
        raise TomatoError("mode must be debug, normal or release, found %r" % mode)
    cg = Codegen(interp, mode)
    units = {}                  # symbol -> (compiled text or NotCompiled error, callees)
    main_classes = [c for c in interp.classes.values() if cg.compiled(c)]

    def add_unit(unit, module, compiler_cls=FuncCompiler):
        fc = compiler_cls(cg, unit)
        if any(p.star for p in unit.node.params):
            units[unit.symbol] = (NotCompiled("*args and **kwargs parameters", unit.node.line), fc.callees)
            return
        prev, interp.cur_mod = interp.cur_mod, module      # names resolve in the module the code was written in (D24c)
        try:
            units[unit.symbol] = (fc.compile(), fc.callees)
        except NotCompiled as err:
            units[unit.symbol] = (err, fc.callees)
        finally:
            interp.cur_mod = prev

    for f in interp.funcs.values():
        u = Unit(cg.func_symbol(f), f.node, f.ptypes, f.ret, None, f.name)
        u.ptypes_all = list(f.ptypes)
        add_unit(u, f.module)
    for c in main_classes:
        for m in c.methods.values():
            ptypes = ([ClassT(c.name)] if m.has_self else []) + list(m.ptypes)
            u = Unit(cg.func_symbol(m), m.node, m.ptypes, m.ret, c, m.name)
            u.ptypes_all = ptypes
            add_unit(u, c.module)
        prev, interp.cur_mod = interp.cur_mod, c.module
        try:
            units[cg.ctor_symbol(c)] = compile_ctor(cg, c)
        finally:
            interp.cur_mod = prev
    fn = interp.entries[entry]
    root = cg.func_symbol(fn)
    reachable, todo = set(), [root]
    while todo:
        sym = todo.pop()
        if sym in reachable or sym not in units:
            continue
        reachable.add(sym)
        text, callees = units[sym]
        if isinstance(text, NotCompiled):
            raise text
        todo.extend(callees)
    bodies = [units[s][0] for s in sorted(units) if s in reachable]
    wrapper = cg.entry_wrapper(fn)
    tables = heap_tables(cg, interp, main_classes, {s for s in reachable})
    out = ["; Tomato compiled to LLVM IR (D30a), %s mode (D34a). Link with tomato/runtime/tomato_rt.c." % mode, RUNTIME]
    out += sorted(cg.declares) + [""]
    out += cg.cstrings + cg.strings + [""]
    out += tables["types"] + bodies + cg.extra_functions + [wrapper] + tables["tables"]
    return "\n".join(out)


class _Sink:
    """Compile-time warnings are reported by `tomato run`; the compiler does not print them twice."""

    def write(self, text):
        pass


def compile_ctor(cg, cls):
    """`new Class(args)`: allocate, set the declared defaults of every field, then run @init (D12ae, D12af, D12w)."""
    init = cls.nearest("init")
    ptypes = list(init.ptypes) if init is not None else []

    class Node:
        line = cls.node.line
        marker = None
        params = []

    node = Node()
    from .nodes import Param
    node.params = [Param("a%d" % i, None, None, None) for i in range(len(ptypes))]
    unit = Unit(cg.ctor_symbol(cls), node, ptypes, ClassT(cls.name), None, cls.node.name)
    unit.ptypes_all = ptypes
    fc = FuncCompiler(cg, unit)
    t = ClassT(cls.name)
    try:
        sig = fc.prologue()
        obj = fc.tmp("obj")
        st = cg.struct_type(cls.name)
        size = fc.tmp("size")
        fc.emit("%s = ptrtoint ptr getelementptr (%s, ptr null, i32 1) to i64" % (size, st))
        fc.emit("%s = call ptr @tomato_alloc(i64 %s, i64 %d)" % (obj, size, cg.type_code(t)))
        for name, owner, fdef, ft in cg.layout(cls.name):
            if fdef.value is not None:
                fc.line = fdef.line
                v, vt = fc.expr(fdef.value, ft)
                addr = fc.tmp("fld")
                fc.emit("%s = getelementptr %s, ptr %s, i32 0, i32 %d" % (addr, st, obj, cg.field_index(cls.name, name)))
                fc.emit("store %s %s, ptr %s" % (llvm_type(ft), fc.coerce(v, vt, ft, fdef.line, "field value"), addr))
        if init is not None:
            sym = cg.func_symbol(init)
            fc.callees.add(sym)
            args = ["ptr " + obj] + ["%s %%p.a%d" % (llvm_type(pt), i) for i, pt in enumerate(ptypes)]
            fc.emit("call void @%s(%s)" % (sym, ", ".join(args)))
            ex, has = fc.tmp("ex"), fc.tmp("has")
            fc.emit("%s = load ptr, ptr @tomato_exc" % ex)
            fc.emit("%s = icmp ne ptr %s, null" % (has, ex))
            bad, ok = fc.label("initfailed"), fc.label("initok")
            fc.cond_br(has, bad, ok)
            fc.place(bad)
            fc.emit("call void @tomato_release(ptr %s)" % obj)      # an @init that raised leaves no object behind
            fc.br("epilogue")
            fc.place(ok)
        fc.emit("store ptr %s, ptr %%retval" % obj)
        fc.br("epilogue")
        return fc.finish(sig), fc.callees
    except NotCompiled as err:
        return err, fc.callees


def heap_tables(cg, interp, main_classes, reachable):
    """Struct types, destructors and vtables, indexed by type code (D35a)."""
    types, tables = [], []
    for c in main_classes:
        cg.type_code(ClassT(c.name))
    # descriptors for every heap type: what its fields hold, so the runtime can free and trace objects (D29d)
    entries = {}
    kinds, offsets = {}, {}
    for key, (code, t) in sorted(cg.codes.items(), key=lambda kv: kv[1][0]):
        if isinstance(t, ClassT):
            fields = cg.layout(t.name)
            types.append("%%class.%d = type { i64, i64%s }" % (code, "".join(", " + llvm_type(f[3]) for f in fields)))
            rc_fields = [cg.field_index(t.name, f[0]) for f in fields if is_rc(f[3])]
            kinds[code] = 1
            offs = ["i32 trunc (i64 ptrtoint (ptr getelementptr (%%class.%d, ptr null, i32 0, i32 %d) to i64) to i32)"
                    % (code, idx) for idx in rc_fields] + ["i32 -1"]
            tables.append("@tomato.offs.%d = constant [%d x i32] [%s]" % (code, len(offs), ", ".join(offs)))
            offsets[code] = "@tomato.offs.%d" % code
        elif isinstance(t, (MapT, SetT)):
            kt = t.key if isinstance(t, MapT) else t.elem
            kinds[code] = 3 | (256 if kt == StrT else 0) | (512 if (isinstance(t, MapT) and is_rc(t.value)) else 0)
        else:
            kinds[code] = 2 | (256 if is_rc(t.elem) else 0)
    n = cg.next_code
    tables.append("@tomato_exc = global ptr null")
    tables.append("@tomato_exc_line = global i32 0")
    tables.append("@tomato_exc_rt = global i32 0")
    tables.append("@tomato_exc_seen = global i32 0")
    names_tbl = []
    for k in range(n):
        owner = next((c for c in main_classes if cg.codes[("class", c.name)][0] == k), None) if k >= 2 else None
        names_tbl.append("ptr %s" % cg.cstr(owner.node.name) if owner is not None else "ptr null")
    tables.append("@tomato_class_names = constant [%d x ptr] [%s]" % (n, ", ".join(names_tbl)))
    parent_codes = []
    for k in range(n):
        owner = next((c for c in main_classes if cg.codes[("class", c.name)][0] == k), None) if k >= 2 else None
        parent_codes.append(str(cg.codes[("class", owner.parent.name)][0]) if owner is not None and owner.parent is not None else "0")
    tables.append("@tomato_parents = constant [%d x i64] [%s]" % (n, ", ".join("i64 " + x for x in parent_codes)))
    tables.append("@tomato_kinds = constant [%d x i32] [%s]" % (n, ", ".join("i32 %d" % kinds.get(k, 0) for k in range(n))))
    tables.append("@tomato_offsets = constant [%d x ptr] [%s]" % (n, ", ".join(
        "ptr %s" % offsets[k] if k in offsets else "ptr null" for k in range(n))))
    # vtables: one per class, one slot per method name
    names = cg.method_slots()
    vt_entries = []
    for k in range(n):
        owner = next((c for c in main_classes if cg.codes[("class", c.name)][0] == k), None) if k >= 2 else None
        if owner is None or not names:
            vt_entries.append("ptr null")
            continue
        slots = []
        for nm in names:
            m = owner.find_method(nm)
            sym = cg.func_symbol(m) if (m is not None and m.has_self and m.node.marker != "init") else None
            slots.append("ptr @%s" % sym if sym in reachable else "ptr null")
        tables.append("@tomato.vt.%d = constant [%d x ptr] [%s]" % (k, len(names), ", ".join(slots)))
        vt_entries.append("ptr @tomato.vt.%d" % k)
    tables.append("@tomato_vtables = constant [%d x ptr] [%s]" % (n, ", ".join(vt_entries)))
    return {"types": types, "tables": tables}
