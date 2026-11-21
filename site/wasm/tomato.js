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

  // extra: optional { "/name.tom": Uint8Array } for the modules the program imports (the command-line repl supplies them;
  // the website has only the program and the standard library)
  TomatoWasm.prototype.compile = function (source, entry, extra) {
    var self = this;
    return this.load().then(function () {
      var files = Object.assign({}, extra || {}, { "/program.tom": enc(source), "/std/builtin.tom": new Uint8Array(self.std[0]), "/std/math.tom": new Uint8Array(self.std[1]) });
      var host = new WasiHost({ args: ["tomatoc", "/program.tom", entry || "main", "/std/"], files: files });
      return host.run(self.compiler).then(function (r) {
        var err = r.stderr.trim();
        if (r.code !== 0 && /could not be opened/.test(err) && /^\s*(from|import)\s/m.test(source))
          err += "\n(imports of your own modules are not supported on this page; the installed tomato command supports them)";
        return { ok: r.code === 0, ir: r.stdout, error: err };
      });
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


  TomatoWasm.prototype.build = function (source, options) {   // options.extra: imported modules
    var self = this, t0 = Date.now();
    var wrapped = { text: source };
    return this.compile(wrapped.text, "main", options && options.extra).then(function (c) {
      if (!c.ok) return { ok: false, stage: "compile", error: tidy(c.error), ms: Date.now() - t0 };
      return self.run(c.ir, options).then(function (r) {
        return { ok: true, stage: "run", stdout: r.stdout, stderr: r.stderr, exit: r.code, timed_out: r.timedOut, ir: c.ir, ms: Date.now() - t0 };
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
