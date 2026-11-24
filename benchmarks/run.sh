#!/bin/sh
# The benchmark runner: builds every benchmark in Tomato, Go, Rust and Python, runs each several times, and writes the
# median and fastest time, peak memory, build time and binary size as JSON and a Markdown table.
#   benchmarks/run.sh [--runs N] [--python-runs N] [--seed N] [--smoke] [--only a,b,c] [--out DIR] [--site]
#     --runs N     runs per program (default 10; the median is reported); Python runs --python-runs times (default 10)
#     --seed N     the seed for the random order of the runs (default 1): every (benchmark, language, run) job is shuffled
#                  and run in that order, so throttling and background load fall evenly on every row; the seed is recorded
#     --smoke      use the tiny inputs from sizes.txt and only check that the four versions print the same thing
#     --only LIST  comma-separated benchmark names (default all)
#     --out DIR    where results.json and results.md go (default benchmarks/results)
#     --site       also copy results.json to site/benchmarks.json for the website's Benchmarks page
# Tomato is built from this checkout (compiler/bootstrap/tomatoc.ll), so the numbers always describe the source tree.
# Tomato is built twice: "tomato" in release mode (what Davis calls the real thing: no leak checks, short error codes) and
# "tomato-debug" in debug mode (leak checks and full error text).
# Needs: clang (for Tomato and the timing helper), go, rustc with cargo (bigint uses the num-bigint crate, fetched once) and python3. A missing toolchain is skipped and noted.
# The Python programs exist only to be compared with; the repository's own tooling does not use Python.
here="$(cd "$(dirname "$0")" && pwd)"; root="$(dirname "$here")"
runs=10; python_runs=10; seed=1; smoke=0; only=""; out="$here/results"; site=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) runs="$2"; shift 2 ;;
    --python-runs) python_runs="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    --smoke) smoke=1; shift ;;
    --only) only="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --site) site=1; shift ;;
    *) echo "usage: run.sh [--runs N] [--python-runs N] [--seed N] [--smoke] [--only a,b] [--out DIR] [--site]" >&2; exit 2 ;;
  esac
done
release_mode=release
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
say() { echo "$*" >&2; }

# --- the Tomato compiler from this checkout, and the timing helper
home="$work/tomato"; mkdir -p "$home/bin"
clang -O1 -w -o "$home/bin/tomatoc" "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" -lm || exit 1
cp "$root/native/tomato" "$home/bin/tomato"; cp -R "$root/runtime" "$root/std" "$root/VERSION" "$home/"
clang -O2 -o "$work/measure" "$here/measure.c" || exit 1
# a clang wrapper that records which optimization level each Tomato build really used
mkdir -p "$work/shim"; : > "$work/clang.log"
printf '#!/bin/sh\necho "$*" >> "%s/clang.log"\nexec "%s" "$@"\n' "$work" "$(command -v clang)" > "$work/shim/clang"; chmod +x "$work/shim/clang"

langs="tomato tomato-debug"
have() { command -v "$1" >/dev/null 2>&1; }
for t in go:go rust:rustc python:python3; do
  need="${t#*:}"; [ "${t%:*}" = rust ] && ! have cargo && need=cargo   # the bigint benchmark is a cargo project, so Rust needs both
  if have "$need" && have "${t#*:}"; then langs="$langs ${t%:*}"; else say "skipping ${t%:*}: $need is not installed"; fi
done
ext() { case "$1" in tomato|tomato-debug) echo tom ;; go) echo go ;; rust) echo rs ;; python) echo py ;; esac; }

benchmarks="$(grep -v '^#' "$here/sizes.txt" | awk 'NF { print $1 }')"
if [ -n "$only" ]; then benchmarks="$(echo "$only" | tr ',' ' ')"; fi
input_for() { # name -> the input (smoke or full)
  if [ $smoke = 1 ]; then awk -v n="$1" '$1 == n { print $2 }' "$here/sizes.txt"; else awk -v n="$1" '$1 == n { print $3 }' "$here/sizes.txt"; fi
}

