# Aircraft reference index

This index keeps evidence for the current Jensen .61 model separate from material for other aircraft. It contains source pointers and findings only; the third-party originals remain local reference files.

## Current model: Jensen Ugly Stik .61

The Jensen plan is the primary geometry reference for the current simulator model: it specifies a 60 in span and 720 in² wing area, with a .45–.61 engine range. The overall aircraft model should follow this source; the [modeling plan](../UGLY-STIK-PLAN.md) and [Jensen source notes](ugly-stik-resources.md#planos-y-documentación-del-avión) track interpretation and open measurements. The local plan and supporting files are under [`references/ugly-stik/downloads/jensen/`](../../references/ugly-stik/downloads/jensen/), with provenance and hashes in [the consolidated reference manifest](ugly-stik-resources.json).

## Owner engine photographs (visual .61 reference)

The local files [`references/.61 ENGINE NITRO OS.png`](<../../references/.61 ENGINE NITRO OS.png>) and [`references/.61 AND EXHAUST.png`](<../../references/.61 AND EXHAUST.png>) show a gold-head O.S. MAX engine and a separated silencer. [Photo brief D/F](ugly-stik-visual-photo-brief.md#fotos-ef-silenciador-montado-y-separado) records hashes, observations and limits. They inform visual anatomy; the exact commercial model and dimensions remain unverified. Originals stay ignored under `references/`.

## Planned second aircraft: Extra 300S .60

The selected reference is Great Planes GPMA0236, a 64 in nitro sport-scale Extra 300S. [Implementation plan](../EXTRA-300-PLAN.md), [family comparison](extra-300-family-research.md), [local resources and inspection](extra-300-resources.md), [download hashes](extra-300-resources.json), and [integration audit](extra-300-integration-audit.md) record the selection and its limits. Thirty-four downloads and the owner's photo remain in ignored [`references/extra-300/`](../../references/extra-300/); the [local gallery](../../references/extra-300/index.html) opens them. [Round 2](extra-300-round2.md) adds the .40 photo context, underside references, CAD inspection and a firsthand .60 build report. EX-01/EX-02 measured the plan and built a visual preview: [metrology and model report](extra-300-model-v1.md). Physics data and flight are still pending. The .40 kit, real Extra 300L/330 series and electric Extra 300 EXP are comparisons, not interchangeable source geometry or flight data.

The [twelve Godot/tooling investigations](extra-aircraft-tooling/README.md) compare CAD extraction, geometry checks, rigging, editor aids, materials, canopy rendering, propeller representation, inspection, asset loading and offline aero tools. They include improvements for the existing Stik and proposed acceptance experiments; no tool adoption or new runtime validation is implied.

## Future large-aircraft reference: Ultra Stick 120

The owner-supplied RHB/Horizon material describes Ultra Stick 120 Light/Lite configurations, with different dimensions and equipment from the Jensen .61. Keep it as a separate candidate for a future large variant and as a source for construction and CAD measurement methods. The originals are stored in [`references/ultra-stick-120/Ultrastick V3/`](../../references/ultra-stick-120/Ultrastick%20V3/). See the [package findings](ugly-stik-new-files.md), [CAD audit](ugly-stik-new-files-cad.md), [inventory and SHA-256 values](../../research/ugly-stik/new-files/inventory.json), and [structured CAD metadata](../../research/ugly-stik/new-files/metadata.json). The RHB redraw and Horizon manual remain distinct configurations pending proof of their relationship.

## Identity pending: MoJo Parts 60

[`references/mojo-60/MoJo Parts 60.dwg`](../../references/mojo-60/MoJo%20Parts%2060.dwg) is a separate owner-supplied drawing. Its available examination records only its file signature, format, size, and hash; its geometry and relationship to either the Jensen or Ultra Stick remain unknown. The filename alone does not identify the model, span, or engine class. Keep the source separate until a compatible CAD reader establishes its contents. See the [DWG audit](ugly-stik-new-files-cad.md#dwg-signatures-and-limits), [inventory](../../research/ugly-stik/new-files/inventory.json), and [metadata](../../research/ugly-stik/new-files/metadata.json).


## Planned turbine aircraft: SebArt Avanti S A200

The [Avanti S plan](../AVANTI-S-PLAN.md) selects the original 200 cm span / 222 cm length A200 with a P100-RX turbine referenced to JetCat's 2017 specification. [Family comparison](avanti-s-family-research.md), [code integration audit](avanti-s-integration-audit.md), [turbine findings](avanti-s-turbine-research.md), and [local resource inventory](avanti-s-resources.md) distinguish this version from Avanti XS, Mini, Freewing EDF and current RX-BL equipment. Originals remain ignored under [references/avanti-s/](../../references/avanti-s/); the [local gallery](../../references/avanti-s/index.html) includes assembly photographs and dimensioned turbine drawings. No complete calibrated A200 airframe plan was found. This is research and a staged implementation proposal, not an integrated or validated jet.

### Avanti S: mesa de trabajo AV-01

[Archivo por componentes y recortes](../../references/avanti-s/organized/index.html) · [dimensiones/flaps interactivos](../../references/avanti-s/organized/study-board.html) · [ficha AV-01](avanti-s-av01-metrology.md) · [mandos e instalación](avanti-s-controls-and-installation.md). Acumulado: 67 originales locales; los derivados conservan procedencia y quedan excluidos de Git. AV-01 permanece parcial hasta cerrar geometría y ejes de bisagra.

### Avanti S: primera maqueta AV-02

[Inspector Godot y evidencia](avanti-s-av02-preview.md) · [capturas y fotos grandes](../../references/avanti-s/av02/index.html) · [investigación geométrica](avanti-s-geometry-followup.md). Acumulado: 76 originales locales. El modelo es aproximado, aislado y no volable.

## Fourth aircraft: P-51D Mustang 1/4 scale, 120 cc class

The research of 2026-10-06 found no commercial ARF for 100-150 cc: that class is the 1/4-scale plans-built P-51D (Veich, Bates, FokkeRC: 2.82 m, 18-27 kg) with a DA-120 / DLE-120. The simulator model is the full-size P-51D scaled exactly 1/4 from published dimensions, the public-domain AN 01-60-3 three-view and the UIUC NAA 45-100 ordinates; CG, throws and flap angles come from the CARF 2.54 m, Hangar 9 60cc and Ziroli manuals. [Plan](../P51-PLAN.md) · [research report](p51-family-research.md) · [manifest with hashes](p51-resources.json) · [physics derivation](../../research/p51/p51-05/derivation.md). Manuals, drawings, airfoil files, engine sheets and photos stay in the ignored [`references/p51-mustang/`](../../references/p51-mustang/) (its `index.json` lists licences). The CARF, Hangar 9 and Top Flite kits are comparisons, not the selected geometry.
