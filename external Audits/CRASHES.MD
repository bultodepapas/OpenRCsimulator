**The senior-developer handoff is ready.** It contains more than **35,000 words across seven Markdown documents**, a combined reading copy, detailed pricing research, **19 implementation work packages**, **46 proposed acceptance cases**, and **eight release gates**.

The package is grounded in the reviewed repository and explicitly separates existing behavior, proposed changes, verified test results, and unresolved research.

## Download the handoff

- **Complete package to forward:** [OpenRC_Crash_Cost_Senior_Handoff_2026-11-09.zip](https://chatgpt.com/library?file_id=libfile_fde3_f-7b0acda58c488191a870d0d86206d22c_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) — all Markdown documents, research JSON, acceptance matrix, reproducibility tool, and retained evidence.
- **Everything in one Markdown document:** [OPENRC_CRASH_COST_SENIOR_HANDOFF.md](https://chatgpt.com/library?file_id=libfile_fde3_f-bcbd77ab586c8191a70c72fd12960bfc_ac5d15b10f548191b3cb750779cf7c10&account_id=personal).

### Individual documents

| Document | What the senior developer will find |
|---|---|
| [README.md](https://chatgpt.com/library?file_id=libfile_fde3_f-0b5ca6acf31081919c9c46b1fb4609df_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | Reading order, scope, key decisions, evidence boundaries, and a ready-to-forward handoff note. |
| [01_EXECUTION_PLAN.md](https://chatgpt.com/library?file_id=libfile_fde3_f-7e9e1bdaa4a08191872e975f5347c3eb_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | Nineteen sequenced work packages with owners, dependencies, files to inspect, required changes, tests, and concrete completion criteria. |
| [02_RUNTIME_IMPLEMENTATION_SPEC.md](https://chatgpt.com/library?file_id=libfile_fde3_f-9135263684388191a4ab16ee6cca2a9e_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | The current call graph and proposed runtime changes: accepted contacts, local damage, persistent evidence, inspections, component reuse, hazards, reporting, and restoration. |
| [03_TEST_AND_RELEASE_SPEC.md](https://chatgpt.com/library?file_id=libfile_fde3_f-081178fbfe5c8191968416417467903c_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | All 46 proposed cases, independent accounting fixtures, checked commands, actual player journeys, eight gates, and adversarial review questions. |
| [04_FLEET_AND_PRICE_WORKBOOK.md](https://chatgpt.com/library?file_id=libfile_fde3_f-01181c3fb2e48191977f6a7ed42b485c_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | Every current catalog route, actual component identifiers and quantities, researched prices, package contents, labor assumptions, missing information, and per-aircraft tasks. |
| [05_DATA_CONTRACT_AND_AUTHORING_STANDARD.md](https://chatgpt.com/library?file_id=libfile_fde3_f-0941ff1bb3048191a14af76edb0a92b8_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | The proposed standard for existing and future aircraft: physical versus financial components, damage regions, packages, provenance, schemas, compatibility, migration, and validation. |
| [06_RESEARCH_AND_BASELINE_NOTES.md](https://chatgpt.com/library?file_id=libfile_fde3_f-9a2732b2427c8191b9c4db0ac06db856_ac5d15b10f548191b3cb750779cf7c10&account_id=personal) | Repository changes since the audit, existing documents to reuse, explanations for the wide ranges, new research findings, corrections, and exact verification limits. |

## What I advanced for the developer

### 1. A defined normal-player experience

The plan requires the game to produce an **automatic, deterministic repair assessment** after a relevant accident. The player should receive a useful local estimate without needing a developer to inject inspection results or manually construct the final bill.

For common supported incidents, the report must explain:

- Which components were affected.
- Which components can be reused under the declared game policy.
- Which parts should be repaired or replaced.
- Which purchased packages cover those requirements.
- Parts, labor, and applicable fees.
- The assumptions or missing information that materially affect the result.

Ordinary uneventful flights should remain quiet. A relevant accident should progress to a meaningful estimate rather than remaining indefinitely in an unresolved inspection state.

The plan also preserves the distinction between **a reliable game model** and **a physically validated failure prediction**. The developer can ship convincing, consistent game outcomes using documented assumptions without claiming measured material strengths or universal survival probabilities.

### 2. An implementation sequence tied to the existing code

The work packages identify what to retain and where to make changes. The existing catalog generators, integer-cent accounting, incident ownership, inspection machinery, settlement behavior, and focused tests provide useful foundations.

The sequence is:

1. Pin the implementation revision and turn the findings into discriminating regression fixtures.
2. Establish compatible aircraft identities and the financial-component contract.
3. Preserve accepted contact evidence and finalize each simulation tick consistently.
4. Fix bounded incident history, duplicate handling, reimpact, and stale inspection decisions.
5. Complete the propeller, ordinary landing-gear, and water observation paths needed by the promised behavior.
6. Connect automatic local damage assessment to normal play.
7. Correct scoped totals, repair choices, packages, labor, and historical price snapshots.
8. Complete the fleet data and normal-player acceptance.
9. Conduct independent review and remove the relevant experimental label only after the gates pass.

Each package has its own definition of completion. This gives the senior developer a practical way to split the project into reviewable changes while keeping the final fleet-wide objective intact.

### 3. Specific treatment of the failures that make costs unreliable

The runtime and test specifications address the important failure modes directly:

- **Repeated contact:** a scrape that gets worse must retain the later evidence and update the affected component.
- **Journal overflow:** a later wing or gear hit cannot disappear because the diagnostic event list is full.
- **Reimpact after inspection:** a component previously considered reusable must be reassessed when relevant new evidence arrives.
- **Disposition downgrade:** a later request to inspect a part must not erase an already confirmed replacement.
- **Duplicate events:** repeated notifications must not create extra purchases, fees, or revisions.
- **Simultaneous contacts:** multiple probes describing one encounter must not each spend the aircraft’s entire impact-energy budget.
- **Restore behavior:** loading a physics-only checkpoint must not silently present unknown prior damage history as a clean aircraft.
- **Graphics independence:** camera position, visual effects, and graphics settings must not change the financial result.

The plan also requires the ordinary gear observation or reviewed proxy needed to distinguish a normal touchdown from a damaging landing. An absent gear-limit event cannot, by itself, prove that the landing caused no damage.

### 4. A stronger definition of “works for every airplane”

I closed a significant loophole during the independent review: **one working propeller bill per airplane is insufficient to call the cost model complete.**

The final release requirement is a coverage ledger across:

**Aircraft route × common incident class × essential affected component group.**

Every essential group in those supported scenarios must have a compatible researched price or an explicitly reviewed game allowance. A route with a priced propeller but missing required wing or landing-gear costs must fail the completion gate.

That requirement covers the **11 fixed-wing configurations**, including the three retained glow variants. The research helicopter has a separate work package because its empty economic inventory cannot support a credible rotorcraft estimate. The plan distinguishes an airplane-wide release from a later claim covering every catalog route.

## Research and prices are prepared for review and import

The workbook includes **27 reviewed prior observations, 17 additional or rechecked observations, and two unpriced research leads**. Those are evidence records; they are not all approved installed-part matches.

One important result of the research is that a plausible price can still be wrong for the modeled installation.

| Research finding | Why it changes the implementation |
|---|---|
| CARF lists Corsair plug-in outer wings at **$341 each**, folding wings at **$754 each**, and a plug-in center wing at **$812**. | These are different variants and purchase scopes. They must not become the low and high ends of one generic “wing price.” The developer must resolve the installed configuration and coverage first. [carf-models.com](https://carf-models.com/en/products/f4u-1d-corsair/id/301/region/5?utm_source=chatgpt.com) |
| The SebArt A200 list includes a **€703 wing set**, **€1,709 fuselage**, **€228 tail set**, and **€650 electric landing-gear set**, with a stated VAT basis. | These provide useful structural and package references, but the current list’s revision and electric gear must be reconciled with the authored aircraft before binding them as exact replacements. [MINI JET class](https://www.sebart.it/download/sebart-pricelist.pdf?utm_source=chatgpt.com) |
| Moki’s standard 250 listing describes an engine with electronic ignition and a mounted ring muffler, at **€4,098 including VAT for Germany**. | Package membership matters: an included ignition or exhaust must not be billed again. The contents of another seller’s engine package still need their own verification. [MOKI-Motoren](https://www.mokimotor.de/produkte/motoren/moki-250/?utm_source=chatgpt.com) |

I corrected **eight classifications that overstated variant or package certainty**, preserving the original observations and adding an explicit correction history. These include the Corsair wing conflict, CARF gear references versus the modeled Sierra assemblies, fuselage coverage, and the A200 commercial-package revision.

The workbook also specifies how to handle:

- A bare wing versus a wing containing servos.
- A wheel pair purchased to replace one damaged wheel.
- A complete PNP package versus separately purchased parts.
- Reusable electronics supplied again inside a replacement package.
- Shared removal, installation, and inspection labor.
- DIY cash cost versus paid shop labor.
- Native currencies, included taxes, exclusions, and any later conversion policy.

## Tests and reproducibility

I added a portable historical-baseline reproducer and executed it successfully in a fresh isolated project.

| Verification | Result |
|---|---|
| Fresh isolated project import | Passed |
| Existing economics scripts | **12 scripts; 674 assertions passed** |
| Constructed current-behavior audit probes | **10 passed** |
| Historical source manifest | **217 source hashes verified** |
| Minimal reconstructed dependency selection | **79 scripts**, with the excluded runtime branch documented |
| Checked execution reports | **14 successful reports retained** |
| Document links, case identifiers, JSON, and archive integrity | Validated |

The probes include demonstrations of undesirable current behavior. Passing those probes confirms the baseline observation; it does not mean the corresponding defect has been fixed.

The **46 proposed acceptance cases remain implementation work**. They cover landing gear, local structure, propellers and powertrains, turbine scenarios, water and battery hazards, event integrity, persistence, accounting, fleet coverage, and the actual player journey.

One particularly important requirement is to exercise the normal flight route. The reviewed startup code can exclude accident reporting during scripted, capture, or trace runs, so a successful simulation run can bypass the feature being tested. The handoff requires evidence from contact through automatic assessment, revised cost, visible report, and archive in normal play. The relevant creation guard is linked in the [pinned `main.gd` source](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/main.gd#L1169-L1184).

## What to hand over

**Send the ZIP to the senior developer and have them start with README, the execution plan, and the runtime specification.** The combined Markdown is convenient for reading or discussing the whole proposal.

The production repository remains unchanged. This delivery contains the detailed implementation specification, advanced research, corrected evidence, test plan, and reproducible baseline. The first development milestone is a complete local accident-to-cost flow in normal play; the final airplane milestone requires all essential common-incident coverage, persistence, accounting, UI, and release gates to pass.