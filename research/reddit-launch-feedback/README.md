# Reddit launch-feedback analysis inputs

Evidence home: [2026-10-26 launch feedback](../../docs/research/reddit-launch-feedback-2026-10-26/README.md). This is a documentation-only investigation; it creates no runtime feature or new implementation track.

- `annotations.tsv` contains one reviewed row for each of the 115 non-OP comments. IDs join to the archived Markdown transcript; author, time and score are read from that source rather than copied into a second dataset.
- `analyze.py` uses the Python standard library to validate coverage and generate the dated [coding report](../../docs/research/reddit-launch-feedback-2026-10-26/coding.md), including all 169 records. The 54 OP comments appear as context and are excluded from community recurrence and score totals.

From the repository root:

```sh
python3 research/reddit-launch-feedback/analyze.py
python3 research/reddit-launch-feedback/analyze.py --check
```

No network request, package installation or runtime execution is needed. Change the retained annotations when a reading judgment changes, then regenerate the report and reconcile any figures quoted in `insights.md`. `--check` checks mechanical consistency, not interpretation quality.

## Annotation rules

`kind` records the main conversational role; mixed comments can carry several `themes` and `requests`. Theme names and request-family definitions are in the generator. `note` records the interpretation and meaningful limits; these are analyst words, not direct quotations.

- **Themes:** tag substantive discussion, including disagreement and technical questions; a theme does not mean demand or support. `SUPPORT` means an explicit encouraging/positive element, not the overall sentiment of a person or comment. `COLLABORATION` includes technical exchanges with other developers, not only concrete offers to join.
- **Requests:** tag an explicit proposal, compatibility/availability question or clear endorsement of a parent's proposal. Do not infer requests from OP promises, unrelated tutorials, or a commenter describing their existing mobile simulator. A grouped family can contain different desired implementations; the individual note preserves that distinction.
- **Exposure:** `firsthand` requires an explicit description of playing/testing OpenRC; `video` indicates footage-based judgment; `website` is a site/link experience; `other_product` covers another simulator/tool or real-world comparison. `unknown` is not a claim that the person never tried OpenRC. Exposure describes the comment, not every activity in the author's life.
- **Counting:** count distinct handles within each family; repeated comments from one handle increase comment count but not requester count. Allow multi-label overlap; never sum row totals into audience size. A vote belongs to its entire comment and is not allocated among its features.
- **OP context:** read replies to understand availability claims, clarification and commitments, but do not turn the developer's own roadmap promises into community demand. The source review separately checks selected current capabilities.

The [analysis](../../docs/research/reddit-launch-feedback-2026-10-26/insights.md) documents sample, score, exposure and source limitations. This coding is descriptive manual analysis, not a representative survey, formal sentiment classifier, independent technical validation or proof of a defect.
