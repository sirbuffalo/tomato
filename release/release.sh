#!/bin/sh
# Cuts a complete Tomato release, on the Mac that holds the signing identities (Davis's iMac; see docs/releasing.md).
# Run it ON that Mac (a terminal there, or byre's bash tool with that client), from any checkout of this repository:
#
#   release/release.sh [options]
#
# No ssh is needed. Optionally, `--host USER@HOST` streams the script to another Mac over ssh and runs it there instead.
# It works in a private clone of the repository (never your own checkout) and runs these steps in order, stopping at the first failure:
#   preflight  a private clone of the repository (clean, on main, equal to origin), signing identities and a test signature,
#              the notary profile, WASI SDK and toolchains, GitHub CLI login and push rights, a quiet machine
#   version    the next version number (or --version X); refuses a version that already has a tag or a GitHub release
#   test       tests/run.sh with the WASI SDK (so the wasm files are rebuilt and compared too)
#   bump       VERSION, site/config.js and std/sys.tom (sys.version)
#   linux      the same tests (tests/run.sh) and benchmarks (plus callgrind instruction counts) on a Linux x86-64 machine over ssh, from the
#              commit being released (before the bump); results go to benchmarks/results/linux-x86_64/. A test FAILURE there stops the release; an
#              unreachable host, missing tools or failed Linux benchmarks only warn
#   bench      benchmarks/run.sh (10 runs per program, seeded shuffled order, Tomato/Go/Rust/Python), benchmarks/count.sh
#              (instruction counts) when the Lima VM exists, then the docs/performance.md snapshot
#   snapshot   release/perf-snapshot.sh: the docs/performance.md section (Mac and Linux columns)
#   build      release/build.sh and release/pkg.sh
#   sign       release/sign-pkg.sh: sign every Mach-O (Application identity), sign the package (Installer identity), notarize,
#              staple; then stapler validate, spctl, pkgutil, codesign and install-layout checks of the result. Then release/dmg.sh:
#              the signed package in a disk image, itself signed (Application identity), notarized, stapled and checked mounted
#   commit     site/build.sh (site/latest.json with the new version, pkg_sha256 and dmg_sha256) and ONE local commit of the release files
#   publish    push the tag, create the GitHub release, upload the package, disk image, tarball and latest.json, download them again and
#              compare sha256 (the public URL too)
#   push       push the release commit to main (the site only changes now, after the assets are live)
#   summary    version, benchmark ratios, notarization result, sha256, release URL
#
# Options:
#   --host USER@HOST     run on another Mac over ssh (needs Remote Login there and a key; default: this machine, no ssh;
#                        also $TOMATO_RELEASE_HOST or host= in release/release.conf)
#   --dry-run            everything except publishing: no tag, no GitHub release, no push. The release commit is made in the
#                        private clone only. Notarization still happens (it is the real test).
#   --skip-bench         no benchmarks (and no performance snapshot); needs no Go, Rust or Python
#   --no-push            publish, but leave the release commit unpushed in the clone and say so
#   --version X          release X instead of the next version
#   --resume             continue after a failure, at the first step not finished
#   --from STEP          continue at STEP (an earlier run's state is kept); steps before it are taken as done
#   --restart            throw away an unfinished run (and the clone's local changes) and begin again
#   --seed N, --runs N   benchmark shuffle seed (default 1) and runs per program (default 10)
#   --max-load N         refuse to start (and to benchmark) while the 1- or 5-minute load average is above N (default 2.0);
#   --wait-quiet SEC     wait up to SEC seconds (default 900) for the load to drop first; --no-load-check turns it off
#   --branch NAME        the branch to release from (default main)
#   --origin URL         the repository to clone (default git@github.com:sirbuffalo/tomato.git)
#   --work-dir DIR       on the signing Mac: clone, state and logs (default ~/.tomato-release)
#   --wasi-sdk DIR       the WASI SDK folder (default: $WASI_SDK, then the usual places)
#   --skip-notarize      with --dry-run only: sign but do not notarize (for a Mac that has no notary profile)
#   --no-linux           skip the Linux step; --linux-host H (default biggie.davismcd.com), --linux-tools DIR (installed by release/linux-setup.sh),
#                        --linux-max-load N (default 32) and --linux-wait SEC (300): wait for biggie's load, then go on with a warning
#   --ignore-linux-failures   release even though the Linux tests failed or did not run (publish otherwise requires a recorded passing
#                        Linux run; needs explicit approval; the summary says so loudly)
#   --no-sign            with --dry-run only: neither sign nor notarize (for a Mac whose keychain cannot sign yet); tests everything else
#   --unlock-keychain    first run `security unlock-keychain` on the signing Mac, asking for its login password on your terminal
#                        (codesign over ssh needs the login keychain unlocked; the password is never stored or passed on)
#   --list-steps, --help
#
# release/release.conf (not committed; see release.conf.example) can set host, branch, origin, work_dir, wasi_sdk,
# max_load and wait_quiet. Nothing secret goes in it: the Apple ID and app-specific password stay in the keychain profile
# `tomato-notary` (xcrun notarytool store-credentials tomato-notary), the GitHub token in gh's own login.
# No Python is used here (the benchmark comparisons run Python programs, nothing else does).
STEPS="preflight version test bump linux bench snapshot build sign commit publish push summary"
usage() { sed -n '2,/^# No Python/p' "$0" | sed 's/^# \{0,1\}//'; }
here="$(cd "$(dirname "$0")" && pwd)"
q() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }   # one argument, quoted for a shell on the other side
step_known() { case " $STEPS " in *" $1 "*) return 0 ;; esac; return 1; }

# ---------------------------------------------------------------- arguments (the same in the driver and on the signing Mac)
host=""; on_host=0; dry=0; skip_bench=0; no_push=0; version=""; resume=0; from=""; restart=0; seed=1; runs=10
max_load=2.0; wait_quiet=900; load_check=1; branch=""; origin=""; work_dir=""; wasi=""; skip_notarize=0; no_sign=0; unlock=0; no_linux=0; ignore_linux=0; linux_host=biggie.davismcd.com; linux_tools="~/.tomato-release/linux-tools"; linux_max_load=32; linux_wait=300; invoked=""
conf="$here/release.conf"
if [ -f "$conf" ]; then   # key=value lines; read, never executed
  while IFS='=' read -r k v; do
    case "$k" in ""|"#"*) continue ;; esac
    v="$(printf %s "$v" | sed 's/^ *//; s/ *$//; s/^"\(.*\)"$/\1/')"; k="$(printf %s "$k" | tr -d ' ')"
    case "$k" in host) host="$v" ;; branch) branch="$v" ;; origin) origin="$v" ;; work_dir) work_dir="$v" ;; wasi_sdk) wasi="$v" ;;
      max_load) max_load="$v" ;; wait_quiet) wait_quiet="$v" ;; esac
  done < "$conf"
fi
[ -n "${TOMATO_RELEASE_HOST:-}" ] && host="$TOMATO_RELEASE_HOST"
orig_args=""; hint_args=""; skipnext=0
for a in "$@"; do
  orig_args="$orig_args $(q "$a")"
  if [ $skipnext = 1 ]; then skipnext=0; continue; fi
  case "$a" in --resume|--restart|--on-host) ;; --from|--invoked) skipnext=1 ;; *) hint_args="$hint_args $(q "$a")" ;; esac   # the flags a resume must repeat
