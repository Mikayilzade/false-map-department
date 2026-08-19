extends "res://src/platform/storage_adapter.gd"

const ROOT := "user://false_map_department"

func write_text(relative_path: String, contents: String) -> Error:
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return dir_error
	var file := FileAccess.open(ROOT.path_join(relative_path), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	file.close()
	return OK

func read_text(relative_path: String) -> Dictionary:
	var path := ROOT.path_join(relative_path)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND, "contents": ""}
	return {"ok": true, "error": OK, "contents": FileAccess.get_file_as_string(path)}

func exists(relative_path: String) -> bool:
	return FileAccess.file_exists(ROOT.path_join(relative_path))