: > "$work/extras"
load_before="$(uptime | sed 's/.*load averages*: //')"
: > "$work/raw.tsv"; : > "$work/build.tsv"; : > "$work/agree.tsv"
for b in $benchmarks; do
  input="$(input_for "$b")"; [ -n "$input" ] || { say "no input for $b in sizes.txt"; exit 1; }
  for l in $langs; do
    src="$here/$b/$b.$(ext "$l")"; bin="$work/$b.$l"
    case "$l" in
      tomato) set -- "$home/bin/tomato" build "$src" -o "$bin" --mode "$release_mode" ;;
      tomato-debug) set -- "$home/bin/tomato" build "$src" -o "$bin" --mode debug ;;
      go) set -- "$(command -v go)" build -o "$bin" "$src" ;;
      rust) if [ -f "$here/$b/Cargo.toml" ]; then   # a benchmark that needs a crate (bigint: num-bigint) is a small Cargo project
          set -- /bin/sh -c 'cargo build --release --locked --quiet --manifest-path "$1/Cargo.toml" --target-dir "$2" && cp "$2/release/$3" "$4"' sh "$here/$b" "$work/cargo" "$b" "$bin"
        else set -- "$(command -v rustc)" -O -o "$bin" "$src"; fi ;;
      python) set -- ;;
    esac
    if [ $# -gt 0 ]; then
      echo "BUILD $b $l" >> "$work/clang.log"
      PATH="$work/shim:$PATH" "$work/measure" "$work/build.log" "$@" 2> "$work/m" < /dev/null
      read -r wall user sys rss code < "$work/m"
      [ "$code" = 0 ] || { say "build failed: $b $l"; cat "$work/build.log" >&2; exit 1; }
      printf '%s %s %s %s\n' "$b" "$l" "$wall" "$(wc -c < "$bin" | tr -d ' ')" >> "$work/build.tsv"
    fi
    i=1; limit=$runs; [ "$l" = python ] && limit=$python_runs; [ $smoke = 1 ] && limit=1
    while [ $i -le $limit ]; do echo "$b $l $i" >> "$work/jobs"; i=$((i + 1)); done
    say "$b $l built"
  done
  if have rustc && [ -f "$here/$b/${b}_radix.rs" ]; then   # an extra Rust version with another algorithm, reported beside the table
    echo "$b rust-radix" >> "$work/extras"
    "$work/measure" "$work/build.log" "$(command -v rustc)" -O -o "$work/$b.rust-radix" "$here/$b/${b}_radix.rs" 2> "$work/m" < /dev/null
    read -r wall user sys rss code < "$work/m"
    [ "$code" = 0 ] || { say "build failed: $b rust-radix"; cat "$work/build.log" >&2; exit 1; }
    printf '%s %s %s %s\n' "$b" rust-radix "$wall" "$(wc -c < "$work/$b.rust-radix" | tr -d ' ')" >> "$work/build.tsv"
    i=1; limit=$runs; [ $smoke = 1 ] && limit=1
    while [ $i -le $limit ]; do echo "$b rust-radix $i" >> "$work/jobs"; i=$((i + 1)); done
  fi
done
# every (benchmark, language, run) job, shuffled with a fixed seed, instead of all runs of one program back to back
awk -v seed="$seed" 'BEGIN { srand(seed) } { printf "%.12f\t%s\n", rand(), $0 }' "$work/jobs" | sort -n | cut -f2- > "$work/order"
total="$(wc -l < "$work/order" | tr -d ' ')"; done_n=0
while read -r b l i; do
  input="$(input_for "$b")"; src="$here/$b/$b.$(ext "$l")"
  case "$l" in python) set -- "$(command -v python3)" "$src" "$input" ;; *) set -- "$work/$b.$l" "$input" ;; esac
  "$work/measure" "$work/$b.$l.out" "$@" 2> "$work/m" < /dev/null
  read -r wall user sys rss code < "$work/m"
  printf '%s %s %s %s %s %s %s\n' "$b" "$l" "$wall" "$user" "$sys" "$rss" "$code" >> "$work/raw.tsv"
  done_n=$((done_n + 1)); [ $((done_n % 50)) = 0 ] && say "$done_n of $total runs"
done < "$work/order"
for b in $benchmarks; do
  # every language must print what Tomato prints
  for l in $langs $(awk -v b="$b" '$1 == b { print $2 }' "$work/extras"); do
    if cmp -s "$work/$b.tomato.out" "$work/$b.$l.out"; then echo "$b $l 1" >> "$work/agree.tsv"; else echo "$b $l 0" >> "$work/agree.tsv"; fi
  done