done
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --on-host) on_host=1; shift ;;
    --invoked) invoked="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --skip-bench) skip_bench=1; shift ;;
    --no-push) no_push=1; shift ;;
    --version) version="$2"; shift 2 ;;
    --resume) resume=1; shift ;;
    --from) from="$2"; shift 2 ;;
    --restart) restart=1; shift ;;
    --seed) seed="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --max-load) max_load="$2"; shift 2 ;;
    --wait-quiet) wait_quiet="$2"; shift 2 ;;
    --no-load-check) load_check=0; shift ;;
    --branch) branch="$2"; shift 2 ;;
    --origin) origin="$2"; shift 2 ;;
    --work-dir) work_dir="$2"; shift 2 ;;
    --wasi-sdk) wasi="$2"; shift 2 ;;
    --skip-notarize) skip_notarize=1; shift ;;
    --no-linux) no_linux=1; shift ;;
    --ignore-linux-failures) ignore_linux=1; shift ;;
    --linux-host) linux_host="$2"; shift 2 ;;
    --linux-tools) linux_tools="$2"; shift 2 ;;
    --linux-max-load) linux_max_load="$2"; shift 2 ;;
    --linux-wait) linux_wait="$2"; shift 2 ;;
    --no-sign) no_sign=1; skip_notarize=1; shift ;;
    --unlock-keychain) unlock=1; shift ;;
    --list-steps) echo $STEPS | tr ' ' '\n'; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
done
[ -n "$branch" ] || branch=main
[ -n "$origin" ] || origin="git@github.com:sirbuffalo/tomato.git"
if [ -n "$from" ] && ! step_known "$from"; then echo "error: unknown step '$from' (steps: $STEPS)" >&2; exit 2; fi
if [ "$skip_notarize" = 1 ] && [ "$dry" = 0 ]; then echo "error: --skip-notarize and --no-sign are only allowed with --dry-run (an un-notarized package must never be published)" >&2; exit 2; fi
if [ "$resume$restart" = 11 ] || { [ -n "$from" ] && [ "$restart" = 1 ]; } || { [ -n "$from" ] && [ "$resume" = 1 ]; }; then echo "error: use only one of --resume, --from and --restart" >&2; exit 2; fi

# ================================================================ the driver (runs where you are)
if [ "$on_host" = 0 ]; then
  say() { printf '%s\n' "$*" >&2; }
  [ -n "$host" ] || host=local
  inv="$0$hint_args"
  if [ "$host" = local ]; then
    say "== running on this machine (no ssh)"
    eval "exec sh \"\$0\" --on-host --invoked \"\$inv\" $orig_args" < /dev/null
  fi
  sshopt="-o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o ConnectTimeout=15"
  if ! ssh $sshopt -o BatchMode=yes "$host" true < /dev/null 2> "${TMPDIR:-/tmp}/release.err.$$"; then
    say "error: cannot ssh to $host without a password:"; sed 's/^/  /' "${TMPDIR:-/tmp}/release.err.$$" >&2; rm -f "${TMPDIR:-/tmp}/release.err.$$"
    say ""
    say "On that Mac: System Settings > General > Sharing > turn on Remote Login (allow the release user)."
    say "From this machine (once): ssh-copy-id $host   (or append this machine's ~/.ssh/id_ed25519.pub to ~/.ssh/authorized_keys there)."
    say "If the message above is 'Host key verification failed', run 'ssh $host' once by hand and accept the key."
    exit 1
  fi
  rm -f "${TMPDIR:-/tmp}/release.err.$$"
  if [ "$unlock" = 1 ]; then
    say "== unlocking the login keychain on $host (type that Mac's login password; it is not stored)"
    ssh -t $sshopt "$host" 'security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"' || { say "error: could not unlock the keychain"; exit 1; }
  fi
  remote="f=\$(mktemp /tmp/tomato-release.XXXXXX) && cat > \"\$f\" && exec sh \"\$f\" --on-host --invoked $(q "$inv") $orig_args"
  say "== $host: streaming $0"
  exec ssh -T $sshopt "$host" "$remote" < "$0"
fi

# ================================================================ on the signing Mac
case "$0" in /tmp/tomato-release.*) trap 'rm -f "$0"' EXIT ;; esac
exec < /dev/null
PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/go/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"; export PATH
command -v caffeinate >/dev/null 2>&1 && { caffeinate -i -w $$ & }   # no idle sleep while the release runs
[ -n "$work_dir" ] || work_dir="$HOME/.tomato-release"
clone="$work_dir/tomato"; state="$work_dir/state"; logs="$work_dir/logs"
mkdir -p "$work_dir" "$logs"
app_sign="${TOMATO_APP_SIGN:-Developer ID Application: Davis McDowell (39BK8TGQ26)}"
pkg_sign="${TOMATO_PKG_SIGN:-Developer ID Installer: Davis McDowell (39BK8TGQ26)}"
profile="${TOMATO_NOTARY_PROFILE:-tomato-notary}"
slug="$(printf %s "$origin" | sed -n 's#.*github\.com[:/]\([^/]*/[^/]*[^/.]\)\(\.git\)\{0,1\}$#\1#p')"; slug="${slug%.git}"   # the greedy match keeps a trailing .git
cur_step=""; started="$(date +%s)"

