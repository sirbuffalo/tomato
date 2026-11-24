// Draws the Benchmarks page from benchmarks.json: a summary, bar charts (plain CSS) and tables. No libraries. A checkbox per
// language chooses which languages are shown; the choice is kept in this browser.
(function () {
  // the key in benchmarks.json, the name, and whether it is shown until someone changes the boxes
  var LANGS = [["tomato", "Tomato (release)", true], ["tomato-debug", "Tomato (debug)", false], ["rust", "Rust", true], ["go", "Go", true], ["c", "C", true], ["cpp", "C++", false],
    ["java", "Java", false], ["csharp", "C#", false], ["swift", "Swift", false], ["javascript", "JavaScript", true], ["typescript", "TypeScript", false], ["php", "PHP", false], ["python", "Python", true]];
  var KEY = "tomato-bench-langs";
  function $(id) { return document.getElementById(id); }
  function fmt(s) { return s >= 10 ? s.toFixed(1) : s >= 1 ? s.toFixed(2) : s >= 0.1 ? s.toFixed(3) : s.toFixed(3); }
  function ratio(r) { return r >= 100 ? r.toFixed(0) : r >= 10 ? r.toFixed(1) : r.toFixed(2); }
  function mb(b) { return b >= 1e9 ? (b / 1e9).toFixed(2) + " GB" : b >= 1e6 ? (b / 1e6).toFixed(1) + " MB" : (b / 1e3).toFixed(0) + " KB"; }
  function kb(b) { return b >= 1e6 ? (b / 1e6).toFixed(1) + " MB" : (b / 1e3).toFixed(0) + " KB"; }
  function el(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function geomean(xs) { return Math.exp(xs.reduce(function (a, x) { return a + Math.log(x); }, 0) / xs.length); }

  fetch("benchmarks.json").then(function (r) { return r.json(); }).then(function (d) {
    var m = d.machine, v = d.versions;
    var all = LANGS.filter(function (l) { return d.benchmarks.some(function (b) { return b.results[l[0]]; }); });
    var tools = [v.go, v.rust, v.clang, v.java, v.csharp && ".NET " + v.csharp, v.swift, v.node && "Node " + v.node, v.php, v.python].filter(Boolean);
    $("meta").textContent = [m.cpu, m.cores + " logical CPUs", m.memory, m.os].filter(Boolean).join(", ") + ". Tomato v" + v.tomato + ", " + tools.join(", ") + ". Median of " + d.runs + " runs (" + d.python_runs + " for Python and PHP)" + (d.seed != null ? ", all runs in one shuffled order (seed " + d.seed + ")" : "") + ", measured " + d.date.slice(0, 10) + "; load average before " + d.load_before + ", after " + d.load_after + ".";
    var cm = $("commands");
    all.forEach(function (l) { if (d.commands[l[0]]) cm.appendChild(el("li", "", "<strong>" + l[1] + ":</strong> <code>" + d.commands[l[0]] + "</code>")); });

    // which languages are ticked: what this browser remembers, else the defaults. Tomato (release) is always shown: every
    // comparison is against it.
    var on = {}, saved = null;
    try { saved = JSON.parse(localStorage.getItem(KEY)); } catch (e) { saved = null; }
    all.forEach(function (l) { on[l[0]] = l[0] === "tomato" || (saved && typeof saved[l[0]] === "boolean" ? saved[l[0]] : l[2]); });
    var lg = $("legend"), pills = [];
    function save() {
      try { localStorage.setItem(KEY, JSON.stringify(on)); } catch (e) { /* the choice just is not remembered */ }
      pills.forEach(function (p) { p.box.checked = on[p.key]; p.label.classList.toggle("off", !on[p.key]); });
      draw();
    }
    all.forEach(function (l) {
      var label = el("label", "lang-pill" + (l[0] === "tomato" ? " fixed" : "") + (on[l[0]] ? "" : " off")), box = document.createElement("input");
      box.type = "checkbox"; box.checked = on[l[0]]; box.disabled = l[0] === "tomato"; box.value = l[0];
      if (l[0] === "tomato") label.title = "Always shown: every comparison is against it";
      box.addEventListener("change", function () { on[l[0]] = box.checked; save(); });
      label.appendChild(box);
      label.appendChild(el("span", "box lang-" + l[0], '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 6.4 4.8 9.2 10 3.2"/></svg>'));
      var name = el("span", "name"); name.textContent = l[1]; name.dataset.name = l[1];
      label.appendChild(name);
      lg.appendChild(label);
      pills.push({ key: l[0], box: box, label: label });
    });
    var quick = el("span", "lang-pills-do");
    [["All", function () { return true; }], ["Reset", function (l) { return l[2]; }]].forEach(function (b) {
      var button = el("button", "", b[0]); button.type = "button";
      button.addEventListener("click", function () { all.forEach(function (l) { on[l[0]] = l[0] === "tomato" || b[1](l); }); save(); });
      quick.appendChild(button);
    });
    lg.appendChild(quick);
    draw();

    // a benchmark need not be written in every language: the ticked ones that have a result for it
    function has(b, ls) { return ls.filter(function (l) { return b.results[l[0]]; }); }

    function draw() {
    var chosen = all.filter(function (l) { return on[l[0]]; }), langs = chosen;
    $("charts").textContent = "";

    // every comparison is Tomato (release) time divided by the other program's time: below 1.0 Tomato is faster
    function tr(b, r) { return b.results.tomato.median / r.median; }
    var others = langs.filter(function (l) { return l[0] !== "tomato" && l[0] !== "tomato-debug"; });

    // summary: per other language, the geometric mean of Tomato's time divided by its time, and where Tomato is faster
    var sum = $("summary"), t = '<div class="table-wrap"><table><thead><tr><th>Compared with</th><th class="num">Tomato ÷ it, geometric mean</th><th class="num">Benchmarks where Tomato is faster</th></tr></thead><tbody>';
    others.forEach(function (l) {
      var rs = d.benchmarks.filter(function (b) { return b.results[l[0]]; }).map(function (b) { return tr(b, b.results[l[0]]); });
      var wins = rs.filter(function (x) { return x < 1; }).length;
      t += "<tr><td>" + l[1] + '</td><td class="num">' + ratio(geomean(rs)) + '</td><td class="num">' + wins + " of " + rs.length + "</td></tr>";
    });
    if (!others.length) t += '<tr><td colspan="3">Tick another language above to compare with it.</td></tr>';
    sum.innerHTML = t + "</tbody></table></div><p class=\"status\">Each number is Tomato's time (release mode) divided by the other language's time, so below 1.0 Tomato is faster and above 1.0 it is slower. The geometric mean treats a ratio of 2 and of 0.5 alike, so one extreme benchmark does not dominate.</p>";

    // bar charts, one per benchmark
    var ch = $("charts");
    d.benchmarks.forEach(function (b) {
      var langs = has(b, chosen);
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
        box.appendChild(el("p", "status", "Also measured, not in the table: " + what + ", " + fmt(x.median) + " s; Tomato ÷ it is " + ratio(tr(b, x)) + "." + (b.name === "sort" ? " Rust's standard sort is a comparison sort; this is the Rust program with a radix sort instead." : "")));
      });
      ch.appendChild(box);
    });

    // table: median seconds (fastest in bold), with the fastest run and the spread
    var h = '<table><thead><tr><th>Benchmark</th><th class="num">Input</th>';
    langs.forEach(function (l) { h += '<th class="num">' + l[1] + " (s)</th>"; });
    h += "</tr></thead><tbody>";
    d.benchmarks.forEach(function (b) {
      var best = Math.min.apply(null, has(b, langs).map(function (l) { return b.results[l[0]].median; }));
      h += "<tr><td>" + b.name + '</td><td class="num">' + b.input + "</td>";
      langs.forEach(function (l) {
        var r = b.results[l[0]];
        if (!r) { h += '<td class="num">n/a</td>'; return; }
        h += '<td class="num' + (r.median === best ? " best" : "") + '">' + fmt(r.median) + ' <small class="status"><br>min ' + fmt(r.min) + ", spread " + Math.round(100 * (r.max - r.min) / r.median) + "%</small></td>";
      });
      h += "</tr>";
    });
    $("table").innerHTML = h + "</tbody></table>";

    var b0debug = on["tomato-debug"];
    // Tomato (release and debug) divided by each other language, per benchmark
    h = '<table><thead><tr><th>Benchmark</th>';
    others.forEach(function (l) { h += '<th class="num">Tomato ÷ ' + l[1] + "</th>"; });
    if (b0debug) others.forEach(function (l) { h += '<th class="num">Tomato debug ÷ ' + l[1] + "</th>"; });
    h += "</tr></thead><tbody>";
    d.benchmarks.forEach(function (b) {
      h += "<tr><td>" + b.name + "</td>";
      others.forEach(function (l) { if (!b.results[l[0]]) { h += '<td class="num">n/a</td>'; return; } var x = tr(b, b.results[l[0]]); h += '<td class="num' + (x < 1 ? " best" : "") + '">' + ratio(x) + "</td>"; });
      if (b0debug) others.forEach(function (l) { h += '<td class="num">' + (!b.results[l[0]] ? "n/a" : ratio(b.results["tomato-debug"].median / b.results[l[0]].median)) + "</td>"; });
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
        if (!r) { h += '<td class="num">n/a</td>'; return; }
        h += '<td class="num">' + (r.build_seconds != null ? r.build_seconds.toFixed(2) + " s build, " + kb(r.binary_bytes) + "<br>" : "no build<br>") + mb(r.peak_memory_bytes) + " peak</td>";
      });
      h += "</tr>";
    });
    $("build").innerHTML = h + "</tbody></table>";
    }
  }).catch(function () { $("meta").textContent = "The results could not be loaded."; });
})();
