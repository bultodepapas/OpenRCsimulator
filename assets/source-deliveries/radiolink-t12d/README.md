# Radiolink T12D transmitter (owner model)

The owner's Blender model of a Radiolink T12D, supplied on 2026-10-24 as a **draft**. The final model will replace these files in place under the same names. Bytes are kept as delivered.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `Radiolink_T12D.blend` | 901,807 | `8bae3db01812fb6bf6ff2b36696ba80e7fa5db261ff83c399db0330e83f530c6` |
| `Radiolink_T12D.glb` | 3,458,880 | `eecd1e5887ad395092f199d8565d826ad7f6baa16ca7976c4473597de5f8496e` |

The model is in metres: 174 mm wide, 207 mm tall including the antenna, face toward −Y. It has 140 named parts under `T12D_root` with separate gimbals, sticks, switches, knobs, handle and screen. The source has 42k triangles before modifiers; the `.glb` export has 156k.

The field pilots use the `.blend` through [generate_people.py](../../../tools/scenery/population/generate_people.py) (`import_transmitter`). The recipe needs `T12D_root`, `Stick_Izq_eje` and `Stick_Der_eje`. Keep these names in the final model; the hold is derived from the stick positions. Intake record, reduction and hold: [HUMAN_SOURCES.json](../../scenery/population/HUMAN_SOURCES.json) (`sc_hum_01_transmitter`). Evidence: [SC-HUM-01](../../../docs/research/scenery-implementation/SC-HUM-01/README.md).

Licence: authored by the owner for this project; redistribution terms are to be confirmed.
