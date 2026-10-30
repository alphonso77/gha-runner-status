# Renders the status model (from model.jq) as a terminal screen.
# Input: the model. $color: "1" for ANSI colors.

def c($code): if $color == "1" then "\u001b[\($code)m" else "" end;
def reset: c("0");
def dim($s): c("2") + $s + reset;
def tone($state; $s):
  (if $state == "ok" then c("32") elif $state == "warn" then c("33") else c("31") end) + $s + reset;
def dur: if . == null then "?"
  elif . < 60 then "\(. | floor)s"
  elif . < 3600 then "\(. / 60 | floor)m"
  else "\(. / 3600 | floor)h \(. % 3600 / 60 | floor)m" end;
def ago($t): (now - ($t | fromdateiso8601)) | dur;
def hhmm: fromdateiso8601 | strflocaltime("%H:%M:%S");
def pad($n): tostring | . + (" " * ([$n - length, 0] | max));

(.runners | map(.name | length) | max // 4) as $w
| [
    c("1") + "Runners" + reset + "  " + .repo + "  " + dim(.checked_at | hhmm)
      + "   " + tone(.state; .state | ascii_upcase) + "  " + .summary,
    "",
    (.runners[] |
      ( if .github == null then tone("down"; "not in GitHub")
        else (tone(if .github.status == "online" then "ok" else "down" end; .github.status)
              + ", " + (if .github.busy then "busy" else "idle" end)) end ) as $gh
      | ( if .host.error then tone("warn"; .host.error)
          elif .host.busy then "running \(.host.job) (run \(.host.run_id // "?")) since \(.host.job_started | hhmm), \(ago(.host.job_started))"
          elif .host.last_finished then "idle · last: \(.host.job) \(.host.last_result) at \(.host.last_finished | hhmm), \(ago(.host.last_finished)) ago"
          else "idle · no jobs in this log" end ) as $rn
      | (c("1") + (.name | pad($w)) + reset + "  GitHub: " + $gh + "   Runner: " + $rn),
        ( if .host.error then empty else
            (" " * $w) + "  " + dim(
              "service \(.host.service // "?")"
              + " · clock " + (if (.host.clock_skew_s // 0) == 0 then "in sync" else "\(.host.clock_skew_s)s off" end)
              + (if .host.errors_15m > 0 then " · \(.host.errors_15m) error burst\(if .host.errors_15m > 1 then "s" else "" end) in 15m (last \(.host.last_error | hhmm))" else "" end)
              + (if .github then " · " + (.github.labels | join(",")) else "" end))
          end )
    ),
    (if (.jobs | length) > 0 then
       "", c("1") + "Jobs" + reset,
       (.jobs[] | "  \(.name)  run \(.run_id)  \(.status) \(.age_s | dur)"
                  + (if .runner then " on \(.runner)" else "" end)
                  + (if .on_runner == null or .status != "queued" then ""
                     elif .on_runner.busy then dim("  (\(.on_runner.name) is running it)")
                     else dim("  (\(.on_runner.name) finished it: \(.on_runner.result))") end))
     else empty end),
    (if (.issues | length) > 0 then
       "", c("1") + "Issues" + reset,
       (.issues[] | "  " + tone(.level; "!") + " " + .text)
     else empty end)
  ]
| .[]
