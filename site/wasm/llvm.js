// An interpreter for the LLVM IR text that the Tomato compiler writes. A browser cannot turn IR into machine code, so
// the page interprets it instead: the IR's memory is the C runtime's WebAssembly memory (runtime.wasm), and calls to
// tomato_* functions go straight to that module. Only the instructions the Tomato compiler emits are supported.
// Integers are BigInts held unsigned within their width; pointers are numbers (WebAssembly pointers are 32 bits).
(function () {
  "use strict";

  // ---------------------------------------------------------------- types
  function parseType(s, p, named) {
    while (s[p] === " ") p++;
    var m;
    if ((m = /^i(\d+)/.exec(s.slice(p, p + 8)))) return [{ k: "i", bits: +m[1] }, p + m[0].length];
    if (s.startsWith("double", p)) return [{ k: "f", bits: 64 }, p + 6];
    if (s.startsWith("float", p)) return [{ k: "f", bits: 32 }, p + 5];
    if (s.startsWith("ptr", p)) return [{ k: "p" }, p + 3];
    if (s.startsWith("void", p)) return [{ k: "v" }, p + 4];
    if (s[p] === "[") {
      m = /^\[\s*(\d+)\s+x\s+/.exec(s.slice(p));
      var r = parseType(s, p + m[0].length, named);
      var q = r[1]; while (s[q] === " ") q++;
      return [{ k: "a", n: +m[1], t: r[0] }, q + 1];
    }
    if (s[p] === "{") {
      var fields = [], q2 = p + 1;
      for (;;) {
        while (s[q2] === " ") q2++;
        if (s[q2] === "}") return [{ k: "s", f: fields }, q2 + 1];
        var r2 = parseType(s, q2, named); fields.push(r2[0]); q2 = r2[1];
        while (s[q2] === " ") q2++;
        if (s[q2] === ",") q2++;
      }
    }
    if (s[p] === "%") {
      m = /^%[\w.$]+/.exec(s.slice(p));
      return [{ k: "n", name: m[0] }, p + m[0].length];
    }
    throw new Error("unsupported type in IR: " + s.slice(p, p + 30));
  }

  function Layout(named) {
    this.named = named;
  }
  Layout.prototype.resolve = function (t) {
    while (t.k === "n") { t = this.named[t.name]; if (!t) throw new Error("unknown type"); }
    return t;
  };
  Layout.prototype.align = function (t) {
    t = this.resolve(t);
    switch (t.k) {
      case "i": return t.bits <= 8 ? 1 : t.bits <= 16 ? 2 : t.bits <= 32 ? 4 : 8;
      case "f": return t.bits / 8;
      case "p": return 4;
      case "a": return this.align(t.t);
      case "s": var a = 1; for (var i = 0; i < t.f.length; i++) a = Math.max(a, this.align(t.f[i])); return a;
    }
    return 1;
  };
  Layout.prototype.size = function (t) {
    t = this.resolve(t);
    switch (t.k) {
      case "i": return t.bits === 1 ? 1 : Math.ceil(t.bits / 8);
      case "f": return t.bits / 8;
      case "p": return 4;
      case "a": return t.n * this.size(t.t);
      case "s": var o = this.offsets(t); return o.size;
    }
    return 0;
  };
  Layout.prototype.offsets = function (t) {
    t = this.resolve(t);
    if (t.cache) return t.cache;
    var off = 0, offs = [], al = 1;
    for (var i = 0; i < t.f.length; i++) {
      var a = this.align(t.f[i]); al = Math.max(al, a);
      off = Math.ceil(off / a) * a; offs.push(off); off += this.size(t.f[i]);
    }
    return (t.cache = { offs: offs, size: Math.ceil(off / al) * al });
  };

  // ---------------------------------------------------------------- text helpers
  function splitTop(s) {   // split on commas that are not inside (), [] or {}
    var out = [], depth = 0, cur = "", inStr = false;
    for (var i = 0; i < s.length; i++) {
      var c = s[i];
      if (c === '"') inStr = !inStr;
      if (!inStr) {
        if (c === "(" || c === "[" || c === "{") depth++;
        else if (c === ")" || c === "]" || c === "}") depth--;
        else if (c === "," && depth === 0) { out.push(cur.trim()); cur = ""; continue; }
      }
      cur += c;
    }
    if (cur.trim() !== "") out.push(cur.trim());
    return out;
  }
  function decodeCString(s) {   // c"ab\0A\00" -> bytes
    var out = [];
    for (var i = 0; i < s.length; i++) {
      if (s[i] === "\\") {
        if (s[i + 1] === "\\") { out.push(92); i++; }
        else { out.push(parseInt(s.substr(i + 1, 2), 16)); i += 2; }
      } else out.push(s.charCodeAt(i));
    }
    return out;
  }
  function hexDouble(h) {
    var b = new DataView(new ArrayBuffer(8)); b.setBigUint64(0, BigInt(h)); return b.getFloat64(0);
  }
  var bitsView = new DataView(new ArrayBuffer(8));
  var mask = function (bits, v) { return BigInt.asUintN(bits, v); };
  var signed = function (bits, v) { return BigInt.asIntN(bits, v); };

  // ---------------------------------------------------------------- the machine
  function Machine(rt, host, opts) {
    this.rt = rt; this.host = host;
    this.ex = rt.exports;
    this.mem = rt.exports.memory;
    this.deadline = opts && opts.deadline ? opts.deadline : 0;
    this.steps = 0;
    this.named = {}; this.layout = new Layout(this.named);
    this.globals = {};            // name -> address
    this.funcs = {};              // name -> {params, blocks, order}
    this.fnAddr = {}; this.fnByAddr = {};
    this.stackBase = 0; this.sp = 0; this.stackEnd = 0;
  }
  Machine.prototype.dv = function () {
    if (!this._dv || this._buf !== this.mem.buffer) { this._buf = this.mem.buffer; this._dv = new DataView(this._buf); }
    return this._dv;
  };
  Machine.prototype.malloc = function (n) { var a = this.ex.malloc(Math.max(n, 1) + 16) >>> 0; return Math.ceil(a / 16) * 16 === a ? a : a; };

  Machine.prototype.load = function (t, addr) {
    var dv = this.dv(); t = this.layout.resolve(t);
    if (t.k === "i") {
      if (t.bits <= 8) return BigInt(dv.getUint8(addr)) & (t.bits === 1 ? 1n : 255n);
      if (t.bits <= 16) return BigInt(dv.getUint16(addr, true));
      if (t.bits <= 32) return BigInt(dv.getUint32(addr, true));
      return dv.getBigUint64(addr, true);
    }
    if (t.k === "p") return dv.getUint32(addr, true);
    if (t.k === "f") return t.bits === 64 ? dv.getFloat64(addr, true) : dv.getFloat32(addr, true);
    throw new Error("cannot load this type");
  };
  Machine.prototype.store = function (t, addr, v) {
    var dv = this.dv(); t = this.layout.resolve(t);
    if (t.k === "i") {
      if (t.bits <= 8) dv.setUint8(addr, Number(v & 255n));
      else if (t.bits <= 16) dv.setUint16(addr, Number(v & 65535n), true);
      else if (t.bits <= 32) dv.setUint32(addr, Number(v & 0xffffffffn), true);
      else dv.setBigUint64(addr, mask(64, v), true);
    } else if (t.k === "p") dv.setUint32(addr, v >>> 0, true);
    else if (t.k === "f") { if (t.bits === 64) dv.setFloat64(addr, v, true); else dv.setFloat32(addr, v, true); }
    else throw new Error("cannot store this type");
  };

  // ---- constants
  Machine.prototype.constValue = function (type, text) {
    text = text.trim();
    var t = this.layout.resolve(type), m;
    if (text === "null" || text === "zeroinitializer" || text === "undef" || text === "poison") return t.k === "f" || t.k === "p" ? 0 : 0n;
    if (text === "true") return 1n; if (text === "false") return 0n;
    if (text[0] === "@") return this.symbol(text.slice(1));
    if (/^-?\d+$/.test(text)) return t.k === "f" ? Number(text) : mask(t.k === "i" ? t.bits : 64, BigInt(text));
    if (/^0x[0-9A-Fa-f]+$/.test(text)) return t.k === "f" ? hexDouble(text) : BigInt(text);
    if (/^-?\d*\.?\d+(e[+-]?\d+)?$/i.test(text)) return Number(text);
    if ((m = /^(getelementptr|ptrtoint|inttoptr|trunc|zext|sext|bitcast|sub|add|mul)(?: inbounds)?\s*\((.*)\)$/.exec(text))) return this.constExpr(m[1], m[2], t);
    throw new Error("unsupported constant in IR: " + text.slice(0, 60));
  };
  Machine.prototype.constExpr = function (op, inner, want) {
    var parts = splitTop(inner), self = this;
    if (op === "getelementptr") {
      var bt = parseType(parts[0], 0)[0];
      var base = this.typed(parts[1]);
      var idx = parts.slice(2).map(function (x) { var v = self.typed(x); return Number(signed(v.bits || 64, BigInt(v.value))); });
      return this.gep(bt, base.value, idx);
    }
    if (op === "sub" || op === "add" || op === "mul") {
      var a = this.typed(parts[0]), b = this.typed(parts[1]);
      var x = BigInt(a.value), y = BigInt(b.value), bits = a.bits || 64;
      return mask(bits, op === "sub" ? x - y : op === "add" ? x + y : x * y);
    }
    var mm = /^(.*)\s+to\s+(\S+)$/.exec(inner);
    var src = this.typed(mm[1]), dst = this.layout.resolve(parseType(mm[2], 0)[0]);
    if (op === "ptrtoint") return mask(dst.bits, BigInt(src.value));
    if (op === "inttoptr") return Number(mask(32, BigInt(src.value)));
    if (op === "trunc") return mask(dst.bits, BigInt(src.value));
    if (op === "zext") return BigInt(src.value);
    if (op === "sext") return mask(dst.bits, signed(src.bits, BigInt(src.value)));
    return src.value;   // bitcast
  };
  Machine.prototype.typed = function (text) {   // "TYPE VALUE" -> {value, bits}
    var r = parseType(text, 0), t = this.layout.resolve(r[0]);
    var rest = text.slice(r[1]).trim();
    return { value: this.constValue(t, rest), bits: t.k === "i" ? t.bits : 0, type: t };
  };
  Machine.prototype.gep = function (baseType, base, idx) {
    var L = this.layout, addr = base + idx[0] * L.size(baseType), t = L.resolve(baseType);
    for (var i = 1; i < idx.length; i++) {
      if (t.k === "s") { addr += L.offsets(t).offs[idx[i]]; t = L.resolve(t.f[idx[i]]); }
      else if (t.k === "a") { addr += idx[i] * L.size(t.t); t = L.resolve(t.t); }
      else throw new Error("bad getelementptr");
    }
    return addr >>> 0;
  };
  Machine.prototype.symbol = function (name) {
    if (name in this.globals) return this.globals[name];
    if (name in this.funcs || this.declared[name]) {
      if (!(name in this.fnAddr)) { var a = 0x7f000000 + 16 * Object.keys(this.fnAddr).length; this.fnAddr[name] = a; this.fnByAddr[a] = name; }
      return this.fnAddr[name];
    }
    var g = this.ex[name];
    if (g instanceof WebAssembly.Global) return g.value;
    throw new Error("unknown symbol @" + name);
  };

  // ---- writing a global's initial value into memory
  Machine.prototype.writeInit = function (type, text, addr) {
    var L = this.layout, t = L.resolve(type); text = text.trim();
    if (text === "zeroinitializer" || text === "undef") return;
    if (t.k === "a") {
      var m = /^c"(.*)"$/s.exec(text);
      if (m) { var bytes = decodeCString(m[1]), u8 = new Uint8Array(this.mem.buffer); for (var i = 0; i < bytes.length; i++) u8[addr + i] = bytes[i]; return; }
      var inner = text.replace(/^\[/, "").replace(/\]$/, ""), els = splitTop(inner), es = L.size(t.t);
      for (var j = 0; j < els.length; j++) { var r = parseType(els[j], 0); this.writeInit(r[0], els[j].slice(r[1]), addr + j * es); }
      return;
    }
    if (t.k === "s") {
      var f = splitTop(text.replace(/^\{/, "").replace(/\}$/, "")), offs = L.offsets(t).offs;
      for (var k = 0; k < f.length; k++) { var rr = parseType(f[k], 0); this.writeInit(rr[0], f[k].slice(rr[1]), addr + offs[k]); }
      return;
    }
    this.store(t, addr, this.constValue(t, text));
  };

  // ---------------------------------------------------------------- loading a module
  Machine.prototype.loadModule = function (src) {
    var lines = src.split("\n"), i, self = this, L = this.layout;
    this.declared = {};
    var gdefs = [], fdefs = [];
    for (i = 0; i < lines.length; i++) {
      var ln = lines[i].charAt(0) === "@" ? lines[i] : lines[i].replace(/;.*$/, "");
      var m;
      if ((m = /^(%[\w.$]+) = type (.*)$/.exec(ln))) { this.named[m[1]] = parseType(m[2], 0, this.named)[0]; continue; }
      if ((m = /^@([\w.$]+) = (.*)$/.exec(lines[i]))) { gdefs.push([m[1], m[2]]); continue; }
      if ((m = /^declare\s+.*?@([\w.$]+)\(/.exec(ln))) { this.declared[m[1]] = true; continue; }
      if (/^define /.test(ln)) {
        var start = i; while (lines[i] !== "}") i++;
        fdefs.push(lines.slice(start, i + 1));
      }
    }
    // layout globals
    var layouts = [];
    gdefs.forEach(function (g) {
      var m2 = /^(?:(?:private|internal|external|linkonce_odr|dso_local|unnamed_addr|local_unnamed_addr)\s+)*(constant|global)\s+(.*)$/.exec(g[1]);
      if (!m2) { self.globals[g[0]] = 0; return; }
      var r = parseType(m2[2], 0), t = r[0], init = m2[2].slice(r[1]).trim();
      if (/external\s/.test(g[1]) && init === "") { return; }
      var size = L.size(t), al = Math.max(L.align(t), 8), a = self.ex.malloc(size + al) >>> 0;
      a = Math.ceil(a / al) * al;
      new Uint8Array(self.mem.buffer, a, size).fill(0);
      self.globals[g[0]] = a; layouts.push([t, init, a]);
    });
    // functions: register names first (calls and function pointers may refer forward)
    var parsed = fdefs.map(function (ls) { return self.parseFunction(ls); });
    parsed.forEach(function (f) { self.funcs[f.name] = f; });
    layouts.forEach(function (x) { self.writeInit(x[0], x[1], x[2]); });
    parsed.forEach(function (f) { self.compileFunction(f); });   // (each becomes JavaScript when it is first called)
    // the runtime reads the generated tables through pointers
    if (this.ex.tomato_set_tables && this.globals.tomato_kinds !== undefined)
      this.ex.tomato_set_tables(this.globals.tomato_kinds, this.globals.tomato_offsets, this.globals.tomato_parents, this.globals.tomato_class_names);
  };

  Machine.prototype.parseFunction = function (ls) {
    var h = /^define\s+(.*?)\s*@([\w.$]+)\((.*)\)\s*(?:(?:#\d+|inlinehint|cold|noinline)\s*)*\{$/.exec(ls[0]);
    if (!h) throw new Error("cannot read function header: " + ls[0].slice(0, 80));
    var params = splitTop(h[3]).map(function (p) {
      var r = parseType(p, 0); var nm = /%[\w.$]+/.exec(p.slice(r[1]));
      return { type: r[0], name: nm ? nm[0] : null };
    });
    var rt = parseType(h[1].replace(/^(?:(?:private|internal|dso_local|noundef|signext|zeroext)\s+)+/, ""), 0)[0];
    var blocks = {}, order = [], cur = null;
    for (var i = 1; i < ls.length - 1; i++) {
      var ln = ls[i].replace(/;.*$/, "").trim();
      if (ln === "") continue;
      var lab = /^([\w.$]+):$/.exec(ln);
      if (lab) { cur = { label: lab[1], text: [] }; blocks[lab[1]] = cur; order.push(cur); continue; }
      if (!cur) { cur = { label: "entry", text: [] }; blocks.entry = cur; order.push(cur); }
      cur.text.push(ln);
    }
    return { name: h[2], params: params, ret: rt, blocks: blocks, order: order };
  };

  // ---- compiling a function to JavaScript. The function is turned into JavaScript source the first time it is called (a
  // program calls few of the functions in the IR), with its registers as local variables and its blocks as the cases of a
  // loop; integers stay BigInts (held unsigned within their width), floats are numbers, pointers are numbers.
  var f64Word = new Float64Array(1), u64Word = new BigUint64Array(f64Word.buffer);
  function bcFI(v) { f64Word[0] = v; return u64Word[0]; }   // a double's bits as an i64
  function bcIF(v) { u64Word[0] = v; return f64Word[0]; }   // i64 bits as a double (a float word and a double have the same bits)
  function fpToInt(v, bits) { return (v !== v || !isFinite(v)) ? 0n : BigInt.asUintN(bits, BigInt(Math.trunc(v))); }
  function divZero() { throw new Error("division by zero"); }
  function badPhi() { throw new Error("bad phi"); }
  function overflowOp(sg, bits, op, x, y) {   // llvm.{s,u}{add,sub,mul}.with.overflow.iN
    var a = sg ? signed(bits, x) : x, b = sg ? signed(bits, y) : y;
    var r = op === "add" ? a + b : op === "sub" ? a - b : a * b;
    var ok = sg ? (r >= -(1n << BigInt(bits - 1)) && r < (1n << BigInt(bits - 1))) : (r >= 0n && r < (1n << BigInt(bits)));
    return [mask(bits, r), ok ? 0n : 1n];
  }

  Machine.prototype.u8 = function () {
    if (!this._u8 || this._u8buf !== this.mem.buffer) { this._u8buf = this.mem.buffer; this._u8 = new Uint8Array(this._u8buf); }
    return this._u8;
  };
  Machine.prototype.alloca = function (sz, al) {
    var s = Math.ceil(this.sp / al) * al; this.sp = s + sz;
    if (this.sp > this.stackEnd) throw new Error("the program used too much stack");
    this.u8().fill(0, s, s + sz);
    return s;
  };
  Machine.prototype.tick = function () { if (this.deadline && Date.now() > this.deadline) throw { timeout: true }; };
  Machine.prototype.callPtr = function (addr, vals, rt) { return this.invoke(this.fnByAddr[addr], vals, rt); };
  Machine.prototype.missing = function (name) { throw new Error("the program calls @" + name + ", which is not available in the browser"); };

  Machine.prototype.compileFunction = function (fn) {
    var self = this;
    fn.js = function () {
      self.genFunction(fn);
      return fn.js.apply(null, arguments);
    };
  };

  var FCMP = {
    oeq: "A === B", one: "(A < B || A > B)", olt: "A < B", ole: "A <= B", ogt: "A > B", oge: "A >= B",
    une: "A !== B", ueq: "(A === B || A !== A || B !== B)", uno: "(A !== A || B !== B)", ord: "(A === A && B === B)",
    ult: "!(A >= B)", ule: "!(A > B)", ugt: "!(A <= B)", uge: "!(A < B)"
  };

  Machine.prototype.genFunction = function (fn) {
    var self = this, L = this.layout, names = {}, regs = [], K = [], temps = 0, hasAlloca = false;
    // Registers. A value used only in the block that defines it shares a variable with other such values of the same kind
    // (once its last use is past), so a function with hundreds of values has a small frame and a deep recursion fits the
    // stack; the rest (used in other blocks, phi nodes, parameters) each have a variable of their own.
    function kindOfType(t) { t = L.resolve(t); return t.k === "i" ? "i" : t.k === "f" ? "f" : t.k === "p" ? "p" : "a"; }
    function kindOfDef(body) {
      var w = /^([a-z]+)/.exec(body)[1], rest = body.slice(w.length).replace(/^\s+/, ""), m;
      try {
        switch (w) {
          case "load": return kindOfType(parseType(splitTop(rest)[0], 0)[0]);
          case "alloca": case "getelementptr": return "p";
          case "icmp": case "fcmp": case "add": case "sub": case "mul": case "sdiv": case "udiv": case "srem": case "urem": case "and": case "or": case "xor": case "shl": case "lshr": case "ashr": return "i";
          case "fadd": case "fsub": case "fmul": case "fdiv": case "frem": case "fneg": return "f";
          case "sext": case "zext": case "trunc": case "sitofp": case "uitofp": case "fptosi": case "fptoui": case "ptrtoint": case "inttoptr": case "bitcast":
            m = /\s+to\s+(\S+)\s*$/.exec(rest); return kindOfType(parseType(m[1], 0)[0]);
          case "select": return kindOfType(parseType(splitTop(rest)[1], 0)[0]);
          case "call": case "tail": m = /^(?:tail\s+)?(?:call\s+)?(.*?)\s*(@[\w.$]+|%[\w.$]+)\(/s.exec(body.replace(/^tail\s+/, "").replace(/^call\s+/, "")); return m ? kindOfType(parseType(m[1].replace(/\s*\(.*\)\s*$/, ""), 0)[0]) : "a";
        }
      } catch (e) { }
      return "a";
    }
    var NAMES = /%[\w.$]+/g;
    (function plan() {
      var defBlock = {}, cross = {}, info = [];
      fn.params.forEach(function (p) { if (p.name) cross[p.name] = true; });
      fn.order.forEach(function (b, bi) {
        var rows = [];
        b.text.forEach(function (t, i) {
          var m = /^(%[\w.$]+) = (.*)$/.exec(t), def = m ? m[1] : null, body = m ? m[2] : t, uses = body.match(NAMES) || [];
          if (def) defBlock[def] = bi;
          if (/^phi /.test(body)) { if (def) cross[def] = true; uses.forEach(function (u) { cross[u] = true; }); uses = []; }
          rows.push({ def: def, uses: uses, kind: def ? kindOfDef(body) : "" });
        });
        info.push(rows);
      });
      info.forEach(function (rows, bi) {
        rows.forEach(function (r) { r.uses.forEach(function (u) { if (u in defBlock && defBlock[u] !== bi) cross[u] = true; }); });
      });
      var gcount = 0, maxk = {};
      info.forEach(function (rows, bi) {
        var last = {}, free = { i: [], f: [], p: [], a: [] }, used = { i: 0, f: 0, p: 0, a: 0 };
        rows.forEach(function (r, i) { r.uses.forEach(function (u) { last[u] = i; }); if (r.def && !(r.def in last)) last[r.def] = i; });
        rows.forEach(function (r, i) {
          if (r.def && !(r.def in names)) {
            if (cross[r.def]) { names[r.def] = "g" + (gcount++); regs.push(names[r.def]); }
            else {
              var k = r.kind, pool = free[k], slot = pool.length ? pool.pop() : k + (used[k]++);
              names[r.def] = slot; r.slot = slot; r.k = k;
              if (used[k] > (maxk[k] || 0)) maxk[k] = used[k];
            }
          }
          // slots whose value is last used here can be taken by the next definition
          r.uses.concat(r.def ? [r.def] : []).forEach(function (u) {
            if (last[u] === i && !cross[u] && names[u] !== undefined && /^[ifpa]\d+$/.test(names[u])) {
              var kk = names[u][0]; if (free[kk].indexOf(names[u]) < 0) free[kk].push(names[u]);
            }
          });
        });
      });
      ["i", "f", "p", "a"].forEach(function (k) { for (var j = 0; j < (maxk[k] || 0); j++) regs.push(k + j); });
    })();
    function reg(n) { var r = names[n]; if (r === undefined) { r = names[n] = "g" + regs.length; regs.push(r); } return r; }
    function konst(x) { K.push(x); return "K[" + (K.length - 1) + "]"; }
    function lit(v) {
      if (typeof v === "bigint") return v < 0n ? "(" + v + "n)" : v + "n";
      if (typeof v === "number") {
        if (v !== v) return "NaN";
        if (v === Infinity) return "Infinity"; if (v === -Infinity) return "(-Infinity)";
        if (v === 0 && 1 / v < 0) return "(-0)";
        return v < 0 ? "(" + v + ")" : String(v);
      }
      return konst(v);
    }
    function opnd(type, text) {
      text = text.trim();
      if (text[0] === "%") return reg(text);
      return lit(self.constValue(type, text));
    }
    var blockIdx = {};
    fn.order.forEach(function (b, i) { blockIdx[b.label] = i; });
    function target(label) {
      if (!(label in blockIdx)) throw new Error("branch to an unknown block %" + label);
      return blockIdx[label];
    }
    function loadExpr(t, p) {
      if (t.k === "i") {
        if (t.bits <= 8) return "(BigInt(dv.getUint8(" + p + ")) & " + (t.bits === 1 ? "1n" : "255n") + ")";
        if (t.bits <= 16) return "BigInt(dv.getUint16(" + p + ", true))";
        if (t.bits <= 32) return "BigInt(dv.getUint32(" + p + ", true))";
        return "dv.getBigUint64(" + p + ", true)";
      }
      if (t.k === "p") return "dv.getUint32(" + p + ", true)";
      if (t.k === "f") return t.bits === 64 ? "dv.getFloat64(" + p + ", true)" : "dv.getFloat32(" + p + ", true)";
      throw new Error("cannot load this type");
    }
    function storeStmt(t, p, v) {
      if (t.k === "i") {
        if (t.bits <= 8) return "dv.setUint8(" + p + ", Number(" + v + " & 255n));";
        if (t.bits <= 16) return "dv.setUint16(" + p + ", Number(" + v + " & 65535n), true);";
        if (t.bits <= 32) return "dv.setUint32(" + p + ", Number(" + v + " & 0xffffffffn), true);";
        return "dv.setBigUint64(" + p + ", BigInt.asUintN(64, " + v + "), true);";
      }
      if (t.k === "p") return "dv.setUint32(" + p + ", " + v + " >>> 0, true);";
      if (t.k === "f") return t.bits === 64 ? "dv.setFloat64(" + p + ", " + v + ", true);" : "dv.setFloat32(" + p + ", " + v + ", true);";
      throw new Error("cannot store this type");
    }
    // returns {code, term}: a JavaScript statement, and whether it ends the block
    function instr(text, bi) {
      var m, dest = null, body = text;
      if ((m = /^(%[\w.$]+) = (.*)$/.exec(text))) { dest = m[1]; body = m[2]; }
      var d = dest ? reg(dest) : null;
      var word = /^([a-z]+)/.exec(body)[1];
      var rest = body.slice(word.length).replace(/^\s+/, "");
      switch (word) {
        case "ret": {
          if (rest === "void") return { code: "return undefined;", term: true };
          var rr = parseType(rest, 0);
          return { code: "return " + opnd(rr[0], rest.slice(rr[1])) + ";", term: true };
        }
        case "br": {
          if (rest.startsWith("label")) return { code: "prev = " + bi + "; b = " + target(rest.replace(/^label\s+%/, "")) + "; continue;", term: true };
          var mm = /^i1\s+(\S+),\s*label\s+%([\w.$]+),\s*label\s+%([\w.$]+)(?:,\s*!prof\s+!\d+)?$/.exec(rest);
          return { code: "prev = " + bi + "; b = " + opnd({ k: "i", bits: 1 }, mm[1]) + " ? " + target(mm[2]) + " : " + target(mm[3]) + "; continue;", term: true };
        }
        case "switch": {
          var sm = /^(i\d+)\s+(\S+),\s*label\s+%(\S+)\s*\[(.*)\]$/.exec(rest);
          var st = parseType(sm[1], 0)[0], sv = opnd(st, sm[2]);
          var code = "prev = " + bi + "; sw = " + sv + "; ", re = /i\d+\s+(-?\d+),\s*label\s+%(\S+)/g, cm;
          while ((cm = re.exec(sm[4]))) code += "if (sw === " + lit(mask(st.bits, BigInt(cm[1]))) + ") b = " + target(cm[2]) + "; else ";
          return { code: code + "b = " + target(sm[3]) + "; continue;", term: true };
        }
        case "unreachable": return { code: 'throw new Error("the program reached unreachable code");', term: true };
        case "alloca": {
          var at = parseType(rest, 0)[0];
          hasAlloca = true;
          return { code: d + " = M.alloca(" + L.size(at) + ", " + Math.max(L.align(at), 1) + ");" };
        }
        case "load": {
          var lp = splitTop(rest), lt = L.resolve(parseType(lp[0], 0)[0]);
          return { code: d + " = " + loadExpr(lt, opnd({ k: "p" }, lp[1].replace(/^ptr\s+/, ""))) + ";" };
        }
        case "store": {
          var sp = splitTop(rest), vr = parseType(sp[0], 0), stype = L.resolve(vr[0]);
          return { code: storeStmt(stype, opnd({ k: "p" }, sp[1].replace(/^ptr\s+/, "")), opnd(stype, sp[0].slice(vr[1]))) };
        }
        case "getelementptr": {
          var gp = splitTop(rest.replace(/^inbounds\s+/, "")), gt = parseType(gp[0], 0)[0];
          var base = opnd({ k: "p" }, gp[1].replace(/^ptr\s+/, "")), c = 0, terms = [];
          var add = function (x, size, isConst, bits) {
            if (isConst) c += Number(signed(bits, BigInt(x))) * size;
            else terms.push("Number(BigInt.asIntN(" + bits + ", " + x + ")) * " + size);
          };
          var t = L.resolve(gt);
          for (var i = 2; i < gp.length; i++) {
            var r = parseType(gp[i], 0), bits = L.resolve(r[0]).bits, tx = gp[i].slice(r[1]).trim(), isC = tx[0] !== "%";
            var val = isC ? self.constValue(r[0], tx) : opnd(r[0], tx);
            if (i === 2) { add(val, L.size(gt), isC, bits); continue; }
            if (t.k === "s") {
              if (!isC) throw new Error("bad getelementptr");
              var k = Number(signed(bits, BigInt(val)));
              c += L.offsets(t).offs[k]; t = L.resolve(t.f[k]);
            } else if (t.k === "a") { add(val, L.size(t.t), isC, bits); t = L.resolve(t.t); }
            else throw new Error("bad getelementptr");
          }
          return { code: d + " = ((" + base + (c ? " + " + c : "") + terms.map(function (x) { return " + " + x; }).join("") + ") >>> 0);" };
        }
        case "icmp": {
          var im = /^(\w+)\s+(.*)$/.exec(rest), ip = splitTop(im[2]), ir = parseType(ip[0], 0), it = L.resolve(ir[0]);
          var A = opnd(it, ip[0].slice(ir[1])), B = opnd(it, ip[1]), pred = im[1], bits2 = it.k === "i" ? it.bits : 32, e;
          var ops = { eq: "===", ne: "!==", ult: "<", ule: "<=", ugt: ">", uge: ">=", slt: "<", sle: "<=", sgt: ">", sge: ">=" };
          if (!(pred in ops)) throw new Error("unsupported icmp " + pred);
          if (pred[0] === "s") e = it.k === "p" ? "(" + A + " | 0) " + ops[pred] + " (" + B + " | 0)" : "BigInt.asIntN(" + bits2 + ", " + A + ") " + ops[pred] + " BigInt.asIntN(" + bits2 + ", " + B + ")";
          else e = A + " " + ops[pred] + " " + B;
          return { code: d + " = (" + e + ") ? 1n : 0n;" };
        }
        case "fcmp": {
          var fm = /^(\w+)\s+(.*)$/.exec(rest), fp = splitTop(fm[2]), fr = parseType(fp[0], 0);
          if (!(fm[1] in FCMP)) throw new Error("unsupported fcmp " + fm[1]);
          var fa = opnd(fr[0], fp[0].slice(fr[1])), fb = opnd(fr[0], fp[1]);
          return { code: d + " = (" + FCMP[fm[1]].replace(/A/g, fa).replace(/B/g, fb) + ") ? 1n : 0n;" };
        }
        case "add": case "sub": case "mul": case "sdiv": case "udiv": case "srem": case "urem": case "and": case "or": case "xor":
        case "shl": case "lshr": case "ashr": {
          var br2 = rest.replace(/^(?:(?:nsw|nuw|exact)\s+)+/, ""), bp = splitTop(br2), brr = parseType(bp[0], 0), bt = L.resolve(brr[0]);
          var X = opnd(bt, bp[0].slice(brr[1])), Y = opnd(bt, bp[1]), W = bt.bits, e2;
          var U = function (s) { return "BigInt.asUintN(" + W + ", " + s + ")"; }, S = function (s) { return "BigInt.asIntN(" + W + ", " + s + ")"; };
          switch (word) {
            case "add": e2 = U(X + " + " + Y); break; case "sub": e2 = U(X + " - " + Y); break; case "mul": e2 = U(X + " * " + Y); break;
            case "sdiv": e2 = "(" + Y + " === 0n ? divZero() : " + U(S(X) + " / " + S(Y)) + ")"; break;
            case "udiv": e2 = "(" + Y + " === 0n ? divZero() : " + X + " / " + Y + ")"; break;
            case "srem": e2 = "(" + Y + " === 0n ? divZero() : " + U(S(X) + " % " + S(Y)) + ")"; break;
            case "urem": e2 = "(" + Y + " === 0n ? divZero() : " + X + " % " + Y + ")"; break;
            case "and": e2 = X + " & " + Y; break; case "or": e2 = X + " | " + Y; break; case "xor": e2 = X + " ^ " + Y; break;
            case "shl": e2 = U(X + " << " + Y); break; case "lshr": e2 = X + " >> " + Y; break; case "ashr": e2 = U(S(X) + " >> " + Y); break;
          }
          return { code: d + " = " + e2 + ";" };
        }
        case "fadd": case "fsub": case "fmul": case "fdiv": case "frem": {
          var fp2 = splitTop(rest), fr2 = parseType(fp2[0], 0);
          var xa = opnd(fr2[0], fp2[0].slice(fr2[1])), xb = opnd(fr2[0], fp2[1]);
          var fop = { fadd: "+", fsub: "-", fmul: "*", fdiv: "/", frem: "%" }[word];
          return { code: d + " = " + xa + " " + fop + " " + xb + ";" };
        }
        case "fneg": { var nr = parseType(rest, 0); return { code: d + " = -" + opnd(nr[0], rest.slice(nr[1])) + ";" }; }
        case "sext": case "zext": case "trunc": case "sitofp": case "uitofp": case "fptosi": case "fptoui": case "ptrtoint": case "inttoptr": case "bitcast": {
          var cm2 = /^(.*)\s+to\s+(\S+)$/.exec(rest), cr = parseType(cm2[1], 0), st2 = L.resolve(cr[0]), dt = L.resolve(parseType(cm2[2], 0)[0]);
          var V = opnd(st2, cm2[1].slice(cr[1])), e3;
          switch (word) {
            case "zext": e3 = V; break;
            case "sext": e3 = "BigInt.asUintN(" + dt.bits + ", BigInt.asIntN(" + st2.bits + ", " + V + "))"; break;
            case "trunc": e3 = "BigInt.asUintN(" + dt.bits + ", " + V + ")"; break;
            case "sitofp": e3 = "Number(BigInt.asIntN(" + st2.bits + ", " + V + "))"; break;
            case "uitofp": e3 = "Number(" + V + ")"; break;
            case "fptosi": case "fptoui": e3 = "fpToInt(" + V + ", " + dt.bits + ")"; break;
            case "ptrtoint": e3 = "BigInt.asUintN(" + dt.bits + ", BigInt(" + V + "))"; break;
            case "inttoptr": e3 = "Number(BigInt.asUintN(32, " + V + "))"; break;
            default:   // bitcast
              if (st2.k === "f" && dt.k === "i") e3 = "bcFI(" + V + ")";
              else if (st2.k === "i" && dt.k === "f") e3 = "bcIF(" + V + ")";
              else e3 = V;
          }
          return { code: d + " = " + e3 + ";" };
        }
        case "select": {
          var slp = splitTop(rest), s1 = parseType(slp[1], 0), s2 = parseType(slp[2], 0);
          return { code: d + " = " + opnd({ k: "i", bits: 1 }, slp[0].replace(/^i1\s+/, "")) + " ? " + opnd(s1[0], slp[1].slice(s1[1])) + " : " + opnd(s2[0], slp[2].slice(s2[1])) + ";" };
        }
        case "extractvalue": {
          var ep = splitTop(rest), er = parseType(ep[0], 0);
          return { code: d + " = " + opnd(er[0], ep[0].slice(er[1])) + "[" + (+ep[1]) + "];" };
        }
        case "tail": case "call": return call(d, body.replace(/^tail\s+/, ""));
      }
      throw new Error("unsupported instruction in IR: " + text.slice(0, 80));
    }
    function call(d, body) {
      var m = /^call\s+(.*?)\s*(@[\w.$]+|%[\w.$]+)\((.*)\)\s*$/s.exec(body);
      if (!m) throw new Error("cannot read call: " + body.slice(0, 80));
      var rtype = parseType(m[1].replace(/\s*\(.*\)\s*$/, ""), 0)[0], callee = m[2], rt = L.resolve(rtype);
      var args = splitTop(m[3]).map(function (a) {
        var r = parseType(a, 0), t = L.resolve(r[0]);
        return { type: t, val: opnd(t, a.slice(r[1]).replace(/^(?:(?:noundef|signext|zeroext)\s+)+/, "")) };
      });
      var vals = args.map(function (a) { return a.val; });
      var set = d ? d + " = " : "", after = " dv = M.dv();";   // (a call may have grown the memory)
      if (callee[0] === "%") return { code: set + "M.callPtr(" + reg(callee) + ", [" + vals.join(", ") + "], " + konst(rt) + ");" + after };
      var name = callee.slice(1), f = self.funcs[name], mo;
      if (f) return { code: set + konst(f) + ".js(" + vals.join(", ") + ");" + after };
      if ((mo = /^llvm\.([su])(add|sub|mul)\.with\.overflow\.i(\d+)$/.exec(name))) return { code: set + "overflowOp(" + (mo[1] === "s") + ", " + mo[3] + ", " + JSON.stringify(mo[2]) + ", " + vals[0] + ", " + vals[1] + ");" };
      if (name === "llvm.floor.f64") return { code: set + "Math.floor(" + vals[0] + ");" };
      if (name === "llvm.pow.f64") return { code: set + "Math.pow(" + vals[0] + ", " + vals[1] + ");" };
      if (name === "llvm.fabs.f64") return { code: set + "Math.abs(" + vals[0] + ");" };
      if (name === "llvm.sqrt.f64") return { code: set + "Math.sqrt(" + vals[0] + ");" };   // (the fast copy of a loop nest; JavaScript's square root is the correctly rounded one too)
      if (name === "llvm.assume") return { code: "" };
      if (name === "llvm.trap") return { code: 'throw new Error("the program trapped");' };
      if (name === "printf") return { code: set + "M.printf([" + vals.join(", ") + "]);" + after };
      if (name === "putchar") return { code: "M.ex.putchar(Number(" + vals[0] + "));" + (d ? " " + d + " = " + vals[0] + ";" : "") + after };
      var ex = self.ex[name];
      if (typeof ex !== "function") return { code: "M.missing(" + JSON.stringify(name) + ");" };
      var conv = args.map(function (a) { var t = a.type; return t.k === "i" && t.bits > 32 ? a.val : t.k === "i" ? "Number(" + a.val + ")" : a.val; });
      var call = konst(ex) + "(" + conv.join(", ") + ")", e;
      if (rt.k === "v") return { code: call + ";" + after };
      if (rt.k === "i") e = "BigInt.asUintN(" + rt.bits + ", BigInt(" + call + "))";
      else if (rt.k === "p") e = call + " >>> 0";
      else e = call;
      return { code: set + e + ";" + after };
    }
    // the parameters first, then the blocks
    var params = fn.params.map(function (p, i) { return "p" + i; });
    var head = [];
    fn.params.forEach(function (p, i) { if (p.name) head.push(reg(p.name) + " = p" + i + ";"); });
    var cases = [];
    fn.order.forEach(function (b, bi) {
      var out = ["case " + bi + ":"], i = 0, phis = [];
      for (; i < b.text.length; i++) {      // phi nodes read the values from before this block began: evaluate them first
        var pm = /^(%[\w.$]+) = phi (.*)$/.exec(b.text[i]);
        if (!pm) break;
        var pr = parseType(pm[2], 0), pt = pr[0], arms = [], re2 = /\[\s*([^,\]]+),\s*%([\w.$]+)\s*\]/g, am, tmp = "ph" + (temps++);
        var sw = "switch (prev) {";
        while ((am = re2.exec(pm[2].slice(pr[1])))) sw += " case " + target(am[2]) + ": " + tmp + " = " + opnd(pt, am[1]) + "; break;";
        out.push(sw + " default: badPhi(); }");
        phis.push([reg(pm[1]), tmp]);
      }
      phis.forEach(function (p) { out.push(p[0] + " = " + p[1] + ";"); });
      var ended = false;
      for (; i < b.text.length && !ended; i++) {
        var r = instr(b.text[i], bi);
        if (r.code) out.push(r.code);
        ended = !!r.term;
      }
      if (!ended) out.push('throw new Error("a block ended without a branch");');
      cases.push(out.join("\n"));
    });
    var src = "var " + regs.concat(["prev = -1", "b = 0", "sw", "dv = M.dv()"]).concat(Array.apply(null, Array(temps)).map(function (_, i) { return "ph" + i; })).join(", ") + ";\n" +
      head.join("\n") + "\n" + (hasAlloca ? "var sp0 = M.sp;\ntry {\n" : "") +
      "for (;;) {\nif ((++M.steps & 4095) === 0) M.tick();\nswitch (b) {\n" + cases.join("\n") + "\ndefault: throw new Error(\"bad block\");\n}\n}\n" +
      (hasAlloca ? "} finally { M.sp = sp0; }\n" : "");
    fn.js = new Function("M", "K", "bcFI", "bcIF", "fpToInt", "divZero", "badPhi", "overflowOp",
      "return function (" + params.join(", ") + ") {\n" + src + "};")(self, K, bcFI, bcIF, fpToInt, divZero, badPhi, overflowOp);
  };

  // ---- calling
  Machine.prototype.invoke = function (name, vals, rt, args) {
    var fn = this.funcs[name];
    if (fn) return fn.js.apply(null, vals);
    var m;
    if ((m = /^llvm\.([su])(add|sub|mul)\.with\.overflow\.i(\d+)$/.exec(name))) {
      var bits = +m[3], x = vals[0], y = vals[1], sg = m[1] === "s";
      var a = sg ? signed(bits, x) : x, b = sg ? signed(bits, y) : y;
      var r = m[2] === "add" ? a + b : m[2] === "sub" ? a - b : a * b;
      var ok = sg ? (r >= -(1n << BigInt(bits - 1)) && r < (1n << BigInt(bits - 1))) : (r >= 0n && r < (1n << BigInt(bits)));
      return [mask(bits, r), ok ? 0n : 1n];
    }
    if (name === "llvm.floor.f64") return Math.floor(vals[0]);
    if (name === "llvm.pow.f64") return Math.pow(vals[0], vals[1]);
    if (name === "llvm.fabs.f64") return Math.abs(vals[0]);
    if (name === "llvm.sqrt.f64") return Math.sqrt(vals[0]);   // (the fast copy of a loop nest; JavaScript's square root is the correctly rounded one too)
    if (name === "llvm.assume") return undefined;
    if (name === "llvm.trap") throw new Error("the program trapped");
    if (name === "printf") return this.printf(vals);
    if (name === "putchar") { this.ex.putchar(Number(vals[0])); return vals[0]; }
    var ex = this.ex[name];
    if (typeof ex !== "function") throw new Error("the program calls @" + name + ", which is not available in the browser");
    var conv = vals.map(function (v, i) {
      var t = args && args[i] && args[i].type;
      return t && t.k === "i" && t.bits > 32 ? BigInt(v) : t && t.k === "i" ? Number(v) : v;
    });
    var out = ex.apply(null, conv);
    if (rt.k === "v") return undefined;
    if (rt.k === "i") return mask(rt.bits, BigInt(out));
    if (rt.k === "p") return out >>> 0;
    return out;
  };
  Machine.prototype.cstring = function (addr) {
    var u8 = new Uint8Array(this.mem.buffer), e = addr; while (u8[e]) e++;
    return new TextDecoder().decode(u8.subarray(addr, e));
  };
  Machine.prototype.printf = function (vals) {
    var fmt = this.cstring(vals[0]), k = 1;
    var self = this;
    fmt.replace(/%(l*)([dusc%])|([^%]+)/g, function (all, l, conv, lit) {
      if (lit) { var bytes = new TextEncoder().encode(lit); for (var i = 0; i < bytes.length; i++) self.ex.putchar(bytes[i]); return ""; }
      if (conv === "%") self.ex.putchar(37);
      else if (conv === "d" && l) self.ex.tomato_print_i64(BigInt.asIntN(64, vals[k++]));
      else if (conv === "u" && l) self.ex.tomato_print_u64(BigInt.asUintN(64, vals[k++]));
      else if (conv === "d") self.ex.tomato_print_i64(BigInt.asIntN(32, vals[k++]));
      else if (conv === "s") { var s = new TextEncoder().encode(self.cstring(vals[k++])); for (var j = 0; j < s.length; j++) self.ex.putchar(s[j]); }
      else if (conv === "c") self.ex.putchar(Number(vals[k++]));
      return "";
    });
    return 0n;
  };

  Machine.prototype.exec = function (fn, vals) { return fn.js.apply(null, vals); };

  // ---------------------------------------------------------------- running a program
  // Runs the IR's @main with the given inputs; returns the exit code. Output goes through the WASI host.
  Machine.prototype.runMain = function (inputs) {
    var stackSize = 4 * 1024 * 1024;
    this.stackBase = this.ex.malloc(stackSize) >>> 0; this.stackBase = Math.ceil(this.stackBase / 16) * 16;
    this.sp = this.stackBase; this.stackEnd = this.stackBase + stackSize - 64;
    var argv = ["program"].concat(inputs || []), self = this;
    var tbl = this.ex.malloc(4 * (argv.length + 1)) >>> 0, dv, ptrs = [];
    argv.forEach(function (a) {
      var b = new TextEncoder().encode(a), p = self.ex.malloc(b.length + 1) >>> 0;
      var u8 = new Uint8Array(self.mem.buffer); u8.set(b, p); u8[p + b.length] = 0; ptrs.push(p);
    });
    dv = this.dv(); ptrs.forEach(function (p, i) { dv.setUint32(tbl + 4 * i, p, true); }); dv.setUint32(tbl + 4 * ptrs.length, 0, true);
    var main = this.funcs.main;
    if (!main) throw new Error("the program has no main");
    var r = this.exec(main, [BigInt(argv.length), tbl]);
    if (this.ex.fflush) this.ex.fflush(0);
    return Number(r === undefined ? 0n : BigInt.asIntN(32, r));
  };

  self.LlvmMachine = Machine;
})();
