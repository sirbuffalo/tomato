#!/bin/sh
# gen.sh [OUTDIR]: writes the fixture index of the registry tests into index/ (config.toml, policy.toml, owners/, seeds/, requests/, names.toml,
# yanks.toml), signed with the test keys of keys/ by `ssh-keygen -Y sign`. The signed text is built here in shell, independently of the
# Tomato code that reads it (docs/package-registry-design.md section 1.4, compiler/src/index.tom `signing_text`):
#
#   tomato-seeds-v1 LF  KIND LF  SUBJECT LF  then NAME=VALUE LF for each field the statement has, in the schema's order
#   (a list is its items joined by commas, a table `key:value` items sorted and joined by commas)
#
# With an OUTDIR the index is written there and nothing in this folder changes (tests/run.sh does that, to check that index/ is what this script makes). Run it again after changing a seed under seeds-src/ or this script; the output is the same on every run (ed25519 signatures are
# deterministic, the stamps are written here). The test keys are public test data: nothing is secret in this folder.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/index}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
chmod 600 "$here"/keys/* 2>/dev/null || true
# ssh-keygen wants private keys that nobody else can read: work on copies
mkdir -p "$tmp/keys"; for k in "$here"/keys/*; do cp "$k" "$tmp/keys/"; done; chmod 600 "$tmp"/keys/*
rm -rf "$out"; mkdir -p "$out/owners" "$out/seeds" "$out/requests"
sum256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi; }
"$here/build-sources.sh" "$tmp/src"
commit_of() { awk -v n="$1" -v v="$2" '$1 == n && $2 == v { print $3 }' "$tmp/src/commits.txt"; }
# the seed hash v1 of section 6 with find, sort and sha256
hash_of() { printf 'sha256:%s' "$(cd "$here/seeds-src/$1/$2" && find . -type f | sed 's#^\./##' | LC_ALL=C sort | while read -r f; do m=644; [ -x "$f" ] && m=755; printf '%s  %s  %s\n' "$(sum256 < "$f")" "$m" "$f"; done | sum256)"; }
fp() { ssh-keygen -l -f "$tmp/keys/$1.pub" | awk '{print $2}'; }
pub() { awk '{print $1 " " $2}' "$tmp/keys/$1.pub"; }
pubc() { cat "$tmp/keys/$1.pub"; }       # with the comment
# emit TABLE KIND SUBJECT KEY ACCEPTED FIELD...: one statement on standard output. A FIELD is TYPE:name=value (s text, l list, d table).
# signed_by is added last, the signature covers every field; TAMPER=name=value writes that field with another value after signing.
emit() {
  table="$1"; kind="$2"; subject="$3"; key="$4"; accepted="$5"; shift 5
  msg="$tmp/msg"
  printf 'tomato-seeds-v1\n%s\n%s\n' "$kind" "$subject" > "$msg"
  for f in "$@"; do printf '%s\n' "${f#?:}" >> "$msg"; done
  printf 'signed_by=%s\n' "$(fp "$key")" >> "$msg"
  rm -f "$msg.sig"; ssh-keygen -q -Y sign -f "$tmp/keys/$key" -n tomato-seeds-v1 "$msg" 2>/dev/null
  printf '[[%s]]\n' "$table"
  for f in "$@"; do
    t="${f%%:*}"; rest="${f#?:}"; name="${rest%%=*}"; val="${rest#*=}"
    case "${TAMPER:-}" in "$name="*) val="${TAMPER#*=}" ;; esac
    case "$t" in
      s) printf '%s = "%s"\n' "$name" "$val" ;;
      l) printf '%s = [' "$name"; sep=""; oldifs="$IFS"; IFS=','; for i in $val; do printf '%s"%s"' "$sep" "$i"; sep=", "; done; IFS="$oldifs"; printf ']\n' ;;
      d) printf '%s = {' "$name"; sep=" "; oldifs="$IFS"; IFS=','; for i in $val; do printf '%s"%s" = "%s"' "$sep" "${i%%:*}" "${i#*:}"; sep=", "; done; IFS="$oldifs"; printf ' }\n' ;;
    esac
  done
  printf 'signed_by = "%s"\n' "$(fp "$key")"
  [ -z "$accepted" ] || printf 'accepted = %s\n' "$accepted"
  printf 'signature = "%s"\n\n' "$(awk '{ printf "%s\\n", $0 }' "$msg.sig")"
}
URL=https://git.fixture.example
# ---- config.toml, policy.toml
cat > "$out/config.toml" <<'T'
# the fixture index of the registry tests (not a real registry)
format = 1
name = "fixture"
T
cat > "$out/policy.toml" <<'T'
# the launch policy: nothing is required (design section 18.3)
version = 1
notice_days = 60

[listing]
require_tests_pass = false
min_tests_per_module = 0
min_age_days = 0
min_score = 0
require_license = false
min_stars = 0
min_endorsements = 0

[short_name]
min_stars = 0
min_endorsements = 0

[demotion]
enabled = false
grace_days = 90
T
# ---- owners: acme.example rotates its key (acme1 root, acme2 added at 2026-12-01 and acme1 retired by the same statement)
{
  emit key key acme.example acme1 2026-11-01T09:00:00Z s:kind=root "s:public=$(pubc acme1)"
  emit key key acme.example acme1 2026-12-01T09:00:00Z s:kind=rotate "s:public=$(pub acme2)" "s:retires=$(fp acme1)"
} > "$out/owners/acme.example.toml"
emit key key other.example other 2026-11-02T09:00:00Z s:kind=root "s:public=$(pub other)" > "$out/owners/other.example.toml"
emit key key dave dave 2026-11-20T09:00:00Z s:kind=root "s:public=$(pub dave)" > "$out/owners/dave.toml"
{ printf '[owner]\nsimilar = "other.example"\n\n'; emit key key rogue.example rogue 2026-11-25T09:00:00Z s:kind=root "s:public=$(pub rogue)"; } > "$out/owners/rogue.example.toml"
# ---- seeds
mkdir -p "$out/seeds/acme.example" "$out/seeds/other.example" "$out/seeds/dave" "$out/seeds/rogue.example"
ver() { # OWNER NAME VERSION KEY ACCEPTED [SEEDS-TABLE] [PUBLISHED]: a [[version]] statement of the commit and hash of that version
  o="$1"; n="$2"; v="$3"; k="$4"; a="$5"; deps="${6:-}"; pub_date="${7:-}"
  mods="$n"; mods="$(printf '%s' "$mods" | tr '-' '_')"
  set -- "s:version=$v" "s:commit=$(commit_of "$o/$n" "$v")" "s:hash=$(hash_of "$o/$n" "$v")" "s:tomato=0.51" "l:modules=$mods"
  [ -z "$deps" ] || set -- "$@" "d:seeds=$deps"
  [ -z "$pub_date" ] || set -- "$@" "s:published=$pub_date"
  emit version version "$o/$n" "$k" "$a" "$@"
}
{
  emit source source acme.example/json5 acme1 2026-11-01T09:05:00Z "s:git=$URL/acme.example/json5.git"
  ver acme.example json5 1.0.0 acme1 2026-11-02T10:00:00Z "" 2026-11-02
  ver acme.example json5 1.1.0 acme1 2026-11-10T10:00:00Z "" 2026-11-10
  ver acme.example json5 1.2.0 acme2 2026-12-02T10:00:00Z "other.example/strutil:0.4.1" 2026-12-02
  ver acme.example json5 1.3.0 acme2 2026-12-05T10:00:00Z "" 2026-12-05
  ver acme.example json5 2.0.0-rc.1 acme2 2026-12-06T10:00:00Z "" 2026-12-06
  # signed by acme1 after the rotation retired it: ignored (the stamp is later than the retirement)
  emit version version acme.example/json5 acme1 2026-12-03T10:00:00Z s:version=1.2.1 "s:commit=$(commit_of acme.example/json5 1.2.0)" "s:hash=$(hash_of acme.example/json5 1.2.0)" s:tomato=0.51 l:modules=json5
  emit yank yank acme.example/json5 acme2 2026-12-04T10:00:00Z s:version=1.1.0 s:kind=bug "s:reason=returns wrong numbers for 1e400"
} > "$out/seeds/acme.example/json5.toml"
{
  emit source source other.example/strutil other 2026-11-02T09:05:00Z "s:git=$URL/other.example/strutil.git"
  ver other.example strutil 0.3.0 other 2026-10-01T10:00:00Z "" 2026-10-01
  emit yank yank other.example/strutil other 2026-10-02T10:00:00Z s:version=0.3.0 s:kind=malware "s:reason=steals tokens"
  # 0.4.0 is signed with the right commit and written with another one: the signature no longer matches, so it is ignored
  TAMPER="commit=0000000000000000000000000000000000000001" ver other.example strutil 0.4.0 other 2026-11-03T10:00:00Z "" 2026-11-03
  ver other.example strutil 0.4.1 other 2026-11-08T10:00:00Z "" 2026-11-08
  ver other.example strutil 0.5.0 other 2026-12-01T10:00:00Z "acme.example/json5:2.0.0-rc.1" 2026-12-01
} > "$out/seeds/other.example/strutil.toml"
{
  emit source source dave/thing dave 2026-11-20T09:05:00Z "s:git=$URL/dave/thing.git"
  ver dave thing 1.0.0 dave 2026-11-21T10:00:00Z "" 2026-11-21
} > "$out/seeds/dave/thing.toml"
# dave/liar: three versions whose signed entries do not match what is at their commit (a tomato.toml that says another version; a
# [seeds] table the entry does not have; a content hash that is not the files')
{
  emit source source dave/liar dave 2026-11-22T09:05:00Z "s:git=$URL/dave/liar.git"
  set -- "s:version=1.0.0" "s:commit=$(commit_of dave/liar 1.0.0)" "s:hash=$(hash_of dave/thing 1.0.0)" s:tomato=0.51 l:modules=liar
  emit version version dave/liar dave 2026-11-22T10:00:00Z "$@"
  ver dave liar 1.1.0 dave 2026-11-23T10:00:00Z "" 2026-11-23
  ver dave liar 1.2.0 dave 2026-11-24T10:00:00Z "" 2026-11-24
} > "$out/seeds/dave/liar.toml"
{
  emit source source rogue.example/evil rogue 2026-11-25T09:05:00Z "s:git=$URL/rogue.example/evil.git"
  # signed by acme2, which is not a key of rogue.example: ignored
  ver rogue.example evil 1.0.0 acme2 2026-11-26T10:00:00Z "" 2026-11-26
} > "$out/seeds/rogue.example/evil.toml"
# ---- requests (the owner's own signed ask for a short name; the maintainers answer in names.toml)
emit request request acme.example acme2 2026-12-02T11:00:00Z s:ask=name s:seed=acme.example/json5 > "$out/requests/acme.example.toml"
# ---- names.toml: the maintainers' short names and handles (key maint); a name signed by a key that is not a maintainer's is ignored
{
  emit name name json5 maint 2026-12-03T09:00:00Z s:name=json5 s:seed=acme.example/json5 s:granted=2026-12-03
  emit name name strutil maint 2026-12-03T09:10:00Z s:name=strutil s:seed=other.example/strutil s:granted=2026-12-03
  emit unname unname strutil maint 2026-12-04T09:00:00Z s:name=strutil "s:reason=released at the owner's request"
  emit name name evil rogue 2026-12-03T09:20:00Z s:name=evil s:seed=rogue.example/evil s:granted=2026-12-03
  emit handle handle dave maint 2026-11-20T08:00:00Z s:handle=dave "s:key=$(pub dave)" s:granted=2026-11-20
} > "$out/names.toml"
# ---- yanks.toml: the maintainers' emergency yank of json5 1.3.0 (listing only); a yank signed by a key that is not a maintainer's is ignored
{
  emit yank maint-yank acme.example/json5 maint 2026-12-07T09:00:00Z s:seed=acme.example/json5 s:version=1.3.0 s:kind=malware "s:reason=exfiltrates ~/.ssh: see the advisory"
  emit yank maint-yank acme.example/json5 rogue 2026-12-07T09:30:00Z s:seed=acme.example/json5 s:version=1.2.0 s:kind=malware "s:reason=not a maintainer"
} > "$out/yanks.toml"
# the maintainer's and the other keys' public lines and fingerprints, for the tests to use
{
  for k in acme1 acme2 other dave maint rogue; do printf '%s %s\n' "$k" "$(fp $k)"; done
} > "$tmp/fingerprints.txt"
# with no argument the files the tests read beside the index are written too
if [ -z "${1:-}" ]; then cp "$tmp/fingerprints.txt" "$here/fingerprints.txt"; cp "$tmp/src/commits.txt" "$here/commits.txt"; fi
echo "wrote $out"
