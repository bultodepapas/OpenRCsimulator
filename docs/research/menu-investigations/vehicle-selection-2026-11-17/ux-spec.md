# Vehicle catalog and skin-selection specification

**Proposed behavior, 2026-11-17.** Owner and delivery steps: [UI-VS plan](../../../plans/vehicle-selection-performance.md). This is a design specification derived from the [pinned source audit](code-audit.md), not a captured or implemented interface.

## 1. What the player must understand

At every point the interface must answer: which vehicle is selected, which exact skin will be used, whether the picture matches that choice, and what the main action will start. Vehicle browsing and paint browsing should stay usable while a detailed model is being prepared.

Keep “Vehicles” as the category-neutral destination. Use the current human-readable names, family and origin, and preserve experimental/surrogate status. The existing main action remains FLY for flight activities and DRIVE for cars. A future boat adapter supplies its own activity semantics only when it exists; do not show an empty Boats destination or imply a boat can launch through the aircraft solver.

## 2. Expanded Vehicles workspace

Use more of the screen when the player opens Vehicles. Keep the current Flight page focused on preparing and starting a session; give the catalog enough width for visual scanning. Retain the still field as context under the existing opaque/translucent surface rules. Do not create a separately rendered world or viewport for every card.

At 1920×1080 and 100% text, prototype a grid with at least **four columns and three fully visible rows**, subject to readable names and the selected pane. Twelve vehicles can then be compared without scrolling; the current thirteenth sits on the next row. This is a design target to verify natively, not a measured layout. A reasonable starting composition is a compact 200–220 px navigation region, roughly 1,000–1,100 px for catalog content and a 440–500 px selected pane, using the existing scale/gutter system. Reflow to fewer columns at large text or small windows rather than shrinking labels.

| Region | Content and behavior |
| --- | --- |
| Header | Vehicles, result count, search field, compact Grid/List choice |
| Filter row | Family, origin, availability; Favorites and Recent; only meaningful current categories |
| Catalog | Static model thumbnails, name, family/origin, selected marker and status; bounded live controls/images, pooling where needed |
| Selected pane | Vehicle name, exact skin name and thumbnail, selected-vehicle detail/3D region, preview state and compatible skin strip |
| Footer/action area | Current vehicle + skin summary, FLY/DRIVE, return to Flight/setup, clear blocking reason when unavailable |

Cards do not need full specifications. Put wingspan/dimensions, propulsion, controls, supported starts, validation notes and author details in the selected pane or existing details disclosure. Avoid repeating the same warning on every row. Color indicates state in addition to words and icons; it is not the only selected/focus cue.

### Card contract

Each visible card has a fixed image region and a readable name region. Long names wrap within a bounded height and have a full tooltip/accessibility label. Use a neutral generated view of the actual model, with consistent camera framing and lighting recipe. A vehicle-card thumbnail represents its declared default appearance unless a remembered-skin thumbnail is available and explicitly identified; the selected pane always names the actual selected skin.

One checkmark/selection accent means “selected for the next session.” A distinct focus outline means “keyboard/controller focus.” Hover is a transient hint, not a change of selection. A favorite star is a separate, named control and does not also select or launch the vehicle. Avoid a large nested button hierarchy that creates ambiguous keyboard/gamepad navigation.

Empty/failed thumbnails retain layout and show a neutral family icon, not a black broken image or another vehicle. Loading a thumbnail cannot block activation of its text card. A late thumbnail result may update only the card still bound to the same source-qualified ID and revision.

## 3. Search, filters and catalog scale

Search display name, stable ID aliases, author and explicit tags from the metadata index. Case-fold for matching and preserve localized display text. Do not parse model/physics files or custom skin archives while typing. A small debounce can coalesce text queries, but the text field itself responds immediately and Enter never starts a session accidentally.

Families initially reflect the actual fleet: airplanes, helicopters, multirotors, airships and cars. Add boats through a registered family adapter later. Origin distinguishes stock and admitted user/imported content; Workshop variants are exposed only through their existing owner and capability contract. Availability distinguishes ready, preview-only, experimental and unavailable without inventing a single “validated” badge that conflates software admission with physical validation.

