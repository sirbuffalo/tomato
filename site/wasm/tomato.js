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
      Promise.all(TomatoWasm.STD.map(function (n) { return get("std/" + TomatoWasm.file(n)).then(function (r) { return r.arrayBuffer(); }); }))
    ]).then(function (x) { self.compiler = x[0]; self.runtime = x[1]; self.std = x[2]; return self; });
    return this.ready;
  };
  TomatoWasm.STD = ["builtin/errors", "builtin/range", "builtin/numbers", "builtin/text", "builtin/sorting", "builtin/lists", "builtin/format", "builtin/bytes", "builtin/bitarray", "builtin/bytearray", "math", "itertools", "rational", "cache", "requests", "toml", "value", "json", "time", "urlparse", "html", "base64", "hex", "random", "secrets", "uuid", "datetime", "csv", "textwrap", "statistics", "re", "utf8", "zlib", "hashlib", "hmac", "struct", "signal", "gzip", "tarfile", "sys", "os", "ospath", "io", "testing", "asyncio", "socket", "terminal", "lineedit", "errors"];   // the standard library modules (std/NAME.tom; the built-ins, bitarray and bytearray are in std/builtin/, see builtin_parts in compiler/src/compiler.tom) and the error table (std/errors.txt)
  TomatoWasm.file = function (n) { return n === "errors" ? "errors.txt" : n + ".tom"; };
  var enc = function (s) { return new TextEncoder().encode(s); };

  // extra: optional { "/name.tom": Uint8Array } for the modules the program imports (the command-line repl supplies them;
  // the website has only the program and the standard library). config: optional text of a tomato.toml, whose [limits] table sets the
  // limits on huge floats for the program (docs/decisions.md D77g); without it the built-in limits apply, since a browser has no files
  TomatoWasm.prototype.compile = function (source, entry, extra, config) {
    var self = this;
    return this.load().then(function () {
      var files = Object.assign({}, extra || {}, { "/program.tom": enc(source) });
      TomatoWasm.STD.forEach(function (n, i) { files["/std/" + TomatoWasm.file(n)] = new Uint8Array(self.std[i]); });
      var args = ["tomatoc", "/program.tom", entry || "main", "/std/"];
      if (typeof config === "string") { files["/tomato.toml"] = enc(config); args.push("debug", "/tomato.toml", ""); }   // (the compiler's arguments: mode, project file, user file)
      var host = new WasiHost({ args: args, files: files });
      return host.run(self.compiler).then(function (r) {
        var err = r.stderr.trim();
        if (!self.local && r.code !== 0 && /could not be opened/.test(err) && /^\s*(from|import)\s/m.test(source))
          err += "\n(imports of your own modules are not supported on this page; the installed tomato command supports them)";
        // warnings (compiler/src/lint.tom) travel as comment lines at the end of the IR: ";! " then the text
        var warnings = r.stdout.split("\n").filter(function (l) { return l.indexOf(";! ") === 0; }).map(function (l) { return l.slice(3); }).join("\n");
        return { ok: r.code === 0, ir: r.stdout, error: err, warnings: warnings };
      });
    });
  };

  // Runs IR. options: { inputs: [..], timeoutMs: 5000 }. Returns { stdout, stderr, code, timedOut }.
  TomatoWasm.prototype.run = function (ir, options) {
    var self = this; options = options || {};
    return this.load().then(function () {
      // stdin: the answers given so far, one per line; ask: stop with exit code 75 when the program wants one more (see tomato_input)
      var host = new WasiHost({ args: ["program"], files: {}, stdin: new TextEncoder().encode(options.stdin || ""), env: options.ask ? ["TOMATO_INPUT_ASK=1"] : [] });
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
          else if (e instanceof RangeError && /call stack/i.test(e.message)) { failure = "error[E350]: stack overflow: a function calls itself too deeply"; code = 1; }
          else { failure = "error[E370]: " + String(e && e.message || e); code = 1; }
        }
        return { stdout: host.text("out"), stderr: host.text("err") + (failure ? failure + "\n" : ""), code: code, timedOut: timedOut };
      });
    });
  };

  // Programs have no top-level code (D16a); only the repl (options.repl) accepts bare statements, and they are
  // moved into an @main function first.
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
      var isDecl = /^(def|class|interface|from|import|export)$/.test(first) || /^async def /.test(l) || l[0] === "@" || l[0] === "!" || /^\w+ implements /.test(l);
      cur = isDecl ? decl : body; cur.push([l, i + 1]);
      if (l[0] === "@" && i + 1 < lines.length) { i++; cur.push([lines[i], i + 1]); }
    }
    // a piece with no statements (an import, a definition) still becomes a program, so that it is checked and an error in it
    // is its own (a missing module, a name the module lacks) instead of "no function is marked @main"
    var hasBody = body.some(function (b) { return b[0].trim() && b[0][0] !== "#"; });
    if (!hasBody && !decl.some(function (d) { return d[0].trim() && d[0][0] !== "#"; })) return { text: src, map: [0].concat(identity) };
    if (!hasBody) body = [["pass", lines.length]];
    var out = [], map = [0], firstBody = body[0][1];
    decl.forEach(function (d) { out.push(d[0]); map.push(d[1]); });
    out.push(""); map.push(firstBody);
    out.push("@main"); map.push(firstBody);
    // the session is async when a statement awaits, starts a task or loops over statuses
    out.push((body.some(function (b) { return /(^|[^\w])(await|async|start) /.test(b[0]); }) ? "async def" : "def") + " main():"); map.push(firstBody);
    body.forEach(function (b) { out.push(b[0].trim() ? "    " + b[0] : b[0]); map.push(b[1]); });
    return { text: out.join("\n") + "\n", map: map };
  }
  function remap(text, map) {
    return text.replace(/\bline (\d+)/g, function (m, n) { return "line " + (map[+n] || n); });
  }
  TomatoWasm.wrapMain = wrapMain;
  TomatoWasm.fixDiag = function (t, w, s) { return fixDiag(t, w, s); };
  // A compiler error names a line of the generated program; point it at what the user wrote (the line, the column, the shown source).
  function fixDiag(text, wrapped, source) {
    var lines = text.split("\n"), gen = wrapped.text.split("\n"), orig = source.split("\n");
    for (var i = 0; i < lines.length; i++) {
      var m = /^\s*--> ([^:]*):(\d+):(\d+)$/.exec(lines[i]);
      if (!m) continue;
      var L = +m[2], C = +m[3], ul = wrapped.map[L] || L, g = gen[L - 1] || "", o = orig[ul - 1];
      var shift = (o !== undefined && g.length >= o.length && g.slice(g.length - o.length) === o) ? g.length - o.length : 0;
      var uc = Math.max(1, C - shift), pad = new Array(String(ul).length + 1).join(" ");
      lines[i] = pad + "--> " + m[1] + ":" + ul + ":" + uc;
      if (o !== undefined && i + 3 < lines.length) {
        var car = /\^+/.exec(lines[i + 3]);
        lines[i + 1] = pad + " |"; lines[i + 2] = ul + " | " + o;
        lines[i + 3] = pad + " | " + new Array(uc).join(" ") + (car ? car[0] : "^");
        for (var j = i + 4; j < lines.length; j++) lines[j] = lines[j].replace(/^\s*= help:/, pad + " = help:");
      }
      break;
    }
    return lines.join("\n");
  }

  TomatoWasm.prototype.build = function (source, options) {   // options.extra: imported modules
    var self = this, t0 = Date.now();
    var wrapped = (options && options.repl) ? wrapMain(source) : { text: source, map: [0].concat(source.split("\n").map(function (_, i) { return i + 1; })) };
    return this.compile(wrapped.text, "main", options && options.extra).then(function (c) {
      if (!c.ok) return { ok: false, stage: "compile", error: fixDiag(tidy(c.error), wrapped, source), ms: Date.now() - t0 };
      return self.run(c.ir, options).then(function (r) {
        return { ok: true, stage: "run", stdout: r.stdout, stderr: remap(r.stderr, wrapped.map), exit: r.code, timed_out: r.timedOut, ir: c.ir, warnings: (options && options.repl) ? "" : tidy(c.warnings), ms: Date.now() - t0 };
      });
    });
  };

  // The compiler's error text is already final (docs/errors.md); only the program name differs on this page.
  // (A stale tomatoc.wasm may still print "error: line N: uncaught error Kind: ..."; that is tidied the old way.)
  function tidy(message) {
    var m = /^error: line \d+: uncaught error (\w+): line (\d+): ([\s\S]*)$/.exec(message);
    if (m) return "error: " + m[3] + "\n --> program.tom:" + m[2];
    m = /^error: line \d+: uncaught error (\w+): ([\s\S]*)$/.exec(message);
    if (m) return "error: " + m[2];
    return message.replace(/--> \/program\.tom:/g, "--> program.tom:");
  }
  self.TomatoWasm = TomatoWasm;
})();
