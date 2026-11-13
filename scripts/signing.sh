# How The Kitty Litter is signed, shared by scripts/bundle.sh and scripts/install.sh, which source it.
#
# A certificate with a Team ID, such as the free Apple Development one Xcode makes, comes first. macOS then ties
# what a build saves in the Keychain to the team rather than to that exact build, so the next build can read it, and
# your phone stays paired and T3 Code stays signed in. The self-signed "Shades Dev" keeps permissions across builds,
# but not Keychain items.

# The certificate to sign with, by its hash, from `security find-identity -v -p codesigning`'s output in $1, or
# nothing if there isn't one. The hash, so two certificates with the same name can't make signing ambiguous.
signing_identity() {
  local wanted match
  for wanted in '"Apple Development' '"Developer ID Application' '"Shades Dev"'; do
    match="$(awk -v wanted="$wanted" 'index($0, wanted) { print $2; exit }' <<< "$1")"
    if [[ -n "$match" ]]; then
      print -r -- "$match"
      return
    fi
  done
}

# The kind of certificate $2 is, such as "Apple Development", from `security find-identity`'s output in $1. Only the
# kind, since the rest of its name is whose it is.
signing_kind() {
  awk -v wanted="$2" 'index($0, wanted) { sub(/^[^"]*"/, ""); sub(/[":].*/, ""); print; exit }' <<< "$1"
}

# The Team ID in `codesign -dvv`'s output in $1, or nothing for a signature without one.
signing_team() {
  awk -F= '$1 == "TeamIdentifier" && $2 != "not set" { print $2; exit }' <<< "$1"
}

# Whether a build signed as $1 may replace the installed copy, signed as $2, each `codesign -dvv`'s output, with
# --ad-hoc or --change-team after them to allow what's otherwise refused. Says why not.
may_replace() {
  local new="$1" installed="$2"
  shift 2
  if [[ "$new" != *"Authority="* && " $* " != *" --ad-hoc "* ]]; then
    echo "This build is signed ad hoc, so macOS would forget The Kitty Litter's permissions."
    echo "Run scripts/make-dev-cert.sh first, or pass --ad-hoc to install it anyway."
    return 1
  fi
  # A copy cut short, such as by a failed install, can't say whose it is, and may still be a team's.
  if [[ -n "$installed" && "$installed" != *"Executable="* && " $* " != *" --change-team "* ]]; then
    echo "The installed copy's signature can't be read, so there's no telling whether this build could read what it"
    echo "saved in the Keychain. Run scripts/install.sh --rollback, or pass --change-team to install it anyway."
    return 1
  fi
  # Moving onto a team, from "Shades Dev" or from nothing, is the way forward. Moving off one loses it all again.
  local team="$(signing_team "$installed")"
  if [[ -n "$team" && "$(signing_team "$new")" != "$team" && " $* " != *" --change-team "* ]]; then
    echo "The installed copy is signed by your developer team, and this build isn't, so it couldn't read what that"
    echo "copy saved in the Keychain. Your phone would need pairing again, T3 Code would sign in again, and macOS would"
    echo "ask for every permission again. Check which certificate scripts/bundle.sh signed with, or pass"
    echo "--change-team to install it anyway."
    return 1
  fi
}
