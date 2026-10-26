# Independent accepted hull-scrape review

Four runtime drafts only; no app edits. Supported within the initialized Session,
flat-solid diagnostic scope. No remaining reproduced blocker after the fixes.

The optional diagnostic branch follows the existing positive-normal-force guard
and uses the exact computed Ft and rigid point vt. Its power is -Ft dot vt,
including body rotation at the datum arm; overlap/speed alone cannot create a
row or power. Existing force expressions/order, mass preparation and default
return envelopes are unchanged. Default calls add type guards only and allocate
no diagnostic arrays; enabled endpoint observation does extra force/query/key
work, so no zero-overhead or performance qualification is implied.

Session observes the committed endpoint after its existing contact handler,
binds actual probe IDs and material query, and refuses pending source/lake scope.
Live mass/CG uses loads_at_properties at the accepted fuel state. The derived
cache is detached, invalidated by state/layout/field key and reset/restore, and
absent from physical checkpoints. Paused manual steps, generation replacement,
reattach and water/terminal handoff are covered by the actual Session harness.

Three issues were corrected before this review completed: invalid packets now
discard pending grains; capture cancellation no longer touches native players;
finite float64 positions outside the float32 render domain are refused. The
last was independently reproduced on snapshot0afc5c24 as an accepted1e50 point
becoming a nonfinite Vector3. The original source/result and passing diagnostic
reproduction remain retained separately from the corrected acceptance tests.

On corrected CrashAudio d1cebf6a,14 independent strict assertions verify capture
player/gain/RNG isolation, render stop-before-new-grain order, invalid fail-quiet
behavior, large supported1e30 positions, huge1e50 rejection, input detachment,
rewind branch preservation and bus/pool release. An initial review assertion
compared the float32 stored gain to a double .2; its rejected receipt is retained.
The corrected assertion compares the actual stored before/after gain bytes.

The existing367-check frozen-force/virtual-work harness and44-check actual
Session/finite-fuel harness were also independently run, clean and strict.
These411 are repeated existing checks, not new tests. Producer505 receipts,
source hashes and projection manifest were read/verified separately. Promotion
must use exact payload-file hashes, not the LF-normalized promotion-text hashes.
The new frozen hull-friction fixture requires its declared -text attribute.

All packet keysets are closed; positive loaded rows, finite SI fields, dot-power
consistency, unique IDs,64 queued grains and the existing7+1 pool are checked.
The250ms age bound uses accepted simulation time, not wall-clock latency on a
stalled host. Gain/reference power are authored presentation choices, not
acoustic calibration. Dummy tests cannot qualify listening, native headroom,
mixing or frame cost. The native post-review gate remains necessary.

Final Director d4fa35e1 adds only the two sim-null lifecycle guards; the44-check
Session harness including that valid-context edge was rerun independently. Final
CrashAudio daf7bc27 differs from the independently tested d1cebf6a only in its
accepted-simulation-time age comment; exact normalized text comparison passes.
