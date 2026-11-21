class Node:
    _fields = ()

    def __init__(self, *args, line=None):
        for f, a in zip(self._fields, args):
            setattr(self, f, a)
        self.line = line

    def __repr__(self):
        return "%s(%s)" % (type(self).__name__, ", ".join(repr(getattr(self, f)) for f in self._fields))


def node(name, *fields):
    return type(name, (Node,), {"_fields": fields})


# type references and expressions
TypeRef = node("TypeRef", "name", "length", "arg", "arg2")   # length: expr or None; arg/arg2: type arguments of list, set, map
IntLit = node("IntLit", "value")
FloatLit = node("FloatLit", "value")
StrLit = node("StrLit", "value")
ListLit = node("ListLit", "items")
MapLit = node("MapLit", "pairs")                     # [(key, value)]
SetLit = node("SetLit", "items")
BoolLit = node("BoolLit", "value")
Name = node("Name", "name")
LlvmRef = node("LlvmRef", "name")
Attr = node("Attr", "obj", "name")
Call = node("Call", "func", "args", "kwargs")        # kwargs: [(name, expr)] keyword arguments (D39a)
TypeCall = node("TypeCall", "type", "args")          # int[length=8](x)
Index = node("Index", "obj", "index")
Slice = node("Slice", "obj", "lo", "hi")
BinOp = node("BinOp", "op", "left", "right")
UnOp = node("UnOp", "op", "operand")
# statements
Assign = node("Assign", "target", "value")
Declare = node("Declare", "name", "type", "value")
Return = node("Return", "value")
If = node("If", "branches", "orelse")                # branches: [(cond, body)]
While = node("While", "cond", "body")
For = node("For", "var", "iter", "body")
ExprStmt = node("ExprStmt", "expr")
Pass = node("Pass")
Break = node("Break")
Continue = node("Continue")
Raise = node("Raise", "value")
Try = node("Try", "body", "handlers", "orelse", "final")   # handlers: [(class name, var or None, body)]
Import = node("Import", "module", "names")
# declarations
Param = node("Param", "name", "type", "default", "star")   # star: None, "*" (*args) or "**" (**kwargs) (D39a)
FuncDef = node("FuncDef", "name", "params", "ret", "body", "private", "override", "marker")
FieldDef = node("FieldDef", "name", "type", "private", "const", "value")
ClassDef = node("ClassDef", "name", "parent", "interfaces", "fields", "methods")
InterfaceDef = node("InterfaceDef", "name", "parents", "methods")
Implements = node("Implements", "cls", "iface")
LlvmDecl = node("LlvmDecl", "name", "params", "ret")
Module = node("Module", "body")
