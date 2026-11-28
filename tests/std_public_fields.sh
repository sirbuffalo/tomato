#!/bin/sh
# Fails when a class of the standard library that calls the runtime (a `!tomato_*` function in one of its methods) has a public
# field that is not on the list below. Such a field can be overwritten by any program, so the runtime call that reads it must
# stay safe for every value (fourth audit, blocker 5: `bytearray`'s `buf` and `n` were public, and `a.n = 100000; a[99999] = 7`
# wrote past its buffer; they are `private` now, D12q). A new class that gets here is either made `private` or, when the runtime
# function checks what it is given, added to the list with the reason. Usage: tests/std_public_fields.sh (prints "ok" or the
# differences)
cd "$(dirname "$0")/.." || exit 1
# FILE:CLASS: FIELDS, each field public on purpose and safe for any value:
#   bitarray: words, n          the runtime call is a bit count of one number (`tomato_popcount`), whatever it holds; the lists are checked
#   progress_bar: ...           the runtime calls write text to a terminal; the fields are read and written by checked Tomato code
#   Socket, Server, DatagramSocket: fd, ...   a descriptor number: the runtime calls only pass it to the system, which refuses a wrong one
#   PipeReader: name, piped     the runtime's handle (`h`) is private
#   tarfile _Reader, _Writer: h, path, fixed_mtime   module-private classes (not exported, so no program can make or reach one); the runtime checks every handle it is given
#   Process: pid, ...           a process number, passed to the system (`h`, `fd_in` are private)
#   Terminal: fd, colors        a descriptor number, as for a socket
#   value.Str, value.Dict: v, fields   the runtime call quotes a text
expected="std/builtin/bitarray.tom:bitarray: words n
std/itertools.tom:progress_bar: items total count label width
std/socket.tom:Socket: fd peer_host peer_port
std/socket.tom:Server: fd host port
std/socket.tom:DatagramSocket: fd host port
std/sys.tom:PipeReader: name piped
std/sys.tom:Process: pid stdout stderr status signal
std/tarfile.tom:_Reader: h path
std/tarfile.tom:_Writer: h path fixed_mtime
std/terminal.tom:Terminal: fd colors
std/value.tom:Str: v
std/value.tom:Dict: fields"
found="$(for f in std/*.tom std/builtin/*.tom; do
  awk -v file="$f" '
    function flush() { if (cls != "" && calls > 0 && pub != "") print file ":" cls ":" pub; cls = ""; calls = 0; pub = "" }
    /^(export )?class / { flush(); cls = $0; sub(/^(export )?class /, "", cls); sub(/[^A-Za-z0-9_].*/, "", cls); next }
    /^[^ \t#]/ { flush(); next }
    cls != "" && /^    [A-Za-z_][A-Za-z0-9_]*: / { name = $1; sub(/:$/, "", name); pub = pub " " name; next }
    cls != "" && /!tomato_/ { calls++ }
    END { flush() }
  ' "$f"
done | sort -u)"
want="$(printf '%s\n' "$expected" | sort -u)"
if [ "$found" = "$want" ]; then echo ok; else
  echo "classes of std that call the runtime and have public fields differ from tests/std_public_fields.sh:"
  printf '%s\n%s\n' "$found" "$want" > /dev/null
  echo "found:"; printf '%s\n' "$found" | sed 's/^/  /'
  echo "expected:"; printf '%s\n' "$want" | sed 's/^/  /'
  exit 1
fi
