"""server/compile_server.py: request checks and run limits (needs clang; builds nothing — it uses the checked-in IR)."""
import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "server"))
import compile_server as cs  # noqa: E402


class WebServer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("clang"):
            raise unittest.SkipTest("clang is not installed")
        if not shutil.which("sandbox-exec") or not shutil.which("bash"):
            raise unittest.SkipTest("sandbox-exec (macOS) is not available")
        cls.build = tempfile.mkdtemp()
        cs.STAGE2 = os.path.join(cls.build, "stage2")
        subprocess.run(["clang", "-O1", "-Wno-override-module", "-o", cs.STAGE2, os.path.join(ROOT, "compiler", "bootstrap", "tomatoc.ll"),
                        cs.RUNTIME, "-lm"], check=True, capture_output=True)
        cls.server = cs.ThreadingHTTPServer(("127.0.0.1", 0), cs.Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def post(self, body, headers=None, host=None):
        h = {"Content-Type": "application/json"}
        h.update(headers or {})
        if host:
            h["Host"] = host
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=60)
        c.request("POST", "/run", body if isinstance(body, str) else json.dumps(body), h)
        r = c.getresponse()
        return r.status, r.read().decode()

    def test_runs_a_program(self):
        st, body = self.post({"source": "@main\ndef main():\n    print(6 * 7)\n"})
        self.assertEqual(st, 200)
        self.assertEqual(json.loads(body)["stdout"], "42\n")

    def test_rejects_cross_site_requests(self):
        src = {"source": "@main\ndef main():\n    print(1)\n"}
        self.assertEqual(self.post(src, {"Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.post(src, {"Origin": "http://evil.example"})[0], 403)
        self.assertEqual(self.post(src, host="evil.example")[0], 403)

    def test_bad_content_length(self):
        self.assertEqual(self.post("{}", {"Content-Length": "abc"})[0], 400)

    def test_output_is_capped(self):
        src = "@main\ndef main():\n    i = 0\n    while True:\n        print('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')\n        i = i + 1\n"
        st, body = self.post({"source": src})
        out = json.loads(body)
        self.assertLessEqual(len(out["stdout"]), cs.MAX_OUTPUT + 100)
        self.assertEqual(out["stopped"], "output")

    def test_oversized_body_is_refused(self):
        self.assertEqual(self.post("x" * (cs.MAX_SOURCE * 2 + 10))[0], 413)

    def test_tailnet_host_is_accepted(self):
        src = {"source": "@main\ndef main():\n    print(1)\n"}
        self.assertEqual(self.post(src, host="some-mac.tailnet.ts.net:49212",
                                   headers={"Origin": "http://some-mac.tailnet.ts.net:49212"})[0], 200)

    def test_program_cannot_write_outside_its_directory(self):
        target = os.path.join(tempfile.gettempdir(), "tomato-sandbox-probe")
        if os.path.exists(target):
            os.remove(target)
        src = ("@main\ndef main():\n    try:\n        f = open('%s', 'w')\n        f.write('x')\n"
               "        f.close()\n        print('wrote')\n    catch IOError:\n        print('denied')\n" % target)
        out = json.loads(self.post({"source": src})[1])
        self.assertEqual(out.get("stdout"), "denied\n", out)
        self.assertFalse(os.path.exists(target))

    def test_program_cannot_read_user_files(self):
        secret = os.path.join(os.path.expanduser("~"), ".tomato-sandbox-probe")
        with open(secret, "w") as f:
            f.write("secret")
        try:
            src = ("@main\ndef main():\n    try:\n        f = open('%s', 'r')\n        print('read')\n"
                   "    catch IOError:\n        print('denied')\n" % secret)
            out = json.loads(self.post({"source": src})[1])
            self.assertEqual(out.get("stdout"), "denied\n", out)
        finally:
            os.remove(secret)

    def test_non_object_body_is_a_400(self):
        self.assertEqual(self.post("[1, 2]")[0], 400)
        self.assertEqual(self.post({"source": "x", "inputs": "abc"})[0], 400)

    def test_program_cannot_signal_other_processes(self):
        src = ("!getppid() -> int\n!kill(pid: int, sig: int) -> int\n\n@main\ndef main():\n"
               "    print(!kill(!getppid(), 0))\n")
        out = json.loads(self.post({"source": src})[1])
        self.assertEqual(out.get("stdout"), "-1\n", out)

    def test_programs_cannot_read_each_others_directories(self):
        src = ("@main\ndef main():\n    try:\n        f = open('%s', 'r')\n        print('read')\n"
               "    catch IOError:\n        print('denied')\n" % os.path.join(tempfile.gettempdir(), "tomato-probe-other"))
        with open(os.path.join(tempfile.gettempdir(), "tomato-probe-other"), "w") as f:
            f.write("x")
        try:
            out = json.loads(self.post({"source": src})[1])
            self.assertEqual(out.get("stdout"), "denied\n", out)
        finally:
            os.remove(os.path.join(tempfile.gettempdir(), "tomato-probe-other"))

    def test_programs_cannot_read_tmp(self):
        probe = "/private/tmp/tomato-probe-tmp"
        with open(probe, "w") as f:
            f.write("x")
        try:
            src = ("@main\ndef main():\n    try:\n        f = open('%s', 'r')\n        print('read')\n"
                   "    catch IOError:\n        print('denied')\n" % probe)
            self.assertEqual(json.loads(self.post({"source": src})[1]).get("stdout"), "denied\n")
        finally:
            os.remove(probe)

    def test_bare_ipv6_loopback_host(self):
        src = {"source": "@main\ndef main():\n    print(1)\n"}
        self.assertEqual(self.post(src, host="[::1]")[0], 200)

    def test_allowed_origin_gets_cors(self):
        cs.ALLOWED_ORIGINS.add("https://tomato.example")
        try:
            src = {"source": "@main\ndef main():\n    print(1)\n"}
            c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=60)
            c.request("OPTIONS", "/run", headers={"Origin": "https://tomato.example"})
            r = c.getresponse()
            r.read()
            self.assertEqual((r.status, r.getheader("Access-Control-Allow-Origin")), (204, "https://tomato.example"))
            self.assertEqual(self.post(src, {"Origin": "https://tomato.example"})[0], 200)
        finally:
            cs.ALLOWED_ORIGINS.discard("https://tomato.example")

    def test_top_level_code_runs(self):
        src = "def sq(n: int) -> int:\n    return n * n\n\nx = 3\nprint(sq(x))\n"
        self.assertEqual(json.loads(self.post({"source": src})[1])["stdout"], "9\n")

    def test_nul_byte_in_inputs_is_a_400(self):
        self.assertEqual(self.post({"source": "x", "inputs": ["a\u0000b"]})[0], 400)

    def test_compile_step_memory_cap(self):
        old = cs.MAX_MEMORY_KB
        cs.MAX_MEMORY_KB = 1          # any running process is over this
        try:
            with self.assertRaises(cs.StepOutOfMemory):
                cs.run_group(["sleep", "5"], 10)
        finally:
            cs.MAX_MEMORY_KB = old

    def test_memory_cap(self):
        old = cs.MAX_MEMORY_KB
        cs.MAX_MEMORY_KB = 200 * 1024
        try:
            src = "@main\ndef main():\n    xs = new_list()\n    while True:\n        xs.append(1)\n\ndef new_list() -> list[int]:\n    return []\n"
            out = json.loads(self.post({"source": src})[1])
            self.assertIn(out.get("stopped"), ("memory", "time"), out)
        finally:
            cs.MAX_MEMORY_KB = old

    def test_cpu_limit(self):
        src = "@main\ndef main():\n    while True:\n        pass\n"
        out = json.loads(self.post({"source": src})[1])
        self.assertTrue(out["timed_out"])


if __name__ == "__main__":
    unittest.main()
