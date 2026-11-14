#!/bin/zsh -f
# Reads macOS's system log and process list for a fixed set of processes, so an agent kept in a sandbox, where
# `log` and `ps` refuse to run, can look into a stalled install. It only works for an agent once its owner lets
# this one script out of the sandbox, since every other app's logs could hold text from the screen. It reads
# nothing else and writes nothing.
#
#   scripts/triage.sh logs --start "2026-01-31 09:00:00" --end "2026-01-31 10:00:00" [--process codesign]...
#   scripts/triage.sh processes
#
# `-f` skips your zsh startup files, and the fixed PATH skips your own tools, since this runs outside the sandbox. In
# the C locale, a byte that isn't UTF-8 can't make awk stop and quote the word it's in.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C

allowed=(codesign trustd securityd SecurityAgent syspolicyd amfid tccd runningboardd launchservicesd lsd Shades)
build_steps=(install.sh bundle.sh codesign swift-build swift-frontend)
max_lines=3000
time_format='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]'

refuse() {
  print -r -- "$1" >&2
  exit 2
}

logs() {
  local start="" end="" chosen=() name predicate=""
  while (( $# )); do
    case "$1" in
      --start|--end)
        (( $# >= 2 )) || refuse "$1 needs a time."
        [[ "$2" == ${~time_format} ]] || refuse "Times look like \"2026-01-31 09:00:00\"."
        if [[ "$1" == --start ]]; then start="$2"; else end="$2"; fi
        shift 2
        ;;
      --process)
        (( $# >= 2 )) || refuse "--process needs a name."
        (( ${allowed[(Ie)$2]} )) || refuse "Only these processes can be read: ${allowed[*]}"
        chosen+=("$2")
        shift 2
        ;;
      *) refuse "logs takes only --start, --end and --process." ;;
    esac
  done
  [[ -n "$start" && -n "$end" ]] || refuse "logs needs both --start and --end."
  (( $#chosen )) || chosen=("${allowed[@]}")

  # Built only from names on the list, so nothing typed reaches the predicate.
  for name in "${chosen[@]}"; do
    predicate+="${predicate:+ OR }process == \"$name\""
  done
  # With nothing of the caller's, such as a HOME whose .logrc could add options or predicate aliases.
  env -i HOME=/var/empty /usr/bin/log show --info --style compact --start "$start" --end "$end" --predicate "$predicate" |
    awk -v max="$max_lines" 'NR <= max { print } END { if (NR > max) printf "Cut %d more lines. Narrow the window or name fewer processes.\n", NR - max }'
}

# Each one's ID, its parent's, how long it's run and which name on the lists it is. Never its arguments, since
# those can carry text, such as a question passed to a test copy of The Kitty Litter. Each field is checked, so an
# argument with a line break in it can't pass for a line of its own.
# shortcut: a name is the first argument's last part, which a program can set, so one can pass for a name on the lists,
# though only its numbers show. Match the executable too once a real ps is checked for how it shows a running script.
processes() {
  (( $# == 0 )) || refuse "processes takes nothing after it."
  print "PID PPID ELAPSED NAME"
  /bin/ps -axww -o pid=,ppid=,etime=,args= |
    awk -v names="${allowed[*]} ${build_steps[*]}" '
      BEGIN {
        split(names, list, " ")
        for (i in list) wanted[list[i]] = 1
        shell["zsh"] = shell["bash"] = shell["sh"] = 1
      }
      function base(path, parts) { return parts[split(path, parts, "/")] }
      $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^([0-9]+-)?([0-9]+:)?[0-9]+:[0-9]+$/ {
        name = base($4)
        if (name in shell) {
          for (i = 5; i <= NF && $i ~ /^-/; i++) ;
          name = (i <= NF && base($i) ~ /^(install|bundle)\.sh$/) ? base($i) : ""
        }
        if (name in wanted) print $1, $2, $3, name
      }'
}

case "${1:-}" in
  logs|processes) "$@" ;;
  *) refuse "Use: scripts/triage.sh logs --start TIME --end TIME [--process NAME]... or scripts/triage.sh processes" ;;
esac
