#!/bin/zsh
# Exercises only the --pull block of scripts/install.sh. Everything after that block is cut off and
# replaced with an echo, so nothing here can build, install or touch /Applications.
set -u
real="$PWD/scripts/install.sh"
work="$PWD/.repro/pull-work"
rm -rf "$work"; mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

git init -q --bare -b main "$work/up.git"
git clone -q "$work/up.git" "$work/a" 2>/dev/null
mkdir -p "$work/a/scripts"
{
  sed -n '1,62p' "$real"
  print -r -- 'echo "WOULD INSTALL: branch=$(git -C "$root" rev-parse --abbrev-ref HEAD) head=$(git -C "$root" log -1 --format=%s)"'
  print -r -- 'exit 0'
} > "$work/a/scripts/install.sh"
chmod +x "$work/a/scripts/install.sh"
print -r -- '.build' > "$work/a/.gitignore"
git -C "$work/a" add -A && git -C "$work/a" commit -qm first && git -C "$work/a" push -q origin HEAD:main 2>/dev/null
git clone -q "$work/up.git" "$work/b" 2>/dev/null

try() {
  print -r -- "--- $1"
  "$work/${2:-a}/scripts/install.sh" --pull 2>&1 | sed "s#$work#<tmp>#g"
  print -r -- "exit=${pipestatus[1]}"
}

try "clean, nothing new"

print -r -- x > "$work/a/untracked"; try "untracked file"; rm "$work/a/untracked"
print -r -- '# x' >> "$work/a/.gitignore"; try "tracked change"; git -C "$work/a" checkout -q .gitignore
print -r -- x > "$work/a/s"; git -C "$work/a" add s; try "staged change"; git -C "$work/a" reset -q; rm "$work/a/s"
mkdir -p "$work/a/.build"; print -r -- x > "$work/a/.build/y"; try "only ignored files changed"; rm -rf "$work/a/.build"

print -r -- 1 > "$work/b/new"; git -C "$work/b" add new; git -C "$work/b" commit -qm "new upstream commit"; git -C "$work/b" push -q origin HEAD:main 2>/dev/null
try "upstream moved ahead"

print -r -- 2 > "$work/b/other"; git -C "$work/b" add other; git -C "$work/b" commit -qm "second upstream commit"; git -C "$work/b" push -q origin HEAD:main 2>/dev/null
print -r -- 3 > "$work/a/mine"; git -C "$work/a" add mine; git -C "$work/a" commit -qm "local commit"
try "diverged from upstream"
git -C "$work/a" fetch -q; git -C "$work/a" reset -q --hard origin/main

git -C "$work/a" checkout -q -b feature; print -r -- f > "$work/a/f"; git -C "$work/a" add f; git -C "$work/a" commit -qm "unreviewed feature commit"; git -C "$work/a" push -q -u origin feature 2>/dev/null
try "checkout on a feature branch with an upstream"

git -C "$work/a" checkout -q --detach; try "detached head"
git -C "$work/a" checkout -q -b nobody; try "branch with no upstream"
