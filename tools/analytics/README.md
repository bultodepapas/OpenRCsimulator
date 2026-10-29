# Local GitHub history

This tool archives the GitHub repository's daily traffic buckets and observes
release ZIP download counters. It writes a local SQLite database and a small
HTML/CSV report; it does not send data anywhere except the read-only GitHub API
requests made by the installed GitHub CLI.

The existing `gh` authentication is used directly. Nothing reads or exports its
token. `GH_TOKEN` or `GITHUB_TOKEN`, if set, take precedence according to `gh`'s
normal rules. Traffic access needs an account with repository access; GitHub's
[traffic API](https://docs.github.com/en/rest/metrics/traffic#get-page-views)
documents the supported token types and required permissions. A workflow's
default `GITHUB_TOKEN` does not supply the required administration permission.
The tool was checked with Python 3.11.9 and GitHub CLI 2.87.3 on Windows; it
uses only Python's standard library.

## Collect and view

From the repository root in PowerShell:

```powershell
$analyticsDir = Join-Path $env:LOCALAPPDATA 'OpenRCsimulator\analytics'
python tools/analytics/github_history.py collect --output-dir $analyticsDir
```

Open `$analyticsDir\report.html` in a browser. The report shows cumulative
downloads for each currently visible release package. It also links to Google
Analytics Explore for website download requests by country and time; those
countries describe the website flow, not GitHub repository readers.

To preview and then install or update the local daily task for this signed-in
user, run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/analytics/install_daily_task.ps1 -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/analytics/install_daily_task.ps1
```

The task is named `OpenRC GitHub Analytics`. It uses an absolute Python path,
the current user's existing `gh` authentication and an interactive, limited
principal; it stores no credential. It runs hidden at 19:10 **local Windows
time** and at this user's logon. The installer prints the active Windows time
zone; `SA Pacific Standard Time` is Bogotá time. If the computer uses another
zone, 19:10 is in that local zone. `StartWhenAvailable` catches up when possible,
and `IgnoreNew` prevents overlapping task instances. The task cannot run when
the account is not logged in, and its paths require this checkout to remain in
place.

Re-running the installer updates this task only after checking its current user,
launcher, arguments and working directory. It refuses to replace a different
task with the same name. If the checkout moves, inspect the existing task before
removing or replacing it; the installer will not assume the old path is owned by
the new checkout. To run the installed task now and inspect its latest result:

```powershell
Start-ScheduledTask -TaskName 'OpenRC GitHub Analytics' -TaskPath '\'
Get-ScheduledTaskInfo -TaskName 'OpenRC GitHub Analytics' -TaskPath '\'
Get-Content "$analyticsDir\last-run.log" -Raw
```

The task overwrites `last-run.log` after each attempt with its timestamps,
standard output, errors and exit code. A nonzero result indicates that one or
both sources or the launcher failed. The installed task uses this script as its
launcher; deleting or moving the checkout stops future collection.

To regenerate reports without contacting GitHub:

```powershell
python tools/analytics/github_history.py report --output-dir $analyticsDir
```

The default repository is `bultodepapas/OpenRCsimulator` and the default asset
pattern is `openrc-simulator-*.zip`, which includes published releases and
prereleases and excludes `SHA256SUMS`. `collect --repo owner/name --asset-glob
'pattern'` can select another repository or package set. Use a separate output
directory for each repository and pattern: an existing archive rejects a change
of either setting to avoid mixing incompatible series.

The directory contains:

| File | Meaning |
| --- | --- |
| `github-history.sqlite3` | Durable observations and UTC traffic buckets. Back this up; it is the source of the reports. |
| `report.html` | Local report, including the latest result for each collection source. |
| `daily-traffic.csv` | GitHub's observed daily page views and daily unique visitors. |
| `download-intervals.csv` | Comparable asset-counter increases between collection windows. |
| `asset-counters.csv` | The latest visible matching assets and their cumulative counters. |
| `last-run.log` | The latest scheduled collection's output and exit code, when the Windows task runs. |

Repository traffic is owner-only data. Keep this directory and backups private
unless deliberately choosing to share them. No visitor identities are collected.

## Interpreting the history

- GitHub provides traffic days for the last 14 days, with timestamps at UTC
  midnight. Overlapping samples update the same date, including revisions;
  missing dates are unknown. A `partial` day was sampled before it ended.
  `observed_after_day` does not guarantee GitHub will never revise it. Daily
  unique visitors cannot be summed to obtain unique visitors across a period.
- GitHub provides [a cumulative counter for each release asset](https://docs.github.com/en/rest/releases/assets#list-release-assets),
  not the time of each download. The first asset observation is a baseline.
  Later increases compare matching asset IDs and keep both collection windows;
  even daily scheduled runs do not provide exact UTC-calendar-day download
  totals. A missed run produces a longer interval, not invented daily values.
  Each asset is fetched during its own recorded request window, so the combined
  counters were not necessarily observed at one instant.
- A newly seen asset, missing asset or decreased counter marks an interval
  `partial`. Its increase includes only matching IDs whose counters did not
  decrease and is blank when none are comparable; a new or returning asset
  starts a new baseline. `matched_ids` means
  the two visible ID sets match and counters did not decrease. Neither status
  can detect assets created and deleted between collections or a hidden reset.
  Current cumulative totals cover only matching assets still visible in the
  latest observation; downloaded files are not unique people or installs.
- Downloads may include repeat and automated requests. Repository traffic,
  website click analytics and download counters are separate measurements;
  they do not establish user identity or a conversion rate.

Traffic and release assets are fetched independently. If one request fails,
the other successful source is saved, the report marks the failed attempt, and
the command exits nonzero. No partial release list is saved. Check `gh auth
status`, account access, connectivity and rate limits, then collect again. If
traffic is not collected for more than 14 days, older missing buckets cannot be
recovered from GitHub. SQLite locks reject overlapping collectors instead of
interleaving snapshots; retry a failed overlapping run. Reports are regenerated
after successful observations and can always be rebuilt from the database.

## Why the small adapter exists

[github-repo-stats](https://github.com/jgehrcke/github-repo-stats) archives
traffic but does not report release download counters. The free MIT
[git-stats v0.1.5](https://github.com/dejo1307/git-stats/tree/v0.1.5) collects
both, but its documented interval logic assigns the entire cumulative counter
of a newly seen asset to the interval and treats decreases as zero. It also
collects additional data beyond these metrics. The adapter reuses the installed
GitHub CLI and restricts the archive and interval claims to this task.

## Checks

```powershell
python tools/analytics/test_github_history.py
```

The tests exercise overlapping and revised traffic buckets, UTC boundaries,
asset baselines, additions, replacements, removals, decreases, failed sources,
pagination and credential handling without contacting GitHub. On Windows they
also verify task ownership checks and test the launcher with a disposable fake
collector, including standard output, error output and the process exit code.
