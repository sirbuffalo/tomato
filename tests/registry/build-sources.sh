#!/bin/sh
# build-sources.sh DEST: makes one bare git repository for each fixture seed, DEST/OWNER/NAME.git, with a commit for each version listed in
# seeds-src/ORDER, and writes DEST/commits.txt (`owner/name version commit`). The commits are deterministic (fixed names, dates, messages and
# trees), so the ids in the checked-in index are the ones this script makes on any machine with git.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dest="$1"
[ -n "$dest" ] || { echo "usage: build-sources.sh DEST" >&2; exit 2; }
mkdir -p "$dest"; dest="$(cd "$dest" && pwd -P)"
: > "$dest/commits.txt"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2026-01-01T00:00:00+0000"
work="$dest/.work"; rm -rf "$work"; mkdir -p "$work"
grep -v '^#' "$here/seeds-src/ORDER" | while read -r name version; do
  [ -n "$name" ] || continue
  repo="$work/$name"
  if [ ! -d "$repo/.git" ]; then mkdir -p "$repo"; git init -q -b main "$repo"; fi
  # the tree of this version replaces the files of the last one
  (cd "$repo" && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +)
  cp -R "$here/seeds-src/$name/$version/." "$repo/"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q --allow-empty -m "$name $version"
  echo "$name $version $(git -C "$repo" rev-parse HEAD)" >> "$dest/commits.txt"
done
for d in "$work"/*/*; do
  [ -d "$d/.git" ] || continue
  name="${d#$work/}"
  mkdir -p "$dest/$(dirname "$name")"; rm -rf "$dest/$name.git"
  git clone -q --bare "$d" "$dest/$name.git"
done
rm -rf "$work"
