#!/bin/sh
# Deterministic instruction counts for the benchmarks: Tomato, Go, Rust and Python, each run under Valgrind (callgrind) inside a
# Linux arm64 virtual machine (Lima, Apple Virtualization framework), because the Mac itself cannot count instructions without
# root and Instruments, and wall-clock time here swings by 100-300% with machine load.
#   benchmarks/count.sh --setup              once: install Lima (needs Homebrew), create the VM "tomato-count" and install the toolchains
#   benchmarks/count.sh [--runs N] [--only a,b] [--smoke] [--vm NAME] [--out FILE]
#     --runs N     measure every program N times (default 2) and report how far the runs disagree
#     --only LIST  comma-separated benchmark names (default all)
#     --smoke      the tiny inputs (column 2 of sizes.txt) instead of the counting inputs (column 4)
#     --out FILE   where the Markdown report goes (default benchmarks/results/instructions.md); it is also printed
# What is counted is INSTRUCTIONS EXECUTED (callgrind's "Ir"), not cycles: Valgrind simulates no pipeline, so nothing here says
# how many M1 cycles a program takes. The count is exact for a given binary and input, and the same on every run up to a tiny
# amount (Go's runtime threads, hash seeds). The whole process is counted, including startup (Go about 0.7 million, Python tens of millions).
# Tomato is built inside the VM from this checkout with its own `tomato build` (it needs only clang), so no cross-compiling happens.
# Go is linked externally (needs gcc) because a plain static Go binary crashes under Valgrind. Python needs only the VM's python3.
here="$(cd "$(dirname "$0")" && pwd)"; root="$(dirname "$here")"
argc=$#; vm=tomato-count; runs=2; only=""; smoke=0; out="$here/results/instructions.md"; guest=0; setup=0
while [ $# -gt 0 ]; do
  case "$1" in
    --setup) setup=1; shift ;;
    --guest) guest=1; shift ;;
    --vm) vm="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    --smoke) smoke=1; shift ;;
    --out) out="$2"; shift 2 ;;
    *) echo "usage: count.sh [--setup] [--runs N] [--only a,b] [--smoke] [--vm NAME] [--out FILE]" >&2; exit 2 ;;
  esac
done

if [ $guest = 0 ]; then
  # ---- on the Mac: set up the VM if asked, copy this checkout into it, run the guest half, keep the report
  if [ $setup = 1 ]; then
    command -v limactl >/dev/null 2>&1 || brew install lima || exit 1
    limactl list -q 2>/dev/null | grep -qx "$vm" || limactl start --name="$vm" --vm-type=vz --cpus=4 --memory=6 --disk=30 --mount-none --tty=false template:ubuntu-24.04 || exit 1
    limactl start "$vm" >/dev/null 2>&1
    # Go 1.27.4 and the newest stable Rust (the versions the Mac has, so the comparison is like for like); Ubuntu's own are too old
    limactl shell "$vm" -- sh -c '
      set -e
      sudo apt-get update -qq
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq valgrind clang gcc python3 curl
      [ -x "$HOME/.cargo/bin/rustc" ] || curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
      /usr/local/go/bin/go version 2>/dev/null | grep -q go1.27.4 || {
        curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.27.4.linux-arm64.tar.gz
        sudo rm -rf /usr/local/go; sudo tar -C /usr/local -xzf /tmp/go.tgz; }' || exit 1
    echo "VM $vm is ready"; [ "$argc" -eq 1 ] && exit 0   # --setup alone just sets up
  fi
  command -v limactl >/dev/null 2>&1 || { echo "limactl not found: run benchmarks/count.sh --setup (see docs/performance.md)" >&2; exit 1; }
  limactl list -q 2>/dev/null | grep -qx "$vm" || { echo "no VM named $vm: run benchmarks/count.sh --setup" >&2; exit 1; }
  limactl start "$vm" >/dev/null 2>&1
  mkdir -p "$(dirname "$out")"
  (cd "$root" && COPYFILE_DISABLE=1 tar -cf - benchmarks compiler/bootstrap runtime std native VERSION) |
    limactl shell "$vm" -- sh -c 'rm -rf "$HOME/tomato-count" && mkdir "$HOME/tomato-count" && tar --warning=no-unknown-keyword -xf - -C "$HOME/tomato-count"' || exit 1
  set -- --guest --runs "$runs"; [ -n "$only" ] && set -- "$@" --only "$only"; [ $smoke = 1 ] && set -- "$@" --smoke
  limactl shell "$vm" -- sh "tomato-count/benchmarks/count.sh" "$@" > "$out.tmp" || { rm -f "$out.tmp"; exit 1; }
  mv "$out.tmp" "$out"; cat "$out"; echo; echo "wrote $out"
  exit 0
fi

