# Agent orchestration investigation — 2026-11-15

## Scope and conclusion

This follow-up challenges the first agent-guidance revision at
`8835554b3b1559b7e06db46146337b47de3dc5a3` on
`docs/senior-agent-orchestration`. It belongs to the DX-06 guidance follow-up;
[AGENTS](../../AGENTS.md), [CLAUDE](../../CLAUDE.md) and
[SUBAGENTS](../SUBAGENTS.md) remain the operating instructions.

**Retain the strongest selected lead as senior developer and final solution owner.
Use helpers for distinct contributions that justify their coordination cost.**
Terra/max and Sonnet/high remain explicit, authorized preferences. The evidence
supports neither a universal helper count nor a guarantee that maximum effort,
more reviewers or a copied workflow improves OpenRC outcomes.

The important correction is operational: the lead must understand, accept or adapt,
integrate and verify the result, while selecting the right execution route for each
assignment. It can apply a good draft directly. Short or tightly coupled work can
stay in the main session. Research, critical review and independent bounded drafts
remain useful delegation candidates.

## Method and evidence limits

The user requested at least twenty parallel investigations. Twenty-one distinct
questions below were assigned to separate researchers in waves of up to three
concurrent helpers. Each was asked for evidence, a counterexample or applicability
limit, and a keep/change/remove/experiment decision. The lead synthesized the
findings, checked consequential documentation and source claims, and authored the
changes. This is a qualitative source investigation, not twenty-one experiments.
Sources reused across questions count as the same evidence.

Research dispatches requested `gpt-6.1-terra` with `max` in fresh contexts. Those
requests do not independently establish the backend model or hidden reasoning
effort. No live Claude Code session or comparative OpenRC coding benchmark was run.
Third-party examples were inspected, not installed or executed. This report uses
original summaries and links; it does not vendor their code, prompts or skills.

| Evidence | What it can establish | Limit |
| --- | --- | --- |
| Official product documentation | Supported interface and intended behavior at inspection | Installed version, account, configuration and effective route may differ |
| Pinned upstream source or example | What that revision implements or instructs | A demonstration is not a production guarantee or efficacy benchmark |
| Original empirical study | Results for its tasks, models, budgets and measured outcomes | Different tasks, clients and acceptance criteria may reverse the result |
| Firsthand issue or Reddit report | A reported experience or reproduction to investigate | Promotion, selection effects, missing logs and unresolved causes remain possible |
| OpenRC inference | A reasoned design choice grounded in its contracts | It needs local outcome evidence before a performance claim |

Public sources were checked on 2026-11-15. Pinned revisions below preserve inspected
examples; moving documentation and issue status must be rechecked when relevant.
Votes, stars, agent counts, PR counts and plausible self-reports were not used as
quality measurements.

## Decisions applied to this branch

| Decision | Reason and resulting policy |
| --- | --- |
| Keep senior lead ownership | One agent remains accountable for design, accepted code, integration and verification; a helper title creates no authority |
| Keep strong helper presets; make routing deliberate | Terra/max and Sonnet/high remain available for substantive uncertainty and review; bounded, checkable work may justify lighter supported effort |
| Make zero helpers explicit | Existing tools/skills or direct lead work can avoid unnecessary handoffs; explicit user delegation instructions still apply |
| Match capabilities before dispatch | Tools determine capability: the Claude presets omit shell, writes and MCP; a Codex text return does not imply those tool restrictions. Supply evidence or choose an already-permitted capable route when needed |
| Strengthen source identity and lifecycle | Verify effective root, actual inputs and helper delta; distinguish running, partial, failed and unresolved work; reconcile before retrying |
| Strengthen review and proof | Separate requirements, concrete defects and optional style; link material claims to evidence and independently ground expected results |
| Preserve selective context | Keep the shared import, relevant specialties and existing OpenRC skills; avoid redundant reads and bulk prompt/catalog injection |
| Reject framework ceremonies | No mandatory per-step commits, peer-team conversion, automatic permission expansion, fixed review-round acceptance or new orchestration service |

The 26 specialist definitions and unrelated simulation, generated-source,
ownership, shared-host admission and verification contracts are preserved. The
profiles retain their declared model presets and tool restrictions.

