// Shared header and a small Markdown renderer for the documentation pages.
(function () {
  var pages = [["index.html", "Home"], ["guide.html", "Guide"], ["docs.html", "Reference"], ["play.html", "Run & Repl"], ["benchmarks.html", "Benchmarks"], ["download.html", "Download"]];
  var here = location.pathname.split("/").pop() || "index.html";
  var h = '<a class="skip" href="#main">Skip to content</a><nav aria-label="Site"><a class="brand" href="index.html"><img src="assets/tomato-logo-full.svg" alt="Tomato" width="138" height="40"></a><div class="links">';
  pages.forEach(function (p) { h += '<a href="' + p[0] + '"' + (p[0] === here ? ' aria-current="page"' : "") + ">" + p[1] + "</a>"; });
  var main = document.querySelector("main"); if (main && !main.id) main.id = "main";
  var el = document.getElementById("site-header");
  if (el) el.innerHTML = h + "</div></nav>";
  ["version", "version2"].forEach(function (id) { var v = document.getElementById(id); if (v) v.textContent = window.TOMATO_VERSION; });
})();

function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
// A link to another document of the reference (decisions.md, specification.md#x) becomes a link inside the Reference page.
var DOC_KEYS = { "specification.md": "specification", "decisions.md": "decisions", "decision-inventory.md": "decision-inventory", "open-questions.md": "open-questions", "provisional.md": "provisional", "PROVISIONAL.md": "provisional" };
function linkTarget(u) {
  if (/^https?:/.test(u)) return u;
  var name = u.split("#")[0];
  return DOC_KEYS[name] ? "docs.html#" + DOC_KEYS[name] : null;
}
function inline(s) {
  var codes = [];
  s = s.replace(/`([^`]+)`/g, function (_, c) { codes.push(c); return "\u0000" + (codes.length - 1) + "\u0000"; });
  s = esc(s);
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>").replace(/(^|[^*\w])\*([^*\s][^*]*)\*(?![*\w])/g, "$1<em>$2</em>");
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (m, text, url) {
    var t = linkTarget(url.replace(/&amp;/g, "&"));
    return t ? '<a href="' + t + '">' + text + "</a>" : text;
  });
  return s.replace(/\u0000(\d+)\u0000/g, function (_, i) { return "<code>" + esc(codes[+i]) + "</code>"; });
}
function splitRow(l) {
  var cells = [], cur = "";
  l = l.trim().replace(/^\|/, "").replace(/\|$/, "");
  for (var i = 0; i < l.length; i++) {
    if (l[i] === "\\" && l[i + 1] === "|") { cur += "|"; i++; }
    else if (l[i] === "|") { cells.push(cur.trim()); cur = ""; }
    else cur += l[i];
  }
  cells.push(cur.trim());
  return cells;
}
function markdown(src) {
  var out = [], lines = src.split("\n"), list = "", code = false, para = [], table = null, quote = [];
  function flush() { if (para.length) { out.push("<p>" + inline(para.join(" ")) + "</p>"); para = []; } }
  function closeList() { if (list) { out.push("</" + list + ">"); list = ""; } }
  function closeTable() {
    if (!table) return;
    var h = "<div class=\"table-wrap\"><table><thead><tr>" + table.head.map(function (c) { return "<th>" + inline(c) + "</th>"; }).join("") + "</tr></thead><tbody>";
    table.rows.forEach(function (r) { h += "<tr>" + r.map(function (c) { return "<td>" + inline(c) + "</td>"; }).join("") + "</tr>"; });
    out.push(h + "</tbody></table></div>"); table = null;
  }
  function closeQuote() { if (quote.length) { out.push("<blockquote>" + inline(quote.join(" ")) + "</blockquote>"); quote = []; } }
  function closeAll() { flush(); closeList(); closeTable(); closeQuote(); }
  lines.forEach(function (l, i) {
    if (l.indexOf("```") === 0) { closeAll(); out.push(code ? "</code></pre>" : "<pre><code>"); code = !code; return; }
    if (code) { out.push(esc(l)); return; }
    if (/^\s*\|.*\|\s*$/.test(l)) {
      flush(); closeList(); closeQuote();
      var cells = splitRow(l);
      if (!table) table = { head: cells, rows: [], sep: false };
      else if (!table.sep && cells.every(function (c) { return /^:?-{2,}:?$/.test(c); })) table.sep = true;
      else table.rows.push(cells);
      return;
    }
    closeTable();
    var m = /^(#{1,6}) (.*)$/.exec(l);
    if (m) {
      closeAll();
      var id = m[2].toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
      out.push("<h" + m[1].length + ' id="' + id + '">' + inline(m[2]) + "</h" + m[1].length + ">");
      return;
    }
    var q = /^>\s?(.*)$/.exec(l);
    if (q) { flush(); closeList(); quote.push(q[1]); return; }
    closeQuote();
    if (/^---+\s*$/.test(l)) { closeAll(); out.push("<hr>"); return; }
    var li = /^\s*(?:([-*])|(\d+)\.) (.*)$/.exec(l);
    if (li) { flush(); var kind = li[2] ? "ol" : "ul"; if (list !== kind) { closeList(); out.push("<" + kind + ">"); list = kind; } out.push("<li>" + inline(li[3]) + "</li>"); return; }
    if (l.trim() === "") { flush(); closeList(); return; }
    closeList();
    para.push(l.trim());
  });
  closeAll();
  return out.join("\n");
}

