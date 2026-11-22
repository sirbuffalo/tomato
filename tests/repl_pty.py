#!/usr/bin/env python3
"""Drive `tomato-repl` in a pty: Tab must insert an indent, blocks end on an empty line, errors must be clean, and the
history file must hold only typed lines. Usage: python3 tests/repl_pty.py   (needs `tomato` on PATH)"""
import os, pty, select, signal, sys, tempfile, time
home = tempfile.mkdtemp()
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(HOME=home, TERM="xterm", TOMATO_HISTORY=home + "/hist")
    os.execvp("bash", ["bash", os.path.join(os.path.dirname(__file__), "..", "native", "tomato-repl")])
def rd():
    time.sleep(1.0); out = b""
    while select.select([fd], [], [], 0.5)[0]:
        try: chunk = os.read(fd, 4096)
        except OSError: break
        if not chunk: break
        out += chunk
    return out.decode(errors="replace")
rd()
out = ""
for s in ["for i in range(2):\r", "\tprint(i)\r", "\r", "if True:\r", "\r", "from nosuch_mod import a\r", ":quit\r"]:
    os.write(fd, s.encode()); out += rd()
time.sleep(0.5)
bad = []
if "    print(i)" not in out: bad.append("Tab did not insert an indent")
if "0\r\n1" not in out: bad.append("block did not run")
if "SyntaxError" not in out or "INDENT" in out or "DEDENT" in out: bad.append("parse error not friendly")
if "/tmp" in out or "/var/folders" in out or ".tom" in out: bad.append("temp path leaked")
hist = open(home + "/hist").read() if os.path.exists(home + "/hist") else ""
if "for i in range(2):" not in hist or "interactive" in hist or "Error" in hist: bad.append("history wrong: " + repr(hist))
try: os.kill(pid, signal.SIGKILL)
except OSError: pass
import re, subprocess
src = os.path.join(os.path.dirname(__file__), "..", "native", "tomato-repl")
fn = re.search(r"^friendly\(\) \{.*?^\}", open(src).read(), re.S | re.M).group(0)
t = subprocess.run(["bash", "-c", 'S=$(mktemp -d); ' + fn + '\nprintf "Could not open file: $S/itertools.tom\\nCompileError: module itertools has no xxx\\n" > $S/err; friendly'],
    capture_output=True, text=True)
if t.stderr.strip() != "itertools has no name 'xxx'": bad.append("missing-name message: " + repr(t.stderr))
print("FAIL: " + "; ".join(bad) if bad else "ok"); sys.exit(1 if bad else 0)
