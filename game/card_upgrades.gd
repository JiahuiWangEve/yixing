extends RefCounted
# One registry owns upgrade eligibility, target card identity and UI explanation.
# Add future upgrade entries here; workshop and manual share this API.
# Permanent card IDs encode all current upgrade metadata, so copying preserves it.
const REGISTRY = {
	"sword": {"target": "sword_plus", "description": "伤害+1"},
	"spear": {"target": "spear_plus", "description": "伤害+1"}
}
static func can_upgrade(id: String) -> bool:
	return REGISTRY.has(id)
static func upgraded_id(id: String) -> String:
	return REGISTRY[id].target if can_upgrade(id) else id
static func description(id: String) -> String:
	return REGISTRY[id].description if can_upgrade(id) else "不可强化"
static func eligible_indices(collection: Array) -> Array:
	var indices = []
	for i in collection.size():
		if can_upgrade(collection[i]): indices.append(i)
	return indices
