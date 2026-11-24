# The cache of the compiled C runtime, sourced (with `.`) by `tomato` and by tests/run.sh. Not run on its own.
#
# Compiling runtime/tomato_rt.c (5,000 lines of C) is most of what `tomato run` costs (1.5 s of 1.6 s with link-time optimisation),
# and the result only depends on the runtime source, the flags and the clang that compiles it. So it is compiled once and kept
# in the user's cache folder: the next run links the stored object (LLVM bitcode when the flags have -flto) and is not slower
# than the link of the program itself.
#
#   rtcache_get FALLBACK_DIR EXT SOURCE FLAGS...    prints the path of the compiled object, or fails (the caller then links SOURCE)
#
# The file is named for a hash of the flags, the output of `clang --version` (which names the clang binary's folder and target
# too) and the source text, so a change to any of them is a different file (a miss); nothing is ever updated in place. It is
# written under a temporary name in the same folder and renamed, which is atomic: concurrent runs may both compile, but each
# only ever sees a whole file. Files not used for 30 days are removed when a new one is stored. The folder is
# $TOMATO_CACHE_DIR, else ~/Library/Caches/tomato (macOS) or ${XDG_CACHE_HOME:-~/.cache}/tomato; TOMATO_CACHE=off turns the
# cache off. When the folder cannot be used (off, read-only, full) the object is built in FALLBACK_DIR instead, as before.
rtcache_dir() {
  if [ -n "${TOMATO_CACHE_DIR:-}" ]; then printf '%s\n' "$TOMATO_CACHE_DIR"
  elif [ "$(uname)" = Darwin ]; then printf '%s\n' "${HOME:-/nonexistent}/Library/Caches/tomato"
  else printf '%s\n' "${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/tomato"; fi
}
rtcache_hash() { # standard input -> a hex digest
  if command -v shasum >/dev/null 2>&1; then shasum -a 256; elif command -v sha256sum >/dev/null 2>&1; then sha256sum; else cksum; fi | awk '{ printf "%s", $1; if ($2 != "") printf "%s", $2; exit }'
}
rtcache_get() {
  rtc_fallback="$1"; rtc_ext="$2"; rtc_src="$3"; shift 3
  rtc_key="$({ printf 'tomato runtime cache 1\n%s\n' "$*"; clang --version 2>&1; cat "$rtc_src"; } | rtcache_hash)"
  [ -n "$rtc_key" ] || return 1
  rtc_name="rt-$(printf '%s' "$rtc_key" | cut -c1-32).$rtc_ext"
  rtc_dir="$(rtcache_dir)"
  if [ "${TOMATO_CACHE:-}" != off ] && mkdir -p "$rtc_dir" 2>/dev/null; then
    if [ -s "$rtc_dir/$rtc_name" ]; then touch "$rtc_dir/$rtc_name" 2>/dev/null; printf '%s\n' "$rtc_dir/$rtc_name"; return 0; fi
    if rtc_tmp="$(mktemp "$rtc_dir/.tmp.XXXXXX" 2>/dev/null)"; then
      if clang "$@" -c -o "$rtc_tmp" "$rtc_src" 2>/dev/null && [ -s "$rtc_tmp" ] && chmod 644 "$rtc_tmp" && mv -f "$rtc_tmp" "$rtc_dir/$rtc_name" 2>/dev/null; then
        find "$rtc_dir" -name 'rt-*' -mtime +30 -exec rm -f {} + 2>/dev/null
        find "$rtc_dir" -name '.tmp.*' -mtime +1 -exec rm -f {} + 2>/dev/null
        printf '%s\n' "$rtc_dir/$rtc_name"; return 0
      fi
      rm -f "$rtc_tmp"
    fi
  fi
  [ -n "$rtc_fallback" ] && [ -d "$rtc_fallback" ] || return 1
  clang "$@" -c -o "$rtc_fallback/$rtc_name" "$rtc_src" 2>/dev/null && [ -s "$rtc_fallback/$rtc_name" ] || return 1
  printf '%s\n' "$rtc_fallback/$rtc_name"
}
