---
name: openrc-release
description: Prepare, publish, resume and verify an OpenRC Simulator release with source-bound checks, patient CI monitoring, six-file artifact verification and website follow-through.
---

# Release OpenRC Simulator

Work from the OpenRC repository root. Commands and paths below are repository-relative; use `python` on native Windows and `python3` on Linux/WSL. A request to make a release authorizes its normal commit/tag/publication sequence; a request to inspect or prepare does not authorize publication. Preserve existing user authorization across retries.

## Load only what matters

Read `docs/TOOLS.md`, section **Release sequence**, and `tools/release/README.md`, section **Patient release automation**. Those are the operating manual; avoid loading the full architecture, research history or every tool guide. Follow additional contracts only when the selected changes require them:

- Version changes: D11g provenance renewal in `docs/research/aero-consistency/D11g/README.md`.
- Changes under `app/physics`, `app/sim` or `app/failures`: `tools/companions/README.md`.
- Local exports/native artifacts: the export and native-package contracts linked by the release sequence.
- Published downloads/site: `site/README.md`, **Preview and maintain**.

Use graph tools for code discovery; use exact known paths and narrow config/string searches for release metadata. Reuse existing tools before writing another probe or watcher.

## Keep one candidate and one monitor

1. Inspect dirty files, branch, HEAD, remote main, published release and existing tags/runs. Preserve unrelated edits. For a new release, choose the next suitable unused version after checking published releases and all existing tags; retain failed tags. For a resume, keep the explicitly pinned candidate/tag. Record the exact base, candidate, tag and owning CI run in a small local checkpoint under a fresh ignored `tmp/` directory. Never store credentials there.
2. Prepare truthful English notes and the numeric project version. Complete required provenance/companion renewal; compare actual outputs before refreshing guards. Reuse only permitted imported-resource caches, with sequential checked imports and fresh drift checks. Never replace goldens to obtain a pass.
3. Run focused checks during editing. On the stable candidate, use the workflow's required full checks and export gates. Reuse valid evidence for unchanged inputs; local quick checks and a green older commit do not qualify the release. Keep new automation/documentation work in a separate reviewable commit when appropriate.
4. Review the exact staged paths. Commit, create the annotated version tag and push commit/tag atomically using the repository's release sequence. Do not move or delete an existing tag. Resolve the **tag push** run by its exact commit and tag; do not choose the newest run or a duplicate main run.
5. Start `tools/release/watch.py` once with that run ID, expected commit/tag and repository. Run it asynchronously, retain the process handle and let its real sleeps perform polling. Read bounded new output; do not repeatedly fetch all jobs, reread unchanged logs or launch a second monitor. Use the host's nonblocking wait/sleep tools and the active session's communication cadence. Report meaningful transitions, failures and decisions, rather than narrating every poll.
6. A watcher alert means inspect the named failed step/log once and classify the failure. A deterministic failure of a publication gate requires a repair and a new candidate identity. Informational failures remain visible and do not become invented release gates. Retry only an evidenced transient/infrastructure failure, with a bounded retry count and unchanged identity; never auto-rerun, cancel jobs or weaken gates. A pending run, API outage, monitor timeout or successful main run is not release success.
7. After the pinned tag run finishes and its `CI required`, `Release builds (Windows, Linux, macOS)` and `GitHub release (v* tags)` jobs all succeed, confirm the actual release is published with the expected tag/title/notes and exact six assets. Report the overall workflow conclusion and any informational failure separately; it can differ from publication-gate success. Download to a fresh directory and run the existing manifest verifier with independent commit/tag/run/repository expectations; current releases also require manifest v2, as the manual explains. Only then update README and localized website downloads, regenerate/test locales, review at 1920×1080 and publish with `site/publish.py`. Verify public English/Spanish links and deployment bytes.

If resuming, inspect the retained checkpoint and live state first; continue from the first unmet gate. Do not recreate commits, tags, successful checks or identical published assets. The watcher is read-only; the existing publisher owns safe same-run publication and identical retries.

Finish with the public release link, delivered platforms and verification outcome, plus any material unresolved limit. If blocked, name the exact failing gate and evidence; distinguish **prepared**, **tag pushed**, **CI passed**, **published** and **download verified**. Software checks do not establish physical or target-hardware qualification.
