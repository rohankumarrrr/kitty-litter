#!/bin/zsh
# Builds Shades.app and swaps it into /Applications, then restarts it. The running copy is only
# touched once the new one is built and properly signed. The old copy is kept, and if the new one
# doesn't come up and report in, the old one goes back. Only one install or rollback runs at a time:
# one started while another is going stops straight away, changes nothing and says which one is.
#
#   scripts/install.sh                # build and install
#   scripts/install.sh --ad-hoc       # allow a build with no stable signature, losing permissions
#   scripts/install.sh --change-team  # allow a build not signed by the installed copy's team
#   scripts/install.sh --rollback     # put the last working copy back
#   scripts/install.sh --pull         # stop if there's uncommitted work, pull, then build and install
#
# scripts/bundle.sh signs with your Apple Development certificate if you have one. Once a copy
# signed by your team is installed, a build signed any other way is refused, since it couldn't
# read what's in the Keychain: your phone would need pairing again and T3 Code would sign in again.
# Moving onto a team, from "Shades Dev" or ad hoc, is allowed. It costs that once, and macOS asks
# for each permission again, since it ties them to the signature.
#
# macOS may ask whether codesign can use your signing key. Choose Always Allow, and it won't
# ask again.
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

# Two at once would swap the same app and read each other's health.json. The lock is the kernel's, so it goes
# when this process does, however it ends, and it's kept through the exec after --pull. This shell never opens
# the lock file itself: closing any handle it has on it, even the one print -u makes, lets go of the lock.
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
  # The holder writes its line just after taking the lock, so until then the line is missing or the last install's.
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
  # Already ours, from before the exec after --pull.
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
  # Copied alongside first, so running out of disk or any other failure leaves the old copy where it is.
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
  # A report from the copy that's gone would look like one from the copy coming back.
  rm -f "$health"
  put_in_place "$keep"
  open "$app"
}

take_lock
# Set out here, since a function's EXIT trap goes off when the function returns.
trap 'rm -f "$holder"' EXIT

# Flags go in any order, and --pull passes the rest on.
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
  # Run what was just pulled, not the copy of this script that's already going.
  exec "$root/scripts/install.sh" "${@:#--pull}"
fi

next="$(mktemp -d)"
trap 'rm -rf "$next" "$holder"' EXIT

"$root/scripts/bundle.sh" "$next"
codesign --verify --deep --strict "$next/Shades.app"

# With a stable identity, permissions carry over, and with the same team, Keychain items do too. Losing either
# takes asking for. Read into variables first: piping these into grep -q can fail by itself under pipefail.
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

# The app writes this once it's up and has checked itself. A problem it finds, such as a
# permission that's off, isn't a reason to go back: not coming up at all is.
rm -f "$health"
# A copy too broken to open is what the wait below is for, so that can't stop the script here.
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
