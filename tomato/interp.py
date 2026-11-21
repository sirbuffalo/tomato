"""Declaration checks and a tree-walking interpreter for Tomato."""
import os
import sys

from . import nodes as N
from .errors import NotDecided, RunFailure, TomatoError, TomatoRaise
from .parser import parse
from .values import (BoolT, ClassT, FixedInt, FixedT, FloatT, IfaceT, INT, Instance, IntT, ListT, NoneT, OptT, UnionT, InterT, TupleT, TTuple,
                     Rational, RationalT, RangeObj, RangeT, SimpleT, StrT, contains, int_value, is_int_type,
                     is_int_value, show, value_type, TList, MapT, SetT, TMap, TSet, TFile, FileT, key_of)

MAX_CALL_DEPTH = 10000  # placeholder; the language has no recursion limit decision yet
SIMPLE = {"File": FileT, "range": RangeT, "float": FloatT, "rational": RationalT, "bool": BoolT, "str": StrT, "None": NoneT}


class FuncInfo:
    def __init__(self, node, owner, ptypes, ret, module="main", key=None):
        self.node, self.owner, self.ptypes, self.ret, self.module = node, owner, ptypes, ret, module
        self.key = key or node.name
        self.has_self = bool(node.params) and node.params[0].name == "self"
        self.name = node.name

    def sig(self):
        return tuple(self.ptypes), self.ret


class ClassInfo:
    """A class. `name` is its key in the interpreter's tables: the plain name in the main program and the prelude,
    and `module.Name` elsewhere (D24c: each module has its own namespace). `node.name` is the name as written."""

    def __init__(self, node, module="main", key=None):
        self.node, self.name, self.module = node, key or node.name, module
        self.parent = None
        self.fields = {}     # own fields: name -> (FieldDef, type)
        self.methods = {}    # own methods
        self.ifaces = set()  # keys of the interfaces it declares, filled in once names are resolved

    def chain(self):
        c = self
        while c:
            yield c
            c = c.parent

    def find_method(self, name):
        for c in self.chain():
            if name in c.methods:
                return c.methods[name]

    def find_field(self, name):
        for c in self.chain():
            if name in c.fields:
                return c, c.fields[name]
        return None, None

    def own_init(self):
        return next((m for m in self.methods.values() if m.node.marker == "init"), None)

    def nearest(self, marker):
        for c in self.chain():
            for m in c.methods.values():
                if m.node.marker == marker:
                    return m


class IfaceInfo:
    def __init__(self, node, module="main", key=None):
        self.node, self.name, self.module = node, key or node.name, module
        self.parents = []    # keys of the interfaces it extends
        self.methods = {}


_UNSET = object()


class BreakLoop(Exception):
    pass


class ContinueLoop(Exception):
    pass


class Return(Exception):
    def __init__(self, value):
        self.value = value


class Frame:
    def __init__(self, owner=None, in_init=False):
        self.vars = {}
        self.owner = owner
        self.in_init = in_init


