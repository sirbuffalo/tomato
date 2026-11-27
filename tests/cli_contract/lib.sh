# The helpers every case in tests/cli_contract/cases/ sources. Plain POSIX sh (it runs on macOS and Linux).
#
# A case is a black-box check of the `tomato` command: it starts $TOMATO (or the tomato on PATH, which run.sh resolves to an absolute path)
# the way a user would, and looks only at what a user sees: the standard output, the standard error, the exit status and the files left behind.
# Nothing here may assume how the command is made (a shell script today, a compiled Tomato program later): no sourcing of its files, no
# reading of its install folder, no shell functions, no `sh -x`. A case that needs a program to run goes through `tomato run` or `tomato build`.
#
# What run.sh gives a case (in the environment): TOMATO (the command), CONTRACT_DIR (tests/cli_contract), W (the case's own empty folder, which is
# also its current folder), CONTRACT_FAST (1 in the fast tier), CONTRACT_UPDATE (1 to rewrite the golden files).

[ -n "${TOMATO:-}" ] && [ -n "${CONTRACT_DIR:-}" ] && [ -n "${W:-}" ] || { echo "tests/cli_contract/lib.sh: run a case through tests/cli_contract/run.sh" >&2; exit 2; }
golden="$CONTRACT_DIR/golden"
case_name="$(basename "${0%.sh}")"
nl="
"
# A clean environment: nothing from the caller's shell changes what the command does. TOMATO_HOME is the case's own folder, so the user's
# own ~/.tomato/config.toml is never read; the compiled-runtime cache is left alone (it makes the checks fast; cache.sh tests it apart).
unset TOMATO_COLOR NO_COLOR TOMATO_WARNINGS TOMATO_CACHE TOMATO_CACHE_DIR TOMATO_UPDATE_URL TOMATO_UPDATE_PRE_URL TOMATO_UPDATE_FALLBACK TOMATO_UPDATE_ALLOW_ANY_URL TOMATO_UPDATE_ALLOW_FILE
export TOMATO_HOME="$W/.tomato-home" TOMATO_BIN="$W/.tomato-bin"
tmp_out="$W/.t.out"; tmp_err="$W/.t.err"; tmp_exp="$W/.t.exp"
mkdir -p "$TOMATO_HOME"

ok() { echo "ok   cli contract: $case_name: $1"; }
bad() { echo "FAIL cli contract: $case_name: $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/     /'; }
skip() { echo "skip cli contract: $case_name: $1"; }
fast() { [ -n "${CONTRACT_FAST:-}" ]; }

# sed script that makes the text the same on every machine: the case's folder becomes @W, the version of the command @VERSION@ and the
# `tomato = "MAJOR.MINOR"` line of a manifest @MINV@ (init writes the oldest compiler that builds the project: this one)
wsed="$(printf '%s' "$W" | sed 's/[][\\.*^$|]/\\&/g')"
norm() { sed -e "s|$wsed|@W|g" -e 's|^Tomato v[^ ]* |Tomato v@VERSION@ |' -e 's|^tomato = "[^"]*"|tomato = "@MINV@"|'; }

# the command's version, and the MAJOR.MINOR that init writes into a manifest (the whole version for a pre-release)
version="$("$TOMATO" version 2>/dev/null | sed -n 's/^Tomato v\([^ ]*\) .*/\1/p')"
case "$version" in *-*) minv="$version" ;; *) minv="$(printf '%s' "$version" | awk -F. '{ print $1 "." $2 }')" ;; esac

# expect KIND NAME ACTUAL_FILE SPEC: SPEC is - (not checked), @NAME (the golden file golden/NAME, after the text is made the same on every
# machine), ~TEXT (the output contains the one line TEXT), =TEXT or plain TEXT (the output is exactly TEXT and a newline; empty: no output at all)
expect() {
  e_name="$1"; e_file="$2"; e_spec="$3"
  case "$e_spec" in
    -) return 0 ;;
    @*) e_gold="$golden/${e_spec#@}"
        norm < "$e_file" > "$tmp_exp.n"
        if [ -n "${CONTRACT_UPDATE:-}" ]; then cp "$tmp_exp.n" "$e_gold"; echo "updated $e_gold"; return 0; fi
        if [ ! -f "$e_gold" ]; then bad "$e_name" "the golden file $e_gold is missing (CONTRACT_UPDATE=1 writes it)"; return 1; fi
        if cmp -s "$tmp_exp.n" "$e_gold"; then return 0; fi
        bad "$e_name" "differs from golden/${e_spec#@} (- expected, + got):
$(diff -u "$e_gold" "$tmp_exp.n" | sed '1,2d' | head -30)"; return 1 ;;
    "~"*) norm < "$e_file" > "$tmp_exp.n"
        e_needle="$(printf '%s' "${e_spec#\~}" | norm)"   # (the text is made the same way: a path of this case is @W; one line)
        if grep -F -q -e "$e_needle" "$tmp_exp.n"; then return 0; fi
        bad "$e_name" "does not contain: ${e_spec#\~}
got: $(head -c 600 "$tmp_exp.n")"; return 1 ;;
    *) e_text="${e_spec#=}"
        if [ -n "$e_text" ]; then printf '%s\n' "$e_text" | norm > "$tmp_exp"; else : > "$tmp_exp"; fi
        norm < "$e_file" > "$tmp_exp.n"
        if cmp -s "$tmp_exp.n" "$tmp_exp"; then return 0; fi
        bad "$e_name" "expected: $e_text
got:      $(head -c 600 "$tmp_exp.n")"; return 1 ;;
  esac
}
# try NAME STATUS OUT ERR ARGS...: runs the command with the arguments (standard input empty, in the current folder) and checks the exit
# status (a number; - not checked; ! any but 0), the standard output and the standard error against OUT and ERR (as for expect)
try() {
  t_name="$1"; t_status="$2"; t_o="$3"; t_e="$4"; shift 4
  "$TOMATO" "$@" > "$tmp_out" 2> "$tmp_err" < /dev/null; rc=$?
  t_ok=1
  case "$t_status" in
    -) ;;
    '!') [ "$rc" -ne 0 ] || { bad "$t_name" "expected a status other than 0, got 0"; t_ok=0; } ;;
    *) [ "$rc" = "$t_status" ] || { bad "$t_name" "expected exit status $t_status, got $rc
stdout: $(head -c 300 "$tmp_out")
stderr: $(head -c 300 "$tmp_err")"; t_ok=0; } ;;
  esac
  if [ "$t_ok" = 1 ]; then expect "$t_name (standard output)" "$tmp_out" "$t_o" || t_ok=0; fi
  if [ "$t_ok" = 1 ]; then expect "$t_name (standard error)" "$tmp_err" "$t_e" || t_ok=0; fi
  [ "$t_ok" = 0 ] || ok "$t_name"
  return 0
}
# check NAME EXPECTED ACTUAL: plain equality
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2
got:      $3"; fi; }
# within DIR COMMAND...: runs the command in DIR (made when missing); the case's counts still count
within() { w_dir="$1"; shift; mkdir -p "$w_dir"; ( cd "$w_dir" && "$@" ); }
# files_in DIR: the names of the files and folders below DIR, sorted, one per line (to show that a command wrote nothing, or exactly these)
files_in() { ( cd "$1" && find . ! -name . | sed 's|^\./||' | LC_ALL=C sort ); }
