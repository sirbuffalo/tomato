#!/bin/sh
# The benchmark runner: builds every benchmark in Tomato and in the other languages whose tools are installed (Go, Rust, C,
# C++, Java, C#, Swift, JavaScript, TypeScript, PHP and Python), runs each several times, and writes the
# median and fastest time, peak memory, build time and binary size as JSON and a Markdown table.
#   benchmarks/run.sh [--runs N] [--python-runs N] [--seed N] [--smoke] [--only a,b,c] [--langs a,b,c] [--out DIR] [--site] [--tomatoc FILE]
#     --runs N     runs per program (default 10; the median is reported); Python and PHP run --python-runs times (default 10)
#     --seed N     the seed for the random order of the runs (default 1): every (benchmark, language, run) job is shuffled
#                  and run in that order, so throttling and background load fall evenly on every row; the seed is recorded
#     --smoke      use the tiny inputs from sizes.txt and only check that all versions print the same thing (C# and Swift, whose
#                  builds are slow, only when --langs names them)
#     --only LIST  comma-separated benchmark names (default all)
#     --langs LIST the other languages to run, of go rust python c cpp java csharp swift javascript typescript php (default
#                  every installed one; Tomato always runs)
#     --out DIR    where results.json and results.md go (default benchmarks/results)
#     --max-minutes N  stop timing after N minutes (default: no limit); SIGINT or SIGTERM stops it too. Either way the runs that finished
#                  are kept: the results are written from them, and results.json says how many runs each program got ("partial": true)
#     --site       also copy results.json to site/benchmarks.json for the website's Benchmarks page
#     --tomatoc F  use this compiler binary (built from compiler/bootstrap/tomatoc.ll) instead of building one: tests/run.sh,
#                  which has just built it, runs one smoke run per benchmark at the same time, and passes it here
# Tomato is built from this checkout (compiler/bootstrap/tomatoc.ll), so the numbers always describe the source tree.
# Tomato is built twice: "tomato" in release mode (what Davis calls the real thing: no leak checks, short error codes) and
# "tomato-debug" in debug mode (leak checks and full error text).
# Needs: clang (for Tomato, the timing helper, C and C++); the rest are skipped, with a note, when missing: go, rustc with cargo
# (bigint uses the num-bigint crate, fetched once), javac and java, dotnet 10 or newer (it builds a single .cs file), swiftc,
# node (22.6 or newer for TypeScript, which it runs by stripping the types), php and python3.
# The other languages' programs exist only to be compared with; the repository's own tooling does not use Python.
here="$(cd "$(dirname "$0")" && pwd)"; root="$(dirname "$here")"
runs=10; python_runs=10; seed=1; smoke=0; only=""; wanted=""; out="$here/results"; site=0; max_minutes=0; tomatoc=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) runs="$2"; shift 2 ;;
    --python-runs) python_runs="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    --smoke) smoke=1; shift ;;
    --only) only="$2"; shift 2 ;;
    --langs) wanted="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --max-minutes) max_minutes="$2"; shift 2 ;;
    --site) site=1; shift ;;
    --tomatoc) tomatoc="$2"; shift 2 ;;
    *) echo "usage: run.sh [--runs N] [--python-runs N] [--seed N] [--smoke] [--only a,b] [--langs a,b] [--out DIR] [--max-minutes N] [--site] [--tomatoc FILE]" >&2; exit 2 ;;
  esac
done
release_mode=release
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
say() { echo "$*" >&2; }

# --- the Tomato compiler from this checkout, and the timing helper
home="$work/tomato"; mkdir -p "$home/bin"
if [ -n "$tomatoc" ]; then cp "$tomatoc" "$home/bin/tomatoc" || exit 1
else clang -O1 -w -o "$home/bin/tomatoc" "$root/compiler/bootstrap/tomatoc.ll" "$root/runtime/tomato_rt.c" -lm || exit 1; fi
cp "$root/native/tomato" "$root/native/rtcache.sh" "$home/bin/"; cp -R "$root/runtime" "$root/std" "$root/VERSION" "$home/"
clang -O2 -o "$work/measure" "$here/measure.c" || exit 1
# a clang wrapper that records which optimization level each Tomato build really used
mkdir -p "$work/shim"; : > "$work/clang.log"
printf '#!/bin/sh\necho "$*" >> "%s/clang.log"\nexec "%s" "$@"\n' "$work" "$(command -v clang)" > "$work/shim/clang"; chmod +x "$work/shim/clang"

