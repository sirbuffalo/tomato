#!/bin/sh
# Builds the WebAssembly files the website runs in the browser (committed, so Pages needs no toolchain):
#   tomatoc.wasm  the compiler written in Tomato (compiler/bootstrap/tomatoc.ll) plus the C runtime
#   runtime.wasm  the C runtime alone, exporting the tomato_* functions the IR interpreter (llvm.js) calls
# Needs the WASI SDK (https://github.com/WebAssembly/wasi-sdk/releases): WASI_SDK=/path/to/wasi-sdk-24.0-arm64-macos
set -e
: "${WASI_SDK:?set WASI_SDK to the folder of an unpacked WASI SDK}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/site/wasm"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cc="$WASI_SDK/bin/clang --target=wasm32-wasi --sysroot=$WASI_SDK/share/wasi-sysroot"
rt="$root/runtime/tomato_rt.c"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }   # macOS has shasum, some Linux systems only sha256sum
# the WASI C library starts programs at __main_argc_argv, so the compiler's own main is renamed for this build only
sed 's/^define i32 @main(i32/define i32 @__main_argc_argv(i32/' "$root/compiler/bootstrap/tomatoc.ll" > "$tmp/tomatoc.ll"
$cc -O1 -Wno-override-module -x ir "$tmp/tomatoc.ll" -x c "$rt" -lm \
  -Wl,--stack-first -Wl,-z,stack-size=8388608 -Wl,--initial-memory=67108864 -Wl,--max-memory=1073741824 -o "$out/tomatoc.wasm"
$cc -O1 -DTOMATO_WASM -mexec-model=reactor "$rt" -lm \
  -Wl,--export-all -Wl,--no-entry -Wl,--initial-memory=33554432 -Wl,--max-memory=1073741824 -o "$out/runtime.wasm"
mkdir -p "$out/std"; cp "$root/std/"*.tom "$root/std/errors.txt" "$out/std/"
{ cat "$root/compiler/bootstrap/tomatoc.ll" "$rt" | sha256 | cut -d" " -f1
  sha256 "$out/tomatoc.wasm" "$out/runtime.wasm" | cut -d" " -f1; } > "$out/SOURCE.sha256"   # source hash, then the two wasm files   # tests/run.sh checks the wasm files are not stale
echo "built $out/tomatoc.wasm and $out/runtime.wasm"
