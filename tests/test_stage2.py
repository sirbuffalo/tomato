"""Self-hosting (D38a): the Tomato compiler compiles itself, and the result reaches a fixed point.

stage 1: the Python compiler builds selfhost/ctool.tom (the Tomato compiler) into a native program;
stage 2: stage 1 compiles the Tomato compiler's own source to IR, clang builds that into a program;
stage 3: stage 2 compiles the same source again. The IR from stages 1 and 2 must be identical, and stage 2
must compile a sample program that behaves like the interpreter.
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from tomato.interp import run_source  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SELF = os.path.join(ROOT, "selfhost")
RUNTIME = os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c")

SAMPLE = """
class Counter:
    n: int = 0
    names: dict[str, int] = {}

    def bump(self, key: str, by: int = 1):
        self.n = self.n + by
        self.names[key] = self.n

def describe(c: Counter, words: list[str]) -> str:
    out = ''
    for w in words:
        if w in c.names:
            out = out + w + '=' + str(c.names[w]) + ' '
    return out

@main
def main():
    c = Counter()
    c.bump('a')
    c.bump('b', 5)
    print(describe(c, ['a', 'x', 'b']), c.n, len(c.names))
"""


class StageTwo(unittest.TestCase):
    def test_the_tomato_compiler_compiles_itself(self):
        if not shutil.which("clang"):
            self.skipTest("clang is not installed")
        d = tempfile.mkdtemp()
        stage1 = os.path.join(d, "stage1")
        subprocess.run([sys.executable, "-m", "tomato", "build", os.path.join(SELF, "ctool.tom"), "--entry", "compile",
                        "-o", stage1], cwd=ROOT, check=True, capture_output=True)
        ctool = os.path.join(SELF, "ctool.tom")
        ir2 = subprocess.run([stage1, ctool, "compile"], check=True, capture_output=True, text=True)
        self.assertEqual(ir2.stderr, "")
        self.assertIn("define i32 @main(i32 %argc, ptr %argv)", ir2.stdout)
        ll2 = os.path.join(d, "stage2.ll")
        with open(ll2, "w") as f:
            f.write(ir2.stdout)
        stage2 = os.path.join(d, "stage2")
        subprocess.run(["clang", "-Wno-override-module", "-o", stage2, ll2, RUNTIME, "-lm"], check=True, capture_output=True)
        ir3 = subprocess.run([stage2, ctool, "compile"], check=True, capture_output=True, text=True)
        self.assertEqual(ir3.stderr, "")
        self.assertEqual(ir3.stdout, ir2.stdout, "stage 2 does not compile itself to the same IR (no fixed point)")
        # the IR checked in under bootstrap/ is exactly what the compiler writes for itself
        with open(os.path.join(ROOT, "bootstrap", "tomatoc.ll")) as f:
            self.assertEqual(f.read(), ir3.stdout, "bootstrap/tomatoc.ll is out of date: run bootstrap/refresh.sh")
        # the compiler built by itself compiles a sample program that behaves like the interpreter
        sample = os.path.join(d, "sample.tom")
        with open(sample, "w") as f:
            f.write(SAMPLE)
        ir = subprocess.run([stage2, sample, "main"], check=True, capture_output=True, text=True)
        ll = os.path.join(d, "sample.ll")
        with open(ll, "w") as f:
            f.write(ir.stdout)
        exe = os.path.join(d, "sample")
        subprocess.run(["clang", "-Wno-override-module", "-o", exe, ll, RUNTIME, "-lm"], check=True, capture_output=True)
        run = subprocess.run([exe], check=True, capture_output=True, text=True)
        out = io.StringIO()
        run_source(SAMPLE, out)
        self.assertEqual(run.stderr, "")
        self.assertEqual(run.stdout, out.getvalue())


if __name__ == "__main__":
    unittest.main()
