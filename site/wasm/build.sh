#!/bin/sh
# Builds the WebAssembly files the website runs in the browser (committed, so Pages needs no toolchain):
#   tomatoc.wasm  the compiler written in Tomato (compiler/bootstrap/tomatoc.ll) plus the C runtime
#   runtime.wasm  the C runtime alone, exporting the tomato_* functions the IR interpreter (llvm.js) calls
# Needs WASI SDK 24 (https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-24) for any host:
#   WASI_SDK=~/wasi-sdk-24.0-arm64-macos sh site/wasm/build.sh   (or wasi-sdk-24.0-x86_64-linux, ...)
#
# The output is byte-identical on every host (macOS arm64 and Linux x86-64 are checked), so wasm built on Linux passes the
# Mac release check "wasm files rebuild identically". What makes that hold (docs/releasing.md, "The wasm files"):
#   - the SDK is pinned: exactly the clang of WASI SDK 24 and its wasi-libc (libc.a is the same file in every host's SDK)
#   - -Wl,--strip-debug: each host's SDK builds its own compiler-rt, and its debug info names that host's build folder
#     (/Users/runner/work/... on macOS, /src/src/... on Linux); without debug sections the linked bytes are the same
#   - no -g and no __FILE__ in our sources, so the repository's folder and the temporary folder never reach the output
#   - the compiler-rt functions whose code or data differ between hosts (trapping arithmetic that embeds __FILE__,
#     __clear_cache, __multc3) must not be linked in; the build stops if one is
# sh site/wasm/sections.sh A.wasm B.wasm says which sections differ when two builds do not match.
set -e
: "${WASI_SDK:?set WASI_SDK to the folder of an unpacked WASI SDK 24}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/site/wasm"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }   # macOS has shasum, some Linux systems only sha256sum
sysroot="$WASI_SDK/share/wasi-sysroot"
want_clang="clang version 18.1.2-wasi-sdk (https://github.com/llvm/llvm-project 26a1d6601d727a96f4301d0d8647b5a42760ae0c)"
want_libc=566b9d6322cb3f339963cb1e6719b0bb0c932724fafa3418cf6aebe763dc2036
have_clang="$("$WASI_SDK/bin/clang" --version 2>/dev/null | head -1)" || true
have_libc="$(sha256 "$sysroot/lib/wasm32-wasi/libc.a" 2>/dev/null | cut -d' ' -f1)" || true
if [ "$have_clang" != "$want_clang" ] || [ "$have_libc" != "$want_libc" ]; then
  echo "site/wasm/build.sh needs WASI SDK 24 (the committed wasm files are built with it, and another version gives other bytes)" >&2
  echo "  $WASI_SDK/bin/clang: ${have_clang:-missing}  (want: $want_clang)" >&2
  echo "  $sysroot/lib/wasm32-wasi/libc.a sha256: ${have_libc:-missing}  (want: $want_libc)" >&2
  echo "  get it from https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-24" >&2
  exit 1
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cc="$WASI_SDK/bin/clang --target=wasm32-wasi --sysroot=$sysroot"
rt="$root/runtime/tomato_rt.c"
# the WASI C library starts programs at __main_argc_argv, so the compiler's own main is renamed for this build only
sed 's/^define i32 @main(i32/define i32 @__main_argc_argv(i32/' "$root/compiler/bootstrap/tomatoc.ll" > "$tmp/tomatoc.ll"
$cc -O1 -Wno-override-module -x ir "$tmp/tomatoc.ll" -x c "$rt" -lm -Wl,--strip-debug \
  -Wl,--stack-first -Wl,-z,stack-size=8388608 -Wl,--initial-memory=67108864 -Wl,--max-memory=1073741824 -o "$tmp/tomatoc.wasm"
$cc -O1 -DTOMATO_WASM -mexec-model=reactor "$rt" -lm -Wl,--strip-debug \
  -Wl,--export-all -Wl,--no-entry -Wl,--initial-memory=33554432 -Wl,--max-memory=1073741824 -o "$tmp/runtime.wasm"
for f in tomatoc runtime; do
  # host-dependent compiler-rt functions (by name, from the name section) and any build folder of the SDK's own sources
  bad="$(LC_ALL=C grep -a -o -E '__(abs|add|sub|mul|neg)v[sdt]i[23]|__clear_cache|__multc3|llvm-project/[[:alnum:]_./-]*' "$tmp/$f.wasm" | sort -u | tr '\n' ' ')" || true
  if [ -n "$bad" ]; then
    echo "site/wasm/build.sh: $f.wasm links code whose bytes differ between the macOS and Linux WASI SDKs: $bad" >&2
    echo "  so the build would not be the same on every host; avoid what pulls it in (see the comment at the top of this script)" >&2
    exit 1
  fi
  mv "$tmp/$f.wasm" "$out/$f.wasm"
done
mkdir -p "$out/std"; cp "$root/std/"*.tom "$root/std/errors.txt" "$out/std/"
{ cat "$root/compiler/bootstrap/tomatoc.ll" "$rt" | sha256 | cut -d" " -f1
  sha256 "$out/tomatoc.wasm" "$out/runtime.wasm" | cut -d" " -f1; } > "$out/SOURCE.sha256"   # source hash, then the two wasm files   # tests/run.sh checks the wasm files are not stale
echo "built $out/tomatoc.wasm and $out/runtime.wasm"
