"""The Tomato lexer in selfhost/lexer.tom must produce the same tokens as the Python lexer (D38a)."""
import glob
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from tomato.interp import run_source  # noqa: E402
from tomato.lexer import lex  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")


def python_tokens(src):
    out = []
    for t in lex(src):
        if t.kind == "INT":
            out.append("INT %d %d" % (t.value, t.line))
        else:
            out.append("%s %s %d" % (t.kind, (t.value or "").replace("\n", "\\n"), t.line))
    return out


class SelfhostLexer(unittest.TestCase):
    def tomato_tokens(self, path):
        out = io.StringIO()
        run_source(open(os.path.join(ROOT, "selfhost", "lexer.tom")).read(), out, entry="show", inputs=[path])
        return out.getvalue().split("\n")[:-1]

    def test_same_tokens_as_the_python_lexer(self):
        files = sorted(glob.glob(os.path.join(ROOT, "examples", "*.tom")) + glob.glob(os.path.join(ROOT, "tomato", "std", "*.tom"))
                       + glob.glob(os.path.join(ROOT, "selfhost", "*.tom")))
        self.assertTrue(files)
        for path in files:
            with self.subTest(path=os.path.basename(path)):
                expected = python_tokens(open(path).read())
                self.assertEqual(self.tomato_tokens(path), expected)


if __name__ == "__main__":
    unittest.main()
