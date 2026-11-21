"""`tomato compile`: write one standalone executable file for a Tomato program.

PROVISIONAL (P35): the file is a Python zip application holding the checked program, every module it imports, any
LLVM IR given with --llvm, and the interpreter. It is not native code yet; native LLVM compilation is the later
Tomato-in-Tomato compiler. Run the result as `./OUT [ENTRY [INPUTS...]]`.
"""
import io
import json
import os
import stat
import sys
import zipfile

from .errors import TomatoError
from .interp import Interpreter

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = '''import sys
sys.path.insert(0, sys.argv[0])
import _program
from tomato.__main__ import run_bundle
sys.exit(run_bundle(_program.DATA, sys.argv))
'''


def compile_program(src, out_path, search=None, llvm_ir=None):
    """Check `src` and write the executable; returns the names of the modules bundled."""
    interp = Interpreter(search=search, llvm_ir=None)   # IR is only bundled here, not run
    interp.check(src)
    modules = {k: v for k, v in interp.module_text.items() if k != "builtin" and not _is_std(k)}
    data = {"program": src, "modules": modules, "llvm_ir": [[a, b] for a, b in (llvm_ir or [])]}
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("__main__.py", RUNNER)
        z.writestr("_program.py", "import json\nDATA = json.loads(%s)\n" % repr(json.dumps(data)))
        for root, _, files in os.walk(HERE):
            for f in sorted(files):
                if f.endswith((".py", ".tom")):
                    full = os.path.join(root, f)
                    z.write(full, os.path.join("tomato", os.path.relpath(full, HERE)))
    # A shell prefix, not a #! line, because the interpreter's path may contain spaces. Programs that call LLVM
    # need the Python that has llvmlite; others use whatever python3 is on the PATH.
    py = sys.executable if llvm_ir else "python3"
    prefix = "#!/bin/sh\nexec '%s' \"$0\" \"$@\"\n" % py.replace("'", "'\\''")
    with open(out_path, "wb") as f:
        f.write(prefix.encode() + buf.getvalue())
    os.chmod(out_path, os.stat(out_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return sorted(modules)


def _is_std(name):
    return os.path.isfile(os.path.join(HERE, "std", name + ".tom"))