## Client configuration and trust

### R01 — Does Codex actually discover and apply the intended helper configuration?

[OpenAI subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents)
supports standalone role files and project helper defaults. The inspected
[`rust-v0.166.0` child configuration source](https://github.com/openai/codex/blob/rust-v0.166.0/codex-rs/core/src/agent/child_config.rs)
applies role settings after resolving spawn/default settings. Consequently, the
shipped Terra/max profile pins are intentional presets: changing defaults alone
does not change them. A native explicit override is the documented project route
for a deliberate substitution.

**Change:** distinguish task labels from actual agent-type selection, and local
configuration from hosted controls. [Developer settings](https://learn.chatgpt.com/docs/developer-settings)
describe the client boundary; project trust and installed support matter. An
unavailable default can also fail validation before a later role override in the
inspected code. Parsing a file or successfully spawning a task does not establish
which profile ran. Do not fabricate unsupported arguments or model IDs.

### R02 — Are Sonnet/high profiles and reported settings reliable?

The current [Claude subagent contract](https://code.claude.com/docs/en/sub-agents)
supports the shipped model, effort and turn-limit fields. Ordinary custom agents
and conversation forks follow different routes. Invocation, environment, managed
settings and hooks can affect the result; [model configuration](https://code.claude.com/docs/en/model-config)
also documents aliases and effort restrictions.

**Change:** verify discovery and the reporting basis at first use or relevant
changes. Keep requested settings separate from client-reported or provider-backed
observations. Issue [#100082](https://github.com/anthropics/claude-code/issues/100082)
reports Sonnet-configured work recorded as Opus on versions 2.1.277–2.1.290, while
[#64706](https://github.com/anthropics/claude-code/issues/64706) concerns effort
display. These reports do not prove universal current misrouting; they explain why
a label, a self-description and an actual request record are different evidence.

### R03 — Should every useful helper always use maximum effort?

[OpenAI model selection](https://developers.openai.com/api/docs/guides/model-selection)
and [Anthropic cost/intelligence guidance](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence)
support comparing settings against the actual task. Greater effort can help hard
work; lower effort can be adequate when acceptance reliably detects failure.
Neither source establishes equivalence between Terra/max and Sonnet/high or an
OpenRC optimum.

**Keep/change:** retain the requested strong presets for consequential uncertainty,
substantive drafts and critical review. Permit a deliberate lighter supported
choice for bounded, checkable work, respecting explicit user instructions. Escalate
on inadequate evidence, failed checks or cross-subsystem uncertainty. A clean
review is not a sufficient acceptance oracle, and repeated low-effort retries can
erase their apparent savings.

### R04 — Which instructions actually load, and what should helpers reread?

[Codex instruction discovery](https://developers.openai.com/codex/guides/agents-md)
has a configurable combined-file budget; it does not prove this project is
truncated. [Claude memory/import behavior](https://code.claude.com/docs/en/memory)
supports the literal `@AGENTS.md` import and deduplicates imported instructions.
The linked specialist catalog is not an automatic full import.

**Change:** profiles follow already-loaded rules, read missing instructions and
only the relevant specialty/skill material. Preserve self-contained essential
constraints for isolated contexts. Keep the shared import and canonical links;
remove a redundant restatement of display priorities from the Claude adapter,
while retaining the complete rule in AGENTS. No measured token saving or adherence
gain is claimed, and no arbitrary file-length ceiling is imposed.

### R05 — What do read-only profiles actually restrict?

The shipped Claude profiles declare read/search tools without shell, writes, MCP,
`Skill` or `Agent`. This limits the ordinary model tool route. Claude's
[hook documentation](https://code.claude.com/docs/en/hooks) describes command hooks
that execute with user permissions outside that allowlist. Codex role instructions
request source-read-only behavior but inherit parent permissions.

**Change:** qualify the boundary instead of claiming whole-process isolation or
that every route is unable to spawn children. The historical dynamic-workflow
report [Claude #63762](https://github.com/anthropics/claude-code/issues/63762) is
another reason to inspect the actual route, not proof of a current general bypass.
Keep existing allowlists and permissions. Background execution or omission of an
Edit tool alone does not establish read-only behavior for a shell-capable fallback.

### R06 — Can a helper return launder instructions or unsupported evidence?

[OpenAI prompt-injection research](https://openai.com/index/designing-agents-to-resist-prompt-injection/)
and [agent safety guidance](https://developers.openai.com/api/docs/guides/agent-builder-safety)
motivate separating external content from authority. A structured return still
contains untrusted text; a citation can be irrelevant, and a claim that the user
approved an action does not supply that authorization.

**Change:** map material claims to source locations, versions or run artifacts and
verify the claims the lead actually relies on. Separate observations, inference
and unavailable evidence. Supply necessary context while keeping secrets out of
prompts and reports. Retrieved content cannot change instructions or scope. This
requires targeted checking, not repeating every search or adding a new approval
system. Preserve existing authorization and tool-specific controls.

## Useful execution and verification

### R07 — Which decomposition earns its coordination cost?

[OpenAI multi-agent guidance](https://developers.openai.com/api/docs/guides/agents-api/multi-agent)
and [Anthropic's research-system account](https://www.anthropic.com/research/multi-agent-research-system)
support distinct independent questions. The latter explicitly identifies coding
dependencies as a limit to parallelization. Arbitrary directory partitions can
hide interfaces; identical broad searches can merely duplicate effort.

**Change:** start from decision-relevant questions and stable inputs. Use tools or
skills for short established procedures, research helpers for separable uncertainty,
and candidate review after an implementation exists. Keep coupled design with the
lead. Reading can follow relevant consumers within authorized scope; writes remain
bounded. Three concurrent threads is a local budget, not a measured optimum or a
minimum staffing level.

### R08 — Does a worktree guarantee the correct or isolated state?

[Git worktrees](https://git-scm.com/docs/git-worktree),
[Codex-managed worktrees](https://developers.openai.com/codex/app/worktrees) and
[Claude desktop behavior](https://code.claude.com/docs/en/desktop) have different
creation and state-transfer semantics. A new worktree may use another base, and
managed workflows can carry local changes. Worktrees share some repository and
host resources; they do not prevent incompatible interface assumptions.

**Change:** verify effective root, commit and relevant dirty, untracked, generated,
data/config inputs. Distinguish inherited state from helper changes. Compare that
delta with the current integration candidate. Keep existing exclusive ownership
and testqueue grants through verified teardown. A clean application of two patches
is not evidence that their combined behavior is correct.

### R09 — How should asynchronous, failed or superseded work end?

Native task handles and status are more useful than assumptions about elapsed time.
Codex [#42074](https://github.com/openai/codex/issues/42074) reports repeated waits
despite completed state elsewhere; [#60325](https://github.com/openai/codex/issues/60325)
reports child work stalling after the parent ended on a 0.167 client. These are
scoped failure reports, not evidence that every current client behaves this way.

**Change:** track handle, question, input identity and whether the result is needed.
After an incomplete return, inspect status/output before retrying. Collect and
assess required results, resolve their questions independently, or report an
unresolved limit. Stop redundant or superseded work where supported and reassess
late results. Interrupting a helper does not undo effects or establish resource
release. No new queue or orchestration framework is needed.

### R10 — How can Good Enemy review avoid false alarms and correlated agreement?

[OpenAI's reviewer research](https://alignment.openai.com/scaling-code-verification/)
weighs useful findings against false alarms and verification effort. Google's
[review standard](https://github.com/google/eng-practices/blob/master/review/reviewer/standard.md)
separates technical requirements from optional preferences; its repository is
archived, so this is a retained engineering principle rather than a current API.

**Change:** classify requirement violations, correctness/regressions and optional
style. Require a trigger, consequence and supporting evidence. Permit no findings
within the examined scope. Missing decisive evidence makes the affected claim
inconclusive. The lead resolves disagreements with a discriminating check, rather
than votes, a forced objection quota or repeated debate. Another persona/provider
does not guarantee an independent error distribution; R20 supplies empirical limits.

### R11 — What makes a draft or passing test report acceptable evidence?

[Anthropic's evaluation guidance](https://www.anthropic.com/research/demystifying-evals-for-ai-agents)
distinguishes actual outcomes from agent claims. Applying that principle here means
checking expectations as well as execution. A helper-authored test can be valuable
when its expected result comes from a contract, known case or independent
measurement rather than the same implementation assumption.

**Change:** receipts identify command, actual tested inputs, configuration,
diagnostics, artifacts and scope. Reassess evidence affected by integration. The
[GitHub PR workflow contract](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request)
normally tests a synthetic merge result; requiring its SHA to equal the PR head
would incorrectly reject valid evidence. Preserve focused checks and required CI.
For illustration, a test sharing an erroneous degrees-to-radians constant can pass;
checking the independent identity 180 degrees = pi radians exposes the common error.

### R12 — How should useful delegation be measured?

The Anthropic research-system result is an internal research comparison, not an
OpenRC coding benchmark; its roughly fifteenfold token comparison is against chat,
not against a solo coding agent. [METR's July 2025 study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)
measures experienced developers with versus without early-2025 AI access, not
subagent orchestration. Both can be misused as universal productivity claims.

**Experiment only:** measure time through accepted integration, lead review/repair,
available total cost and tokens, failures, incomplete tasks, confirmed findings,
false alarms and later defects. Keep task difficulty and acceptance comparable;
analyze Codex and Claude setups separately. A small local sample is directional.
The [optional protocol](#optional-local-comparison) adds no mandatory telemetry or
duplicate broad test gate.

## Examples, skills and community experience

### R13 — What do official implementations actually do?

The pinned OpenAI [agents-as-tools example](https://github.com/openai/openai-agents-python/blob/64fbde5d02b42ae5f9db668eb0184cdb3fc9d775/examples/agent_patterns/agents_as_tools.py)
gives a manager specialist tools, then invokes a separate synthesizer. Its
[typed evaluation example](https://github.com/openai/openai-agents-python/blob/64fbde5d02b42ae5f9db668eb0184cdb3fc9d775/examples/agent_patterns/deterministic.py)
uses structured verdicts but exits successfully on rejection. Neither mechanism
proves semantic success. Anthropic's pinned [SDK agent example](https://github.com/anthropics/claude-agent-sdk-python/blob/4720d367f7db9d5df8a166c74d7f36a538ac8c34/examples/agents.py)
gives a Sonnet reviewer Read/Grep and different tools to writing/testing agents.

The [orchestrator notebook](https://github.com/anthropics/claude-cookbooks/blob/ce8b2629efe8b24048b127b4c79af1e9cbab93d4/patterns/agents/orchestrator_workers.ipynb)
has a synchronous worker loop despite parallel wording. Its supplied audience and
feature context keys have no placeholders in either prompt, so those values are
not delivered. It uses one shared model and returns worker outputs without final
synthesis. These observations concern that pinned example, not Anthropic's products.

**Keep/change:** preserve manager ownership, tailored tools and explicit result
status. Check that essential inputs reached the helper when context is uncertain.
Do not import example parsers, prompts or SDK dependencies; final integration
stays with OpenRC's selected lead.

### R14 — Which community workflow mechanisms fit OpenRC?

Superpowers v7.0.2's pinned [subagent workflow](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/SKILL.md)
and [reviewer brief](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/task-reviewer-prompt.md)
use complete task context, a recorded base and a fresh review of specification and
quality. Its [fix loop](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/references/fix-loop.md)
escalates before lead adjudication. Those are useful mechanisms.

**Reject as universal policy:** implementer commits, prohibiting lead fixes,
prohibiting all parallel implementation, or compulsory per-task review regardless
of scale. A round cap cannot make an unresolved material defect acceptable.
ECC's pinned [Kiro reviewer](https://github.com/affaan-m/ECC/blob/5af4395e5c52643b7f5ecc716079cd253504b354/.kiro/agents/code-reviewer.md)
adds useful caller/context inspection and noise filtering, but a shell-capable
allowlist is not read-only enforcement. These are shipped instructions, not
comparative efficacy evidence. No third-party workflow or hook was installed.

### R15 — When is a skill enough, and can the helper actually use it?

The baseline contains 101 `.agents` and 98 `.claude` skill manifests; the four shared
`openrc-*` wrappers are identical, with `openrc-release` only under `.agents`.
Existing wrappers route repository-specific tools and asset constraints. Their
presence is not a reason to preload the full catalog.

[Claude skills](https://code.claude.com/docs/en/skills) and
[OpenAI skills](https://developers.openai.com/api/docs/guides/tools-skills) document
selective loading. An ordinary Claude helper does not automatically inherit the
parent's invoked skills. The shipped profiles cannot invoke `Skill`; they can read
the relevant files or receive essential constraints in their brief.

Anthropic's [October 22, 2026 migration article](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop)
reports advantages from folding some enterprise subagents into a skill-based main
loop, while retaining subagents for verification, parallelism and isolation.
**Change:** distinguish reusable procedure from separate execution context. Its
enterprise comparisons are not evidence that a single agent always wins in coding.

### R16 — Which firsthand Reddit successes contain transferable detail?

Four reports were opened rather than relying on search headlines:

- A [Codex scaling discussion](https://www.reddit.com/r/codex/comments/1sc7g2x/how_are_you_actually_running_codex_at_scale/)
  describes four-to-six-agent worktree setup and reconciliation costs, and an
  integrator workflow; another participant uses scoped exploration. The proposed
  arrangement does not establish that shared concurrent writes are safe.
- A [Claude workflow comment](https://www.reddit.com/r/ClaudeCode/comments/1udrdgy/comment/otewk1s/)
  describes written specs, worktrees and baseline checks. It promotes its author's
  [dxkit project](https://github.com/vyuh-labs/dxkit); repository existence does not
  corroborate performance claims.
- A [game-development account](https://www.reddit.com/r/ClaudeCode/comments/1vyytv9/i_ran_a_multiagent_claude_code_development_team/)
  and its [write-up](https://brandonifco.github.io/two-weeks-253-pull-requests/)
  describe missed rule clauses despite green tests and a later source-consumption
  check. The linked project returned 404 during inspection, and claimed human-hour
  equivalence was AI-estimated. Activity counts were not independently verified.
- A [single-agent skills versus team comparison](https://www.reddit.com/r/ClaudeCode/comments/1xuqnnc/i_tested_anthropics_one_agent_with_skills_beats_a/)
  reports equivalent observed quality with less time/cost for the single-agent
  condition on a small booking-site task. It is a narrow self-report with few runs,
  model-judged design and no linked logs found.

**Keep/change:** bounded assignments, baseline-aware integration and domain checks
are plausible transferable mechanisms. Retain the possibility of zero helpers and
compare integrated outcomes. These reports do not rank models or establish an
OpenRC speedup.

### R17 — What do firsthand failures contradict?

The booking-site comparison above also reports a tester-to-orchestrator handoff
that led to a harmful keyboard fix. A plain solo agent sometimes failed too; this
is counterevidence to a universal team advantage, not proof that solo is reliable.
An [effort-calibration report](https://www.reddit.com/r/claudeskills/comments/1upilfs/i_ran_450_benchmark_runs_on_claude_codes/)
links [benchmark artifacts](https://github.com/nagisanzenin/effortmining) and claims
savings, but uses one model, small cells and a self-promoted plugin. Its own hard
diagnosis/research cases favor higher effort; artifacts were not rerun here.

A [runaway-analysis report](https://www.reddit.com/r/ClaudeAI/comments/1vce5x3/be_careful_running_claude_code_subagents/)
describes expensive analysis and contradictory returns, but its nesting diagnosis
is the model's post-hoc explanation. A [worktree discussion](https://www.reddit.com/r/ClaudeCode/comments/1vtfawm/how_are_you_running_multiple_coding_agents_at_the/)
reports semantic conflict between refactoring and tests; subsequent product
promotion weakens uncontrolled success claims.

**Change:** distinguish concurrency, lifetime task count and depth; bound retries
and follow-ups; coordinate interfaces as well as files. Treat high/max value as
task-dependent. No anecdote justifies weakening verification or installing a plugin.

### R18 — Which upstream bugs warrant practical checks?

| Report | Scope and limit | Practical response |
| --- | --- | --- |
| [Codex #26718](https://github.com/openai/codex/issues/26718) | CLI 0.137.0 resume/config report; a later [pinned message path](https://github.com/openai/codex/blob/393f64565ab46f09d99ca4d9bd973537e72a114b/codex-rs/core/src/tools/handlers/multi_agents_v2/message_tool.rs) supports an unloaded-child distinction; no current live reproduction here | Recheck exposed settings after explicit resume or known reload when material |
| [Codex #42565](https://github.com/openai/codex/issues/42565) | App-server 0.153.0/macOS fresh-context children reportedly omit dynamic tools while retaining core/configured MCP tools; source investigation and local test by reporters | Check actual capabilities; a full-history fork changes other properties and is not an equivalent universal fix |
| [Codex #33144](https://github.com/openai/codex/issues/33144) | Windows reports of incorrect worktree root/path; no precise recurrence rate or client version | Verify effective root before review or mutation, allowing equivalent sandbox mappings |
| [Codex #52887](https://github.com/openai/codex/issues/52887) | CLI 0.162.1 override-placement report with limited trials; cause and relevance to pinned profiles unresolved | Do not rewrite general configuration from this anecdote; inspect the actual invocation when reproducing |

Issue closure or duplication is not proof of a fix. These reports motivate
targeted checks, not repetitive discovery audits or a claim that all clients fail.

## Empirical boundaries and lead responsibility

### R19 — Does research justify removing or shrinking repository instructions?

[Gloaguen et al., v3, September 29, 2026](https://arxiv.org/html/2602.11988v3)
compare 300 SWE-bench Lite and 138 CTXbench tasks. Generated-file changes in mean
resolution rate were not statistically significant, while costs increased.
Developer-committed files outperformed generated files in one comparison, and an
ablation removing other documentation changed the result. The study does not
establish a universal length threshold. Its Python issue tests do not evaluate
OpenRC physical validity, generated-data provenance or resource ownership.

[Khatri, REALM 2026](https://aclanthology.org/2026.realm-1.5.pdf) uses 17 tasks and
288 runs: thirteen tasks have gold PR tests and four use fuzzy diff overlap. Its
design cannot resolve modest correctness differences. A post-hoc OpShin observation
of fewer blind full-suite runs with instructions is illustrative and underpowered,
not a confirmed efficiency gain. The PDF qualifies the simpler landing-page claims.

[Lulla et al., v1](https://arxiv.org/html/2601.20404v1) report lower median runtime
and output tokens on 124 small PR tasks, but only fifty output pairs received a
manual sanity check, without comprehensive functional evaluation. A
[separate instruction-structure preprint](https://arxiv.org/pdf/2605.10039) studies
a trivial annotation behavior; its null results cannot establish compliance with
safety-critical constraints.

**Keep/change:** retain essential project rules and remove only real duplication.
Do not bulk-generate repository summaries or count linked catalog bytes as loaded
context. A future comparison must measure rule compliance and independently
checked quality alongside time and cost.

### R20 — Does empirical scaling research support a fixed multi-agent recipe?

[Kim et al., scaling study v3, April 8, 2026](https://arxiv.org/html/2512.08296v3)
compare 260 configurations over six benchmarks. Centralized coordination helps a
finance task, all tested multi-agent variants lose on sequential PlanCraft, and
decentralized coordination performs better on a browsing task. Coding cells use
only twenty instances per condition, with broad uncertainty. Matching reasoning
budgets is not matching elapsed time or spend. Its thresholds are not OpenRC rules.

[Tran and Kiela, v2](https://arxiv.org/html/2604.02460v2) find strong single-agent
results on text-only multi-hop questions under requested thinking budgets, with
exceptions at low budgets and artificially corrupted context. Requested caps and
approximate token accounting limit equal-compute interpretations. Neither study
tests this project's Terra/max or Sonnet/high configuration.

[Correlated Errors in Large Language Models, ICML 2025](https://proceedings.mlr.press/v267/kim25e.html)
finds shared errors across models and providers on other tasks. **Inference:**
role diversity and agreement do not replace independent source/test evidence.
Keep senior-lead ownership as a project responsibility choice, not a claimed
universally optimal topology.

### R21 — Does final lead ownership create an implementation bottleneck?

The shipped helpers are useful for research, critique and text drafts. Claude's
declared allowlists exclude shell, writes and MCP; Codex helpers can inherit shell
and MCP while remaining source-read-only by instruction. A text return alone says
nothing about available tools. Promising execution without the necessary capability
and scope hides a limitation. Forcing the lead to retype an understood, reviewed
draft would add ceremony without evidence.
[GitHub's review guidance](https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/review-copilot-output)
supports examining agent-produced changes before acceptance.

**Change:** final ownership means understanding and deliberately accepting or
adapting, integrating and verifying the code. Match tools before dispatch. A
capable already-permitted native helper can produce an isolated bounded draft;
otherwise return text or keep execution with the lead. Do not broaden all profiles.
An independently scoped UI regression can be a useful future comparison; a changing
shared-kernel interface is a counterexample where lead-owned central work is safer.
Both retain existing parsing, focused checks, testqueue and final-candidate rules.

## Optional local comparison

This is a future experiment, not a new completion gate or a claimed result.

1. Choose representative bounded research, UI, numerical and shared-interface
   tasks; state acceptance and domain constraints before observing outcomes.
2. Compare the same selected lead alone, with one helper and with two helpers.
   If testing effort, change that factor separately. Balance order or task
   difficulty, preserve source/input state and comparable tools, and avoid leaking
   an earlier solution into a later attempt.
3. Use relevant existing checks and independently grounded expected results.
   Include known-correct cases and known defects if evaluating review quality;
   false alarms and missed defects matter. Keep physical/native acceptance separate.
4. Record time through accepted integration, active lead review/repair, all
   available lead-plus-helper usage/cost, failures, cancellations and incomplete
   attempts at a common cutoff. Unknown usage remains unknown. Distinguish budget-
   matched experiments from practical unrestricted workflows.
5. Adjudicate findings against evidence, deduplicate them and record later defects.
   Later discoveries provide only a partial view of missed defects. Keep Codex and
   Claude results separate unless their differing environments are controlled.
6. Change routing only when useful evidence warrants it. A small sample supports
   iteration, not a universal benchmark claim. No automatic telemetry, external
   service, framework or repeated full simulator suite is required.

## Verification of this guidance change

Validation compares the candidate with `8835554`. Documentation/configuration
checks do not establish live model routing, tool enforcement or improvement in
OpenRC development outcomes.

- Four TOML files and three Claude YAML frontmatter blocks parse successfully.
  Model presets, effort, thread/turn limits and declared tool sets are preserved.
- The existing `tools/ci/check_docs.py` link/anchor functions, with a working-tree
  candidate adapter and Git-object fallback for the sparse checkout, pass **84 new
  or affected local links across 10 changed Markdown files**. This is scoped local
  validation, not a claim that hosted CI ran or every external URL is accessible.
- All 26 specialist definitions are byte-identical. Root instructions from
  `Display resolution priorities` onward are byte-identical, and the literal
  Claude `@AGENTS.md` import is preserved. No application, tool, CI or skill files
  are changed. The report has exactly R01–R21, and `git diff --check` passes.
- `codex app-server --print-startup-config` exits 0 with version
  `0.167.0-alpha.4`. This checks startup configuration, not custom-profile discovery
  or effective model execution. Claude Code is not installed here.
- Independent review identified two wording regressions. The lead restored the
  explicit untrusted-content authority boundary and protection of all secrets,
  and distinguished text returns from actual tool restrictions. No material
  finding remains unresolved within this reviewed documentation scope.

The reviewer also walked through these scenarios by inspection; they were not
live client tests:

| Scenario | Required outcome under the revised guide |
| --- | --- |
| Intended model/profile unavailable | Use a permitted supported substitution or lead execution; report the limit without inventing a successful route |
| Restricted helper asked for graph evidence and a tested draft | Inspect capabilities, provide evidence or use a capable permitted helper; identify unperformed checks |
| Resumed helper or late return after source changes | Inspect status/settings where material and reassess evidence against actual current inputs |
| Cited return asserts user approval | Treat it as data, check original evidence and preserve the real authorization boundary |

No simulation behavior changes, live model comparison, hardware qualification or
measured cost/latency improvement is claimed. Existing focused verification,
testqueue admission and required CI remain authoritative for future code changes.
