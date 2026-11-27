#!/bin/sh
# Fails when a keyword or built-in of the compiler is missing from the website highlighter (site/site.js) or the VS Code
# grammar (editors/vscode/syntaxes/tomato.tmLanguage.json). Usage: tests/highlighter_lists.sh (prints "ok" or the missing words)
cd "$(dirname "$0")/.." || exit 1
lexer=compiler/src/lexer.tom
grammar=editors/vscode/syntaxes/tomato.tmLanguage.json
site=site/site.js
words() { grep -o "'[A-Za-z_]*'" | tr -d "'"; }
# the list of keywords: the lines of is_keyword() between "words = [" and "]"
keywords="$(awk '/^def is_keyword/ {on=1} on {print} on && /\]/ {exit}' $lexer | words)"
builtins="$(grep -A1 '^def builtin_names' compiler/src/lint.tom | tail -1 | words) round divmod any all"
# contextual keywords (not in the lexer's table, but the parser treats them as keywords)
contextual="start yields None"
bad=0
missing() { echo "$1 does not know the $2 '$3'"; bad=1; }
for w in $keywords $contextual; do
  case "$w" in
    True|False|None) grep -q "True|False|None" $site || missing site keyword "$w" ;;
    start|yields) grep -q "\"$w\"" $site || missing site keyword "$w" ;;
    *) grep "var KW" $site | grep -q "[(|]$w[|)]" || missing site keyword "$w" ;;
  esac
  case "$w" in
    True|False|None) grep '"constant"' $grammar ;;
    start|yields) grep -A1 '"\(start-expression\|yields-clause\)"' $grammar ;;
    *) awk '/^    "keyword": \{/ {on=1} /^    "constant"/ {on=0} on' $grammar ;;
  esac | grep -q "[(|]$w[|)]" || missing grammar keyword "$w"
done
for w in $builtins; do
  grep "var BI" $site | grep -q "[(|]$w[|)]" || missing site built-in "$w"
  grep '"builtin"' $grammar | grep -q "[(|]$w[|)]" || missing grammar built-in "$w"
done
# self is colored by both
grep -q 'self' $site || missing site keyword self
grep -q 'bself' $grammar || missing grammar keyword self
# the type names must be the same in both (the site's TY list and the grammar's "type" rule)
site_types="$(grep 'var TY' $site | sed 's/.*\^(//; s/)\$.*//' | tr '|' '\n' | sort)"
gram_types="$(grep '"type":' -A2 $grammar | grep -o 'b(int|[^)]*' | sed 's/^b(//' | tr '|' '\n' | sort)"
for w in $site_types; do echo "$gram_types" | grep -qx "$w" || missing grammar type "$w"; done
# the repl's highlighter (compiler/src/hltomato.tom) colors the same built-in functions and types as the website, and the linter's names
hl="$(grep -E '^const (BUILTINS|TYPES) ' compiler/src/hltomato.tom | sed "s/^[^']*'//; s/'.*//" | tr ' ' '\n' | grep .)"
site_bi="$(grep 'var BI' $site | sed 's/.*\^(//; s/)\$.*//' | tr '|' '\n')"
for w in $builtins $site_bi $site_types; do echo "$hl" | grep -qx "$w" || missing hltomato built-in "$w"; done
for w in $hl; do { echo "$site_bi"; echo "$site_types"; } | grep -qx "$w" || { echo "hltomato.tom knows '$w', which the website does not"; bad=1; }; done
# the repl's Tab completion (compiler/src/repledit.tom) offers the lexer's keywords, the contextual ones, and self: the same words
rk="$(grep -E '^const KEYWORDS ' compiler/src/repledit.tom | sed "s/^[^']*'//; s/'.*//" | tr ' ' '\n' | grep .)"
kwset=" $(echo $keywords $contextual self) "
for w in $keywords $contextual self; do echo "$rk" | grep -qx "$w" || missing repledit keyword "$w"; done
for w in $rk; do case "$kwset" in *" $w "*) ;; *) echo "repledit.tom completes the keyword '$w', which the lexer does not know"; bad=1 ;; esac; done
# the standard library modules (std/NAME.tom) are colored after import/from
for f in std/*.tom; do
  w="$(basename "$f" .tom)"
  grep "var MOD" $site | grep -q "[(|]$w[|)]" || missing site module "$w"
  grep '"import-module"' -A2 $grammar | grep -q "[(|]$w[|)]" || missing grammar module "$w"
done
[ $bad = 0 ] && echo ok
exit $bad
