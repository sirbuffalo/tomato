# tier: any
# `tomato update`, only the paths that end before anything is downloaded or installed: the flags, a manifest that cannot be read or is not
# understood, a version that is not newer, a manifest with no checksum, a download that is not an official release URL. The manifest comes
# from a file: (TOMATO_UPDATE_URL, with TOMATO_UPDATE_ALLOW_ANY_URL, the test override of the https-only rule). Nothing is installed, nothing
# touches the network. When $TOMATO is a checkout (not an install) the command refuses, and the case says so and skips.
. "$CONTRACT_DIR/lib.sh"

official="https://github.com/sirbuffalo/tomato/releases/download/v9.9.9/t.tar.gz"
zeros=0000000000000000000000000000000000000000000000000000000000000000
mk() { printf '{"version":"%s","url":"%s","sha256":"%s"}' "$2" "$3" "$4" > "$1"; }
upd() { # NAME STATUS OUT ERR MANIFEST-FILE ARGS...: run update against that manifest (the fallback manifest is a file that is not there)
  u_n="$1"; u_s="$2"; u_o="$3"; u_e="$4"; u_f="$5"; shift 5
  ( export TOMATO_UPDATE_URL="file://$W/$u_f" TOMATO_UPDATE_FALLBACK="file://$W/nosuch.json" TOMATO_UPDATE_ALLOW_ANY_URL=1; try "$u_n" "$u_s" "$u_o" "$u_e" update "$@" )
}
mk old.json 0.0.1 "$official" "$zeros"
( export TOMATO_UPDATE_URL="file://$W/old.json" TOMATO_UPDATE_FALLBACK="file://$W/nosuch.json" TOMATO_UPDATE_ALLOW_ANY_URL=1; "$TOMATO" update > "$W/o" 2> "$W/e" < /dev/null )
if grep -q 'is not one' "$W/e"; then skip "tomato is a checkout here, not an install: update refuses (checked: the text says so)"
  try "update in a checkout refuses to replace it" 1 "" "~tomato update replaces an install, and " update
  exit 0
fi
# (every run of update here has TOMATO_UPDATE_URL set to a file: nothing ever reaches the network)
try "update: an unknown flag" 1 "" "error: tomato update takes --minor and --pre, not --bogus" update --bogus
upd "update: an older manifest version is left alone" 0 "tomato v$version is the latest" "" old.json
upd "update: --minor and --pre are accepted" 0 "tomato v$version is the latest" "" old.json --minor --pre
mk same.json "$version" "$official" "$zeros"
upd "update: the same version is the latest" 0 "tomato v$version is the latest" "" same.json
printf '{"version":"9.9.9","url":"%s"}' "$official" > nosum.json
upd "update: a manifest with no checksum is refused, after saying what it would do" 1 "updating v$version -> v9.9.9" "error: the manifest has no valid sha256: not updating" nosum.json
mk badsum.json 9.9.9 "$official" zz
upd "update: a checksum that is not 64 hex digits is refused" 1 "updating v$version -> v9.9.9" "error: the manifest has no valid sha256: not updating" badsum.json
printf '{"foo":1}' > junk.json
upd "update: a manifest that is not understood (named by its address)" 1 "" "~is not understood" junk.json
upd "update: a manifest that is not there" 1 "" "~error: cannot read file://@W/nosuch2.json" nosuch2.json
mk evil.json 9.9.9 "http://example.invalid/x.tar.gz" "$zeros"
( export TOMATO_UPDATE_URL="file://$W/evil.json" TOMATO_UPDATE_FALLBACK="file://$W/nosuch.json" TOMATO_UPDATE_ALLOW_FILE=1
  try "update: a download that is not an official release URL is refused before anything is downloaded" 1 "updating v$version -> v9.9.9" "error: the download is not an official release URL: not updating" update )
( export TOMATO_UPDATE_URL="file://$W/old.json" TOMATO_UPDATE_FALLBACK="file://$W/old.json"; unset TOMATO_UPDATE_ALLOW_ANY_URL
  try "update: file: manifests are refused without the test override (https only)" 1 "" "~error: cannot read " update )