say() { printf '%s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
banner() { printf '\n== %s: %s\n' "$1" "$2"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on this Mac. $2"; }
st_get() { [ -f "$state" ] && sed -n "s/^$1=//p" "$state" | tail -1; }
st_set() { { [ -f "$state" ] && grep -v "^$1=" "$state"; printf '%s=%s\n' "$1" "$2"; } > "$state.new" 2>/dev/null; mv "$state.new" "$state"; }
tee_run() { # LOGFILE command...: show the output live, keep it, return the command's status
  lg="$1"; shift; rcf="$lg.rc"
  { "$@" < /dev/null 2>&1; echo $? > "$rcf"; } | tee "$lg"
  return "$(cat "$rcf")"
}
loadavg() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1, $2, $3 }'; }
wait_quiet_machine() { # label
  [ "$load_check" = 1 ] || return 0
  what="$1"
  deadline=$(( $(date +%s) + wait_quiet ))
  while :; do
    set -- $(loadavg); l1="$1"; l5="$2"
    busy="$(awk -v a="$l1" -v b="$l5" -v m="$max_load" 'BEGIN { print (a > m || b > m) ? 1 : 0 }')"
    [ "$busy" = 0 ] && { note "machine is quiet enough for $what: load average $l1 (1 min), $l5 (5 min), limit $max_load"; return 0; }
    [ "$(date +%s)" -lt "$deadline" ] || die "the machine is busy (load average $l1 / $l5, limit $max_load, waited ${wait_quiet}s). Quit what is running, or raise --max-load, or use --no-load-check. Timings taken now would not be comparable."
    note "busy: load average $l1 (1 min), $l5 (5 min) is above $max_load; checking again in 30 s"; sleep 30
  done
}
find_wasi() {
  for d in "$wasi" "${WASI_SDK:-}" "$HOME"/wasi-sdk* "$work_dir"/wasi-sdk* /opt/wasi-sdk* /usr/local/wasi-sdk* /private/tmp/wasisdk/wasi-sdk* /opt/homebrew/opt/wasi-sdk; do
    [ -n "$d" ] && [ -x "$d/bin/clang" ] && [ -d "$d/share/wasi-sysroot" ] && { echo "$d"; return 0; }
  done
  return 1
}
ratio_table() { awk -F'|' '/^Tomato.s time divided by/ { t = 1; next } t && /^\| / { printf "|%s|%s|%s|%s|\n", $2, $3, $4, $5; n++; next } t && n { exit }' "$clone/benchmarks/results/results.md"; }
in_clone() { cd "$clone" || die "no clone at $clone"; }
verify_state_tree() { # a resumed run must still be on the commit the run started from, with only release files changed
  in_clone
  base="$(st_get base_sha)"; [ -n "$base" ] || return 0
  git merge-base --is-ancestor "$base" HEAD 2>/dev/null || die "the clone is no longer based on $base (state says so). Use --restart."
  bad="$(git status --porcelain | sed 's/^...//' | grep -v -e '^VERSION$' -e '^std/sys.tom$' -e '^site/' -e '^benchmarks/results/' -e '^docs/performance.md$' || true)"
  [ -z "$bad" ] || die "unexpected changes in $clone: $(echo "$bad" | head -5 | tr '\n' ' ')"
}

# ---------------------------------------------------------------- steps
step_preflight() {
  banner preflight "this Mac, tools, keys, clone"
  [ "$(uname)" = Darwin ] || die "the signing machine must be a Mac"
  note "host $(hostname), $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null), user $(whoami)"
  # every problem is collected and listed together, so one run says everything that is missing
  problems=""
  prob() { problems="$problems
  - $*"; }
  have() { command -v "$1" >/dev/null 2>&1; }
  for t in git clang shasum codesign productsign pkgutil pkgbuild productbuild lipo spctl hdiutil xcrun curl; do have "$t" || prob "$t not found: install the Xcode command line tools (xcode-select --install)"; done
  if have xcrun; then
    xcrun --find notarytool >/dev/null 2>&1 || prob "xcrun notarytool is missing: install Xcode 13+ or the current command line tools"
    xcrun --find stapler >/dev/null 2>&1 || prob "xcrun stapler is missing: install the Xcode command line tools"
  fi
  have gh || prob "gh (GitHub CLI) not found: brew install gh, then gh auth login"
  if [ "$skip_bench" = 0 ]; then
    have go || prob "go not found: brew install go (the benchmarks compare against it), or use --skip-bench"
    have rustc && have cargo || prob "rustc/cargo not found: install Rust (rustup, or brew install rust), or use --skip-bench"
    if have python3 && python3 --version >/dev/null 2>&1; then :; else prob "python3 does not run (xcode-select --install): only the benchmark comparison programs use it; or use --skip-bench"; fi
  fi
  # signing identities, and a real test signature: the login keychain must be unlocked and its keys usable without a dialog
  if [ "$no_sign" = 1 ]; then note "signing not checked (--no-sign, dry run): the package will NOT be signed"
  else
    ids="$(security find-identity -v 2>/dev/null)"; ids_ok=1
    printf '%s\n' "$ids" | grep -q "\"$app_sign\"" || { ids_ok=0; prob "signing identity not in the keychain: $app_sign (import the Developer ID Application certificate with its private key)"; }
    printf '%s\n' "$ids" | grep -q "\"$pkg_sign\"" || { ids_ok=0; prob "signing identity not in the keychain: $pkg_sign (import the Developer ID Installer certificate with its private key)"; }
    if [ "$ids_ok" = 1 ] && have codesign && have productsign && have pkgbuild; then
      t="$(mktemp -d)"; cp /usr/bin/true "$t/probe"
      if codesign --force --sign "$app_sign" "$t/probe" > "$t/err" 2>&1; then
        pkgbuild --nopayload --identifier com.davismcd.tomato.probe --version 1 "$t/p.pkg" > /dev/null 2>&1
        if productsign --sign "$pkg_sign" "$t/p.pkg" "$t/ps.pkg" > "$t/err" 2>&1; then note "test signatures with both identities worked"
        else prob "cannot sign a package with '$pkg_sign': $(tail -1 "$t/err"). See the keychain fix below."; keychain_hint=1; fi
      else prob "cannot sign code with '$app_sign': $(tail -1 "$t/err"). See the keychain fix below."; keychain_hint=1; fi
      rm -rf "$t"
    fi
    if [ "$skip_notarize" = 1 ]; then note "notary profile not checked (--skip-notarize, dry run)"
    elif have xcrun; then
      if xcrun notarytool history --keychain-profile "$profile" > "$logs/notary-check.txt" 2>&1; then note "notary profile $profile works"
      else prob "notarytool keychain profile '$profile' is missing or rejected ($(head -1 "$logs/notary-check.txt")). Create it once, in Terminal on this Mac (only the Apple ID owner can; the app-specific password is typed there and stays in the keychain): xcrun notarytool store-credentials $profile --apple-id APPLE_ID --team-id 39BK8TGQ26"; fi
    fi
  fi
  # WASI SDK
  if w="$(find_wasi)" && "$w/bin/clang" --version > /dev/null 2>&1; then st_set wasi "$w"; note "WASI SDK $w"
  else prob "no WASI SDK found (the tests rebuild the wasm files with it). Unpack one from https://github.com/WebAssembly/wasi-sdk/releases (wasi-sdk-24.0-arm64-macos.tar.gz) into your home folder and pass --wasi-sdk DIR, or set WASI_SDK, or leave it at ~/wasi-sdk-* or /opt/wasi-sdk-*"; fi
  # GitHub (only a real release needs GitHub; a dry run from another origin does not)
  if [ -n "$slug" ] && have gh; then
    if gh auth status > "$logs/gh-check.txt" 2>&1; then
      perm="$(gh repo view "$slug" --json viewerPermission -q .viewerPermission 2>/dev/null)"
      case "$perm" in ADMIN|MAINTAIN|WRITE) note "gh: logged in, $perm on $slug" ;; *) prob "gh cannot write to $slug (permission: ${perm:-unknown})" ;; esac
    else prob "gh is not logged in on this Mac: run gh auth login"; fi
  elif [ -z "$slug" ]; then
    [ "$dry" = 1 ] && note "origin is not on GitHub: GitHub checks skipped (dry run)" || prob "origin $origin is not a GitHub repository, so a real release cannot be published (use --dry-run)"
  fi
  if [ -z "$(git config --global user.email 2>/dev/null)" ]; then   # no identity configured: the release commit uses the GitHub login's (see step_commit)
    have gh && [ -n "$(gh api user -q .login 2>/dev/null)" ] || prob "git has no user.email and gh cannot tell who you are: git config --global user.name ...; git config --global user.email ..."
  fi
  if [ -n "$problems" ]; then
    [ -z "${keychain_hint:-}" ] || problems="$problems
  - keychain fix, once, in Terminal on this Mac (it asks for the login password): security unlock-keychain ~/Library/Keychains/login.keychain-db && security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db   (errSecInternalComponent means the keychain is locked or its key refuses non-interactive use; over ssh add --unlock-keychain)
  - if signing works right after a login but fails later: the keychain locks itself on a timeout or on sleep. Turn that off once: security set-keychain-settings ~/Library/Keychains/login.keychain-db   (no -t, no -l; security show-keychain-info must then say no-timeout without lock-on-sleep)
  - if this Mac was restarted: log in at it once (at the Mac or through Screen Sharing). macOS unlocks the login keychain at login; if signing still fails after that, redo the keychain fix above"
    die "preflight found problems:$problems"
  fi
  # the private clone
  if [ -z "$(st_get base_sha)" ]; then   # the clone has not been synced yet (a first run, or one that failed in preflight): do the full path
    if [ ! -d "$clone/.git" ]; then
      rm -rf "$clone"; say "cloning $origin into $clone"; git clone --quiet --no-local "$origin" "$clone" || die "git clone $origin failed (does this Mac have access to GitHub over ssh?)"
    fi
    in_clone; git remote set-url origin "$origin"
    git fetch --quiet --tags --prune origin || die "git fetch origin failed"
    git rev-parse --verify --quiet "origin/$branch" > /dev/null || die "origin has no branch $branch"
    dirty="$(git status --porcelain)"; ahead="$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)"
    if [ -n "$dirty" ] || [ "$ahead" != 0 ] || [ "$(git rev-parse --abbrev-ref HEAD)" != "$branch" ]; then
      if [ "$restart" = 1 ] || { [ "$prev_status" = finished ] && [ "$prev_mode" = dry ]; }; then
        note "resetting the clone to origin/$branch (discarding: $(git status --short | wc -l | tr -d ' ') changed files, $ahead unpushed commits from the last unfinished or dry run)"
        git checkout -q -f -B "$branch" "origin/$branch" && git clean -fdxq || die "could not reset the clone"
      else
        die "the clone $clone is not clean and on $branch, equal to origin ($(git status --short | wc -l | tr -d ' ') changes, $ahead unpushed commits). It is private to this script; inspect it, or use --restart to discard everything in it."
      fi
    fi
    git merge --ff-only -q "origin/$branch" || die "cannot fast-forward the clone to origin/$branch"
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$branch")" ] || die "the clone is not equal to origin/$branch"
    git clean -fdxq   # untracked and ignored leftovers (release/out) never leak into a release
    st_set base_sha "$(git rev-parse HEAD)"; note "clone: $branch at $(git rev-parse --short HEAD), equal to origin"
    if [ -n "$slug" ]; then git push --dry-run -q origin "HEAD:refs/heads/$branch" > "$logs/push-check.txt" 2>&1 || { cat "$logs/push-check.txt" >&2; die "git push to origin would fail (ssh key for GitHub on this Mac?)"; }; note "git push access to origin works"; fi
  else
    verify_state_tree; note "resuming in $clone at $(git rev-parse --short HEAD)"
  fi
  wait_quiet_machine preflight
}

