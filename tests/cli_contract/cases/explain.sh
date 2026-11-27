# tier: any
# `tomato explain CODE [FILE]`: decode an error id (E04, or E04:12 as the id and line of a release build's error line), with the source line when given a file.
. "$CONTRACT_DIR/lib.sh"

try "explain E01: the id, the class and the message" 0 "error[E01]: ZeroDivisionError: division by zero" "" explain E01
try "explain E04: another id" 0 "error[E04]: IndexError: index out of range" "" explain E04
try "explain pads the id to two digits" 0 "error[E04]: IndexError: index out of range" "" explain E004
try "explain reads leading zeros of a long id and of a line" 0 "error[E04]: IndexError: index out of range" "" explain E0004:0003
try "explain E04:12 with no file names the error only" 0 "error[E04]: IndexError: index out of range" "" explain E04:12
try "explain a high id the table knows" 0 "~error[E543]: ConfigError: " "" explain E543
try "explain an id the table does not list" 0 "error[E9999]: an error the table does not list" "" explain E9999
try "explain a very long number is not listed either" 0 "error[E4294967296]: an error the table does not list" "" explain E4294967296
# what is not an id: status 1, the text on standard error
for c in x E E0 E00 E1 e04 E04: E04:x E04:12:3 E04x "E 4" E-1 :12 E:1; do
  try "explain $c is not an error id" 1 "" "error: $c is not an error id (they look like E04 or E04:12)" explain "$c"
done
# with a file and a line, the line is laid out like a compiler error
printf 'a = 1\n    x = 1 // 0\n' > src.tom
try "explain E04:2 FILE shows the line and a caret under its code" 0 @explain_line.txt "" explain E04:2 src.tom
try "explain E04:1 FILE: no indent" 0 @explain_line1.txt "" explain E04:1 src.tom
try "explain E04:99 FILE: a line past the end is said, status 0" 0 @explain_past_end.txt "" explain E04:99 src.tom
try "explain E04:0 FILE: line zero means no location: the id only" 0 "error[E04]: IndexError: index out of range" "" explain E04:0 src.tom
try "explain E04 FILE: no line, the id only" 0 "error[E04]: IndexError: index out of range" "" explain E04 src.tom
try "explain E04:2 with a file that is not there: the id, then the error, status 1" 1 "error[E04]: IndexError: index out of range" "error: cannot read nosuch.tom" explain E04:2 nosuch.tom
printf 'print(1)\n' > two_digit_line.tom
try "explain E01:1 FILE: a one-line file" 0 @explain_one_line.txt "" explain E01:1 two_digit_line.tom
mkdir -p sub; printf 'x\n' > sub/t.tom
try "explain E01:1 sub/t.tom: the path is shown as it was written" 0 "~ --> sub/t.tom:1" "" explain E01:1 sub/t.tom
if fast; then skip "explain decodes what a release build printed (a link: not in the fast tier)"; else
# the id the command prints is the one a release build prints with its line: run a failing program in release mode and decode it
printf '@main\ndef main():\n    x = 0\n    print(5 // x)\n' > dz.tom
"$TOMATO" run dz.tom --mode release > /dev/null 2> "$W/release.err"
check "a release build prints the id, the message and the line" "error[E01]: division by zero (line 4)" "$(cat "$W/release.err")"
try "explain decodes what a release build printed" 0 @explain_release.txt "" explain "$(sed -n 's/^error\[\(E[0-9]*\)\].* (line \([0-9]*\))$/\1:\2/p' "$W/release.err")" dz.tom
fi
try "explain: --color=always paints nothing on standard output (the colors are for errors)" 0 "error[E01]: ZeroDivisionError: division by zero" "" explain E01 --color=always