langs="tomato tomato-debug"
have() { command -v "$1" >/dev/null 2>&1; }
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
installed() { # language -> is its toolchain here?
  case "$1" in
    go) have go ;;
    rust) have rustc && have cargo ;;        # the bigint benchmark is a cargo project, so Rust needs both
    c) have clang ;;
    cpp) have clang++ && echo '#include <vector>' | clang++ -std=c++17 -x c++ -fsyntax-only - 2>/dev/null ;;   # a clang without a C++ library cannot
    java) have javac && have java ;;
    csharp) have dotnet && [ "$(dotnet --version 2>/dev/null | cut -d. -f1)" -ge 10 ] 2>/dev/null ;;
    swift) have swiftc && swiftc --version >/dev/null 2>&1 ;;
    javascript) have node ;;
    typescript) have node && echo 'const x: number = 0;' > "$work/probe.ts" && node --experimental-strip-types --no-warnings "$work/probe.ts" >/dev/null 2>&1 ;;
    php) have php ;;
    python) have python3 ;;
    *) echo "unknown language $1" >&2; exit 2 ;;
  esac
}
all_langs="go rust python c cpp java csharp swift javascript typescript php"      # (release/perf-snapshot.sh reads the first three)
if [ -n "$wanted" ]; then tries="$(echo "$wanted" | tr ',' ' ')"
elif [ $smoke = 1 ]; then tries="$(echo "$all_langs" | sed 's/ csharp swift//')"
else tries="$all_langs"; fi
for t in $tries; do
  case " $all_langs " in *" $t "*) ;; *) echo "unknown language '$t' (known: $all_langs)" >&2; exit 2 ;; esac
  if installed "$t"; then langs="$langs $t"; else say "skipping $t: its tools are not installed"; fi
done
ext() {
  case "$1" in tomato|tomato-debug) echo tom ;; rust) echo rs ;; csharp) echo cs ;; javascript) echo js ;; typescript) echo ts ;; python) echo py ;; *) echo "$1" ;; esac
}

