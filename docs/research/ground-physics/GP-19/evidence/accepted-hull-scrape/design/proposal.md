# GP19 accepted hull scrape: bounded next implementation

2026-10-26. Read-only audit; no app edits or native audio. Read the audio tool
index/README and current HullContact, Session, crash Director, CrashAudio and
retained asset ledgers. Graph lookup had no indexed matches; current source was
then inspected. Seven selected source/ledger files are frozen under `source/`.

## Concrete gap and baseline

Director currently render-polls `soft_contacts` in `_touch_feedback`, deduplicates
only the latest rendered tick, then issues scrape one-shots using slide speed and
120ms wall-time pacing. A touch that begins/ends between rendered frames can be
missed. Geometric contact is not proof of loaded friction.

The existing HullContact force loop already computes the positive unilateral
normal load, tangent velocity, friction scale and tangent force. Its separate
`contacts()` feed only contains geometry and velocities.

`checks/baseline-02` completes **10 checks, zero diagnostics**, using the existing
law on one explicitly synthetic COM point. `observations.json` shows:

- Loaded sliding: 10 m/s, 2 mm compression, 7.2 N normal force and 28.8 W tangent loss.
- Opening at 1 m/s with the same overlap/slide: clamped normal force 0, no friction
  load and 0 W, while `contacts()` still reports a 10 m/s geometric slide. The current
  speed-only scrape branch would qualify it.
- Loaded stationary contact: positive normal load, zero tangent power.

This is an instantaneous force/feed distinction, not an accepted-interval work or
audibility measurement. The first draft-only probe failed type inference; its
rejected receipt remains separate. No physics or assets were modified.

## Smallest source seam: optional exact-law diagnostics

Own only four runtime paths initially:

1. `app/physics/hull_contact.gd`: optional diagnostic output in the **existing**
   loads loop, forwarded through `loads_properties`. Keep every force expression,
   operation order, default return and existing no-diagnostic call unchanged.
   Do not implement a second friction formula in audio or `contacts()`.
2. `app/sim/flight_session.gd`: accepted-endpoint producer/cache and one additive
   read-only method. Existing contact_events/soft_contacts/checkpoint shapes stay
   unchanged. This file needs root's surgical integration/ownership coordination.
3. `app/render/crash/director.gd`: accepted-tick wiring/priming and exclusive
   continuing-flight scrape ownership; existing visual trail pacing stays intact.
4. `app/render/crash/crash_audio.gd`: bounded capture/grain scheduling inside the
   existing player pool, plus explicit soft-scrape cancellation on terminal handoff.

Suggested pure optional extension:

`HullContact.loads(s, prepared, lake_samples = [], diagnostics_out = null)`

The nullable output avoids allocating diagnostic rows on ordinary RK calls.
When requested at the accepted endpoint, append loaded point rows using the
already computed `f_up`, `(f_n,f_e)`, `(v_n,v_e)` and physical point position:

`P_t = -(F_t · v_t,relative) >= 0`.

For static flat ground, actual relative tangent velocity is the current point
velocity in the field plane. Zero-clamped normal load yields no loaded row and
no scrape power, even if geometric contacts remain. Stationary loaded rows have
zero power. The implementation must verify the reported dot product against
actual force virtual work and finite/passive bounds.

For finite-fuel aircraft, forward diagnostics through the existing
`loads_properties` owner using its accepted live mass/inertia sample; never reuse
constant-build stiffness. This is one extra **physics-owner endpoint query** when
contact observation is needed, not a render-frame force evaluation or a change to
the integrated loads. No mutable diagnostic collection runs during RK trials.
First scope is the current qualified flat-solid branch. A loaded lake/bed/bank
branch without matching exact diagnostics returns explicit unavailable rather
than guessing a tangent or relabeling water. Flat rows outside a configured lake
can remain supported only when the source can certify the complete batch.

## Exact proposed physical packet

`FlightSession.hull_scrape_observation()` returns nine closed keys:

```text
schema = "openrc-hull-friction-observation"
version = 1
tick: int
generation: int                 # local statistics_generation, nonnegative
law_identity: String            # existing HullContact law identity
available: bool
sampling = "accepted_endpoint_instantaneous_power"
contacts: Array
reason: String
```

