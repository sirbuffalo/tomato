"""`tomato repl`: type Tomato one piece at a time (D42a, P59).

Definitions (functions, classes, interfaces, imports, LLVM declarations) and statements are read one at a time and run
by the interpreter. Variables and definitions stay set between lines, so `x = 3` on one line is there on the next. A
definition may be entered again to replace it, and a declaration `x: int = 3` may be entered again to reset x.

What you enter is also kept as a program, so the shell can compile it: `:compile` writes the LLVM IR, `:run` builds a
native program with clang and runs it from the top, `:program` shows the text and `:save FILE` writes it out.
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile

from . import nodes as N
from .codegen import compile_to_ir
from .errors import NotDecided, RunFailure, TomatoError, TomatoRaise
from .interp import BreakLoop, ContinueLoop, Interpreter, Return
from .parser import parse
from .static import Checker
from .values import NoneT, show_item

DECLS = (N.ClassDef, N.InterfaceDef, N.FuncDef, N.Implements, N.Import, N.LlvmDecl)
HELP = """Type Tomato: a statement, an expression (its value is shown), or a def/class (end it with an empty line).
  :load FILE      run a file's definitions and statements into this session
  :vars           show the variables
  :defs           show the functions, classes and interfaces
  :program        show the session as one program (definitions, then your statements inside @main)
  :compile [FILE] compile the session to LLVM IR (default session.ll)
  :run            compile the session natively with clang and run it from the top
  :save FILE      write the session program to FILE
  :reset          forget everything
  :help           this text
  :quit           leave (also Ctrl-D)"""


class Session:
    def __init__(self, out=None, err=None, search=None):
        self.out = out or sys.stdout
        self.err = err or sys.stderr
        self.search = list(search or [os.getcwd()])
        self.reset()

    def reset(self):
        self.interp = Interpreter(self.out, search=self.search, warn_out=self.err)
        self.interp.load(parse(self.interp.module_source("builtin", None)), "builtin")
        self.interp.scope.setdefault("main", dict(self.interp.scope["builtin"]))
        self.defs = {}         # definition name -> its source text, in the order first entered
        self.stmts = []        # statements that ran, as source text

    # ------------------------------------------------------------------ running input
    def feed(self, text):
        """Run a piece of Tomato. Returns False when it failed (the error has been printed)."""
        try:
            module = parse(text)
        except TomatoError as e:
            return self.fail(e)
        items = module.body
        starts = [it.line for it in items] + [len(text.split("\n")) + 1]
        lines = text.split("\n")
        ok = True
        for k, it in enumerate(items):
            chunk = "\n".join(lines[starts[k] - 1:starts[k + 1] - 1]).rstrip("\n")
            ok = self.run_item(it, chunk) and ok
            if not ok:
                break
        return ok

    def run_item(self, it, chunk):
        try:
            if isinstance(it, DECLS):
                self.define(it, chunk)
            else:
                self.statement(it, chunk)
            return True
        except (TomatoError, TomatoRaise, RecursionError, ZeroDivisionError, OverflowError) as e:
            return self.fail(e)
        except (BreakLoop, ContinueLoop, Return):
            return self.fail(TomatoError("break, continue and return belong inside a loop or a function"))

    def fail(self, e):
        self.out.flush()
        if isinstance(e, TomatoRaise):
            text = "uncaught error %s: %s" % (e.value.cls.name, e.value.fields.get("message", ""))
        elif isinstance(e, RecursionError):
            text = "recursion went too deep"
        else:
            text = str(e)
        print("error: " + text, file=self.err)
        return False

    def define(self, it, chunk):
        interp = self.interp
        names = [getattr(it, "name", None)]
        if isinstance(it, N.Import):
            names = []
        for name in names:                       # entering a definition again replaces it
            key = interp.scope["main"].get(name)
            if key is not None and key not in interp.scope["builtin"].values():
                for table in (interp.funcs, interp.classes, interp.ifaces):
                    table.pop(key, None)
                interp.scope["main"].pop(name, None)
                interp.entries = {k: v for k, v in getattr(interp, "entries", {}).items() if v.name != name}
        before = (dict(interp.funcs), dict(interp.classes), dict(interp.ifaces), {k: dict(v) for k, v in interp.scope.items()})
        try:
            interp.load(N.Module([it], line=1), "main")
            self.recheck()
        except Exception:
            interp.funcs, interp.classes, interp.ifaces = before[0], before[1], before[2]
            interp.scope = before[3]
            raise
        label = getattr(it, "name", None) or "import %s" % getattr(it, "module", chunk)
        self.defs.pop(label, None)
        self.defs[label] = chunk

    def recheck(self):
        checker = Checker(self.interp)
        checker.run()

    def statement(self, s, chunk):
        interp = self.interp
        glob = interp.globals
        if isinstance(s, N.Declare) and s.name in glob.vars:
            del glob.vars[s.name]                # `x: int = 3` again starts x over
        self.check_statement(s)
        if isinstance(s, N.ExprStmt):
            value = interp.eval(s.expr, glob)
            if value is not None:
                print(show_item(value), file=self.out)
            else:
                self.stmts.append(chunk)          # a call that did something (print, a method) is part of the program
            return
        interp.exec_stmt(s, glob)
        self.stmts.append(chunk)

    def check_statement(self, s):
        """The checks of a program, made before the line runs (D40a), with the variables set so far."""
        checker = Checker(self.interp)
        env = {name: (entry[0], True) for name, entry in self.interp.globals.vars.items()}

        class Top:
            ret = NoneT
        checker.fi = Top
        saved, self.interp.cur_mod = self.interp.cur_mod, "main"
        try:
            checker.stmt(s, env)
        finally:
            self.interp.cur_mod = saved

    # ------------------------------------------------------------------ the session as a program
    def program(self):
        """Definitions, then the statements: top-level code is a program by itself (D42a)."""
        return "\n\n".join(self.defs.values()) + ("\n\n" if self.defs else "") + "\n".join(self.stmts) + "\n"

    # ------------------------------------------------------------------ commands
    def command(self, line):
        word, _, rest = line[1:].strip().partition(" ")
        rest = rest.strip()
        if word in ("quit", "q", "exit"):
            return "quit"
        if word == "help":
            print(HELP, file=self.out)
        elif word == "vars":
            vars_ = self.interp.globals.vars
            for name in vars_:
                t, v = vars_[name]
                print("%s: %r = %s" % (name, t, show_item(v)), file=self.out)
            if not vars_:
                print("no variables yet", file=self.out)
        elif word == "defs":
            for label in self.defs:
                print(label, file=self.out)
            if not self.defs:
                print("no definitions yet", file=self.out)
        elif word == "reset":
            self.reset()
            print("session cleared", file=self.out)
        elif word == "program":
            print(self.program(), end="", file=self.out)
        elif word == "save":
            if not rest:
                print("error: :save needs a file name", file=self.err)
            else:
                self.write(rest, self.program())
        elif word == "compile":
            self.compile(rest or "session.ll")
        elif word == "run":
            self.run_native()
        elif word == "load":
            self.load(rest)
        else:
            print("error: unknown command :%s (try :help)" % word, file=self.err)

    def write(self, path, text):
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        except OSError as e:
            return print("error: cannot write %s: %s" % (path, e.strerror), file=self.err)
        print("wrote %s" % path, file=self.out)

    def load(self, path):
        if not path:
            return print("error: :load needs a file name", file=self.err)
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            return print("error: cannot read %s: %s" % (path, e.strerror), file=self.err)
        folder = os.path.dirname(os.path.abspath(path))
        if folder not in self.interp.search:
            self.interp.search.append(folder)
        if self.feed(text):
            print("loaded %s" % path, file=self.out)

    def compiled(self):
        try:
            return compile_to_ir(self.program(), "main", self.interp.search)
        except TomatoError as e:
            self.fail(e)

    def compile(self, path):
        ir = self.compiled()
        if ir is not None:
            self.write(path, ir)

    def run_native(self):
        clang = shutil.which("clang")
        if not clang:
            return print("error: :run needs clang on the PATH", file=self.err)
        ir = self.compiled()
        if ir is None:
            return
        runtime = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runtime", "tomato_rt.c")
        with tempfile.TemporaryDirectory() as d:
            ll, exe = os.path.join(d, "session.ll"), os.path.join(d, "session")
            with open(ll, "w", encoding="utf-8") as f:
                f.write(ir)
            r = subprocess.run([clang, "-O1", "-Wno-override-module", "-x", "ir", ll, "-x", "c", runtime, "-lm", "-o", exe],
                               capture_output=True, text=True)
            if r.returncode != 0:
                return print("error: clang failed:\n%s" % r.stderr.strip(), file=self.err)
            self.out.flush()
            r = subprocess.run([exe], capture_output=True, text=True)
            self.out.write(r.stdout)
            self.out.flush()
            if r.stderr:
                self.err.write(r.stderr)
            print("(native run finished with exit status %d)" % r.returncode, file=self.out)


def needs_more(text):
    """Whether the lines typed so far are the start of a block that the user has not finished."""
    first = text.split("\n")[0].rstrip()
    if first.startswith("@") or first.endswith(":"):
        return True
    depth = 0
    for ch in text:
        depth += ch in "([{"
        depth -= ch in ")]}"
    return depth > 0


def read_piece(read, prompt=">>> ", more="... "):
    """One command, statement or block. A block ends with an empty line."""
    line = read(prompt)
    if line.strip() == "" or line.startswith(":"):
        return line
    text = line
    while needs_more(text):
        nxt = read(more)
        if nxt.strip() == "":
            break
        text += "\n" + nxt
    return text


def main(argv):
    """tomato repl [FILE ...]: files given are loaded first, so their definitions and variables are already set."""
    from . import __version__
    session = Session()
    interactive = sys.stdin.isatty()
    if interactive:
        try:
            import readline  # noqa: F401  (gives line editing and history)
        except ImportError:
            pass
        print("Tomato v%s repl. :help for commands, :quit or Ctrl-D to leave." % __version__)
    for path in argv:
        session.load(path)

    def read(prompt):
        return input(prompt if interactive else "")

    while True:
        try:
            text = read_piece(read)
        except EOFError:
            if interactive:
                print()
            return 0
        except KeyboardInterrupt:
            print("\n(interrupted)")
            continue
        if text.strip() == "":
            continue
        try:
            if text.startswith(":"):
                if session.command(text.strip()) == "quit":
                    return 0
            else:
                session.feed(text if text.endswith("\n") else text + "\n")
        except KeyboardInterrupt:
            print("\n(interrupted)")
        sys.stdout.flush()
