#!/bin/sh
# Sandbox tests of release/release.sh: what happens when a run fails and is resumed (--resume, --from, --restart).
# Usage: tests/release_resume.sh WORKDIR     (tests/run.sh calls it; it prints "ok NAME" or "FAIL NAME" and the reason, one per line)
#
# Nothing real is touched. The "GitHub" origin is a bare repository in WORKDIR (git's url.insteadOf maps git@github.com:sirbuffalo/tomato.git
# to it, ssh is replaced by a program that fails), the repository holds fake tests/build/sign scripts, and a folder of stand-ins for gh, curl,
# codesign, pkgutil, xcrun and the other Mac tools comes first on the PATH of the script (TOMATO_RELEASE_TEST_BIN). Failures are injected by
# creating files in $FAKE/inject (fail-tests, fail-build, fail-sign, fail-dmg, bad-notarization, gh-logged-out, fail-gh-create,
# fail-gh-create-partial, fail-gh-download, reject-main, bad-hardening). A file named `signal` (or `signal-codesign`) holding INT, TERM or HUP makes
# the gh download (codesign) stand-in send that signal to the release script (to sign-pkg.sh) and its step, like Ctrl-C or a kill: the interrupt tests. No network, no signing, no notarization, nothing published.
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
W="$1"; [ -n "$W" ] || { echo "usage: $0 WORKDIR" >&2; exit 2; }
mkdir -p "$W"; W="$(cd "$W" && pwd)"
real_path="$PATH"
# A shell cannot trap a signal that was ignored when it started (nohup, a runner that ignores SIGHUP, a job started with `trap '' HUP`), and
# then the release script correctly ignores the hangup too: the interrupt (HUP) tests would see the run finish or fail instead of status 129.
# So the runs get a default SIGHUP disposition (perl resets it and execs); without perl, and with SIGHUP ignored, those checks are said to be skipped.
hup_default=""
if command -v perl > /dev/null 2>&1; then hup_default='perl -e $SIG{HUP}="DEFAULT";exec@ARGV'; fi
hup_ignored=0
if [ -z "$hup_default" ] && [ "$(sh -c 'kill -HUP $$; echo alive' 2> /dev/null)" = alive ]; then hup_ignored=1; fi   # (a shell that survives its own SIGHUP had it ignored)
fails=0
oks=0
pass() { oks=$((oks + 1)); echo "ok   $1"; }
fail() { fails=$((fails + 1)); echo "FAIL $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/     /'; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2
actual:   $3"; fi; }
ne() { if [ "$2" != "$3" ]; then pass "$1"; else fail "$1" "both were: $2"; fi; }
sha() { if command -v shasum > /dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }

# ---------------------------------------------------------------- the stand-ins
bin="$W/bin"; mkdir -p "$bin"
mkstub() { cat > "$bin/$1"; chmod +x "$bin/$1"; }
# the real tools the stand-ins fall back to
realtool() { PATH="$real_path" command -v "$1"; }
mkstub uname <<'EOF'
#!/bin/sh
[ $# = 0 ] && { echo Darwin; exit 0; }
exec "$(PATH="$TOMATO_TEST_REAL_PATH" command -v uname)" "$@"
EOF
mkstub sw_vers <<'EOF'
#!/bin/sh
case "$1" in -productName) echo macOS ;; *) echo 14.0 ;; esac
EOF
for t in clang lipo productbuild hdiutil codesign-unused; do printf '#!/bin/sh\necho "fake %s"\n' "$t" > "$bin/$t"; chmod +x "$bin/$t"; done
mkstub security <<'EOF'
#!/bin/sh
echo '  1) AAAA "Developer ID Application: Davis McDowell (39BK8TGQ26)"'
echo '  2) BBBB "Developer ID Installer: Davis McDowell (39BK8TGQ26)"'
EOF
mkstub codesign <<'EOF'
#!/bin/sh
echo "codesign $*" >> "$FAKE/calls.log"
[ -f "$FAKE/inject/signal-codesign" ] && kill -"$(cat "$FAKE/inject/signal-codesign")" "$PPID"   # (the script that runs us; we exit, so its trap runs then)
case "$*" in
  *-dv*) [ -e "$FAKE/inject/bad-hardening" ] || echo "flags=0x10000(runtime)" >&2; echo "Authority=Developer ID Application: Davis McDowell (39BK8TGQ26)" >&2 ;;
