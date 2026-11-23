// Checks site/site.js's tomatoErrors (the playground's colored errors) in JavaScriptCore: the words are the plain text, escaped, so the
// text of the HTML (tags removed, entities decoded) equals the input, and the colors come from classes. Prints "ok" or what is wrong.
//   jsc tests/site_errors.js   (or on Linux: node native/jsc-on-node.js tests/site_errors.js)
var window = globalThis, location = { pathname: "x.html" };
var el = function () { return { appendChild: function () {}, addEventListener: function () {} }; };
var document = { querySelector: function () { return null; }, getElementById: function () { return null; }, querySelectorAll: function () { return []; }, addEventListener: function () {}, createElement: el, head: el() };
load("site/site.js");
function text(html) { return html.replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&"); }
var plain = "error: name 'x<y' is not defined & more\n --> program.tom:3:11\n  |\n3 |     print(a<b)\n  |           ^^^^\n  = help: did you mean '<script>'?\n  at half (line 6)\nwarning: the variable 'u' is never used\n 4 |   u = 1\n  |   ^";
var html = tomatoErrors(plain), bad = [];
if (text(html) !== plain) bad.push("text differs: " + text(html));
if (html.indexOf("<script>") >= 0 || html.indexOf("a<b") >= 0) bad.push("not escaped");
["e-label e-error", "e-msg", "e-arrow", "e-loc", "e-gutter", "e-caret e-error", "e-helplabel", "e-help", "e-trace", "e-label e-warning", "e-caret e-warning"].forEach(function (c) { if (html.indexOf('class="' + c + '"') < 0) bad.push("missing class " + c); });
print(bad.length ? bad.join("; ") : "ok");
