// A small WASI (preview 1) host for the Tomato compiler and runtime: command-line arguments, standard output and error,
// and an in-memory file system (a map of path -> bytes) so the compiler can read the program and the standard library.
// No server: this is all the browser needs to run tomatoc.wasm.
(function () {
  var ERRNO = { SUCCESS: 0, ACCES: 2, BADF: 8, EXIST: 20, INVAL: 28, ISDIR: 31, NOENT: 44, NOSYS: 52, NOTDIR: 54, NOTEMPTY: 55 };

  function WasiHost(options) {
    this.args = options.args || [];
    this.files = options.files || {};                 // "/path" -> Uint8Array
    this.dirs = { "/": true, "/tmp": true };          // the directories made explicitly (a path that is a prefix of a file is a directory too)
    this.mtimes = {};                                 // "/path" -> modification time in nanoseconds (BigInt), for files and directories
    this.stdout = []; this.stderr = [];
    this.fds = {};                                    // fd -> {path, data, pos, write}
    this.nextFd = 4;
    this.exitCode = null;
    this.memory = null;
    this.onStdout = options.onStdout || null;
    this.stdin = options.stdin || new Uint8Array(0);   // what the program reads with input(): all of it, then end of input
    this.stdinPos = 0;
    this.env = options.env || [];                     // "NAME=value" strings
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

  // directories over the file map (the playground has no real file system): "/" and "/tmp", the ones made with mkdir, and the
  // folders that hold a file
  WasiHost.prototype.isDir = function (p) {
    if (p === "/" || this.dirs[p]) return true;
    var pre = p + "/";
    for (var k in this.files) if (k.indexOf(pre) === 0) return true;
    for (var d in this.dirs) if (d.indexOf(pre) === 0) return true;
    return false;
  };
  WasiHost.prototype.entries = function (p) {      // the names in directory p, sorted by bytes: [[name, isDir], ...]
    var pre = p === "/" ? "/" : p + "/", seen = {}, out = [], self = this;
    var add = function (path, isLeaf) {
      if (path.indexOf(pre) !== 0 || path === p) return;
      var rest = path.slice(pre.length), slash = rest.indexOf("/"), name = slash < 0 ? rest : rest.slice(0, slash);
      if (name === "") return;
      var dir = slash >= 0 || !isLeaf;
      if (!(name in seen)) { seen[name] = out.length; out.push([name, dir]); } else if (dir) out[seen[name]][1] = true;
    };
    for (var k in this.files) add(k, true);
    for (var d in this.dirs) add(d, false);
    var enc = new TextEncoder();
    out.sort(function (a, b) {
      var x = enc.encode(a[0]), y = enc.encode(b[0]);
      for (var i = 0; i < x.length && i < y.length; i++) if (x[i] !== y[i]) return x[i] - y[i];
      return x.length - y.length;
    });
    return out;
  };
  // a path given relative to a directory descriptor: 3 is "/", and an opened directory (opendir, readdir) is its own path
  WasiHost.prototype.at = function (dirfd, ptr, len) {
    var d = this.fds[dirfd];
    return norm(d && d.dir ? d.path : "/", this.str(ptr, len));
  };
  WasiHost.prototype.parentOf = function (p) { var i = p.lastIndexOf("/"); return i <= 0 ? "/" : p.slice(0, i); };
  WasiHost.prototype.touch = function (p) { this.mtimes[p] = BigInt(Date.now()) * 1000000n; };

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
      environ_sizes_get: function (n, size) {
        var v = h.view(), total = 0;
        h.env.forEach(function (a) { total += new TextEncoder().encode(a).length + 1; });
        v.setUint32(n, h.env.length, true); v.setUint32(size, total, true); return ERRNO.SUCCESS;
      },
      environ_get: function (ptrs, buf) {
        var v = h.view(), b = h.bytes(), p = buf;
        h.env.forEach(function (a, i) {
          var e = new TextEncoder().encode(a);
          v.setUint32(ptrs + i * 4, p, true); b.set(e, p); b[p + e.length] = 0; p += e.length + 1;
        });
        return ERRNO.SUCCESS;
      },
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
        var v = h.view(); var type = fd <= 2 ? 2 : (fd === 3 || (h.fds[fd] && h.fds[fd].dir) ? 3 : 4);
        v.setUint8(out, type); v.setUint16(out + 2, 0, true); v.setBigUint64(out + 8, 0xffffffffffffffffn, true); v.setBigUint64(out + 16, 0xffffffffffffffffn, true);
        return ERRNO.SUCCESS;
      },
      fd_fdstat_set_flags: function () { return ERRNO.SUCCESS; },
      fd_filestat_get: function (fd, out) {
        var f = h.fds[fd]; var v = h.view();
        for (var i = 0; i < 64; i += 8) v.setBigUint64(out + i, 0n, true);
        v.setUint8(out + 16, f ? (f.dir ? 3 : 4) : 2);
        if (f && !f.dir) { v.setBigUint64(out + 32, BigInt(f.data.length), true); v.setBigUint64(out + 48, h.mtimes[f.path] || 0n, true); }
        return ERRNO.SUCCESS;
      },
      path_filestat_get: function (dirfd, flags, ptr, len, out) {
        var p = h.at(dirfd, ptr, len); var v = h.view();
        var isFile = p in h.files, isDir = !isFile && h.isDir(p);
        if (!isFile && !isDir) return ERRNO.NOENT;
        for (var i = 0; i < 64; i += 8) v.setBigUint64(out + i, 0n, true);
        v.setUint8(out + 16, isFile ? 4 : 3); v.setBigUint64(out + 24, 1n, true);
        if (isFile) v.setBigUint64(out + 32, BigInt(h.files[p].length), true);
        v.setBigUint64(out + 48, h.mtimes[p] || 0n, true);
        return ERRNO.SUCCESS;
      },
      path_open: function (dirfd, dirflags, ptr, len, oflags, rb, ri, fdflags, outfd) {
        var p = h.at(dirfd, ptr, len), create = (oflags & 1) !== 0, wantDir = (oflags & 2) !== 0, excl = (oflags & 4) !== 0, trunc = (oflags & 8) !== 0;
        var wants = Number(rb & 64n) !== 0 || Number(rb & 2n) !== 0;   // fd_write or fd_datasync rights
        var fd;
        if (!(p in h.files) && h.isDir(p)) {          // a directory: it can be listed and examined, not written
          if (excl && create) return ERRNO.EXIST;
          if (!wantDir && (create || trunc || wants)) return ERRNO.ISDIR;
          fd = h.nextFd++; h.fds[fd] = { path: p, dir: true, pos: 0 };
          h.view().setUint32(outfd, fd, true); return ERRNO.SUCCESS;
        }
        if (wantDir) return (p in h.files) ? ERRNO.NOTDIR : ERRNO.NOENT;
        if (!(p in h.files)) {
          if (!create) return ERRNO.NOENT;
          var parent = h.parentOf(p);
          if (parent in h.files) return ERRNO.NOTDIR;
          if (!h.isDir(parent)) return ERRNO.NOENT;
          h.files[p] = new Uint8Array(0); h.touch(p);
        } else if (create && excl) return ERRNO.EXIST;
        else if (trunc) { h.files[p] = new Uint8Array(0); h.touch(p); }
        fd = h.nextFd++;
        h.fds[fd] = { path: p, data: h.files[p], pos: 0, write: create || wants, append: (fdflags & 1) !== 0 };
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
        if (fd === 0) {
          var v0 = h.view(), b0 = h.bytes(), total0 = 0;
          for (var j = 0; j < n; j++) {
            var p0 = v0.getUint32(iovs + j * 8, true), l0 = v0.getUint32(iovs + j * 8 + 4, true);
            var k0 = Math.min(l0, h.stdin.length - h.stdinPos);
            b0.set(h.stdin.subarray(h.stdinPos, h.stdinPos + k0), p0); h.stdinPos += k0; total0 += k0;
            if (k0 < l0) break;
          }
          v0.setUint32(out, total0, true); return ERRNO.SUCCESS;
        }
        var f = h.fds[fd]; if (!f) return ERRNO.BADF;
        if (f.dir) return ERRNO.ISDIR;
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
          var f = h.fds[fd]; if (f.dir) return ERRNO.ISDIR;
          if (f.append) f.pos = f.data.length;
          var end = f.pos + data.length;
          if (end > f.data.length) { var nd = new Uint8Array(end); nd.set(f.data); f.data = nd; }
          f.data.set(data, f.pos); f.pos = end; h.files[f.path] = f.data; h.touch(f.path);
        } else return ERRNO.BADF;
        v.setUint32(out, total, true); return ERRNO.SUCCESS;
      },
      fd_readdir: function (fd, buf, buflen, cookie, outused) {
        var f = h.fds[fd]; if (!f || !f.dir) return ERRNO.BADF;
        var enc = new TextEncoder(), list = h.entries(f.path), parts = [], total = 0;
        for (var i = Number(cookie); i < list.length; i++) {
          var name = enc.encode(list[i][0]), rec = new Uint8Array(24 + name.length), dv = new DataView(rec.buffer);
          dv.setBigUint64(0, BigInt(i + 1), true); dv.setUint32(16, name.length, true); dv.setUint8(20, list[i][1] ? 3 : 4);
          rec.set(name, 24); parts.push(rec); total += rec.length;
        }
        var all = concat(parts), n = Math.min(buflen, all.length);
        h.bytes().set(all.subarray(0, n), buf); h.view().setUint32(outused, n, true); return ERRNO.SUCCESS;
      },
      path_create_directory: function (dirfd, ptr, len) {
        var p = h.at(dirfd, ptr, len);
        if (p in h.files || h.isDir(p)) return ERRNO.EXIST;
        var parent = h.parentOf(p);
        if (parent in h.files) return ERRNO.NOTDIR;
        if (!h.isDir(parent)) return ERRNO.NOENT;
        h.dirs[p] = true; h.touch(p); return ERRNO.SUCCESS;
      },
      path_remove_directory: function (dirfd, ptr, len) {
        var p = h.at(dirfd, ptr, len);
        if (p in h.files) return ERRNO.NOTDIR;
        if (!h.isDir(p)) return ERRNO.NOENT;
        if (h.entries(p).length > 0) return ERRNO.NOTEMPTY;
        if (p === "/") return ERRNO.INVAL;
        delete h.dirs[p]; return ERRNO.SUCCESS;
      },
      path_rename: function (oldfd, optr, olen, newfd, nptr, nlen) {
        var a = h.at(oldfd, optr, olen), b = h.at(newfd, nptr, nlen);
        var aFile = a in h.files, aDir = !aFile && h.isDir(a);
        if (!aFile && !aDir) return ERRNO.NOENT;
        if (a === b) return ERRNO.SUCCESS;
        var bFile = b in h.files, bDir = !bFile && h.isDir(b), parent = h.parentOf(b);
        if (parent in h.files) return ERRNO.NOTDIR;
        if (!h.isDir(parent)) return ERRNO.NOENT;
        if (aFile) {
          if (bDir) return ERRNO.ISDIR;
          h.files[b] = h.files[a]; delete h.files[a];
          if (h.mtimes[a] !== undefined) { h.mtimes[b] = h.mtimes[a]; delete h.mtimes[a]; }
          return ERRNO.SUCCESS;
        }
        if (bFile) return ERRNO.NOTDIR;
        if (bDir && h.entries(b).length > 0) return ERRNO.NOTEMPTY;
        if (b.indexOf(a + "/") === 0) return ERRNO.INVAL;
        var pre = a + "/", moved = [];
        Object.keys(h.files).forEach(function (k) { if (k.indexOf(pre) === 0) moved.push([k, b + k.slice(a.length), true]); });
        Object.keys(h.dirs).forEach(function (k) { if (k.indexOf(pre) === 0) moved.push([k, b + k.slice(a.length), false]); });
        moved.push([a, b, false]);
        moved.forEach(function (m) {
          if (m[2]) { h.files[m[1]] = h.files[m[0]]; delete h.files[m[0]]; } else { h.dirs[m[1]] = true; delete h.dirs[m[0]]; }
          if (h.mtimes[m[0]] !== undefined) { h.mtimes[m[1]] = h.mtimes[m[0]]; delete h.mtimes[m[0]]; }
        });
        h.dirs[b] = true; return ERRNO.SUCCESS;
      },
      path_unlink_file: function (dirfd, ptr, len) {
        var p = h.at(dirfd, ptr, len);
        if (!(p in h.files)) return h.isDir(p) ? ERRNO.ISDIR : ERRNO.NOENT;
        delete h.files[p]; delete h.mtimes[p]; return ERRNO.SUCCESS;
      }
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
