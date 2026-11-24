// Auto-indent for the playground's editor and repl input. The functions are pure (text and selection in, text and selection out) so tests/site_editor.js can run them in a JS shell.
var TOMATO_INDENT = "    ";
// the line without a trailing # comment (a # inside a string stays)
function tomatoCode(line) {
  var q = "";
  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (q) { if (c === "\\") i++; else if (c === q) q = ""; }
    else if (c === '"' || c === "'") q = c;
    else if (c === "#") return line.slice(0, i);
  }
  return line;
}
function tomatoOpensBlock(line) { return /:\s*$/.test(tomatoCode(line)); }
// not when the statement continues on the next line (a trailing open bracket, comma or backslash)
function tomatoLeavesBlock(line) { return /^\s*(return|break|continue|pass|raise)\b(?!.*[(\[{,\\]\s*$)/.test(line); }
function tomatoIndentOf(line) { return /^ */.exec(line)[0]; }
// The indent a new line gets after `line`: the same, plus one level after a line that opens a block, minus one after return/break/continue/pass/raise.
function tomatoNextIndent(line) {
  var ind = tomatoIndentOf(line);
  if (tomatoOpensBlock(line)) return ind + TOMATO_INDENT;
  if (tomatoLeavesBlock(line) && ind.length >= TOMATO_INDENT.length) return ind.slice(TOMATO_INDENT.length);
  return ind;
}
// Handle one key in a text box. Returns {value, start, end} for the new text and selection, or null to leave the key to the browser.
function tomatoEditKey(value, start, end, key, shift) {
  var lineStart = value.lastIndexOf("\n", start - 1) + 1;
  if (key === "Enter" && !shift) {
    var line = value.slice(lineStart, start), ind = tomatoNextIndent(line);
    var ins = "\n" + ind;
    return { value: value.slice(0, start) + ins + value.slice(end), start: start + ins.length, end: start + ins.length };
  }
  if (key === "Backspace" && start === end && start > lineStart && /^ +$/.test(value.slice(lineStart, start))) {
    var n = start - lineStart, cut = n % TOMATO_INDENT.length || TOMATO_INDENT.length;
    return { value: value.slice(0, start - cut) + value.slice(end), start: start - cut, end: start - cut };
  }
  if (key === "Tab") {
    var multi = value.slice(start, end).indexOf("\n") >= 0;
    if (!shift && !multi) {
      var pad = TOMATO_INDENT.slice(0, TOMATO_INDENT.length - (start - lineStart) % TOMATO_INDENT.length);
      return { value: value.slice(0, start) + pad + value.slice(end), start: start + pad.length, end: start + pad.length };
    }
    // indent or dedent every line the selection touches
    var endAt = end > start && value[end - 1] === "\n" ? end - 1 : end;
    var lastEnd = value.indexOf("\n", endAt); if (lastEnd < 0) lastEnd = value.length;
    var lines = value.slice(lineStart, lastEnd).split("\n"), s = start, e = end, first = true;
    lines = lines.map(function (l, i) {
      var d;
      if (!shift) { d = TOMATO_INDENT.length; if (l === "") d = 0; else l = TOMATO_INDENT + l; }
      else { var m = /^ {1,4}/.exec(l); d = m ? -m[0].length : 0; if (m) l = l.slice(m[0].length); }
      if (first) { if (s > lineStart) s = Math.max(lineStart, s + d); first = false; }
      e += d; return l;
    });
    var nv = value.slice(0, lineStart) + lines.join("\n") + value.slice(lastEnd);
    if (nv === value) return null;   // nothing to dedent: leave Shift+Tab to the browser so focus can move on
    return { value: nv, start: s, end: Math.max(s, e) };
  }
  return null;
}
// Wire a textarea or input to tomatoEditKey. multiline: Enter keeps the indent (the textarea); false: only Tab and Backspace (the repl line, see play.html).
function tomatoAttachEditor(el, onChange, enabled) {
  el.addEventListener("keydown", function (e) {
    if (e.ctrlKey || e.metaKey || e.altKey || e.isComposing) return;
    if (enabled && !enabled(e)) return;
    var r = tomatoEditKey(el.value, el.selectionStart, el.selectionEnd, e.key, e.shiftKey);
    if (!r) return;
    e.preventDefault();
    // replace only the changed range through the browser's editing command, so Ctrl+Z still undoes it; assign the value if that is unavailable
    var a = el.value, b = r.value, p = 0, q = 0;
    while (p < a.length && p < b.length && a[p] === b[p]) p++;
    while (q < a.length - p && q < b.length - p && a[a.length - 1 - q] === b[b.length - 1 - q]) q++;
    el.setSelectionRange(p, a.length - q);
    var piece = b.slice(p, b.length - q), done = false;
    try { done = piece ? document.execCommand("insertText", false, piece) : document.execCommand("delete"); } catch (x) {}
    if (!done || el.value !== b) el.value = b;
    el.setSelectionRange(r.start, r.end);
    if (onChange) onChange();
  });
}
