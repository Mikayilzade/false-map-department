extends RefCounted

const CanonicalJson = preload("res://src/domain/canonical_json.gd")
const CoreTransactionCoordinator = preload("res://src/domain/core_transaction_coordinator.gd")

var _coordinator := CoreTransactionCoordinator.new()

func execute_edit(
		definition: Dictionary,
		state: Dictionary,
		command: Dictionary,
		receipt_by_command_id: Dictionary
) -> Dictionary:
	var command_id: String = str(command.get("command_id", ""))
	if command_id.is_empty():
		return {"ok": false, "accepted": false, "code": "command_id_required", "receipt_by_command_id": receipt_by_command_id.duplicate(true)}
	var fingerprint: String = _semantic_fingerprint(command)
	if receipt_by_command_id.has(command_id):
		var receipt: Dictionary = _dictionary(receipt_by_command_id[command_id])
		if str(receipt.get("semantic_fingerprint", "")) != fingerprint:
			return {
				"ok": false,
				"accepted": false,
				"code": "duplicate_command_id_conflict",
				"receipt_by_command_id": receipt_by_command_id.duplicate(true),
			}
		return {
			"ok": true,
			"accepted": false,
			"idempotent_replay": true,
			"code": "already_applied",
			"transaction_id": str(receipt.get("transaction_id", "")),
			"known_post_state_hash": str(receipt.get("post_state_hash", "")),
			"post_state_hash": _coordinator.state_hash(state),
			"history_entries": [],
			"state": state,
			"receipt_by_command_id": receipt_by_command_id.duplicate(true),
		}

	var result: Dictionary = _coordinator.execute_edit(definition, state, command)
	var receipts: Dictionary = receipt_by_command_id.duplicate(true)
	if result.get("accepted", false):
		receipts[command_id] = {
			"semantic_fingerprint": fingerprint,
			"transaction_id": str(result.get("transaction_id", "")),
			"post_state_hash": str(result.get("post_state_hash", "")),
		}
	result["receipt_by_command_id"] = receipts
	return result

func _semantic_fingerprint(command: Dictionary) -> String:
	var semantic: Dictionary = command.duplicate(true)
	semantic.erase("expected_pre_state_hash")
	return CanonicalJson.sha256(semantic)

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