esac
exit 0
EOF
mkstub productsign <<'EOF'
#!/bin/sh
for a; do last="$a"; done; : > "$last"
EOF
mkstub pkgbuild <<'EOF'
#!/bin/sh
for a; do last="$a"; done; : > "$last"
EOF
mkstub xcrun <<'EOF'
#!/bin/sh
exit 0
EOF
mkstub spctl <<'EOF'
#!/bin/sh
exit 0
EOF
mkstub ssh <<'EOF'
#!/bin/sh
echo "ssh is not allowed in the release sandbox: $*" >&2; exit 255
EOF
mkstub pkgutil <<'EOF'
#!/bin/sh
case "$1" in
  --check-signature)
    echo "   Status: signed by a developer certificate issued by Apple for distribution"
    [ -e "$FAKE/inject/bad-notarization" ] || echo "   Notarization: trusted by the Apple notary service"
    echo "   Certificate Chain:"; echo "    1. Developer ID Installer: Davis McDowell (39BK8TGQ26)" ;;
  --expand-full)
    v="$(sed -n 's/^version=//p' "$2" | head -1)"; x="$3"
    mkdir -p "$x/component.pkg/Scripts" "$x/component.pkg/Payload/usr/local/bin" "$x/component.pkg/Payload/usr/local/lib/tomato/native/bin"
    printf '#!/bin/sh\n' > "$x/component.pkg/Scripts/preinstall"; cp "$x/component.pkg/Scripts/preinstall" "$x/component.pkg/Scripts/postinstall"
    chmod +x "$x/component.pkg/Scripts/preinstall" "$x/component.pkg/Scripts/postinstall"
    ln -s ../lib/tomato/native/bin/tomato "$x/component.pkg/Payload/usr/local/bin/tomato"
    printf '#!/bin/sh\necho "Tomato v%s (compiler written in Tomato)"\n' "$v" > "$x/component.pkg/Payload/usr/local/lib/tomato/native/bin/tomato"
    chmod +x "$x/component.pkg/Payload/usr/local/lib/tomato/native/bin/tomato"
    printf '<pkg-ref id="com.davismcd.tomato" version="%s">component.pkg</pkg-ref>\n' "$v" > "$x/Distribution" ;;
esac
EOF
mkstub file <<'EOF'
#!/bin/sh
for f; do case "$f" in */bin/tomato) echo "$f: Mach-O 64-bit executable arm64" ;; *) echo "$f: data" ;; esac; done
EOF
mkstub curl <<'EOF'
#!/bin/sh
# curl -fsSL -o OUT URL: the file of that name in the fake release of the tag in the URL
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
echo "curl $url" >> "$FAKE/calls.log"
tag="$(printf %s "$url" | sed -n 's#.*/download/\([^/]*\)/.*#\1#p')"
src="$FAKE/releases/$tag/$(basename "$url")"
[ -f "$src" ] || { echo "curl: (22) not found: $url" >&2; exit 22; }
cp "$src" "$out"
EOF
mkstub gh <<'EOF'
#!/bin/sh
: "${FAKE:?}"
echo "gh $*" >> "$FAKE/calls.log"
inj() { [ -e "$FAKE/inject/$1" ]; }
case "$1 $2" in
  "auth status") inj gh-logged-out && { echo "You are not logged into any GitHub hosts" >&2; exit 1; }; exit 0 ;;
  "repo view") echo ADMIN ;;
  "api user") echo testuser ;;
  "release view")
    [ -d "$FAKE/releases/$3" ] && exit 0
    echo "release not found" >&2; exit 1 ;;
  "release create"|"release upload")
    verb="$2"; tag="$3"; shift 3; files=""
    for a; do [ -f "$a" ] && files="$files $a"; done
    d="$FAKE/releases/$tag"
    if [ "$verb" = create ]; then
      inj fail-gh-create && { echo "HTTP 502 from GitHub" >&2; exit 1; }
      git --git-dir="$BARE" rev-parse -q --verify "refs/tags/$tag" > /dev/null || { echo "tag $tag is not on the remote (--verify-tag)" >&2; exit 1; }
      mkdir -p "$d"
      if inj fail-gh-create-partial; then set -- $files; cp "$1" "$d/"; echo "HTTP 502 from GitHub after the first asset" >&2; exit 1; fi
    else [ -d "$d" ] || { echo "release not found" >&2; exit 1; }; fi
    for f in $files; do cp "$f" "$d/"; done ;;
  "release download")
    tag="$3"; shift 3; dir=""; pats=""
    while [ $# -gt 0 ]; do case "$1" in --dir) dir="$2"; shift 2 ;; --pattern) pats="$pats $2"; shift 2 ;; *) shift ;; esac; done
    inj fail-gh-download && { echo "network error" >&2; exit 1; }
    if [ -f "$FAKE/inject/signal" ]; then   # an interrupt: the release script, its step (our parent) and this stand-in all get the signal, as from Ctrl-C
      step=$PPID; main="$(ps -o ppid= -p "$step" | tr -d ' ')"; kill -"$(cat "$FAKE/inject/signal")" "$main" "$step" $$; sleep 5; exit 1
    fi
    for p in $pats; do cp "$FAKE/releases/$tag/$p" "$dir/" || exit 1; done ;;
  *) echo "gh stub: unexpected: $*" >&2; exit 99 ;;