Default order preserves the current curated stock order, followed by stable user content order. Offer name, recently used and favorites. Search/filter/sort never silently replace the selected launch tuple. If the selection is filtered out, the selected pane remains and says “Selected vehicle is outside these filters,” with Reveal/Clear filters. Remember scroll/focus per workspace and query; use stable IDs, not list indexes.

For zero results show the query, active filter summary and Clear filters. For an empty imported library show its existing import/Creator entry action and supported capability, without implying that arbitrary files can fly immediately. A missing or incompatible remembered import remains discoverable as unavailable with its reason and an appropriate Locate/Update action supplied by the library owner.

At 100 entries, measure both native-list and pooled-card prototypes. Prefer the simpler implementation that meets latency and memory gates. If pooling is used, keep only visible rows plus a small overscan window. At 1,000 metadata entries the number of live cards and decoded thumbnails must still be related to viewport size, not total entries. No full-scene preview is built to populate the grid.

## 4. Skin identity and direct changing

The selected pane always includes an explicit line such as **Skin: Navy Blue · 4 of 13**, with a small appearance thumbnail. Show **Skin: Factory finish · 1 of 1** when there is one appearance; replace the pointless change control with descriptive text. Do not hide the existence of the selected finish merely because it cannot be changed. User-facing skin labels are proper names; surrounding controls and statuses translate.

Place a short strip of up to five visible skin cards immediately below the selected vehicle. Each has a thumbnail, name and selected marker. Activating a visible card selects it in one action; keep the camera/pose steady when geometry is compatible. Previous/Next skin controls step through the same stable order without reopening a modal. A labeled **All skins (13)** button opens the expanded gallery for large sets. The existing modal and focus/cancel behavior are the starting point, not a new interaction framework.

The gallery shows only skins compatible with that vehicle/base revision, plus explicitly unavailable entries when a saved choice cannot be restored. It has search for larger libraries, Stock/Custom filtering where useful, a persistent current-selection marker, and Create/Import actions only for supported vehicles. Use a responsive, bounded thumbnail grid; prioritize selected and visible entries, then overscan. Opening or arrowing through the gallery does not build a 3D model. Activation selects once and closes the full gallery, matching current behavior; the inline strip stays available for rapid comparison.

### Default and saved identity

Current stock defaults are not encoded uniformly. Several aircraft and cars persist an empty skin ID as their default, while the blimp has an explicit default ID. Define a canonical display identity at the UI boundary and map it to existing saved IDs/default aliases. Do not rewrite a user's appearance merely to make identifiers uniform. Keep skin preferences per vehicle, including the existing aircraft, ground and airship storage routes, until a separately tested migration is needed.

Changing away and back restores that vehicle's last accepted skin. A removed custom skin shows that it is unavailable and identifies any actual fallback; never leave its old label on a different finish. Preserve the current save-error channel. A visible successful selection is an in-memory result; a failed write must not be described as successfully saved. Keep current synchronous saves in the first slice and profile them before proposing write coalescing.

Keep persisted desired, effective selected and displayed appearance identities distinct. While an index is being bootstrapped/repaired, an unresolved saved skin is “Checking installed skin,” not proof it has been deleted. If the desired skin is unavailable after reconciliation, show its name/reason and a clearly identified factory-finish option; choosing that option is an explicit new selection. Recheck or retain the exact selected content revision through launch. Never silently launch a default under the missing skin's name.

## 5. Interaction and loading state table

The selected launch tuple and displayed preview tuple are separate. The interface exposes that distinction while work is pending.

