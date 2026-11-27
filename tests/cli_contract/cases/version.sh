# tier: any
# `tomato version`: the line, its spellings, and that it needs nothing from the folder it is run in.
. "$CONTRACT_DIR/lib.sh"

try "version: one line, the version and what the compiler is written in" 0 @version.txt "" version
try "--version is the same" 0 @version.txt "" --version
try "-V is the same" 0 @version.txt "" -V
try "version ignores the words after it" 0 @version.txt "" version now please
case "$version" in
  [0-9]*.[0-9]*) ok "the version is MAJOR.MINOR or longer: $version" ;;
  *) bad "the version is MAJOR.MINOR or longer" "$version" ;;
esac
# a version is MAJOR.MINOR[.PATCH][-PRERELEASE][+BUILD], what `tomato update` and a manifest's `tomato` key compare (SemVer 2.0)
if printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then ok "the version is a SemVer text"; else bad "the version is a SemVer text" "$version"; fi
# a broken manifest in the folder, a missing tests folder, no write permission: version reads none of it
mkdir -p "$W/broken"; printf '[project\nname = \n' > "$W/broken/tomato.toml"
within "$W/broken" try "version does not read the folder's tomato.toml" 0 @version.txt "" version
# the options every command takes are checked first, wherever the command word is
try "version: a bad --color value is refused first" 1 "" "error: --color takes auto, always or never, not 'blue'" version --color=blue
try "version: --color=never is accepted" 0 @version.txt "" version --color=never
try "version: --no-warnings is accepted" 0 @version.txt "" version --no-warnings