esac
EOF
if ! PATH="$real_path" command -v shasum > /dev/null 2>&1; then   # (Linux without perl's shasum)
  mkstub shasum <<'EOF'
#!/bin/sh
[ "$1" = -a ] && shift 2
exec sha256sum "$@"
EOF
fi

# ---------------------------------------------------------------- the repository that is "released"
tmpl="$W/template"; rm -rf "$tmpl"; mkdir -p "$tmpl/seed"
(
  cd "$tmpl/seed" || exit 1
  export HOME="$tmpl" GIT_CONFIG_GLOBAL="$tmpl/gitconfig" GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$GIT_CONFIG_GLOBAL"
  git init -q . && git symbolic-ref HEAD refs/heads/main
  mkdir -p std site/wasm/std release tests benchmarks/results docs
  echo 1.0.0 > VERSION
  printf 'def version():\n    return '"'"'1.0.0'"'"'\n' > std/sys.tom
  # (the real std/sys.tom has "    return '0.51'" with four spaces; the script's sed and its check both want that shape)
  cp std/sys.tom site/wasm/std/sys.tom
  echo 'window.TOMATO_VERSION = "1.0.0";' > site/config.js
  printf '{\n  "version": "1.0.0"\n}\n' > site/latest.json
  echo "# performance" > docs/performance.md; echo x > benchmarks/results/results.md
  printf 'release/out/\n' > .gitignore
  cat > tests/run.sh <<'EOF'
#!/bin/sh
echo "tests HEAD=$(git rev-parse HEAD) VERSION=$(cat VERSION)" >> "$FAKE/calls.log"
[ -e "$FAKE/inject/fail-tests" ] && { echo "FAIL fake test"; echo "1 passed, 1 failed"; exit 1; }
echo "ok   fake test"; echo "10 passed, 0 failed"
EOF
  cat > release/build.sh <<'EOF'
#!/bin/sh
set -e
echo build >> "$FAKE/calls.log"
[ -e "$FAKE/inject/fail-build" ] && { echo "build failed" >&2; exit 1; }
v="$(cat VERSION)"; n=$(( $(cat "$FAKE/counter" 2>/dev/null || echo 0) + 1 )); echo $n > "$FAKE/counter"
out=release/out; rm -rf "$out"; mkdir -p "$out"
printf 'tarball %s build %s\n' "$v" "$n" > "$out/tomato-$v.tar.gz"
sum="$(shasum -a 256 "$out/tomato-$v.tar.gz" | cut -d' ' -f1)"
printf '{\n  "version": "%s",\n  "url": "https://github.com/sirbuffalo/tomato/releases/download/v%s/tomato-%s.tar.gz",\n  "sha256": "%s"\n}\n' "$v" "$v" "$v" "$sum" > "$out/latest.json"
EOF
  cat > release/pkg.sh <<'EOF'
#!/bin/sh
set -e
v="$(cat VERSION)"; out=release/out; n="$(cat "$FAKE/counter")"
printf 'version=%s\nunsigned build %s\n' "$v" "$n" > "$out/tomato-$v.pkg"
psum="$(shasum -a 256 "$out/tomato-$v.pkg" | cut -d' ' -f1)"; purl="$(sed -n 's/.*"url" *: *"\([^"]*\)\.tar\.gz".*/\1/p' "$out/latest.json").pkg"
grep -v '"pkg_' "$out/latest.json" | sed '$d' | sed '$s/$/,/' > "$out/l.tmp"
printf '  "pkg_url": "%s",\n  "pkg_sha256": "%s"\n}\n' "$purl" "$psum" >> "$out/l.tmp"; mv "$out/l.tmp" "$out/latest.json"
EOF
  cat > release/sign-pkg.sh <<'EOF'
#!/bin/sh
set -e
echo "sign-pkg $1" >> "$FAKE/calls.log"
[ -e "$FAKE/inject/fail-sign" ] && { echo "notarization rejected" >&2; exit 1; }
grep -q '^signed$' "$1" && { echo "error: $1 is signed already" >&2; exit 1; }
{ cat "$1"; echo signed; } > "$2"
echo "notarized (submission fake-1)"
sum="$(shasum -a 256 "$2" | cut -d' ' -f1)"
sed "s/\"pkg_sha256\": *\"[0-9a-f]*\"/\"pkg_sha256\": \"$sum\"/" "$TOMATO_LATEST_JSON" > "$TOMATO_LATEST_JSON.tmp" && mv "$TOMATO_LATEST_JSON.tmp" "$TOMATO_LATEST_JSON"
EOF
  cat > release/dmg.sh <<'EOF'
#!/bin/sh
set -e
echo "dmg $1" >> "$FAKE/calls.log"
[ -e "$FAKE/inject/fail-dmg" ] && { echo "dmg failed" >&2; exit 1; }
printf 'dmg of %s\n' "$(shasum -a 256 "$1" | cut -d' ' -f1)" > "$2"
sum="$(shasum -a 256 "$2" | cut -d' ' -f1)"
durl="$(sed -n 's/.*"url" *: *"\([^"]*\)\.tar\.gz".*/\1/p' "$TOMATO_LATEST_JSON").dmg"
grep -v '"dmg_' "$TOMATO_LATEST_JSON" | sed '$d' | sed '$s/,*$/,/' > "$2.json"
printf '  "dmg_url": "%s",\n  "dmg_sha256": "%s"\n}\n' "$durl" "$sum" >> "$2.json"; mv "$2.json" "$TOMATO_LATEST_JSON"
echo "notarized dmg (submission fake-2)"
EOF
  cat > site/build.sh <<'EOF'
#!/bin/sh
set -e
v="$(cat VERSION)"
case "$v" in
  *-*) cp release/out/latest.json site/latest-pre.json ;;
  *) cp release/out/latest.json site/latest.json; sed "s/window.TOMATO_VERSION = \".*\"/window.TOMATO_VERSION = \"$v\"/" site/config.js > site/config.js.new && mv site/config.js.new site/config.js ;;
esac
EOF
  git add -A && git commit -q -m "fake tomato 1.0.0"
  git init -q --bare "$tmpl/bare.git" && git --git-dir="$tmpl/bare.git" symbolic-ref HEAD refs/heads/main
  git push -q "$tmpl/bare.git" main
  git --git-dir="$tmpl/bare.git" tag v1.0.0 main   # 1.0.0 is released: the next version is 1.0.1
) || { echo "FAIL release sandbox: cannot build the fake repository"; exit 1; }
cat > "$tmpl/bare.git/hooks/pre-receive" <<'EOF'
#!/bin/sh
while read old new ref; do
  if [ "$ref" = refs/heads/main ] && [ -e "$FAKE/inject/reject-main" ]; then echo "main is protected (test)" >&2; exit 1; fi
done
exit 0
EOF
chmod +x "$tmpl/bare.git/hooks/pre-receive"
mkdir -p "$tmpl/wasi/bin" "$tmpl/wasi/share/wasi-sysroot"; printf '#!/bin/sh\necho fake wasi clang\n' > "$tmpl/wasi/bin/clang"; chmod +x "$tmpl/wasi/bin/clang"
mkdir -p "$W/script"; cp "$root/release/release.sh" "$W/script/release.sh"   # no release.conf next to this copy

# ---------------------------------------------------------------- one sandbox per scenario
SB=""
sandbox() { # NAME: a fresh bare "GitHub", fake folder and signing-Mac work dir; selects it for rel
  SB="$W/s.$1"; rm -rf "$SB"; mkdir -p "$SB/fake/inject" "$SB/fake/releases/v1.0.0"
  cp -R "$tmpl/bare.git" "$SB/bare.git"; cp -R "$tmpl/wasi" "$SB/wasi"; : > "$SB/fake/calls.log"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$SB/gitconfig"
  run_n=0
}
inject() { : > "$SB/fake/inject/$1"; }
clear_inject() { rm -f "$SB/fake/inject/$1"; }
rel() { # ARGS: a run of release.sh in the sandbox; the output is in $SB/out, the status is $rc
  run_n=$((run_n + 1))
  mkdir -p "$SB/tmp"
  ( cd "$SB" && env -u TOMATO_RELEASE_HOST -u WASI_SDK TMPDIR="$SB/tmp" TOMATO_RELEASE_TEST_BIN="$bin" TOMATO_TEST_REAL_PATH="$real_path" FAKE="$SB/fake" BARE="$SB/bare.git" \
      HOME="$SB" GIT_CONFIG_GLOBAL="$SB/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_SSH_COMMAND=false GIT_TERMINAL_PROMPT=0 \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$SB/bare.git.insteadOf" GIT_CONFIG_VALUE_0="git@github.com:sirbuffalo/tomato.git" \
      $hup_default sh "$W/script/release.sh" --work-dir "$SB/work" --wasi-sdk "$SB/wasi" --no-load-check --skip-bench --no-linux "$@" > "$SB/out.$run_n" 2>&1 < /dev/null )
  rc=$?; cp "$SB/out.$run_n" "$SB/out"
}
real() { rel --ignore-linux-failures "$@"; }   # a real run (it can only reach the sandbox's bare repository and gh stand-in)
stget() { sed -n "s/^$1=//p" "$SB/work/state" | tail -1; }
done_steps() { stget done | sed 's/^ *//'; }
cl() { git -C "$SB/work/tomato" "$@"; }
bare() { git --git-dir="$SB/bare.git" "$@"; }
calls() { grep -c "$1" "$SB/fake/calls.log"; }
has() { grep -q "$1" "$SB/out"; }
nofiles() { ls -A "$1" 2> /dev/null | tr '\n' ' '; }   # what is left in a folder (a run's TMPDIR: it must be empty again)
base_main="$(git --git-dir="$tmpl/bare.git" rev-parse main)"

# ---------------------------------------------------------------- 1. a dry run publishes and pushes nothing
sandbox dry
rel --dry-run; eq "dry run: finishes" 0 "$rc"
eq "dry run: every step is recorded as done" "preflight version test bump linux bench snapshot build sign commit publish push summary" "$(done_steps)"
eq "dry run: origin has no new tag" "v1.0.0" "$(bare tag)"
eq "dry run: origin's main is untouched" "$base_main" "$(bare rev-parse main)"
eq "dry run: gh made no release and uploaded nothing" 0 "$(calls 'gh release \(create\|upload\)')"
ne "dry run: the release commit exists in the clone" "$base_main" "$(cl rev-parse HEAD)"
eq "dry run: the commit is the one recorded" "$(stget commit_sha)" "$(cl rev-parse HEAD)"

# ---------------------------------------------------------------- 2. a real run: the tested commit is the tagged commit's parent
sandbox real
real; eq "real run: finishes" 0 "$rc"
c="$(stget commit_sha)"
eq "real run: the tag is the release commit" "$c" "$(bare rev-parse 'v1.0.1^{commit}')"
eq "real run: main is the release commit" "$c" "$(bare rev-parse main)"
eq "real run: the tests ran on the commit the release commit is built on, before the bump" "tests HEAD=$(bare rev-parse "$c^") VERSION=1.0.0" "$(grep '^tests' "$SB/fake/calls.log")"
eq "real run: one GitHub release with the four assets" "latest.json tomato-1.0.1.dmg tomato-1.0.1.pkg tomato-1.0.1.tar.gz" "$(ls "$SB/fake/releases/v1.0.1" | tr '\n' ' ' | sed 's/ $//')"
eq "real run: VERSION and sys.version say 1.0.1" "1.0.1 1.0.1" "$(bare show main:VERSION) $(bare show main:std/sys.tom | sed -n "s/.*return '\(.*\)'/\1/p")"
# a finished run: --resume refuses; the steps before publish cannot be redone; the later ones are safe to repeat
rel --resume; ne "finished run: --resume refuses" 0 "$rc"
rel --from build; ne "after the tag: --from build is refused" 0 "$rc"; has 'tagged and pushed' && pass "after the tag: the message says why" || fail "after the tag: the message says why" "$(cat "$SB/out")"
rel --from commit; ne "after the tag: --from commit is refused" 0 "$rc"; has 'tagged and pushed' && pass "after the tag: ... for the same reason" || fail "after the tag: ... for the same reason" "$(cat "$SB/out")"
rel --ignore-linux-failures --from push; eq "after the tag: --from push finds the commit already on main" 0 "$rc"
has 'already on origin' && pass "after the tag: push says nothing is left to push" || fail "after the tag: push says nothing is left to push" "$(cat "$SB/out")"
rel --ignore-linux-failures --from publish; eq "after the tag: --from publish repeats safely" 0 "$rc"
eq "after the tag: still one release created" 1 "$(calls 'gh release create')"
eq "after the tag: the tag did not move" "$c" "$(bare rev-parse 'v1.0.1^{commit}')"

# ---------------------------------------------------------------- 3. --from never skips, and goes back properly
sandbox from
inject fail-build
rel --dry-run; ne "from: a build failure stops the run" 0 "$rc"; eq "from: it failed at build" build "$(stget failed_step)"
rel --dry-run --from sign; ne "from: --from sign is refused while build and linux... are not done" 0 "$rc"
has 'did not finish' && pass "from: the refusal names the unfinished steps" || fail "from: the refusal names the unfinished steps" "$(cat "$SB/out")"
eq "from: the refusal changed nothing" "preflight version test bump linux bench snapshot" "$(done_steps)"
clear_inject fail-build
rel --dry-run --resume; eq "from: --resume carries on at build" 0 "$rc"
eq "from: the tests were not run again" 1 "$(calls '^tests')"
eq "from: one release commit" 1 "$(cl rev-list --count "$(stget base_sha)..HEAD")"
# going back: the release commit is taken off, the later steps count as not done, a failure there resumes there
inject fail-dmg
rel --dry-run --from sign; ne "from: going back to sign (the disk image fails)" 0 "$rc"
eq "from: the steps from sign on are not done" "preflight version test bump linux bench snapshot build" "$(done_steps)"
eq "from: the release commit was taken off" "" "$(stget commit_sha)"
eq "from: HEAD is back on the start commit" "$(stget base_sha)" "$(cl rev-parse HEAD)"
clear_inject fail-dmg
n="$(calls '^build')"
rel --dry-run --resume; eq "from: --resume goes on at sign" 0 "$rc"
eq "from: ... without building again" "$n" "$(calls '^build')"
eq "from: ... and without signing the signed package a second time" 1 "$(calls '^sign-pkg')"
eq "from: ... and ends with one release commit" 1 "$(cl rev-list --count "$(stget base_sha)..HEAD")"
eq "from: ... that is the recorded one" "$(stget commit_sha)" "$(cl rev-parse HEAD)"
# back to the start of the tests: the clone is reset to the start commit (the bump is undone), and everything runs again
rel --dry-run --from test; eq "from: --from test runs on" 0 "$rc"
eq "from: the tests ran again, on the start commit and an unbumped tree" "tests HEAD=$(stget base_sha) VERSION=1.0.0" "$(grep '^tests' "$SB/fake/calls.log" | tail -1)"
eq "from: ... that makes two runs of the tests" 2 "$(calls '^tests')"
eq "from: still one release commit" 1 "$(cl rev-list --count "$(stget base_sha)..HEAD")"
rel --dry-run --from nosuchstep; eq "from: an unknown step is refused" 2 "$rc"
rel --from test; ne "from: a real run cannot resume a dry run" 0 "$rc"; has 'earlier run was a dry run' && pass "from: ... and the message says it was a dry run" || fail "from: ... and the message says it was a dry run" "$(cat "$SB/out")"

# ---------------------------------------------------------------- 4. push: exactly the recorded commit, from a verified tree
sandbox push
inject reject-main
real; ne "push: a rejected push of main stops the run" 0 "$rc"; eq "push: it failed at push" push "$(stget failed_step)"
c="$(stget commit_sha)"
eq "push: the tag and the release exist; main does not have the commit yet" "$c / $base_main" "$(bare rev-parse 'v1.0.1^{commit}') / $(bare rev-parse main)"
clear_inject reject-main
cl commit -q --allow-empty -m "something else, made by hand"
real --resume; eq "push: a resume pushes the recorded release commit, not HEAD" 0 "$rc"
eq "push: main is the release commit" "$c" "$(bare rev-parse main)"
ne "push: ... and HEAD is something else" "$c" "$(cl rev-parse HEAD)"
sandbox pushdirty
inject reject-main
real; ne "push (dirty): the rejected push stops the run" 0 "$rc"
clear_inject reject-main
echo hand-edit >> "$SB/work/tomato/VERSION"
real --resume; ne "push (dirty): a clone changed after the commit is refused" 0 "$rc"; has 'uncommitted changes' && pass "push (dirty): ... for the uncommitted change" || fail "push (dirty): ... for the uncommitted change" "$(tail -5 "$SB/out")"; eq "push (dirty): main is untouched" "$base_main" "$(bare rev-parse main)"
cl checkout -q -- VERSION
cl reset -q --hard "$(stget base_sha)"
real --resume; ne "push (moved): a clone that no longer has the release commit is refused" 0 "$rc"; has 'release commit of this run is' && pass "push (moved): ... because the release commit is missing" || fail "push (moved): ... because the release commit is missing" "$(tail -5 "$SB/out")"; eq "push (moved): main is untouched" "$base_main" "$(bare rev-parse main)"
sandbox pushed
inject reject-main
real; ne "push (by hand): the rejected push stops the run" 0 "$rc"
c="$(stget commit_sha)"; clear_inject reject-main
bare update-ref refs/heads/main "$c"   # somebody pushed it for us
real --resume; eq "push (by hand): a resume finds the commit on main and finishes" 0 "$rc"; eq "push (by hand): recorded as pushed" yes "$(stget pushed)"

# ---------------------------------------------------------------- 5. publish: nothing twice, nothing different
sandbox pubfail
inject fail-gh-create
real; ne "publish: a failed gh release create stops the run" 0 "$rc"; eq "publish: ... at publish" publish "$(stget failed_step)"
c="$(stget commit_sha)"
eq "publish: the tag is on origin (the release needs it)" "$c" "$(bare rev-parse 'v1.0.1^{commit}')"
eq "publish: main is not pushed" "$base_main" "$(bare rev-parse main)"
clear_inject fail-gh-create
real --resume; eq "publish: the resume creates the release and finishes" 0 "$rc"
eq "publish: ... two create calls, the failed one and the one that worked" 2 "$(calls '^gh release create')"
sandbox pubpartial
inject fail-gh-create-partial
real; ne "publish: a release created with one asset stops the run" 0 "$rc"
clear_inject fail-gh-create-partial
real --resume; eq "publish: the resume uploads the rest into that release" 0 "$rc"
eq "publish: ... all four assets are there" 4 "$(ls "$SB/fake/releases/v1.0.1" | wc -l | tr -d ' ')"
eq "publish: ... no second release was created" 1 "$(grep -c '^gh release create' "$SB/fake/calls.log")"
sandbox pubverify
inject fail-gh-download
real; ne "publish: a verification that cannot download stops the run" 0 "$rc"
eq "publish: ... main is not pushed" "$base_main" "$(bare rev-parse main)"
eq "publish: ... and the download folder is gone (the run's temp folder is empty)" "" "$(nofiles "$SB/tmp")"
clear_inject fail-gh-download
real --resume; eq "publish: the resume verifies again and finishes" 0 "$rc"
eq "publish: ... without a second release" 1 "$(grep -c '^gh release create' "$SB/fake/calls.log")"
# the Linux gate stops a real run after the commit, before anything is tagged; what is then resumed must be what was signed
sandbox gate
rel; ne "gate: a real run without a passing Linux run stops at publish" 0 "$rc"; eq "gate: ... at publish" publish "$(stget failed_step)"
eq "gate: no new tag" "v1.0.0" "$(bare tag)"
printf 'tampered\n' >> "$SB/work/tomato/release/out/tomato-1.0.1.pkg"
rel --ignore-linux-failures --resume; ne "gate: a changed package is not published" 0 "$rc"; has 'not the package that was signed' && pass "gate: the message says why" || fail "gate: the message says why" "$(cat "$SB/out")"
eq "gate: still no tag, no release" "0" "$(calls 'gh release create')"
sandbox tagelsewhere
rel; ne "tag: gate stop" 0 "$rc"
bare tag v1.0.1 "$base_main"   # the tag appeared on origin on another commit meanwhile
rel --ignore-linux-failures --resume; ne "tag: a tag on origin that is not the release commit stops the publish" 0 "$rc"
eq "tag: no release was created" 0 "$(calls 'gh release create')"
eq "tag: origin's tag stayed" "$base_main" "$(bare rev-parse 'v1.0.1^{commit}')"
sandbox taglocal
rel; ne "tag (local): gate stop" 0 "$rc"
cl tag v1.0.1 "$(stget base_sha)"
rel --ignore-linux-failures --resume; ne "tag (local): a local tag on another commit stops the publish" 0 "$rc"; eq "tag (local): origin has no new tag" "v1.0.0" "$(bare tag)"

# ---------------------------------------------------------------- 6. a dirty clone after a failed preflight
sandbox dirty
rel --dry-run; eq "dirty: a dry run leaves the clone with a release commit" 0 "$rc"
inject gh-logged-out
rel --dry-run; ne "dirty: the next run's preflight fails (gh logged out)" 0 "$rc"
eq "dirty: ... before the clone was synced" "" "$(stget base_sha)"
clear_inject gh-logged-out
rel --dry-run --resume; eq "dirty: --resume resets the clone and goes on" 0 "$rc"
eq "dirty: ... ending with one release commit on a clean tree" "1 " "$(cl rev-list --count "$(stget base_sha)..HEAD") $(cl status --porcelain)"
sandbox dirtyreal
real --no-push; eq "dirty (unpushed): a real run with --no-push leaves its commit in the clone" 0 "$rc"
c="$(stget commit_sha)"
inject gh-logged-out
real --no-push; ne "dirty (unpushed): the next preflight fails" 0 "$rc"
clear_inject gh-logged-out
real --no-push --resume; ne "dirty (unpushed): --resume does not throw the unpushed release commit away" 0 "$rc"
eq "dirty (unpushed): ... the commit is still there" "$c" "$(cl rev-parse "$c^{commit}")"
real --no-push --restart; ne "dirty (unpushed): --restart does reset, then the tag exists and the run stops" 0 "$rc"
has 'tag v1.0.1 already exists\|already has a release' && pass "dirty (unpushed): ... a published version cannot be released again" || fail "dirty (unpushed): ... a published version cannot be released again" "$(tail -5 "$SB/out")"

# ---------------------------------------------------------------- 7. signing: a failed check never leaves a signed package to be signed again
sandbox sign
inject bad-notarization
rel --dry-run; ne "sign: a package that does not check out stops the run" 0 "$rc"; eq "sign: ... at sign" sign "$(stget failed_step)"
clear_inject bad-notarization
rel --dry-run --resume; eq "sign: the resume signs the built package again (never a signed one)" 0 "$rc"
sandbox dmg
inject fail-dmg
rel --dry-run; ne "sign: a failing disk image stops the run" 0 "$rc"
clear_inject fail-dmg
rel --dry-run --resume; eq "sign: the resume finishes" 0 "$rc"
eq "sign: ... without signing the package a second time" 1 "$(calls '^sign-pkg')"
has 'only the disk image is redone' && pass "sign: ... and says so" || fail "sign: ... and says so" "$(tail -8 "$SB/out")"

# a package check that fails after it expanded the package leaves no copy of it behind
sandbox checkleak
inject bad-hardening
rel --dry-run; ne "sign: a Mach-O file that is not hardened stops the run" 0 "$rc"; eq "sign: ... at sign" sign "$(stget failed_step)"
has 'hardened runtime' && pass "sign: ... and the message says so" || fail "sign: ... and the message says so" "$(tail -5 "$SB/out")"
eq "sign: ... and the expanded package is gone (the run's temp folder is empty)" "" "$(nofiles "$SB/tmp")"

# ---------------------------------------------------------------- 8. an interrupt: temp folders removed, the step is the failed one, --resume continues there
for sig in TERM HUP; do
  case $sig in TERM) code=143 ;; HUP) code=129 ;; esac
  if [ "$sig" = HUP ] && [ "$hup_ignored" = 1 ]; then oks=$((oks + 10)); echo "ok   interrupt (HUP): skipped, SIGHUP is ignored here and there is no perl to reset it (counts as its 10 checks)"; continue; fi
  sandbox "int$sig"
  printf '%s' "$sig" > "$SB/fake/inject/signal"
  real; eq "interrupt ($sig): the run stops with status $code" "$code" "$rc"
  has "interrupted ($sig) during step publish" && pass "interrupt ($sig): the message names the step" || fail "interrupt ($sig): the message names the step" "$(tail -5 "$SB/out")"
  eq "interrupt ($sig): the failed step is publish, the run is still unfinished" "publish running" "$(stget failed_step) $(stget status)"
  eq "interrupt ($sig): publish is not recorded as done" "preflight version test bump linux bench snapshot build sign commit" "$(done_steps)"
  eq "interrupt ($sig): no temp folder is left" "" "$(nofiles "$SB/tmp")"
  rel --resume; ne "interrupt ($sig): without --restart a new run is not started over it" 0 "$rc"
  real; has 'unfinished' && pass "interrupt ($sig): a fresh run points at --resume" || fail "interrupt ($sig): a fresh run points at --resume" "$(tail -5 "$SB/out")"
  clear_inject signal
  real --resume; eq "interrupt ($sig): --resume finishes the release" 0 "$rc"
  c="$(stget commit_sha)"
  eq "interrupt ($sig): ... one release, the tag and main on the release commit" "1 $c $c" "$(grep -c '^gh release create' "$SB/fake/calls.log") $(bare rev-parse 'v1.0.1^{commit}') $(bare rev-parse main)"
  eq "interrupt ($sig): ... and nothing left in the temp folder" "" "$(nofiles "$SB/tmp")"
