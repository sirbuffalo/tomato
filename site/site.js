// Shared header and a small Markdown renderer for the documentation pages.
(function () {
  var pages = [["index.html", "Home"], ["guide.html", "Guide"], ["docs.html", "Reference"], ["play.html", "Run & Repl"], ["download.html", "Download"]];
  var here = location.pathname.split("/").pop() || "index.html";
  var h = '<nav><a class="brand" href="index.html">🍅 Tomato</a>';
  pages.forEach(function (p) { h += '<a href="' + p[0] + '"' + (p[0] === here ? ' aria-current="page"' : "") + ">" + p[1] + "</a>"; });
  var el = document.getElementById("site-header");
  if (el) el.innerHTML = h + "</nav>";
  var v = document.getElementById("version");
  if (v) v.textContent = window.TOMATO_VERSION;
})();

function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
function inline(s) {
  s = esc(s);
  s = s.replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2">$1</a>');
  return s;
}
function markdown(src) {
  var out = [], lines = src.split("\n"), list = false, code = false, para = [];
  function flush() { if (para.length) { out.push("<p>" + inline(para.join(" ")) + "</p>"); para = []; } }
  function closeList() { if (list) { out.push("</ul>"); list = false; } }
  lines.forEach(function (l) {
    if (l.indexOf("```") === 0) { flush(); closeList(); out.push(code ? "</code></pre>" : "<pre><code>"); code = !code; return; }
    if (code) { out.push(esc(l)); return; }
    var m = /^(#{1,4}) (.*)$/.exec(l);
    if (m) {
      flush(); closeList();
      var id = m[2].toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
      out.push("<h" + m[1].length + ' id="' + id + '">' + inline(m[2]) + "</h" + m[1].length + ">");
      return;
    }
    if (/^\s*[-*] /.test(l)) { flush(); if (!list) { out.push("<ul>"); list = true; } out.push("<li>" + inline(l.replace(/^\s*[-*] /, "")) + "</li>"); return; }
    if (l.trim() === "") { flush(); closeList(); return; }
    para.push(l.trim());
  });
  flush(); closeList();
  return out.join("\n");
}
