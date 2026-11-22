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
    parsed.forEach(function (f) { self.compileFunction(f); });
    // the runtime reads the generated tables through pointers
    if (this.ex.tomato_set_tables && this.globals.tomato_kinds !== undefined)
      this.ex.tomato_set_tables(this.globals.tomato_kinds, this.globals.tomato_offsets, this.globals.tomato_parents, this.globals.tomato_class_names);
  };

  Machine.prototype.parseFunction = function (ls) {
    var h = /^define\s+(.*?)\s*@([\w.$]+)\((.*)\)\s*(?:#\d+\s*)?\{$/.exec(ls[0]);
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

  // ---- compiling instructions to closures
  Machine.prototype.operand = function (type, text) {
    var self = this; text = text.trim();
    if (text[0] === "%") { var n = text; return function (f) { return f.r[n]; }; }
    var v = this.constValue(type, text);
    return function () { return v; };
  };

  Machine.prototype.compileFunction = function (fn) {
    var self = this, L = this.layout;
    fn.compiled = {};
    fn.order.forEach(function (b) {
      b.code = b.text.map(function (t) { return self.compileInstr(t); });
    });
  };

  function cmpInt(pred, bits, a, b) {
    switch (pred) {
      case "eq": return a === b; case "ne": return a !== b;
      case "ult": return a < b; case "ule": return a <= b; case "ugt": return a > b; case "uge": return a >= b;
    }
    var x = signed(bits, a), y = signed(bits, b);
    switch (pred) { case "slt": return x < y; case "sle": return x <= y; case "sgt": return x > y; case "sge": return x >= y; }
    throw new Error("unsupported icmp " + pred);
  }
  function cmpFloat(pred, a, b) {
    var un = a !== a || b !== b;
    switch (pred) {
      case "oeq": return !un && a === b; case "one": return !un && a !== b;
      case "olt": return !un && a < b; case "ole": return !un && a <= b; case "ogt": return !un && a > b; case "oge": return !un && a >= b;
      case "une": return un || a !== b; case "ueq": return un || a === b; case "uno": return un; case "ord": return !un;
      case "ult": return un || a < b; case "ule": return un || a <= b; case "ugt": return un || a > b; case "uge": return un || a >= b;
    }
    throw new Error("unsupported fcmp " + pred);
  }

  Machine.prototype.compileInstr = function (text) {
    var self = this, L = this.layout, m, dest = null, body = text;
    if ((m = /^(%[\w.$]+) = (.*)$/.exec(text))) { dest = m[1]; body = m[2]; }
    var set = dest ? function (f, v) { f.r[dest] = v; } : function () {};
    var word = /^([a-z]+)/.exec(body)[1];
    var rest = body.slice(word.length).replace(/^\s+/, "");

    switch (word) {
      case "ret": {
        if (rest === "void") return { ret: function () { return undefined; } };
        var rr = parseType(rest, 0), val = self.operand(rr[0], rest.slice(rr[1]));
        return { ret: function (f) { return val(f); } };
      }
      case "br": {
        if (rest.startsWith("label")) { var to = rest.replace(/^label\s+%/, ""); return { br: function () { return to; } }; }
        var mm = /^i1\s+(\S+),\s*label\s+%(\S+),\s*label\s+%(\S+)$/.exec(rest);
        var c = self.operand({ k: "i", bits: 1 }, mm[1]), a = mm[2], b = mm[3];
        return { br: function (f) { return c(f) ? a : b; } };
      }
      case "switch": {
        var sm = /^(i\d+)\s+(\S+),\s*label\s+%(\S+)\s*\[(.*)\]$/.exec(rest);
        var st = parseType(sm[1], 0)[0], sv = self.operand(st, sm[2]), def = sm[3], cases = {};
        var re = /i\d+\s+(-?\d+),\s*label\s+%(\S+)/g, cm;
        while ((cm = re.exec(sm[4]))) cases[mask(st.bits, BigInt(cm[1])).toString()] = cm[2];
        return { br: function (f) { var k = sv(f).toString(); return k in cases ? cases[k] : def; } };
      }
      case "unreachable": return { br: function () { throw new Error("the program reached unreachable code"); } };
      case "alloca": {
        var at = parseType(rest, 0)[0], sz = L.size(at), al = Math.max(L.align(at), 1);
        return { op: function (f) {
          var s = Math.ceil(self.sp / al) * al; self.sp = s + sz;
          if (self.sp > self.stackEnd) throw new Error("the program used too much stack");
          new Uint8Array(self.mem.buffer, s, sz).fill(0); f.r[dest] = s;
        } };
      }
      case "load": {
        var lp = splitTop(rest), lt = parseType(lp[0], 0)[0], ptr = self.operand({ k: "p" }, lp[1].replace(/^ptr\s+/, ""));
        return { op: function (f) { f.r[dest] = self.load(lt, ptr(f)); } };
      }
      case "store": {
        var sp = splitTop(rest), vr = parseType(sp[0], 0), stype = vr[0];
        var sval = self.operand(stype, sp[0].slice(vr[1])), sptr = self.operand({ k: "p" }, sp[1].replace(/^ptr\s+/, ""));
        return { op: function (f) { self.store(stype, sptr(f), sval(f)); } };
      }
      case "getelementptr": {
        var gp = splitTop(rest.replace(/^inbounds\s+/, "")), gt = parseType(gp[0], 0)[0];
        var base = self.operand({ k: "p" }, gp[1].replace(/^ptr\s+/, ""));
        var idx = gp.slice(2).map(function (x) {
          var r = parseType(x, 0); var bits = L.resolve(r[0]).bits; return { v: self.operand(r[0], x.slice(r[1])), bits: bits };
        });
        return { op: function (f) {
          var ix = idx.map(function (d) { return Number(signed(d.bits, d.v(f))); });
          f.r[dest] = self.gep(gt, base(f), ix);
        } };
      }
      case "icmp": {
        var im = /^(\w+)\s+(.*)$/.exec(rest), ip = splitTop(im[2]), ir = parseType(ip[0], 0), it = L.resolve(ir[0]);
        var ia = self.operand(it, ip[0].slice(ir[1])), ib = self.operand(it, ip[1]), pred = im[1], bits = it.k === "i" ? it.bits : 32;
        if (it.k === "p") return { op: function (f) { f.r[dest] = cmpInt(pred, 32, BigInt(ia(f)), BigInt(ib(f))) ? 1n : 0n; } };
        return { op: function (f) { f.r[dest] = cmpInt(pred, bits, ia(f), ib(f)) ? 1n : 0n; } };
      }
      case "fcmp": {
        var fm = /^(\w+)\s+(.*)$/.exec(rest), fp = splitTop(fm[2]), fr = parseType(fp[0], 0);
        var fa = self.operand(fr[0], fp[0].slice(fr[1])), fb = self.operand(fr[0], fp[1]), fpred = fm[1];
        return { op: function (f) { f.r[dest] = cmpFloat(fpred, fa(f), fb(f)) ? 1n : 0n; } };
      }
      case "add": case "sub": case "mul": case "sdiv": case "udiv": case "srem": case "urem": case "and": case "or": case "xor":
      case "shl": case "lshr": case "ashr": {
        var br2 = rest.replace(/^(?:(?:nsw|nuw|exact)\s+)+/, ""), bp = splitTop(br2), brr = parseType(bp[0], 0), bt = L.resolve(brr[0]);
        var ba = self.operand(bt, bp[0].slice(brr[1])), bb = self.operand(bt, bp[1]), bits2 = bt.bits;
        return { op: function (f) {
          var x = ba(f), y = bb(f), r;
          switch (word) {
            case "add": r = x + y; break; case "sub": r = x - y; break; case "mul": r = x * y; break;
            case "sdiv": if (y === 0n) throw new Error("division by zero"); r = signed(bits2, x) / signed(bits2, y); break;
            case "udiv": if (y === 0n) throw new Error("division by zero"); r = x / y; break;
            case "srem": if (y === 0n) throw new Error("division by zero"); r = signed(bits2, x) % signed(bits2, y); break;
            case "urem": if (y === 0n) throw new Error("division by zero"); r = x % y; break;
            case "and": r = x & y; break; case "or": r = x | y; break; case "xor": r = x ^ y; break;
            case "shl": r = x << y; break; case "lshr": r = x >> y; break; case "ashr": r = signed(bits2, x) >> y; break;
          }
          f.r[dest] = mask(bits2, r);
        } };
      }
      case "fadd": case "fsub": case "fmul": case "fdiv": case "frem": {
        var fp2 = splitTop(rest), fr2 = parseType(fp2[0], 0);
        var xa = self.operand(fr2[0], fp2[0].slice(fr2[1])), xb = self.operand(fr2[0], fp2[1]);
        return { op: function (f) {
          var x = xa(f), y = xb(f);
          f.r[dest] = word === "fadd" ? x + y : word === "fsub" ? x - y : word === "fmul" ? x * y : word === "fdiv" ? x / y : x % y;
        } };
      }
      case "fneg": { var nr = parseType(rest, 0), na = self.operand(nr[0], rest.slice(nr[1])); return { op: function (f) { f.r[dest] = -na(f); } }; }
      case "sext": case "zext": case "trunc": case "sitofp": case "uitofp": case "fptosi": case "fptoui": case "ptrtoint": case "inttoptr": case "bitcast": {
        var cm2 = /^(.*)\s+to\s+(\S+)$/.exec(rest), cr = parseType(cm2[1], 0), st2 = L.resolve(cr[0]), dt = L.resolve(parseType(cm2[2], 0)[0]);
        var cv = self.operand(st2, cm2[1].slice(cr[1]));
        return { op: function (f) {
          var v = cv(f), r;
          switch (word) {
            case "zext": r = v; break;
            case "sext": r = mask(dt.bits, signed(st2.bits, v)); break;
            case "trunc": r = mask(dt.bits, v); break;
            case "sitofp": r = Number(signed(st2.bits, v)); break;
            case "uitofp": r = Number(v); break;
            case "fptosi": case "fptoui": r = (v !== v || !isFinite(v)) ? 0n : mask(dt.bits, BigInt(Math.trunc(v))); break;
            case "ptrtoint": r = mask(dt.bits, BigInt(v)); break;
            case "inttoptr": r = Number(mask(32, v)); break;
            default: r = v;
          }
          f.r[dest] = r;
        } };
      }
      case "select": {
        var slp = splitTop(rest), sc = self.operand({ k: "i", bits: 1 }, slp[0].replace(/^i1\s+/, ""));
        var s1 = parseType(slp[1], 0), s2 = parseType(slp[2], 0);
        var sa = self.operand(s1[0], slp[1].slice(s1[1])), sb = self.operand(s2[0], slp[2].slice(s2[1]));
        return { op: function (f) { f.r[dest] = sc(f) ? sa(f) : sb(f); } };
      }
      case "phi": {
        var pr = parseType(rest, 0), pt = pr[0], arms = [], re2 = /\[\s*([^,\]]+),\s*%([\w.$]+)\s*\]/g, pm;
        while ((pm = re2.exec(rest.slice(pr[1])))) arms.push([pm[2], self.operand(pt, pm[1])]);
        return { phi: true, op: function (f) { for (var i = 0; i < arms.length; i++) if (arms[i][0] === f.prev) { f.r[dest] = arms[i][1](f); return; } throw new Error("bad phi"); } };
      }
      case "extractvalue": {
        var ep = splitTop(rest), er = parseType(ep[0], 0), ev = self.operand(er[0], ep[0].slice(er[1])), ei = +ep[1];
        return { op: function (f) { f.r[dest] = ev(f)[ei]; } };
      }
      case "tail": case "call": return self.compileCall(dest, body.replace(/^tail\s+/, ""));
    }
    throw new Error("unsupported instruction in IR: " + text.slice(0, 80));
  };

  Machine.prototype.compileCall = function (dest, body) {
    var self = this, L = this.layout;
    var m = /^call\s+(.*?)\s*(@[\w.$]+|%[\w.$]+)\((.*)\)\s*$/s.exec(body);
    if (!m) throw new Error("cannot read call: " + body.slice(0, 80));
    var retText = m[1].replace(/\s*\(.*\)\s*$/, ""), rtype = parseType(retText, 0)[0], callee = m[2];
    var args = splitTop(m[3]).map(function (a) {
      var r = parseType(a, 0); var t = L.resolve(r[0]);
      return { type: t, val: self.operand(t, a.slice(r[1]).replace(/^(?:(?:noundef|signext|zeroext)\s+)+/, "")) };
    });
    var rt = L.resolve(rtype);
    var st = function (f, v) { if (dest) f.r[dest] = v; };
    if (callee[0] === "%") {
      var fp = callee;
      return { op: function (f) { var name = self.fnByAddr[f.r[fp]]; st(f, self.invoke(name, args.map(function (a) { return a.val(f); }), rt)); } };
    }
    var name = callee.slice(1);
    return { op: function (f) { st(f, self.invoke(name, args.map(function (a) { return a.val(f); }), rt, args)); } };
  };

  // ---- calling
  Machine.prototype.invoke = function (name, vals, rt, args) {
    var fn = this.funcs[name];
    if (fn) return this.exec(fn, vals);
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

  Machine.prototype.exec = function (fn, vals) {
    var f = { r: {}, prev: null }, i, savedSp = this.sp;
    for (i = 0; i < fn.params.length; i++) if (fn.params[i].name) f.r[fn.params[i].name] = vals[i];
    var blk = fn.order[0], self = this;
    try {
      for (;;) {
        var code = blk.code, next = null, j, ins;
        // phi nodes read the values from before this block began, so evaluate them first
        for (j = 0; j < code.length; j++) {
          ins = code[j];
          if (ins.phi) ins.op(f); else break;
        }
        for (; j < code.length; j++) {
          ins = code[j];
          if (this.deadline && (++this.steps & 0xfff) === 0 && Date.now() > this.deadline) throw { timeout: true };
          if (ins.op) ins.op(f);
          else if (ins.ret) return ins.ret(f);
          else { next = ins.br(f); break; }
        }
        if (next === null) throw new Error("a block ended without a branch");
        f.prev = blk.label; blk = fn.blocks[next];
      }
    } finally { this.sp = savedSp; }
  };

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
