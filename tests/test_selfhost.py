"""The Tomato lexer in compiler/src/lexer.tom (used through compiler/src/lextool.tom) must produce the same tokens as the Python lexer (D38a)."""
import glob
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))
os.environ["PYTHONPATH"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python")
from tomato.interp import run_source  # noqa: E402
from tomato.lexer import lex  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")


def python_tokens(src):
    out = []
    for t in lex(src):
        if t.kind == "INT":
            out.append("INT %d %d" % (t.value, t.line))
        else:
            out.append("%s %s %d" % (t.kind, (t.value or "").replace("\n", "\\n").replace("\r", "\\r"), t.line))
    return out


class SelfhostLexer(unittest.TestCase):
    def tomato_tokens(self, path):
        out = io.StringIO()
        run_source(open(os.path.join(ROOT, "compiler", "src", "lextool.tom")).read(), out, entry="show", inputs=[path],
                   search=[os.path.join(ROOT, "compiler", "src")])
        return out.getvalue().split("\n")[:-1]

    def test_same_tokens_as_the_python_lexer(self):
        files = sorted(glob.glob(os.path.join(ROOT, "examples", "*.tom")) + glob.glob(os.path.join(ROOT, "python", "tomato", "std", "*.tom"))
                       + glob.glob(os.path.join(ROOT, "compiler", "src", "*.tom")))
        self.assertTrue(files)
        for path in files:
            with self.subTest(path=os.path.basename(path)):
                expected = python_tokens(open(path).read())
                self.assertEqual(self.tomato_tokens(path), expected)

    def test_compiled_lexer_matches_too(self):
        """Stage 1 (D38a): the Python compiler builds the Tomato lexer, and the native program gives the same tokens."""
        import shutil
        import subprocess
        import tempfile
        if not shutil.which("clang"):
            self.skipTest("clang is not installed")
        exe = os.path.join(tempfile.mkdtemp(), "lexer")
        subprocess.run([sys.executable, "-m", "tomato", "build", os.path.join(ROOT, "compiler", "src", "lextool.tom"),
                        "--entry", "show", "-o", exe], cwd=ROOT, check=True, capture_output=True)
        for path in sorted(glob.glob(os.path.join(ROOT, "examples", "*.tom")) + glob.glob(os.path.join(ROOT, "compiler", "src", "*.tom"))):
            with self.subTest(path=os.path.basename(path)):
                out = subprocess.run([exe, path], check=True, capture_output=True, text=True).stdout.split("\n")[:-1]
                self.assertEqual(out, python_tokens(open(path).read()))


if __name__ == "__main__":
    unittest.main()
