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

signing_kind() {
  awk -v wanted="$2" 'index($0, wanted) { sub(/^[^"]*"/, ""); sub(/[":].*/, ""); print; exit }' <<< "$1"
}

signing_team() {
  awk -F= '$1 == "TeamIdentifier" && $2 != "not set" { print $2; exit }' <<< "$1"
}

may_replace() {
  local new="$1" installed="$2"
  shift 2
  if [[ "$new" != *"Authority="* && " $* " != *" --ad-hoc "* ]]; then
    echo "This build is signed ad hoc, so macOS would forget The Kitty Litter's permissions."
    echo "Run scripts/make-dev-cert.sh first, or pass --ad-hoc to install it anyway."
    return 1
  fi
  if [[ -n "$installed" && "$installed" != *"Executable="* && " $* " != *" --change-team "* ]]; then
    echo "The installed copy's signature can't be read, so there's no telling whether this build could read what it"
    echo "saved in the Keychain. Run scripts/install.sh --rollback, or pass --change-team to install it anyway."
    return 1
  fi
  local team="$(signing_team "$installed")"
  if [[ -n "$team" && "$(signing_team "$new")" != "$team" && " $* " != *" --change-team "* ]]; then
    echo "The installed copy is signed by your developer team, and this build isn't, so it couldn't read what that"
    echo "copy saved in the Keychain. Your phone would need pairing again, T3 Code would sign in again, and macOS would"
    echo "ask for every permission again. Check which certificate scripts/bundle.sh signed with, or pass"
    echo "--change-team to install it anyway."
    return 1
  fi
}