| State/event | Selected pane and catalog | Resource/launch behavior |
| --- | --- | --- |
| Focus or hover another card | Focus cue changes; selected checkmark and skin remain | No committed selection, preference write or full preview build; optional bounded prediction can nominate future work |
| Activate vehicle B | Immediately show B's name and remembered skin | Commit latest selection; invalidate obsolete UI consumers; start eligible preview preparation |
| B preparing while A is visible | “Selected: B / Skin: …”; “Showing A · Preparing B” beside old preview, or use B's static thumbnail | Old image cannot masquerade as B; navigation and skin metadata remain active |
| Compatible cached skin selected | Name/checkmark change immediately; show short preparing status only if needed | Prepare complete material transaction; publish if still current and valid; no geometry rebuild |
| Detailed preview ready | Remove pending label after the requested tuple's first rendered draw | Keep selection unchanged; ready means displayed, not just resource-loaded |
| Preview failed | “Preview unavailable for B / Skin …”; Retry; preserve selected identity | Independent launch validation remains authoritative; no silent A launch |
| Bad/missing vehicle content | Unavailable reason and recovery action | Refuse launch through the owning adapter; keep catalog usable |
| Back/Escape in gallery without activation | Preserve selected vehicle/skin; restore originating focus and scroll | Discard queued thumbnail consumers; drain active owned work safely |
| Rapid A→B→C→A | Latest name/skin stays responsive; previous candidates never flash | Coalesce intent; no queue of all intermediate full builds |
| Fly/Drive while preview is pending | Transition feedback names the accepted vehicle, skin and activity | Proposed common contract: capture exact revisions/settings before waiting; preserve each activity's validation/recovery. Current activity routes need this explicit snapshot/feedback work |
| Locale/text scale/resize during loading | Preserve logical focus, selected IDs and status; reflow text | Old card bindings/thumbnail callbacks cannot target recycled wrong entries |
| Import revision published/removed | Mark stale entry; refresh matching metadata without losing unrelated selection | Invalidate content-keyed derivatives; in-flight work uses its immutable snapshot or is discarded |

Do not display an overall percentage derived from resource-load progress. If useful, show resource phase progress separately, then “Preparing preview” and “Displaying preview.” The existing stage-based loading-bar policy owns full launch transitions. There is no artificial minimum load time or animation that delays a cache hit.

## 6. Native input and accessibility

Use existing Screen/ScreenStack and native Button focus/activation. Tab and controller navigation visit the search/filter area, card grid, skin controls and main action in a predictable order. D-pad/arrows within a grid move logical rows/columns; reflow updates neighbors without selecting another vehicle. Materialize an offscreen focused item before transferring native focus and scrolling it into view. If filtering removes focus, choose a documented nearest visible item or the empty-state action, while preserving selection.

Enter/Accept activates only the focused control once. Escape/Back closes the topmost gallery or returns from Vehicles through existing shell behavior. Do not bind unqualified left/right keys to skins while a text field, popup or grid owns them. Provide named on-screen controls and hints for any shoulder-button shortcut; use the existing action mapping, not new global raw-key interception. Radio-axis movement must not unintentionally select or launch an aircraft.

Names exposed to accessibility and automation include vehicle, skin, availability and selected state. Provide status announcements for completion/failure without announcing every intermediate focus/prefetch. Keep focus indicators visible over the background in normal and opaque modes, preserve contrast, and use non-color selected cues. A headless assertion does not establish screen-reader or physical controller usability; inspect native behavior with supported tools/devices.

Verify EN/ES visually first and test string coverage/layout in all configured locales. Include 30–40% pseudolocalization, 100/150/200% text, long imported names, non-Latin names, missing images and repeated resize. Reduced motion removes crossfades/sweeps while preserving immediate state changes. Any optional preview fade is short and interruptible; it cannot make blocked main-thread work appear responsive or delay the final usable result.

## 7. Suggested walkthroughs for acceptance

1. A new player opens Vehicles, sees at least twelve readable cards in the 1080p prototype, selects the Corsair and identifies the selected skin without opening a second screen.
2. They choose two visible skins, then another from All skins; each choice updates exactly once, keeps focus understandable and launches with that appearance.
3. They rapidly navigate aircraft→car→blimp→aircraft while a large model is loading. The selected name, current image identity and main action remain truthful throughout.
4. They browse 100 imported metadata entries, type a query, favorite one, change a filter, and return from an activity. Search, selected state, logical focus and scroll are restored correctly.
5. A selected imported file or custom skin is removed/replaced during preparation. The UI reports the unavailable/revised content and never installs a stale candidate or claims it is ready to fly.

These walkthroughs become native acceptance cases under UI-VS-01/07/12. Their automated state counterparts belong in the existing Home, roster, livery-picker, preview-request and preference tests listed in the [benchmark protocol](benchmark-protocol.md).
