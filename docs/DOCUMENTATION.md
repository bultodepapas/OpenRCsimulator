# Maintain the documentation

Give each subject one home. Start at the [documentation map](README.md) and update the page a reader already uses for that task.

## Choose the right home

| What changed? | Where to write it |
| --- | --- |
| How a player or contributor does one task | The relevant guide. Give the entry point, steps, expected result and limits. Check claims against current code, accepted data and configuration. |
| Project priority, dependency or release gate | The [roadmap](../ROADMAP.md). Name the next action, the proof it needs and the work it blocks. |
| Detailed implementation or qualification work | A focused task specification under its [track](TRACKS.md). Identify owner, step IDs, affected interfaces, open work and acceptance. Link back to the roadmap for priority. |
| A consequential design choice | Open the topic from the [decisions index](DECISIONS.md) and record the selected alternative, the reason and the evidence or constraint that could justify revisiting it. |
| A repeatable lesson from an investigation | [Learnings](LEARNINGS.md#keeping-this-useful). Describe the symptom, cause and check that can catch it again. |
| A result for a particular build, host or aircraft | A dated [research record](research/README.md). Link the source identity, test inputs, method, result, limits and reproducer. Research scripts and datasets belong under [root research](../research/README.md). |
| Contents of a distributed package | Its [tagged release notes](releases/). Keep the published description tied to that package. |

## Retire a plan

1. Check each step against current source and evidence. Move unresolved work, including external acceptance, to the owning task or roadmap gate.
2. Transfer a design choice with its rationale, useful operating instructions and any unique reference, license, measurement or reproduction recipe to their respective homes.
3. Search for inbound links, anchors, paths in scripts, and instruction imports. Update active callers to their new destinations. Preserve frozen manifests and source hashes with their original snapshot identities.
4. Delete superseded prose. Git history preserves earlier revisions.

## Evidence and link checks

Use relative links to committed paths. Commit new evidence with the link to it. A path under a local cache such as `references/`, `.tools/`, `app/captures/` or `dist/` needs a documented download or regeneration recipe to work for another contributor. Generated data names its owning source and generator.

Keep a compact summary, the inputs required to reproduce it and appropriate primary evidence. Use JPEG at about quality 85 for ordinary views and lossless PNG for pixel-level comparisons, masks or measured color. Record rights and provenance. For large redistributable inputs, prefer a hash and acquisition recipe. The [large-file check](../tools/repo/check_large_files.py) checks tracked files against the project's 50 MiB allowance list and GitHub's 100 MiB limit.

Verify relative links, reference-style links, heading anchors and explicit instruction imports against a fresh checkout. Check command paths and arguments against their scripts or help. Run `git diff --check`. Software correctness, physical measurements, pilot acceptance and performance on a particular device each require their own evidence.

## Agent instruction files

The root [AGENTS.md](../AGENTS.md) contains durable shared rules. Nested instructions cover exceptions or invariants specific to that subtree. Read applicable files on the path to an edit and pass them to any helpers. The root [CLAUDE.md](../CLAUDE.md) imports `@AGENTS.md` and contains client-specific guidance. A Markdown link provides navigation only.

Put a new rule at the narrowest scope where it applies. Explain the triggering condition, required action and how to verify it. Keep commands in the [tool guide](TOOLS.md), helper routing in the [subagent guide](SUBAGENTS.md), and machine-specific preferences in local configuration. Check changes to loading or profiles in the affected client when available. Inspect the effective root, overrides, context budget and loading records if discovery is uncertain.
