// Checks site/editor.js (auto-indent in the playground editor) in a JS shell. Prints "ok" or what is wrong.
//   jsc tests/site_editor.js   (or on Linux: node native/jsc-on-node.js tests/site_editor.js)
load("site/editor.js");
var bad = [];
function key(text, k, shift) {   // "|" marks the caret, "[" and "]" a selection
  var s = text.indexOf("["), e = text.indexOf("]");
  if (s >= 0) { text = text.replace("[", "").replace("]", ""); e -= 1; } else { s = e = text.indexOf("|"); text = text.replace("|", ""); }
  var r = tomatoEditKey(text, s, e, k, shift);
  if (!r) return null;
  return r.value.slice(0, r.start) + (r.start === r.end ? "|" : "[") + r.value.slice(r.start, r.end) + (r.start === r.end ? "" : "]") + r.value.slice(r.end);
}
function eq(name, got, want) { if (got !== want) bad.push(name + ": got " + JSON.stringify(got) + " wanted " + JSON.stringify(want)); }
eq("def", key("@main\ndef main():|", "Enter"), "@main\ndef main():\n    |");
eq("comment after colon", key("if x:  # hi|", "Enter"), "if x:  # hi\n    |");
eq("nested", key("    for i in y:|", "Enter"), "    for i in y:\n        |");
eq("normal line", key("    x = 1|", "Enter"), "    x = 1\n    |");
eq("colon in comment", key("# note:|", "Enter"), "# note:\n|");
eq("return dedents", key("        return 1|", "Enter"), "        return 1\n    |");
eq("pass at top", key("pass|", "Enter"), "pass\n|");
eq("enter mid line", key("a|b", "Enter"), "a\n|b");
eq("enter replaces selection", key("if x:[ab]c", "Enter"), "if x:\n    |c");
eq("backspace indent", key("        |x", "Backspace"), "    |x");
eq("backspace odd indent", key("      |x", "Backspace"), "    |x");
eq("backspace after text", key("ab |", "Backspace"), null);
eq("backspace plain", key("a|", "Backspace"), null);
eq("tab", key("|x", "Tab"), "    |x");
eq("tab aligns", key("ab|", "Tab"), "ab  |");
eq("shift tab one line", key("        |x", "Tab", true), "    |x");
eq("indent selection", key("[a\nb]", "Tab"), "[    a\n    b]");
eq("dedent selection", key("[    a\n  b]", "Tab", true), "[a\nb]");
eq("indent skips blank", key("[a\n\nb]", "Tab"), "[    a\n\n    b]");
eq("return open paren", key("    return foo(|", "Enter"), "    return foo(\n    |");
eq("shift tab nothing to dedent", key("|x", "Tab", true), null);
eq("comment ending in colon", key("x = 1  # see:|", "Enter"), "x = 1  # see:\n|");
eq("colon in string", key("print(\"a #:\")|", "Enter"), "print(\"a #:\")\n|");
eq("other keys", key("a|", "x"), null);
print(bad.length ? bad.join("\n") : "ok");
