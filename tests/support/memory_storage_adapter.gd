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

func remove_path(relative_path: String) -> Error:
	if not _files.has(relative_path):
		return ERR_FILE_NOT_FOUND
	_files.erase(relative_path)
	return OK

func rename_path(from_relative_path: String, to_relative_path: String) -> Error:
	if not _files.has(from_relative_path):
		return ERR_FILE_NOT_FOUND
	_files[to_relative_path] = _files[from_relative_path]
	_files.erase(from_relative_path)
	return OK

func overwrite_for_test(relative_path: String, contents: String) -> void:
	_files[relative_path] = contents