// ---- syntax highlighting for <pre><code> blocks (same token classes as editors/vscode/syntaxes/tomato.tmLanguage.json)
(function () {
  var KW = /^(def|class|interface|implements|private|const|override|return|if|elif|else|while|for|in|pass|break|continue|try|catch|finally|raise|assert|yield|import|from|export|async|await|as|is|and|or|xor|not)$/;
  var MOD = /^(asyncio|base64|cache|csv|datetime|hex|hashlib|hmac|html|io|itertools|json|lineedit|math|os|ospath|random|rational|re|requests|secrets|socket|statistics|struct|sys|terminal|testing|textwrap|time|toml|urlparse|utf8|uuid|zlib)$/;
  var TY = /^(int|uint|float|rational|bool|str|list|dict|set|tuple|File|range|Error|RuntimeError|IOError|FileNotFoundError|FileExistsError|PermissionError|IsADirectoryError|NotADirectoryError|IndexError|KeyError|ValueError|ZeroDivisionError|OverflowError|EOFError|CancelledError|Sized|bitarray|frozenbitarray)$/;
  var BI = /^(print|len|str|int|float|rational|range|open|input|sleep|clock|min|max|sum|abs|chr|ord|round|divmod|any|all|hash|sorted|reversed|enumerate|zip|map|filter|list|dict|set|tuple|bool)$/;
  var TOKEN = /(#[^\n]*)|((?:\bf)?(?:"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))|(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(!?[A-Za-z_]\w*)|(->|\*\*|\/\/|==|!=|<=|>=|[-+*\/%<>=&|^])|(@\w+)/g;
  // an f-string: the text is a string, each {expression} is highlighted as code, and a format spec after the colon ({x:>8.2f}) is a number-like part
  var FEXPR = /^((?:[^:\[\(\{'"]|\[[^\]]*\]|\([^)]*\)|'[^']*'|"[^"]*")*)(:[^]*)?$/;
  function fstring(t) {
    var out = "", text = "", i = 1, s = function (x) { return x ? '<span class="tk-s">' + esc(x) + "</span>" : ""; };
    text = "f";
    while (i < t.length) {
      var c = t.charAt(i), two = t.substr(i, 2);
      if (c === "\\") { text += t.substr(i, 2); i += 2; }
      else if (two === "{{" || two === "}}") { text += two; i += 2; }
      else if (c === "{") {
        var depth = 1, j = i + 1;
        while (j < t.length && depth > 0) { var d = t.charAt(j); if (d === "{") depth++; else if (d === "}") depth--; j++; }
        if (depth > 0) { text += t.slice(i); i = t.length; break; }
        var inner = t.slice(i + 1, j - 1), parts = FEXPR.exec(inner) || [inner, inner, ""];
        out += s(text) + '<span class="tk-o">{</span>' + highlight(parts[1]) + (parts[2] ? '<span class="tk-n">' + esc(parts[2]) + "</span>" : "") + '<span class="tk-o">}</span>';
        text = ""; i = j;
      } else { text += c; i++; }
    }
    return out + s(text);
  }
  function highlight(src) {
    var out = "", last = 0, m, re = new RegExp(TOKEN.source, "g");   // its own copy: an f-string field calls highlight again
    while ((m = re.exec(src))) {
      out += esc(src.slice(last, m.index));
      var t = m[0], cls = "";
      if (m[1]) cls = "tk-c";
      else if (m[2] && t.charAt(0) === "f") { out += fstring(t); last = m.index + t.length; continue; }
      else if (m[2]) cls = "tk-s";
      else if (m[3]) cls = "tk-n";
      else if (m[4]) {
        var after = src.charAt(m.index + t.length), word = t.replace(/^!/, "");
        if (t.charAt(0) === "!") cls = "tk-l";
        else if (/^(True|False|None)$/.test(t)) cls = "tk-k2";
        else if (KW.test(t) || t === "self") cls = "tk-k";
        else if ((t === "start" || t === "yields") && /^\s+(?!(?:in|is|and|or|xor|not|if|else|for|as)\b)[A-Za-z_]/.test(src.slice(m.index + t.length, m.index + t.length + 40))) cls = "tk-k";
        else if (MOD.test(t) && /\b(?:import|from)\s+$/.test(src.slice(Math.max(0, m.index - 20), m.index))) cls = "tk-t";
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
  // Error text (docs/errors.md) as HTML: the same layout as the terminal, with a span per part so the style sheet can color it. The words
  // are the plain text escaped, so copying the output gives what the command line prints.
  function errors(text) {
    var kind = "error";
    return String(text).split("\n").map(function (l) {
      var m;
      if ((m = /^(error|warning)(\[E\d+\])?: (.*)$/.exec(l))) { kind = m[1]; return '<span class="e-label e-' + m[1] + '">' + m[1] + (m[2] || "") + ':</span> <span class="e-msg">' + esc(m[3]) + "</span>"; }
      if ((m = /^( *)--> (.*)$/.exec(l))) return esc(m[1]) + '<span class="e-arrow">--&gt;</span> <span class="e-loc">' + esc(m[2]) + "</span>";
      if ((m = /^( *[0-9]* \|)(.*)$/.exec(l))) { var c = /^( *)(\^+)$/.exec(m[2]); return '<span class="e-gutter">' + esc(m[1]) + "</span>" + (c ? esc(c[1]) + '<span class="e-caret e-' + kind + '">' + c[2] + "</span>" : esc(m[2])); }
      if ((m = /^( *)= help: (.*)$/.exec(l))) return esc(m[1]) + '<span class="e-gutter">=</span> <span class="e-helplabel">help:</span> <span class="e-help">' + esc(m[2]) + "</span>";
      if (/^ {2}(at |\.\.\. and )/.test(l)) return '<span class="e-trace">' + esc(l) + "</span>";
      return esc(l);
    }).join("\n");
  }
  window.tomatoErrors = errors;
  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("pre > code").forEach(function (el) {
      if (el.className.indexOf("no-hl") < 0 && el.parentNode.id !== "out") el.innerHTML = highlight(el.textContent);
    });
  });
})();
