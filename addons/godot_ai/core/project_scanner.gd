@tool
extends RefCounted

const SKIP_DIRS := [".godot", ".git", "addons"]
const CODE_EXTENSIONS := ["gd", "shader", "gdshader", "tscn", "tres"]
const MAX_FILE_CHARS := 6000


static func get_file_tree() -> String:
	var lines: PackedStringArray = []
	_scan_dir("res://", lines, 0)
	if lines.is_empty():
		return ""
	return "\n".join(lines)


static func read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""

	var content := file.get_as_text()
	file.close()

	if content.length() > MAX_FILE_CHARS:
		content = content.left(MAX_FILE_CHARS) + "\n# ... (truncated)"

	return content


static func find_files_by_name(query: String) -> Array:
	# returns list of res:// paths whose filename matches query (case-insensitive)
	var results: Array = []
	var query_lower := query.to_lower()
	_find_matching("res://", query_lower, results)
	return results


static func _scan_dir(path: String, lines: PackedStringArray, depth: int) -> void:
	if depth > 5:
		return

	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var name := dir.get_next()

	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue

		var full := path + name

		if dir.current_is_dir():
			if name not in SKIP_DIRS:
				lines.append("  ".repeat(depth) + name + "/")
				_scan_dir(full + "/", lines, depth + 1)
		else:
			var ext := name.get_extension()
			if ext in CODE_EXTENSIONS:
				lines.append("  ".repeat(depth) + name)

		name = dir.get_next()

	dir.list_dir_end()


static func _find_matching(path: String, query: String, results: Array) -> void:
	if results.size() >= 5:
		return

	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var name := dir.get_next()

	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue

		var full := path + name

		if dir.current_is_dir():
			if name not in SKIP_DIRS:
				_find_matching(full + "/", query, results)
		else:
			if query in name.to_lower():
				results.append(full)

		name = dir.get_next()

	dir.list_dir_end()
