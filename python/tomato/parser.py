from .errors import TomatoError, NotDecided
from .lexer import lex
from . import nodes as N

TYPE_WITH_LENGTH = ("int", "uint")
CMP = {"==", "!=", "<", "<=", ">", ">="}


class Parser:
    def __init__(self, src):
        self.toks = lex(src)
        self.p = 0

    # token helpers
    @property
    def t(self):
        return self.toks[self.p]

    def peek(self, k=1):
        return self.toks[min(self.p + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.p]
        self.p += 1
        return t

    def is_op(self, v):
        return self.t.kind == "OP" and self.t.value == v

    def is_kw(self, v):
        return self.t.kind == "KW" and self.t.value == v

    def accept_op(self, v):
        if self.is_op(v):
            return self.next()

    def accept_kw(self, v):
        if self.is_kw(v):
            return self.next()

    def expect_op(self, v):
        if not self.is_op(v):
            self.err("expected %r" % v)
        return self.next()

    def expect_kw(self, v):
        if not self.is_kw(v):
            self.err("expected %r" % v)
        return self.next()

    def expect(self, kind):
        if self.t.kind != kind:
            self.err("expected %s" % kind.lower())
        return self.next()

    def err(self, msg):
        t = self.t
        shown = t.value if t.value is not None else t.kind
        raise TomatoError("%s, found %r" % (msg, shown), t.line)

    # module
    def module(self):
        body = []
        while self.t.kind != "EOF":
            body.append(self.top_item())
        return N.Module(body, line=1)

    def top_item(self):
        t = self.t
        if self.is_op("!"):
            self.next()
            nm = self.expect("NAME")
            params = self.params()
            ret = self.type() if self.accept_op("->") else None
            self.expect("NEWLINE")
            return N.LlvmDecl(nm.value, params, ret, line=t.line)
        if self.is_kw("export"):
            self.next()
            if not (self.is_kw("def") or self.is_kw("class") or self.is_kw("interface") or self.is_op("@")):
                self.err("expected a function, class or interface after export")
            d = self.top_item()
            d.exported = True
            return d
        if self.is_kw("from"):
            self.next()
            mod = self.expect("NAME").value
            self.expect_kw("import")
            names = [self.expect("NAME").value]
            while self.accept_op(","):
                names.append(self.expect("NAME").value)
            self.expect("NEWLINE")
            return N.Import(mod, names, line=t.line)
        if self.is_kw("import"):
            raise NotDecided("`import module` (only `from module import name, ...` is decided so far)", t.line)
        if self.is_op("@"):
            self.next()
            m = self.expect("NAME")
            if m.value in ("init", "add"):
                raise TomatoError("@%s belongs to a method inside a class" % m.value, m.line)
            self.expect("NEWLINE")
            if not self.is_kw("def"):
                self.err("expected a function after @%s" % m.value)
            return self.funcdef(in_class=False, marker="entry:" + m.value)
        if self.is_kw("def"):
            return self.funcdef(in_class=False)
        if self.is_kw("class"):
            return self.classdef()
        if self.is_kw("interface"):
            return self.interfacedef()
        if t.kind == "NAME" and self.peek().kind == "KW" and self.peek().value == "implements":
            cls = self.next()
            self.next()
            out = []
            while True:
                out.append(N.Implements(cls.value, self.expect("NAME").value, line=cls.line))
                if not self.accept_op(","):
                    break
            self.expect("NEWLINE")
            return out[0] if len(out) == 1 else N.Module(out, line=cls.line)
        return self.statement()

    # types
    def type(self):
        base = self.inter_type()
        if self.is_op("|"):                       # `|` joins types into a union (D23g)
            members, line = [base], self.t.line
            while self.is_op("|"):
                self.next()
                members.append(self.inter_type())
            return N.TypeRef("union", None, members, None, line=line)
        return base

    def inter_type(self):
        base = self.base_type()
        if self.is_op("&"):                       # `&` joins types into an intersection (D23h)
            members, line = [base], self.t.line
            while self.is_op("&"):
                self.next()
                members.append(self.base_type())
            return N.TypeRef("intersection", None, members, None, line=line)
        return base

    def base_type(self):
        t = self.expect("NAME") if self.t.kind == "NAME" else None
        if t is None:
            self.err("expected a type")
        length = None
        if t.value in ("list", "set", "tuple"):
            self.expect_op("[")
            arg = self.type()
            self.expect_op("]")
            return N.TypeRef(t.value, None, arg, None, line=t.line)
        if t.value == "dict":
            self.expect_op("[")
            arg = self.type()
            self.expect_op(",")
            arg2 = self.type()
            self.expect_op("]")
            return N.TypeRef("dict", None, arg, arg2, line=t.line)
        if t.value in TYPE_WITH_LENGTH and self.is_op("["):
            self.next()
            key = self.expect("NAME")
            if key.value != "length":
                raise TomatoError("only the length= argument exists for integer types", key.line)
            self.expect_op("=")
            length = self.expr()
            self.expect_op("]")
        return N.TypeRef(t.value, length, None, None, line=t.line)

    # declarations
    def params(self):
        self.expect_op("(")
        out = []
        while not self.is_op(")"):
            star = None
            if self.is_op("*") or self.is_op("**"):  # *args and **kwargs (D39a)
                star = "**" if self.next().value == "**" or self.accept_op("*") else "*"
            nm = self.expect("NAME")
            ty = None
            if self.accept_op(":"):
                ty = self.type()
            default = self.expr() if self.accept_op("=") else None
            if star:
                if ty is None or default is not None:
                    raise TomatoError("%s%s needs a type (%s) and takes no default (D39a)"
                                      % (star, nm.value, "tuple[T]" if star == "*" else "dict[str, V]"), nm.line)
                if any(q.star == "**" for q in out) or (star == "*" and any(q.star for q in out)):
                    raise TomatoError("*args comes before **kwargs, and both come last (D39a)", nm.line)
            elif any(q.star for q in out):
                raise TomatoError("parameter %r follows *args or **kwargs; they come last (D39a)" % nm.value, nm.line)
            elif default is None and any(q.default is not None for q in out if not q.star):
                raise TomatoError("parameter %r needs a default value: it follows one that has a default (D19c)" % nm.value, nm.line)
            out.append(N.Param(nm.value, ty, default, star, line=nm.line))
            if not self.accept_op(","):
                break
        self.expect_op(")")
        return out

    def funcdef(self, in_class, marker=None, override=False, body_required=True):
        line = self.expect_kw("def").line
        private = bool(self.accept_kw("private"))
        name = self.expect("NAME").value
        params = self.params()
        ret = None
        if self.accept_op("->"):
            ret = self.type()
        if not body_required:
            if self.is_op(":"):
                raise TomatoError("interface methods cannot have bodies (D12e)", line)
            self.expect("NEWLINE")
            return N.FuncDef(name, params, ret, None, private, override, marker, line=line)
        self.expect_op(":")
        body = self.block()
        return N.FuncDef(name, params, ret, body, private, override, marker, line=line)

    def block(self):
        self.expect("NEWLINE")
        self.expect("INDENT")
        out = []
        while self.t.kind != "DEDENT":
            out.append(self.statement())
        self.next()
        return out

    def classdef(self):
        line = self.expect_kw("class").line
        name = self.expect("NAME").value
        parent = None
        if self.accept_op("("):
            parent = self.expect("NAME").value
            if self.is_op(","):
                raise TomatoError("a class may inherit from at most one parent class (D12b)", self.t.line)
            self.expect_op(")")
        ifaces = []
        if self.accept_kw("implements"):
            ifaces.append(self.expect("NAME").value)
            while self.accept_op(","):
                ifaces.append(self.expect("NAME").value)
        self.expect_op(":")
        self.expect("NEWLINE")
        self.expect("INDENT")
        fields, methods = [], []
        while self.t.kind != "DEDENT":
            if self.accept_kw("pass"):
                self.expect("NEWLINE")
                continue
            self.member(fields, methods)
        self.next()
        return N.ClassDef(name, parent, ifaces, fields, methods, line=line)

    def member(self, fields, methods):
        marker = None
        if self.is_op("@"):
            self.next()
            m = self.expect("NAME")
            if m.value not in ("init", "add"):
                raise TomatoError("unknown marker @%s (only @init and @add exist)" % m.value, m.line)
            marker = m.value
            self.expect("NEWLINE")
        override = bool(self.accept_kw("override"))
        if self.is_kw("def"):
            methods.append(self.funcdef(True, marker, override))
            return
        if marker or override:
            self.err("expected a method after the marker")
        line = self.t.line
        private = const = False
        while self.is_kw("private") or self.is_kw("const"):
            if self.next().value == "private":
                if const:
                    raise TomatoError("write `private const`, not `const private` (D12y)", line)
                private = True
            else:
                const = True
        nm = self.expect("NAME")
        self.expect_op(":")
        ty = self.type()
        value = self.expr() if self.accept_op("=") else None
        self.expect("NEWLINE")
        fields.append(N.FieldDef(nm.value, ty, private, const, value, line=line))

    def interfacedef(self):
        line = self.expect_kw("interface").line
        name = self.expect("NAME").value
        parents = []
        if self.accept_op("("):
            parents.append(self.expect("NAME").value)
            while self.accept_op(","):
                parents.append(self.expect("NAME").value)
            self.expect_op(")")
        self.expect_op(":")
        self.expect("NEWLINE")
        self.expect("INDENT")
        methods = []
        while self.t.kind != "DEDENT":
            if self.accept_kw("pass"):
                self.expect("NEWLINE")
                continue
            methods.append(self.funcdef(True, body_required=False))
        self.next()
        return N.InterfaceDef(name, parents, methods, line=line)

    # statements
    def statement(self):
        t = self.t
        if self.is_kw("def") or self.is_kw("class") or self.is_kw("interface"):
            raise NotDecided("declarations nested inside blocks", t.line)
        if self.is_kw("return"):
            self.next()
            v = None if self.t.kind == "NEWLINE" else self.expr()
            self.expect("NEWLINE")
            return N.Return(v, line=t.line)
        if self.is_kw("pass"):
            self.next()
            self.expect("NEWLINE")
            return N.Pass(line=t.line)
        if self.is_kw("break") or self.is_kw("continue"):
            kw = self.next().value
            self.expect("NEWLINE")
            return (N.Break if kw == "break" else N.Continue)(line=t.line)
        if self.is_kw("raise"):
            self.next()
            v = self.expr()
            self.expect("NEWLINE")
            return N.Raise(v, line=t.line)
        if self.is_kw("try"):
            return self.trystmt()
        if self.is_kw("if"):
            return self.ifstmt()
        if self.is_kw("for"):
            self.next()
            var = self.expect("NAME").value
            self.expect_kw("in")
            it = self.expr()
            self.expect_op(":")
            return N.For(var, it, self.block(), line=t.line)
        if self.is_kw("while"):
            self.next()
            cond = self.expr()
            self.expect_op(":")
            return N.While(cond, self.block(), line=t.line)
        e = self.expr()
        if self.is_op(":") and isinstance(e, N.Name):
            self.next()
            ty = self.type()
            self.expect_op("=")
            v = self.expr()
            self.expect("NEWLINE")
            return N.Declare(e.name, ty, v, line=t.line)
        if self.is_op("="):
            self.next()
            if not isinstance(e, (N.Name, N.Attr, N.Index)):
                raise TomatoError("cannot assign to this expression", t.line)
            v = self.expr()
            self.expect("NEWLINE")
            return N.Assign(e, v, line=t.line)
        self.expect("NEWLINE")
        return N.ExprStmt(e, line=t.line)

    def trystmt(self):
        line = self.next().line
        self.expect_op(":")
        body = self.block()
        handlers, orelse, final = [], None, None
        while self.is_kw("catch"):
            self.next()
            cls = self.expect("NAME").value
            var = self.expect("NAME").value if self.accept_kw("as") else None
            self.expect_op(":")
            handlers.append((cls, var, self.block()))
        if self.is_kw("else"):
            if not handlers:
                raise TomatoError("else after try needs a catch", self.t.line)
            self.next()
            self.expect_op(":")
            orelse = self.block()
        if self.is_kw("finally"):
            self.next()
            self.expect_op(":")
            final = self.block()
        if not handlers and final is None:
            raise TomatoError("try needs a catch or a finally", line)
        return N.Try(body, handlers, orelse, final, line=line)

    def ifstmt(self):
        line = self.next().line
        branches = []
        cond = self.expr()
        self.expect_op(":")
        branches.append((cond, self.block()))
        orelse = None
        while True:
            if self.accept_kw("elif"):
                cond = self.expr()
                self.expect_op(":")
                branches.append((cond, self.block()))
            elif self.accept_kw("else"):
                self.expect_op(":")
                orelse = self.block()
                break
            else:
                break
        return N.If(branches, orelse, line=line)

    # expressions
    def expr(self):
        return self.or_()

    def or_(self):
        e = self.xor_()
        while self.is_kw("or"):
            ln = self.next().line
            e = N.BinOp("or", e, self.xor_(), line=ln)
        return e

    def xor_(self):                            # `a xor b` on bools (D23h): between `or` and `and`
        e = self.and_()
        while self.is_kw("xor"):
            ln = self.next().line
            e = N.BinOp("xor", e, self.and_(), line=ln)
        return e

    def and_(self):
        e = self.not_()
        while self.is_kw("and"):
            ln = self.next().line
            e = N.BinOp("and", e, self.not_(), line=ln)
        return e

    def not_(self):
        if self.is_kw("not"):
            ln = self.next().line
            return N.UnOp("not", self.not_(), line=ln)
        return self.cmp()

    def cmp(self):
        e = self.bit_or()
        if self.is_kw("is"):
            t = self.next()
            op = "is not" if self.accept_kw("not") else "is"
            return N.BinOp(op, e, self.bit_or(), line=t.line)
        if self.is_kw("in"):
            t = self.next()
            return N.BinOp("in", e, self.bit_or(), line=t.line)
        if self.t.kind == "OP" and self.t.value in CMP:
            t = self.next()
            e = N.BinOp(t.value, e, self.bit_or(), line=t.line)
            if self.t.kind == "OP" and self.t.value in CMP:
                raise NotDecided("chained comparisons", self.t.line)
        return e

    def bit_or(self):                          # `|`, `^`, `&` on numbers (D23h); Python's precedence
        e = self.bit_xor()
        while self.is_op("|"):
            t = self.next()
            e = N.BinOp("|", e, self.bit_xor(), line=t.line)
        return e

    def bit_xor(self):
        e = self.bit_and()
        while self.is_op("^"):
            t = self.next()
            e = N.BinOp("^", e, self.bit_and(), line=t.line)
        return e

    def bit_and(self):
        e = self.add()
        while self.is_op("&"):
            t = self.next()
            e = N.BinOp("&", e, self.add(), line=t.line)
        return e

    def add(self):
        e = self.mul()
        while self.t.kind == "OP" and self.t.value in ("+", "-"):
            t = self.next()
            e = N.BinOp(t.value, e, self.mul(), line=t.line)
        return e

    def mul(self):
        e = self.unary()
        while self.t.kind == "OP" and self.t.value in ("*", "/", "%", "//"):
            t = self.next()
            e = N.BinOp(t.value, e, self.unary(), line=t.line)
        return e

    def unary(self):
        if self.is_op("-"):
            ln = self.next().line
            return N.UnOp("-", self.unary(), line=ln)
        return self.power()

    def power(self):                           # `**` binds tighter than a minus on its left, and nests to the right (P57)
        e = self.postfix()
        if self.is_op("**"):
            t = self.next()
            return N.BinOp("**", e, self.unary(), line=t.line)
        return e

    def postfix(self):
        e = self.atom()
        while True:
            if self.is_op("("):
                ln = self.next().line
                args, kwargs = [], []
                while not self.is_op(")"):
                    if self.t.kind == "NAME" and self.peek().kind == "OP" and self.peek().value == "=":
                        kw = self.next()                  # name=value keyword argument (D39a)
                        self.next()
                        if any(k == kw.value for k, _ in kwargs):
                            raise TomatoError("keyword argument %s is given twice" % kw.value, kw.line)
                        kwargs.append((kw.value, self.expr()))
                    else:
                        if kwargs:
                            raise TomatoError("a positional argument cannot follow a keyword argument (D39a)", self.t.line)
                        args.append(self.expr())
                    if not self.accept_op(","):
                        break
                self.expect_op(")")
                e = N.Call(e, args, kwargs, line=ln)
            elif self.is_op("["):
                ln = self.next().line
                lo = None if self.is_op(":") else self.expr()
                if self.accept_op(":"):
                    hi = None if self.is_op("]") else self.expr()
                    self.expect_op("]")
                    e = N.Slice(e, lo, hi, line=ln)
                else:
                    self.expect_op("]")
                    e = N.Index(e, lo, line=ln)
            elif self.is_op("."):
                self.next()
                e = N.Attr(e, self.expect("NAME").value, line=e.line)
            else:
                return e

    def atom(self):
        t = self.t
        if t.kind == "INT":
            self.next()
            return N.IntLit(t.value, line=t.line)
        if t.kind == "FLOAT":
            self.next()
            return N.FloatLit(t.value, line=t.line)
        if t.kind == "STR":
            self.next()
            return N.StrLit(t.value, line=t.line)
        if t.kind == "KW" and t.value in ("True", "False"):
            self.next()
            return N.BoolLit(t.value == "True", line=t.line)
        if t.kind == "NAME":
            if t.value in TYPE_WITH_LENGTH and self.peek().kind == "OP" and self.peek().value == "[":
                ty = self.type()
                self.expect_op("(")
                args = [self.expr()]
                self.expect_op(")")
                return N.TypeCall(ty, args, line=t.line)
            self.next()
            return N.Name(t.value, line=t.line)
        if self.is_op("("):
            self.next()
            e = self.expr()
            self.expect_op(")")
            return e
        if self.is_op("!"):
            self.next()
            nm = self.expect("NAME")
            return N.LlvmRef(nm.value, line=t.line)
        if self.is_op("{"):
            self.next()
            if self.accept_op("}"):
                return N.MapLit([], line=t.line)
            first = self.expr()
            if self.accept_op(":"):
                pairs = [(first, self.expr())]
                while self.accept_op(","):
                    if self.is_op("}"):
                        break
                    k = self.expr()
                    self.expect_op(":")
                    pairs.append((k, self.expr()))
                self.expect_op("}")
                return N.MapLit(pairs, line=t.line)
            items = [first]
            while self.accept_op(","):
                if self.is_op("}"):
                    break
                items.append(self.expr())
            self.expect_op("}")
            return N.SetLit(items, line=t.line)
        if self.is_op("["):
            self.next()
            items = []
            while not self.is_op("]"):
                items.append(self.expr())
                if not self.accept_op(","):
                    break
            self.expect_op("]")
            return N.ListLit(items, line=t.line)
        self.err("expected an expression")


def parse(src):
    return Parser(src).module()
