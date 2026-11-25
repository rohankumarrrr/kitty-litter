#!/bin/zsh
set -euo pipefail

pstack_commit=11a71d2932c09b6192b598ce52517b7a826fc9f0
ponytail_commit=96608e078b2d5ea607c5c3b8b5a54d1c1fba6846
dickwu_commit=ff4ebddf0488598723a82bfdce1afb04de0b1c44
jakub_commit=659cc4e5b6df90cfe1f306f5ae1c83fa549e075c
emil_commit=5206a950b715e0cabe7043ea0b2304332b91494e
superfuture_commit=d4d2609b53fccb475d11490e2c6261e5eb2f0c5d

out="${1:-$HOME/kittens/_skills}"
work="$(mktemp -d "${TMPDIR:-/tmp}/kitten-skills.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fetch() {
  git -C "$work" init -q "$1"
  git -C "$work/$1" fetch -q --depth 1 "$2" "$3"
  git -C "$work/$1" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

fetch pstack https://github.com/chhoumann/t3-pstack "$pstack_commit"
fetch ponytail https://github.com/DietrichGebert/ponytail "$ponytail_commit"
fetch dickwu https://github.com/dickwu/apple-design-skill "$dickwu_commit"
fetch jakub https://github.com/jakubkrehel/skills "$jakub_commit"
fetch emil https://github.com/emilkowalski/skills "$emil_commit"
fetch superfuture https://github.com/Superfuture/design-review "$superfuture_commit"

# Outside the repo: Superfuture's review posts an install ID to its author's server on every run, and its Pro mode uploads the code under review. Its README says deleting those sections opts out.
review="$work/superfuture/design-review/skills/design-review"
awk '/^## /{skip = /^## (0\. Usage ping|5\. Pro mode)/} !skip' "$review/SKILL.md" > "$work/review.md"
mv "$work/review.md" "$review/SKILL.md"
if grep -nE 'curl|superfuture-metrics\.pages\.dev|design-review-pro\.jprimiani\.workers\.dev' "$review/SKILL.md" "$review/checklist.md" >&2; then
  echo "Superfuture's design review still reaches out after stripping, so nothing was copied." >&2
  exit 1
fi

design="$out/design"
rm -rf "$out/pstack" "$out/ponytail" "$design"
mkdir -p "$out/pstack" "$out/ponytail" "$design"/{dickwu-apple-design,jakubkrehel-better-interface/skills,superfuture-design-review}
cp -R "$work/pstack/plugins/pstack/skills" "$work/pstack/plugins/pstack/agents" "$out/pstack/"
cp "$work/pstack/LICENSE" "$work/pstack/LICENSE-cursor-team-kit" "$work/pstack/LICENSE-thermos" "$work/pstack/NOTICE.md" "$out/pstack/"
cp -R "$work/ponytail/skills/ponytail" "$out/ponytail/skill"
cp "$work/ponytail/LICENSE" "$out/ponytail/"
cp -R "$work/dickwu/SKILL.md" "$work/dickwu/README.md" "$work/dickwu/references" "$design/dickwu-apple-design/"
cp -R "$work/jakub/skills/"{better-interface,interface-review,better-accessibility,better-colors,better-layout,better-typography,better-ui,better-writing} "$design/jakubkrehel-better-interface/skills/"
cp "$work/jakub/LICENSE" "$design/jakubkrehel-better-interface/"
cp -R "$work/emil/skills/apple-design" "$design/emilkowalski-apple-design"
cp "$work/emil/LICENSE" "$design/emilkowalski-apple-design/"
cp "$review/SKILL.md" "$review/checklist.md" "$design/superfuture-design-review/"
echo "Skills are in $out"