Each loaded row has exactly contact_id, point_ned, normal_force_n,
tangent_force_ned_n, relative_tangent_velocity_ned_mps, friction_power_w,
material_id. All simulation vectors remain packed float64 triples. IDs come from
existing hull bindings, never invented structural section IDs. Material identity
comes only from Environment.sample_support at that point; its terrain geometry
does not replace the hull's actual flat law. Unknown material stays empty/unknown.
Contact/component labels do not imply intended support, damage or benign belly
contact; this remains independent of any X8 role qualification.

The Session computes/caches this only for the current accepted boundary, after its
existing first stepped handler has committed contact state. It may lazily request
the optional same-law diagnostics within that accepted callback, once per tick.
It must refuse stale bindings/unready pending configuration and invalidate derived
cache on reset/restore and source/field binding changes. It adds no physical state,
checkpoint key, accumulator or statistics event.

**Do not call `P_t*h` integrated accepted work.** At most that is an explicitly
labelled endpoint rectangle approximation for presentation weighting. Accurate
interval work requires accepted-path quadrature/receipts and separate integration
qualification. No damage/heat ledger is updated from this sound observation.

## Existing asset and voice ownership

Use the existing generic CrashAudio `scrape.wav` for the first extension. Its
retained source ledger says original offline synthesis, not a recording. Reusing
this available asset is sensible; no replacement with wheel-roll recordings is
needed just for a provenance label, and no new synthesis/download is proposed.
Downloaded CC0 landing-gear textures already exist, but are wheel/footstep proxies,
not calibrated hull scraping. Any later material substitution needs its own
audition; do not infer gravel from rough usage or acoustic gain from friction μ.

Prefer **power-driven short grains**, retaining the existing scrape transient and
roughly 120 ms pacing, instead of assuming it can become a seamless loop. Capture
each accepted packet, accumulate only the observed presentation window and queue
one bounded aggregate grain using power-weighted physical position. Reuse the
existing authored gain/pitch envelope limits; any reference-power normalization
must be explicitly an authored mix convention, not measured acoustic efficiency.
Zero physical tangent power produces no friction grain. No proposed numerical
sound scale is claimed calibrated by this audit.

Tag soft-scrape uses within the existing seven one-shot slots. Do not add another
bus/player bank or exceed the existing eight total voices (including fire).
Terminal `impact()` clears queued/tagged continuing-flight scrape before primary
impact layers; water reset does the same. Wreck.secondary and terminal layers
then remain their existing exclusive aftermath owners. Never run both the new
accepted scrape grains and Director's legacy sliding `audio.touch` calls.
New-touch non-sliding thuds/visual marks retain their existing behavior initially.

## Accepted capture and lifecycle

CrashAudio can mirror the existing opt-in accepted capture pattern:
`set_accepted_hull_observation(enabled)` and `observe_accepted(snapshot)` while
keeping current impact/touch/update signatures for legacy benches.

Director connects once to stepped **after Session**, captures only detached SI
data and converts NED positions at playback. The presentation wrapper supplies
tick_rate, actual paused state and terminal outcome separately from the strict
physical packet. Queue capacity 64 and bounded age follow existing GP19 practice;
drop-oldest overflow is explicit in diagnostics. No playback/bus work occurs in
the physics callback.

Duplicate ticks do not retrigger. Gaps/rewinds/rate or generation changes prime;
paused manual steps never queue replay-on-resume grains. Reset/restore/detach
clear capture and tagged voices. Prime again on the existing lifecycle receipt
after its generation update so tick0 priming cannot discard the first actual
post-reset motion. Terminal outcome clears living-hull capture even if a guard
fires without a new tick. Live render update must apply current pause handling to
the shared audio owner as well as the existing crash branch.

## Gates before activation

Draft outside app, then root reviews the four-path patch. Add focused force-metric
and accepted-audio tests using the existing checked runner with Dummy:

- Exact default load bytes and full Session checkpoint parity on/off, including
  finite fuel; independent tangent virtual-work/zero-load/zero-slip cases.
- Same accepted tape at 30/60/144 Hz drain cadence, brief loaded contact between
  renders, reverse/stop, duplicates, rejected ticks and queue age/overflow.
- Paused manual step, resume, reset/restore, generation, detach/reconfigure and
  exact connection/bus/voice counts; terminal and water handoff cannot double-play.
- Existing crash/audio/soft-hull regressions remain unchanged in legacy mode.

Only software/playback planning is qualified by Dummy. Native audition/capture,
mix/headroom and quiet-host timing follow after integration, when the solver-tape
owner releases timing resources. No physical material/sound calibration, rolling
sound replacement or new damage classification is part of this slice.
