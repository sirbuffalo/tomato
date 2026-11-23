#!/bin/sh
# Prints the message template of every error the compiler can raise (CompileError, ParseError, LexError) in compiler/src, one
# per line: the first line of the message with each {expression} of an f-text turned into {}. Used to keep std/errors.txt
# complete: tests/run.sh checks that every template is in the table (the table is the list of error ids).
cd "$(dirname "$0")/.." || exit 1
awk '
function template(s,    q, i, c, out, depth, isf, esc) {
  # s starts at the opening of the text: an optional f, then a quote
  isf = 0
  if (substr(s, 1, 1) == "f") { isf = 1; s = substr(s, 2) }
  q = substr(s, 1, 1)
  if (q != "\"" && q != "\x27") return ""
  out = ""; depth = 0; esc = 0
  for (i = 2; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (depth > 0) { if (c == "{") depth++; else if (c == "}") { depth--; if (depth == 0) out = out "{}" } continue }
    if (esc) { esc = 0; out = out "\\" c; continue }
    if (c == "\\") { esc = 1; continue }
    if (c == q) { if (substr(s, i + 1, 1) == " " || substr(s, i + 1, 1) == "+") { rest = substr(s, i + 1); if (rest ~ /^ *\+/) out = out "{}" } break }
    if (isf && c == "{") { if (substr(s, i + 1, 1) == "{") { out = out "{"; i++; continue } depth = 1; continue }
    out = out c
  }
  sub(/\\n.*/, "", out)
  # Literal + diagnostics share E190 with the general binary-operator template.
  if (out == "cannot use \x27+\x27 with {} and {}") return "cannot use \x27{}\x27 with {} and {}"
  # The unknown escape message appends the escaped character and the closing apostrophe.
  if (out ~ /^this text has an unknown escape /) return "this text has an unknown escape \x27{}\x27"
  return out
}
/raise (CompileError|ParseError|LexError)\(/ {
  line = $0
  sub(/.*raise (CompileError|ParseError|LexError)\(/, "", line)
  t = template(line)
  if (t != "") print t
}' compiler/src/*.tom | sort -u
