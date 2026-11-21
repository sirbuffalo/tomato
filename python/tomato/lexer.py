from .errors import TomatoError

KEYWORDS = {
    "def", "class", "interface", "implements", "private", "const", "override",
    "return", "if", "elif", "else", "while", "for", "in", "pass", "break", "continue", "try", "catch", "finally",
    "raise", "import", "from", "export", "as", "is", "and", "or", "xor", "not",
    "True", "False",
}
SIMPLE_ESC = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", "'": "'", '"': '"'}
TWO = {"==", "!=", "<=", ">=", "->", "**", "//"}
ONE = set("+-*/%<>=()[]{}:,.@!|&^")


class Tok:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind, self.value, self.line = kind, value, line

    def __repr__(self):
        return "Tok(%s,%r,%d)" % (self.kind, self.value, self.line)


def lex(src):
    toks = []
    indents = [0]
    depth = 0
    lines = src.split("\n")
    for ln, raw in enumerate(lines, 1):
        i, n = 0, len(raw)
        if depth == 0:
            width = 0
            while i < n and raw[i] in " ":
                i += 1
                width += 1
            if i < n and raw[i] == "\t":
                raise TomatoError("tabs are not allowed for indentation (not yet decided)", ln)
            if i >= n or raw[i] == "#":
                continue
            if width > indents[-1]:
                indents.append(width)
                toks.append(Tok("INDENT", None, ln))
            while width < indents[-1]:
                indents.pop()
                toks.append(Tok("DEDENT", None, ln))
                if width > indents[-1]:
                    raise TomatoError("inconsistent indentation", ln)
        while i < n:
            c = raw[i]
            if c == " ":
                i += 1
            elif c == "#":
                break
            elif c.isdigit():
                j = i
                while j < n and raw[j].isdigit():
                    j += 1
                is_float = False
                if j + 1 < n and raw[j] == "." and raw[j + 1].isdigit():       # 1.5 (P55)
                    is_float = True
                    j += 1
                    while j < n and raw[j].isdigit():
                        j += 1
                if j < n and raw[j] in "eE":                                    # 2e3, 1.5e-3
                    k = j + 1
                    if k < n and raw[k] in "+-":
                        k += 1
                    if k < n and raw[k].isdigit():
                        while k < n and raw[k].isdigit():
                            k += 1
                        is_float, j = True, k
                if j < n and (raw[j].isalpha() or raw[j] in "._"):
                    raise TomatoError("a number is whole digits, digits.digits, or either with an exponent like 2e3", ln)
                if is_float:
                    toks.append(Tok("FLOAT", float(raw[i:j]), ln))
                else:
                    toks.append(Tok("INT", int(raw[i:j]), ln))
                i = j
            elif c.isalpha() or c == "_":
                j = i
                while j < n and (raw[j].isalnum() or raw[j] == "_"):
                    j += 1
                w = raw[i:j]
                toks.append(Tok("KW" if w in KEYWORDS else "NAME", w, ln))
                i = j
            elif c in "\"'":
                j = i + 1
                buf = []
                while j < n and raw[j] != c:
                    if raw[j] == "\\":
                        j += 1
                        if j >= n:
                            break
                        e = raw[j]
                        if e in SIMPLE_ESC:
                            buf.append(SIMPLE_ESC[e])
                        elif e == "u" and raw[j + 1:j + 2] == "{":
                            k = raw.find("}", j)
                            try:
                                cp = int(raw[j + 2:k], 16)
                                buf.append(chr(cp))
                            except (ValueError, OverflowError):
                                raise TomatoError("bad \\u{...} escape", ln)
                            if k < 0 or 0xD800 <= cp <= 0xDFFF:
                                raise TomatoError("bad \\u{...} escape (surrogates are not Unicode characters)", ln)
                            j = k
                        else:
                            raise TomatoError("unknown escape \\%s" % e, ln)
                    else:
                        buf.append(raw[j])
                    j += 1
                if j >= n:
                    raise TomatoError("unterminated string", ln)
                toks.append(Tok("STR", "".join(buf), ln))
                i = j + 1
            elif raw[i:i + 2] in TWO:
                toks.append(Tok("OP", raw[i:i + 2], ln))
                i += 2
            elif c in ONE:
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth -= 1
                toks.append(Tok("OP", c, ln))
                i += 1
            else:
                raise TomatoError("unexpected character %r" % c, ln)
        if depth == 0:
            toks.append(Tok("NEWLINE", None, ln))
    if depth != 0:
        raise TomatoError("unclosed bracket", len(lines))
    while len(indents) > 1:
        indents.pop()
        toks.append(Tok("DEDENT", None, len(lines)))
    toks.append(Tok("EOF", None, len(lines)))
    return toks
