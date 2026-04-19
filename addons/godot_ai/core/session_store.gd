@tool
extends RefCounted

const INDEX_PATH := "user://godot_ai_sessions.json"
const SESSION_DIR := "user://"
const MAX_SESSIONS := 20


func save_session(id: String, messages: Array, total_chars: int) -> void:
	var title := "New chat"
	for msg in messages:
		if msg.get("role", "") == "user":
			var t: String = msg.get("text", "").strip_edges()
			if not t.is_empty():
				title = t.substr(0, 40) + ("…" if t.length() > 40 else "")
			break

	var path := SESSION_DIR + "godot_ai_session_%s.json" % id
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({"messages": messages, "total_chars": total_chars}))
	file.close()

	var index := _load_index()
	index = index.filter(func(e): return e.get("id", "") != id)
	index.append({"id": id, "title": title, "updated_at": Time.get_unix_time_from_system()})
	index.sort_custom(func(a, b): return a["updated_at"] > b["updated_at"])
	while index.size() > MAX_SESSIONS:
		var oldest: Dictionary = index.pop_back()
		var old_path := SESSION_DIR + "godot_ai_session_%s.json" % oldest.get("id", "")
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	_save_index(index)


func load_session(id: String) -> Dictionary:
	var path := SESSION_DIR + "godot_ai_session_%s.json" % id
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var data = json.get_data()
	return data if data is Dictionary else {}


func list_sessions() -> Array:
	var index := _load_index()
	index.sort_custom(func(a, b): return a["updated_at"] > b["updated_at"])
	return index


func delete_session(id: String) -> void:
	var path := SESSION_DIR + "godot_ai_session_%s.json" % id
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var index := _load_index()
	index = index.filter(func(e): return e.get("id", "") != id)
	_save_index(index)


func generate_id() -> String:
	return str(Time.get_unix_time_from_system())


func _load_index() -> Array:
	if not FileAccess.file_exists(INDEX_PATH):
		return []
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if not file:
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return []
	file.close()
	var data = json.get_data()
	return data if data is Array else []


func _save_index(index: Array) -> void:
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(index))
	file.close()