class Interpreter:
    def __init__(self, out=None, modules=None, search=None, llvm_ir=None, warn_out=None):
        self.out = out or sys.stdout
        self.sources = modules or {}          # module name -> source text (overrides the search path)
        self.search = list(search or [])      # directories holding NAME.tom files (D24a placeholder)
        self.exports = {}                     # module -> names it exports
        self.loading = []                     # modules being loaded, to catch import cycles
        self.module_text = {}                 # module name -> source text actually loaded
        self.cur_mod = "main"
        self.warnings = []                    # compile-time warnings: (line, text)
        self.warn_out = warn_out              # where warnings are printed; None means standard error
        self.llvm_decls = {}                  # !name declarations: name -> (param types, return type) (D27b)
        self.llvm = None                      # LLVM functions callable as !name (D27a, P33)
        if llvm_ir:
            from .llvm_bridge import LlvmBridge
            self.llvm = LlvmBridge()
            for label, text in llvm_ir:
                self.llvm.add_ir(text, label)
        self.classes, self.ifaces, self.funcs = {}, {}, {}
        self.extra_impl = []     # (class key, interface key, line)
        self.scope = {"builtin": {}}   # module -> {name as written: table key}, the module's own namespace (D24c)
        self.globals = Frame()
        self.depth = 0

    # ---------------------------------------------------------- types
    def resolve(self, ref):
        if ref is None:
            return NoneT
        n = ref.name
        if n in ("int", "uint"):
            if ref.length is None:
                if n == "uint":
                    raise TomatoError("uint needs a length: uint[length=N]", ref.line)
                return INT
            bits = self.const_int(ref.length)
            if bits < 1:
                raise TomatoError("integer length must be a positive whole number (D05i)", ref.line)
            return FixedT(n == "int", bits)
        if n == "union":
            members = []
            for m in ref.arg:
                t = self.resolve(m)
                for x in (t.members if isinstance(t, UnionT) else (t.inner, NoneT) if isinstance(t, OptT) else (t,)):
                    if x in members:
                        raise TomatoError("%r | %r repeats a type, which is not a useful type (D23g)" % (x, x), ref.line)
                    members.append(x)
            if len(members) == 2 and NoneT in members:
                return OptT(members[0] if members[1] == NoneT else members[1])
            if members == [NoneT]:
                raise TomatoError("None | None is not a useful type (D23g)", ref.line)
            return UnionT(members)
        if n == "intersection":
            members = []
            for m in ref.arg:
                t = self.resolve(m)
                if not isinstance(t, (ClassT, IfaceT)):
                    raise TomatoError("only interfaces and classes can be joined with & (D23h), found %r" % (t,), ref.line)
                if t in members:
                    raise TomatoError("%r & %r repeats a type (D23h)" % (t, t), ref.line)
                members.append(t)
            if all(isinstance(t, ClassT) for t in members):
                raise TomatoError("& needs at least one interface among its types, found only classes (D23h)", ref.line)
            if sum(isinstance(t, ClassT) for t in members) > 1:
                raise TomatoError("an intersection can hold at most one class (D23h)", ref.line)
            return InterT(members)
        if n == "optional":
            inner = self.resolve(ref.arg)
            if inner == NoneT or isinstance(inner, OptT):
                raise TomatoError("%r | None is not a useful type (D23b)" % (inner,), ref.line)
            return OptT(inner)
        if n == "list":
            return ListT(self.resolve(ref.arg))
        if n == "tuple":
            return TupleT(self.resolve(ref.arg))
        if n in ("dict", "set"):
            kt = self.resolve(ref.arg)
            if not (is_int_type(kt) or kt in (StrT, BoolT)):
                raise NotDecided("%s keys of type %r (only integers, str and bool are decided)"
                                 % (n, kt), ref.line)
            return MapT(kt, self.resolve(ref.arg2)) if n == "dict" else SetT(kt)
        if n in SIMPLE:
            return SIMPLE[n]
        key = self.scope_get(n)
        if key in self.classes:
            return ClassT(key)
        if key in self.ifaces:
            return IfaceT(key)
        raise TomatoError("unknown type %r" % n, ref.line)

    def type_named(self, n):
        """The type a bare name stands for in `x in Type` (D23f), or None when the name is not a type."""
        if n == "int":
            return INT
        if n in SIMPLE:
            return SIMPLE[n]
        key = self.scope_get(n)
        if key in self.classes:
            return ClassT(key)
        if key in self.ifaces:
            return IfaceT(key)
        return None

    def type_expr(self, e, fr):
        """The type an expression on the right of `in` writes (a name, or names joined by | and &), or None (D23f, D23h)."""
        if isinstance(e, N.Name):
            return self.type_named(e.name) if e.name not in fr.vars else None
        if isinstance(e, N.BinOp) and e.op in ("|", "&"):
            a, b = self.type_expr(e.left, fr), self.type_expr(e.right, fr)
            if a is None or b is None:
                return None
            if e.op == "|":
                ms = (a.members if isinstance(a, UnionT) else (a,)) + (b.members if isinstance(b, UnionT) else (b,))
                return UnionT(ms)
            if not (isinstance(a, (ClassT, IfaceT, InterT)) and isinstance(b, (ClassT, IfaceT, InterT))):
                raise TomatoError("only interfaces and classes can be joined with & (D23h)", e.line)
            ms = (a.members if isinstance(a, InterT) else (a,)) + (b.members if isinstance(b, InterT) else (b,))
            if all(isinstance(t, ClassT) for t in ms):
                raise TomatoError("& needs at least one interface among its types, found only classes (D23h)", e.line)
            return InterT(ms)
        return None

    def type_match(self, v, t):
        if isinstance(t, UnionT):
            return any(self.type_match(v, m) for m in t.members)
        if isinstance(t, InterT):
            return all(self.type_match(v, m) for m in t.members)
        if isinstance(t, (ClassT, IfaceT)):
            return self.fits(v, t)
        return value_type(v) == t

    def const_int(self, e):
        if isinstance(e, N.IntLit):
            return e.value
        if isinstance(e, N.UnOp) and e.op == "-":
            return -self.const_int(e.operand)
        if isinstance(e, N.BinOp) and e.op in "+-*":
            a, b = self.const_int(e.left), self.const_int(e.right)
            return a + b if e.op == "+" else a - b if e.op == "-" else a * b
        raise NotDecided("widths other than integer-literal arithmetic (named constants)", e.line)

    # ---------------------------------------------------------- declaration collection and checks
    # ---------------------------------------------------------- modules (D24a; syntax and rules are placeholders, P31)
    def scope_get(self, name):
        """The table key a name written in the current module stands for, or None (D24c)."""
        return self.scope.get(self.cur_mod, {}).get(name)

    def vis_class(self, n):
        return self.classes.get(self.scope_get(n))

    def vis_name(self, n):
        key = self.scope_get(n)
        return self.funcs.get(key) or self.classes.get(key)

    def key_for(self, modname, name):
        return name if modname in ("main", "builtin") else "%s.%s" % (modname, name)

    def module_source(self, name, line):
        text = self.find_module_source(name, line)
        self.module_text[name] = text   # kept so `tomato compile` can bundle every module a program uses
        return text

    def find_module_source(self, name, line):
        if name in self.sources:
            return self.sources[name]
        here = os.path.dirname(os.path.abspath(__file__))
        for d in self.search + [os.path.join(here, "std")]:
            path = os.path.join(d, name + ".tom")
            if os.path.isfile(path):
                with open(path, encoding="utf-8") as f:
                    return f.read()
        try:  # the standard library inside a bundled executable is not a plain file
            import pkgutil
            data = pkgutil.get_data("tomato", "std/%s.tom" % name)
            if data is not None:
                return data.decode("utf-8")
        except (OSError, ImportError):
            pass
        raise TomatoError("no module named %r" % name, line)

    def import_module(self, imp, into):
        name = imp.module
        if name in self.loading:
            raise TomatoError("modules import each other in a cycle: %s" % " -> ".join(self.loading + [name]), imp.line)
        if name not in self.exports:
            self.loading.append(name)
            try:
                self.load(parse(self.module_source(name, imp.line)), name)
            finally:
                self.loading.pop()
        for n in imp.names:
            if n not in self.exports[name]:
                raise TomatoError("module %s does not export %r" % (name, n), imp.line)
            if n in self.scope[into] and self.scope[into][n] != self.scope[name][n]:
                raise TomatoError("%s is already declared in this module" % n, imp.line)
            self.scope[into][n] = self.scope[name][n]

    def load(self, module, modname="main"):
        items = []
        for it in module.body:
            items.extend(it.body if isinstance(it, N.Module) else [it])
        self.scope.setdefault(modname, dict(self.scope["builtin"]) if modname != "builtin" else {})
        for it in items:
            if isinstance(it, N.Import):
                self.import_module(it, modname)
        prev, self.cur_mod = self.cur_mod, modname
        try:
            self.load_declarations(items, modname)
        finally:
            self.cur_mod = prev

    def declare_check(self, name, line):
        if name in self.scope[self.cur_mod]:
            raise TomatoError("%s is already declared in this module (or built in or imported)" % name, line)

    def load_declarations(self, items, modname):
        new_classes, new_ifaces, new_impl, new_funcs = [], [], [], []
        exported = set()
        for it in items:
            if isinstance(it, N.ClassDef):
                self.declare_check(it.name, it.line)
                key = self.key_for(modname, it.name)
                self.classes[key] = c = ClassInfo(it, modname, key)
                self.scope[modname][it.name] = key
                new_classes.append(c)
            elif isinstance(it, N.InterfaceDef):
                self.declare_check(it.name, it.line)
                key = self.key_for(modname, it.name)
                self.ifaces[key] = i = IfaceInfo(it, modname, key)
                self.scope[modname][it.name] = key
                new_ifaces.append(i)
            elif isinstance(it, N.Implements):
                new_impl.append(it)
            if isinstance(it, (N.ClassDef, N.InterfaceDef, N.FuncDef)) and getattr(it, "exported", False):
                exported.add(it.name)
        self.exports[modname] = exported
        for c in new_classes:
            p = c.node.parent
            if p is not None:
                if self.scope[modname].get(p) not in self.classes:
                    raise TomatoError("unknown parent class %r" % p, c.node.line)
                c.parent = self.classes[self.scope[modname][p]]
            for n in c.node.interfaces:
                if self.scope[modname].get(n) not in self.ifaces:
                    raise TomatoError("unknown interface %r" % n, c.node.line)
                c.ifaces.add(self.scope[modname][n])
        for i in new_ifaces:
            for n in i.node.parents:
                if self.scope[modname].get(n) not in self.ifaces:
                    raise TomatoError("unknown interface %r" % n, i.node.line)
                i.parents.append(self.scope[modname][n])
        for imp in new_impl:
            ck, ik = self.scope[modname].get(imp.cls), self.scope[modname].get(imp.iface)
            if ck not in self.classes:
                raise TomatoError("unknown class %r" % imp.cls, imp.line)
            if ik not in self.ifaces:
                raise TomatoError("unknown interface %r" % imp.iface, imp.line)
            self.extra_impl.append((ck, ik, imp.line))
        for c in new_classes:
            seen = set()
            for k in c.chain():
                if k.name in seen:
                    raise TomatoError("class %s inherits from itself" % c.name, c.node.line)
                seen.add(k.name)
        for i in new_ifaces:
            for m in i.node.methods:
                self.add_iface_method(i, m)
        for i in new_ifaces:
            self.iface_cycle_check(i, [])
        for i in new_ifaces:
            self.iface_requirements(i.name)
        for c in new_classes:
            self.collect_class(c)
        for it in items:
            if isinstance(it, N.LlvmDecl):
                self.declare_llvm(it)
        for it in items:
            if isinstance(it, N.FuncDef):
                self.declare_check(it.name, it.line)
                key = self.key_for(modname, it.name)
                self.funcs[key] = self.make_func(it, None)
                self.funcs[key].key = key
                self.scope[modname][it.name] = key
                new_funcs.append(self.funcs[key])
        for c in new_classes:
            self.check_class(c)
        for imp in [x for x in self.extra_impl if x[0] in {c.name for c in new_classes}]:
            self.check_implements(imp)
        for it in items:
            if not isinstance(it, (N.ClassDef, N.InterfaceDef, N.Implements, N.FuncDef, N.Import, N.LlvmDecl)):
                raise TomatoError("top-level code is not allowed: put it in a function marked @main (D16a)", it.line)
        if modname == "main":
            self.entries = {}
            for f in new_funcs:
                m = f.node.marker
                if m and m.startswith("entry:"):
                    name = m[6:]
                    if name in self.entries:
                        raise NotDecided("more than one function marked @%s" % name, f.node.line)
                    if f.ret != NoneT:
                        raise NotDecided("an entry point that returns a value (exit status)", f.node.line)
                    for k, t in enumerate(f.ptypes):
                        if k == f.star:
                            t = t.elem
                        elif k == f.kwstar:
                            t = t.value
                        if isinstance(t, UnionT) and all(m in (INT, FloatT, BoolT, StrT) for m in t.members):
                            continue
                        if not (is_int_type(t) or t in (FloatT, BoolT, StrT)):
                            raise NotDecided("an entry point parameter of type %r (inputs are int, float, bool and str)"
                                             % (t,), f.node.line)
                    self.entries[name] = f

    def make_func(self, node, owner):
        params = node.params[1:] if (node.params and node.params[0].name == "self") else node.params
        if owner is not None and node.params and node.params[0].name == "self" and node.params[0].type:
            raise TomatoError("self is written without a type (D12al)", node.line)
        ptypes = []
        for p in params:
            if p.name == "self":
                raise TomatoError("self must be the first parameter", node.line)
            if p.type is None:
                raise TomatoError("parameter %r needs a type (D04b)" % p.name, node.line)
            ptypes.append(self.resolve(p.type))
        fi = FuncInfo(node, owner, ptypes, self.resolve(node.ret) if node.ret else NoneT,
                      owner.module if owner is not None else self.cur_mod)
        fi.defaults = [p.default for p in params]         # default argument values, or None (D19c)
        fi.nfixed = sum(1 for p in params if not p.star)
        fi.min_args = sum(1 for p in params if not p.star and p.default is None)
        fi.star = fi.kwstar = None                        # indexes of the *args and **kwargs parameters (D39a)
        for k, p in enumerate(params):
            if p.star == "*":
                if not isinstance(ptypes[k], TupleT):
                    raise TomatoError("*%s must be typed tuple[T], found %r (D39a)" % (p.name, ptypes[k]), node.line)
                fi.star = k
            elif p.star == "**":
                if not (isinstance(ptypes[k], MapT) and ptypes[k].key == StrT):
                    raise TomatoError("**%s must be typed dict[str, V], found %r (D39a)" % (p.name, ptypes[k]), node.line)
                fi.kwstar = k
        return fi

    def add_iface_method(self, i, m):
        if not (m.params and m.params[0].name == "self"):
            raise NotDecided("interface members without self (class functions in interfaces)", m.line)
        if m.name in i.methods:
            raise TomatoError("method %s declared twice in %s" % (m.name, i.name), m.line)
        i.methods[m.name] = self.make_func(m, None)

    def iface_cycle_check(self, i, path):
        if i.name in path:
            raise TomatoError("interface inheritance cycle: %s" % " -> ".join(path + [i.name]), i.node.line)
        for p in i.parents:
            self.iface_cycle_check(self.ifaces[p], path + [i.name])

    def iface_closure(self, name):
        out, todo = set(), [name]
        while todo:
            n = todo.pop()
            if n not in out:
                out.add(n)
                todo.extend(self.ifaces[n].parents)
        return out

    def iface_requirements(self, name):
        req = {}
        for n in sorted(self.iface_closure(name)):
            for mn, f in self.ifaces[n].methods.items():
                if mn in req and req[mn].sig() != f.sig():
                    raise TomatoError("interfaces require %s with different signatures (D12bd)" % mn,
                                      self.ifaces[n].node.line)
                req[mn] = f
        return req

    def class_ifaces(self, cls):
        """All interface names a class counts as implementing, including inherited ones (D12bf)."""
        names = set()
        for c in cls.chain():
            names |= c.ifaces
            names |= {ik for ck, ik, _ in self.extra_impl if ck == c.name}
        out = set()
        for n in names:
            if n not in self.ifaces:
                raise TomatoError("unknown interface %r" % n)
            out |= self.iface_closure(n)
        return out

    def collect_class(self, c):
        names = set()
        for f in c.node.fields:
            if f.name in names:
                raise TomatoError("field %s declared twice" % f.name, f.line)
            names.add(f.name)
            t = self.resolve(f.type)
            c.fields[f.name] = (f, t)
        for m in c.node.methods:
            if m.name in c.methods or m.name in c.fields:
                raise TomatoError("%s is declared twice in %s" % (m.name, c.name), m.line)
            c.methods[m.name] = self.make_func(m, c)
        if c.parent:
            for fname in c.fields:
                if c.parent.find_field(fname)[0]:
                    raise NotDecided("redeclaring a parent's field in a subclass (%s)" % fname, c.node.line)

    def check_class(self, c):
        inits = [m for m in c.methods.values() if m.node.marker == "init"]
        if len(inits) > 1:
            raise TomatoError("class %s has more than one @init (D12aj)" % c.name, c.node.line)
        adds = [m for m in c.methods.values() if m.node.marker == "add"]
        if len(adds) > 1:
            raise NotDecided("more than one @add method in a class", c.node.line)
        for m in c.methods.values():
            n = m.node
            if n.marker in ("init", "add") and not m.has_self:
                raise TomatoError("@%s needs a method with self" % n.marker, n.line)
            if n.override:
                if n.marker == "init":
                    raise TomatoError("@init is never replaced (D12aw)", n.line)
                if n.marker == "add":
                    raise NotDecided("override combined with @add", n.line)
                if not m.has_self:
                    raise TomatoError("only instance methods can be replaced (D12aw)", n.line)
            if n.marker == "init":
                continue
            parent_m = c.parent.find_method(m.name) if c.parent else None
            if parent_m is not None and parent_m.has_self and m.has_self and parent_m.node.marker != "init":
                if not n.override:
                    raise TomatoError("%s.%s replaces a parent method and needs `override` (D12ar)"
                                      % (c.name, m.name), n.line)
                if parent_m.sig() != m.sig():
                    raise TomatoError("override %s must match the parent's types exactly (D12au)" % m.name, n.line)
            elif n.override:
                raise TomatoError("%s.%s is marked override but replaces nothing (D12ar)" % (c.name, m.name), n.line)
        if inits:
            self.check_init(c, inits[0])
        else:
            parent_init = c.parent.nearest("init") if c.parent else None
            if not parent_init:
                for k in c.chain():
                    for fname, (f, t) in k.fields.items():
                        if f.value is None and k is c:
                            raise TomatoError("class %s has no @init but field %s has no value (D12af)"
                                              % (c.name, fname), f.line)
        for i in self.class_ifaces(c):
            self.check_conforms(c, i, c.node.line)

    def check_init(self, c, init):
        n = init.node
        if len(init.ptypes) == 1:
            t = init.ptypes[0]
            bad = {k.name for k in c.chain()}
            if isinstance(t, ClassT) and t.name in bad:
                raise TomatoError("@init of %s takes one parameter that accepts its own or its parent's type: "
                                  "a call would be ambiguous with conversion (D12ba)" % c.name, n.line)
            if isinstance(t, IfaceT):
                impl = set()
                for k in c.chain():
                    impl |= self.class_ifaces(k)
                if t.name in impl:
                    raise TomatoError("@init of %s takes one interface-typed parameter that accepts the class "
                                      "or its parent (D12ba)" % c.name, n.line)
        if c.parent and c.parent.nearest("init"):
            first = n.body[0] if n.body else None
            ok = (isinstance(first, N.ExprStmt) and isinstance(first.expr, N.Call)
                  and isinstance(first.expr.func, N.Attr) and isinstance(first.expr.func.obj, N.Name)
                  and first.expr.func.obj.name == c.node.parent and first.expr.args
                  and isinstance(first.expr.args[0], N.Name) and first.expr.args[0].name == "self")
            if not ok:
                raise TomatoError("a subclass @init must start by calling the parent's @init, e.g. "
                                  "%s.start(self, ...) (D12ag, D12ap)" % c.node.parent, n.line)
            calls = self.count_calls(n.body[1:], c.node.parent)
            if calls:
                raise TomatoError("the parent's @init must be called exactly once (D12ag)", n.line)
        required = {fname for fname, (f, t) in c.fields.items() if f.value is None}
        done = self.init_flow(n.body, set(), required, c, n)
        if done is not None and required - done:
            raise TomatoError("@init of %s does not set field %s on every path (D12x)"
                              % (c.name, sorted(required - done)[0]), n.line)

    def init_flow(self, stmts, assigned, required, c, init_node):
        """Which required fields are surely set when these statements finish; None when they always return.

        P16: the exact D12x rules are open, so this is conservative. A field set only inside a loop does not
        count (the loop may not run), and an `if` counts only when every branch, including an `else`, sets it.
        """
        for st in stmts:
            if isinstance(st, N.Assign) and isinstance(st.target, N.Attr) and isinstance(st.target.obj, N.Name) \
                    and st.target.obj.name == "self":
                assigned = assigned | {st.target.name}
            elif isinstance(st, N.Return):
                if required - assigned:
                    raise TomatoError("@init of %s returns before setting field %s (D12x)"
                                      % (c.name, sorted(required - assigned)[0]), st.line)
                return None
            elif isinstance(st, N.If):
                results = [self.init_flow(body, assigned, required, c, init_node) for _, body in st.branches]
                results.append(self.init_flow(st.orelse, assigned, required, c, init_node) if st.orelse else assigned)
                live = [r for r in results if r is not None]
                if not live:
                    return None
                assigned = set.intersection(*live)
            elif isinstance(st, (N.While, N.For)):
                self.init_flow(st.body, assigned, required, c, init_node)
        return assigned

    def count_calls(self, stmts, parent):
        found = 0
        for s in stmts:
            for e in self.walk(s):
                if isinstance(e, N.Call) and isinstance(e.func, N.Attr) and isinstance(e.func.obj, N.Name) \
                        and e.func.obj.name == parent and e.args and isinstance(e.args[0], N.Name) \
                        and e.args[0].name == "self":
                    found += 1
        return found

    def walk(self, x):
        if isinstance(x, N.Node):
            yield x
            for f in x._fields:
                yield from self.walk(getattr(x, f))
        elif isinstance(x, (list, tuple)):
            for y in x:
                yield from self.walk(y)

    def check_conforms(self, c, iface, line):
        for mn, req in self.iface_requirements(iface).items():
            m = c.find_method(mn)
            if m is None or not m.has_self:
                raise TomatoError("class %s lacks method %s required by %s (D12g)" % (c.name, mn, iface), line)
            if m.sig() != req.sig():
                raise TomatoError("%s.%s does not match %s's types exactly (D12bg)" % (c.name, mn, iface), line)

    def check_implements(self, imp):
        ck, ik, line = imp
        if sum(1 for x in self.extra_impl if x[:2] == (ck, ik)) > 1:
            raise NotDecided("duplicate implements declarations", line)
        self.check_conforms(self.classes[ck], ik, line)

    # ---------------------------------------------------------- conversion
    def is_subclass(self, cls, name):
        return any(k.name == name for k in cls.chain())

    def implements(self, cls, iface):
        return iface in self.class_ifaces(cls)

    def fits(self, v, t):
        if isinstance(t, ClassT):
            return isinstance(v, Instance) and self.is_subclass(v.cls, t.name)
        if isinstance(t, IfaceT):
            return isinstance(v, Instance) and self.implements(v.cls, t.name)
        return False

    def convert(self, v, t, line=None, what="value"):
        """Implicit conversion of an already-typed value to type t (D05o, D12ay, D12bb)."""
        if isinstance(t, OptT):
            return None if v is None else self.convert(v, t.inner, line, what)
        if isinstance(t, InterT):                     # the value must be every member (D23h)
            if all(self.fits(v, m) for m in t.members):
                return v
            raise TomatoError("%s of type %r does not fit %r" % (what, value_type(v), t), line)
        if isinstance(t, UnionT):                     # the first member that accepts the value (D23g)
            for m in t.members:
                try:
                    return self.convert(v, m, line, what)
                except (TomatoError, RunFailure):
                    continue
            raise TomatoError("%s of type %r does not fit %r" % (what, value_type(v), t), line)
        if v is None and t != NoneT:
            raise RunFailure("None where a %r is needed (D23b): check for None first" % (t,), line)
        if isinstance(t, IntT):
            if isinstance(v, FixedInt):
                return v.n
            if is_int_value(v):
                return v
        elif isinstance(t, FixedT):
            if isinstance(v, FixedInt):
                if contains(t, v.t):
                    return FixedInt(v.n, t)
            elif is_int_value(v):
                raise TomatoError("%r cannot be used as %r without an explicit conversion (D05o)"
                                  % (what, t), line)
        elif isinstance(t, (ClassT, IfaceT)):
            if self.fits(v, t):
                return v
        elif value_type(v) == t:
            return v
        if t == NoneT:
            raise TomatoError("%s of type %r where None is expected: declare it as %r | None (D23b)"
                              % (what, value_type(v), value_type(v)), line)
        raise TomatoError("%s of type %r does not fit %r" % (what, value_type(v), t), line)

    def explicit_int(self, v, t, line):
        if not is_int_value(v):
            raise TomatoError("only integers convert this way, found %r" % value_type(v), line)
        n = int_value(v)
        if isinstance(t, IntT):
            return n
        lo, hi = t.range()
        if not lo <= n <= hi:
            raise RunFailure("%d is out of range for %r (D05p)" % (n, t), line)
        return FixedInt(n, t)

    # ---------------------------------------------------------- running
    def check(self, src):
        """Load and check a program without running it (declarations, interfaces, overrides, @init rules)."""
        self.load(parse(self.module_source("builtin", None)), "builtin")
        self.load(parse(src), "main")
        self.find_reference_cycles()

    def find_reference_cycles(self):
        """Best-effort compile-time warning (D29b): classes that refer to each other through their fields form a
        reference cycle, which reference counting would never free. A class referring to itself (a linked list or a
        tree) is not reported, since that is usually not a cycle of objects."""
        def classes_in(t):
            if isinstance(t, ClassT):
                return {t.name}
            if isinstance(t, IfaceT):
                return {c.name for c in self.classes.values() if t.name in self.class_ifaces(c)}
            if isinstance(t, ListT):
                return classes_in(t.elem)
            if isinstance(t, SetT):
                return classes_in(t.elem)
            if isinstance(t, MapT):
                return classes_in(t.key) | classes_in(t.value)
            return set()
        edges = {}
        for c in self.classes.values():
            out = {}
            for k in c.chain():
                for fname, (f, t) in k.fields.items():
                    for target in classes_in(t):
                        out.setdefault(target, (k.name, fname))
            edges[c.name] = out
        index, low, stack, on, comps, counter = {}, {}, [], set(), [], [0]

        def visit(v):
            index[v] = low[v] = counter[0]
            counter[0] += 1
            stack.append(v)
            on.add(v)
            for w in edges.get(v, ()):
                if w not in index:
                    visit(w)
                    low[v] = min(low[v], low[w])
                elif w in on:
                    low[v] = min(low[v], index[w])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on.discard(w)
                    comp.append(w)
                    if w == v:
                        break
                comps.append(comp)

        for v in sorted(edges):
            if v not in index:
                visit(v)
        for comp in comps:
            if len(comp) < 2 or all(self.classes[n].module == "builtin" for n in comp):
                continue
            names = sorted(comp)
            via = []
            for a in names:
                for b, (owner, fname) in sorted(edges[a].items()):
                    if b in comp and b != a:
                        via.append("%s.%s -> %s" % (owner, fname, b))
            line = min(self.classes[n].node.line for n in names)
            text = ("classes %s refer to each other (%s): compiled programs free such reference cycles with the "
                    "runtime's cycle collector, which costs some time (D29d)" % (", ".join(names), "; ".join(via)))
            self.warnings.append((line, text))
            print("warning: line %d: %s" % (line, text), file=self.warn_out or sys.stderr)

    def parse_input(self, text, t, position, name, line):
        """Turn one command-line input into a value of the entry point's parameter type (D28a, P34)."""
        def bad(what):
            raise TomatoError("input %d (%s) must be %s, found %r" % (position, name, what, text), line)
        if isinstance(t, UnionT):                        # the most restrictive member that fits (D28b)
            for m in (INT, FloatT, BoolT, StrT):
                if m in t.members:
                    try:
                        return self.parse_input(text, m, position, name, line)
                    except TomatoError:
                        continue
            bad("one of " + repr(t))
        if t == StrT:
            return text
        if t == BoolT:
            if text not in ("true", "false", "True", "False"):
                bad("true or false")
            return text in ("true", "True")
        if t == FloatT:
            try:
                v = float(text)
            except ValueError:
                bad("a number")
            if v != v or v in (float("inf"), float("-inf")):
                bad("a finite number")
            return v
        body = text[1:] if text[:1] in "+-" else text
        if not (body.isascii() and body.isdigit()):
            bad("a whole number")
        n = int(text)
        if isinstance(t, FixedT):
            lo, hi = t.range()
            if not lo <= n <= hi:
                raise TomatoError("input %d (%s) %d does not fit %r" % (position, name, n, t), line)
            return FixedInt(n, t)
        return n

    def run(self, src, entry="main", inputs=None):
        self.load(parse(self.module_source("builtin", None)), "builtin")
        self.load(parse(src), "main")
        self.find_reference_cycles()
        self.check_llvm_against_ir()
        fn = self.entries.get(entry)
        if fn is None:
            raise TomatoError("no function marked @%s: a program starts at its entry point, "
                              "@main unless another is chosen (D16a)" % entry)
        inputs = inputs or []
        names = [p.name for p in fn.node.params if p.name != "self" and not p.star]
        nfix = fn.nfixed
        # `name=value` inputs go to the parameter of that name, or into **kwargs (D39a)
        positional, keyed = [], []
        for x in inputs:
            key, eq, val = x.partition("=")
            if eq and key.isidentifier() and (key in names or fn.kwstar is not None):
                keyed.append((key, val))
            else:
                positional.append(x)
        lo = fn.min_args
        if len(positional) > nfix and fn.star is None:
            raise TomatoError("entry point @%s takes %d input(s)%s, got %d"
                              % (entry, nfix, " (" + ", ".join(names) + ")" if names else "", len(positional)))
        args = [self.parse_input(x, t, k + 1, n, fn.node.line)
                for k, (x, t, n) in enumerate(zip(positional[:nfix], fn.ptypes, names))]
        for key, val in keyed:
            if key in names:
                k = names.index(key)
                if k < len(args):
                    raise TomatoError("input %s is given twice" % key, fn.node.line)
                while len(args) < k:
                    if fn.defaults[len(args)] is None:
                        raise TomatoError("entry point @%s is missing the input %s" % (entry, names[len(args)]), fn.node.line)
                    args.append(self.eval(fn.defaults[len(args)], Frame(), fn.ptypes[len(args)]))
                args.append(self.parse_input(val, fn.ptypes[k], k + 1, key, fn.node.line))
        if len(args) < lo:
            raise TomatoError("entry point @%s takes %d input(s)%s, got %d"
                              % (entry, nfix, " (" + ", ".join(names) + ")" if names else "", len(args)))
        while len(args) < nfix:
            self.fill_default_values_one(fn, args)
        if fn.star is not None:
            et = fn.ptypes[fn.star].elem
            args.append(TTuple(et, [self.parse_input(x, et, nfix + 1 + k, fn.node.params[fn.star].name, fn.node.line)
                                    for k, x in enumerate(positional[nfix:])]))
        if fn.kwstar is not None:
            vt = fn.ptypes[fn.kwstar].value
            m = TMap(StrT, vt)
            for key, val in keyed:
                if key not in names:
                    m.items[key_of(key)] = [key, self.parse_input(val, vt, 0, key, fn.node.line)]
            args.append(m)
        self.fill_default_values(fn, args)
        try:
            self.invoke(fn, args, fn.node.line)
        except TomatoRaise as r:
            raise TomatoError("uncaught error %s: %s" % (r.value.cls.name, r.value.fields.get("message", "")),
                              r.line)

    def exec_block(self, stmts, fr):
        for s in stmts:
            self.exec_stmt(s, fr)

    def lookup(self, name, fr, line):
        if name in fr.vars:
            return fr.vars[name]
        if fr is not self.globals and name in self.globals.vars:
            return self.globals.vars[name]
        raise TomatoError("unknown name %r" % name, line)

    def exec_stmt(self, s, fr):
        try:
            self.exec_stmt_inner(s, fr)
        except TomatoError as e:
            if e.line is None:  # errors raised from values (such as overflow) do not know their line
                e.line = s.line
                e.args = ("line %d: %s" % (s.line, e.message),)
            raise

    def exec_stmt_inner(self, s, fr):
        if isinstance(s, N.ExprStmt):
            self.eval(s.expr, fr)
        elif isinstance(s, N.Pass):
            pass
        elif isinstance(s, N.Declare):
            t = self.resolve(s.type)
            if s.name in fr.vars:
                raise NotDecided("declaring a name twice", s.line)
            fr.vars[s.name] = [t, self.convert(self.eval(s.value, fr, t), t, s.line, "initial value")]
        elif isinstance(s, N.Assign):
            self.assign(s, fr)
        elif isinstance(s, N.Return):
            raise Return(self.eval(s.value, fr, fr.ret_type if hasattr(fr, "ret_type") else None)
                         if s.value is not None else None)
        elif isinstance(s, N.If):
            for cond, body in s.branches:
                if self.truth(self.eval(cond, fr), s.line):
                    self.exec_block(body, fr)
                    return
            if s.orelse:
                self.exec_block(s.orelse, fr)
        elif isinstance(s, N.For):
            it = self.eval(s.iter, fr)
            if isinstance(it, TList):
                # PROVISIONAL: the loop sees items appended while it runs (index-based, like Python)
                elem, items = it.elem, it.items
                k = 0
                while k < len(items):
                    self.bind_loop_var(s, fr, elem, items[k])
                    if self.loop_body(s.body, fr):
                        break
                    k += 1
                return
            if isinstance(it, TMap):
                # PROVISIONAL: a loop over a map or set walks a snapshot, so changing it inside the loop is allowed
                for key, _ in list(it.items.values()):
                    self.bind_loop_var(s, fr, it.ktype, key)
                    if self.loop_body(s.body, fr):
                        break
                return
            if isinstance(it, TSet):
                for el in list(it.items.values()):
                    self.bind_loop_var(s, fr, it.etype, el)
                    if self.loop_body(s.body, fr):
                        break
                return
            if not isinstance(it, RangeObj):
                raise NotDecided("for over %r (range and lists are built in; the iteration protocol for classes is open)"
                                 % value_type(it), s.line)
            for n in it:
                self.bind_loop_var(s, fr, INT, n)
                if self.loop_body(s.body, fr):
                    break
        elif isinstance(s, N.While):
            while self.truth(self.eval(s.cond, fr), s.line):
                if self.loop_body(s.body, fr):
                    break
        elif isinstance(s, N.Break):
            raise BreakLoop()
        elif isinstance(s, N.Continue):
            raise ContinueLoop()
        elif isinstance(s, N.Raise):
            v = self.eval(s.value, fr)
            if not (isinstance(v, Instance) and self.is_subclass(v.cls, "Error")):
                raise TomatoError("raise needs an Error object, found %r" % value_type(v), s.line)
            raise TomatoRaise(v, s.line)
        elif isinstance(s, N.Try):
            self.exec_try(s, fr)
        else:
            raise TomatoError("cannot run %s" % type(s).__name__, s.line)

    def loop_body(self, body, fr):
        """Run one pass of a loop; True when the loop should stop (break)."""
        try:
            self.exec_block(body, fr)
        except ContinueLoop:
            pass
        except BreakLoop:
            return True
        return False

    def make_error(self, kind, message):
        inst = Instance(self.classes[kind])
        inst.fields["message"] = message
        return inst

    def exec_try(self, s, fr):
        try:
            try:
                self.exec_block(s.body, fr)
            except (TomatoRaise, RunFailure) as exc:
                val = exc.value if isinstance(exc, TomatoRaise) else self.make_error(exc.kind, exc.message)
                for cname, var, body in s.handlers:
                    cinfo = self.vis_class(cname)
                    if cinfo is None or not self.is_subclass(cinfo, "Error"):
                        raise TomatoError("catch needs an error class (a subclass of Error), found %r" % cname, s.line)
                    if self.is_subclass(val.cls, cinfo.name):
                        if var:
                            fr.vars[var] = [ClassT(cinfo.name), val]
                        self.exec_block(body, fr)
                        break
                else:
                    raise
            else:
                if s.orelse:
                    self.exec_block(s.orelse, fr)
        finally:
            if s.final:
                self.exec_block(s.final, fr)

    def bind_loop_var(self, s, fr, t, value):
        if s.var in fr.vars:
            if fr.vars[s.var][0] != t:
                raise TomatoError("loop variable %s already has type %r" % (s.var, fr.vars[s.var][0]), s.line)
            fr.vars[s.var][1] = value
        else:
            fr.vars[s.var] = [t, value]

    def truth(self, v, line):
        if not isinstance(v, bool):
            raise TomatoError("a condition must be a bool, found %r (truthiness is not yet decided)"
                              % value_type(v), line)
        return v

    def assign(self, s, fr):
        tgt = s.target
        if isinstance(tgt, N.Name):
            cur = None
            if tgt.name in fr.vars:
                cur = fr.vars[tgt.name]
            elif fr is not self.globals and tgt.name in self.globals.vars:
                raise NotDecided("assigning to a module variable from inside a function", s.line)
            if cur is None:
                v = self.eval(s.value, fr)
                st = self.static_type(s.value, fr)
                # a variable copied from an optional stays optional, whatever it holds right now (D23b)
                fr.vars[tgt.name] = [st if isinstance(st, (OptT, UnionT, InterT)) else value_type(v), v]
            else:
                cur[1] = self.convert(self.eval(s.value, fr, cur[0]), cur[0], s.line, "assigned value")
            return
        if isinstance(tgt, N.Index):
            lst = self.eval(tgt.obj, fr)
            if isinstance(lst, TMap):
                key = self.map_key(lst, tgt.index, fr, s.line)
                val = self.convert(self.eval(s.value, fr, lst.vtype), lst.vtype, s.line, "dict value")
                lst.items[key_of(key)] = [key, val]
                return
            if isinstance(lst, TTuple):
                raise TomatoError("a tuple cannot be changed (D39a)", s.line)
            if not isinstance(lst, TList):
                raise TomatoError("only list items can be assigned by index (strings cannot be changed in place)", s.line)
            i = self.list_index(lst, tgt, fr)
            lst.items[i] = self.convert(self.eval(s.value, fr, lst.elem), lst.elem, s.line, "assigned item")
            return
        self.declared_member_check(tgt.obj, tgt.name, False, fr, s.line)
        obj = self.eval(tgt.obj, fr)
        if not isinstance(obj, Instance):
            raise TomatoError("only instances have fields", s.line)
        owner, entry = obj.cls.find_field(tgt.name)
        if entry is None:
            raise TomatoError("%s has no field %s (D12u)" % (obj.cls.name, tgt.name), s.line)
        f, t = entry
        self.check_access(f.private, owner, fr, "field " + tgt.name, s.line)
        if f.const:
            if not fr.in_init:
                raise TomatoError("const field %s cannot change after initialization (D12o)" % tgt.name, s.line)
            if f.value is not None:
                raise NotDecided("writing a const field that also has a declared value", s.line)
            if tgt.name in obj.const_set:
                raise TomatoError("const field %s is already set (D12z)" % tgt.name, s.line)
            obj.const_set.add(tgt.name)
        obj.fields[tgt.name] = self.convert(self.eval(s.value, fr, t), t, s.line, "assigned value")

    def check_access(self, private, owner, fr, what, line):
        if private and (fr.owner is None or fr.owner is not owner):
            raise TomatoError("%s is private to class %s (D12ac, D12r)" % (what, owner.name), line)

    # ---------------------------------------------------------- expressions
    def literal_only(self, e):
        if isinstance(e, N.IntLit):
            return True
        if isinstance(e, N.UnOp) and e.op == "-":
            return self.literal_only(e.operand)
        return isinstance(e, N.BinOp) and e.op in ("+", "-", "*") and \
            self.literal_only(e.left) and self.literal_only(e.right)

    def make_int(self, n, t, line, run=False):
        if isinstance(t, FixedT):
            lo, hi = t.range()
            if not lo <= n <= hi:
                raise (RunFailure if run else TomatoError)("%d does not fit %r (D05r, D05x)" % (n, t), line)
            return FixedInt(n, t)
        return n

    def eval(self, e, fr, expected=None):
        if isinstance(e, N.Name) and e.name == "None" and e.name not in fr.vars and expected is not None \
                and expected != NoneT and not isinstance(expected, OptT) \
                and not (isinstance(expected, UnionT) and NoneT in expected.members):
            raise TomatoError("type error: None where %r is expected; write the type as %r | None (D23b)"
                              % (expected, expected), e.line)
        if isinstance(e, N.IntLit):
            return self.make_int(e.value, expected if is_int_type(expected) else INT, e.line)
        if isinstance(e, N.StrLit):
            return e.value
        if isinstance(e, N.ListLit):
            return self.list_literal(e, fr, expected)
        if isinstance(e, N.MapLit):
            return self.map_literal(e, fr, expected)
        if isinstance(e, N.SetLit):
            return self.set_literal(e, fr, expected)
        if isinstance(e, N.LlvmRef):
            return self.llvm_ref(e)
        if isinstance(e, N.BoolLit):
            return e.value
        if isinstance(e, N.Name):
            return self.name_value(e, fr)
        if isinstance(e, N.UnOp):
            return self.unop(e, fr, expected)
        if isinstance(e, N.BinOp):
            return self.binop(e, fr, expected)
        if isinstance(e, N.TypeCall):
            t = self.resolve(e.type)
            return self.explicit_int(self.eval(e.args[0], fr), t, e.line)
        if isinstance(e, N.Call):
            return self.call(e, fr)
        if isinstance(e, N.Attr):
            return self.attr(e, fr)
        if isinstance(e, N.Index):
            return self.index(e, fr)
        if isinstance(e, N.Slice):
            return self.slice(e, fr)
        raise TomatoError("cannot evaluate %s" % type(e).__name__, e.line)

    def name_value(self, e, fr):
        n = e.name
        if n == "None" and n not in fr.vars:
            return None
        if n in fr.vars:
            return fr.vars[n][1]
        if fr is not self.globals and n in self.globals.vars:
            return self.globals.vars[n][1]
        if self.vis_name(n) or n in ("print", "int", "rational", "range", "len", "str", "open"):
            return ("ref", n)
        raise TomatoError("unknown name %r" % n, e.line)

    def unop(self, e, fr, expected):
        if e.op == "not":
            return not self.truth(self.eval(e.operand, fr), e.line)
        if isinstance(e.operand, N.IntLit) and is_int_type(expected):
            return self.make_int(-e.operand.value, expected, e.line)  # a negative literal (D05r)
        v = self.eval(e.operand, fr, expected)
        if isinstance(v, FixedInt):
            return FixedInt(-v.n, v.t)
        if is_int_value(v):
            return -v
        raise NotDecided("negating %r" % value_type(v), e.line)

    def binop(self, e, fr, expected):
        op = e.op
        if op in ("and", "or"):
            a = self.truth(self.eval(e.left, fr), e.line)
            if (op == "and") != a:
                return a
            return self.truth(self.eval(e.right, fr), e.line)
        if op == "xor":                              # both sides are always evaluated (D23h)
            a = self.truth(self.eval(e.left, fr), e.line)
            return a != self.truth(self.eval(e.right, fr), e.line)
        if op in ("&", "|", "^"):
            a, b = self.eval(e.left, fr), self.eval(e.right, fr)
            return self.bitwise(op, a, b, e.line)
        if op in ("+", "-", "*"):
            if self.literal_only(e) and is_int_type(expected):
                a, b = self.eval(e.left, fr, expected), self.eval(e.right, fr, expected)
                return self.arith(op, a, b, e.line)
            ll, rl = self.literal_only(e.left), self.literal_only(e.right)
            if ll and not rl:
                b = self.eval(e.right, fr)
                a = self.eval(e.left, fr, value_type(b) if is_int_value(b) else None)
            elif rl and not ll:
                a = self.eval(e.left, fr)
                b = self.eval(e.right, fr, value_type(a) if is_int_value(a) else None)
            else:
                a, b = self.eval(e.left, fr), self.eval(e.right, fr)
            return self.arith(op, a, b, e.line)
        if op == "in":
            t = self.type_expr(e.right, fr)
            if t is not None:                              # `x in Type`: a type test (D23e, D23f)
                return self.type_match(self.eval(e.left, fr), t)
        a, b = self.eval(e.left, fr), self.eval(e.right, fr)
        if op in ("is", "is not"):
            if a is None or b is None:
                same = a is b
            elif isinstance(a, Instance) and isinstance(b, Instance):
                same = a is b
            else:
                raise NotDecided("`is` with %r and %r (only None and objects are decided)" % (value_type(a), value_type(b)), e.line)
            return same if op == "is" else not same
        if op == "in":
            if isinstance(a, str) and isinstance(b, str):
                return a in b
            if isinstance(b, TMap) or isinstance(b, TSet):
                kt = b.ktype if isinstance(b, TMap) else b.etype
                if not (value_type(a) == kt or (is_int_value(a) and is_int_type(kt))):
                    raise TomatoError("type error: cannot look for %r in %r" % (value_type(a), value_type(b)), e.line)
                return key_of(a) in b.items
            if isinstance(b, TList):
                if value_type(a) != b.elem and not (is_int_value(a) and is_int_type(b.elem)):
                    raise TomatoError("type error: cannot look for %r in %r" % (value_type(a), value_type(b)), e.line)
                return any(self.compare("==", a, x, e.line) for x in b.items)
            if isinstance(a, str) or isinstance(b, str):
                raise TomatoError("type error: cannot use in with %r and %r" % (value_type(a), value_type(b)), e.line)
            raise NotDecided("in with %r and %r (only text in text is decided)" % (value_type(a), value_type(b)), e.line)
        if op == "/":
            return self.divide(a, b, e.line)
        if op == "%":
            return self.modulo(a, b, e.line)
        return self.compare(op, a, b, e.line)

    def clash(self, op, a, b, line):
        """A known type mismatch is a type error (D04a); mixed numeric kinds stay undecided."""
        ta, tb = value_type(a), value_type(b)
        if is_int_value(a) and is_int_value(b):
            return
        if ta == tb:
            return
        numeric = lambda v: is_int_value(v) or isinstance(v, (float, Rational))  # noqa: E731
        if numeric(a) and numeric(b):
            return
        if isinstance(a, Instance) and isinstance(b, Instance):
            return
        raise TomatoError("type error: cannot use %s with %r and %r" % (op, ta, tb), line)

    def arith(self, op, a, b, line):
        if isinstance(a, Instance):
            if op != "+":
                raise NotDecided("operators other than + on instances", line)
            m = a.cls.nearest("add")
            if m is None:
                raise TomatoError("%s has no @add method" % a.cls.name, line)
            return self.invoke(m, [b], line, self_obj=a)
        self.clash(op, a, b, line)
        if isinstance(a, str) and isinstance(b, str) and op == "+":
            return a + b
        if isinstance(a, Rational) and isinstance(b, Rational) and op == "+":
            r = Rational(1, 1)
            r.f = a.f + b.f
            return r
        if not (is_int_value(a) and is_int_value(b)):
            raise NotDecided("%s on %r and %r (only integer + - * and exact rational + are decided)"
                             % (op, value_type(a), value_type(b)), line)
        ta, tb = value_type(a), value_type(b)
        if ta == tb:
            t = ta
        elif contains(ta, tb):
            t = ta
        elif contains(tb, ta):
            t = tb
        else:
            raise TomatoError("no common integer type for %r and %r (D05s)" % (ta, tb), line)
        x, y = int_value(a), int_value(b)
        r = x + y if op == "+" else x - y if op == "-" else x * y
        return self.make_int(r, t, line, True) if isinstance(t, FixedT) else r

    def bitwise(self, op, a, b, line):
        """`&`, `|` and `^` on whole numbers (D23h): two's-complement bits, the result in the wider operand's type."""
        self.clash(op, a, b, line)
        if not (is_int_value(a) and is_int_value(b)):
            raise NotDecided("%s on %r and %r (only whole numbers are decided)" % (op, value_type(a), value_type(b)), line)
        ta, tb = value_type(a), value_type(b)
        if ta == tb or contains(ta, tb):
            t = ta
        elif contains(tb, ta):
            t = tb
        else:
            raise TomatoError("no common integer type for %r and %r (D05s)" % (ta, tb), line)
        x, y = int_value(a), int_value(b)
        r = x & y if op == "&" else x | y if op == "|" else x ^ y
        return self.make_int(r, t, line, True) if isinstance(t, FixedT) else r

    def divide(self, a, b, line):
        self.clash("/", a, b, line)
        if not (is_int_value(a) and is_int_value(b)):
            raise NotDecided("/ on %r and %r (only integer / integer is decided)"
                             % (value_type(a), value_type(b)), line)
        x, y = int_value(a), int_value(b)
        if y == 0:
            raise RunFailure("division by zero (D05ab)", line)
        if x == 0:
            return 0.0 if y > 0 else -0.0  # integer zero counts as positive, so the divisor's sign decides (D05ai)
        try:
            return x / y
        except OverflowError:
            raise RunFailure("division result overflows float (D05af)", line)

    def modulo(self, a, b, line):
        self.clash("%", a, b, line)
        if not (is_int_value(a) and is_int_value(b)):
            raise NotDecided("% on non-integers", line)
        y = int_value(b)
        if y == 0:
            raise RunFailure("modulo by zero", line)
        # PROVISIONAL: remainder takes the divisor's sign (Python-style); result type as D05s.
        ta, tb = value_type(a), value_type(b)
        t = ta if contains(ta, tb) else tb if contains(tb, ta) else None
        if t is None:
            raise TomatoError("no common integer type for %r and %r" % (ta, tb), line)
        r = int_value(a) % y
        return self.make_int(r, t, line, True) if isinstance(t, FixedT) else r

    def compare(self, op, a, b, line):
        if op in ("==", "!=") and (a is None or b is None):
            return (a is b) == (op == "==")  # PROVISIONAL (D23a): None equals only None
        self.clash(op, a, b, line)
        if is_int_value(a) and is_int_value(b):
            x, y = int_value(a), int_value(b)
        elif type(a) == type(b) and isinstance(a, (float, str, bool)):
            x, y = a, b
        elif op in ("==", "!="):
            x, y = a, b
            if isinstance(a, Rational) and isinstance(b, Rational):
                x, y = a.f, b.f
            elif isinstance(a, (TList, TMap, TSet)) or isinstance(b, (TList, TMap, TSet)):
                raise NotDecided("comparing lists, dicts or sets (equality is open)", line)
            elif isinstance(a, (Instance,)) or isinstance(b, Instance):
                x, y = (a is b), True
            elif value_type(a) != value_type(b):
                raise NotDecided("comparing %r with %r" % (value_type(a), value_type(b)), line)
        else:
            raise NotDecided("ordering %r and %r" % (value_type(a), value_type(b)), line)
        if op == "==":
            return x == y
        if op == "!=":
            return x != y
        if isinstance(a, bool):
            raise NotDecided("ordering bools", line)
        return x < y if op == "<" else x <= y if op == "<=" else x > y if op == ">" else x >= y

    # ---------------------------------------------------------- strings (D17b-c; operations are placeholders)
    def int_arg(self, v, what, line):
        if not is_int_value(v):
            raise TomatoError("%s must be an integer, found %r" % (what, value_type(v)), line)
        return int_value(v)

    def declare_llvm(self, d):
        """`!name(a: T, b: U) -> R` states the Tomato types of an LLVM function (D27b). LLVM names are global."""
        from .llvm_bridge import tomato_to_llvm
        ptypes = []
        for p in d.params:
            if p.type is None:
                raise TomatoError("parameter %r of !%s needs a type" % (p.name, d.name), d.line)
            ptypes.append(self.resolve(p.type))
        ret = self.resolve(d.ret) if d.ret else NoneT
        for t in ptypes + [ret]:
            if tomato_to_llvm(t) is None:
                raise NotDecided("type %r in !%s (only int, int[length=N] and uint[length=N] up to 64 bits, float, "
                                 "bool and no value cross to LLVM)" % (t, d.name), d.line)
        if d.name in self.llvm_decls and self.llvm_decls[d.name] != (ptypes, ret):
            raise TomatoError("!%s is declared twice with different types" % d.name, d.line)
        self.llvm_decls[d.name] = (ptypes, ret)

    def check_llvm_against_ir(self):
        """When IR is attached, every declared function that the IR defines must have the declared types."""
        from .llvm_bridge import tomato_to_llvm
        if self.llvm is None:
            return
        for name, (ptypes, ret) in self.llvm_decls.items():
            if self.llvm.has(name):
                want = (tomato_to_llvm(ret), [tomato_to_llvm(t) for t in ptypes])
                got = self.llvm.sigs[name]
                if want != got:
                    raise TomatoError("!%s is declared (%s) -> %s but the LLVM IR defines (%s) -> %s"
                                      % (name, ", ".join(want[1]), want[0], ", ".join(got[1]), got[0]))

    def llvm_call(self, ref, args_nodes, fr, line):
        decl = self.llvm_decls.get(ref.name)
        if decl is None:
            raise TomatoError("!%s is not declared: add `!%s(a: T) -> R` at the top level (D27b)" % (ref.name, ref.name), line)
        ptypes, ret = decl
        if len(args_nodes) != len(ptypes):
            raise TomatoError("!%s takes %d argument(s), got %d" % (ref.name, len(ptypes), len(args_nodes)), line)
        args = [self.convert(self.eval(a, fr, t), t, line, "argument") for a, t in zip(args_nodes, ptypes)]
        if self.llvm is None:
            raise NotDecided("!%s is an LLVM function; no LLVM IR is attached (use --llvm FILE.ll, D27a)" % ref.name, line)
        if not self.llvm.has(ref.name):
            raise TomatoError("no LLVM function named %s in the attached IR" % ref.name, line)
        call_args = [self.to_llvm(a, t, ref.name, line) for a, t in zip(args, ptypes)]
        return self.from_llvm(self.llvm.function(ref.name)(*call_args), ret)

    def to_llvm(self, v, t, name, line):
        """Pass a value of declared Tomato type `t` to LLVM; LLVM integers have no sign, so use two's complement."""
        if t in (BoolT, FloatT):
            return v
        n = int_value(v)
        bits = 64 if isinstance(t, IntT) else t.bits
        signed = isinstance(t, IntT) or t.signed
        lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
        if not lo <= n <= hi:
            raise RunFailure("%d does not fit LLVM i%d" % (n, bits), line)
        return n - (1 << bits) if n >= (1 << (bits - 1)) else n

    def from_llvm(self, result, ret):
        """Give an LLVM result the declared Tomato type (LLVM integers have no sign: the declaration decides)."""
        if ret == NoneT:
            return None
        if ret in (BoolT, FloatT):
            return result
        if isinstance(ret, FixedT):
            return FixedInt(result & ((1 << ret.bits) - 1) if not ret.signed else result, ret)
        return result

    def llvm_ref(self, e):
        raise NotDecided("!%s is an LLVM function; this interpreter has no LLVM attached (D27a)" % e.name, e.line)

    def map_literal(self, e, fr, expected):
        if isinstance(expected, SetT) and not e.pairs:
            return TSet(expected.elem)
        if isinstance(expected, MapT):
            kt, vt = expected.key, expected.value
        elif not e.pairs:
            raise NotDecided("the type of an empty {} without a declared type (name it: m: dict[str, int] = {})", e.line)
        else:
            kt, vt = value_type(self.eval(e.pairs[0][0], fr)), value_type(self.eval(e.pairs[0][1], fr))
            if not (is_int_type(kt) or kt in (StrT, BoolT)):
                raise NotDecided("dict keys of type %r" % (kt,), e.line)
        m = TMap(kt, vt)
        for k, v in e.pairs:
            key = self.convert(self.eval(k, fr, kt), kt, e.line, "dict key")
            if key_of(key) in m.items:
                raise TomatoError("duplicate key %s in a dict literal" % show(key), e.line)
            m.items[key_of(key)] = [key, self.convert(self.eval(v, fr, vt), vt, e.line, "dict value")]
        return m

    def set_literal(self, e, fr, expected):
        if isinstance(expected, SetT):
            et = expected.elem
        else:
            et = value_type(self.eval(e.items[0], fr))
            if not (is_int_type(et) or et in (StrT, BoolT)):
                raise NotDecided("set elements of type %r" % (et,), e.line)
        st = TSet(et)
        for x in e.items:
            v = self.convert(self.eval(x, fr, et), et, e.line, "set element")
            st.items[key_of(v)] = v
        return st

    def map_key(self, m, key_node, fr, line):
        return self.convert(self.eval(key_node, fr, m.ktype), m.ktype, line, "dict key")

    def map_method(self, m, name, args, line):
        if name == "keys":
            return TList(m.ktype, [k for k, _ in m.items.values()])
        if name == "values":
            return TList(m.vtype, [v for _, v in m.items.values()])
        if name == "remove":
            key = self.convert(args[0], m.ktype, line, "dict key")
            if key_of(key) not in m.items:
                raise RunFailure("key %s not found" % show(key), line)
            del m.items[key_of(key)]
            return None
        raise NotDecided("dict method %s (only keys, values and remove are placeholders)" % name, line)

    def set_method(self, st, name, args, line):
        if name in ("add", "remove"):
            if len(args) != 1:
                raise TomatoError("%s takes 1 argument, got %d" % (name, len(args)), line)
            v = self.convert(args[0], st.etype, line, "set element")
            if name == "add":
                st.items[key_of(v)] = v
            elif key_of(v) not in st.items:
                raise RunFailure("element %s not found" % show(v), line)
            else:
                del st.items[key_of(v)]
            return None
        raise NotDecided("set method %s (only add and remove are placeholders)" % name, line)

    def list_literal(self, e, fr, expected):
        if isinstance(expected, ListT):
            elem = expected.elem
            items = [self.convert(self.eval(x, fr, elem), elem, e.line, "list item") for x in e.items]
            return TList(elem, items)
        if not e.items:
            raise NotDecided("the type of an empty list literal without a declared type (name it: xs: list[int] = [])",
                             e.line)
        first = self.eval(e.items[0], fr)
        elem = value_type(first)
        items = [first] + [self.convert(self.eval(x, fr, elem), elem, e.line, "list item") for x in e.items[1:]]
        return TList(elem, items)

    def list_index(self, obj, e, fr):
        i = self.int_arg(self.eval(e.index, fr), "an index", e.line)
        if i < 0:
            raise NotDecided("negative list indexes", e.line)
        if i >= len(obj.items):
            raise RunFailure("list index %d is out of range for length %d" % (i, len(obj.items)), e.line)
        return i

    def list_method(self, lst, name, args, line):
        if isinstance(lst, TTuple):
            raise TomatoError("a tuple cannot be changed, so it has no method %s (D39a)" % name, line)
        if name == "append":
            if len(args) != 1:
                raise TomatoError("append takes 1 argument, got %d" % len(args), line)
            lst.items.append(self.convert(args[0], lst.elem, line, "appended item"))
            return None
        raise NotDecided("list method %s (only append is decided; removal, insertion and slicing are open)" % name, line)

    def index(self, e, fr):
        obj = self.eval(e.obj, fr)
        if isinstance(obj, TMap):
            key = self.map_key(obj, e.index, fr, e.line)
            if key_of(key) not in obj.items:
                raise RunFailure("key %s not found" % show(key), e.line)
            return obj.items[key_of(key)][1]
        if isinstance(obj, TSet):
            raise NotDecided("indexing a set", e.line)
        if isinstance(obj, TList):
            return obj.items[self.list_index(obj, e, fr)]
        if not isinstance(obj, str):
            raise NotDecided("indexing %r (only text and list indexing is decided)" % value_type(obj), e.line)
        i = self.int_arg(self.eval(e.index, fr), "an index", e.line)
        if i < 0:
            raise NotDecided("negative string indexes", e.line)
        if i >= len(obj):
            raise RunFailure("string index %d is out of range for length %d" % (i, len(obj)), e.line)
        return obj[i]

    def slice(self, e, fr):
        obj = self.eval(e.obj, fr)
        if isinstance(obj, (TList, TMap, TSet)):
            raise NotDecided("slicing a list, dict or set", e.line)
        if not isinstance(obj, str):
            raise NotDecided("slicing %r (only text slicing is decided)" % value_type(obj), e.line)
        lo = 0 if e.lo is None else self.int_arg(self.eval(e.lo, fr), "a slice bound", e.line)
        hi = len(obj) if e.hi is None else self.int_arg(self.eval(e.hi, fr), "a slice bound", e.line)
        if not 0 <= lo <= hi <= len(obj):
            raise RunFailure("slice [%d:%d] is out of range for length %d" % (lo, hi, len(obj)), e.line)
        return obj[lo:hi]

    def str_method(self, s, name, args, line):
        def want(n, types=None):
            if len(args) != n:
                raise TomatoError("%s takes %d argument(s), got %d" % (name, n, len(args)), line)
            for a in args:
                if types and not isinstance(a, str):
                    raise TomatoError("%s takes text, found %r" % (name, value_type(a)), line)
        if name in ("upper", "lower", "strip"):
            want(0)
            return getattr(s, name)()
        if name in ("startswith", "endswith"):
            want(1, True)
            return getattr(s, name)(args[0])
        if name == "find":
            want(1, True)
            return s.find(args[0])
        if name == "replace":
            want(2, True)
            if args[0] == "":
                raise NotDecided("replacing an empty string", line)
            return s.replace(args[0], args[1])
        if name == "split":
            want(1, True)
            if args[0] == "":
                raise NotDecided("splitting on an empty string", line)
            return TList(StrT, s.split(args[0]))
        if name == "join":
            if len(args) != 1 or not (isinstance(args[0], TList) and args[0].elem == StrT):
                raise TomatoError("join takes a list[str]", line)
            return s.join(args[0].items)
        raise TomatoError("text has no method %s" % name, line)

    def open_file(self, args, line):
        if not 1 <= len(args) <= 2 or not all(isinstance(a, str) for a in args):
            raise TomatoError("open(path) or open(path, mode) takes text", line)
        mode = args[1] if len(args) == 2 else "r"
        if mode not in ("r", "w", "a"):
            raise TomatoError("open mode must be 'r', 'w' or 'a', found %r" % mode, line)
        try:
            return TFile(open(args[0], mode, encoding="utf-8", newline=""), args[0])
        except OSError as err:
            raise RunFailure("cannot open %s: %s" % (args[0], err.strerror or err), line, kind="IOError")

    def file_method(self, f, name, args, line):
        if name not in ("read", "write", "close"):
            raise NotDecided("file method %s (only read, write and close are placeholders)" % name, line)
        if f.closed and name != "close":
            raise RunFailure("file %s is closed" % f.path, line, kind="IOError")
        try:
            if name == "read":
                return f.handle.read()
            if name == "write":
                if len(args) != 1 or not isinstance(args[0], str):
                    raise TomatoError("write takes text", line)
                f.handle.write(args[0])
                return None
            if not f.closed:
                f.handle.close()
                f.closed = True
            return None
        except (OSError, ValueError) as err:
            raise RunFailure("file %s: %s" % (f.path, err), line, kind="IOError")

    def to_text(self, v, line):
        if isinstance(v, (str, bool, float, Rational)) or is_int_value(v):
            return show(v)
        raise NotDecided("str() of %r" % value_type(v), line)

    # ---------------------------------------------------------- calls and attributes
    def static_type(self, e, fr):
        """The declared type of an expression where it is known without running it, else None (P19)."""
        if isinstance(e, N.Name):
            return fr.vars[e.name][0] if e.name in fr.vars else None
        if isinstance(e, N.Call):
            f = e.func
            if isinstance(f, N.Name) and f.name not in fr.vars:
                fkey = self.scope_get(f.name)
                if fkey in self.funcs:
                    return self.funcs[fkey].ret
                if fkey in self.classes:
                    return ClassT(fkey)
            elif isinstance(f, N.Attr):
                if isinstance(f.obj, N.Name) and self.vis_class(f.obj.name) and f.obj.name not in fr.vars:
                    m = self.vis_class(f.obj.name).find_method(f.name)
                    return m.ret if m else None
                return self.member_type(self.static_type(f.obj, fr), f.name, True)
        elif isinstance(e, N.Attr):
            return self.member_type(self.static_type(e.obj, fr), e.name, False)
        return None

    def member_type(self, t, name, is_method):
        if isinstance(t, (UnionT, InterT)):
            return None                                # members are checked when the code runs (D23g)
        if isinstance(t, OptT):
            t = t.inner
        if isinstance(t, ClassT) and t.name in self.classes:
            cls = self.classes[t.name]
            if is_method:
                m = cls.find_method(name)
                return m.ret if m else None
            found = cls.find_field(name)[1]
            return found[1] if found else None
        if isinstance(t, IfaceT) and is_method:
            m = self.iface_requirements(t.name).get(name)
            return m.ret if m else None
        return None

    def declared_member_check(self, obj_node, member, is_method, fr, line):
        """Members must exist on the declared type of the receiver, not only on the object's real class
        (D04a, D12bb). Where the receiver's type cannot be known without running (P19) it is checked at run time."""
        t = self.static_type(obj_node, fr)
        if isinstance(t, (UnionT, InterT)):
            return                                     # members are checked when the code runs (D23g)
        if isinstance(t, OptT):
            t = t.inner            # narrowing is not designed yet: a None receiver fails when the code runs (D23b)
        kind = "method" if is_method else "field"
        if isinstance(t, IfaceT):
            if not is_method or member not in self.iface_requirements(t.name):
                raise TomatoError("interface %s has no %s %s" % (t.name, kind, member), line)
        elif isinstance(t, ClassT) and t.name in self.classes:
            cls = self.classes[t.name]
            found = cls.find_method(member) if is_method else cls.find_field(member)[1]
            if found is None:
                raise TomatoError("%s has no %s %s" % (t.name, kind, member), line)

    def attr(self, e, fr):
        self.declared_member_check(e.obj, e.name, False, fr, e.line)
        if isinstance(e.obj, N.Name) and self.vis_class(e.obj.name) and e.obj.name not in fr.vars:
            raise TomatoError("%s.%s must be called" % (e.obj.name, e.name), e.line)
        obj = self.eval(e.obj, fr)
        if not isinstance(obj, Instance):
            raise TomatoError("%r has no members" % value_type(obj), e.line)
        owner, entry = obj.cls.find_field(e.name)
        if entry is None:
            raise TomatoError("%s has no field %s" % (obj.cls.name, e.name), e.line)
        self.check_access(entry[0].private, owner, fr, "field " + e.name, e.line)
        if e.name not in obj.fields:
            raise TomatoError("field %s is read before it is set" % e.name, e.line)
        return obj.fields[e.name]

    def call(self, e, fr):
        f = e.func
        if isinstance(f, N.Attr):
            if isinstance(f.obj, N.Name) and self.vis_class(f.obj.name) and f.obj.name not in fr.vars:
                return self.call_class_qualified(self.vis_class(f.obj.name), f.name, e, fr)
            self.declared_member_check(f.obj, f.name, True, fr, e.line)
            obj = self.eval(f.obj, fr)
            if e.kwargs and not isinstance(obj, Instance):
                raise TomatoError("keyword arguments work only with functions, methods and classes you define (D39a)", e.line)
            if isinstance(obj, TMap):
                kt = obj.ktype if f.name == "remove" else None
                return self.map_method(obj, f.name, [self.eval(a, fr, kt) for a in e.args], e.line)
            if isinstance(obj, TSet):
                return self.set_method(obj, f.name, [self.eval(a, fr, obj.etype) for a in e.args], e.line)
            if isinstance(obj, TFile):
                return self.file_method(obj, f.name, [self.eval(a, fr) for a in e.args], e.line)
            if isinstance(obj, TList):
                return self.list_method(obj, f.name, [self.eval(a, fr, obj.elem) for a in e.args], e.line)
            if isinstance(obj, str):
                return self.str_method(obj, f.name, [self.eval(a, fr) for a in e.args], e.line)
            if not isinstance(obj, Instance):
                raise TomatoError("%r has no methods" % value_type(obj), e.line)
            m = obj.cls.find_method(f.name)
            if m is None or not m.has_self:
                raise TomatoError("%s has no method %s" % (obj.cls.name, f.name), e.line)
            if m.node.marker == "init":
                raise NotDecided("calling @init on an existing instance", e.line)
            self.check_access(m.node.private, m.owner, fr, "method " + f.name, e.line)
            return self.invoke(m, self.eval_args(m, e.args, fr, e.line, kwargs=e.kwargs), e.line, self_obj=obj)
        if isinstance(f, N.LlvmRef):
            return self.llvm_call(f, e.args, fr, e.line)
        if not isinstance(f, N.Name):
            raise NotDecided("calling a computed expression", e.line)
        n = f.name
        if n in fr.vars or (n in self.globals.vars and fr is not self.globals):
            raise NotDecided("calling a variable", e.line)
        if e.kwargs and n not in fr.vars and not (self.scope_get(n) in self.funcs or self.vis_class(n)):
            raise TomatoError("keyword arguments work only with functions, methods and classes you define (D39a)", e.line)
        if n == "print":
            self.out.write(" ".join(show(self.eval(a, fr)) for a in e.args) + "\n")
            return None
        if n == "open":
            return self.open_file([self.eval(a, fr) for a in e.args], e.line)
        if n == "len":
            if len(e.args) != 1:
                raise TomatoError("len(x) takes one argument", e.line)
            v = self.eval(e.args[0], fr)
            if isinstance(v, (TList, TMap, TSet)):
                return len(v.items)
            if not isinstance(v, str):
                raise NotDecided("len of %r (only text, lists, dicts and sets are decided)" % value_type(v), e.line)
            return len(v)
        if n == "str":
            if len(e.args) != 1:
                raise TomatoError("str(x) takes one argument", e.line)
            return self.to_text(self.eval(e.args[0], fr), e.line)
        if n == "int":
            if len(e.args) != 1:
                raise TomatoError("int(x) takes one argument", e.line)
            v = self.eval(e.args[0], fr)
            if isinstance(v, str):
                t = v.strip()
                body = t[1:] if t[:1] in "+-" else t
                if not (body.isascii() and body.isdigit()):
                    raise RunFailure("cannot convert %r to int" % v, e.line)
                return int(t)
            return self.explicit_int(v, INT, e.line)
        if n == "range":
            vals = [self.eval(a, fr) for a in e.args]
            if not 1 <= len(vals) <= 3 or not all(is_int_value(v) for v in vals):
                raise TomatoError("range takes one to three integers: range(stop), range(start, stop), "
                                  "range(start, stop, step)", e.line)
            nums = [int_value(v) for v in vals]
            if len(nums) == 1:
                start, stop, step = 0, nums[0], 1
            else:
                start, stop, step = nums[0], nums[1], (nums[2] if len(nums) == 3 else 1)
            if step == 0:
                raise TomatoError("range step cannot be zero", e.line)
            return RangeObj(start, stop, step)
        if n == "rational":
            if len(e.args) != 2:
                raise TomatoError("rational(numerator, denominator) takes two arguments (D05aq)", e.line)
            a, b = self.eval(e.args[0], fr), self.eval(e.args[1], fr)
            if not (is_int_value(a) and is_int_value(b)):
                raise TomatoError("rational arguments must be integers (D05ar)", e.line)
            return Rational(int_value(a), int_value(b))
        fkey = self.scope_get(n)
        if fkey in self.funcs:
            fn = self.funcs[fkey]
            return self.invoke(fn, self.eval_args(fn, e.args, fr, e.line, kwargs=e.kwargs), e.line)
        if self.vis_class(n):
            return self.construct(self.vis_class(n), e, fr)
        raise TomatoError("unknown function %r" % n, e.line)

    def eval_args(self, fn, args, fr, line, pre=_UNSET, kwargs=None):
        nfix = getattr(fn, "nfixed", len(fn.ptypes))
        star, kwstar = getattr(fn, "star", None), getattr(fn, "kwstar", None)
        lo = getattr(fn, "min_args", nfix)
        kwargs = kwargs or []
        if (len(args) > nfix and star is None) or (not kwargs and len(args) < lo):
            raise TomatoError("%s takes %s argument(s), got %d"
                              % (fn.name, "%d to %d" % (lo, nfix) if lo != nfix else str(nfix), len(args)), line)
        if pre is not _UNSET:  # the one argument was already evaluated (see construct)
            vals = [pre]
        else:
            vals = [self.eval(a, fr, t) for a, t in zip(args[:nfix], fn.ptypes)]
        extra = [self.eval(a, fr, fn.ptypes[star].elem) for a in args[nfix:]] if pre is _UNSET else []
        names = [p.name for p in fn.node.params if p.name != "self" and not p.star]
        named, extra_kw = {}, {}
        for name, ex in kwargs:
            if name in names:
                k = names.index(name)
                if k < len(vals):
                    raise TomatoError("%s got more than one value for %s" % (fn.name, name), line)
                named[k] = self.eval(ex, fr, fn.ptypes[k])
            elif kwstar is not None:
                extra_kw[name] = self.eval(ex, fr, fn.ptypes[kwstar].value)
            else:
                raise TomatoError("%s has no parameter %s" % (fn.name, name), line)
        for k in range(len(vals), nfix):
            if k in named:
                vals.append(named[k])
            elif fn.defaults[k] is not None:
                prev, self.cur_mod = self.cur_mod, fn.module
                try:
                    vals.append(self.eval(fn.defaults[k], Frame(), fn.ptypes[k]))
                finally:
                    self.cur_mod = prev
            else:
                raise TomatoError("%s is missing the argument %s" % (fn.name, names[k]), line)
        if star is not None:
            vals.append(TTuple(fn.ptypes[star].elem, [self.convert(v, fn.ptypes[star].elem, line, "argument") for v in extra]))
        if kwstar is not None:
            m = TMap(StrT, fn.ptypes[kwstar].value)
            for name, v in extra_kw.items():
                m.items[key_of(name)] = [name, self.convert(v, m.vtype, line, "argument " + name)]
            vals.append(m)
        return vals

    def fill_default_values_one(self, fn, vals):
        k = len(vals)
        prev, self.cur_mod = self.cur_mod, fn.module
        try:
            vals.append(self.eval(fn.defaults[k], Frame(), fn.ptypes[k]))
        finally:
            self.cur_mod = prev

    def fill_default_values(self, fn, vals):
        """Give the parameters the caller left out their defaults, evaluated now, in the callee's module (D19c);
        `*args` and `**kwargs` start empty (D39a)."""
        for k in range(len(vals), len(fn.ptypes)):
            if k == getattr(fn, "star", None):
                vals.append(TTuple(fn.ptypes[k].elem, []))
                continue
            if k == getattr(fn, "kwstar", None):
                vals.append(TMap(StrT, fn.ptypes[k].value))
                continue
            prev, self.cur_mod = self.cur_mod, fn.module
            try:
                vals.append(self.eval(fn.defaults[k], Frame(), fn.ptypes[k]))
            finally:
                self.cur_mod = prev
        return vals

    def invoke(self, fn, args, line, self_obj=None):
        if len(args) != len(fn.ptypes):
            raise TomatoError("%s takes %d argument(s), got %d" % (fn.name, len(fn.ptypes), len(args)), line)
        if self.depth >= MAX_CALL_DEPTH:
            raise TomatoError("calls are nested more than %d deep (the recursion limit is not yet decided)"
                              % MAX_CALL_DEPTH, line)
        self.depth += 1
        prev_mod, self.cur_mod = self.cur_mod, fn.module
        try:
            return self.invoke_frame(fn, args, line, self_obj)
        finally:
            self.depth -= 1
            self.cur_mod = prev_mod

    def invoke_frame(self, fn, args, line, self_obj):
        fr = Frame(fn.owner, in_init=fn.node.marker == "init")
        fr.ret_type = fn.ret
        if self_obj is not None:
            fr.vars["self"] = [ClassT(fn.owner.name), self_obj]
        for p, t, v in zip([p for p in fn.node.params if p.name != "self"], fn.ptypes, args):
            fr.vars[p.name] = [t, self.convert(v, t, line, "argument %s" % p.name)]
        try:
            self.exec_block(fn.node.body, fr)
        except (BreakLoop, ContinueLoop):
            raise TomatoError("break or continue outside a loop", line)
        except Return as r:
            if fn.ret == NoneT:
                if r.value is not None:
                    raise TomatoError("%s returns no value" % fn.name, line)
                return None
            return self.convert(r.value, fn.ret, line, "return value")
        if fn.ret != NoneT:
            raise TomatoError("%s ended without returning a %r" % (fn.name, fn.ret), line)
        return None

    def call_class_qualified(self, cls, name, e, fr):
        m = cls.find_method(name)
        if m is None:
            raise TomatoError("%s has no method %s" % (cls.name, name), e.line)
        self.check_access(m.node.private, m.owner, fr, "method " + name, e.line)
        if not m.has_self:
            return self.invoke(m, self.eval_args(m, e.args, fr, e.line, kwargs=e.kwargs), e.line)
        if not e.args:
            raise TomatoError("%s.%s needs self as its first argument (D12ao)" % (cls.name, name), e.line)
        obj = self.eval(e.args[0], fr)
        if not (isinstance(obj, Instance) and self.is_subclass(obj.cls, cls.name)):
            raise TomatoError("first argument must be an instance of %s" % cls.name, e.line)
        if m.node.marker != "init" and not (fr.owner and fr.owner is not cls and self.is_subclass(fr.owner, cls.name)):
            raise NotDecided("class-qualified calls other than a subclass calling its parent", e.line)
        return self.invoke(m, self.eval_args(m, e.args[1:], fr, e.line, kwargs=e.kwargs), e.line, self_obj=obj)

    def construct(self, cls, e, fr):
        # The single argument is evaluated once: here when it may be a conversion (D12az), and the value is then
        # reused for @init. A literal-only argument has no side effects and may need a contextual type, so it is
        # evaluated later, against the parameter type.
        pre = _UNSET
        if len(e.args) == 1 and not self.literal_only(e.args[0]):
            pre = a = self.eval(e.args[0], fr)
            if isinstance(a, Instance) and (self.is_subclass(cls, a.cls.name) or self.is_subclass(a.cls, cls.name)):
                if self.is_subclass(a.cls, cls.name):
                    return a
                raise RunFailure("cannot convert %s to %s: it is not one (D12az)" % (a.cls.name, cls.name), e.line)
        init = cls.nearest("init")
        if init is None:
            if e.args:
                raise TomatoError("%s takes no arguments (D12af)" % cls.name, e.line)
        elif cls.own_init() is None:
            raise TomatoError("%s has no @init of its own, so it cannot be called (D12ah)" % cls.name, e.line)
        inst = Instance(cls)
        for k in reversed(list(cls.chain())):
            for fname, (f, t) in k.fields.items():
                if f.value is not None:
                    prev_mod, self.cur_mod = self.cur_mod, k.module
                    try:
                        inst.fields[fname] = self.convert(self.eval(f.value, self.globals, t), t, f.line, "field value")
                    finally:
                        self.cur_mod = prev_mod
        if init is not None:
            self.invoke(init, self.eval_args(init, e.args, fr, e.line, pre, kwargs=e.kwargs), e.line, self_obj=inst)
        for k in cls.chain():
            for fname in k.fields:
                if fname not in inst.fields:
                    raise TomatoError("field %s was never set (D12x)" % fname, e.line)
        return inst


def run_source(src, out=None, entry="main", modules=None, search=None, llvm_ir=None, inputs=None, warn_out=None):
    try:
        Interpreter(out, modules, search, llvm_ir, warn_out).run(src, entry, inputs)
    except RecursionError:
        raise TomatoError("calls are nested too deep for this host (the recursion limit is not yet decided)")
