#!/bin/sh
# Check the actual linker, not just whether clang accepts -flto. LTO removes value across translation units. (release/linux-setup.sh has
# the same probe inline, because it is piped over ssh and cannot read this file: change both together.)
set -eu
command -v nm >/dev/null || { echo 'error: nm is required to verify LTO' >&2; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf 'int value(void) { return 42; }\n' > "$work/a.c"
printf 'int value(void); int main(void) { return value() != 42; }\n' > "$work/b.c"
clang -O2 -flto "$work/a.c" "$work/b.c" -o "$work/test"
"$work/test"
nm "$work/test" | grep -q ' main$' || { echo 'error: nm does not list main in a linked program, so the LTO check cannot tell' >&2; exit 1; }
if nm "$work/test" | grep -q ' value$'; then
  echo 'error: cross-module LTO did not eliminate value' >&2
  exit 1
fi
echo 'LTO cross-module optimization verified'