benchmarks="$(grep -v '^#' "$here/sizes.txt" | awk 'NF { print $1 }')"
if [ -n "$only" ]; then benchmarks="$(echo "$only" | tr ',' ' ')"; fi
size_of() { # language, the path it was built to, benchmark -> the bytes of what the build made
  case "$1" in java) cat "$2.classes"/*.class | wc -c | tr -d ' ' ;; csharp) wc -c < "$2.dir/$3.dll" | tr -d ' ' ;; *) wc -c < "$2" | tr -d ' ' ;; esac
}
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
    [ -f "$src" ] || continue         # not every benchmark is written in every language
    case "$l" in
      tomato) set -- "$home/bin/tomato" build "$src" -o "$bin" --mode "$release_mode" ;;
      tomato-debug) set -- "$home/bin/tomato" build "$src" -o "$bin" --mode debug ;;
      go) set -- "$(command -v go)" build -o "$bin" "$src" ;;
      rust) if [ -f "$here/$b/Cargo.toml" ]; then   # a benchmark that needs a crate (bigint: num-bigint) is a small Cargo project
          set -- /bin/sh -c 'cargo build --release --locked --quiet --manifest-path "$1/Cargo.toml" --target-dir "$2" && cp "$2/release/$3" "$4"' sh "$here/$b" "$work/cargo" "$b" "$bin"
        else set -- "$(command -v rustc)" -O -o "$bin" "$src"; fi ;;
      c) set -- "$(command -v clang)" -O2 -o "$bin" "$src" -lm ;;
      cpp) set -- "$(command -v clang++)" -std=c++17 -O2 -o "$bin" "$src" ;;
      java) set -- "$(command -v javac)" -d "$bin.classes" "$src" ;;
      csharp) mkdir -p "$work/cs/$b" && cp "$src" "$work/cs/$b/" && set -- "$(command -v dotnet)" build "$work/cs/$b/$b.cs" -c Release -o "$bin.dir" ;;
      swift) set -- "$(command -v swiftc)" -O -o "$bin" "$src" ;;
      javascript|typescript|php|python) set -- ;;
    esac
    if [ $# -gt 0 ]; then
      echo "BUILD $b $l" >> "$work/clang.log"
      PATH="$work/shim:$PATH" "$work/measure" "$work/build.log" "$@" 2> "$work/m" < /dev/null
      read -r wall user sys rss code < "$work/m"
      [ "$code" = 0 ] || { say "build failed: $b $l"; cat "$work/build.log" >&2; exit 1; }
      printf '%s %s %s %s\n' "$b" "$l" "$wall" "$(size_of "$l" "$bin" "$b")" >> "$work/build.tsv"
    fi
    i=1; limit=$runs; case "$l" in python|php) limit=$python_runs ;; esac; [ $smoke = 1 ] && limit=1
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
total="$(wc -l < "$work/order" | tr -d ' ')"; done_n=0; stop=0
trap 'stop=1' INT TERM      # a stop signal ends the timing loop; what has run so far is still summarized below
start_time="$(date +%s)"
while read -r b l i; do
  [ $stop = 0 ] || break
  if [ "$max_minutes" -gt 0 ] && [ $(( $(date +%s) - start_time )) -ge $((max_minutes * 60)) ]; then stop=1; say "time limit reached after $done_n of $total runs"; break; fi
  input="$(input_for "$b")"; src="$here/$b/$b.$(ext "$l")"
  case "$l" in
    java) set -- "$(command -v java)" -cp "$work/$b.$l.classes" "$b" "$input" ;;
    csharp) set -- "$(command -v dotnet)" "$work/$b.$l.dir/$b.dll" "$input" ;;
    javascript) set -- "$(command -v node)" "$src" "$input" ;;
    typescript) set -- "$(command -v node)" --experimental-strip-types --no-warnings "$src" "$input" ;;
    php) set -- "$(command -v php)" "$src" "$input" ;;
    python) set -- "$(command -v python3)" "$src" "$input" ;;
    *) set -- "$work/$b.$l" "$input" ;;
  esac
  "$work/measure" "$work/$b.$l.out" "$@" 2> "$work/m" < /dev/null
  read -r wall user sys rss code < "$work/m"
  [ $stop = 1 ] && [ "$code" != 0 ] && break      # the signal killed this run halfway: do not count it
  printf '%s %s %s %s %s %s %s\n' "$b" "$l" "$wall" "$user" "$sys" "$rss" "$code" >> "$work/raw.tsv"
  done_n=$((done_n + 1)); [ $((done_n % 50)) = 0 ] && say "$done_n of $total runs"
done < "$work/order"
ran() { grep -q "^$1 $2 " "$work/raw.tsv"; }     # benchmark, language: was it run?
[ $stop = 0 ] && partial=false || partial=true
cp "$work/raw.tsv" "$out/raw.tsv"      # every run: benchmark language wall user sys peak-memory-bytes exit-code
if [ $partial = true ]; then   # a benchmark Tomato never ran has nothing to compare with, so it is left out
  keep=""; for b in $benchmarks; do ran "$b" tomato && keep="$keep $b" || say "no Tomato run of $b: left out"; done; benchmarks="$keep"
fi
for b in $benchmarks; do
  # every language must print what Tomato prints
  for l in $langs $(awk -v b="$b" '$1 == b { print $2 }' "$work/extras"); do
    ran "$b" "$l" || continue
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
[ -n "$memory" ] || memory="$(awk '/^MemTotal:/ { printf "%d GB", $2 / 1048576 + 0.5 }' /proc/meminfo 2>/dev/null)"
if have sw_vers; then osname="$(sw_vers -productName) $(sw_vers -productVersion) ($(uname -sr))"
else osname="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}") on $(uname -m) ($(uname -sr))"; fi
used() { case " $langs " in *" $1 "*) return 0 ;; esac; return 1; }
ver() { "$@" 2>&1 | head -1 | sed 's/"/\\"/g'; }
{
  printf '{\n  "date": "%s",\n  "machine": {"cpu": "%s", "cores": %s, "memory": "%s", "os": "%s"},\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$machine" "$cores" "$memory" "$osname"
  printf '  "versions": {"tomato": "%s", "clang": "%s", "go": "%s", "rust": "%s", "python": "%s", "java": "%s", "csharp": "%s", "swift": "%s", "node": "%s", "php": "%s"},\n' \
    "$(cat "$root/VERSION")" "$(ver clang --version)" "$(have go && ver go version)" "$(have rustc && ver rustc --version)" "$(have python3 && ver python3 --version)" \
    "$(used java && ver javac -version)" "$(used csharp && ver dotnet --version)" "$(used swift && ver swiftc --version)" "$(have node && ver node --version)" "$(used php && ver php --version)"
  printf '  "runs": %s,\n  "python_runs": %s,\n  "order": "shuffled",\n  "seed": %s,\n  "load_before": "%s",\n  "load_after": "%s",\n  "partial": %s,\n' "$runs" "$python_runs" "$seed" "$load_before" "$load_after" "$partial"
  # the -O level (and -flto, when used) clang really got for the Tomato builds, read from the wrapper's log
  olevel() { awk -v l="$1" '$1 == "BUILD" { m = ($3 == l); next } m { s = ""; for (i = 1; i <= NF; i++) if ($i ~ /^-O[0-9sz]$/ || $i == "-flto") s = s (s == "" ? "" : " ") $i; if (s != "") { print s; exit } }' "$work/clang.log"; }
  printf '  "commands": {"tomato": "tomato build --mode %s (clang %s on the LLVM IR)", "tomato-debug": "tomato build --mode debug (clang %s on the LLVM IR)", "go": "go build", "rust": "rustc -O (bigint: cargo build --release with the num-bigint crate)", "rust-radix": "rustc -O (sort_radix.rs: a radix sort instead of the standard sort)", "c": "clang -O2", "cpp": "clang++ -std=c++17 -O2", "java": "javac, then java", "csharp": "dotnet build -c Release, then dotnet FILE.dll", "swift": "swiftc -O", "javascript": "node FILE", "typescript": "node --experimental-strip-types FILE", "php": "php FILE", "python": "python3 FILE"},\n' \
    "$release_mode" "$(olevel tomato | head -1)" "$(olevel tomato-debug | head -1)"
  one_result() {   # the JSON for program $l of benchmark $b
      med="$(stat_of "$b" "$l" 3 | median)"; min="$(stat_of "$b" "$l" 3 | head -1)"; max="$(stat_of "$b" "$l" 3 | tail -1)"
      rss="$(stat_of "$b" "$l" 6 | median)"
      bt="$(awk -v b="$b" -v l="$l" '$1 == b && $2 == l { print $3 }' "$work/build.tsv")"; bs="$(awk -v b="$b" -v l="$l" '$1 == b && $2 == l { print $4 }' "$work/build.tsv")"
      ok="$(awk -v b="$b" -v l="$l" '$1 == b && $2 == l { print $3 }' "$work/agree.tsv")"
      printf '%s"%s": {"median": %s, "min": %s, "max": %s, "peak_memory_bytes": %s, "build_seconds": %s, "binary_bytes": %s, "agrees": %s, "runs": %s}' \
        "$sep" "$l" "$med" "$min" "$max" "$rss" "${bt:-null}" "${bs:-null}" "$([ "$ok" = 1 ] && echo true || echo false)" "$(stat_of "$b" "$l" 3 | wc -l | tr -d ' ')"
  }
  printf '  "benchmarks": [\n'
  first=1
  for b in $benchmarks; do
    [ $first = 1 ] || printf ',\n'; first=0
    printf '    {"name": "%s", "input": %s, "results": {' "$b" "$(input_for "$b")"
    sep=""
    for l in $langs; do
      ran "$b" "$l" || continue
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
  echo "Machine: $machine, $cores cores, $memory, $osname. Tomato v$(cat "$root/VERSION"). Median of $runs runs ($python_runs for Python and PHP), all runs in one shuffled order (seed $seed); load average before $load_before, after $load_after."
  echo
  printf '| benchmark | input |'; for l in $langs; do printf ' %s (s) |' "$l"; done; echo
  printf '| --- | --- |'; for l in $langs; do printf ' ---: |'; done; echo
  for b in $benchmarks; do
    printf '| %s | %s |' "$b" "$(input_for "$b")"
    for l in $langs; do ran "$b" "$l" || { printf ' n/a |'; continue; }; printf ' %s |' "$(stat_of "$b" "$l" 3 | median | awk '{ printf "%.3f", $1 }')"; done
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
      ran "$b" "$l" || { printf ' n/a | n/a |'; continue; }
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
      for l in $cmp_langs; do ran "$b" "$l" || { printf ' n/a |'; continue; }; printf ' %s |' "$(stat_of "$b" "$l" 3 | median | awk -v t="$tm" '{ printf "%.2f", t / $1 }')"; done
    done
    echo
  done
} > "$out/results.md"
[ $site = 1 ] && cp "$out/results.json" "$root/site/benchmarks.json"
disagree="$(awk '$3 == 0 { print $1 " " $2 }' "$work/agree.tsv")"
[ -n "$disagree" ] && { echo "WARNING: outputs differ from Tomato's for: $disagree"; }
echo "wrote $out/results.json and $out/results.md"
