#!/bin/sh
# Quick checks that the website is consistent and publishable; needs no compiler. The Pages deploy depends on this
# (not on the full tests/run.sh, which runs separately). Usage: sh site/check.sh
cd "$(dirname "$0")/.." || exit 1
fails=0
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
ok() { echo "ok   $1"; }
v="$(cat VERSION)"
[ "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)" = "$v" ] && ok "site/latest.json is v$v" || bad "site/latest.json version differs from VERSION"
[ "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)" = "$v" ] && ok "site/config.js is v$v" || bad "site/config.js version differs from VERSION"
for k in url pkg_url dmg_url; do
  grep -q "\"$k\": *\"https://github.com/sirbuffalo/tomato/releases/download/v$v/tomato-$v\.[a-z.]*\"" site/latest.json && ok "latest.json $k names v$v" || bad "latest.json $k does not name v$v"
done
for f in index download guide play docs benchmarks; do [ -s "site/$f.html" ] && ok "site/$f.html exists" || bad "site/$f.html missing"; done
for f in tomatoc.wasm runtime.wasm; do [ -s "site/wasm/$f" ] && ok "site/wasm/$f exists" || bad "site/wasm/$f missing"; done
[ "$fails" = 0 ] || { echo "$fails site check(s) failed"; exit 1; }
echo "site checks passed"
