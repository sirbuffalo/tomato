// Runs the Tomato toolchain in JavaScriptCore (the jsc shell that ships with macOS), so the repl never has to start a
// new native program: macOS checks each freshly built executable the first time it runs (0.7 s or more), and the same
// compiler and runtime that run on the website (WebAssembly) do not need that check.
//   jsc tomato-jsc.js -- WASMDIR compile|run FILE
// jsc cannot set an exit status, so the last line on standard error is "~rc N" (0 for success).
var self = globalThis;
(function polyfills() {
  if (typeof TextEncoder === "undefined") {
    globalThis.TextEncoder = function () {};
    TextEncoder.prototype.encode = function (s) {
      var out = [];
      for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i);
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < s.length) { c = 0x10000 + ((c - 0xd800) << 10) + (s.charCodeAt(++i) - 0xdc00); }
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
        else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
        else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      }
      return new Uint8Array(out);
    };
    globalThis.TextDecoder = function () {};
    TextDecoder.prototype.decode = function (b) {
      var s = "", i = 0;
      while (i < b.length) {
        var c = b[i++];
        if (c >= 0xf0) { c = ((c & 7) << 18) | ((b[i++] & 63) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63); c -= 0x10000; s += String.fromCharCode(0xd800 + (c >> 10), 0xdc00 + (c & 1023)); continue; }
        if (c >= 0xe0) c = ((c & 15) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
        else if (c >= 0xc0) c = ((c & 31) << 6) | (b[i++] & 63);
        s += String.fromCharCode(c);
      }
      return s;
    };
  }
  if (typeof crypto === "undefined") globalThis.crypto = { getRandomValues: function (a) { for (var i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256); return a; } };
})();

var args = Array.prototype.slice.call(arguments);
var dir = args[0], mode = args[1], file = args[2];
["wasi.js", "llvm.js", "tomato.js"].forEach(function (f) { load(dir + "/" + f); });

var bin = function (p) { return read(p, "binary"); };
var tw = new TomatoWasm("");
tw.compiler = new WebAssembly.Module(bin(dir + "/tomatoc.wasm"));
tw.runtime = new WebAssembly.Module(bin(dir + "/runtime.wasm"));
tw.std = [bin(dir + "/std/builtin.tom"), bin(dir + "/std/math.tom")].map(function (u) { return u.buffer.slice(u.byteOffset, u.byteOffset + u.byteLength); });
tw.ready = Promise.resolve(tw);

var source = new TextDecoder().decode(bin(file));
function emit(text, stream) {   // jsc's print adds a newline, so one trailing newline is dropped first
  if (text === "") return;
  var t = text.charAt(text.length - 1) === "\n" ? text.slice(0, -1) : text;
  if (stream === "err") printErr(t); else print(t);
}
function finish(code) { printErr("~rc " + code); }
tw.compile(source, "main").then(function (c) {
  if (mode === "compile") { emit(c.ok ? c.ir : c.error, c.ok ? "out" : "err"); finish(c.ok ? 0 : 1); return; }
  if (!c.ok) { emit(c.error, "err"); finish(1); return; }
  return tw.run(c.ir, { inputs: [], timeoutMs: 5000 }).then(function (r) {
    emit(r.stdout, "out"); emit(r.stderr, "err");
    if (r.timedOut) printErr("error: the program ran longer than 5 seconds");
    finish(r.code);
  });
}).catch(function (e) { printErr("error: " + (e && e.message || e)); finish(1); });
