"""The `tomato` command line (D28a, D30a, P35):
  tomato run FILE [ENTRY [INPUTS...]] [--llvm FILE.ll ...]   run a program with the interpreter
  tomato compile FILE [-o OUT.ll] [--entry NAME]             compile to LLVM IR
  tomato build FILE [-o OUT] [--entry NAME]                  compile to IR, then link a native program with clang
  (compile and build also take --mode debug|normal|release; tomato explain CODE FILE decodes a normal-mode code)
  tomato bundle FILE [-o OUT] [--llvm FILE.ll ...]           one executable holding the program and the interpreter
"""
import os
import sys
import threading

from .bundle import compile_program
from .codegen import compile_to_ir
from .errors import TomatoError
from .interp import run_source

ENTRY_FLAG, MODE_FLAG = None, "debug"

USAGE = """usage: tomato run FILE [ENTRY [INPUTS...]] [--llvm FILE.ll ...]
       tomato compile FILE [-o OUT.ll] [--entry NAME] [--mode debug|normal|release]
       tomato build FILE [-o OUT] [--entry NAME] [--mode debug|normal|release] [--llvm FILE.ll ...]
       tomato explain CODE FILE
       tomato bundle FILE [-o OUT] [--llvm FILE.ll ...]

  FILE     the Tomato program
  ENTRY    the entry point to run, written without the @ (default: main)
  INPUTS   values for the entry point's parameters, in order
  --llvm   LLVM IR that `!name(...)` calls can use when running (needs llvmlite)
  compile  checks FILE and writes LLVM IR (default OUT: FILE with .ll). LLVM's tools turn that into any target.
           Only a core subset compiles so far; the rest stops with "the compiler does not support ... yet".
  build    compile, then link a native program with clang and the C runtime (and any --llvm IR files, which
           define the `!name` functions the program declares); run it as: ./OUT [INPUTS...]
  explain  turns an error code printed by a normal-mode program, such as E03:12, into the full message and the
           source line it came from; give it the same FILE the program was built from
  --mode   how a compiled program reports errors: debug (full messages, the default), normal (short codes
           for `explain`) or release (nothing readable)
  bundle   checks FILE and writes one executable that holds the program and the Python interpreter (not native);
           run it as: ./OUT [ENTRY [INPUTS...]]"""



def read_args(argv):
    """Split argv into positional words, --llvm IR files, -o OUT and --entry NAME."""
    args, llvm_ir, out, k = [], [], None, 1
    global ENTRY_FLAG, MODE_FLAG
    ENTRY_FLAG, MODE_FLAG = None, "debug"
    while k < len(argv):
        if argv[k] == "--llvm" and k + 1 < len(argv):
            with open(argv[k + 1], encoding="utf-8") as f:
                llvm_ir.append((argv[k + 1], f.read()))
            k += 2
        elif argv[k] == "-o" and k + 1 < len(argv):
            out = argv[k + 1]
            k += 2
        elif argv[k] == "--entry" and k + 1 < len(argv):
            ENTRY_FLAG = argv[k + 1]
            k += 2
        elif argv[k] == "--mode" and k + 1 < len(argv):
            MODE_FLAG = argv[k + 1]
            k += 2
        else:
            args.append(argv[k])
            k += 1
    return args, llvm_ir, out


