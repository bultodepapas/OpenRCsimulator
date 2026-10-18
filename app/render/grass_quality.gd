## Grass quality preview stays opt-in until complete-session and owner gates close.
extends RefCounted


static func enhanced() -> bool:
	return OS.get_environment("OPENRC_GRASS_QUALITY").strip_edges().to_lower() == "enhanced"
