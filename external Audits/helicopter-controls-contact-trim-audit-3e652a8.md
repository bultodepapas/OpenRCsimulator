## Review completed

I found **six reproducible correctness problems in the playable helicopter path**, plus **one separate HX-700 laboratory API defect**. The strongest findings concern ground yaw control, the transition between low-RPM and normal rotor equations, and disagreement between helicopter contact physics and the Club lake bank.

I also tested two optimization candidates. Both preserved the sampled outputs, but **neither timing experiment established a reliable speedup**. They remain concrete opportunities to remove unnecessary work, with that limitation clearly recorded.

**Full report, reproduction scripts, candidate code, checked logs, source identities, and replay instructions:**  
[OpenRC_Helicopter_Audit_3e652a8_2026-11-06.zip](https://chatgpt.com/library?file_id=libfile_a440c2f9eda88191939b6fe81aa8143e&account_id=personal)

I read [`external Audits/CONSOLIDATED-AUDITS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/external%20Audits/CONSOLIDATED-AUDITS.md) before reviewing the code. Experiments used commit **`3e652a879ab8e928fc7d0b23d8303ac5724c3be6`**. During the review, `main` advanced to `2e2e349`; I checked that change and its newly added A13 audit. The responsible helicopter files remained unchanged, and the new audit did not duplicate these findings. The [closing comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/3e652a879ab8e928fc7d0b23d8303ac5724c3be6...2e2e3492e67d30635cc4e727025581e2848cdf2e) is included in the evidence.

The repository was left unchanged. Experimental candidates exist only in the audit package.

## What is actually implemented

The distinction between the helicopter implementations matters when judging realism:

| Implementation | Current role | Relevant characteristics |
|---|---|---|
| **X-Cell .60 Research Trainer** | Historical playable helicopter | 8.2 kg; 0.775 m main-rotor radius; 167 rad/s nominal shaft speed; normal/idle-up curves; trainer/direct cyclic; heading/rate yaw control. |
| **HX-700 Electric 3D Experimental** | Laboratory flight candidate | 5.2 kg; 0.70 m radius; 2,100 rpm nominal speed; body-rate FBL controller; independent generated configuration. The playable session deliberately refuses it. |
| **Advanced articulated HX-700** | Mechanical inspector and separate elasticity experiment | Articulated servos, swash, links, blade pitch and transmission motion. These presentation mechanisms do not yet supply achieved actuator states to flight dynamics. |

The project explicitly retains six open HX-700 release gates, including identified rotor/FBL dynamics, achieved servo states, freewheel/power-off behavior and flight-response validation. I respected those boundaries instead of treating provisional parameters or missing qualified autorotation as new discoveries. [Implementation status and model limits](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/docs/HELICOPTER.md#L3-L18)

The review followed both flight configurations through their generators and loader, rotor/inflow/airframe equations, drive coupling, electronics, integration, input conditioning, lifecycle, contact, presentation, camera and audio consumers. The advanced mechanism was examined separately.

## Findings at a glance

| ID | Priority | Finding | Demonstrated effect |
|---|---|---|---|
| **H01** | **P1** | Grounded heading reference continues accumulating | Centered yaw retains a saturated demand, including an opposite-sign demand, through arming and spool-up. |
| **H02** | **P2** | Low-RPM blend activates a rotor equation outside its domain | Accepted gust settings terminate a real 240 Hz ground startup after 740 accepted ticks. |
| **H03** | **P2** | Helicopter contact omits lake-bank geometry | A constructed accepted tick reports a tail-fin crash **157.3 mm above the composed bank**. |
| **H04** | **P2** | Mode confirmation becomes stale when collective moves | A previewed **−0.588°** change can authorize a subsequent **−10.084°** change. |
| **H05** | **P2** | Rotor-disc terrain rejection is not conservative | An accepted constructed tick misses at least **7.16 mm** of penetration of its declared disc proxy. |
| **H06** | **P3** | Collective display bypasses swash saturation | The display accessor reports **12.605°** while the rotor equations receive **6.865°**. |
| **H07** | **P3 — laboratory** | HX hover solver returns incompatible trim data | The solver reports convergence, but the same flight evaluator rejects its returned trim. |

These priorities reflect the demonstrated software consequences. They are not estimates of occurrence frequency during ordinary flying.

---

## H01 — Ground yaw input can leave a hidden, reversed command for startup

**Where:** [`electronics.gd:204–241`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/electronics.gd#L204-L241), [`helicopter_flight_session.gd:530–545`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L530-L545), and its [arming/hold guards](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L773-L810).

The controller has **two separate memories**: heading reference and yaw-rate integral. Its relevant structure is:

\[
\dot{\psi}_{ref}=r_{manual},
\]

\[
r_{target}=
\operatorname{clip}
\left(
r_{manual}+K_\psi\,\operatorname{wrap}(\psi_{ref}-\psi),
-r_{max},r_{max}
\right).
\]

The ground session prevents accumulation of the yaw integral by zeroing `result.derivative[5]`. It leaves the heading-reference derivative, `result.derivative[4]`, active.

Consequently, a stopped, disarmed helicopter can integrate commanded heading even though the aircraft cannot turn.

### Reproduction

Using the actual production session and keyboard-command conditioning:

- Apply positive yaw for 480 accepted ticks, then center for 60 ticks.
- Rotor speed, body position and actual heading remain unchanged.
- The heading reference advances **2.9997916667 rad**, while the yaw integral remains zero.
- With the stick centered, the controller still requests **+1.5 rad/s** and 0.175 rad tail collective.
- Arming and hold release accept. After another 1,200 spool ticks, the rotor reaches **616.72 rpm**, with the same yaw demand remaining.

Extending the positive command to 720 ticks exposes a more serious consequence. Reference advance becomes **4.4997916667 rad**. Shortest-angle wrapping converts the error to approximately −1.78339 rad, so the centered-stick target becomes **−1.5 rad/s**, opposite the earlier input. That demand persists while the rotor reaches **619.72 rpm**.

This proves a latent, potentially reversed control request. The experiment does not claim a flown upset or crash.

### Concrete improvement

Implement heading-reference tracking during constrained operation with ineffective rotor authority, and reconcile both controller memories with accepted aircraft heading before pickup.

The conditions need care:

- A powered helicopter that can legitimately yaw on the ground must retain that ability.
- An airborne coasting rotor can still have tail authority, so disabling heading control whenever drive hold is active would be too broad.
- Reference correction must obey accepted-state and rollback semantics, with equivalent native-backend behavior.

**Verification:** test stopped input in both directions, several wrap crossings, centering, arm, spool and liftoff; then add blocked-powered, legitimate ground-turn, recontact and checkpoint cases. Assert reference error and target rate, not merely the integral.

**Prior-work distinction:** ground heading/integrator tracking is already an [explicit plan requirement](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/docs/plans/helicopter.md#L791-L795). This is a newly reproduced implementation gap in that requirement, distinct from the older inverted Euler-heading limitation.

## H02 — The low-RPM transition has a mathematical domain gap

**Where:** [`main_rotor.gd:125–148`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/main_rotor.gd#L125-L148), [`low_rpm_transition():216–233`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/main_rotor.gd#L216-L233), and [`flight_dynamics.gd:338–353`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/flight_dynamics.gd#L338-L353).

Let \(U\) be main-hub crossflow magnitude, \(R\) rotor radius and \(\Omega_n\) nominal shaft speed. The transition endpoints are:

\[
\Omega_u=
\min\left(
\max\left(0.08\Omega_n,\frac{U}{0.15R}\right),
0.20\Omega_n
\right),
\qquad
\Omega_l=\frac{\Omega_u}{2}.
\]

Only the bounded startup law is evaluated below \(\Omega_l\). Immediately above it, the ordinary rotor law is also evaluated as a blend member. That ordinary law requires:

\[
\mu^2=\frac{U^2}{(\Omega R)^2}<2.
\]

Once the transition cap is active, the X-Cell lower endpoint is 16.7 rad/s. A gap therefore appears when:

\[
U>\sqrt{2}(16.7)(0.775)
=\boxed{18.303459\ \mathrm{m/s}}.
\]

At \(U=20\ \mathrm{m/s}\), the invalid interval is approximately:

\[
16.7<\Omega\le18.247917\ \mathrm{rad/s}.
\]

The production evaluators accept 16.700000 rad/s, reject 16.700001 and 17, then accept 18.5 rad/s.

**A smooth blend weight cannot make an undefined blend member evaluable.** Even when its weight is tiny, the implementation evaluates the ordinary equation first.

### Reachable session failure

The production ground session accepted:

- Mean wind: **15 m/s FROM 0°**.
- Gust peak: **8 m/s**.
- Duration: **12 s**; period: **120 s**; delay: zero.

After normal zero-pitch arming and hold release, it accepted 740 ticks at 240 Hz. At \(t=3.0833333333\) s:

- Accepted shaft speed: **16.6514856023 rad/s**.
- World wind: **[−19.1744775495, 0, 0] m/s**.
- The next RK trial fails with **“main-rotor advance ratio exceeds the kernel domain at this speed.”**
- The session becomes unflyable.

The calculation itself uses hub-relative airflow, including aircraft motion and \(\omega\times r\); the quoted world wind is a recorded environmental value.

Three steady-wind controls completed 2,400 ticks each. This is a strong-gust startup failure, not a claim that ordinary wind always prevents startup.

### Concrete improvement

Make the startup transition valid across its admitted envelope, or reject unsupported combined weather/start conditions before launch.

For a revised closure:

1. Keep the bounded law active wherever the other blend member is invalid.
2. Avoid activating arbitrarily close to the \(\mu^2=2\) singularity merely because the inequality barely passes.
3. Review main- and tail-rotor transitions together.
4. Preserve finite checks, stop events, refusal classification and rollback.

Removing the guard, zeroing wind or clamping advance ratio without a model justification would conceal the problem.

**Verification:** test both seams across crossflow, neighboring floating-point values, actual accepted-weather starts and coast-downs, tail saturation, and reference/native equivalence.

**Prior-work distinction:** broad low-speed/high-flow refusal was already known. The existing [one-second coast-down test](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/tests/test_heli_flight.gd#L113-L125) reproduces a different `aerodynamic_stage_refused` result. The new finding isolates this disjoint main-rotor transition and demonstrates its reachability in an admitted **240 Hz startup**.

## H03 — Helicopter contact physics ignores the lake bank

**Where:** [`lake_world.gd:75–84`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/render/lake/lake_world.gd#L75-L84), [`helicopter_main.gd:114–145`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/helicopter_main.gd#L114-L145), and the session’s [skid stage](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L530-L556) and [impact call](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L600-L608).

The lake renderer publishes a validated `lake_context` after preparing the bank. Helicopter startup checks `lake_error`, but does not transfer the successful lake context into helicopter physics.

Skids and terminal collision detection receive only dry `ground_surfaces`. They therefore omit the lake composition already supported by [`ground_terrain.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/ground_terrain.gd#L63-L110).

### Reproduction

Using stock Club, lake and X-Cell data, I tested a constructed upright reset at NED position `[110,171,-0.085]` m, downward velocity 1.2 m/s, and initially stopped rotor.

One real 240 Hz tick advances without a numerical fault, then reports a tail-fin crash. At its reported contact point:

| Quantity | NED-down coordinate |
|---|---:|
| Reported fin contact | −0.002282787 m |
| Composed dry-bank ground | +0.155043718 m |
| **Clearance above the bank** | **0.157326505 m** |

A separate component sweep produces roughly **236.72 N of premature skid support** above the same bank area.

The witness samples stock lake data and its composed terrain. Scene attachment and the missing transfer are established by source tracing; the lake scene was not rendered or attached in this headless probe.

### Concrete improvement

Carry one validated terrain identity through:

- Skid support and terminal impacts.
- Terrain bounds and ground-effect height.
- Camera clearance.
- Aftermath and ground-audio contact queries.
- Reset/checkpoint identity and backend eligibility.

The [helicopter audio contact path](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/audio/helicopter_audio.gd#L88-L115) also resamples dry terrain, so fixing only the crash detector would leave another inconsistent consumer.

Water can retain an explicit unsupported or terminal-contact policy. **This finding does not require implementing helicopter flotation.**

**Verification:** exercise accepted stock/custom lakes, disabled lake, dry landscapes, both bank edges, normals, support forces, first-contact location, restart/restore and ground effect.

**Prior-work distinction:** [commit `0fced1b`](https://github.com/bultodepapas/OpenRCsimulator/commit/0fced1b46f0056935ad1e17fb362411594cb4479) and [PR 8’s discussion](https://github.com/bultodepapas/OpenRCsimulator/pull/8#discussion_r4490036854) address failed shoreline attachment. They do not fix the missing physics context on the successful-attachment path.

## H04 — Mode confirmation can authorize a different pitch jump

**Where:** [`helicopter_flight_session.gd:820–832`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L820-L832), its [collective accessor](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L768-L771), and [HUD message rendering](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/helicopter_main.gd#L279-L294).

The first request computes a pitch change but stores only the destination string in `pending_mode`. The second request accepts that destination even if collective has moved.

The stopped-ground reproduction:

1. Conditioned input raises collective to **94.1667%**.
2. The first request previews **11.7° → 11.1°**, an exact change of **−0.58823667°**.
3. Collective moves to zero over 460 accepted ticks; the original prompt remains.
4. The second request immediately accepts idle-up.
5. At the current inputs, production electronics changes from **−2.52101430° → −12.60507149°**: **−10.08405719°**.

That is a different control effect from the one the confirmation describes. The probe establishes the accepted action and electronics output; it does not demonstrate a powered maneuver afterward.

### Concrete improvement

Store the proposed transition’s source mode, destination mode, input generation and displayed pitch effect. Recompute it on confirmation. If the effect materially changed, update the preview and require another explicit press.

```gdscript
# Contract sketch, not a production patch.
var proposal = preview_mode_change(current_controls, next_mode)

if proposal.needs_confirmation and not pending.same_effect(proposal):
    pending = proposal
    show_mode_preview(proposal)
    return false

apply_mode(proposal.target_mode)
pending.clear()
```

Preserve physical-radio input. If the preview uses actual postmix pitch, its validity must include cyclic/trainer saturation effects too.

**Verification:** retain unchanged-stick confirmation; add movement between presses, both transition directions, saturation, pause, cancellation and controller recovery. Existing [control-action tests](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/tests/test_heli_control_actions.gd#L61-L65) cover only the unchanged-stick case.

**Prior-work distinction:** the intrinsic normal/idle-up curve discontinuity was already reported and may be deliberate radio behavior. This finding concerns the implemented confirmation becoming stale.

## H05 — A safe candidate point is incorrectly treated as a safe rotor disc

**Where:** [`impact_detector.gd:439–485`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/impact_detector.gd#L439-L485).

The documented fast-rotor terrain proxy is a [conservative disc](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/docs/HELICOPTER.md#L75-L79).

For disc-centre down coordinate \(c_D\), unit-normal down component \(n_D\), radius \(R\), and upper terrain-height bound \(h_{max}\), a sufficient clearance condition is:

\[
c_D+R\sqrt{1-n_D^2}+h_{max}<0.
\]

The outer test includes this whole-disc support. Inside the subsequent gradient iteration, however, `support_extent_down` becomes zero after the first iteration. The function can return `possible=false` because **one candidate point** is above the highest terrain, although other points on the tilted disc are lower.

There is a second mathematical weakness: four local-gradient iterations do not establish the global maximum of

\[
p_D+h(p_N,p_E)
\]

over a disc on non-monotone terrain.

### Reproduction

A constructed stock X-Cell reset uses:

- Position `[200,200.274,-0.245]` m.
- Inverted quaternion `[0,1,0,0]`.
- Body vertical velocity −1.68 m/s, corresponding to world-down +1.68 m/s.
- Main speed 167 rad/s and zero initial flap.

Initially, the horizontal disc is clear of the entire terrain-height bound. One actual 240 Hz tick accepts with no fault and no crash.

At the accepted endpoint, the detector reports `possible=false`, depth `-INF`. Independent samples in the actual tilted disc find:

\[
p_D=0.001478044\ \mathrm{m},
\qquad
h=0.005683942\ \mathrm{m},
\]

\[
p_D+h=\boxed{0.007161985\ \mathrm{m}}.
\]

That proves at least **7.16 mm of penetration of the declared proxy**. A separate flat-disc case also misses an interior crest, so deleting the bad inner return alone would not establish conservative coverage.

### Concrete improvement

Keep the valid outer bound. Replace the local-safe-point rejection with a conservative terrain search:

- Exact support is suitable for a planar surface.
- Analytic microrelief needs bounded subdivision, interval bounds or a conservative remainder.
- Preserve swept-event ordering.
- Keep phase-resolved blade physics distinct from this disc proxy.

Dense sampling is useful for discovering counterexamples, but is not itself a proof of conservatism.

**Verification:** retain both witnesses; test tilted and flat boundaries, both rotors, speed thresholds, interior crests, competing scenery contacts and rollback.

The demonstrated condition is inverted, very low, and involves sub-centimetre relief. It proves a missed proxy contact, not exact blade-phase intersection or its frequency during piloted flight. HELI-33’s acknowledged phase and elasticity limitations do not cover this invalid rejection of the implemented proxy.

## H06 — The collective display can disagree substantially with rotor input

**Where:** [`helicopter_main.gd:282`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/helicopter_main.gd#L282), [`collective_pitch():768–771`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/sim/helicopter_flight_session.gd#L768-L771), and [`electronics.gd:186–203`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/electronics.gd#L186-L203).

The HUD accessor samples the authored collective curve and gain. The rotor equations receive collective **after** servo mixing, individual travel limits and inverse linkage.

At full collective with neutral cyclic, both give **12.60507149°**. With accepted DIRECT CYCLIC inputs roll +1 and pitch −1:

\[
s=[2,\ 1.3660254,\ -0.3660254]
\]

becomes

\[
s_{clipped}=[1,\ 1,\ -0.3660254].
\]

The inverse mix gives:

\[
\theta_{0,used}
=0.22\frac{1+1-0.3660254}{3}
=0.11982480\ \mathrm{rad}
=6.86546^\circ.
\]

The display accessor remains at 12.60507°: a **5.73962° discrepancy**.

The saturation is intentional. The problem is that the displayed angle does not identify the angle used by the rotor equations.

### Concrete improvement

Display the accepted-state postmix value already available through [presentation telemetry](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/helicopter_main.gd#L374-L385), optionally alongside a separately labeled requested-curve angle and saturation indication.

Do not replace `collective_pitch()` globally without checking its callers: startup pickup, mode preview and the audio load proxy currently use it.

**Verification:** compare HUD data against same-state electronics output through neutral/saturated cyclic, both collective signs, trainer/direct changes and mode transitions. Define whether displayed values are accepted or interpolated.

This is separate from the already documented absence of achieved physical servo dynamics.

## H07 — HX-700 trim succeeds, then its consumer rejects the result

**Where:** [`trim.gd:98–109`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/trim.gd#L98-L109), [solver evaluation](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/trim.gd#L127-L153), and [`electronics.gd:307–322`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/electronics.gd#L307-L322).

The hover solver accepts the HX context with `flight_mode="3d"`. During solving, it uses trainer-disabled electronics and a tail-only trim offset.

After convergence, it unconditionally returns `roll_reference_rad` and `pitch_reference_rad`. The body-rate FBL controller deliberately rejects either key.

The clean reproduction:

- Converges in **six iterations**.
- Reports `ok=true`.
- Has scaled residual **\(9.94946\times10^{-14}\)**.
- Produces `electronics_refused` when its returned trim is passed to the flight evaluator.
- Refuses both returned-stick and neutral-cyclic variants.
- Accepts the same solved state/sticks with the solver’s original tail-only offset.

### Concrete improvement

Either explicitly reject unsupported FBL trim before claiming success, or emit a controller-law-specific trim contract.

For a supported FBL result, verify that neutral rate sticks plus returned collective and trim reproduce the converged forces, moments and shaft balance. Avoid applying solved cyclic twice through both stick and bias.

**Verification:** add a round-trip test for every accepted controller/mode pair, followed by a small accepted integration step. Preserve the intentional rejection of attitude references and all HX release gates.

This is a laboratory API consistency defect. It has no current playable-HX exposure.

---

## Optimization results

### O01 — Remove angular-derivative work that is immediately overwritten

In [`flight_dynamics.gd:200–224`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/flight_dynamics.gd#L200-L224), the geared coupling already supplies authoritative angular acceleration. The evaluator then:

1. Builds an effective moment.
2. Calls the full rigid-body derivative.
3. Overwrites its last three outputs with the coupling acceleration.

The discarded work in [`rigid_body.gd:121–137`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rigid_body.gd#L121-L137) includes inertia multiplication, rotor momentum addition, a cross product and inverse-inertia multiplication.

The coupling itself must remain intact:

\[
J\dot\omega=M-\omega\times(J\omega+\Omega b)-b\dot\Omega,
\]

\[
I_s\dot\Omega+b^T\dot\omega=Q.
\]

The opportunity is to compute translation and quaternion derivatives, then use the existing coupled angular solution directly. The [native implementation already follows that structure](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/research/native-kernel/src/nk_helicopter_stage.hpp#L283-L311).

The isolated candidate preserved arithmetic order and quaternion-norm handling. It passed **1,704 assertions**, including **1,458 complete serialized result comparisons**, both configurations, invalid inputs, 240 accepted trajectory steps and two rotor-stop cases.

**Timing was inconclusive.** Eight baseline batches ranged 573,801–854,064 μs per 3,000 evaluations; candidate batches ranged 561,779–885,308 μs. This supports a verified work-elimination candidate, not a demonstrated throughput or FPS gain.

### O02 — Postpone hull-reach square root until after the maximum

[`impact_detector.gd:164–176`](https://github.com/bultodepapas/OpenRCsimulator/blob/3e652a879ab8e928fc7d0b23d8303ac5724c3be6/app/physics/rotorcraft/impact_detector.gd#L164-L176) recomputes 56 stock probe norms during cache validation.

For finite nonnegative squared norms:

\[
\max_i\sqrt{s_i}=\sqrt{\max_i s_i}.
\]

A candidate retained validation and the original sum order while reducing this loop from **56 source square roots to one**. It passed **2,107 sampled assertions**, including mutable-cache rejection cases and complete detector-output comparisons.

Its ABBA timings were also inconsistent. I would retain the candidate and evidence, but require a stable complete-workload benefit before integrating it.

## Verification and limits

The experiments used **Godot `4.8.beta2.official.cafc17a19`**, Linux x86-64, **240 Hz**, float64 state and reference GDScript physics.

| Check | Result |
|---|---|
| Ground yaw, mode preview and collective counterexamples | Clean production-session/input reproductions |
| Gust startup | Reproduced; retained-script rerun matched |
| Steady-wind controls | Three cases completed 2,400 ticks each |
| Bank and rotor-disc cases | Accepted production-session ticks from constructed resets |
| HX trim contract | Clean convergence/refusal/control reproduction |
| Existing electronics/lifecycle/swash tests | **33/33, 19/19, 51/51** |
| Generator checks | Artifacts fresh; **5/5 X-Cell and 2/2 HX tests** |
| Optimization parity | **1,704/1,704 and 2,107/2,107 assertions** |
| Fresh package reconstruction | Four imports and four representative probes passed without engine diagnostics |

The separate Python schema test could not start because `jsonschema` was unavailable; it is not counted as a pass or a simulator defect.

Controls probes used three unused scenery-builder stubs; contact probes used 15 neutral placeholders for unused graphical preloads. Production physics and session sources were preserved. The review does not establish rendered UI behavior, audible sound, physical-transmitter behavior, native-backend execution, target-GPU performance or independent helicopter fidelity.

The package retains failed exploratory attempts separately from accepted evidence. A passing counterexample script means the problem reproduced—it does not mean a repair was applied.

### Recommended implementation order

I would address **H01 and H04 first**, because they make accepted pilot actions produce persistent or unreviewed control effects. Next, resolve **H02’s admitted startup envelope**, then unify terrain identity and conservative contact behavior for **H03/H05**. Follow with the telemetry correction and HX trim contract.

For performance work, preserve the numerical comparisons and profile the complete target workload before adopting either candidate. The most valuable immediate changes are the ones that make the existing control, equation-domain and geometry contracts agree; those provide a sound basis for the later HX-700 realism work.