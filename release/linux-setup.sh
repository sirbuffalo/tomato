#!/bin/sh
# Installs the toolchains the Linux x86-64 part of a release needs (release/release.sh, step "linux") into one folder, with no root:
# clang (LLVM prebuilt), Go, Rust (rustup, minimal profile), Valgrind (built from source). Run it ON the Linux machine:
#   ssh biggie.davismcd.com 'sh -s' < release/linux-setup.sh        (or copy it there)
# Environment: TOMATO_LINUX_TOOLS (default ~/.tomato-release/linux-tools), LLVM_VERSION (21.1.8), GO_VERSION (1.27.4),
# VALGRIND_VERSION (3.26.0). Re-running skips what is already installed. Needs curl, tar, xz, bzip2, gcc and make.
# Checksums: Go is verified against go.dev's published sha256, rustup-init against static.rust-lang.org's; LLVM and Valgrind come
# over https from their official download locations and their sha256 is written to SHA256SUMS in the folder for later comparison.
set -e
prefix="${TOMATO_LINUX_TOOLS:-$HOME/.tomato-release/linux-tools}"
llvm="${LLVM_VERSION:-21.1.8}"; gov="${GO_VERSION:-1.27.4}"; vg="${VALGRIND_VERSION:-3.26.0}"
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || { echo "error: this installs Linux x86-64 tools" >&2; exit 1; }
for t in curl tar xz bzip2 gcc make; do command -v "$t" >/dev/null 2>&1 || { echo "error: $t is needed to install the toolchains" >&2; exit 1; }; done
mkdir -p "$prefix/bin" "$prefix/dl"; cd "$prefix/dl"
log() { printf '== %s\n' "$*"; }
record() { shasum -a 256 "$1" 2>/dev/null >> "$prefix/SHA256SUMS" || sha256sum "$1" >> "$prefix/SHA256SUMS"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
export PATH="$prefix/bin:$prefix/llvm/bin:$prefix/go/bin:$prefix/cargo/bin:$PATH"

if ! command -v go >/dev/null 2>&1 || ! go version | grep -q "go$gov "; then
  log "Go $gov"
  f="go$gov.linux-amd64.tar.gz"; curl -fsSL -o "$f" "https://go.dev/dl/$f"
  want="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' | tr ',{' '\n\n' | awk -v f="\"$f\"" '$0 ~ "\"filename\": *" f { hit = 1 } hit && /"sha256"/ { gsub(/.*: *"|".*/, ""); print; exit }')"
  [ -n "$want" ] && [ "$(sha "$f")" = "$want" ] || { echo "error: Go tarball checksum mismatch (want '$want')" >&2; exit 1; }
  rm -rf "$prefix/go"; tar -C "$prefix" -xzf "$f"; ln -sf "$prefix/go/bin/go" "$prefix/bin/go"; ln -sf "$prefix/go/bin/gofmt" "$prefix/bin/gofmt"
fi
go version

if ! command -v rustc >/dev/null 2>&1; then
  log "Rust (rustup, minimal)"
  u="https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
  curl -fsSL -o rustup-init "$u"; want="$(curl -fsSL "$u.sha256" | cut -d' ' -f1)"
  [ "$(sha rustup-init)" = "$want" ] || { echo "error: rustup-init checksum mismatch" >&2; exit 1; }
  chmod +x rustup-init
  RUSTUP_HOME="$prefix/rustup" CARGO_HOME="$prefix/cargo" ./rustup-init -y --profile minimal --no-modify-path --default-toolchain stable
  # cargo needs the same homes every time: small wrappers
  for b in rustc cargo; do printf '#!/bin/sh\nRUSTUP_HOME="%s" CARGO_HOME="%s" exec "%s/cargo/bin/%s" "$@"\n' "$prefix/rustup" "$prefix/cargo" "$prefix" "$b" > "$prefix/bin/$b"; chmod +x "$prefix/bin/$b"; done
fi
rustc --version

if ! command -v clang >/dev/null 2>&1 || ! clang --version | grep -q "version $llvm"; then
  log "clang $llvm (LLVM prebuilt)"
  f="LLVM-$llvm-Linux-X64.tar.xz"; curl -fsSL -o "$f" "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvm/$f"
  record "$prefix/dl/$f" 2>/dev/null || true
  rm -rf "$prefix/llvm"; mkdir -p "$prefix/llvm"; tar -C "$prefix/llvm" --strip-components=1 -xJf "$f"
  ln -sf "$prefix/llvm/bin/clang" "$prefix/bin/clang"
  rm -f "$f"
fi
clang --version | head -1

if ! command -v valgrind >/dev/null 2>&1 || ! valgrind --version | grep -q "$vg"; then
  log "Valgrind $vg (from source)"
  f="valgrind-$vg.tar.bz2"; curl -fsSL -o "$f" "https://sourceware.org/pub/valgrind/$f"
  record "$prefix/dl/$f" 2>/dev/null || true
  rm -rf "src-valgrind"; mkdir src-valgrind; tar -C src-valgrind --strip-components=1 -xjf "$f"
  (cd src-valgrind && ./configure --prefix="$prefix/valgrind" > configure.log 2>&1 && make -j"$(nproc)" > make.log 2>&1 && make install > install.log 2>&1) || { echo "error: building Valgrind failed (see $prefix/dl/src-valgrind/*.log)" >&2; exit 1; }
  ln -sf "$prefix/valgrind/bin/valgrind" "$prefix/bin/valgrind"
fi
valgrind --version
# does it work on this system's C library (some need libc6-dbg symbols for ld.so redirection)?
if ! valgrind --tool=none /bin/true > "$prefix/dl/vg-probe.txt" 2>&1; then cat "$prefix/dl/vg-probe.txt" >&2; echo "error: valgrind cannot run /bin/true here (needs libc debug symbols: apt-get download libc6-dbg, dpkg -x it, and point valgrind at it with --extra-debuginfo-path)" >&2; exit 1; fi
echo "linux tools ready in $prefix (add $prefix/bin to PATH; release/release.sh does that itself)"
