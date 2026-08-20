extends RefCounted

func write_text(_relative_path: String, _contents: String) -> Error:
	return ERR_UNAVAILABLE

func read_text(_relative_path: String) -> Dictionary:
	return {"ok": false, "error": ERR_UNAVAILABLE, "contents": ""}

func exists(_relative_path: String) -> bool:
	return false

func remove_path(_relative_path: String) -> Error:
	return ERR_UNAVAILABLE

func rename_path(_from_relative_path: String, _to_relative_path: String) -> Error:
	return ERR_UNAVAILABLE
