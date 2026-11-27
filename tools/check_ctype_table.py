#!/usr/bin/env python3
"""Checks the isalpha/isdigit tables in runtime/tomato_rt.c (ctype_alpha_rows, ctype_digit_rows; written by tools/gen_ctype_table.c)
against Python's str.isalpha and str.isdigit for every code point from 0x80 up (ASCII is handled before the tables).

    python3 -I tools/check_ctype_table.py runtime/tomato_rt.c

Exit status 0: the tables are Python's; 1: they differ (the first differences are printed); 2: this Python is not Unicode 16.0.0
(Python 3.14), so it cannot say. Surrogates (U+D800..U+DFFF) are in neither table and in neither of Python's answers.
"""
import re
import sys
import unicodedata

UNICODE = "16.0.0"


def rows(text, name):
    m = re.search(r"static const int32_t %s\[\]\[2\] = \{(.*?)\n\};" % name, text, re.S)
    if not m:
        sys.exit("check_ctype_table: %s not found" % name)
    s = set()
    for a, b in re.findall(r"\{0x([0-9A-Fa-f]+), 0x([0-9A-Fa-f]+)\}", m.group(1)):
        s.update(range(int(a, 16), int(b, 16) + 1))
    return s


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check_ctype_table.py runtime/tomato_rt.c")
    if unicodedata.unidata_version != UNICODE:
        print("check_ctype_table: needs Python 3.14 (Unicode %s); this Python has %s" % (UNICODE, unicodedata.unidata_version), file=sys.stderr)
        return 2
    text = open(sys.argv[1], encoding="utf-8").read()
    bad = 0
    for name, pred in (("ctype_alpha_rows", str.isalpha), ("ctype_digit_rows", str.isdigit)):
        have = rows(text, name)
        want = {cp for cp in range(0x80, 0x110000) if pred(chr(cp))}
        if have != want:
            bad += 1
            d = sorted(have ^ want)
            print("%s differs from Python at %d code points, first: %s" % (
                name, len(d), ", ".join("U+%04X (%s)" % (c, "table only" if c in have else "Python only") for c in d[:5])))
    return 1 if bad else 0


sys.exit(main())
