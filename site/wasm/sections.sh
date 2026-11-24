#!/bin/sh
# Lists the sections of a WebAssembly file, or says which sections of two wasm files differ.
#   sh site/wasm/sections.sh FILE.wasm         one line per section: offset, size, cksum, name
#   sh site/wasm/sections.sh OLD.wasm NEW.wasm  exit 0 if the files are byte-identical, else print the sections that differ and exit 1
# Plain POSIX sh, od, awk, tail, head and cksum, so it runs on macOS and Linux without the WASI SDK.
set -e

# offset size name, for each section (offset of the section's id byte; size includes the id and length bytes)
list() {
  od -An -v -tu1 "$1" | awk '
    function name(id) {
      if (id == 1) return "type"; if (id == 2) return "import"; if (id == 3) return "function"; if (id == 4) return "table"
      if (id == 5) return "memory"; if (id == 6) return "global"; if (id == 7) return "export"; if (id == 8) return "start"
      if (id == 9) return "element"; if (id == 10) return "code"; if (id == 11) return "data"; if (id == 12) return "datacount"
      if (id == 13) return "tag"; return "unknown-" id
    }
    # states: 0 header, 1 section id, 2 section size, 3 custom name length, 4 custom name, 5 skipping the payload
    BEGIN { st = 0; pos = 0 }
    {
      for (i = 1; i <= NF; i++) {
        c = $i + 0
        if (st == 0) { if (pos == 7) st = 1 }
        else if (st == 1) { start = pos; id = c; size = 0; mul = 1; st = 2 }
        else if (st == 2) {
          size += (c % 128) * mul; mul *= 128
          if (c < 128) {
            end = pos + 1 + size
            if (id == 0) { nlen = 0; nmul = 1; nm = ""; st = 3 }
            else { print start, end - start, name(id); st = (size > 0) ? 5 : 1 }
          }
        }
        else if (st == 3) {
          nlen += (c % 128) * nmul; nmul *= 128
          if (c < 128) { if (nlen > 0) st = 4; else { print start, end - start, "custom:"; st = (pos + 1 < end) ? 5 : 1 } }
        }
        else if (st == 4) {
          nm = nm sprintf("%c", c); nlen--
          if (nlen == 0) { print start, end - start, "custom:" nm; st = (pos + 1 < end) ? 5 : 1 }
        }
        else if (st == 5) { if (pos + 1 == end) st = 1 }
        pos++
      }
    }
    END { if (st != 1) { print "error: " FILENAME " ends inside a section (state " st ")" > "/dev/stderr"; exit 1 } }'
}

# offset size cksum name
sums() {
  list "$1" > "$tmp/list" || exit 2
  while read -r off size nm; do
    printf '%s %s %s %s\n' "$off" "$size" "$(tail -c "+$((off + 1))" "$1" | head -c "$size" | cksum | cut -d' ' -f1)" "$nm"
  done < "$tmp/list"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
case $# in
  1) sums "$1" ;;
  2)
    cmp -s "$1" "$2" && exit 0
    for f in "$1" "$2"; do [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' ')" = 0061736d ] || { echo "$f is not a WebAssembly file"; exit 1; }; done
    sums "$1" > "$tmp/a"; sums "$2" > "$tmp/b"
    echo "$1 ($(wc -c < "$1" | tr -d ' ') bytes) and $2 ($(wc -c < "$2" | tr -d ' ') bytes) differ in:"
    # compare by name and position (the nth section called X), ignoring offsets, which move when an earlier section changes size
    awk -v first="$1" -v second="$2" 'NR == FNR { k = $4 "#" (++na[$4]); a[k] = $2 " " $3; order[++n] = k; next }
         { k = $4 "#" (++nb[$4]); b[k] = $2 " " $3; if (!(k in a)) order[++n] = k }
         END {
           for (i = 1; i <= n; i++) {
             k = order[i]; s = k; sub(/#1$/, "", s)
             if (!(k in a)) print "  " s ": only in " second
             else if (!(k in b)) print "  " s ": only in " first
             else if (a[k] != b[k]) { split(a[k], x, " "); split(b[k], y, " ")
               print "  " s ": " (x[1] == y[1] ? "same size (" x[1] " bytes), different bytes" : x[1] " bytes vs " y[1] " bytes") }
           }
         }' "$tmp/a" "$tmp/b"
    exit 1 ;;
  *) echo "usage: sh site/wasm/sections.sh FILE.wasm [OTHER.wasm]" >&2; exit 2 ;;
esac
