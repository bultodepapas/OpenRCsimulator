# R11 start, refinement and wheel fixture repairs

2026-10-14. These test changes align existing regression fixtures with the R04 transaction, R09 weather capability and current aircraft contracts. They do not change production loads, data, error tolerances or integrator-order bands. [Exact patch identities](patch-receipt.json) and the original source bytes remain in this directory.

| Test | Original failure | Corrected check | Native Windows result |
| --- | --- | --- | --- |
| `test_start_choice.gd` | Three assertions expected a rejected replacement to erase an accepted flight, or a compatibility fallback to erase its diagnostic | Byte-exact checkpoint, commands, engine/paused/crash state and launch metadata survive refused replacements; no reset/tick/fault is published. Initial invalid starts still fail closed. An explicit compatibility fallback retains its cause in trace metadata. | 36/0; independent existing runway-transaction suite 32/0 |
| `test_shaft_refinement.gd` | Removing only `downwash_gradient` produces invalid P-51 data when its dependent `ground_effect` module is present; four refused candidates then silently retain the lagged model | The in-memory no-lag fixture removes both dependent optional laws. Validation/application failure returns no trajectory, so it cannot be labeled an integrator-order measurement. | 3/0, original order/error bounds |
| `test_ui_home.gd` | Tooltip assertion expected the pre-R09 turbulence-only sentence | The check requires the current explicit turbulence **and** altitude-varying-atmosphere limitation. Existing vehicle selection, weather refusal, start/reset and input-route checks remain. | All Home checks pass |
| `test_wheel_session.gd` | Assumed the Avanti was gearless | Requires its three-contact applied wheel profile, sourced main/nose radii and distinct brake availability. A separate valid file-backed gearless v2 fixture exercises `no_gear`, zero wheel count and no invented continuous wheel slots. | 46/0 |

The focused runner records all GDScript/data hashes before and after each batch, preserves merged stdout/stderr and rejects source drift, nonzero exits and `ERROR`/`SCRIPT ERROR`/`FAIL` lines. This is functional verification on an isolated physical Windows source copy, not performance qualification. The passing Home run has a two-ObjectDB-instance exit warning; the runner's error policy does not classify warnings as a pass/fail condition. Its cause has not been established and no leak fix is claimed here.

## P-51 context control

The original Windows copy has P-51 data SHA-256 `21d5f6dd1951afd91da407289b4a69530b62795af08f60d71c183cdb8b76a008`, without the dependent ground-effect module. Its original shaft test already passes and cannot reproduce the Linux failure. That exploratory [before](before/verification.json) and [after](after/verification.json) remain recorded; they are not the paired regression proof for this failure.

The immutable Linux remainder uses P-51 data SHA-256 `3ef8334ff11ae71d8ce1c14f7674fea440d27b24db0036a37881c1647e553ff2`. Those exact bytes were copied read-only into the disposable Windows app; [receipt](p51-context-receipt.json), [prior data](p51-before-context.json), [Linux data](p51-linux-frozen-context.json). No live P-51 data or frozen Linux source was edited. The [original test](frozen-p51-before/test_shaft_refinement.gd.log) then reproduces all five failures, and the [corrected test](frozen-p51-after/test_shaft_refinement.gd.log) passes:

| Formulation | RPM refinement ratios, 60→120→240 Hz | 240 Hz error against 1,920 Hz |
| --- | --- | --- |
| Coupled RK4, valid no-lag fixture | 16.3514, 16.1793 | 4.91355e-9 rpm |
| Coupled RK4, held production lag | 4.08667, 4.06154 | 2.86319e-6 rpm |
| Split | 2.08091, 2.15018 | 0.214172 rpm |

The no-lag fixture changes neither the production aircraft nor the lagged case. It is an integrator convergence experiment, not a physical argument for disabling ground effect.

The original wheel assertion also reproduces in [the same before batch](frozen-p51-before/test_wheel_session.gd.log). An intermediate repair incorrectly assumed the Avanti had a legacy fallback profile and failed; [that attempt](frozen-p51-after/test_wheel_session.gd.log) remains retained. Reading the actual profile establishes `applied` with explicit brake hardware assumptions; the [final focused run](wheel-current-profile/verification.json) passes 46/0. The original 42 checks remain, with four added gearless-file/session checks. Linux focused and canonical integration are separate enclosing gates.
