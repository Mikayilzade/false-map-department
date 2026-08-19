extends RefCounted

func write_text(_relative_path: String, _contents: String) -> Error:
	return ERR_UNAVAILABLE

func read_text(_relative_path: String) -> Dictionary:
	return {"ok": false, "error": ERR_UNAVAILABLE, "contents": ""}

func exists(_relative_path: String) -> bool:
	return false
