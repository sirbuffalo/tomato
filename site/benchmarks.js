// Draws the Benchmarks page from benchmarks.json: a summary, bar charts (plain CSS) and tables. No libraries.
(function () {
  var LANGS = [["tomato", "Tomato (release)"], ["tomato-debug", "Tomato (debug)"], ["rust", "Rust"], ["go", "Go"], ["python", "Python"]];
  function $(id) { return document.getElementById(id); }
  function fmt(s) { return s >= 10 ? s.toFixed(1) : s >= 1 ? s.toFixed(2) : s >= 0.1 ? s.toFixed(3) : s.toFixed(3); }
  function ratio(r) { return r >= 100 ? r.toFixed(0) : r >= 10 ? r.toFixed(1) : r.toFixed(2); }
  function mb(b) { return b >= 1e9 ? (b / 1e9).toFixed(2) + " GB" : b >= 1e6 ? (b / 1e6).toFixed(1) + " MB" : (b / 1e3).toFixed(0) + " KB"; }
  function kb(b) { return b >= 1e6 ? (b / 1e6).toFixed(1) + " MB" : (b / 1e3).toFixed(0) + " KB"; }
  function el(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function geomean(xs) { return Math.exp(xs.reduce(function (a, x) { return a + Math.log(x); }, 0) / xs.length); }

  fetch("benchmarks.json").then(function (r) { return r.json(); }).then(function (d) {
    var m = d.machine, v = d.versions;
    var langs = LANGS.filter(function (l) { return d.benchmarks[0].results[l[0]]; });
    $("meta").textContent = m.cpu + ", " + m.cores + " cores, " + m.memory + ", " + m.os + ". Tomato v" + v.tomato + ", " + (v.go || "") + ", " + (v.rust || "") + ", " + (v.python || "") + ". Median of " + d.runs + " runs (" + d.python_runs + " for Python)" + (d.seed != null ? ", all runs in one shuffled order (seed " + d.seed + ")" : "") + ", measured " + d.date.slice(0, 10) + "; load average before " + d.load_before + ", after " + d.load_after + ".";
    var b0debug = !!d.benchmarks[0].results["tomato-debug"];
    var cm = $("commands");
    langs.forEach(function (l) { if (d.commands[l[0]]) cm.appendChild(el("li", "", "<strong>" + l[1] + ":</strong> <code>" + d.commands[l[0]] + "</code>")); });
    var lg = $("legend");
    langs.forEach(function (l) { lg.appendChild(el("span", "", '<i class="lang-' + l[0] + '"></i>' + l[1])); });

    // every comparison is Tomato (release) time divided by the other program's time: below 1.0 Tomato is faster
    function tr(b, r) { return b.results.tomato.median / r.median; }
    var others = langs.filter(function (l) { return l[0] !== "tomato" && l[0] !== "tomato-debug"; });

    // summary: per other language, the geometric mean of Tomato's time divided by its time, and where Tomato is faster
    var sum = $("summary"), t = '<div class="table-wrap"><table><thead><tr><th>Compared with</th><th class="num">Tomato ÷ it, geometric mean</th><th class="num">Benchmarks where Tomato is faster</th></tr></thead><tbody>';
    others.forEach(function (l) {
      var rs = d.benchmarks.map(function (b) { return tr(b, b.results[l[0]]); });
      var wins = rs.filter(function (x) { return x < 1; }).length;
      t += "<tr><td>" + l[1] + '</td><td class="num">' + ratio(geomean(rs)) + '</td><td class="num">' + wins + " of " + d.benchmarks.length + "</td></tr>";
    });
    sum.innerHTML = t + "</tbody></table></div><p class=\"status\">Each number is Tomato's time (release mode) divided by the other language's time, so below 1.0 Tomato is faster and above 1.0 it is slower. The geometric mean treats a ratio of 2 and of 0.5 alike, so one extreme benchmark does not dominate.</p>";

    // bar charts, one per benchmark
    var ch = $("charts");
    d.benchmarks.forEach(function (b) {
      var max = Math.max.apply(null, langs.map(function (l) { return b.results[l[0]].median; }));
      var box = el("div", "bench-chart"); box.setAttribute("role", "img");
      box.setAttribute("aria-label", b.name + ": " + langs.map(function (l) { return l[1] + " " + fmt(b.results[l[0]].median) + " seconds"; }).join(", "));
      box.appendChild(el("h3", "", b.name + ' <span class="status">input ' + b.input + "</span>"));
      langs.forEach(function (l) {
        var r = b.results[l[0]], row = el("div", "bench-row");
        row.appendChild(el("span", "", l[1]));
        var track = el("div", "bench-track"), fill = el("div", "bench-fill lang-" + l[0]);
        fill.style.width = Math.max(0.5, 100 * r.median / max) + "%"; track.appendChild(fill); row.appendChild(track);
        row.appendChild(el("span", "bench-val", fmt(r.median) + " s"));
        box.appendChild(row);
      });
      if (b.extra) Object.keys(b.extra).forEach(function (k) {
        var x = b.extra[k], what = d.commands[k] || k;
        box.appendChild(el("p", "status", "Also measured, not in the table: " + what + ", " + fmt(x.median) + " s; Tomato ÷ it is " + ratio(tr(b, x)) + "." + (b.name === "sort" ? " Tomato's <code>sorted</code> is an introsort, so this is not a like-for-like comparison: it shows the headroom a radix special case for plain int lists would give." : "")));
      });
      ch.appendChild(box);
    });

    // table: median seconds (fastest in bold), with the fastest run and the spread
    var h = '<table><thead><tr><th>Benchmark</th><th class="num">Input</th>';
    langs.forEach(function (l) { h += '<th class="num">' + l[1] + " (s)</th>"; });
    h += "</tr></thead><tbody>";
    d.benchmarks.forEach(function (b) {
      var best = Math.min.apply(null, langs.map(function (l) { return b.results[l[0]].median; }));
      h += "<tr><td>" + b.name + '</td><td class="num">' + b.input + "</td>";
      langs.forEach(function (l) {
        var r = b.results[l[0]];
        h += '<td class="num' + (r.median === best ? " best" : "") + '">' + fmt(r.median) + ' <small class="status"><br>min ' + fmt(r.min) + ", spread " + Math.round(100 * (r.max - r.min) / r.median) + "%</small></td>";
      });
      h += "</tr>";
    });
    $("table").innerHTML = h + "</tbody></table>";

    // Tomato (release and debug) divided by each other language, per benchmark
    h = '<table><thead><tr><th>Benchmark</th>';
    others.forEach(function (l) { h += '<th class="num">Tomato ÷ ' + l[1] + "</th>"; });
    if (b0debug) others.forEach(function (l) { h += '<th class="num">Tomato debug ÷ ' + l[1] + "</th>"; });
    h += "</tr></thead><tbody>";
    d.benchmarks.forEach(function (b) {
      h += "<tr><td>" + b.name + "</td>";
      others.forEach(function (l) { var x = tr(b, b.results[l[0]]); h += '<td class="num' + (x < 1 ? " best" : "") + '">' + ratio(x) + "</td>"; });
      if (b0debug) others.forEach(function (l) { h += '<td class="num">' + ratio(b.results["tomato-debug"].median / b.results[l[0]].median) + "</td>"; });
      h += "</tr>";
    });
    $("ratios").innerHTML = h + "</tbody></table>";

    // build time, binary size, peak memory
    h = '<table><thead><tr><th>Benchmark</th>';
    langs.forEach(function (l) { h += '<th class="num">' + l[1] + "</th>"; });
    h += "</tr></thead><tbody>";
    d.benchmarks.forEach(function (b) {
      h += "<tr><td>" + b.name + "</td>";
      langs.forEach(function (l) {
        var r = b.results[l[0]];
        h += '<td class="num">' + (r.build_seconds != null ? r.build_seconds.toFixed(2) + " s build, " + kb(r.binary_bytes) + "<br>" : "no build<br>") + mb(r.peak_memory_bytes) + " peak</td>";
      });
      h += "</tr>";
    });
    $("build").innerHTML = h + "</tbody></table>";
  }).catch(function () { $("meta").textContent = "The results could not be loaded."; });
})();
