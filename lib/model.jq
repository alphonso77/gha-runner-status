# Builds the status model from GitHub's view and each runner's own view.
# Inputs: $repo, $now (epoch), $gh (runners API response), $gherr (string),
#         $jobs (unfinished jobs), $hosts ([{name, probe: {key: value}}]).
# Grace periods keep the normal second or two of lag at job start/end quiet.

def age($t): if $t then $now - ($t | fromdateiso8601) else null end;
def dur: if . == null then "?"
  elif . < 60 then "\(. | floor)s"
  elif . < 3600 then "\(. / 60 | floor)m"
  else "\(. / 3600 | floor)h \(. % 3600 / 60 | floor)m" end;
def hhmm: fromdateiso8601 | strflocaltime("%H:%M:%S");
def issue($level; $text): {level: $level, text: $text};

($gh.runners // []) as $ghr
| [ $hosts[] as $h
    | ($ghr | map(select(.name == $h.name)) | first) as $g
    | $h.probe as $p
    | ($p.ssh_rc == "0" and ($p.error | not) and $p.now != null) as $reachable
    | (if $reachable then
         ($p.now | tonumber) as $r | ($p.local_before | tonumber) as $b | ($p.local_after | tonumber) as $a
         | if $r < $b then $r - $b elif $r > $a then $r - $a else 0 end
       else null end) as $skew
    | {
        name: $h.name,
        github: (if $g then {status: $g.status, busy: $g.busy, labels: [$g.labels[].name]} else null end),
        host: (if $reachable then {
            service: $p.service,
            busy: ($p.busy == "true"),
            job: $p.job_name, job_started: $p.job_started, run_id: $p.run_id,
            last_result: $p.last_result, last_finished: $p.last_finished,
            errors_15m: ($p.errors_15m // "0" | tonumber), last_error: $p.last_error,
            clock_skew_s: $skew
          } else {error: ($p.error // "unreachable over SSH")} end)
      }
    | .issues = [
        (if $gherr != "" then empty
         elif .github == null then issue("down"; "not registered in GitHub")
         elif .github.status != "online" then issue("down"; "\(.github.status) in GitHub")
         else empty end),
        (if .host.error then issue("warn"; .host.error) else empty end),
        (if .host.service and (.host.service | startswith("active") | not)
         then issue("down"; "runner service is \(.host.service)") else empty end),
        (if .github and .host.busy != null and .github.busy != .host.busy
            and ((if .host.busy then age(.host.job_started) else age(.host.last_finished) end) // 999) > 20
         then issue("warn"; "GitHub says \(if .github.busy then "busy" else "idle" end), runner says \(if .host.busy then "busy" else "idle" end)")
         else empty end),
        (if (.host.clock_skew_s // 0 | fabs) > 5
         then issue("warn"; "clock off by \(.host.clock_skew_s)s") else empty end)
      ]
  ] as $runners
| [ $jobs[] as $j
    | ($runners | map(select(.host.run_id == ($j.run_id | tostring))) | first) as $r
    | {run_id: $j.run_id, name: $j.name, status: $j.status, created_at: $j.created_at,
       runner: $j.runner_name, age_s: age($j.created_at),
       # What the runner that took this run says, whatever GitHub shows.
       on_runner: (if $r then {name: $r.name, busy: $r.host.busy, started: $r.host.job_started,
                               finished: (if $r.host.busy then null else $r.host.last_finished end),
                               result: (if $r.host.busy then null else $r.host.last_result end)}
                   else null end)}
    | .issues = [
        (if .status != "queued" or .age_s <= 20 then empty
         elif .on_runner.busy == true
         then issue("warn"; "GitHub shows \(.name) (run \(.run_id)) queued, but \(.on_runner.name) has been running it since \(.on_runner.started | hhmm)")
         elif .on_runner
         then issue("warn"; "GitHub shows \(.name) (run \(.run_id)) queued, but \(.on_runner.name) finished it at \(.on_runner.finished | hhmm) (\(.on_runner.result))")
         elif .age_s > 60
         then issue("warn"; "\(.name) (run \(.run_id)) queued \(.age_s | dur) with no runner on it")
         else empty end)
      ]
  ] as $jobs
| ([ (if $gherr != "" then issue("down"; "GitHub API: \($gherr)") else empty end),
     ($runners[] | .name as $n | .issues[] | .text = "\($n): \(.text)"),
     ($jobs[].issues[]) ]) as $issues
| ($runners | map(select(.github.status == "online")) | length) as $online
| ($runners | map(select(.host.busy == true or .github.busy == true)) | length) as $busy
| {
    checked_at: ($now | todate),
    repo: $repo,
    state: (if any($issues[]; .level == "down") then "down" elif ($issues | length) > 0 then "warn" else "ok" end),
    summary: ("\($online)/\($runners | length) online, \($busy) busy"
              + (if ($issues | length) > 0 then ", \($issues | length) issue\(if ($issues | length) > 1 then "s" else "" end)" else "" end)),
    runners: $runners,
    jobs: $jobs,
    issues: $issues
  }