def main(argv):
    try:
        args, llvm_ir, out = read_args(argv)
    except OSError as err:
        print("error: cannot read %s: %s" % (err.filename, err.strerror), file=sys.stderr)
        return 1
    cmd = args[0] if args else None
    if cmd == "explain":
        return explain_code(args[1:])
    if len(args) < 2 or cmd not in ("run", "compile", "build", "bundle") or (cmd != "run" and len(args) != 2) \
            or (cmd == "run" and (out or ENTRY_FLAG)) or (cmd == "compile" and llvm_ir):
        print(USAGE, file=sys.stderr)
        return 2
    path = args[1]
    try:
        with open(path, encoding="utf-8") as f:
            src = f.read()
    except OSError as err:
        print("error: cannot read %s: %s" % (path, err.strerror), file=sys.stderr)
        return 1
    search = [os.path.dirname(os.path.abspath(path))]
    base = path[:-4] if path.endswith(".tom") else path
    try:
        if cmd == "bundle":
            target = out or base
            mods = compile_program(src, target, search=search, llvm_ir=llvm_ir)
            print("wrote %s%s" % (target, " (bundles modules: %s)" % ", ".join(mods) if mods else ""))
        elif cmd == "compile":
            target = out or base + ".ll"
            with open(target, "w", encoding="utf-8") as f:
                f.write(compile_to_ir(src, ENTRY_FLAG or "main", search, MODE_FLAG))
            print("wrote %s" % target)
        elif cmd == "build":
            return build_native(src, out or base, ENTRY_FLAG or "main", search, MODE_FLAG, llvm_ir)
        else:
            entry, inputs = (args[2] if len(args) > 2 else "main"), args[3:]
            run_source(src, entry=entry, llvm_ir=llvm_ir, inputs=inputs, search=search)
    except TomatoError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    return 0


def explain_code(args):
    from .errcodes import explain
    if len(args) != 2:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        with open(args[1], encoding="utf-8") as f:
            print(explain(args[0], f.read()))
    except OSError as err:
        print("error: cannot read %s: %s" % (args[1], err.strerror), file=sys.stderr)
        return 1
    except ValueError as err:
        print("error: %s" % err, file=sys.stderr)
        return 1
    return 0


def build_native(src, target, entry, search, mode="debug", extra_ir=()):
    """Compile to IR in a temporary folder and link it with the C runtime using clang."""
    import shutil
    import subprocess
    import tempfile
    clang = shutil.which("clang")
    if not clang:
        print("error: tomato build needs clang on the PATH", file=sys.stderr)
        return 1
    ir = compile_to_ir(src, entry, search, mode)
    runtime = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runtime", "tomato_rt.c")
    with tempfile.TemporaryDirectory() as d:
        ll = os.path.join(d, "program.ll")
        with open(ll, "w", encoding="utf-8") as f:
            f.write(ir)
        inputs = [ll]
        for k, (label, text) in enumerate(extra_ir):     # LLVM IR given with --llvm is linked in (D27)
            path = os.path.join(d, "extra%d.ll" % k)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            inputs.append(path)
        r = subprocess.run([clang, "-O1", "-Wno-override-module", "-x", "ir"] + inputs + ["-x", "c", runtime, "-lm",
                            "-o", target], capture_output=True, text=True)
    if r.returncode != 0:
        print("error: clang failed:\n%s" % r.stderr.strip(), file=sys.stderr)
        return 1
    print("wrote %s" % target)
    return 0


def run_bundle(data, argv):
    """Entry point of a file written by `tomato compile`: ./OUT [ENTRY [INPUTS...]]."""
    sys.setrecursionlimit(500000)
    threading.stack_size(512 * 1024 * 1024)
    result = []

    def go():
        entry, inputs = (argv[1] if len(argv) > 1 else "main"), argv[2:]
        try:
            run_source(data["program"], entry=entry, modules=data["modules"], inputs=inputs,
                       llvm_ir=[tuple(x) for x in data["llvm_ir"]] or None)
            result.append(0)
        except TomatoError as e:
            print("error: %s" % e, file=sys.stderr)
            result.append(1)

    t = threading.Thread(target=go)
    t.start()
    t.join()
    return result[0] if result else 1


def main_big_stack(argv):
    """Run on a thread with a large stack so deep Tomato recursion does not overflow the host."""
    sys.setrecursionlimit(500000)
    threading.stack_size(512 * 1024 * 1024)
    result = []
    t = threading.Thread(target=lambda: result.append(main(argv)))
    t.start()
    t.join()
    return result[0] if result else 1


if __name__ == "__main__":
    sys.exit(main_big_stack(sys.argv))
