@tool
extends RefCounted

const MEMORY_PATH := "user://godot_ai_memory.json"
const MAX_ENTRIES := 50

var _entries: Array = []


func load_memory() -> void:
	if not FileAccess.file_exists(MEMORY_PATH):
		_entries = []
		return

	var file := FileAccess.open(MEMORY_PATH, FileAccess.READ)
	if not file:
		_entries = []
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.get_data()
		if data is Array:
			_entries = data
	file.close()


func save_memory() -> void:
	var file := FileAccess.open(MEMORY_PATH, FileAccess.WRITE)
	if not file:
		push_error("Godot AI: could not write memory.json")
		return
	file.store_string(JSON.stringify(_entries, "\t"))
	file.close()


func add_entry(text: String) -> void:
	var entry := text.strip_edges()
	if entry.is_empty():
		return
	if entry in _entries:
		return
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	save_memory()


func remove_entry(index: int) -> void:
	if index >= 0 and index < _entries.size():
		_entries.remove_at(index)
		save_memory()


func clear() -> void:
	_entries.clear()
	save_memory()


func get_entries() -> Array:
	return _entries.duplicate()


func is_empty() -> bool:
	return _entries.is_empty()


func build_prompt_block() -> String:
	if _entries.is_empty():
		return ""
	var lines := "\n".join(_entries.map(func(e): return "- " + e))
	return "### Project memory\n%s" % lines
