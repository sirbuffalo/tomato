#!/bin/sh
# Installs the toolchains the Linux x86-64 part of a release needs (release/release.sh, step "linux") into one folder, with no root:
# clang (LLVM prebuilt), Go, Rust (rustup, minimal profile), Valgrind (built from source). Run it ON the Linux machine:
#   ssh biggie.davismcd.com 'sh -s' < release/linux-setup.sh        (or copy it there)
# Environment: TOMATO_LINUX_TOOLS (default ~/.tomato-release/linux-tools), LLVM_VERSION (21.1.8), GO_VERSION (1.27.4),
# VALGRIND_VERSION (3.26.0). Re-running skips what is already installed. Needs curl, tar, xz, bzip2, gcc, make and nm (binutils), and cmake when libxml2 has to be built.
# Checksums: Go is verified against go.dev's published sha256, rustup-init against static.rust-lang.org's, libxml2 (built for lld) against
# the .sha256sum that download.gnome.org publishes beside it; LLVM and Valgrind come
# over https from their official download locations and their sha256 is written to SHA256SUMS in the folder for later comparison.
set -e
prefix="${TOMATO_LINUX_TOOLS:-$HOME/.tomato-release/linux-tools}"
llvm="${LLVM_VERSION:-21.1.8}"; gov="${GO_VERSION:-1.27.4}"; vg="${VALGRIND_VERSION:-3.26.0}"
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || { echo "error: this installs Linux x86-64 tools" >&2; exit 1; }
for t in curl tar xz bzip2 gcc make nm; do command -v "$t" >/dev/null 2>&1 || { echo "error: $t is needed to install the toolchains" >&2; exit 1; }; done
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

# (The wrapper below runs $prefix/llvm/bin/clang, so a matching clang elsewhere is not enough.)
if [ ! -x "$prefix/llvm/bin/clang" ] || ! "$prefix/llvm/bin/clang" --version | grep -q "version $llvm"; then
  log "clang $llvm (LLVM prebuilt)"
  f="LLVM-$llvm-Linux-X64.tar.xz"; curl -fsSL -o "$f" "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvm/$f"
  record "$prefix/dl/$f" 2>/dev/null || true
  rm -rf "$prefix/llvm"; mkdir -p "$prefix/llvm"; tar -C "$prefix/llvm" --strip-components=1 -xJf "$f"
  rm -f "$f"
fi
# The LLVM prebuilt lld needs libxml2.so.2, absent on newer Ubuntu releases. Build that ABI locally, and use lld explicitly:
# the LLVM archive does not include the LLVMgold plugin needed by the system linker. Wrappers keep the library path local to lld.
if [ ! -f "$prefix/libxml2/lib/libxml2.so.2" ]; then
  log "libxml2 2.13.9 (for lld)"
  command -v cmake >/dev/null 2>&1 || { echo "error: cmake is needed to build libxml2 for lld" >&2; exit 1; }
  f="libxml2-2.13.9.tar.xz"; curl -fsSL -o "$f" "https://download.gnome.org/sources/libxml2/2.13/$f"
  want="$(curl -fsSL "https://download.gnome.org/sources/libxml2/2.13/libxml2-2.13.9.sha256sum" | awk -v f="$f" '$2 == f { print $1 }')"
  got="$(sha256sum "$f" 2>/dev/null || shasum -a 256 "$f")"; got="${got%% *}"
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "error: $f does not match the sha256 that download.gnome.org publishes" >&2; rm -f "$f"; exit 1; }
  record "$prefix/dl/$f"
  rm -rf src-libxml2; mkdir src-libxml2; tar -C src-libxml2 --strip-components=1 -xJf "$f"
  cmake -S src-libxml2 -B src-libxml2/build -DCMAKE_INSTALL_PREFIX="$prefix/libxml2" -DCMAKE_INSTALL_LIBDIR=lib -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_TESTS=OFF > src-libxml2/configure.log 2>&1
  cmake --build src-libxml2/build -j 2 > src-libxml2/build.log 2>&1
  cmake --install src-libxml2/build > src-libxml2/install.log 2>&1
fi
rm -f "$prefix/bin/clang" "$prefix/bin/ld.lld"
printf '#!/bin/sh\nexec "%s/llvm/bin/clang" -Wno-unused-command-line-argument --ld-path="%s/bin/ld.lld" "$@"\n' "$prefix" "$prefix" > "$prefix/bin/clang"
printf '#!/bin/sh\nLD_LIBRARY_PATH="%s/libxml2/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "%s/llvm/bin/ld.lld" "$@"\n' "$prefix" "$prefix" > "$prefix/bin/ld.lld"
chmod +x "$prefix/bin/clang" "$prefix/bin/ld.lld"
hash -r
clang --version | head -1
probe="$(mktemp -d)"
printf 'int value(void) { return 42; }\n' > "$probe/a.c"
printf 'int value(void); int main(void) { return value() != 42; }\n' > "$probe/b.c"
# (the same probe as release/check-lto.sh, which cannot be read here: this script is piped over ssh; change both together)
if ! clang -O2 -flto "$probe/a.c" "$probe/b.c" -o "$probe/test" || ! "$probe/test" || ! nm "$probe/test" | grep -q ' main$' || nm "$probe/test" | grep -q ' value$'; then
  rm -rf "$probe"; echo "error: clang did not perform cross-module LTO" >&2; exit 1
fi
rm -rf "$probe"

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
