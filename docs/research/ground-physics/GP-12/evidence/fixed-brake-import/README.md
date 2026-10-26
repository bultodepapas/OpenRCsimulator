# GP-12: numerical CSV import mode

2026-10-26 followup to the fixed-brake input cohort. Normal Godot import first
treated the two numerical CSV fixtures as translations, producing two warnings.
The same cold-cache pass generated a missing Japanese font and encountered ten
asset MD5 diagnostics. The rejected complete report is retained separately.

The two fixture `.csv.import` files now declare `remap/importer="keep"`, the
engine's supported raw-file mode. This follows the [official import guide](https://docs.godotengine.org/en/4.5/tutorials/assets_pipeline/import_process.html)
and the exact pinned [4d10419ca importer implementation](https://github.com/godotengine/godot/blob/4d10419ca/editor/file_system/editor_file_system.cpp#L618).
No CSV bytes, physics, input roles or expected output hashes changed.

The subsequent full-project standard import completed with zero engine errors
and warnings. A separate disposable Git autocrlf clone containing both raw CSVs,
their import settings and a minimal project also imported cleanly from an empty
cache: all four fixture/configuration files stayed byte-identical and no
translation files were generated. This is a cold fixture-import check, not a
whole-application fresh-clone qualification or a full test-suite result.

The normal import regenerated defaults for three embedded landscape textures.
Their pre-import authored UID/compression/mipmap settings were restored with
source/commit guards and retained records; no landscape source was changed.
The next import honored them. Newly generated script UID companions are normal
Godot metadata for the new scripts, not simulation state.

`manifest.json` binds the selected sources, rejected/passing receipts and
construction records. Original fixed-brake evidence remains unchanged.