release_exists() { # TAG: 0 yes, 1 no; stops on any other gh failure (network, auth) instead of reading it as "no"
  out="$(gh release view "$1" --repo "$slug" 2>&1)" && return 0
  case "$out" in *"not found"*|*"Not Found"*) return 1 ;; esac
  die "cannot ask GitHub about release $1: $out"
}

step_version() {
  banner version "choose the number"
  in_clone; cur="$(cat VERSION)"
  if [ -n "$version" ]; then new="$version"
  elif [ -n "$slug" ] && ! release_exists "v$cur" && ! git rev-parse -q --verify "refs/tags/v$cur" > /dev/null; then new="$cur"   # VERSION was bumped ahead of its release
  else new="$(printf %s "$cur" | awk -F. -v OFS=. '{ $NF = $NF + 1; print }')"; fi
  printf %s "$new" | grep -Eq '^[0-9]+(\.[0-9]+)+$' || die "'$new' is not a version number like 0.51"
  if [ -n "$slug" ] && [ -z "$(st_get published)" ]; then
    release_exists "v$new" && die "GitHub already has a release v$new"
  fi
  git rev-parse -q --verify "refs/tags/v$new" > /dev/null && [ -z "$(st_get published)" ] && die "tag v$new already exists"
  [ "$new" != "$cur" ] && [ "$(printf '%s\n%s\n' "$cur" "$new" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" != "$new" ] && die "$new is not newer than the current $cur"
  st_set version "$new"; say "releasing Tomato $new (current VERSION is $cur)"
}

step_test() {
  banner test "tests/run.sh with the WASI SDK"
  in_clone; verify_state_tree
  [ "$(cat VERSION)" = "$(st_get version)" ] && [ "$(cat VERSION)" != "$(git show HEAD:VERSION)" ] && die "VERSION is already bumped; tests must run on the unbumped tree (use --from bump, or --restart)"
  if tee_run "$logs/test.log" env WASI_SDK="$(st_get wasi)" sh tests/run.sh; then :; else
    grep '^FAIL' "$logs/test.log" | head -10 >&2; die "tests failed (full output: $logs/test.log on the signing Mac)"
  fi
  tail -1 "$logs/test.log" | grep -q ' 0 failed' || die "unexpected test summary: $(tail -1 "$logs/test.log")"
  [ -z "$(git status --porcelain)" ] || die "the tests changed tracked files (the wasm rebuild is not identical?): $(git status --short | head -5 | tr '\n' ' ')"
  st_set tests "$(tail -1 "$logs/test.log")"
}

step_bump() {
  banner bump "VERSION, site/config.js and std/sys.tom"
  in_clone; v="$(st_get version)"
  printf '%s\n' "$v" > VERSION
  sed "s/window.TOMATO_VERSION = \".*\"/window.TOMATO_VERSION = \"$v\"/" site/config.js > site/config.js.new && mv site/config.js.new site/config.js
  for f in std/sys.tom site/wasm/std/sys.tom; do   # sys.version() returns the version as text (tests/run.sh t_sys_version checks it against VERSION)
    sed "s/^    return '[0-9.]*'\$/    return '$v'/" "$f" > "$f.new" && mv "$f.new" "$f"
  done
  note "VERSION, site/config.js and std/sys.tom now say $v"
}

step_bench() {
  banner bench "benchmarks"
  in_clone; verify_state_tree; v="$(st_get version)"
  if [ "$skip_bench" = 1 ]; then note "skipped (--skip-bench): benchmarks/results and docs/performance.md are unchanged"; st_set bench skipped; return 0; fi
  wait_quiet_machine "the benchmarks"
  tee_run "$logs/bench.log" sh benchmarks/run.sh --runs "$runs" --seed "$seed" --site || die "benchmarks/run.sh failed (see $logs/bench.log)"
  grep -q "\"tomato\": \"$v\"" benchmarks/results/results.json || die "benchmarks/results/results.json is not for v$v"
  if [ -n "$(grep "outputs differ" "$logs/bench.log")" ]; then die "a benchmark's output differed between languages (see $logs/bench.log)"; fi
  load_after="$(loadavg)"
  if command -v limactl > /dev/null 2>&1 && limactl list -q 2>/dev/null | grep -qx tomato-count; then
    tee_run "$logs/count.log" sh benchmarks/count.sh || die "benchmarks/count.sh failed (see $logs/count.log)"
    st_set counts yes
  else
    note "instruction counts skipped: no Lima VM 'tomato-count' here (benchmarks/count.sh --setup creates it)"; st_set counts "skipped (no VM)"
  fi
  st_set bench "done (load after: $load_after)"
}

# The script that runs ON the Linux machine (sent over ssh): tests, benchmarks, instruction counts. It prints @@KEY=value lines.
linux_remote_script() { cat <<'REMOTE'
# args: tools runs seed skip_bench max_load wait_sec newversion
tools="$1"; runs="$2"; seed="$3"; skip_bench="$4"; max_load="$5"; wait_sec="$6"; newver="$7"
W="$HOME/.tomato-release/linux"; src="$W/src"; out="$W/out"
case "$tools" in "~/"*) tools="$HOME/${tools#\~/}" ;; esac
PATH="$tools/bin:$tools/llvm/bin:$tools/go/bin:$PATH"; export PATH
missing=""; for t in clang go rustc cargo python3 gcc make valgrind; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
[ -z "$missing" ] || { echo "@@TOOLS_MISSING=$missing"; exit 0; }
rm -rf "$out"; mkdir -p "$out"; cd "$src" || exit 1
echo "@@MACHINE=$(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //'), $(nproc) threads, $(uname -sr)"
deadline=$(( $(date +%s) + wait_sec ))
while :; do
  l1="$(cut -d' ' -f1 /proc/loadavg)"
  awk -v a="$l1" -v m="$max_load" 'BEGIN { exit !(a <= m) }' && break
  [ "$(date +%s)" -lt "$deadline" ] || { echo "@@LOAD_WARN=load average $l1 is above $max_load after waiting ${wait_sec}s; benchmarking anyway"; break; }
  sleep 20
done
# Without working LTO the benchmark numbers would be the wrong ones, so then (and only then) they are skipped; failing tests still get
# benchmarks, as before (--ignore-linux-failures goes on with fresh Linux numbers). A toolchain without LTO still gets its tests (which
# then do not require LTO) and is reported as a failure on the last line of tests.log.
lto_ok=1; sh release/check-lto.sh > "$out/tests.log" 2>&1 || lto_ok=0
TOMATO_TEST_REQUIRE_LTO=$lto_ok sh tests/run.sh >> "$out/tests.log" 2>&1; rc=$?
[ "$lto_ok" = 1 ] || { echo 'FAIL Linux release toolchain does no link-time optimisation (release/check-lto.sh): 1 failed in addition to the tests above' >> "$out/tests.log"; rc=1; }
echo "@@TESTS_RC=$rc"; echo "@@TESTS_SUMMARY=$(tail -1 "$out/tests.log")"
if [ "$skip_bench" = 0 ] && [ "$lto_ok" = 0 ]; then
  echo "@@BENCH=skipped"; echo "@@COUNT=skipped"