done
load_after="$(uptime | sed 's/.*load averages*: //')"

if [ $smoke = 1 ]; then
  bad="$(awk '$3 == 0 { print $1 " " $2 }' "$work/agree.tsv")"
  if [ -n "$bad" ]; then echo "outputs differ from Tomato's for:"; echo "$bad"; exit 1; fi
  echo "ok: every benchmark prints the same in $(echo $langs | tr ' ' ',')"
  exit 0
fi

# --- summary: median, fastest and slowest wall time and the median peak memory per program
stat_of() { # name lang column -> sorted values on stdout
  awk -v b="$1" -v l="$2" -v c="$3" '$1 == b && $2 == l { print $c }' "$work/raw.tsv" | sort -n
}
median() { awk '{ v[NR] = $1 } END { if (NR % 2) printf "%s", v[(NR + 1) / 2]; else printf "%.6f", (v[NR / 2] + v[NR / 2 + 1]) / 2 }'; }
machine="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //')"
cores="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
memory="$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%d GB", $1 / 1073741824 }')"
osname="$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null) ($(uname -sr))"
ver() { "$@" 2>&1 | head -1 | sed 's/"/\\"/g'; }
{
  printf '{\n  "date": "%s",\n  "machine": {"cpu": "%s", "cores": %s, "memory": "%s", "os": "%s"},\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$machine" "$cores" "$memory" "$osname"
  printf '  "versions": {"tomato": "%s", "clang": "%s", "go": "%s", "rust": "%s", "python": "%s"},\n' \
    "$(cat "$root/VERSION")" "$(ver clang --version)" "$(have go && ver go version)" "$(have rustc && ver rustc --version)" "$(have python3 && ver python3 --version)"
  printf '  "runs": %s,\n  "python_runs": %s,\n  "order": "shuffled",\n  "seed": %s,\n  "load_before": "%s",\n  "load_after": "%s",\n' "$runs" "$python_runs" "$seed" "$load_before" "$load_after"
  # the -O level (and -flto, when used) clang really got for the Tomato builds, read from the wrapper's log
  olevel() { awk -v l="$1" '$1 == "BUILD" { m = ($3 == l); next } m { s = ""; for (i = 1; i <= NF; i++) if ($i ~ /^-O[0-9sz]$/ || $i == "-flto") s = s (s == "" ? "" : " ") $i; if (s != "") { print s; exit } }' "$work/clang.log"; }
  printf '  "commands": {"tomato": "tomato build --mode %s (clang %s on the LLVM IR)", "tomato-debug": "tomato build --mode debug (clang %s on the LLVM IR)", "go": "go build", "rust": "rustc -O (bigint: cargo build --release with the num-bigint crate)", "rust-radix": "rustc -O (sort_radix.rs: a radix sort instead of the standard sort)", "python": "python3 FILE"},\n' \
    "$release_mode" "$(olevel tomato | head -1)" "$(olevel tomato-debug | head -1)"
  one_result() {   # the JSON for program $l of benchmark $b
      med="$(stat_of "$b" "$l" 3 | median)"; min="$(stat_of "$b" "$l" 3 | head -1)"; max="$(stat_of "$b" "$l" 3 | tail -1)"
      rss="$(stat_of "$b" "$l" 6 | median)"
      bt="$(awk -v b="$b" -v l="$l" '$1 == b && $2 == l { print $3 }' "$work/build.tsv")"; bs="$(awk -v b="$b" -v l="$l" '$1 == b && $2 == l { print $4 }' "$work/build.tsv")"
      ok="$(awk -v b="$b" -v l="$l" '$1 == b && $2 == l { print $3 }' "$work/agree.tsv")"
      printf '%s"%s": {"median": %s, "min": %s, "max": %s, "peak_memory_bytes": %s, "build_seconds": %s, "binary_bytes": %s, "agrees": %s}' \
        "$sep" "$l" "$med" "$min" "$max" "$rss" "${bt:-null}" "${bs:-null}" "$([ "$ok" = 1 ] && echo true || echo false)"
  }
  printf '  "benchmarks": [\n'
  first=1
  for b in $benchmarks; do
    [ $first = 1 ] || printf ',\n'; first=0
    printf '    {"name": "%s", "input": %s, "results": {' "$b" "$(input_for "$b")"
    sep=""
    for l in $langs; do
      one_result
      sep=", "
    done
    printf '}'
    extra="$(awk -v b="$b" '$1 == b { print $2 }' "$work/extras")"
    if [ -n "$extra" ]; then
      printf ', "extra": {'; sep=""
      for l in $extra; do one_result; sep=", "; done
      printf '}'
    fi
    printf '}'
  done
  printf '\n  ]\n}\n'
} > "$out/results.json"

