#!/usr/bin/env bash
# <xbar.title>GitHub Actions runner status</xbar.title>
# <xbar.desc>Self-hosted runners: GitHub's view and each runner's own view.</xbar.desc>
# <xbar.dependencies>gh,jq,ssh</xbar.dependencies>
# <xbar.abouturl>https://github.com/alphonso77/gha-runner-status</xbar.abouturl>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
#
# SwiftBar plugin. Symlink it into the SwiftBar plugin folder; the ".30s" in
# the name is the refresh interval. It wraps `runner-status --json`.

# Menu-bar apps start with a minimal PATH; add where gh and jq usually live.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

# Follow the symlink from the plugin folder back to the checkout.
self=$0
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case $link in /*) self=$link ;; *) self=$(dirname "$self")/$link ;; esac
done
BIN=${RUNNER_STATUS_BIN:-$(cd "$(dirname "$self")/.." && pwd -P)/runner-status}

model=$("$BIN" --json 2>&1)
if ! jq -e .state >/dev/null 2>&1 <<< "$model"; then
  echo "| sfimage=exclamationmark.triangle"
  echo "---"
  echo "runner-status failed | color=red"
  printf '%s\n' "$model" | head -5 | sed 's/|/¦/g; s/$/ | font=Menlo size=11/'
  echo "Refresh | refresh=true"
  exit 0
fi

jq -r --arg bin "$BIN" '
  def clean: tostring | gsub("\\|"; "¦");
  def hhmm: fromdateiso8601 | strflocaltime("%H:%M");
  (.runners | map(select(.host.busy == true or .github.busy == true)) | length) as $busy
  | (.issues | length) as $n
  # Menu bar title: an icon, plus a few words only when there is something to see.
  | (if .state == "ok" then "\(if $busy > 0 then "\($busy) busy " else "" end)| sfimage=checkmark.circle"
     elif .state == "warn" then "\($n) | sfimage=exclamationmark.triangle.fill sfcolor=#E8A317"
     else "\($n) | sfimage=xmark.octagon.fill sfcolor=#D23F31" end),
    "---",
    "\(.repo | clean): \(.state | ascii_upcase), \(.summary | clean) | color=\(if .state == "ok" then "#2E9E44" elif .state == "warn" then "#E8A317" else "#D23F31" end)",
    "---",
    (.runners[] |
      "\(.name): " + (if .github then "\(.github.status), \(if .github.busy then "busy" else "idle" end)" else "not in GitHub" end)
      + (if .host.error then " · \(.host.error)"
         elif .host.busy then " · running \(.host.job) since \(.host.job_started | hhmm)"
         elif .host.last_finished then " · last \(.host.job) \(.host.last_result) at \(.host.last_finished | hhmm)"
         else "" end)
      | clean + " | sfimage=\(if . | test("offline|not in GitHub|unreachable") then "circle.slash" else "server.rack" end)"),
    (if (.jobs | length) > 0 then "---", "Jobs | size=11",
       (.jobs[] | . as $j
        | "\(.name) · run \(.run_id) · \(.status)" + (if .on_runner and (.on_runner.busy | not) then " (\(.on_runner.name) finished it)" else "" end)
        | clean + " | href=https://github.com/\($repo)/actions/runs/\($j.run_id)" )
     else empty end),
    (if $n > 0 then "---", "Issues | size=11", (.issues[] | (.text | clean) + " | color=\(if .level == "down" then "#D23F31" else "#E8A317" end) size=12") else empty end),
    "---",
    "Open GitHub Actions | href=https://github.com/\(.repo)/actions",
    "Watch in Terminal | bash=\($bin | clean) param1=-w terminal=true",
    "Refresh now | refresh=true"
' --arg repo "$(jq -r .repo <<< "$model")" <<< "$model"