elif [ "$skip_bench" = 0 ]; then
  echo "$newver" > VERSION   # the tests ran on the commit before the bump (they compare VERSION with site/latest.json); the results are for the new version
  sh benchmarks/run.sh --runs "$runs" --seed "$seed" --out "$out" > "$out/bench.log" 2>&1 && ! grep -q "outputs differ" "$out/bench.log" && echo "@@BENCH=ok" || echo "@@BENCH=failed"
  sh benchmarks/count.sh --guest --runs 2 > "$out/instructions.md" 2> "$out/count.log" && echo "@@COUNT=ok" || echo "@@COUNT=failed"
fi
echo "@@DONE=1"
REMOTE
}

step_linux() {
  banner linux "tests and benchmarks on $linux_host (Linux x86-64)"
  in_clone; verify_state_tree; v="$(st_get version)"; lo=benchmarks/results/linux-x86_64
  # the override is part of the run: a --resume without the flag must not stop at the same failure again
  if [ "$ignore_linux" = 1 ]; then st_set ignore_linux 1; elif [ "$(st_get ignore_linux)" = 1 ]; then ignore_linux=1; fi
  # Why the benchmarks run on a slightly different tree than the tests: the tests need VERSION to equal site/latest.json (the commit before
  # the bump); the benchmarks must record the new version, and VERSION is the only bumped file they read (site/config.js is website-only).
  # results.json is checked below to name that version, so the committed Linux numbers cannot belong to another release.
  # back to what is committed: a skipped or failed step keeps the previous release's Linux results, and a resume drops this run's earlier ones
  if [ -n "$(git ls-tree HEAD -- "$lo")" ]; then git checkout -q HEAD -- "$lo"; fi   # nothing committed yet (the first release): nothing to restore
  git clean -fdq -- "$lo" || true
  st_set linux_passed ""   # set again below only by a run whose tests exited 0 with a " 0 failed" summary; publish requires it
  if [ "$no_linux" = 1 ]; then note "skipped (--no-linux)"; st_set linux "skipped (--no-linux)"; st_set linux_tests "skipped (--no-linux)"; return 0; fi
  sshopt="-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
  warn() { printf 'WARNING: %s\n' "$*" >&2; st_set linux "NOT RUN: $*"; st_set linux_tests "not run"; }
  mk() { sed -n "s/^@@$1=//p" "$logs/linux.log" | tail -1; }
  fo="$logs/linux-out"
  # a resume after the gate stopped the run reuses the finished remote run (tests, benchmarks and counts take long) and only re-applies the gate
  if [ "$(st_get linux_fetched)" = "$v" ] && [ -f "$fo/tests.log" ]; then note "reusing the finished Linux run from this release run"
  else
  if ! ssh $sshopt "$linux_host" true < /dev/null 2> "$logs/linux-ssh.txt"; then
    warn "cannot ssh to $linux_host ($(tail -1 "$logs/linux-ssh.txt")). Authorize this Mac's key there (ssh-copy-id $linux_host, or append ~/.ssh/id_ed25519.pub to ~/.ssh/authorized_keys) and run 'ssh $linux_host' once by hand to accept the host key. The macOS release goes on."
    return 0
  fi
  # the commit the run started from (the Mac tests ran on it too); the new VERSION is written before the benchmarks
  git archive HEAD | ssh $sshopt "$linux_host" 'rm -rf ~/.tomato-release/linux && mkdir -p ~/.tomato-release/linux/src && tar -xf - -C ~/.tomato-release/linux/src' || die "copying the source to $linux_host failed"
  linux_remote_script > "$logs/linux-run.sh"
  ssh $sshopt "$linux_host" 'cat > ~/.tomato-release/linux-run.sh' < "$logs/linux-run.sh" || die "cannot copy the Linux run script"
  tee_run "$logs/linux.log" ssh $sshopt "$linux_host" "sh ~/.tomato-release/linux-run.sh $(q "$linux_tools") $runs $seed $skip_bench $linux_max_load $linux_wait $v" || { warn "the run on $linux_host was cut off (see $logs/linux.log)"; return 0; }
  mk() { sed -n "s/^@@$1=//p" "$logs/linux.log" | tail -1; }
  tm="$(mk TOOLS_MISSING)"
  if [ -n "$tm" ]; then warn "Linux tools missing on $linux_host:$tm. Install them once: ssh $linux_host 'sh -s' < release/linux-setup.sh (or --linux-tools DIR)"; return 0; fi
  [ -n "$(mk DONE)" ] || { warn "the Linux run did not finish (see $logs/linux.log)"; return 0; }
  rm -rf "$fo"; mkdir -p "$fo"
  # to a file first: in a pipe, only the local tar's status would be seen, and a cut-off stream could look complete
  ssh $sshopt "$linux_host" 'tar -cf - -C ~/.tomato-release/linux/out .' > "$fo.tar" || die "copying the Linux results back failed"
  tar -xf "$fo.tar" -C "$fo" || die "the Linux results archive is damaged"; rm -f "$fo.tar"
  [ -f "$fo/tests.log" ] || die "the Linux results lack tests.log"
  cp "$fo/tests.log" "$logs/linux-tests.log"
  st_set linux_fetched "$v"
  fi
  cp "$fo/tests.log" "$logs/linux-tests.log"
  [ -z "$(mk LOAD_WARN)" ] || printf 'WARNING: %s\n' "$(mk LOAD_WARN)" >&2
  st_set linux_machine "$(mk MACHINE)"; st_set linux_load_warn "$(mk LOAD_WARN)"
  st_set linux_tests "$(mk TESTS_SUMMARY)"
  b="$(mk BENCH)"; c="$(mk COUNT)"
  if [ "$skip_bench" = 1 ]; then st_set linux "tests only (--skip-bench)"
  else
    if [ "$b" = ok ] && ! grep -q "\"tomato\": \"$v\"" "$fo/results.json" 2>/dev/null; then b=failed; fi   # (a skipped run stays skipped)
    if [ "$b" = ok ]; then   # fresh numbers replace the committed ones, all of them
      rm -rf "$lo"; mkdir -p "$lo"; cp "$fo/results.json" "$fo/results.md" "$lo/"
      if [ "$c" = ok ]; then cp "$fo/instructions.md" "$lo/"; fi
    fi
    st_set linux "tests $(mk TESTS_RC | sed 's/^0$/passed/; s/^[1-9].*/FAILED/'); benchmarks ${b:-n/a}; instruction counts ${c:-n/a}"
    [ "$b" = skipped ] && printf 'WARNING: the Linux benchmarks were skipped on %s: its toolchain does no link-time optimisation (release/check-lto.sh; see %s)\n' "$linux_host" "$logs/linux-tests.log" >&2
    [ "$b" = ok ] || [ "$b" = skipped ] || printf 'WARNING: the Linux benchmarks failed on %s (see %s); the release goes on without fresh Linux numbers.\n' "$linux_host" "$logs/linux.log" >&2
  fi
  if [ "$(mk TESTS_RC)" != 0 ]; then
    st_set linux_tests "FAILED: $(mk TESTS_SUMMARY)"
    grep '^FAIL' "$logs/linux-tests.log" | head -15 >&2
    if [ "$ignore_linux" = 1 ]; then printf 'WARNING: the Linux tests FAILED, continuing because of --ignore-linux-failures (log: %s)\n' "$logs/linux-tests.log" >&2
    else die "the Linux x86-64 tests FAILED on $linux_host (log: $logs/linux-tests.log). Fix them, or release anyway with --resume --ignore-linux-failures"; fi
  fi
  if [ "$(mk TESTS_RC)" = 0 ]; then case "$(mk TESTS_SUMMARY)" in *" passed, 0 failed") st_set linux_passed "$v" ;; esac; fi
}

