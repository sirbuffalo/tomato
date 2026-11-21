"""The Tomato parser in compiler/src/parser.tom must build the same tree as tomato/parser.py (D38a)."""
import glob
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))
os.environ["PYTHONPATH"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python")
from tomato.interp import run_source  # noqa: E402
from tomato.nodes import Node  # noqa: E402
from tomato.parser import parse  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SELF = os.path.join(ROOT, "compiler", "src")


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")


def dump(v):
    if isinstance(v, Node):
        s = "(%s %d" % (type(v).__name__, v.line)
        if getattr(v, "exported", False):
            s += " exported"
        for f in v._fields:
            s += " " + dump(getattr(v, f))
        return s + ")"
    if v is None:
        return "None"
    if isinstance(v, bool):
        return "True" if v else "False"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return '"' + esc(v) + '"'
    if isinstance(v, list):
        return "[" + " ".join(dump(x) for x in v) + "]"
    if isinstance(v, tuple):
        return "<" + " ".join(dump(x) for x in v) + ">"
    raise TypeError(v)


def files():
    return sorted(glob.glob(os.path.join(ROOT, "examples", "*.tom")) + glob.glob(os.path.join(ROOT, "python", "tomato", "std", "*.tom"))
                  + glob.glob(os.path.join(SELF, "*.tom")))


class SelfhostParser(unittest.TestCase):
    def test_same_tree_under_the_interpreter(self):
        src = open(os.path.join(SELF, "parsetool.tom")).read()
        for path in files():
            with self.subTest(path=os.path.basename(path)):
                out = io.StringIO()
                run_source(src, out, entry="show", inputs=[path], search=[SELF])
                self.assertEqual(out.getvalue().rstrip("\n"), dump(parse(open(path).read())))

    def test_same_tree_when_compiled(self):
        """Stage 1 (D38a): the Python compiler builds the Tomato parser; the native program gives the same tree."""
        if not shutil.which("clang"):
            self.skipTest("clang is not installed")
        exe = os.path.join(tempfile.mkdtemp(), "parser")
        subprocess.run([sys.executable, "-m", "tomato", "build", os.path.join(SELF, "parsetool.tom"), "--entry", "show",
                        "-o", exe], cwd=ROOT, check=True, capture_output=True)
        for path in files():
            with self.subTest(path=os.path.basename(path)):
                out = subprocess.run([exe, path], check=True, capture_output=True, text=True).stdout
                self.assertEqual(out.rstrip("\n"), dump(parse(open(path).read())))


if __name__ == "__main__":
    unittest.main()
