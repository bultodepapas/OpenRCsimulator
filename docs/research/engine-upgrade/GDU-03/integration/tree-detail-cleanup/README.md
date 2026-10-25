# GDU-03 field-tree test cleanup

The positive unit result retained an unexplained ObjectDB leak alongside its intentional invalid-bark-option warning. Reproducing `test_field_tree_detail.gd` with `--verbose` identifies one leaked `Node3D` and orphan name `treelineDetail`.

The test's missing-runway-direction assertion called `FieldTreeDetail.build(..., NAN).get_child_count()` inline. The builder returns a caller-owned empty `Node3D`; the test discarded that node without freeing it. The test now retains this fixture, makes the same zero-child assertion, and frees it. No runtime builder, assertion or diagnostic suppression changed.

The focused verbose rerun exits normally with **zero errors**, **no leaked instances or orphan names**, and exactly the original intentional `bark_lod_error_px` warning. All existing assertions pass. The original verbose run also emitted a cleanup `get_path` error while reporting the orphan, which is absent after cleanup. [Verification](verification.json) retains both checked-runner reports and complete verbose logs, engine/source identities and the remaining expected warning. User data was isolated; the shared frozen suite was not modified.