step_snapshot() {
  banner snapshot "docs/performance.md"
  in_clone; v="$(st_get version)"
  if [ "$skip_bench" = 1 ]; then note "skipped (--skip-bench)"; return 0; fi
  sh release/perf-snapshot.sh "$v" || die "release/perf-snapshot.sh failed"
}

step_build() {
  banner build "release/build.sh and release/pkg.sh"
  in_clone; verify_state_tree
  tee_run "$logs/build.log" sh -c 'sh release/build.sh && sh release/pkg.sh' || die "building the release files failed (see $logs/build.log)"
  v="$(st_get version)"; [ -f "release/out/tomato-$v.pkg" ] && [ -f "release/out/tomato-$v.tar.gz" ] && [ -f release/out/latest.json ] || die "release/out lacks the expected files"
}

check_pkg() { # the signed package: signature, staple, Gatekeeper, binaries, install layout
  p="$1"; v="$2"
  pkgutil --check-signature "$p" | tee "$logs/check-signature.txt" | sed 's/^/   /'
  grep -q "$pkg_sign" "$logs/check-signature.txt" || die "the package is not signed by '$pkg_sign'"
  if [ "$skip_notarize" = 0 ]; then
    grep -q 'Notarization: trusted by the Apple notary service' "$logs/check-signature.txt" || die "pkgutil does not report the package as notarized"
    xcrun stapler validate "$p" || die "stapler validate failed"
    spctl --assess --type install -vv "$p" 2>&1 | sed 's/^/   /'; [ "$(spctl --assess --type install "$p" > /dev/null 2>&1; echo $?)" = 0 ] || die "spctl rejects the package"
  fi
  x="$(mktemp -d)"; pkgutil --expand-full "$p" "$x/x" || die "cannot expand the package"
  comp="$x/x/component.pkg"
  for s in preinstall postinstall; do [ -x "$comp/Scripts/$s" ] || die "$s is not executable in the package"; done
  [ "$(readlink "$comp/Payload/usr/local/bin/tomato")" = ../lib/tomato/native/bin/tomato ] || die "usr/local/bin/tomato is not the expected symlink"
  grep -q "<pkg-ref id=\"com.davismcd.tomato\" version=\"$v\"" "$x/x/Distribution" || die "Distribution does not list component.pkg at version $v"
  bins="$(find "$x/x" -type f -exec file {} + | grep -v '(for architecture' | sed -n 's/: *Mach-O.*//p' | sort -u)"
  [ -n "$bins" ] || die "no Mach-O binary found in the package"
  echo "$bins" | while IFS= read -r b; do
    codesign --verify --strict "$b" || exit 1
    codesign -dv --verbose=4 "$b" 2>&1 | grep -q 'flags=.*runtime' || { echo "not hardened: $b" >&2; exit 1; }
    codesign -dv --verbose=4 "$b" 2>&1 | grep -q "Authority=$app_sign" || { echo "not signed by $app_sign: $b" >&2; exit 1; }
  done || die "a Mach-O file in the package is not signed with the hardened runtime by the Application identity"
  note "every Mach-O is signed by '$app_sign' with the hardened runtime: $(echo "$bins" | sed 's#.*/##' | sort -u | tr '\n' ' ')"
  [ "$("$comp/Payload/usr/local/lib/tomato/native/bin/tomato" version 2>&1)" = "Tomato v$v (compiler written in Tomato)" ] || die "the packaged tomato does not report v$v"
  rm -rf "$x"; note "install layout and the packaged 'tomato version' check out"
}

step_sign() {
  banner sign "sign, notarize, staple, verify"
  in_clone; verify_state_tree; v="$(st_get version)"; o=release/out
  [ -f "$o/tomato-$v.pkg" ] || die "$o/tomato-$v.pkg is missing; run the build step"
  if [ "$no_sign" = 1 ]; then   # dry run on a Mac that cannot sign yet: everything after this still gets exercised
    note "--no-sign: the package stays UNSIGNED"; sum="$(shasum -a 256 "$o/tomato-$v.pkg" | cut -d' ' -f1)"
    TOMATO_NO_SIGN=1 TOMATO_LATEST_JSON="$o/latest.json" tee_run "$logs/dmg.log" sh release/dmg.sh "$o/tomato-$v.pkg" "$o/tomato-$v.dmg" || die "building the disk image failed (see $logs/dmg.log)"
    st_set pkg_sha256 "$sum"; st_set dmg_sha256 "$(shasum -a 256 "$o/tomato-$v.dmg" | cut -d' ' -f1)"; st_set tar_sha256 "$(shasum -a 256 "$o/tomato-$v.tar.gz" | cut -d' ' -f1)"; st_set notarization "NOT signed or notarized (dry run with --no-sign)"; return 0
  fi
  [ "$skip_notarize" = 1 ] && export TOMATO_SKIP_NOTARIZE=1
  # a resume after a disk-image failure keeps the package signed and checked by this run: re-signing would repack it (a new
  # hash) and cost another notarization; a rebuilt (unsigned) package has another hash, so it is signed again
  psig="$(st_get pkg_signed_sha256)"
  if [ -n "$psig" ] && [ "$(shasum -a 256 "$o/tomato-$v.pkg" | cut -d' ' -f1)" = "$psig" ]; then
    note "the package was already signed, notarized and checked in this release run (sha256 $psig): only the disk image is redone"
  else
  rm -f "$o/tomato-$v.signed.pkg"
  TOMATO_APP_SIGN="$app_sign" TOMATO_PKG_SIGN="$pkg_sign" TOMATO_NOTARY_PROFILE="$profile" TOMATO_LATEST_JSON="$o/latest.json" \
    tee_run "$logs/sign.log" sh release/sign-pkg.sh "$o/tomato-$v.pkg" "$o/tomato-$v.signed.pkg" || die "signing or notarizing failed (see $logs/sign.log; Apple's log is printed above on a rejection)"
  mv "$o/tomato-$v.signed.pkg" "$o/tomato-$v.pkg"
  check_pkg "$o/tomato-$v.pkg" "$v"
  st_set pkg_signed_sha256 "$(shasum -a 256 "$o/tomato-$v.pkg" | cut -d' ' -f1)"
  fi
  sum="$(shasum -a 256 "$o/tomato-$v.pkg" | cut -d' ' -f1)"
  grep -q "\"pkg_sha256\": \"$sum\"" "$o/latest.json" || die "latest.json's pkg_sha256 is not the signed package's hash $sum"
  tsum="$(shasum -a 256 "$o/tomato-$v.tar.gz" | cut -d' ' -f1)"; grep -q "\"sha256\": \"$tsum\"" "$o/latest.json" || die "latest.json's sha256 is not the tarball's hash"
  # the disk image: the finished package inside, the image itself signed, notarized and stapled; dmg.sh checks it mounted
  rm -f "$o/tomato-$v.dmg"
  TOMATO_APP_SIGN="$app_sign" TOMATO_NOTARY_PROFILE="$profile" TOMATO_LATEST_JSON="$o/latest.json" \
    tee_run "$logs/dmg.log" sh release/dmg.sh "$o/tomato-$v.pkg" "$o/tomato-$v.dmg" || die "building, signing or notarizing the disk image failed (see $logs/dmg.log)"
  dsum="$(shasum -a 256 "$o/tomato-$v.dmg" | cut -d' ' -f1)"
  grep -q "\"dmg_sha256\": \"$dsum\"" "$o/latest.json" || die "latest.json's dmg_sha256 is not the disk image's hash $dsum"
  grep -q "\"pkg_sha256\": \"$sum\"" "$o/latest.json" || die "latest.json lost the package's hash while adding the disk image"
  codesign -dv --verbose=4 "$o/tomato-$v.dmg" 2>&1 | grep -q "Authority=$app_sign" || die "the disk image is not signed by '$app_sign'"
  if [ "$skip_notarize" = 0 ]; then
    xcrun stapler validate "$o/tomato-$v.dmg" || die "stapler validate failed on the disk image"
    spctl --assess --type open --context context:primary-signature "$o/tomato-$v.dmg" > /dev/null 2>&1 || die "spctl rejects the disk image"
  fi
  st_set pkg_sha256 "$sum"; st_set dmg_sha256 "$dsum"; st_set tar_sha256 "$tsum"
  st_set notarization "$(if [ "$skip_notarize" = 1 ]; then echo 'NOT notarized (dry run with --skip-notarize)'; else echo "package: $(sed -n 's/^notarized (\(.*\))$/Accepted, \1/p' "$logs/sign.log" | tail -1); disk image: $(sed -n 's/^notarized dmg (\(.*\))$/Accepted, \1/p' "$logs/dmg.log" | tail -1)"; fi)"
  note "signed package sha256 $sum"; note "signed disk image sha256 $dsum"
}

