#!/bin/zsh -f
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

  for name in "${chosen[@]}"; do
    predicate+="${predicate:+ OR }process == \"$name\""
  done
  # Outside the repo: `log` reads options and predicate aliases from ~/.logrc in HOME.
  env -i HOME=/var/empty /usr/bin/log show --info --style compact --start "$start" --end "$end" --predicate "$predicate" |
    awk -v max="$max_lines" 'NR <= max { print } END { if (NR > max) printf "Cut %d more lines. Narrow the window or name fewer processes.\n", NR - max }'
}

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
