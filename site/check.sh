#!/bin/sh
# Quick checks that the website is consistent and publishable; needs no compiler. The Pages deploy depends on this
# (not on the full tests/run.sh, which runs separately). Usage: sh site/check.sh
cd "$(dirname "$0")/.." || exit 1
fails=0
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
ok() { echo "ok   $1"; }
v="$(cat VERSION)"
mv_() { sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' "$1"; }
urls() { # FILE VERSION: the three download URLs name that version's release
  for k in url pkg_url dmg_url; do
    grep -q "\"$k\": *\"https://github.com/sirbuffalo/tomato/releases/download/v$2/tomato-$2\.[a-z.]*\"" "$1" && ok "$1 $k names v$2" || bad "$1 $k does not name v$2"
  done
}
# site/latest.json and site/config.js name the latest stable release; a pre-release (VERSION like 1.1.0-rc.1) is in
# site/latest-pre.json instead (docs/releasing.md, Version numbers)
stable="$(mv_ site/latest.json)"
case "$stable" in ""|*-*) bad "site/latest.json must name a stable release, not '$stable'" ;; esac
case "$v" in
  *-*) [ -f site/latest-pre.json ] && [ "$(mv_ site/latest-pre.json)" = "$v" ] && ok "site/latest-pre.json is v$v" || bad "site/latest-pre.json must name the pre-release v$v"
       urls site/latest-pre.json "$v" ;;
  *) [ "$stable" = "$v" ] && ok "site/latest.json is v$v" || bad "site/latest.json version differs from VERSION"
     if [ -f site/latest-pre.json ]; then case "$(mv_ site/latest-pre.json)" in *-*) ok "site/latest-pre.json names a pre-release" ;; *) bad "site/latest-pre.json does not name a pre-release" ;; esac; fi ;;
esac
[ "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)" = "$stable" ] && ok "site/config.js is v$stable" || bad "site/config.js version differs from site/latest.json"
urls site/latest.json "$stable"
for f in index download guide play docs benchmarks; do [ -s "site/$f.html" ] && ok "site/$f.html exists" || bad "site/$f.html missing"; done
for f in tomatoc.wasm runtime.wasm; do [ -s "site/wasm/$f" ] && ok "site/wasm/$f exists" || bad "site/wasm/$f missing"; done
[ "$fails" = 0 ] || { echo "$fails site check(s) failed"; exit 1; }
echo "site checks passed"
