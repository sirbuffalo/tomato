# Split Tomato's emitted IR into independently compilable modules. The input format is deliberately checked:
# if the emitter changes, fail rather than silently generating a different program.
FNR == NR {
  if (/^define /) { f++; sig[f] = $0; start = FNR }
  if (/^}$/ && start) { size[f] = FNR - start; start = 0 }
  next
}
FNR == 1 {
  if (start || !f) { print "unsupported IR: incomplete function" > "/dev/stderr"; exit 1 }
  for (i = 1; i <= f; i++) {
    best = 0
    for (j = 1; j < parts; j++) if (load[j] < load[best]) best = j
    owner[i] = best; load[best] += size[i]
  }
  f = 0
}
/^define / {
  f++; body = 1
  for (j = 0; j < parts; j++) if (j != owner[f]) {
    decl = $0; sub(/^define /, "declare ", decl); sub(/ \{$/, "", decl)
    print decl >> (dir "/part" j ".ll")
  }
}
!body {
  line = $0
  if (line ~ /^@[^ ]+ = /) {
    # Promote private constants to a single definition; every other module declares the same symbol.
    sub(/ = private constant /, " = constant ", line)
    for (j = 0; j < parts; j++) {
      if (j == 0) { print line >> (dir "/part" j ".ll"); continue }
      decl = line
      if (match(decl, / = (global|constant) (ptr|i[0-9]+|\[[^]]*\]|\{[^}]*\}) /)) {
        decl = substr(decl, 1, RSTART + RLENGTH - 2)
        sub(/ = /, " = external ", decl)
        print decl >> (dir "/part" j ".ll")
      } else { print "unsupported global: " line > "/dev/stderr"; exit 1 }
    }
  } else for (j = 0; j < parts; j++) print line >> (dir "/part" j ".ll")
  next
}
body { print >> (dir "/part" owner[f] ".ll") }
/^}$/ { body = 0 }
END { if (body) { print "unsupported IR: incomplete function" > "/dev/stderr"; exit 1 } }
