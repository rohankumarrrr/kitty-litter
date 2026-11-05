#!/bin/zsh
# Puts the skills kittens work by into ~/kittens/_skills: Lauren Tan's pstack, as adapted for T3 by
# t3-pstack, and Ponytail. Both are MIT licensed, and their licenses are copied along with them.
#
# This copies instruction files, pinned to commits that were read first. It doesn't run their
# installers, which would add session hooks and auto-updates to every agent on this Mac. To
# update, read what changed, then change the commits here.
#
#   scripts/install-kitten-skills.sh [folder]     # defaults to ~/kittens/_skills
set -euo pipefail

pstack_commit=7f64e2ba7e1aedcee95cc6e3e92eb5fda62f8b6a
ponytail_commit=96608e078b2d5ea607c5c3b8b5a54d1c1fba6846

out="${1:-$HOME/kittens/_skills}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch() {
  git -C "$work" init -q "$1"
  git -C "$work/$1" fetch -q --depth 1 "$2" "$3"
  git -C "$work/$1" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

fetch pstack https://github.com/chhoumann/t3-pstack "$pstack_commit"
fetch ponytail https://github.com/DietrichGebert/ponytail "$ponytail_commit"

rm -rf "$out/pstack" "$out/ponytail"
mkdir -p "$out/pstack" "$out/ponytail"
cp -R "$work/pstack/plugins/pstack/skills" "$work/pstack/plugins/pstack/agents" "$out/pstack/"
cp "$work/pstack/LICENSE" "$work/pstack/LICENSE-cursor-team-kit" "$work/pstack/LICENSE-thermos" "$work/pstack/NOTICE.md" "$out/pstack/"
cp -R "$work/ponytail/skills/ponytail" "$out/ponytail/skill"
cp "$work/ponytail/LICENSE" "$out/ponytail/"
echo "Skills are in $out"
