"""Error codes for compiled programs (D34a, P37).

Normal mode prints `error CODE` where CODE is `E<kind>:<line>`, for example `E03:12`. `tomato explain CODE FILE`
decodes it against the source file into the full debug-style message. Release mode prints nothing.
The numbers are PROVISIONAL and may change until Davis decides the format.
"""
import re

KINDS = {
    1: ("overflow", "integer overflow: the result does not fit the integer type (D05e, D05n)"),
    2: ("division by zero", "division by zero (D05ab)"),
    3: ("modulo by zero", "modulo by zero (D05au)"),
    4: ("range step", "range step cannot be zero"),
    5: ("conversion", "integer conversion out of range for the destination type (D05p)"),
    6: ("missing return", "the function ended without returning a value"),
    7: ("index", "index out of range (D20a, D17c)"),
    8: ("class conversion", "the object is not an instance of that class (D12az, D12bh)"),
    9: ("duplicate key", "duplicate key in a dict literal"),
    10: ("key not found", "the key or element is not there (D20b)"),
    11: ("uncaught", "an error was raised and never caught (D22a)"),
    12: ("none", "None where a value is needed (D23b)"),
    13: ("file", "a file could not be opened (IOError)"),
    14: ("empty separator", "an empty text to search for or split on is not decided"),
}
BY_NAME = {name: code for code, (name, _) in KINDS.items()}
CODE = re.compile(r"^E(\d{2}):(\d+)$")


def code_for(kind):
    return BY_NAME[kind]


def explain(code, source):
    """Return the full readable text for CODE given the program's source text; raises ValueError for a bad code."""
    m = CODE.match(code.strip())
    if not m or int(m.group(1)) not in KINDS:
        raise ValueError("not a Tomato error code: %r (codes look like E03:12)" % code)
    kind, line = int(m.group(1)), int(m.group(2))
    lines = source.split("\n")
    out = ["error %s: %s" % (code.strip(), KINDS[kind][1])]
    if 1 <= line <= len(lines):
        text = lines[line - 1]
        out.append("  --> line %d" % line)
        out.append("   %d | %s" % (line, text))
        out.append("   %s | %s^" % (" " * len(str(line)), " " * (len(text) - len(text.lstrip()))))
    else:
        raise ValueError("line %d is not in this file (it has %d lines): is this the program the code came from?"
                         % (line, len(lines)))
    return "\n".join(out)
