#!/usr/bin/env python3
"""Generates the terminal width tables inside runtime/tomato_rt.c (between the BEGIN/END GENERATED WIDTH TABLES markers).

    python3 -I tools/gen_width_table.py runtime/tomato_rt.c           rewrites the tables in place
    python3 -I tools/gen_width_table.py --check runtime/tomato_rt.c   exits 1 when the file's tables are not the ones this makes

Needs Python 3.14 (Unicode 16.0.0, which is what the tables are; `python3 -c "import unicodedata; print(unicodedata.unidata_version)"`
says what yours has). Under any other Python the generator stops with exit status 2 and says so, instead of writing or
reporting a table that differs only because the Unicode version does.

The data is unicodedata's, for code points from 0x300 up (below that the runtime answers 0 for controls and 1 otherwise):

  width 0  general category Mn, Me or Cf, except U+110BD and U+110CD (the Kaithi number signs, which are drawn over a
           following digit and take a cell of their own in terminals), and the Hangul Jamo vowels and final consonants,
           U+1160 to U+11FF and U+D7B0 to U+D7FF, which combine with the consonant before them
  width 2  East Asian Width W or F. Every Emoji_Presentation character is W (UAX #11 has made it so since Unicode 9), so the
           emoji need no data file of their own: Python has no Emoji_Presentation property, and the one on the machines this
           was written on (Unicode 17) is not 16.0. unicodedata gives W to the unassigned code points of the CJK blocks and
           planes 2 and 3 (EastAsianWidth.txt's @missing lines), as the table has always had them

Unassigned code points are 1 (never 0): a terminal has no way to know what a future combining mark is.
"""
import sys
import unicodedata

BEGIN = "/* BEGIN GENERATED WIDTH TABLES (tools/gen_width_table.py; do not edit) */\n"
END = "/* END GENERATED WIDTH TABLES */\n"
UNICODE = "16.0.0"
NOT_ZERO = {0x110BD, 0x110CD}


def zero(cp):
    if 0x1160 <= cp <= 0x11FF or 0xD7B0 <= cp <= 0xD7FF:
        return True
    return unicodedata.category(chr(cp)) in ("Mn", "Me", "Cf") and cp not in NOT_ZERO


def wide(cp):
    return unicodedata.east_asian_width(chr(cp)) in ("W", "F")


def ranges(pred):
    out = []
    cp = 0x300
    while cp < 0x110000:
        if 0xD800 <= cp < 0xE000 or not pred(cp):
            cp += 1
            continue
        last = cp
        while last + 1 < 0x110000 and not 0xD800 <= last + 1 < 0xE000 and pred(last + 1):
            last += 1
        out.append((cp, last))
        cp = last + 1
    return out


def emit(name, rs):
    s = "static const CpRange %s[] = {\n" % name
    for i in range(0, len(rs), 8):
        s += "    " + ",".join("{0x%04X,0x%04X}" % r for r in rs[i:i + 8]) + ",\n"
    return s + "};\n"


def generate():
    # a combining mark that is East Asian Wide (U+302A-D, U+3099-A, U+16FE4) is 0: the runtime looks at width0 first
    w = ranges(wide)
    z = ranges(zero)
    s = BEGIN
    s += "/* Unicode %s as Python %d.%d has it (unicodedata): width 0 for Mn, Me and Cf, width 2 for East Asian Width W and F. */\n" % (
        unicodedata.unidata_version, *sys.version_info[:2])
    return s + emit("width0", z) + emit("width2", w) + END


def main():
    args = sys.argv[1:]
    check = args[:1] == ["--check"]
    if check:
        args = args[1:]
    if len(args) != 1:
        sys.stderr.write(__doc__)
        return 2
    if unicodedata.unidata_version != UNICODE:
        sys.stderr.write("gen_width_table.py needs a Python whose unicodedata is Unicode %s (Python 3.14); this is Python %s with Unicode %s\n"
                         % (UNICODE, sys.version.split()[0], unicodedata.unidata_version))
        return 2
    path = args[0]
    text = open(path, encoding="utf-8").read()
    a, b = text.find(BEGIN), text.find(END)
    if a < 0 or b < 0:
        sys.stderr.write("%s: the BEGIN/END GENERATED WIDTH TABLES markers are missing\n" % path)
        return 2
    new = text[:a] + generate() + text[b + len(END):]
    if check:
        if new != text:
            sys.stderr.write("%s: the width tables are not what tools/gen_width_table.py makes: run it without --check\n" % path)
            return 1
        return 0
    open(path, "w", encoding="utf-8").write(new)
    return 0


sys.exit(main())
