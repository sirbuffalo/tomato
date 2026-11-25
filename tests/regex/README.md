# Regex oracle corpus

`cases.txt` contains one JSON object per line, generated with Python 3.14.4. Each row records the pattern, flags, subject, capture spans for match/search/fullmatch and finditer, whole-match and group findall results, split, and a substitution template and result. Unmatched captures use `[-1,-1]` in spans and empty strings in groups and split, as approved for Tomato. The `tests/programs/re_corpus.tom` runner reads this data without Python; it is registered in the test suite.

The corpus exercises common constructs, flags, Unicode text, empty matches, and several replacement references. It is a starting oracle, not a complete test of errors, limits, all supported syntax, callback substitution, or intentional differences between Tomato's character tables and Python's. Those need separate tests.
