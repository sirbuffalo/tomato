"""A small web server that runs Tomato programs with the Tomato compiler written in Tomato (D38a).

    python3 web/compile_server.py [--port 49212]

On first start it builds the compiler in stages: the Python compiler builds selfhost/ctool.tom (stage 1), stage 1
compiles the compiler's own source, and clang builds that into stage 2. Every program the page sends is compiled by
stage 2, linked with the C runtime by clang, and run with a time, memory and output limit.

It runs code on this machine: it binds to 127.0.0.1 only, so put it behind a port forward you trust.
Python's standard library is used because Tomato has no networking yet.
"""
import argparse
import json
import os
import resource
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BUILD = os.path.join(ROOT, "build")
STAGE1 = os.path.join(BUILD, "stage1")
STAGE2 = os.path.join(BUILD, "stage2")
RUNTIME = os.path.join(ROOT, "tomato", "runtime", "tomato_rt.c")
PAGE = os.path.join(os.path.dirname(__file__), "compile.html")
COMPILE_SECONDS, RUN_SECONDS, MAX_OUTPUT, MAX_SOURCE = 60, 5, 64 * 1024, 100 * 1024
slots = threading.Semaphore(2)


def build_compiler():
    """Build stage 2 (the Tomato compiler compiled by itself) unless it is already newer than its sources."""
    os.makedirs(BUILD, exist_ok=True)
    sources = [os.path.join(ROOT, "selfhost", f) for f in os.listdir(os.path.join(ROOT, "selfhost")) if f.endswith(".tom")]
    sources.append(RUNTIME)
    newest = max(os.path.getmtime(p) for p in sources)
    if os.path.exists(STAGE2) and os.path.getmtime(STAGE2) > newest:
        return
    print("building the Tomato compiler (stage 1, then stage 2)...", flush=True)
    ctool = os.path.join(ROOT, "selfhost", "ctool.tom")
    subprocess.run([sys.executable, "-m", "tomato", "build", ctool, "--entry", "compile", "-o", STAGE1],
                   cwd=ROOT, check=True)
    ir = subprocess.run([STAGE1, ctool, "compile"], cwd=ROOT, check=True, capture_output=True, text=True).stdout
    with open(os.path.join(BUILD, "stage2.ll"), "w") as f:
        f.write(ir)
    subprocess.run(["clang", "-O1", "-Wno-override-module", "-o", STAGE2, os.path.join(BUILD, "stage2.ll"), RUNTIME, "-lm"],
                   check=True)
    print("compiler ready", flush=True)


def limits():
    resource.setrlimit(resource.RLIMIT_CPU, (RUN_SECONDS, RUN_SECONDS))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT * 4, MAX_OUTPUT * 4))
    try:
        resource.setrlimit(resource.RLIMIT_AS, (2 << 30, 2 << 30))
    except (ValueError, OSError):
        pass                                    # macOS does not enforce address-space limits
    os.setsid()


def run_program(source, entry, inputs):
    """Compile `source` with stage 2, link it, run it; returns a dict for the page."""
    started = time.time()
    work = tempfile.mkdtemp(prefix="tomato-web-")
    try:
        program = os.path.join(work, "program.tom")
        with open(program, "w", encoding="utf-8") as f:
            f.write(source)
        c = subprocess.run([STAGE2, program, entry], cwd=ROOT, capture_output=True, text=True, timeout=COMPILE_SECONDS)
        if c.returncode != 0:
            return {"ok": False, "stage": "compile", "error": tidy((c.stderr or c.stdout).strip()), "ms": ms(started)}
        ll = os.path.join(work, "program.ll")
        with open(ll, "w") as f:
            f.write(c.stdout)
        exe = os.path.join(work, "program")
        link = subprocess.run(["clang", "-O1", "-Wno-override-module", "-o", exe, ll, RUNTIME, "-lm"],
                              capture_output=True, text=True, timeout=COMPILE_SECONDS)
        if link.returncode != 0:
            return {"ok": False, "stage": "link", "error": link.stderr.strip()[:4000], "ir": c.stdout, "ms": ms(started)}
        try:
            r = subprocess.run([exe] + inputs, cwd=work, capture_output=True, timeout=RUN_SECONDS + 2, preexec_fn=limits)
            out, err, code = r.stdout, r.stderr, r.returncode
            timed_out = code == -signal.SIGXCPU          # the CPU limit ended it
        except subprocess.TimeoutExpired as e:
            out, err, code, timed_out = e.stdout or b"", e.stderr or b"", None, True
        return {"ok": True, "stage": "run", "stdout": clip(out), "stderr": clip(err), "exit": code, "timed_out": timed_out,
                "ir": c.stdout, "ms": ms(started)}
    except subprocess.TimeoutExpired:
        return {"ok": False, "stage": "compile", "error": "the compiler took too long", "ms": ms(started)}
    finally:
        shutil.rmtree(work, ignore_errors=True)


def tidy(message):
    """The compiler reports an error as `error: line N: uncaught error Kind: text`; show it as `Kind: text (line N)`."""
    import re
    m = re.match(r"error: line \d+: uncaught error (\w+): line (\d+): (.*)$", message, re.S)
    if m:
        return "%s on line %s: %s" % (m.group(1), m.group(2), m.group(3))
    m = re.match(r"error: line \d+: uncaught error (\w+): (.*)$", message, re.S)
    return "%s: %s" % (m.group(1), m.group(2)) if m else message


def ms(started):
    return int((time.time() - started) * 1000)


def clip(data):
    text = data[:MAX_OUTPUT].decode("utf-8", "replace")
    return text + ("\n… output cut at %d bytes" % MAX_OUTPUT if len(data) > MAX_OUTPUT else "")


def examples():
    out = {}
    folder = os.path.join(ROOT, "examples")
    for name in sorted(os.listdir(folder)):
        if name.endswith(".tom") and name not in ("primes.tom", "mathlib.tom"):     # those need features/LLVM files not offered here
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                out[name[:-4]] = f.read()
    return out


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body, kind="application/json"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", kind + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            with open(PAGE, "rb") as f:
                self.reply(200, f.read(), "text/html")
        elif self.path == "/examples":
            self.reply(200, json.dumps(examples()))
        else:
            self.reply(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        if self.path != "/run":
            return self.reply(404, json.dumps({"error": "not found"}))
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_SOURCE * 2:
            return self.reply(413, json.dumps({"ok": False, "stage": "request", "error": "the program is too large"}))
        try:
            req = json.loads(self.rfile.read(length) or b"{}")
            source, entry = str(req.get("source", "")), str(req.get("entry") or "main")
            inputs = [str(x) for x in req.get("inputs", [])][:20]
        except (ValueError, TypeError):
            return self.reply(400, json.dumps({"ok": False, "stage": "request", "error": "bad request"}))
        if len(source) > MAX_SOURCE or not entry.replace("_", "").isalnum():
            return self.reply(400, json.dumps({"ok": False, "stage": "request", "error": "bad program or entry name"}))
        if not slots.acquire(timeout=30):
            return self.reply(503, json.dumps({"ok": False, "stage": "request", "error": "busy: try again in a moment"}))
        try:
            self.reply(200, json.dumps(run_program(source, entry, inputs)))
        finally:
            slots.release()

    def log_message(self, fmt, *args):
        print("%s %s" % (self.address_string(), fmt % args), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=49212)
    args = ap.parse_args()
    build_compiler()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("Tomato compiler website on http://127.0.0.1:%d/" % args.port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
