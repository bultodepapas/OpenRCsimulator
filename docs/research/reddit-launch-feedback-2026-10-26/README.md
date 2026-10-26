# Reddit launch feedback — 2026-10-26

[Deep analysis and constructive recommendations](insights.md) · [Counts, scores and complete coding ledger](coding.md) · [Current capabilities](current-capabilities.md) · [Original transcript](comments.md)

This collection preserves and analyzes the first-public-release discussion. Original comments remain unchanged in the transcript; interpretations, descriptive counts and current-source comparisons live in separate linked documents. The [original Reddit post](https://www.reddit.com/r/RCPlanes/comments/1x8iee8/) is a historical feedback source, not an authority for current implementation status.

## Coverage

| Item | Retrieved |
| --- | ---: |
| Unique comments | 169 |
| Top-level comments / replies | 50 / 119 |
| Distinct author handles, including OP | 68 |
| OP comments / other participants' comments | 54 / 115 |
| Reddit's advertised comment count | 170 |
| Unexpanded `more` placeholders | 0 |

**The one-comment discrepancy remains unresolved.** Every comment returned by the listing is preserved, but this cannot establish recovery of all comments ever posted. No retrieved comment has a deleted/removed body. See [source and coverage](comments.md#source-and-coverage) for acquisition, timestamp, ordering and transcription limits. The [specific comment supplied by the user](comments.md#comment-19rjlwu08zdr8) is included.

## Read the findings

- [Insights](insights.md): repeated needs, highest-scoring comments, twelve constructive findings, counterevidence and a proposed sequence of small outcomes with acceptance evidence.
- [Coding](coding.md): every archived comment, 115 manually annotated community comments, topic recurrence by distinct handle, explicit-request families, net scores and exposure distinctions. OP replies are retained as context and excluded from community demand counts.
- [Current capabilities](current-capabilities.md): source-backed distinctions between existing features, discoverability/qualification gaps and missing user-facing functionality. This review did not run the application or qualify hardware.
- [Transcript](comments.md): original post, all retrieved comment bodies, authors, timestamps, scores, parent links and media URLs. No local images or videos were added.

## Reproduce and review the counts

[Method, annotation inputs and generator](../../../research/reddit-launch-feedback/README.md). Run:

```sh
python3 research/reddit-launch-feedback/analyze.py --check
```

The generator checks unique IDs, complete community annotation coverage, label validity and exact agreement between the annotations and generated tables. It does not establish that a subjective label is correct; review a row against its source comment and amend the annotation when necessary.

The analysis uses the archived scores, not a live vote refresh. Counts describe this self-selected thread, not the market. The original 169 bodies and parent links were checked during collection; analytical links and generated tables were checked after this analysis. No runtime behavior, physics data, roadmap status or public replies were changed.
