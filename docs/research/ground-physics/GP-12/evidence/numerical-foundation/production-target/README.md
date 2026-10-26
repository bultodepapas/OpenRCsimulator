# Production-target foundation handoff

Review-only payload is under `app/`; nothing has been copied to main. The
manifest pins current-main preconditions and every target/fixture hash.
`review.patch` is the textual diff; six binary fixtures are copied losslessly
from the reviewed captures and frozen outputs, not represented by text diffs.

Five runtime files: QP, AR core, bounded Strategy, Impulse, Step. Impulse calls
Strategy only for bounded solve; all proof/digest/bounds calls go straight to AR.
Strategy forwards no proof API. These are mechanical import changes from the
completed frozen numerical foundation. Mathematical outputs/certificates and
whole Step output bytes match that source. There are no temporary imports in
the production payload.

New paired tests: strategy34, slip19, work24. The existing AR53 test is included
unchanged for validation and need not be overwritten. Total130/0 focused checks.
Two retained whole-Step checkpoint comparisons add14/0 and confirm complete
state/receipt/event byte equality after import cleanup. Validation scripts use
absolute sibling imports only to run the unpromoted payload against the existing
import cache. Production scripts use `res://` paths.

Frozen outputs bind five exact inputs, old-main strict/opt-in outputs, and the
reviewed candidate outputs, including old-main ordinary successful shaft cases.
Every fixture has a pinned hash. New tests verify complete default bytes, full
candidate bytes, exact input binding, budget accounting and malformed/positive
work controls. The binary includes exact source identities. Preserve bytes
across checkout with `/app/tests/fixtures/ground_contact_*.bin -text` and verify
the fixture hashes in a fresh clone when retaining this patch.

Use `../gp12-local-reuse/foundation-report.json` for the original complete10s
tape and corrected full-reaction postprocessing, clearly separate from open
drop/branch/performance gates. Promotion remains subject to root review and main
checked regressions. No new flight or production performance qualification.
