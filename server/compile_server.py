"""A small web server that runs Tomato programs with the Tomato compiler written in Tomato (D38a).

    python3 server/compile_server.py [--port 49212]

On first start it builds the compiler in stages: the Python compiler builds compiler/src/ctool.tom (stage 1), stage 1
compiles the compiler's own source, and clang builds that into stage 2. Every program the page sends is compiled by
stage 2, linked with the C runtime by clang, and run with a CPU/time limit, a polled 1 GB memory cap and a 64 KB output cap.

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
RUNTIME = os.path.join(ROOT, "python", "tomato", "runtime", "tomato_rt.c")
PAGE = os.path.join(os.path.dirname(__file__), "compile.html")
COMPILE_SECONDS, RUN_SECONDS, MAX_OUTPUT, MAX_SOURCE = 60, 5, 64 * 1024, 100 * 1024
ALLOWED_ORIGINS = set()              # sites (scheme://host) that may call /run from another origin, set by --allow-origin
EXTRA_HOSTS = set()                 # more host names allowed by --allow-host
slots = threading.Semaphore(2)


def build_compiler():
    """Build stage 2 (the Tomato compiler compiled by itself) from the checked-in bootstrap IR with clang alone, unless
    the sources it was built from (compiler/src/*.tom, the runtime, the bootstrap IR) are unchanged since the last build."""
    import hashlib
    os.makedirs(BUILD, exist_ok=True)
    sources = sorted(os.path.join(ROOT, "compiler", "src", f) for f in os.listdir(os.path.join(ROOT, "compiler", "src")) if f.endswith(".tom"))
    sources += [RUNTIME, os.path.join(ROOT, "compiler", "bootstrap", "tomatoc.ll")]
    digest = hashlib.sha256()
    for path in sources:
        with open(path, "rb") as f:
            digest.update(f.read())
    stamp = os.path.join(BUILD, "stage2.sha256")
    if os.path.exists(STAGE2) and os.path.exists(stamp) and open(stamp).read() == digest.hexdigest():
        return
    print("building the Tomato compiler (stage 1 from compiler/bootstrap/tomatoc.ll, then stage 2)...", flush=True)
    ctool = os.path.join(ROOT, "compiler", "src", "ctool.tom")
    cc = ["clang", "-O1", "-Wno-override-module", "-o"]
    subprocess.run(cc + [STAGE1, os.path.join(ROOT, "compiler", "bootstrap", "tomatoc.ll"), RUNTIME, "-lm"], check=True)
    ir = subprocess.run([STAGE1, ctool, "compile"], cwd=ROOT, check=True, capture_output=True, text=True).stdout
    with open(os.path.join(BUILD, "stage2.ll"), "w") as f:
        f.write(ir)
    subprocess.run(cc + [STAGE2, os.path.join(BUILD, "stage2.ll"), RUNTIME, "-lm"], check=True)
    with open(stamp, "w") as f:
        f.write(digest.hexdigest())
    print("compiler ready", flush=True)


MAX_MEMORY_KB = 1 << 20            # 1 GB resident; macOS ignores RLIMIT_AS, so the run loop polls instead


def rss_kb(pid):
    r = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    try:
        return int(r.stdout.strip() or 0)
    except ValueError:
        return 0


class StepOutOfMemory(Exception):
    """A compile or link step went over MAX_MEMORY_KB and was killed."""


def group_rss_kb(pgid):
    r = subprocess.run(["ps", "-ax", "-o", "pgid=,rss="], capture_output=True, text=True)
    total = 0
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == str(pgid) and parts[1].isdigit():
            total += int(parts[1])
    return total


SANDBOX_PROFILE = """(version 1)
(allow default)
(deny network*)
(deny process-fork)
(deny signal (target others))
(deny file-write*)
(allow file-write* (subpath (param "WORK")) (literal "/dev/null"))
(deny file-read* (subpath "/Users") (subpath "/private/var/root") (subpath "/Volumes") (subpath "/private/tmp") (subpath "/private/var/tmp") (subpath (param "TMP")))
(allow file-read* (subpath (param "WORK")))
"""


def run_group(argv, timeout, **kw):
    """subprocess.run that puts the child in its own process group and kills the whole group on timeout, so a compiler's
    helper processes (clang's cc1) do not outlive it. A CPU `ulimit` bounds the memory-hungry steps too."""
    wrapped = ["sh", "-c", 'ulimit -t %d; exec "$@"' % timeout, "sh"] + argv
    proc = subprocess.Popen(wrapped, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True, **kw)
    deadline = time.time() + timeout
    over_memory = False
    try:
        while True:
            try:
                out, err = proc.communicate(timeout=0.25)
                break
            except subprocess.TimeoutExpired:
                if time.time() > deadline:
                    raise
                if group_rss_kb(proc.pid) > MAX_MEMORY_KB:      # the compiler or clang is using too much memory
                    over_memory = True
                    raise subprocess.TimeoutExpired(argv, timeout)
    except subprocess.TimeoutExpired as e:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        if over_memory:
            raise StepOutOfMemory()
        raise
    return subprocess.CompletedProcess(argv, proc.returncode, out, err)


def run_text(argv, **kw):
    r = run_group(argv, COMPILE_SECONDS, **kw)
    return subprocess.CompletedProcess(argv, r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace"))


def run_limited(exe, inputs, work):
    """Run `exe` with a CPU limit, output files capped by RLIMIT_FSIZE (so output never fills memory), a polled memory
    cap and a wall-clock timeout. Uses a `ulimit` wrapper rather than preexec_fn, which is unsafe in a threaded server.
    Returns (stdout bytes, stderr bytes, exit code, reason or None)."""
    blocks = (MAX_OUTPUT + 1 + 1023) // 1024      # bash counts `ulimit -f` in 1024-byte blocks
    # sandbox-exec: the program may write only inside its work directory and cannot read user files (it can still read
    # system files such as /etc). Without it a submitted program could overwrite or read anything the server user can.
    wrapper = 'ulimit -t %d; ulimit -f %d; exec sandbox-exec -D WORK="$1" -D TMP="$4" -p "$2" "$3" "${@:5}"' % (RUN_SECONDS, blocks)
    # The capture files live in a directory the sandboxed program cannot write, and are read back through the same open
    # files, so the program cannot swap them for symlinks that the unsandboxed server would then follow.
    capture = tempfile.mkdtemp(prefix="tomato-cap-")
    reason = None
    with open(os.path.join(capture, "out"), "w+b") as fo, open(os.path.join(capture, "err"), "w+b") as fe:
        proc = subprocess.Popen(["bash", "-c", wrapper, "bash", os.path.realpath(work), SANDBOX_PROFILE, exe, os.path.realpath(tempfile.gettempdir())] + inputs, cwd=work, stdin=subprocess.DEVNULL, stdout=fo,
                                stderr=fe, start_new_session=True)
        deadline = time.time() + RUN_SECONDS + 2
        while proc.poll() is None:
            if time.time() > deadline:
                reason = "time"
            elif rss_kb(proc.pid) > MAX_MEMORY_KB:
                reason = "memory"
            if reason:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass
                proc.wait()
                break
            time.sleep(0.05)
        code = proc.returncode
        if reason is None and code in (-signal.SIGXCPU, 128 + signal.SIGXCPU):
            reason = "time"
        if reason is None and code in (-signal.SIGXFSZ, 128 + signal.SIGXFSZ):
            reason = "output"
        fo.seek(0)
        fe.seek(0)
        result = (fo.read(MAX_OUTPUT + 1), fe.read(MAX_OUTPUT + 1), code, reason)
    shutil.rmtree(capture, ignore_errors=True)
    return result


def with_main(src):
    """The compiler written in Tomato does not read top-level code yet (D42a), so a file that has some and no @main gets
    its top-level statements moved into an @main function here, as the Python compiler does natively."""
    import re
    if re.search(r"^@main\b", src, re.M):
        return src
    decl, body, cur, lines, k = [], [], None, src.split("\n"), 0
    while k < len(lines):
        ln = lines[k]
        if not ln.strip() or ln.startswith("#") or ln.startswith((" ", "\t")):
            (cur if cur is not None else decl).append(ln)
        else:
            first = ln.split()[0].split("(")[0]
            is_decl = first in ("def", "class", "interface", "from", "import", "export") or ln.startswith(("@", "!")) \
                or re.match(r"^\w+ implements ", ln)
            cur = decl if is_decl else body
            cur.append(ln)
            if ln.startswith("@") and k + 1 < len(lines):
                k += 1
                cur.append(lines[k])
        k += 1
    if not any(b.strip() and not b.startswith("#") for b in body):
        return src
    return "\n".join(decl) + "\n@main\ndef main():\n" + "\n".join("    " + b if b.strip() else b for b in body) + "\n"


def run_program(source, entry, inputs):
    """Compile `source` with stage 2, link it, run it; returns a dict for the page."""
    started = time.time()
    source = with_main(source)
    if not shutil.which("sandbox-exec") or not shutil.which("bash"):
        return {"ok": False, "stage": "run", "error": "this server needs sandbox-exec (macOS) to confine the programs it runs"}
    work = tempfile.mkdtemp(prefix="tomato-web-")
    try:
        program = os.path.join(work, "program.tom")
        with open(program, "w", encoding="utf-8") as f:
            f.write(source)
        c = run_text([STAGE2, program, entry], cwd=ROOT)
        if c.returncode != 0:
            return {"ok": False, "stage": "compile", "error": tidy((c.stderr or c.stdout).strip()), "ms": ms(started)}
        ll = os.path.join(work, "program.ll")
        with open(ll, "w") as f:
            f.write(c.stdout)
        exe = os.path.join(work, "program")
        link = run_text(["clang", "-O1", "-Wno-override-module", "-o", exe, ll, RUNTIME, "-lm"])
        if link.returncode != 0:
            return {"ok": False, "stage": "link", "error": link.stderr.strip()[:4000], "ir": c.stdout, "ms": ms(started)}
        out, err, code, reason = run_limited(exe, inputs, work)
        return {"ok": True, "stage": "run", "stdout": clip(out), "stderr": clip(err), "exit": code,
                "timed_out": reason == "time", "stopped": reason, "ir": c.stdout, "ms": ms(started)}
    except StepOutOfMemory:
        return {"ok": False, "stage": "compile", "error": "the compiler used too much memory", "ms": ms(started)}
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
    timeout = 30          # a client that stalls after its headers must not hold a thread forever
    def reply(self, code, body, kind="application/json"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", kind + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.cors()
        self.end_headers()
        self.wfile.write(data)

    def cors(self):
        origin = (self.headers.get("Origin") or "").rstrip("/").lower()
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")

    def do_OPTIONS(self):
        """The preflight for a page on an allowed site: only that origin may send a JSON POST."""
        if not self.trusted():
            return self.reply(403, json.dumps({"error": "forbidden"}))
        self.send_response(204)
        self.cors()
        self.send_header("Access-Control-Allow-Methods", "GET, POST")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def trusted(self):
        """Refuse cross-site and DNS-rebinding requests: the Host must be local or a tailnet name, and an Origin (sent by
        browsers on cross-site requests) must be that same host."""
        from urllib.parse import urlparse
        raw = (self.headers.get("Host") or "").strip().lower()
        host = raw[1:raw.index("]")] if raw.startswith("[") and "]" in raw else raw.rsplit(":", 1)[0]
        if not (host in ("127.0.0.1", "localhost", "::1") or host.endswith(".ts.net") or host in EXTRA_HOSTS):
            return False
        origin = self.headers.get("Origin")
        if origin and origin.rstrip("/").lower() in ALLOWED_ORIGINS:
            return True
        if origin and (urlparse(origin).hostname or "").lower() != host:
            return False
        return True

    def do_GET(self):
        if not self.trusted():
            return self.reply(403, json.dumps({"error": "forbidden"}))
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
        if not self.trusted():
            return self.reply(403, json.dumps({"ok": False, "stage": "request", "error": "forbidden"}))
        if (self.headers.get("Content-Type") or "").split(";")[0].strip().lower() != "application/json":
            return self.reply(415, json.dumps({"ok": False, "stage": "request", "error": "send application/json"}))
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length < 0:
            return self.reply(400, json.dumps({"ok": False, "stage": "request", "error": "bad Content-Length"}))
        if length > MAX_SOURCE * 2:
            return self.reply(413, json.dumps({"ok": False, "stage": "request", "error": "the program is too large"}))
        try:
            req = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(req, dict) or not isinstance(req.get("inputs", []), list):
                raise ValueError("not an object")
            source, entry = str(req.get("source", "")), str(req.get("entry") or "main")
            inputs = [str(x) for x in req.get("inputs", [])][:20]
        except (ValueError, TypeError):
            return self.reply(400, json.dumps({"ok": False, "stage": "request", "error": "bad request"}))
        if "\0" in entry or any("\0" in x for x in inputs):
            return self.reply(400, json.dumps({"ok": False, "stage": "request", "error": "NUL bytes are not allowed"}))
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
    ap.add_argument("--allow-host", action="append", default=[], help="another Host name to accept (*.ts.net is already)")
    ap.add_argument("--allow-origin", action="append", default=[], help="a website allowed to call /run, e.g. https://tomato.davismcd.com")
    args = ap.parse_args()
    ALLOWED_ORIGINS.update(o.rstrip("/").lower() for o in args.allow_origin)
    EXTRA_HOSTS.update(h.lower() for h in args.allow_host)
    build_compiler()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("Tomato compiler website on http://127.0.0.1:%d/" % args.port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