done
# the same in sign-pkg.sh (stand-ins for the Mac tools; the signing tool is stopped by the signal): the expanded package is removed
sandbox signpkg; mkdir -p "$SB/tmp"
printf 'version=1.0.1\nunsigned\n' > "$SB/in.pkg"; printf TERM > "$SB/fake/inject/signal-codesign"
( cd "$SB" && env PATH="$bin:$real_path" TOMATO_TEST_REAL_PATH="$real_path" FAKE="$SB/fake" TMPDIR="$SB/tmp" sh "$root/release/sign-pkg.sh" in.pkg out.pkg > "$SB/out" 2>&1 < /dev/null ); rc=$?
eq "sign-pkg: a TERM while it signs ends it with status 143" 143 "$rc"
eq "sign-pkg: it had reached codesign, and made no package" "1 " "$(calls '^codesign --force') $(ls "$SB/out.pkg" 2> /dev/null)"
eq "sign-pkg: the expanded package is removed" "" "$(nofiles "$SB/tmp")"

# ---------------------------------------------------------------- 9. what must never happen in a dry run
sandbox drynever
rel --dry-run --from test 2>/dev/null; ne "dry: --from without an earlier run is refused" 0 "$rc"
rel --dry-run; eq "dry: finishes" 0 "$rc"
for s in publish push; do rel --dry-run --from $s; eq "dry: --from $s still publishes and pushes nothing (status)" 0 "$rc"; done
eq "dry: no new tag, main untouched, no release, ever" "v1.0.0|$base_main|0" "$(bare tag)|$(bare rev-parse main)|$(calls 'gh release \(create\|upload\)')"

# a skipped section would show here: the number of ok lines is fixed (raise it when a check is added)
[ "$oks" = 141 ] || { echo "FAIL the number of ok lines: expected 141, got $oks"; fails=$((fails + 1)); }
[ "$fails" = 0 ] || exit 1
exit 0
