# CR-31d package cost optimizer

`PackageOptimizer.optimize(required_unit_ids, candidates, search_limit)` is a pure helper that chooses the least-cost feasible package set covering an explicit installed-unit list. It performs no purchases and does not read or change incident, aircraft, inventory, or physics state.

Each candidate dictionary has exactly these fields:

| Field | Contract |
| --- | --- |
| `id` | Unique, non-empty string identifying the package candidate. |
| `coverage_ids` | Non-empty array of unique installed-unit IDs covered by the candidate. Every ID must appear in `required_unit_ids`. |
| `cost_cents` | Non-negative integer cents through 9,000,000,000,000,000, or `null` when the price is unknown. Floats, NaN, negatives, and larger amounts are rejected. This is the shared Catalog/Calculator/RepairPlanner amount ceiling. |
| `available` | Boolean. `false` excludes the candidate from the search. |
| `compatible` | Boolean. `false` excludes the candidate from the search. |
| `provenance` | Non-empty string naming the price/coverage source. |

`required_unit_ids` must contain unique non-empty strings. The optimizer accepts at most 64 required units and 512 candidates to bound input size and recursion depth. `search_limit` must be an integer from 1 through 1,000,000; it counts explored search states and defaults to 100,000.

A feasible answer is an exact cover: every required unit is covered once, and no selected candidates overlap. The optimizer compares summed integer-cent costs under the same 9,000,000,000,000,000-cent ceiling and breaks equal-cost ties by the lexicographically smallest sorted candidate-ID array. It returns sorted `selected_candidate_ids`, `total_cost_cents`, and selected provenance records.

Result status communicates what was established:

| Status | Meaning |
| --- | --- |
| `optimal` | The complete search proved a minimum known-cost exact cover, with no feasible exact cover containing an unknown price. |
| `unknown_cost` | A complete exact cover includes a candidate with unknown cost. Any known-cost solution is returned as provisional, with `optimality_proven` false. An unknown candidate only matters when it belongs to a complete feasible exact cover. |
| `search_limit` | The search bound stopped exploration. A known cover may be returned, but `search_complete` and `optimality_proven` are false. |
| `infeasible` | A complete search found no exact cover using available, compatible candidates. |
| `cost_out_of_range` | A complete known-cost exact cover exists, but every such cover's summed cost exceeds the shared economics amount ceiling. |
| `invalid_input` | The input violates the schema or declared bounds; `errors` explains why. |

The helper uses deterministic branch selection on the uncovered unit with the fewest remaining candidates, then exhaustively compares complete covers under the explicit node limit. It does not use unknown prices as zero and does not report completeness after the search limit is reached.

The Godot test compares small fixtures to an independent exhaustive subset oracle and covers bundle/individual overlap, unknown-price alternatives, infeasible cases, search limits, invalid values, deterministic ties, and input purity. Run it from the repository root with:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script 'res://tests/test_economy_package_optimizer.gd'
```
