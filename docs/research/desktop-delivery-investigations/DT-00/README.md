# DT-00 — Desktop delivery investigation

2026-10-07 · Revision 1. **Complete: source/code investigation; native desktop acceptance and performance measurements remain pending.**

Supports the [Desktop Delivery Plan](../../../DESKTOP-DELIVERY-PLAN.md). Scope: first launch, fullscreen, packaging, installation and measured desktop optimization. No application code changed.

| Report | Answers |
| --- | --- |
| [01 — Launch and display](01-launch-display.md) | Current gaps, fullscreen default, recovery, DPI, automation isolation and UI ownership |
| [02 — Distribution](02-distribution.md) | Portable EXE, installer, macOS application, signing, notarization and platform evidence |
| [03 — Performance and acceptance](03-performance-acceptance.md) | Measurement protocol, Compatibility limits, budgets and release evidence |
| [Audit snapshot](audit-snapshot.json) | HEAD, inspected-file hashes, working-tree context and installed engine CLI evidence |
| [Documentation validation](validation.json) | Local links, unique step rows, registry entries and whitespace checks |

Method: read the existing export pipeline, project settings, entry route, preferences, frame logger, UI/visual investigations and primary vendor documentation. Executed only engine version/help probes and documentation checks. Export scripts and past evidence were inspected, not rerun. The shared tree contains another developer's physics work; HEAD alone does not identify that working tree.

Sources were consulted on 2026-10-07. Godot's `stable` documentation is a moving reference; implementation must verify APIs and behavior against the installed `4.7.2.stable.official.ed1daf0bf`. Vendor documentation establishes intended behavior, not a native platform test result. Reports paraphrase linked sources; no third-party assets or code were imported. Repository-authored notes retain the repository license; upstream documentation retains its own terms.
