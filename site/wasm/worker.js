// Runs the Tomato toolchain off the page thread, so a program that never ends can be stopped by terminating this worker.
importScripts("wasi.js", "llvm.js", "tomato.js");
var toolchain = new TomatoWasm("");
onmessage = function (e) {
  toolchain.build(e.data.source, { inputs: e.data.inputs || [], timeoutMs: e.data.timeoutMs || 5000 }).then(
    function (r) { postMessage({ id: e.data.id, result: r }); },
    function (err) { postMessage({ id: e.data.id, result: { ok: false, stage: "run", error: String(err && err.message || err) } }); });
};
