extends RefCounted
## Finite admission ceilings for Aircraft Creator input (AC-01).
##
## These are engineering admission policy, not measured platform capacity: every reader applies
## them before allocating and at every expansion. A platform gate may only lower them, in a new
## policy revision. Tests exercise limit - 1, limit and limit + 1.

const POLICY_ID := "openrc-creator-limits v1"

const KIB := 1024
const MIB := 1024 * 1024

# Model sources.
const MODEL_SOURCE_BYTES := 32 * MIB
const TRIANGLES := 200000
const EXPANDED_VERTICES := 600000
const STL_ASCII_LINE_BYTES := 64 * KIB
const STL_ASCII_SOLIDS := 64

# GLB container and graph.
const GLB_JSON_BYTES := 2 * MIB
const JSON_DEPTH := 32
const JSON_VALUES := 100000
const GLB_NODES := 512
const GLB_DEPTH := 32
const GLB_MESHES := 128
const GLB_PRIMITIVES := 256
const GLB_MATERIALS := 32
const GLB_IMAGES := 16
const GLB_ACCESSORS := 2048
const GLB_BUFFER_VIEWS := 2048

# Images.
const PNG_BYTES := 16 * MIB
const PNG_SIDE_PIXELS := 4096
const PNG_AGGREGATE_PIXELS := 16777216
const PNG_CHUNKS := 4096
const PAINT_GROUPS := 9
const INFLATE_SCRATCH_BYTES := 64 * KIB

# Authoring records.
const RECORD_BYTES := 2 * MIB
const INVENTORY_ITEMS := 256
const HULL_POINTS := 128
const NAME_CHARACTERS := 120
const NOTE_CHARACTERS := 4096
const RAW_NUMBER_CHARACTERS := 256
const DRAFT_BYTES := 4 * MIB

## Largest integer a count, revision or generation field may hold: 2^53 - 1, exact in float64.
const MAX_SAFE_INTEGER := 9007199254740991

# Creator store (AC-13). Nothing is evicted, so every ceiling is final for a store root.
const STORE_QUOTA_BYTES := 4096 * MIB
const STORE_POINTER_BYTES := 4 * KIB
const STORE_INDEX_BYTES := 2 * MIB
const STORE_AIRCRAFT := 512
const STORE_DRAFTS := 512
const STORE_REVISIONS_PER_AIRCRAFT := 1000
const SOURCE_FILE_NAME_CHARACTERS := 255
