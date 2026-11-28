#!/bin/sh
# Checks that no shipped shell script has a case command inside a command substitution (dollar, open paren, case ... esac, close paren).
# bash 3.2 (macOS /bin/sh) mis-parses the ) of a case pattern in there when it is inside double quotes, and runs words of the text as
# commands ("an: command not found"). Build the text in a variable before the line instead. Prints ok, or one line per place.
cd "$(dirname "$0")/.." || exit 1
bad=""
for f in $(git ls-files | grep -E '(\.sh$|^native/tomato$|^release/)'); do
  [ -f "$f" ] || continue
  # the pattern is written in two halves so that this file does not match itself
  if tr '\n' ' ' < "$f" | grep -qE '[$]\([[:space:]]*'"case"'[[:space:]]'; then bad="$bad $f"; fi
  if tr '\n' ' ' < "$f" | grep -qE '`[[:space:]]*'"case"'[[:space:]]'; then bad="$bad $f"; fi
done
if [ -z "$bad" ]; then echo ok; else echo "case inside a command substitution (bash 3.2 mis-parses it; build the text in a variable first) in:$bad"; fi
