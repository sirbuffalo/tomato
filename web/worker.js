// Runs the Python interpreter (via Pyodide, Python compiled to WebAssembly) off the page thread
// so a runaway Tomato program can be stopped by terminating this worker.
importScripts("https://cdn.jsdelivr.net/pyodide/v0.26.4/full/pyodide.js");

let pyodide;
const ready = (async () => {
  pyodide = await loadPyodide();
  const bundle = await (await fetch("bundle.json")).json();
  pyodide.FS.mkdir("/tomato");
  pyodide.FS.mkdir("/tomato/std");
  for (const [path, src] of Object.entries(bundle.files)) pyodide.FS.writeFile("/" + path, src);
  pyodide.runPython("import sys; sys.path.insert(0, '/'); sys.setrecursionlimit(3000)");
  pyodide.runPython(`
import io
from tomato.errors import TomatoError
from tomato.interp import run_source
from tomato.codegen import compile_to_ir
def compile_tomato(src):
    try:
        return [compile_to_ir(src), ""]
    except TomatoError as e:
        return ["", str(e)]
def run_tomato(src):
    out = io.StringIO()
    try:
        run_source(src, out)
        return [out.getvalue(), ""]
    except TomatoError as e:
        return [out.getvalue(), str(e)]
`);
  postMessage({ type: "ready", examples: bundle.examples });
})().catch((e) => postMessage({ type: "fatal", message: String(e) }));

onmessage = async (ev) => {
  await ready;
  if (ev.data.type === "compile") {
    const [out, err] = pyodide.globals.get("compile_tomato")(ev.data.source).toJs();
    postMessage({ type: "compiled", out, err });
    return;
  }
  if (ev.data.type !== "run") return;
  const [out, err] = pyodide.globals.get("run_tomato")(ev.data.source).toJs();
  postMessage({ type: "result", out, err });
};