step_commit() {
  banner commit "site files and one local release commit"
  in_clone; verify_state_tree; v="$(st_get version)"; sum="$(st_get pkg_sha256)"
  [ -n "$sum" ] || die "no signed package yet (the sign step has not finished)"
  [ "$(shasum -a 256 "release/out/tomato-$v.pkg" | cut -d' ' -f1)" = "$sum" ] || die "release/out/tomato-$v.pkg is not the package that was signed"
  sh site/build.sh > "$logs/site-build.log" 2>&1 || { cat "$logs/site-build.log" >&2; die "site/build.sh failed"; }
  [ "$(cat VERSION)" = "$v" ] || die "VERSION is not $v"
  [ "$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' site/latest.json)" = "$v" ] || die "site/latest.json is not version $v"
  [ "$(sed -n 's/.*"pkg_sha256" *: *"\([^"]*\)".*/\1/p' site/latest.json)" = "$sum" ] || die "site/latest.json pkg_sha256 is not $sum"
  dsum="$(st_get dmg_sha256)"; [ -n "$dsum" ] || die "no disk image yet (the sign step has not finished)"
  [ "$(shasum -a 256 "release/out/tomato-$v.dmg" | cut -d' ' -f1)" = "$dsum" ] || die "release/out/tomato-$v.dmg is not the disk image that was signed"
  [ "$(sed -n 's/.*"dmg_sha256" *: *"\([^"]*\)".*/\1/p' site/latest.json)" = "$dsum" ] || die "site/latest.json dmg_sha256 is not $dsum"
  [ "$(sed -n 's/.*TOMATO_VERSION = "\([^"]*\)".*/\1/p' site/config.js)" = "$v" ] || die "site/config.js is not $v"
  bad="$(git status --porcelain | sed 's/^...//' | grep -v -e '^VERSION$' -e '^std/sys.tom$' -e '^site/' -e '^benchmarks/results/' -e '^docs/performance.md$' || true)"
  [ -z "$bad" ] || die "unexpected changed files, not committing: $(echo "$bad" | head -5 | tr '\n' ' ')"
  if [ -z "$(git config user.email)" ]; then   # the author is the logged-in GitHub account (its noreply address), so nothing personal is configured here
    login="$(gh api user -q .login)"; gid="$(gh api user -q .id)"; gname="$(gh api user -q .name)"
    export GIT_AUTHOR_NAME="${gname:-$login}" GIT_COMMITTER_NAME="${gname:-$login}" GIT_AUTHOR_EMAIL="$gid+$login@users.noreply.github.com" GIT_COMMITTER_EMAIL="$gid+$login@users.noreply.github.com"
  fi
  if [ -n "$(git status --porcelain)" ]; then
    git add -A VERSION std/sys.tom site benchmarks/results docs/performance.md
    git commit -q -m "Release Tomato $v" -m "Signed and notarized package sha256 $sum, disk image sha256 $dsum." || die "git commit failed"
  fi
  [ "$(git rev-parse HEAD)" != "$(st_get base_sha)" ] || die "nothing was committed"
  st_set commit_sha "$(git rev-parse HEAD)"; note "committed $(git rev-parse --short HEAD) \"Release Tomato $v\" in $clone (not pushed)"
}

step_publish() {
  banner publish "tag, GitHub release, assets, verification"
  in_clone; v="$(st_get version)"; sum="$(st_get pkg_sha256)"; tsum="$(st_get tar_sha256)"; dsum="$(st_get dmg_sha256)"; o=release/out; tag="v$v"; c="$(st_get commit_sha)"
  [ -n "$c" ] && [ "$(git rev-parse HEAD)" = "$c" ] || die "HEAD is not the release commit; run the commit step"
  # the Linux gate: a real release needs a recorded passing Linux run; a skipped, unreachable or failed one needs the explicit
  # override. It is checked before the dry-run exit too, so a dry run shows what a real one would do.
  lt="$(st_get linux_tests)"
  if [ "$(st_get linux_passed)" != "$v" ] && [ "$ignore_linux" != 1 ] && [ "$(st_get ignore_linux)" != 1 ]; then
    gate="no passing Linux x86-64 test run is recorded (linux tests: ${lt:-none}). Run the linux step (--from linux), or publish anyway only with explicit approval: --resume --ignore-linux-failures"
    if [ "$dry" = 1 ]; then say "DRY RUN: a real release would STOP here: $gate"; else die "$gate"; fi
  elif [ "$(st_get linux_passed)" = "$v" ]; then note "Linux gate: passed ($lt)"
  else note "Linux gate: OVERRIDDEN by --ignore-linux-failures (linux tests: ${lt:-none})"; fi
  if [ "$dry" = 1 ]; then
    say "DRY RUN: would push tag $tag ($(git rev-parse --short HEAD)), create the GitHub release $tag on $slug with"
    ls -l "$o/tomato-$v.pkg" "$o/tomato-$v.dmg" "$o/tomato-$v.tar.gz" "$o/latest.json" | awk '{ print "   " $NF " (" $5 " bytes)" }'
    say "and then download them and compare sha256 $sum (package), $dsum (disk image)."; return 0
  fi
  [ -n "$slug" ] || die "origin is not a GitHub repository"
  [ -n "$dsum" ] && [ -f "$o/tomato-$v.dmg" ] && [ "$(shasum -a 256 "$o/tomato-$v.dmg" | cut -d" " -f1)" = "$dsum" ] || die "the signed disk image $o/tomato-$v.dmg is missing or changed; nothing is published without it"
  if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then [ "$(git rev-parse "$tag^{commit}")" = "$c" ] || die "tag $tag exists locally on another commit"; else git tag "$tag" "$c"; fi
  git push -q origin "refs/tags/$tag" || die "pushing the tag failed"
  if gh release view "$tag" --repo "$slug" > /dev/null 2>&1; then
    note "release $tag exists (resuming): uploading the assets again"
    gh release upload "$tag" "$o/tomato-$v.tar.gz" "$o/tomato-$v.pkg" "$o/tomato-$v.dmg" "$o/latest.json" --clobber --repo "$slug" || die "gh release upload failed"
  else
    gh release create "$tag" "$o/tomato-$v.tar.gz" "$o/tomato-$v.pkg" "$o/tomato-$v.dmg" "$o/latest.json" --verify-tag --title "Tomato $v" --generate-notes --repo "$slug" || die "gh release create failed. Nothing is on the site yet; to undo a half-made release: gh release delete $tag --cleanup-tag -y --repo $slug"
  fi
  st_set published yes
  d="$(mktemp -d)"
  gh release download "$tag" --repo "$slug" --dir "$d" --pattern "tomato-$v.pkg" --pattern "tomato-$v.dmg" --pattern "tomato-$v.tar.gz" --pattern latest.json || die "cannot download the published assets"
  [ "$(shasum -a 256 "$d/tomato-$v.pkg" | cut -d' ' -f1)" = "$sum" ] || die "the PUBLISHED package's sha256 differs from $sum. The site is not updated (main is not pushed). Delete the release: gh release delete $tag --cleanup-tag -y --repo $slug"
  [ "$(shasum -a 256 "$d/tomato-$v.tar.gz" | cut -d' ' -f1)" = "$tsum" ] || die "the PUBLISHED tarball's sha256 differs from $tsum (main is not pushed)"
  [ "$(shasum -a 256 "$d/tomato-$v.dmg" | cut -d' ' -f1)" = "$dsum" ] || die "the PUBLISHED disk image's sha256 differs from $dsum (main is not pushed)"
  cmp -s "$d/latest.json" site/latest.json || die "the published latest.json differs from site/latest.json (main is not pushed)"
  url="$(sed -n 's/.*"pkg_url" *: *"\([^"]*\)".*/\1/p' site/latest.json)"
  curl -fsSL -o "$d/public.pkg" "$url" || die "cannot download $url"
  [ "$(shasum -a 256 "$d/public.pkg" | cut -d' ' -f1)" = "$sum" ] || die "$url serves a different file than the signed package"
  durl="$(sed -n 's/.*"dmg_url" *: *"\([^"]*\)".*/\1/p' site/latest.json)"
  curl -fsSL -o "$d/public.dmg" "$durl" || die "cannot download $durl"
  [ "$(shasum -a 256 "$d/public.dmg" | cut -d' ' -f1)" = "$dsum" ] || die "$durl serves a different file than the signed disk image"
  rm -rf "$d"; st_set release_url "https://github.com/$slug/releases/tag/$tag"
  note "published and verified: sha256 $sum, $url; disk image sha256 $dsum, $durl"
}

step_push() {
  banner push "the release commit to $branch"
  in_clone; c="$(st_get commit_sha)"
  if [ "$dry" = 1 ]; then say "DRY RUN: would push $(git rev-parse --short HEAD) to origin/$branch."; return 0; fi
  if [ "$no_push" = 1 ]; then say "--no-push: the release commit $(git rev-parse --short HEAD) stays unpushed in $clone on the signing Mac. Push it with: git -C $clone push origin HEAD:$branch"; st_set pushed no; return 0; fi
  git push origin "HEAD:refs/heads/$branch" || die "pushing $branch failed (someone pushed meanwhile?). The release is published; the commit is in $clone: fetch, rebase it, and push by hand: git -C $clone pull --no-rebase origin $branch && git -C $clone push origin HEAD:$branch (a merge, not a rebase: the published tag must stay an ancestor of main)"
  git fetch -q origin; [ "$(git rev-parse "origin/$branch")" = "$c" ] || die "origin/$branch is not the release commit after the push"
  st_set pushed yes; note "pushed $(git rev-parse --short HEAD) to origin/$branch"
}

step_summary() {
  in_clone; v="$(st_get version)"
  banner summary "Tomato $v$(if [ "$dry" = 1 ]; then echo ' (DRY RUN: nothing was published or pushed)'; fi)"
  say "version:        $v"
  say "tests:          $(st_get tests)"
  say "benchmarks:     $(st_get bench)   instruction counts: $(st_get counts)"
  if [ "$(st_get bench)" != skipped ] && [ -f benchmarks/results/results.md ]; then
    say ""; say "Tomato's time divided by each language's time (below 1.0 Tomato is faster, above 1.0 slower):"; ratio_table
    say ""
  fi
  say ""; say "LINUX x86-64 ($linux_host): $(st_get linux)"
  say "  tests: $(st_get linux_tests)$(if [ -n "$(st_get linux_load_warn)" ]; then echo "  [$(st_get linux_load_warn)]"; fi)"
  case "$(st_get linux_tests)" in FAILED*|"not run") say "  !! the Linux tests did not pass or did not run: read this before trusting the release" ;; esac
  if [ -f benchmarks/results/linux-x86_64/results.md ] && grep -q "\"tomato\": \"$v\"" benchmarks/results/linux-x86_64/results.json 2>/dev/null; then say "  Tomato's time divided by each language's (Linux; below 1.0 Tomato is faster):"; awk -F"|" '/^Tomato.s time divided by/ { t = 1; next } t && /^\| / { printf "  |%s|%s|%s|%s|\n", $2, $3, $4, $5; n++; next } t && n { exit }' benchmarks/results/linux-x86_64/results.md; fi
  say ""
  say "notarization:   $(st_get notarization)"
  say "package sha256: $(st_get pkg_sha256)"
  say "disk image sha256: $(st_get dmg_sha256)"
  say "tarball sha256: $(st_get tar_sha256)"
  if [ "$dry" = 1 ]; then say "release URL:    (not published: dry run)"; else say "release URL:    $(st_get release_url)"; fi
  say "release commit: $(st_get commit_sha) in $clone  (pushed: $(if [ "$dry" = 1 ]; then echo 'no, dry run'; else st_get pushed; fi))"
  say "elapsed:        $(( ($(date +%s) - $(st_get run_started)) / 60 )) minutes of wall time since the run began"
  st_set status finished
}

# ---------------------------------------------------------------- run the steps
if [ "$resume" = 1 ] || [ -n "$from" ]; then
  [ -f "$state" ] || die "no earlier run to resume (no $state)"
  [ "$(st_get status)" = finished ] && [ "$resume" = 1 ] && die "the last run finished; start a new one"
  [ "$(st_get mode)" = "$([ "$dry" = 1 ] && echo dry || echo real)" ] || die "the earlier run was a $(st_get mode) run; resume it with the same --dry-run setting (or use --restart)"
  if [ "$resume" = 1 ]; then
    start=""; for s in $STEPS; do case " $(st_get done) " in *" $s "*) ;; *) start="$s"; break ;; esac; done
    [ -n "$start" ] || start=summary
  else start="$from"; fi
  [ "$(st_get status)" = finished ] && st_set status running
  mode=resume
else
  if [ -f "$state" ] && [ "$(st_get status)" != finished ] && [ "$restart" = 0 ]; then
    die "an earlier release run (v$(st_get version), $(st_get mode), failed at '$(st_get failed_step)') is unfinished. Continue it with --resume (or --from STEP), or discard it with --restart."
  fi
  prev_status="$(st_get status)"; prev_mode="$(st_get mode)"   # what the last run left in the clone decides whether preflight may reset it
  rm -f "$state"; start=preflight; mode=fresh
  st_set status running; st_set run_started "$started"; st_set mode "$([ "$dry" = 1 ] && echo dry || echo real)"
  [ -z "$version" ] || st_set requested_version "$version"
fi
[ -n "$(st_get run_started)" ] || st_set run_started "$started"
# a version given on the command line wins; otherwise the state's
[ -n "$version" ] || version="$(st_get requested_version)"
say "release run: $(st_get mode), branch $branch, origin $origin, work dir $work_dir"
say "steps: $STEPS; starting at $start"
running=0
for s in $STEPS; do
  [ "$s" = "$start" ] && running=1
  if [ "$s" = preflight ] && [ "$mode" = resume ]; then running=1; fi
  [ "$running" = 1 ] || continue
  cur_step="$s"
  if [ "$s" = preflight ]; then ( set -e; step_preflight "$mode" ); else ( set -e; "step_$s" ); fi
  rc=$?
  if [ $rc -ne 0 ]; then
    st_set failed_step "$s"
    printf '\nFAILED at step %s. Fix the cause, then continue with:\n  %s --resume\n(or --from STEP; --restart throws the run away)\n' "$s" "${invoked:-release/release.sh}" >&2
    printf 'Logs are in %s on the signing Mac.\n' "$logs" >&2
    exit 1
  fi
  case " $(st_get done) " in *" $s "*) ;; *) st_set done "$(st_get done) $s" ;; esac
  # a resumed run starts at its own step; preflight itself is not a "next" step then
  [ "$s" = preflight ] && [ "$mode" = resume ] && [ "$start" != preflight ] && running=0
done
exit 0
