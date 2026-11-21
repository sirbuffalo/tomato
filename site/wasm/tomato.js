// The Tomato toolchain in the browser, with no server:
//   compile(source)  runs tomatoc.wasm (the compiler written in Tomato) to get LLVM IR
//   run(ir, inputs)  runs that IR on runtime.wasm (the C runtime) with the IR interpreter in llvm.js
(function () {
  function TomatoWasm(base) { this.base = base || ""; this.ready = null; }
  TomatoWasm.prototype.load = function () {
    var self = this;
    if (this.ready) return this.ready;
    var get = function (u) { return fetch(self.base + u).then(function (r) { if (!r.ok) throw new Error("cannot load " + u); return r; }); };
    this.ready = Promise.all([
      get("tomatoc.wasm").then(function (r) { return r.arrayBuffer(); }).then(WebAssembly.compile),
      get("runtime.wasm").then(function (r) { return r.arrayBuffer(); }).then(WebAssembly.compile),
      Promise.all(["builtin", "math"].map(function (n) { return get("std/" + n + ".tom").then(function (r) { return r.arrayBuffer(); }); }))
    ]).then(function (x) { self.compiler = x[0]; self.runtime = x[1]; self.std = x[2]; return self; });
    return this.ready;
  };
  var enc = function (s) { return new TextEncoder().encode(s); };

  TomatoWasm.prototype.compile = function (source, entry) {
    var self = this;
    return this.load().then(function () {
      var files = { "/program.tom": enc(source), "/std/builtin.tom": new Uint8Array(self.std[0]), "/std/math.tom": new Uint8Array(self.std[1]) };
      var host = new WasiHost({ args: ["tomatoc", "/program.tom", entry || "main", "/std/"], files: files });
      return host.run(self.compiler).then(function (r) { return { ok: r.code === 0, ir: r.stdout, error: r.stderr.trim() }; });
    });
  };

  // Runs IR. options: { inputs: [..], timeoutMs: 5000 }. Returns { stdout, stderr, code, timedOut }.
  TomatoWasm.prototype.run = function (ir, options) {
    var self = this; options = options || {};
    return this.load().then(function () {
      var host = new WasiHost({ args: ["program"], files: {} });
      return WebAssembly.instantiate(self.runtime, host.imports(self.runtime)).then(function (inst) {
        host.memory = inst.exports.memory;
        if (inst.exports._initialize) inst.exports._initialize();
        var machine = new LlvmMachine(inst, host, { deadline: Date.now() + (options.timeoutMs || 5000) });
        var code = 0, timedOut = false, failure = "";
        try {
          machine.loadModule(ir);
          code = machine.runMain(options.inputs || []);
        } catch (e) {
          if (e && e.wasiExit !== undefined) code = e.wasiExit;
          else if (e && e.timeout) { timedOut = true; code = 124; }
          else { failure = String(e && e.message || e); code = 1; }
        }
        return { stdout: host.text("out"), stderr: host.text("err") + (failure ? "error: " + failure + "\n" : ""), code: code, timedOut: timedOut };
      });
    });
  };

  // The compiler written in Tomato does not read top-level code yet (D42a), so a program without @main has its
  // top-level statements moved into an @main function first, until the compiler reads top-level code itself.
  // Returns { text, map } where map[n] is the line of the user's source that line n of the generated program came from,
  // so errors are reported against what the user typed.
  function wrapMain(src) {
    var lines = src.split("\n"), identity = lines.map(function (_, i) { return i + 1; });
    if (/^@main\b/m.test(src)) return { text: src, map: [0].concat(identity) };
    var decl = [], body = [], cur = null;
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      if (!l.trim() || l[0] === " " || l[0] === "\t" || l[0] === "#") { (cur || decl).push([l, i + 1]); continue; }
      var first = l.split(/[ (]/)[0];
      var isDecl = /^(def|class|interface|from|import|export)$/.test(first) || l[0] === "@" || l[0] === "!" || /^\w+ implements /.test(l);
      cur = isDecl ? decl : body; cur.push([l, i + 1]);
      if (l[0] === "@" && i + 1 < lines.length) { i++; cur.push([lines[i], i + 1]); }
    }
    if (!body.some(function (b) { return b[0].trim() && b[0][0] !== "#"; })) return { text: src, map: [0].concat(identity) };
    var out = [], map = [0], firstBody = body[0][1];
    decl.forEach(function (d) { out.push(d[0]); map.push(d[1]); });
    out.push(""); map.push(firstBody);
    out.push("@main"); map.push(firstBody);
    out.push("def main():"); map.push(firstBody);
    body.forEach(function (b) { out.push(b[0].trim() ? "    " + b[0] : b[0]); map.push(b[1]); });
    return { text: out.join("\n") + "\n", map: map };
  }
  function remap(text, map) {
    return text.replace(/\bline (\d+)/g, function (m, n) { return "line " + (map[+n] || n); });
  }
  TomatoWasm.wrapMain = wrapMain;

  TomatoWasm.prototype.build = function (source, options) {
    var self = this, t0 = Date.now();
    var wrapped = wrapMain(source);
    return this.compile(wrapped.text, "main").then(function (c) {
      if (!c.ok) return { ok: false, stage: "compile", error: remap(tidy(c.error), wrapped.map), ms: Date.now() - t0 };
      return self.run(c.ir, options).then(function (r) {
        return { ok: true, stage: "run", stdout: r.stdout, stderr: remap(r.stderr, wrapped.map), exit: r.code, timed_out: r.timedOut, ir: c.ir, ms: Date.now() - t0 };
      });
    });
  };

  // "error: line N: uncaught error Kind: line M: text" -> "Kind on line M: text"
  function tidy(message) {
    var m = /^error: line \d+: uncaught error (\w+): line (\d+): ([\s\S]*)$/.exec(message);
    if (m) return m[1] + " on line " + m[2] + ": " + m[3];
    m = /^error: line \d+: uncaught error (\w+): ([\s\S]*)$/.exec(message);
    return m ? m[1] + ": " + m[2] : message;
  }
  self.TomatoWasm = TomatoWasm;
})();
