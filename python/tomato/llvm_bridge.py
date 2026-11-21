"""Lets the Python interpreter run LLVM functions named with `!name` (D27a).

PROVISIONAL (P33): the functions come from LLVM IR text given to the interpreter, and are run with llvmlite's JIT.
Only whole numbers, bools and floats cross the boundary; anything else stops as not decided.
"""
import ctypes
import re

from .errors import NotDecided, TomatoError

C_TYPES = {"i1": ctypes.c_bool, "i8": ctypes.c_int8, "i16": ctypes.c_int16, "i32": ctypes.c_int32,
           "i64": ctypes.c_int64, "float": ctypes.c_float, "double": ctypes.c_double, "void": None}
DEFINE = re.compile(r"^\s*define\s+(?P<head>[^@]*?)@(?P<name>[-\w$.\"]+)\s*\((?P<params>[^)]*)\)", re.M)


def tomato_to_llvm(t):
    """The LLVM type a Tomato type crosses the `!x` boundary as (D27b); None when it cannot cross."""
    from .values import BoolT, FixedT, FloatT, IntT, NoneT
    if isinstance(t, IntT):
        return "i64"
    if isinstance(t, FixedT) and t.bits <= 64:
        return "i%d" % t.bits
    if t == FloatT:
        return "double"
    if t == BoolT:
        return "i1"
    if t == NoneT:
        return "void"
    return None


def parse_signatures(ir):
    """Map each defined function name to (return type, [parameter types]) read from the IR text."""
    out = {}
    for m in DEFINE.finditer(ir):
        words = [w for w in m.group("head").split() if w not in (
            "dso_local", "internal", "private", "external", "linkonce_odr", "weak", "hidden", "noundef", "signext",
            "zeroext", "fastcc", "ccc", "local_unnamed_addr", "unnamed_addr", "nounwind", "readonly")]
        ret = words[-1] if words else "void"
        params = []
        for p in m.group("params").split(","):
            p = p.strip()
            if p and p != "...":
                params.append(next(w for w in p.split() if w not in ("noundef", "signext", "zeroext")))
        out[m.group("name").strip('"')] = (ret, params)
    return out


class LlvmBridge:
    def __init__(self):
        try:
            import llvmlite.binding as llvm
        except ImportError:
            raise TomatoError("running LLVM needs the llvmlite package (pip install llvmlite)")
        self.llvm = llvm
        llvm.initialize()
        llvm.initialize_native_target()
        llvm.initialize_native_asmprinter()
        target = llvm.Target.from_default_triple()
        self.engine = llvm.create_mcjit_compiler(llvm.parse_assembly(""), target.create_target_machine())
        self.sigs, self.modules, self.cache = {}, [], {}

    def add_ir(self, ir, label="<ir>"):
        try:
            mod = self.llvm.parse_assembly(ir)
            mod.verify()
        except (RuntimeError, ValueError) as err:
            raise TomatoError("LLVM rejected %s: %s" % (label, str(err).strip().splitlines()[0] if str(err).strip() else err))
        self.modules.append(mod)  # keep the module alive: the engine does not own it
        self.engine.add_module(mod)
        self.engine.finalize_object()
        self.engine.run_static_constructors()
        self.sigs.update(parse_signatures(ir))

    def has(self, name):
        return name in self.sigs

    def signature(self, name):
        ret, params = self.sigs[name]
        for t in [ret] + params:
            if t not in C_TYPES:
                raise NotDecided("LLVM type %s in !%s (only i1, i8-i64, float, double and void cross over)" % (t, name))
        return ret, params

    def function(self, name):
        if name not in self.cache:
            ret, params = self.signature(name)
            addr = self.engine.get_function_address(name)
            if not addr:
                raise TomatoError("LLVM has no function named %s" % name)
            self.cache[name] = ctypes.CFUNCTYPE(C_TYPES[ret], *[C_TYPES[p] for p in params])(addr)
        return self.cache[name]
