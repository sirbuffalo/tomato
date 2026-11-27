#!/usr/bin/env python3
"""Generates the case tables inside runtime/tomato_rt.c (between the BEGIN/END GENERATED CASE TABLES markers).

    python3 -I tools/gen_case_table.py runtime/tomato_rt.c           rewrites the tables in place
    python3 -I tools/gen_case_table.py --check runtime/tomato_rt.c   exits 1 when the file's tables are not the ones this makes

Needs Python 3.14 (Unicode 16.0.0); under any other Python it exits 2 and says which Unicode version it found. The suite runs
--check (tests/run.sh, "generated tables").

The data is Python's own: str.upper, str.lower and str.title of every single code point (Python 3.14 = Unicode 16.0.0: the
runtime's upper, lower, title and capitalize follow CPython's full case mapping, SpecialCasing included, so asking Python
gives its answers by construction), the version of which is recorded in the generated text. Python has no API for the two
context properties of the final-sigma and title rules, so they are read back from its behaviour on small strings:

  Cased           islower or isupper or general category Lt (Unicode's definition: Lowercase, Uppercase or Lt)
  Case_Ignorable  what Python's lower() skips when it looks for the neighbours of a capital sigma: 'A' + c + 'SIGMA' gives a
                  final sigma exactly when c is ignorable and not cased; for a cased c the trailing form 'ASIGMA' + c does

Tables (code points below 0x80 are handled by the runtime before it looks at them):
  case_upper_rows, case_lower_rows   {first, last, delta, step}: the code points first, first+step, ... up to last map to
                                     code point + delta (one code point to one)
  case_title_rows                    the same for titlecase where it differs from upper case (and is one code point)
  case_upper_full, case_lower_full, case_title_full
                                     {code point, count, {up to three code points}}: the mappings that are longer than one
  case_prop_runs                     where the properties change: (code point << 2) | flags, flags 1 = cased, 2 = case
                                     ignorable, from 0x80 on, the flags holding up to the next entry
"""
import sys
import unicodedata

BEGIN = "/* BEGIN GENERATED CASE TABLES (tools/gen_case_table.py; do not edit) */\n"
END = "/* END GENERATED CASE TABLES */\n"


def code_points():
    return [cp for cp in range(0x80, 0x110000) if not 0xD800 <= cp < 0xE000]


def rows(delta):
    """delta: cp -> int for the code points with a mapping; returns {first, last, delta, step} rows."""
    out = []
    keys = sorted(delta)
    i = 0
    while i < len(keys):
        cp = keys[i]
        d = delta[cp]
        step = 1
        if i + 1 < len(keys) and keys[i + 1] == cp + 2 and delta[keys[i + 1]] == d and (cp + 1) not in delta:
            step = 2
        last = cp
        i += 1
        while i < len(keys) and keys[i] == last + step and delta[keys[i]] == d:
            last = keys[i]
            i += 1
        out.append((cp, last, d, step))
    return out


def emit_rows(name, rs):
    s = "static const int32_t %s[][4] = {\n" % name
    for first, last, d, step in rs:
        s += "    {0x%X, 0x%X, %d, %d},\n" % (first, last, d, step)
    return s + "};\n"


def emit_full(name, entries):
    s = "static const int32_t %s[][5] = {\n" % name
    for cp, text in entries:
        cps = [ord(c) for c in text]
        assert 2 <= len(cps) <= 3
        s += "    {0x%X, %d, 0x%X, 0x%X, %s},\n" % (cp, len(cps), cps[0], cps[1], "0x%X" % cps[2] if len(cps) == 3 else "0")
    return s + "};\n"


def properties():
    cased = {}
    for cp in code_points():
        c = chr(cp)
        cased[cp] = c.islower() or c.isupper() or unicodedata.category(c) == "Lt"
    ignorable = {}
    for cp in code_points():
        c = chr(cp)
        if cased[cp]:
            ignorable[cp] = ("AΣ" + c).lower()[1] == "ς"
        else:
            ignorable[cp] = ("A" + c + "Σ").lower()[-1] == "ς"
    out = []   # run starts: (code point, flags) where the flags change, from 0x80
    prev = None
    for cp in range(0x80, 0x110000):
        f = (1 if cased.get(cp) else 0) | (2 if ignorable.get(cp) else 0)
        if f != prev:
            out.append((cp, f))
            prev = f
    return out


def generate():
    ups, lows, titles = {}, {}, {}
    upper_full, lower_full, title_full = [], [], []
    title_delta = {}
    for cp in code_points():
        c = chr(cp)
        u, l, t = c.upper(), c.lower(), c.title()
        for text, simple, full in ((u, ups, upper_full), (l, lows, lower_full)):
            if len(text) == 1:
                if text != c:
                    simple[cp] = ord(text) - cp
            else:
                full.append((cp, text))
        if t != u:
            if len(t) == 1:
                title_delta[cp] = ord(t) - cp
            else:
                title_full.append((cp, t))
    props = properties()
    # worst growth in UTF-8 bytes of one character: the runtime's buffer holds three times the input
    worst = max(len(text.encode()) / len(chr(cp).encode()) for cp, text in upper_full + lower_full + title_full)
    assert worst <= 3, worst
    v = "%d.%d" % sys.version_info[:2]
    s = BEGIN
    s += "/* Unicode %s case mapping as Python %s has it: str.upper, str.lower and str.title of every code point from 0x80 up. */\n" % (unicodedata.unidata_version, v)
    s += emit_rows("case_upper_rows", rows(ups))
    s += emit_rows("case_lower_rows", rows(lows))
    s += emit_rows("case_title_rows", rows(title_delta))
    s += emit_full("case_upper_full", upper_full)
    s += emit_full("case_lower_full", lower_full)
    s += emit_full("case_title_full", title_full)
    s += "static const uint32_t case_prop_runs[] = {\n"
    for i in range(0, len(props), 8):
        s += "    " + " ".join("0x%X," % (cp << 2 | f) for cp, f in props[i:i + 8]) + "\n"
    s += "};\n"
    return s + END


def main():
    args = sys.argv[1:]
    check = args[:1] == ["--check"]
    if check:
        args = args[1:]
    if len(args) != 1:
        sys.stderr.write(__doc__)
        return 2
    if unicodedata.unidata_version != "16.0.0":
        sys.stderr.write("gen_case_table.py needs a Python whose unicodedata is Unicode 16.0.0 (Python 3.14); this is Python %s with Unicode %s\n"
                         % (sys.version.split()[0], unicodedata.unidata_version))
        return 2
    path = args[0]
    text = open(path, encoding="utf-8").read()
    a, b = text.find(BEGIN), text.find(END)
    if a < 0 or b < 0:
        sys.stderr.write("%s: the BEGIN/END GENERATED CASE TABLES markers are missing\n" % path)
        return 2
    new = text[:a] + generate() + text[b + len(END):]
    if check:
        if new != text:
            sys.stderr.write("%s: the case tables are not what tools/gen_case_table.py makes: run it without --check\n" % path)
            return 1
        return 0
    open(path, "w", encoding="utf-8").write(new)
    return 0


sys.exit(main())
