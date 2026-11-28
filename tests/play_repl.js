// The website repl's session logic (site/play.html), driven under node with the page's own script: the DOM is a stub, and a piece is compiled
// and run by the same WebAssembly toolchain the page uses (site/wasm). It prints what the page would log, one entry per line, as `in:`
// (echo of the typed piece), `out:` and `e:` (an error, its lines joined by | ). tests/run.sh compares it with what the installed repl does.
//   node tests/play_repl.js            (run from the repository root; Node 18 or later)
const fs = require("fs"), vm = require("vm");
const html = fs.readFileSync("site/play.html", "utf8");
const script = html.slice(html.indexOf("<script>\nfunction $(id)") + "<script>\n".length, html.lastIndexOf("</script>"));
const log = [];
function el(id) {
  const e = { id, value: "", children: [], style: {}, dataset: {}, className: "", textContent: "", set innerHTML(v) { this._h = v; }, get innerHTML() { return this._h || ""; },
    appendChild(c) { this.children.push(c); if (id === "repl-log") log.push(c); return c; }, removeChild() {}, setAttribute() {}, addEventListener() {}, focus() {}, setSelectionRange() {},
    set onclick(f) { this._onclick = f; }, set onsubmit(f) { this._onsubmit = f; }, hidden: false, disabled: false };
  return e;
}
const els = {};
const document = { getElementById(id) { return els[id] || (els[id] = el(id)); }, createElement() { return el("new"); }, createTextNode(t) { return { text: t }; } };
const ctx = { document, console, TextEncoder, TextDecoder, WebAssembly, Uint8Array, Uint32Array, Int32Array, BigInt, BigInt64Array, BigUint64Array, DataView, ArrayBuffer, Date, URL, Worker: function () {}, setTimeout, clearTimeout, window: {}, fetch: () => Promise.resolve({ json: () => ({}) }),
  tomatoHighlight: (t) => t, tomatoErrors: (t) => t, tomatoOpensBlock: (l) => /:\s*$/.test(l.replace(/#.*$/, "")), tomatoNextIndent: () => "", tomatoAttachEditor() {} };
ctx.self = ctx; vm.createContext(ctx);
// the toolchain of the page's worker (site/wasm/worker.js), in this context
for (const f of ["wasi.js", "llvm.js", "tomato.js"]) vm.runInContext(fs.readFileSync("site/wasm/" + f, "utf8"), ctx, { filename: f });
ctx.fetch = (u) => { const p = "site/wasm/" + u; return fs.promises.readFile(p).then((b) => ({ ok: true, arrayBuffer: () => Promise.resolve(b.buffer.slice(b.byteOffset, b.byteOffset + b.length)) })); };
vm.runInContext("var toolchain = new TomatoWasm('');", ctx);
vm.runInContext(script, ctx, { filename: "play.html" });
// the page's runProgram talks to a worker; here the toolchain is called directly, with the worker's own arguments
ctx.runProgram = function (source, repl, inputs, stdin) {
  ctx.__args = { source, repl, inputs, stdin };
  return vm.runInContext("toolchain.build(__args.source, { repl: !!__args.repl, inputs: __args.inputs || [], stdin: __args.stdin || '', ask: true, timeoutMs: 5000 })", ctx)
    .catch((e) => ({ ok: false, stage: "run", error: String(e && e.message || e) }));
};
const pieces = JSON.parse(fs.readFileSync(0, "utf8"));    // the pieces to enter, in order (a JSON array of texts; a block is one text with \n)
(async () => {
  for (const p of pieces) await vm.runInContext("submit", ctx)(p, false);
  for (const c of log) {
    const t = c.className + ":" + (c.textContent !== "" ? c.textContent : (c.innerHTML || c.children.map((x) => x.text).join("")));
    console.log(t.replace(/<[^>]*>/g, "").replace(/&gt;/g, ">").replace(/&lt;/g, "<").split("\n").join(" | "));
  }
})();
