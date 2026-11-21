// A small WASI (preview 1) host for the Tomato compiler and runtime: command-line arguments, standard output and error,
// and an in-memory file system (a map of path -> bytes) so the compiler can read the program and the standard library.
// No server: this is all the browser needs to run tomatoc.wasm.
(function () {
  var ERRNO = { SUCCESS: 0, BADF: 8, EXIST: 20, INVAL: 28, NOENT: 44, NOSYS: 52 };

  function WasiHost(options) {
    this.args = options.args || [];
    this.files = options.files || {};                 // "/path" -> Uint8Array
    this.stdout = []; this.stderr = [];
    this.fds = {};                                    // fd -> {path, data, pos, write}
    this.nextFd = 4;
    this.exitCode = null;
    this.memory = null;
    this.onStdout = options.onStdout || null;
  }
  WasiHost.prototype.view = function () { return new DataView(this.memory.buffer); };
  WasiHost.prototype.bytes = function () { return new Uint8Array(this.memory.buffer); };
  WasiHost.prototype.str = function (ptr, len) { return new TextDecoder().decode(this.bytes().subarray(ptr, ptr + len)); };
  WasiHost.prototype.text = function (which) { return new TextDecoder().decode(concat(which === "out" ? this.stdout : this.stderr)); };

  function concat(chunks) {
    var n = 0; chunks.forEach(function (c) { n += c.length; });
    var out = new Uint8Array(n), o = 0;
    chunks.forEach(function (c) { out.set(c, o); o += c.length; });
    return out;
  }
  function norm(dirPath, rel) {
    var parts = (dirPath + "/" + rel).split("/"), out = [];
    parts.forEach(function (p) { if (p === "" || p === ".") return; if (p === "..") out.pop(); else out.push(p); });
    return "/" + out.join("/");
  }

  WasiHost.prototype.imports = function (module) {
    var h = this;
    var wasi = {
      args_sizes_get: function (argc, size) {
        var v = h.view(), total = 0;
        h.args.forEach(function (a) { total += new TextEncoder().encode(a).length + 1; });
        v.setUint32(argc, h.args.length, true); v.setUint32(size, total, true); return ERRNO.SUCCESS;
      },
      args_get: function (argv, buf) {
        var v = h.view(), b = h.bytes(), p = buf;
        h.args.forEach(function (a, i) {
          var e = new TextEncoder().encode(a);
          v.setUint32(argv + i * 4, p, true); b.set(e, p); b[p + e.length] = 0; p += e.length + 1;
        });
        return ERRNO.SUCCESS;
      },
      environ_sizes_get: function (n, size) { var v = h.view(); v.setUint32(n, 0, true); v.setUint32(size, 0, true); return ERRNO.SUCCESS; },
      environ_get: function () { return ERRNO.SUCCESS; },
      clock_time_get: function (id, prec, out) { h.view().setBigUint64(out, BigInt(Date.now()) * 1000000n, true); return ERRNO.SUCCESS; },
      random_get: function (buf, len) { crypto.getRandomValues(h.bytes().subarray(buf, buf + len)); return ERRNO.SUCCESS; },
      proc_exit: function (code) { h.exitCode = code; throw { wasiExit: code }; },
      sched_yield: function () { return ERRNO.SUCCESS; },
      fd_prestat_get: function (fd, out) {
        if (fd !== 3) return ERRNO.BADF;
        var v = h.view(); v.setUint8(out, 0); v.setUint32(out + 4, 1, true); return ERRNO.SUCCESS;
      },
      fd_prestat_dir_name: function (fd, ptr, len) { if (fd !== 3) return ERRNO.BADF; h.bytes()[ptr] = 47; return ERRNO.SUCCESS; },
      fd_fdstat_get: function (fd, out) {
        var v = h.view(); var type = fd <= 2 ? 2 : (fd === 3 ? 3 : 4);
        v.setUint8(out, type); v.setUint16(out + 2, 0, true); v.setBigUint64(out + 8, 0xffffffffffffffffn, true); v.setBigUint64(out + 16, 0xffffffffffffffffn, true);
        return ERRNO.SUCCESS;
      },
      fd_fdstat_set_flags: function () { return ERRNO.SUCCESS; },
      fd_filestat_get: function (fd, out) {
        var f = h.fds[fd]; var v = h.view();
        for (var i = 0; i < 64; i += 8) v.setBigUint64(out + i, 0n, true);
        v.setUint8(out + 16, f ? 4 : 2);
        if (f) v.setBigUint64(out + 32, BigInt(f.data.length), true);
        return ERRNO.SUCCESS;
      },
      path_filestat_get: function (dirfd, flags, ptr, len, out) {
        var p = norm("/", h.str(ptr, len)); var v = h.view();
        if (!(p in h.files)) return ERRNO.NOENT;
        for (var i = 0; i < 64; i += 8) v.setBigUint64(out + i, 0n, true);
        v.setUint8(out + 16, 4); v.setBigUint64(out + 32, BigInt(h.files[p].length), true);
        return ERRNO.SUCCESS;
      },
      path_open: function (dirfd, dirflags, ptr, len, oflags, rb, ri, fdflags, outfd) {
        var p = norm("/", h.str(ptr, len)), create = (oflags & 1) !== 0, trunc = (oflags & 8) !== 0;
        var wants = Number(rb & 64n) !== 0 || Number(rb & 2n) !== 0;   // fd_write or fd_datasync rights
        if (!(p in h.files)) { if (!create) return ERRNO.NOENT; h.files[p] = new Uint8Array(0); }
        else if (trunc) h.files[p] = new Uint8Array(0);
        var fd = h.nextFd++;
        h.fds[fd] = { path: p, data: h.files[p], pos: 0, write: create || wants };
        h.view().setUint32(outfd, fd, true); return ERRNO.SUCCESS;
      },
      fd_close: function (fd) { delete h.fds[fd]; return ERRNO.SUCCESS; },
      fd_seek: function (fd, off, whence, out) {
        var f = h.fds[fd]; if (!f) return ERRNO.BADF;
        var o = Number(off); f.pos = whence === 0 ? o : whence === 1 ? f.pos + o : f.data.length + o;
        h.view().setBigUint64(out, BigInt(f.pos), true); return ERRNO.SUCCESS;
      },
      fd_tell: function (fd, out) { var f = h.fds[fd]; if (!f) return ERRNO.BADF; h.view().setBigUint64(out, BigInt(f.pos), true); return ERRNO.SUCCESS; },
      fd_read: function (fd, iovs, n, out) {
        var f = h.fds[fd]; if (!f) return ERRNO.BADF;
        var v = h.view(), b = h.bytes(), total = 0;
        for (var i = 0; i < n; i++) {
          var p = v.getUint32(iovs + i * 8, true), l = v.getUint32(iovs + i * 8 + 4, true);
          var k = Math.min(l, f.data.length - f.pos);
          b.set(f.data.subarray(f.pos, f.pos + k), p); f.pos += k; total += k;
          if (k < l) break;
        }
        v.setUint32(out, total, true); return ERRNO.SUCCESS;
      },
      fd_write: function (fd, iovs, n, out) {
        var v = h.view(), b = h.bytes(), total = 0, chunks = [];
        for (var i = 0; i < n; i++) {
          var p = v.getUint32(iovs + i * 8, true), l = v.getUint32(iovs + i * 8 + 4, true);
          chunks.push(b.slice(p, p + l)); total += l;
        }
        var data = concat(chunks);
        if (fd === 1) { h.stdout.push(data); if (h.onStdout) h.onStdout(data); }
        else if (fd === 2) h.stderr.push(data);
        else if (h.fds[fd]) {
          var f = h.fds[fd], end = f.pos + data.length;
          if (end > f.data.length) { var nd = new Uint8Array(end); nd.set(f.data); f.data = nd; }
          f.data.set(data, f.pos); f.pos = end; h.files[f.path] = f.data;
        } else return ERRNO.BADF;
        v.setUint32(out, total, true); return ERRNO.SUCCESS;
      },
      path_create_directory: function () { return ERRNO.SUCCESS; },
      path_unlink_file: function (dirfd, ptr, len) { delete h.files[norm("/", h.str(ptr, len))]; return ERRNO.SUCCESS; }
    };
    wasi.clock_res_get = function (id, out) { h.view().setBigUint64(out, 1000000n, true); return ERRNO.SUCCESS; };
    if (module) WebAssembly.Module.imports(module).forEach(function (i) {   // anything not implemented answers "not supported"
      if (i.module === "wasi_snapshot_preview1" && !(i.name in wasi)) wasi[i.name] = function () { return ERRNO.NOSYS; };
    });
    return { wasi_snapshot_preview1: wasi };
  };

  // Runs a WASI command module to completion; returns { code, stdout, stderr, files }.
  WasiHost.prototype.run = function (module) {
    var h = this;
    return WebAssembly.instantiate(module, h.imports(module)).then(function (inst) {
      h.memory = inst.exports.memory;
      try { inst.exports._start(); h.exitCode = 0; }
      catch (e) { if (!(e && e.wasiExit !== undefined)) throw e; }
      return { code: h.exitCode, stdout: h.text("out"), stderr: h.text("err"), files: h.files, instance: inst };
    });
  };
  self.WasiHost = WasiHost;
})();
