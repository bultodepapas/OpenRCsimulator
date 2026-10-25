# GDU-02: official Godot 4.8 beta1 parallel trial

Date: 2026-10-25. Windows experiment, not a production engine switch.
Owning plan: [Godot 4.8 upgrade](../../../plans/godot-4.8-upgrade.md).

## Source and isolation

- Source snapshot: `a6c2ce38a80a44327392367520c828b42ba0acda` in a detached worktree.
- Official editor: `4.8.beta1.official.4d10419ca`, Windows x86_64. The editor ZIP and matching export templates are verified against pinned official SHA-512 values in [prepare_trial.py](../../../../research/engine-upgrade/prepare_trial.py).
- Local worktree: `D:/OpenRCsimulator-experiments/godot-4.8-beta1`. It was moved from `tmp/` to avoid exhausting C:. Production `app/`, its import cache and the 4.7.2 editor pin are unchanged by this work.
- The trial keeps Compatibility rendering and the existing physics settings. Launchers request 1920×1080 and isolate user data through both `APPDATA` and a dedicated project user-directory name.
- This is the official engine, separate from the [NVIDIA native reconstruction trial](../../visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md). Official beta1 does not provide that fork's DLSS implementation.
- AI companion qualification remains pinned to 4.7.2. Changing a version string would not requalify their behavior; their runtime guard remains in force.

Reproduce from the repository root on Windows:

```powershell
python research/engine-upgrade/prepare_trial.py --destination D:/OpenRCsimulator-experiments/godot-4.8-beta1
# Optional standalone Windows experiment, using official matching release templates:
python research/engine-upgrade/prepare_trial.py --destination D:/OpenRCsimulator-experiments/godot-4.8-beta1 --export-windows
```

Use a new destination for another source revision. The bootstrap imports the isolated tree, preserves the legacy focus/controller/fullscreen defaults explicitly, regenerates model and customization manifests through their existing generators, and creates `Play Godot 4.8.cmd` and `Edit Godot 4.8.cmd`.

Presentation source pins become `4.8.0` because the contract compares the runtime's numeric major/minor/patch version. The receipt separately records the complete **beta1** engine identity and marks the presentation unqualified. Three presentation test fixtures use those pins; their assertions remain intact. Generated geometry, physics data and golden flights are not re-recorded.

`trial-receipt.json` and `trial-source.patch` are tool-owned local artifacts. They record the base commit, actual tracked patch, untracked source hashes, generated manifests and launcher identities. Unknown changes to managed sources or launchers are refused. Evidence is under `tmp/gdu-02-20261025/` in the original checkout and the trial's `tmp/` directory; images stay outside Git.

## GDU-01 update: upstream state

The [official archive](https://godotengine.org/download/archive/) still lists beta1, published October 15, as the newest 4.8 build. The [official migration index](https://docs.godotengine.org/en/latest/tutorials/migrating/index.html) has no published 4.7→4.8 guide yet; the [beta1 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/) and its linked breaking-change PRs are the applicable guidance.

The following regressions are now closed upstream, but their fixes merged on October 22, **after** the official beta1 build:

| Issue | Fix on upstream master | Implication for this beta1 trial |
| --- | --- | --- |
| [#124742: Compatibility globals](https://github.com/godotengine/godot/issues/124742) | [#124750](https://github.com/godotengine/godot/pull/124750), `5d1cd20f9117e4721fce626454e2323eb9462d0a` | Still requires renderer qualification, especially devices with 16 texture slots. A Windows visual failure is not assumed without reproduction. |
| [#124744: macOS universal templates swapped](https://github.com/godotengine/godot/issues/124744) | [#124757](https://github.com/godotengine/godot/pull/124757), `ff6882317eaaae6dec8ff4535ee9078975a4423a` | No macOS package is qualified by this trial. |
| [#124731: X11→Wayland fallback crash](https://github.com/godotengine/godot/issues/124731) | [#124734](https://github.com/godotengine/godot/pull/124734), `a7cb6c2e5f93e7c112f72a0c0c2e4200b724bd26` | Linux native fallback remains a separate gate. |

The same GitHub query used by GDU-00 returns 87 open 4.8-milestone regressions on this date, versus 93 on October 21. Issue closure alone does not establish that a fix is present in a downloaded binary.

## Initial evidence

- Pristine import: exit 0, zero engine errors, eight OBJ ambient-material warnings. Tracked churn: 307 `.import` files, 767 added lines; no `.tscn` or `.tres` churn. Raw diff inventory: `pristine-import-numstat.tsv`.
- Import changed aircraft dependency metadata. The original model-manifest checks correctly rejected changed Avanti/Timber `.import` hashes. The trial therefore rebuilds model manifests **before** customization bindings, rather than weakening their SHA checks.
- Initial headless checks passed: simulation (11), four golden flights, shared ground-vehicle kernel (23), flight logging (3,247), reconstruction policy (103), graphics profile policy (67), and presentation source proofs (97).
- Golden checks use their existing numerical tolerances; passing them is **not** the byte-identical GDU-04 acceptance gate.
- Three fixture tests initially retained literal 4.7.2 presentation identities. Their candidate-only fixture adaptations are recorded separately from engine regressions.

Full `app/test.sh`, paired 1080p visual/audio evidence, exact cross-engine replay, native evaluator receipts and non-Windows exports remain separate gates. This experiment does not mark GDU-03 or production acceptance complete.
