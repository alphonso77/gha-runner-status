#!/usr/bin/env bash
# Feeds made-up GitHub and runner states through lib/model.jq and checks the
# issues it raises. No network. Run: tests/model-test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
NOW=1800000000
iso() { date -u -r $((NOW - $1)) +%Y-%m-%dT%H:%M:%SZ; }  # iso <seconds ago>
fails=0

# host <name> <busy> <run_id> <started ago> <finished ago>
host() {
  jq -n --arg n "$1" --arg busy "$2" --arg run "$3" --arg s "$(iso $4)" --arg f "$(iso $5)" --arg now $NOW \
    '{name: $n, probe: {ssh_rc: "0", now: $now, local_before: $now, local_after: $now,
      service: "active/running", busy: $busy, run_id: $run, job_name: "ci",
      job_started: $s, last_finished: $f, last_result: "Succeeded", errors_15m: "0"}}'
}
# job <run_id> <status> <runner or ""> <created ago>
job() {
  jq -n --argjson id "$1" --arg st "$2" --arg r "$3" --arg c "$(iso $4)" \
    '{run_id: $id, name: "ci", status: $st, created_at: $c, runner_name: (if $r == "" then null else $r end)}'
}

# check <description> <expected issue substring, or "" for none> <hosts json> <jobs json>
check() {
  local got
  got=$(jq -n --arg repo o/r --argjson now $NOW --arg gherr "" \
    --argjson gh '{"runners":[{"name":"r1","status":"online","busy":false,"labels":[]},{"name":"r2","status":"online","busy":false,"labels":[]}]}' \
    --argjson hosts "$3" --argjson jobs "$4" -f "$ROOT/lib/model.jq" | jq -r '[.jobs[].issues[].text] | join(" | ")')
  if { [ -z "$2" ] && [ -z "$got" ]; } || { [ -n "$2" ] && [[ $got == *"$2"* ]]; }; then
    echo "ok   $1"
  else
    echo "FAIL $1"; echo "     want: ${2:-<no issue>}"; echo "     got:  ${got:-<no issue>}"; fails=$((fails + 1))
  fi
}

idle_r1=$(host r1 false 100 900 800)
check "queued, a runner is running it" "queued, but r2 has been running it" \
  "[$idle_r1, $(host r2 true 500 60 9999)]" "[$(job 500 queued "" 61)]"
check "queued, a runner already finished it" "queued, but r2 finished it" \
  "[$idle_r1, $(host r2 false 500 120 60)]" "[$(job 500 queued "" 121)]"
check "queued 90s, no runner has it" "queued 1m with no runner on it" \
  "[$idle_r1, $(host r2 false 400 900 800)]" "[$(job 500 queued "" 90)]"
check "queued 10s, normal pickup lag" "" \
  "[$idle_r1, $(host r2 false 400 900 800)]" "[$(job 500 queued "" 10)]"
check "in progress, the runner finished it 60s ago" "in progress, but r2 finished it" \
  "[$idle_r1, $(host r2 false 500 200 60)]" "[$(job 500 in_progress r2 200)]"
check "in progress, the runner finished it 5s ago (grace)" "" \
  "[$idle_r1, $(host r2 false 500 200 5)]" "[$(job 500 in_progress r2 200)]"
check "in progress and the runner agrees" "" \
  "[$idle_r1, $(host r2 true 500 200 9999)]" "[$(job 500 in_progress r2 200)]"
check "two jobs in one run: r1 finished one, r2 still running the other" "" \
  "[$(host r1 false 500 200 60), $(host r2 true 500 200 9999)]" "[$(job 500 in_progress r2 200)]"

[ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