# ---- inside the VM
export PATH="/usr/local/go/bin:$HOME/.cargo/bin:$PATH"
here="$(cd "$(dirname "$0")" && pwd)"; root="$(dirname "$here")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
say() { echo "$*" >&2; }
export GOMAXPROCS=1 PYTHONHASHSEED=0 CGO_ENABLED=1
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] && export GODEBUG=asyncpreemptoff=1   # x86-64 Linux only: callgrind crashes on the Go wordcount binary with async preemption signals; the arm64 VM counts stay as they were
home="$work/tomato"; mkdir -p "$home/bin"
clang -O1 -w -o "$home/bin/tomatoc" "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" -lm || exit 1
cp "$root/native/tomato" "$root/native/rtcache.sh" "$home/bin/"; cp -R "$root/runtime" "$root/std" "$root/VERSION" "$home/"
release_mode=release
langs="tomato go rust python"
ext() { case "$1" in tomato) echo tom ;; go) echo go ;; rust) echo rs ;; python) echo py ;; esac; }
benchmarks="$(grep -v '^#' "$here/sizes.txt" | awk 'NF { print $1 }')"
[ -n "$only" ] && benchmarks="$(echo "$only" | tr ',' ' ')"
input_for() { if [ $smoke = 1 ]; then awk -v n="$1" '$1 == n { print $2 }' "$here/sizes.txt"; else awk -v n="$1" '$1 == n { print $4 }' "$here/sizes.txt"; fi; }
: > "$work/counts"; : > "$work/bad"
for b in $benchmarks; do
  input="$(input_for "$b")"; [ -n "$input" ] || { say "no input for $b in sizes.txt"; exit 1; }
  for l in $langs; do
    src="$here/$b/$b.$(ext "$l")"; bin="$work/$b.$l"
    case "$l" in
      tomato) "$home/bin/tomato" build "$src" -o "$bin" --mode "$release_mode" >&2 ;;
      go) go build -ldflags=-linkmode=external -o "$bin" "$src" ;;
      rust) if [ -f "$here/$b/Cargo.toml" ]; then
          cargo build --release --locked --quiet --manifest-path "$here/$b/Cargo.toml" --target-dir "$work/cargo" && cp "$work/cargo/release/$b" "$bin"
        else rustc -O -o "$bin" "$src"; fi ;;
      python) bin="" ;;
    esac || { say "build failed: $b $l"; exit 1; }
    i=1
    while [ $i -le "$runs" ]; do
      if [ "$l" = python ]; then set -- python3 "$src" "$input"; else set -- "$bin" "$input"; fi
      valgrind --tool=callgrind --callgrind-out-file=/dev/null "$@" > "$work/$b.$l.out" 2> "$work/vg" < /dev/null
      n="$(sed -n 's/^==[0-9]*== Collected : //p' "$work/vg")"
      [ -n "$n" ] || { say "no count for $b $l:"; cat "$work/vg" >&2; exit 1; }
      echo "$b $l $i $n" >> "$work/counts"; i=$((i + 1))
    done
    say "$b $l $n"
  done
  for l in go rust python; do cmp -s "$work/$b.tomato.out" "$work/$b.$l.out" || echo "$b $l" >> "$work/bad"; done
done

# ---- the report
count_of() { awk -v b="$1" -v l="$2" '$1 == b && $2 == l && $3 == 1 { print $4 }' "$work/counts"; }
spread_of() { awk -v b="$1" -v l="$2" '$1 == b && $2 == l { if (!n++ || $4 < lo) lo = $4; if ($4 > hi) hi = $4 } END { printf "%.4f", (hi - lo) / lo * 100 }' "$work/counts"; }
ver() { "$@" 2>&1 | head -1; }
echo "# Instructions executed (deterministic, under Valgrind in a Linux arm64 VM)"
echo
echo "Tomato v$(cat "$root/VERSION") (release mode). $(ver valgrind --version) callgrind, $(uname -srm), $(nproc) cores. $(ver clang --version | sed 's/ (.*//'), $(ver go version | cut -d' ' -f3), $(ver rustc --version | cut -d' ' -f1,2), $(ver python3 --version). Every program ran $runs times; inputs are $([ $smoke = 1 ] && echo "the smoke inputs" || echo "the counting inputs") from sizes.txt."
echo
echo "These are INSTRUCTIONS EXECUTED by the whole process (startup included), not cycles. Valgrind has no pipeline model, so this says nothing about M1 cycles; it is the same on a busy machine and on an idle one."
echo
echo "| benchmark | input | tomato | go | rust | python |"
echo "| --- | --- | ---: | ---: | ---: | ---: |"
for b in $benchmarks; do
  printf '| %s | %s |' "$b" "$(input_for "$b")"
  for l in $langs; do printf ' %s |' "$(count_of "$b" "$l" | awk '{ printf "%.2f M", $1 / 1e6 }')"; done
  echo
done
echo
echo "Tomato's instructions divided by each other language's (below 1.0 Tomato executes fewer instructions, above 1.0 more):"
echo
echo "| benchmark | tomato ÷ go | tomato ÷ rust | tomato ÷ python |"
echo "| --- | ---: | ---: | ---: |"
for b in $benchmarks; do
  t="$(count_of "$b" tomato)"; printf '| %s |' "$b"
  for l in go rust python; do printf ' %s |' "$(count_of "$b" "$l" | awk -v t="$t" '{ printf "%.2f", t / $1 }')"; done
  echo
done
echo
echo "Run-to-run difference, (largest - smallest) / smallest over $runs runs, in percent:"
echo
echo "| benchmark | tomato | go | rust | python |"
echo "| --- | ---: | ---: | ---: | ---: |"
for b in $benchmarks; do
  printf '| %s |' "$b"
  for l in $langs; do printf ' %s |' "$(spread_of "$b" "$l")"; done
  echo
done
if [ -s "$work/bad" ]; then echo; echo "WARNING: output differs from Tomato's for: $(tr '\n' ',' < "$work/bad")"; fi
