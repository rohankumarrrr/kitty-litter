#!/bin/zsh -f
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C

allowed=(codesign trustd securityd SecurityAgent syspolicyd amfid tccd runningboardd launchservicesd lsd Shades)
build_steps=(install.sh bundle.sh codesign swift-build swift-package swift-frontend)
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
  {
    /bin/ps -axww -o pid=,args= | awk '{ print "args", $0 }'
    /bin/ps -axww -o ucomm=,pid=,ppid=,etime= | awk '{ print "name", $0 }'
  } |
    awk -v names="${allowed[*]} ${build_steps[*]}" '
      BEGIN {
        split(names, list, " ")
        for (i in list) wanted[list[i]] = 1
        shell["zsh"] = shell["bash"] = shell["sh"] = 1
      }
      function base(path, parts) { return parts[split(path, parts, "/")] }
      $1 == "args" && $2 ~ /^[0-9]+$/ {
        for (i = 4; i <= NF && $i ~ /^-/; i++) ;
        if (i <= NF && base($i) ~ /^(install|bundle)\.sh$/) script[$2] = base($i)
        next
      }
      $1 == "name" {
        if (NF < 4 || $NF !~ /^([0-9]+-)?([0-9]+:)?[0-9]+:[0-9]+$/ || $(NF - 1) !~ /^[0-9]+$/ || $(NF - 2) !~ /^[0-9]+$/) next
        pid = $(NF - 2); ppid = $(NF - 1); elapsed = $NF
        name = $0
        sub(/^name +/, "", name)
        sub(/ +[0-9]+ +[0-9]+ +[^ ]+ *$/, "", name)
        sub(/ +$/, "", name)
        if (name in shell) name = (pid in script) ? script[pid] : ""
        if (name in wanted) print pid, ppid, elapsed, name
      }'
}

case "${1:-}" in
  logs|processes) "$@" ;;
  *) refuse "Use: scripts/triage.sh logs --start TIME --end TIME [--process NAME]... or scripts/triage.sh processes" ;;
esac
