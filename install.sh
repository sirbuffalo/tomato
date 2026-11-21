#!/bin/sh
# Installs the `tomato` command for the current user.
#   ./install.sh             copy Tomato to ~/.tomato, link ~/.local/bin/tomato, and install llvmlite for `!x` calls
#   ./install.sh --no-llvm   skip llvmlite (no network needed; `!x` calls will not run)
# Override the locations with TOMATO_HOME and TOMATO_BIN. Remove it with: rm -rf ~/.tomato ~/.local/bin/tomato
set -e
home="${TOMATO_HOME:-$HOME/.tomato}"
bindir="${TOMATO_BIN:-$HOME/.local/bin}"
root="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
mkdir -p "$home" "$bindir"
rm -rf "$home/tomato" "$home/bin" "$home/examples"
cp -R "$root/tomato" "$root/bin" "$root/examples" "$home/"
find "$home" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
if [ "$1" != "--no-llvm" ]; then
  [ -x "$home/.venv/bin/python" ] || python3 -m venv "$home/.venv"
  "$home/.venv/bin/pip" install --quiet llvmlite || echo "llvmlite did not install: programs that call !x will not run" >&2
fi
ln -sf "$home/bin/tomato" "$bindir/tomato-py"
echo "installed Tomato to $home"
echo "linked $bindir/tomato-py (the Python version; ./install-native.sh installs the native tomato command)"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "add $bindir to your PATH to run 'tomato'" ;; esac
echo "try: tomato-py run $home/examples/primes.tom"