# --- the Markdown table: median seconds, and the ratio to Rust (or to the fastest program when Rust is missing)
{
  echo "# Benchmark results"
  echo
  echo "Machine: $machine, $cores cores, $memory, $osname. Tomato v$(cat "$root/VERSION"). Median of $runs runs ($python_runs for Python), all runs in one shuffled order (seed $seed); load average before $load_before, after $load_after."
  echo
  printf '| benchmark | input |'; for l in $langs; do printf ' %s (s) |' "$l"; done; echo
  printf '| --- | --- |'; for l in $langs; do printf ' ---: |'; done; echo
  for b in $benchmarks; do
    printf '| %s | %s |' "$b" "$(input_for "$b")"
    for l in $langs; do printf ' %s |' "$(stat_of "$b" "$l" 3 | median | awk '{ printf "%.3f", $1 }')"; done
    echo
  done
  echo
  echo "Fastest run and spread ((slowest - fastest) / median), per program:"
  echo
  printf '| benchmark |'; for l in $langs; do printf ' %s min (s) | spread |' "$l"; done; echo
  printf '| --- |'; for l in $langs; do printf ' ---: | ---: |'; done; echo
  for b in $benchmarks; do
    printf '| %s |' "$b"
    for l in $langs; do
      med="$(stat_of "$b" "$l" 3 | median)"; mn="$(stat_of "$b" "$l" 3 | head -1)"; mx="$(stat_of "$b" "$l" 3 | tail -1)"
      printf ' %s | %s |' "$(awk -v v="$mn" 'BEGIN { printf "%.3f", v }')" "$(awk -v a="$mn" -v z="$mx" -v m="$med" 'BEGIN { printf "%.0f%%", (z - a) / m * 100 }')"
    done
    echo
  done
  echo
  while read -r b l; do
    echo "$b, $l: median $(stat_of "$b" "$l" 3 | median | awk '{ printf "%.3f", $1 }') s, fastest $(stat_of "$b" "$l" 3 | head -1 | awk '{ printf "%.3f", $1 }') s, tomato ÷ $l $(stat_of "$b" "$l" 3 | median | awk -v t="$(stat_of "$b" tomato 3 | median)" '{ printf "%.2f", t / $1 }') (benchmarks/$b/${b}_radix.rs; not in the tables above)."
    echo
  done < "$work/extras"
  echo "Tomato's time divided by each other language's time (below 1.0 Tomato is faster, above 1.0 it is slower):"
  echo
  cmp_langs=""; for l in $langs; do case "$l" in tomato|tomato-debug) ;; *) cmp_langs="$cmp_langs $l" ;; esac; done
  printf '| benchmark |'; for t in tomato tomato-debug; do for l in $cmp_langs; do printf ' %s ÷ %s |' "$t" "$l"; done; done; echo
  printf '| --- |'; for t in tomato tomato-debug; do for l in $cmp_langs; do printf ' ---: |'; done; done; echo
  for b in $benchmarks; do
    printf '| %s |' "$b"
    for t in tomato tomato-debug; do
      tm="$(stat_of "$b" "$t" 3 | median)"
      for l in $cmp_langs; do printf ' %s |' "$(stat_of "$b" "$l" 3 | median | awk -v t="$tm" '{ printf "%.2f", t / $1 }')"; done
    done
    echo
  done
} > "$out/results.md"
[ $site = 1 ] && cp "$out/results.json" "$root/site/benchmarks.json"
disagree="$(awk '$3 == 0 { print $1 " " $2 }' "$work/agree.tsv")"
[ -n "$disagree" ] && { echo "WARNING: outputs differ from Tomato's for: $disagree"; }
echo "wrote $out/results.json and $out/results.md"
