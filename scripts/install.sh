#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
source "$root/scripts/signing.sh"
app=/Applications/Shades.app
data="$HOME/Library/Application Support/shades"
keep="$data/last-good/Shades.app"
health="$data/health.json"
lock="$data/install.lock"
holder="$data/install.holder"
wait_seconds="${SHADES_HEALTH_SECONDS:-30}"

# Outside the repo: the kernel drops this lock when the shell exits or closes any handle on the lock file, but keeps it across exec.
take_lock() {
  local taken=0 i pid="" since=""
  mkdir -p "$data"
  touch "$lock"
  if [[ ! -w "$lock" ]]; then
    echo "$lock can't be written, so nothing was installed."
    exit 1
  fi
  zmodload zsh/system
  zsystem flock -e -t 0 -f lock_fd "$lock" 2>/dev/null && taken=1
  for i in {1..20}; do
    pid="" since=""
    if [[ -f "$holder" ]]; then
      read -r pid since < "$holder" || true
    fi
    if (( taken )); then
      break
    fi
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "Another install, process $pid, has been running since $since, so nothing was installed."
      exit 1
    fi
    sleep 0.1
  done
  if (( ! taken )); then
    echo "Another install is running, so nothing was installed."
    exit 1
  fi
  if [[ "$pid" == "$$" ]]; then
    return
  fi
  if [[ -n "$pid" ]]; then
    echo "The install that started $since, process $pid, stopped without finishing, so this one is taking over."
  fi
  print -r -- "$$ $(date '+%a %b %-d at %-I:%M:%S %p')" > "$holder"
}

stop_running() {
  pkill -x Shades 2>/dev/null || true
  while pgrep -x Shades >/dev/null; do sleep 0.1; done
}

put_in_place() {
  rm -rf "$app.new"
  ditto "$1" "$app.new"
  rm -rf "$app"
  mv "$app.new" "$app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
}

restore() {
  if [[ ! -d "$keep" ]]; then
    echo "There's no earlier copy to go back to."
    exit 1
  fi
  stop_running
  rm -f "$health"
  put_in_place "$keep"
  open "$app"
}

take_lock
trap 'rm -f "$holder"' EXIT

if [[ " $* " == *" --rollback "* ]]; then
  restore
  echo "Back on the last working copy."
  exit 0
fi

if [[ " $* " == *" --pull "* ]]; then
  if [[ -n "$(git -C "$root" status --porcelain)" ]]; then
    echo "$root has uncommitted work, so nothing was installed."
    exit 1
  fi
  git -C "$root" pull --ff-only
  exec "$root/scripts/install.sh" "${@:#--pull}"
fi

next="$(mktemp -d)"
trap 'rm -rf "$next" "$holder"' EXIT

"$root/scripts/bundle.sh" "$next"
codesign --verify --deep --strict "$next/Shades.app"

signature="$(codesign -dvv "$next/Shades.app" 2>&1)"
installed="$([[ -d "$app" ]] && codesign -dvv "$app" 2>&1 || true)"
may_replace "$signature" "$installed" "$@" || exit 1

stop_running
if [[ -d "$app" ]]; then
  mkdir -p "${keep:h}"
  rm -rf "$keep"
  ditto "$app" "$keep"
fi
put_in_place "$next/Shades.app"

rm -f "$health"
open "$app" || true
deadline=$(( SECONDS + wait_seconds ))
while (( SECONDS < deadline )); do
  if [[ -f "$health" ]] && pgrep -x Shades >/dev/null; then
    echo "Installed and running."
    exit 0
  fi
  sleep 0.5
done

echo "The new copy didn't come up within $wait_seconds seconds, so the last working copy is going back."
restore
exit 1
