// Shared header and a small Markdown renderer for the documentation pages.
(function () {
  var pages = [["index.html", "Home"], ["guide.html", "Guide"], ["docs.html", "Reference"], ["play.html", "Run & Repl"], ["download.html", "Download"]];
  var here = location.pathname.split("/").pop() || "index.html";
  var h = '<nav><a class="brand" href="index.html">🍅 Tomato</a>';
  pages.forEach(function (p) { h += '<a href="' + p[0] + '"' + (p[0] === here ? ' aria-current="page"' : "") + ">" + p[1] + "</a>"; });
  var el = document.getElementById("site-header");
  if (el) el.innerHTML = h + "</nav>";
  ["version", "version2"].forEach(function (id) { var v = document.getElementById(id); if (v) v.textContent = window.TOMATO_VERSION; });
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

// ---- syntax highlighting for <pre><code> blocks (same token classes as editors/vscode/syntaxes/tomato.tmLanguage.json)
(function () {
  var KW = /^(def|class|interface|implements|private|const|override|return|if|elif|else|while|for|in|pass|break|continue|try|catch|finally|raise|import|from|export|as|is|and|or|xor|not)$/;
  var TY = /^(int|uint|float|rational|bool|str|list|dict|set|tuple|File|range|Error|RuntimeError|IOError)$/;
  var BI = /^(print|len|str|int|float|rational|range|open)$/;
  var TOKEN = /(#[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(!?[A-Za-z_]\w*)|(->|\*\*|\/\/|==|!=|<=|>=|[-+*\/%<>=&|^])|(@\w+)/g;
  function highlight(src) {
    var out = "", last = 0, m;
    TOKEN.lastIndex = 0;
    while ((m = TOKEN.exec(src))) {
      out += esc(src.slice(last, m.index));
      var t = m[0], cls = "";
      if (m[1]) cls = "tk-c";
      else if (m[2]) cls = "tk-s";
      else if (m[3]) cls = "tk-n";
      else if (m[4]) {
        var after = src.charAt(m.index + t.length), word = t.replace(/^!/, "");
        if (t.charAt(0) === "!") cls = "tk-l";
        else if (/^(True|False|None)$/.test(t)) cls = "tk-k2";
        else if (KW.test(t)) cls = "tk-k";
        else if (BI.test(t) && after === "(") cls = "tk-b";
        else if (TY.test(t)) cls = "tk-t";
        else if (/\s*\(/.test(src.slice(m.index + t.length, m.index + t.length + 2)) || after === "(") cls = "tk-f";
        else if (/^[A-Z]/.test(word)) cls = "tk-t";
      } else if (m[5]) cls = "tk-o";
      else if (m[6]) cls = "tk-d";
      out += cls ? '<span class="' + cls + '">' + esc(t) + "</span>" : esc(t);
      last = m.index + t.length;
    }
    return out + esc(src.slice(last));
  }
  window.tomatoHighlight = highlight;
  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("pre > code").forEach(function (el) {
      if (el.className.indexOf("no-hl") < 0 && el.parentNode.id !== "out") el.innerHTML = highlight(el.textContent);
    });
  });
})();
