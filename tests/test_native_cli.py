"""The `tomato` command built on the Tomato compiler (install-native.sh, native/tomato): it needs only clang."""
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class NativeCli(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("clang"):
            raise unittest.SkipTest("clang is not installed")
        cls.home = tempfile.mkdtemp()
        env = dict(os.environ, TOMATO_HOME=os.path.join(cls.home, "t"), TOMATO_BIN=os.path.join(cls.home, "bin"))
        subprocess.run([os.path.join(ROOT, "install-native.sh")], check=True, capture_output=True, env=env)
        cls.tomato = os.path.join(cls.home, "bin", "tomato")

    def run_cli(self, *args):
        return subprocess.run([self.tomato] + list(args), capture_output=True, text=True)

    def example(self, name):
        return os.path.join(ROOT, "examples", name)

    def test_run_with_entry_and_inputs(self):
        r = self.run_cli("run", self.example("args.tom"), "prime", "17")
        self.assertEqual((r.returncode, r.stdout), (0, "17 True\n"))
        r = self.run_cli("run", self.example("args.tom"), "greet", "bob", "2", "true")
        self.assertEqual(r.stdout, "BOB\nBOB\n")
        r = self.run_cli("run", self.example("compiled.tom"), "main", "12")
        self.assertIn("fib 12 = 144", r.stdout)

    def test_build_and_compile(self):
        out = os.path.join(self.home, "objects")
        r = self.run_cli("build", self.example("objects.tom"), "-o", out)
        self.assertEqual(r.returncode, 0, r.stderr)
        run = subprocess.run([out, "4"], capture_output=True, text=True)
        self.assertIn("item3x6", run.stdout)
        r = self.run_cli("compile", self.example("shapes.tom"))
        self.assertIn("define i32 @main", r.stdout)

    def test_llvm_functions(self):
        r = self.run_cli("run", self.example("mathlib.tom"), "main", "--llvm", self.example("mathlib.ll"))
        self.assertEqual(r.stdout, "1.4142135623730951\n42\nTrue False\n1000000000\n", r.stderr)

    def test_errors_name_the_line(self):
        bad = os.path.join(self.home, "bad.tom")
        with open(bad, "w") as f:
            f.write("@main\ndef main():\n    print(1 + 'a')\n")
        r = self.run_cli("run", bad)
        self.assertEqual(r.returncode, 1)
        self.assertIn("CompileError on line 3: type error", r.stderr)

    def test_inputs_keep_globs_and_empty_words(self):
        prog = os.path.join(self.home, "echo.tom")
        with open(prog, "w") as f:
            f.write("@main\ndef main(a: str, b: str):\n    print('[' + a + '][' + b + ']')\n")
        cwd = tempfile.mkdtemp()
        for n in ("zz1", "zz2"):
            open(os.path.join(cwd, n), "w").close()
        r = subprocess.run([self.tomato, "run", prog, "main", "*", ""], capture_output=True, text=True, cwd=cwd)
        self.assertEqual((r.returncode, r.stdout), (0, "[*][]\n"), r.stderr)
        r = subprocess.run([self.tomato, "run", prog, "main", "a b", "z?"], capture_output=True, text=True, cwd=cwd)
        self.assertEqual(r.stdout, "[a b][z?]\n")

    def test_double_dash_passes_flag_like_inputs(self):
        prog = os.path.join(self.home, "echo2.tom")
        with open(prog, "w") as f:
            f.write("@main\ndef main(a: str, b: str):\n    print('[' + a + '][' + b + ']')\n")
        r = self.run_cli("run", prog, "--", "main", "-o", "--entry")
        self.assertEqual((r.returncode, r.stdout), (0, "[-o][--entry]\n"), r.stderr)

    def test_symlinked_install(self):
        link = os.path.join(self.home, "linked-tomato")
        os.symlink(self.tomato, link)
        r = subprocess.run([link, "version"], capture_output=True, text=True)
        self.assertEqual(r.stdout, "Tomato v%s (compiler written in Tomato)\n" % open(os.path.join(ROOT, "VERSION")).read().strip())

    def test_unknown_command_is_an_error(self):
        r = self.run_cli("wghwrltghs")
        self.assertEqual(r.returncode, 2)
        self.assertIn("error: unknown command 'wghwrltghs'", r.stderr)
        r = self.run_cli("help")
        self.assertEqual(r.returncode, 0)
        for word in ("run", "build", "compile", "repl", "update", "version"):
            self.assertIn("tomato " + word, r.stdout)

    def test_repl_needs_no_python(self):
        piece = "x = 3\nx + 4\ndef sq(n: int) -> int:\n    return n * n\n\nsq(x)\nprint('hi')\n:quit\n"
        env = dict(os.environ, PATH=os.path.dirname(shutil.which("clang")) + ":/usr/bin:/bin")   # no tomato-py on the PATH
        r = subprocess.run([self.tomato, "repl"], input=piece, capture_output=True, text=True, env=env)
        self.assertEqual((r.returncode, r.stdout), (0, "7\n9\nhi\n"), r.stderr)

    def test_repl_leave_and_exit(self):
        for word in ("leave()", "exit()", "quit()"):
            r = subprocess.run([self.tomato, "repl"], input="print('a')\n%s\nprint('b')\n" % word, capture_output=True, text=True)
            self.assertEqual((r.returncode, r.stdout), (0, "a\n"), word)

    def test_usage(self):
        self.assertEqual(self.run_cli().returncode, 2)
        self.assertEqual(self.run_cli("version").stdout, "Tomato v%s (compiler written in Tomato)\n" % open(os.path.join(ROOT, "VERSION")).read().strip())


if __name__ == "__main__":
    unittest.main()
