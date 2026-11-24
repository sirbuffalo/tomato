#!/bin/sh
# Makes a failed tests/run.sh visible without the job log (which GitHub shows only to people with admin rights on the repository):
# every FAIL line, with the few lines under it, becomes an error annotation (the check-runs API and the run's summary page show
# annotations to everyone) and goes into the job summary. Usage: tests/ci_report.sh LOGFILE   (used by the workflows)
log="$1"
[ -f "$log" ] || { echo "ci_report: no log at '$log'" >&2; exit 0; }
fails="$(grep -c '^FAIL' "$log")"
{
  echo "### tests/run.sh: $(grep -E '^[0-9]+ passed, [0-9]+ failed' "$log" | tail -n 1 || true)"
  echo
  if [ "$fails" -gt 0 ]; then
    echo "$fails failing checks:"; echo
    echo '```'
    # the FAIL line and the indented detail lines under it (the runner indents them by 5 spaces)
    awk '/^FAIL/ { show = 1; print; next } /^     / && show { print; next } { show = 0 }' "$log" | cut -c1-300 | head -300
    echo '```'
  else
    echo "No FAIL line: the run stopped early (see the end of the log)."; echo
    echo '```'; tail -n 30 "$log" | cut -c1-300; echo '```'
  fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
# at most 10 annotations are shown per step: one per failing check, the detail lines joined into the message
awk '
  function flush() { if (msg != "") { gsub(/%/, "%25", msg); gsub(/\r/, "%0D", msg); gsub(/\n/, "%0A", msg); print "::error title=tests/run.sh::" msg; n++ } msg = "" }
  /^FAIL/ { flush(); if (n >= 9) exit; msg = substr($0, 1, 300); show = 1; lines = 0; next }
  /^     / && show { if (lines < 6) { msg = msg "\n" substr($0, 1, 200); lines++ } next }
  { show = 0 }
  END { flush() }
' "$log"
if [ "$fails" -eq 0 ]; then echo "::error title=tests/run.sh::the run failed without a FAIL line: $(tail -n 3 "$log" | tr '\n' ' ' | cut -c1-400)"; fi
exit 0
