# T02 — Virtualized cards and recycled thumbnail bindings

**Decision:** require bounded live controls/images for the 1,000-entry case in UI-VS-07. **Researched:** 2026-11-17. [Twenty-investigation index](README.md).

## Question and search vocabulary

How can a large catalog show many vehicles while its layout and image work depend on the visible window?

Queries used: `site:docs.unity3d.com UI Toolkit ListView recycle visual elements virtualizationMethod fixed height` and `site:learn.microsoft.com WPF optimizing performance controls UI virtualization recycling data virtualization`. The important distinction is **UI virtualization** versus **data virtualization**, followed by **container recycling**, **overscan**, and **binding lifetime**.

## Primary evidence and transfer limits

[Unity 6000.0 ListView](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/UIElements.ListView.html) documents creating visible elements and rebinding recycled ones. [Microsoft's WPF control-performance guide](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/optimizing-performance-controls) separates UI virtualization from retaining the underlying dataset and warns about state incorrectly attached to recycled containers. Both were accessed on 2026-11-17. Their APIs are examples of established UI mechanisms, not Godot features.

The current [LiveryPicker](../../../../../app/ui/livery_picker.gd#L58-L136) creates a button/image hierarchy for every choice, then eventually loads its available thumbnails. Loading one image per frame reduces a burst but does not limit the number retained or the cost of an unusually large image.

## Application to OpenRC

Maintain an ordered array of catalog IDs separately from a fixed pool of native Godot card controls. For a four-column layout showing three rows, one overscan row on each side produces a 20-card pool. That arithmetic is an illustrative layout, not a universal pool size; recompute from actual viewport, text scale and card dimensions.

Each binding receives vehicle ID, revision, thumbnail key and binding generation. An asynchronous image completion must match all four before assignment. Unbinding clears image references, selection styling, names, tooltips and any per-item signal state. Do not accumulate another pressed callback each time a control is reused.

Keep selected ID, focused ID and scroll anchor in the view model. A controller move to an offscreen row first materializes the row, then transfers native focus. Search, sort, deletion and language changes preserve the logical target where possible; otherwise choose a deterministic nearby item. Accessible names must describe the new bound item immediately.

Schedule images by visibility and selected state. Count unique image bytes and reserve decode/upload work through the common admission policy. Overscan is a prediction allowance, not permission to decode all 1,000 thumbnails. Stock thumbnails should have bounded dimensions; imported images must use admitted derivatives rather than arbitrary source-resolution pictures.

Compare a simpler native implementation first. If it meets the 100-entry target but materializes the entire 1,000-entry collection, it has not met the agreed scale gate. Do not assume GridContainer or ItemList virtualizes its children automatically.

## Counterexample and risks

An aggressively small pool can oscillate on scroll boundaries and repeatedly reload textures. Excessive overscan defeats the memory benefit. Fixed heights simplify offsets, but localized multi-line labels and 200% text can invalidate a fixed-pixel assumption. Compute the row metric for the current layout and invalidate it on reflow; never clip necessary information to preserve a benchmark.

## Experiment and decision gate

Compare full creation, bounded rows, and bounded rows with one-row overscan on identical 13/100/1,000-entry datasets. Measure live controls, texture references/bytes, layout CPU, input-to-drawn-focus latency, filter-to-usable-result latency and scroll frame intervals. Run repeated down/up movement, search while images finish, resize, localization and controller focus restoration.

Accept only if pool size remains tied to the viewport, late images never decorate another vehicle, and native navigation stays correct. Reject a faster layout that loses focus or shows stale skins. Do not count synthetic descriptors as proof of full-model memory behavior.

**Plan impact:** add binding-generation and recycled-state checks to UI-VS-07 and the existing picker/layout tests; reuse T01's metadata snapshot and T12's byte reservations.
