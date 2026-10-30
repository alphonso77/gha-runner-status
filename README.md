# gha-runner-status

A terminal status screen for self-hosted GitHub Actions runners. It shows what GitHub thinks each runner is doing next to what the runner's own logs say, and flags where the two disagree.

```
Runners  your-account/your-repo  13:53:12   WARN  2/2 online, 0 busy, 1 issue

runner-1  GitHub: online, idle   Runner: idle · last: ci Succeeded at 13:33:13, 19m ago
          service active/running · clock in sync · self-hosted,Linux,X64,wsl
runner-2  GitHub: online, idle   Runner: idle · last: ci Succeeded at 13:47:25, 5m ago
          service active/running · clock in sync · self-hosted,Linux,X64,native

Jobs
  ci  run 1234567890  queued 8m  (runner-2 finished it: Succeeded)

Issues
  ! GitHub shows ci (run 1234567890) queued, but runner-2 finished it at 13:47:25 (Succeeded)
```

That last line is why this exists. GitHub's UI and API can show a job as queued for minutes after a runner has picked it up, or even finished it. From GitHub alone, that looks like a dead runner. From the runner's log, it's plainly fine.

## What it checks

From GitHub (`gh api`): each runner's online/offline and busy/idle state, and every unfinished job in queued or in-progress runs.

From each runner, over SSH (read-only; nothing is installed on the runner):

- the runner's systemd service state
- the job it's running (name, run id, start time), or the last one it finished and the result
- error bursts in the runner log in the last 15 minutes
- clock skew against the machine running this script

Then it raises an issue when:

- a runner is offline or missing in GitHub, unreachable over SSH, or its service isn't active
- GitHub and the runner disagree about busy/idle for more than 20 seconds
- GitHub shows a job queued that a runner is running or has already finished
- a job has been queued over a minute and no runner has it
- a runner's clock is more than 5 seconds off

## Setup

Needs `gh` (logged in, with access to the repo), `jq` and `ssh` with key-based login to each runner host. Runners are expected to be the standard `actions-runner` install on Linux, running as a systemd service, either native or inside WSL2 on Windows.

```sh
git clone https://github.com/alphonso77/gha-runner-status
mkdir -p ~/.config/runner-status
cp gha-runner-status/config.example.json ~/.config/runner-status/config.json
# edit it: your repo and runners
gha-runner-status/runner-status
```

### config.json

```json
{
  "repo": "your-account/your-private-repo",
  "runners": [
    { "name": "runner-1", "ssh": "runner-1.local" },
    { "name": "runner-2", "ssh": "windows-box", "wsl": "Ubuntu-24.04" },
    { "name": "runner-3", "ssh": "runner-3", "dir": "/opt/actions-runner" }
  ]
}
```

- `name` is the runner's name as GitHub shows it.
- `ssh` is anything `ssh` accepts: a host alias from `~/.ssh/config`, `user@host`, an IP.
- `wsl` (Windows hosts only) is the WSL distro the runner lives in. The probe is sent through `wsl.exe`, base64-encoded so cmd.exe quoting can't mangle it.
- `dir` (optional) is the runner directory. By default the probe uses the first of `/home/*/actions-runner` and `/opt/actions-runner`.

Set `RUNNER_STATUS_CONFIG` to use a config file somewhere else. Only repo-level runners are supported for now.

## Usage

```sh
runner-status              # print once
runner-status -w           # refresh every 10 seconds (-w 5 for every 5)
runner-status --oneline    # OK 2/2 online, 1 busy
runner-status --json       # the full status model
```

Exit status is `0` ok, `1` warn, `2` down, `64` for a usage or setup error.

## Menu bar (planned)

The script is built so a menu-bar app can wrap it without changes:

- `--oneline` gives a title: the state (`OK`, `WARN`, `DOWN`) and a short summary.
- `--json` gives everything else: `state`, `summary`, `runners[]` (each with `github`, `host` and `issues`), `jobs[]` and a flat `issues[]` list with `level` and `text`.
- The exit status gives the color without parsing anything.

A [SwiftBar](https://github.com/swiftbar/SwiftBar) or [xbar](https://xbarapp.com) plugin would be a few lines calling those. Menu-bar apps start with a minimal `PATH`, so a plugin needs to add the directories holding `gh` and `jq` (on Apple silicon Homebrew, `/opt/homebrew/bin`).

## Related

[gha-wsl-runner](https://github.com/alphonso77/gha-wsl-runner): setting up the runners this watches.

## License

MIT
