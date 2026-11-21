"""The editor support files (editors/vscode): valid JSON, every regex compiles, and the grammar names the language's keywords."""
import json
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VSCODE = os.path.join(ROOT, "editors", "vscode")


def load(*parts):
    with open(os.path.join(VSCODE, *parts), encoding="utf-8") as f:
        return json.load(f)


class Editors(unittest.TestCase):
    def test_json_files_parse(self):
        for parts in (("package.json",), ("language-configuration.json",), ("snippets", "tomato.json"),
                      ("syntaxes", "tomato.tmLanguage.json")):
            load(*parts)

    def test_every_grammar_regex_compiles(self):
        found = []

        def walk(o):
            if isinstance(o, dict):
                for k in ("match", "begin", "end"):
                    if k in o:
                        found.append(re.compile(o[k]))
                for v in o.values():
                    walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)
        walk(load("syntaxes", "tomato.tmLanguage.json"))
        self.assertGreater(len(found), 20)

    def test_grammar_covers_the_lexer_keywords(self):
        with open(os.path.join(ROOT, "python", "tomato", "lexer.py"), encoding="utf-8") as f:
            block = re.search(r"KEYWORDS = \{(.*?)\}", f.read(), re.S).group(1)
        words = set(re.findall(r'"(\w+)"', block))
        text = json.dumps(load("syntaxes", "tomato.tmLanguage.json"))
        for w in words:
            self.assertRegex(text, r"\b%s\b" % w, w)

    def test_extension_registers_tom_files(self):
        lang = load("package.json")["contributes"]["languages"][0]
        self.assertEqual(lang["extensions"], [".tom"])


if __name__ == "__main__":
    unittest.main()
