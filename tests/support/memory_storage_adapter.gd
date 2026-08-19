extends "res://src/platform/storage_adapter.gd"

var _files: Dictionary = {}

func write_text(relative_path: String, contents: String) -> Error:
	_files[relative_path] = contents
	return OK

func read_text(relative_path: String) -> Dictionary:
	if not _files.has(relative_path):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND, "contents": ""}
	return {"ok": true, "error": OK, "contents": str(_files[relative_path])}

func exists(relative_path: String) -> bool:
	return _files.has(relative_path)

func overwrite_for_test(relative_path: String, contents: String) -> void:
	_files[relative_path] = contents
