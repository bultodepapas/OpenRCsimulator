# Aircraft reference index

This index keeps evidence for the current Jensen .61 model separate from material for other aircraft. It contains source pointers and findings only; the third-party originals remain local reference files.

## Current model: Jensen Ugly Stik .61

The Jensen plan is the primary geometry reference for the current simulator model: it specifies a 60 in span and 720 in² wing area, with a .45–.61 engine range. The overall aircraft model should follow this source; the [modeling plan](../UGLY-STIK-PLAN.md) and [Jensen source notes](ugly-stik-resources.md#planos-y-documentación-del-avión) track interpretation and open measurements. The local plan and supporting files are under [`references/ugly-stik/downloads/jensen/`](../../references/ugly-stik/downloads/jensen/), with provenance and hashes in [the consolidated reference manifest](ugly-stik-resources.json).

## Future large-aircraft reference: Ultra Stick 120

The owner-supplied RHB/Horizon material describes Ultra Stick 120 Light/Lite configurations, with different dimensions and equipment from the Jensen .61. Keep it as a separate candidate for a future large variant and as a source for construction and CAD measurement methods. The originals are stored in [`references/ultra-stick-120/Ultrastick V3/`](../../references/ultra-stick-120/Ultrastick%20V3/). See the [package findings](ugly-stik-new-files.md), [CAD audit](ugly-stik-new-files-cad.md), [inventory and SHA-256 values](../../research/ugly-stik/new-files/inventory.json), and [structured CAD metadata](../../research/ugly-stik/new-files/metadata.json). The RHB redraw and Horizon manual remain distinct configurations pending proof of their relationship.

## Identity pending: MoJo Parts 60

[`references/mojo-60/MoJo Parts 60.dwg`](../../references/mojo-60/MoJo%20Parts%2060.dwg) is a separate owner-supplied drawing. Its available examination records only its file signature, format, size, and hash; its geometry and relationship to either the Jensen or Ultra Stick remain unknown. The filename alone does not identify the model, span, or engine class. Keep the source separate until a compatible CAD reader establishes its contents. See the [DWG audit](ugly-stik-new-files-cad.md#dwg-signatures-and-limits), [inventory](../../research/ugly-stik/new-files/inventory.json), and [metadata](../../research/ugly-stik/new-files/metadata.json).
