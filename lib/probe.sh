# Runs on a runner host (native Linux or inside WSL) and prints key=value lines
# describing what the runner itself thinks it is doing. Read-only.
# Sent over SSH by runner-status; RUNNER_DIR may be exported ahead of it.

d=${RUNNER_DIR:-}
[ -n "$d" ] || d=$(ls -d /home/*/actions-runner /opt/actions-runner 2>/dev/null | head -1)
echo "now=$(date -u +%s)"
echo "dir=$d"
if [ ! -d "$d/_diag" ]; then echo "error=no actions-runner directory with _diag found"; exit 0; fi

echo "service=$(systemctl list-units 'actions.runner.*' --all --no-legend --plain 2>/dev/null | awk 'NR==1 {print $3 "/" $4}')"
echo "agent=$(grep -o '"agentName": *"[^"]*"' "$d/.runner" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')"

R=$(ls -t "$d"/_diag/Runner_*.log 2>/dev/null | head -1)
[ -n "$R" ] || { echo "error=no Runner log in $d/_diag"; exit 0; }

# "[2026-10-30 17:44:52Z INFO ..." -> "2026-10-30T17:44:52Z"
ts() { sed -E 's/^\[([0-9-]+) ([0-9:]+)Z.*/\1T\2Z/'; }

s=$(grep -n 'WRITE LINE: .*: Running job: ' "$R" | tail -1)
e=$(grep -n 'WRITE LINE: .*: Job .* completed with result: ' "$R" | tail -1)
if [ -n "$s" ]; then
  echo "job_name=${s##*Running job: }"
  echo "job_started=$(echo "${s#*:}" | ts)"
fi
if [ -n "$e" ]; then
  echo "last_result=${e##*with result: }"
  echo "last_finished=$(echo "${e#*:}" | ts)"
fi

# Busy when the newest "Running job" line comes after the newest "completed" line.
sn=${s%%:*}; en=${e%%:*}
if [ -n "$s" ] && [ "$sn" -gt "${en:-0}" ]; then echo "busy=true"; else echo "busy=false"; fi

# The newest Worker log belongs to the current job, or the last one when idle.
W=$(ls -t "$d"/_diag/Worker_*.log 2>/dev/null | head -1)
[ -n "$W" ] && echo "run_id=$(awk '/"k": "run_id"/ {getline; gsub(/.*"v": "|".*/, ""); print; exit}' "$W")"

# Error bursts in the last 15 minutes: one per distinct second with ERR lines.
cut=$(date -u -d '-15 min' '+[%Y-%m-%d %H:%M:%S' 2>/dev/null)
if [ -n "$cut" ]; then
  echo "errors_15m=$(grep ' ERR ' "$R" | awk -v c="$cut" '$0 >= c {print substr($0, 1, 21)}' | sort -u | wc -l | tr -d ' ')"
fi
last_err=$(grep ' ERR ' "$R" | tail -1)
[ -n "$last_err" ] && echo "last_error=$(echo "$last_err" | ts)"
exit 0
